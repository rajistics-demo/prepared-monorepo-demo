#!/usr/bin/env bash
# Assemble build/context/ for the `prepared` image target. CI only.
#
#   SEED_SHA=<main commit> TOOLCHAIN_IMAGE=... EVENTS_SVC_IMAGE=... FIXTURES_DIR=... \
#     [GITHUB_TOKEN=...] env/scripts/assemble-context.sh
#
# Produces
#   build/context/seed/repo.git   bare clone of main + demo/* tags only (no reference/* branches),
#                                 origin set to the plain https URL, no credentials anywhere
#   build/context/images/*.tar    docker save of the three PostgreSQL images (by digest) and events-svc
#   build/context/fixtures/       output of env/fixtures/build.sh
#   build/context/lock.json       describes everything above plus the bundle key
set -euo pipefail

: "${SEED_SHA:?}" "${TOOLCHAIN_IMAGE:?}" "${EVENTS_SVC_IMAGE:?}" "${FIXTURES_DIR:?}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
REPO_URL="${REPO_URL:-https://github.com/rajistics-demo/prepared-monorepo-demo.git}"
CTX="$REPO/build/context"
rm -rf "$CTX"
mkdir -p "$CTX/images" "$CTX/seed"

# --- seed -----------------------------------------------------------------
auth=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
  # Passed on the command line only; never written to the seed's config.
  basic="$(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 | tr -d '\n')"
  auth=(-c "http.https://github.com/.extraheader=AUTHORIZATION: basic $basic")
fi
git "${auth[@]}" clone --quiet --bare --no-tags --single-branch --branch main "$REPO_URL" "$CTX/seed/repo.git"
git "${auth[@]}" -C "$CTX/seed/repo.git" fetch --quiet origin '+refs/tags/demo/*:refs/tags/demo/*'
git -C "$CTX/seed/repo.git" remote set-url origin "$REPO_URL"
git -C "$CTX/seed/repo.git" cat-file -e "${SEED_SHA}^{commit}"
test "$(git -C "$CTX/seed/repo.git" rev-parse refs/heads/main)" = "$SEED_SHA" || {
  echo "main moved past SEED_SHA; rebuild from the new main" >&2; exit 1; }
rm -rf "$CTX/seed/repo.git/hooks"
git -C "$CTX/seed/repo.git" repack -adq
if grep -Eiq 'extraheader|authorization|token' "$CTX/seed/repo.git/config"; then
  echo "credential material found in seed config" >&2; exit 1
fi
if git -C "$CTX/seed/repo.git" for-each-ref --format='%(refname)' | grep -v -E '^refs/(heads/main|tags/demo/)'; then
  echo "unexpected refs in seed" >&2; exit 1
fi

# --- service images -----------------------------------------------------------
save() { # name source_ref tag
  local name="$1" src="$2" tag="$3"
  docker image inspect "$src" >/dev/null 2>&1 || docker pull --quiet --platform linux/amd64 "$src" >/dev/null
  docker tag "$src" "$tag"
  docker save --platform linux/amd64 -o "$CTX/images/$name.tar" "$tag" 2>/dev/null || docker save -o "$CTX/images/$name.tar" "$tag"
}
images_json="{}"
for name in pg14 pg16 pg17; do
  ref="$(python3 -c "import json,sys;p=json.load(open('$REPO/env/pins.json'))['services']['$name'];print(p['ref']+'@'+p['index_digest'])")"
  ver="$(python3 -c "import json;print(json.load(open('$REPO/env/pins.json'))['services']['$name']['ref'].split(':')[1])")"
  save "$name" "$ref" "prepared-monorepo/postgres:$ver"
done
save events-svc "$EVENTS_SVC_IMAGE" "prepared-monorepo/events-svc:${SEED_SHA:0:12}"

# --- fixtures -------------------------------------------------------------------
cp -a "$FIXTURES_DIR" "$CTX/fixtures"

# --- bundle key from the toolchain image ---------------------------------------
docker run --rm --entrypoint /bin/sh "$TOOLCHAIN_IMAGE" -c \
  'cat "/opt/prepared/bundle/$(readlink /opt/prepared/bundle/current).key.json"' > "$CTX/bundle-key.json"

# --- lock.json --------------------------------------------------------------------
python3 - "$REPO" "$CTX" "$SEED_SHA" "$EVENTS_SVC_IMAGE" <<'PY'
import hashlib, json, os, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path
repo, ctx, seed_sha, events_src = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], sys.argv[4]
pins = json.loads((repo / "env/pins.json").read_text())
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def image_id(ref): return subprocess.run(["docker", "image", "inspect", "--format", "{{.Id}}", ref], capture_output=True, text=True, check=True).stdout.strip()
images = {}
for name in ("pg14", "pg16", "pg17"):
    p = pins["services"][name]
    tag = f"prepared-monorepo/postgres:{p['ref'].split(':')[1]}"
    images[name] = {"file": f"{name}.tar", "tag": tag, "source_ref": p["ref"], "source_index_digest": p["index_digest"],
                    "source_linux_amd64_digest": p["linux_amd64_digest"], "image_id": image_id(tag)}
tag = f"prepared-monorepo/events-svc:{seed_sha[:12]}"
images["events-svc"] = {"file": "events-svc.tar", "tag": tag, "source_ref": "built in CI from services/events-svc at seed sha",
                        "image_id": image_id(tag)}
for v in images.values():
    f = ctx / "images" / v["file"]
    v["tar_sha256"], v["tar_bytes"] = sha(f), f.stat().st_size
manifest = json.loads((ctx / "fixtures/manifest.json").read_text())
seed_refs = subprocess.run(["git", "-C", str(ctx / "seed/repo.git"), "for-each-ref", "--format=%(refname) %(objectname)"],
                           capture_output=True, text=True, check=True).stdout.split("\n")
lock = {
    "schema": 1,
    "built_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "build": {"repo": os.environ.get("GITHUB_REPOSITORY"), "commit": os.environ.get("GITHUB_SHA"),
              "run_id": os.environ.get("GITHUB_RUN_ID"), "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT")},
    "base": pins["agent_server_base"],
    "ruby": pins["ruby"],
    "pins_sha256": sha(repo / "env/pins.json"),
    "seed": {"sha": seed_sha, "refs": [r for r in seed_refs if r]},
    "bundle": json.loads((ctx / "bundle-key.json").read_text()),
    "fixtures": {"manifest_sha256": sha(ctx / "fixtures/manifest.json"),
                 "keys": {k: v["key"] for k, v in manifest["dbs"].items()}},
    "images": images,
    "auth_mode": "none (synthetic demo; AWS SSO and private ECR are NOT exercised)",
}
(ctx / "lock.json").write_text(json.dumps(lock, indent=2, sort_keys=True) + "\n")
(ctx / "bundle-key.json").unlink()
print(json.dumps({"seed": seed_sha, "bundle_key": lock["bundle"]["key"][:16],
                  "images": {k: v["tar_bytes"] for k, v in images.items()}}, indent=1))
PY
du -sh "$CTX"/* | sed 's/^/context: /'
