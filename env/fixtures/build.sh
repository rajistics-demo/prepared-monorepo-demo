#!/usr/bin/env bash
# Build keyed database fixtures for the prepared image. Runs on a CI runner,
# never on the Rajistics node.
#
#   TOOLCHAIN_IMAGE=<toolchain image> EVENTS_SVC_IMAGE=<events-svc image> \
#     env/fixtures/build.sh <out-dir>
#
# 1. Starts pg14/pg16/pg17 + events-svc from server/compose.yaml in a private
#    Compose project with image-default PostgreSQL settings.
# 2. Runs `bin/rails dev:bootstrap` (AUTH_MODE=none) inside the toolchain image,
#    so the fixtures come from the same Ruby and bundle that ship.
# 3. Dumps every database with pg_dump -Fc *inside its own server container*
#    (dump tool major == server major).
# 4. Writes manifest.json with the fixture key, file checksums, row counts,
#    encoding/collation and extensions per database.
# Synthetic seed data only; no live or production data is involved.
set -euo pipefail

OUT="${1:?usage: build.sh <out-dir>}"
: "${TOOLCHAIN_IMAGE:?set TOOLCHAIN_IMAGE}"
: "${EVENTS_SVC_IMAGE:?set EVENTS_SVC_IMAGE}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT="fx-$(date +%s)-$$"
WORK="$(mktemp -d)"
mkdir -p "$OUT"

free_port() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])'; }
export PG14_PORT="$(free_port)" PG16_PORT="$(free_port)" PG17_PORT="$(free_port)" EVENTS_SVC_PORT="$(free_port)"
export EVENTS_SVC_IMAGE
COMPOSE=(docker compose -p "$PROJECT" -f "$REPO/server/compose.yaml")

cleanup() {
  "${COMPOSE[@]}" down -v --remove-orphans --timeout 10 >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

"${COMPOSE[@]}" up -d --wait --wait-timeout 120 pg14 pg16 pg17
"${COMPOSE[@]}" up -d --wait --wait-timeout 120 --no-build events-svc

# Writable copy of the repo for Rails tmp/ and log/; the bundle stays read-only in the image.
cp -a "$REPO/." "$WORK/repo"
docker run --rm --network host --user root --entrypoint /bin/bash \
  -e AUTH_MODE=none -e BOOTSTRAP_ENVS=development,test \
  -e PG14_PORT -e PG16_PORT -e PG17_PORT -e EVENTS_SVC_PORT \
  -e BUNDLE_FROZEN=true -e BUNDLE_APP_CONFIG=/tmp/bundle-config -e BUNDLE_USER_HOME=/tmp/bundle-home \
  -v "$WORK/repo:/src" -w /src/server "$TOOLCHAIN_IMAGE" \
  -c 'set -euo pipefail
      key="$(python3 /opt/prepared/bin/keys.py bundle --repo /src)"
      test -d "/opt/prepared/bundle/$key" || { echo "bundle key $key not in toolchain image" >&2; exit 1; }
      export BUNDLE_PATH="/opt/prepared/bundle/$key"
      bin/rails dev:bootstrap
      cat tmp/bootstrap-state.json'

declare -A SERVICE=([primary]=pg16 [ledger]=pg14 [events]=pg17)
declare -A DBS=(
  [primary]="server_primary_development server_primary_test"
  [ledger]="server_ledger_development server_ledger_test"
  [events]="server_events_development server_events_test"
)
ROWS_SQL="SELECT table_name || '=' || (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', table_schema, table_name), false, true, '')))[1]::text FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE' ORDER BY table_name"
FACTS_SQL="SELECT pg_encoding_to_char(encoding) || '|' || datcollate || '|' || datctype FROM pg_database WHERE datname = current_database()"
EXT_SQL="SELECT extname || '=' || extversion FROM pg_extension ORDER BY extname"

MANIFEST_PARTS="$WORK/parts"
mkdir -p "$MANIFEST_PARTS"
for logical in primary ledger events; do
  svc="${SERVICE[$logical]}"
  mkdir -p "$OUT/$logical"
  python3 "$REPO/env/keys/keys.py" fixture --repo "$REPO" --db "$logical" --json > "$MANIFEST_PARTS/$logical.key.json"
  server_version="$("${COMPOSE[@]}" exec -T "$svc" psql -X -U postgres -Atc 'SHOW server_version')"
  for db in ${DBS[$logical]}; do
    "${COMPOSE[@]}" exec -T "$svc" pg_dump -U postgres -Fc --no-owner -d "$db" > "$OUT/$logical/$db.dump"
    "${COMPOSE[@]}" exec -T "$svc" psql -X -U postgres -d "$db" -Atc "$ROWS_SQL" > "$MANIFEST_PARTS/$db.rows"
    "${COMPOSE[@]}" exec -T "$svc" psql -X -U postgres -d "$db" -Atc "$FACTS_SQL" > "$MANIFEST_PARTS/$db.facts"
    "${COMPOSE[@]}" exec -T "$svc" psql -X -U postgres -d "$db" -Atc "$EXT_SQL" > "$MANIFEST_PARTS/$db.ext"
  done
  echo "$server_version" > "$MANIFEST_PARTS/$logical.server_version"
done

python3 - "$OUT" "$MANIFEST_PARTS" <<'PY'
import hashlib, json, sys
from pathlib import Path
out, parts = Path(sys.argv[1]), Path(sys.argv[2])
dbs = {"primary": ["server_primary_development", "server_primary_test"],
       "ledger": ["server_ledger_development", "server_ledger_test"],
       "events": ["server_events_development", "server_events_test"]}
manifest = {"fixture_format_version": 1, "method": "pg_dump -Fc in the matching server container; restore with pg_restore --no-owner --exit-on-error into fresh per-run volumes", "dbs": {}}
for logical, names in dbs.items():
    key = json.loads((parts / f"{logical}.key.json").read_text())
    entries = []
    for name in names:
        dump = out / logical / f"{name}.dump"
        rows = dict(l.split("=", 1) for l in (parts / f"{name}.rows").read_text().split("\n") if l.strip())
        enc, coll, ctype = (parts / f"{name}.facts").read_text().strip().split("|")
        entries.append({"name": name, "file": dump.name, "bytes": dump.stat().st_size,
                        "sha256": hashlib.sha256(dump.read_bytes()).hexdigest(), "row_counts": rows,
                        "encoding": enc, "collate": coll, "ctype": ctype,
                        "extensions": [l for l in (parts / f"{name}.ext").read_text().split("\n") if l.strip()]})
    manifest["dbs"][logical] = {"key": key["key"], "key_inputs": key["inputs"],
                                "server_version": (parts / f"{logical}.server_version").read_text().strip(),
                                "databases": entries}
(out / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
print(json.dumps({k: {"key": v["key"][:16], "dbs": {d["name"]: d["row_counts"] for d in v["databases"]}} for k, v in manifest["dbs"].items()}, indent=1))
PY
