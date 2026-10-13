#!/bin/bash
# Node-side wrapper around the official runtime-api-configs CLI (OpenHands/extensions, pinned by sha256).
# Runs on the Replicated VM via SSM as root. Never prints credentials or config environment values.
#
#   warm-config.sh precheck <image-ref>          read-only gates; exits nonzero if any gate fails
#   warm-config.sh save     <image-ref> <count>  template v1_current -> save DEMO_NAME (additive)
#   warm-config.sh delete                        remove DEMO_NAME (rollback); refuses anything else
#   warm-config.sh snapshot                      non-secret view of all configs + warm pods
#
# Only DEMO_NAME can be written or deleted. An existing DEMO_NAME must prove demo ownership
# (source=db and an image under DEMO_IMAGE_REPO), otherwise every mutation aborts.
# Expects $CLI (path to warm_runtime_configs.py) and $WORK (private temp dir); ssm-run.sh provides both.
set -u
DEMO_NAME="prepared-monorepo"
DEMO_IMAGE_REPO="ghcr.io/rajistics-demo/prepared-monorepo-sandbox"
# Disk model inputs (bytes). Defaults come from CI measurements of the current image; see env/rajistics/README.md.
NEW_COMPRESSED="${NEW_COMPRESSED:-1072481526}"   # compressed layers not shared with the 1.50.1 base
NEW_UNPACKED="${NEW_UNPACKED:-2997473430}"       # prepared unpacked (6242167574) minus base unpacked (3244694144)
PER_SANDBOX="${PER_SANDBOX:-5671178776}"         # inner Docker peak (cold 4671178776) + 1 GB task/checkout/logs
SANDBOXES="${SANDBOXES:-3}"                      # warm + work + verify coexisting
MARGIN_PCT="${MARGIN_PCT:-25}"
DISK_MAX_PCT="${DISK_MAX_PCT:-70}"               # conservative cap on projected use; not relaxed without live evidence
MODE="${1:-}"; shift || true
umask 077
mkdir -p "$WORK/bin"
printf '#!/bin/sh\nexec k0s kubectl "$@"\n' > "$WORK/bin/kubectl"; chmod 700 "$WORK/bin/kubectl"
export PATH="$WORK/bin:$PATH"

# Error bodies can echo request input (e.g. a 422 with config environment values): print the status only.
errcode() { grep -oE 'HTTP [0-9]{3}|Could not connect' "$1" | head -1; }

# Credentials only ever live in this process's environment. bootstrap's stdout holds them; its stderr holds
# only CLI/kubectl error text (redacted anyway). An empty admin-password Secret means admin is disabled.
creds() {
  local out
  if ! out="$(python3 "$CLI" bootstrap --namespace openhands 2>"$WORK/boot.err")"; then
    echo "GATE runtime-api admin access: FAIL ($(sed -E 's/[A-Za-z0-9+\/=_-]{24,}/<redacted>/g' "$WORK/boot.err" | head -1))"
    local url; url="https://$(kubectl -n openhands get ingress -l app.kubernetes.io/name=runtime-api -o jsonpath='{.items[0].spec.rules[0].host}')"
    echo "runtime-api GET /api/admin/challenge -> $(curl -s -o "$WORK/ch.json" -w '%{http_code}' "$url/api/admin/challenge") $(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("error",""))' "$WORK/ch.json" 2>/dev/null)"
    # Reads still work with the read-only default key; mutations stay blocked.
    export RUNTIME_API_URL="$url"
    API_KEY="$(kubectl -n openhands get secret default-api-key -o jsonpath='{.data.default-api-key}' | base64 -d)"; export API_KEY
    return 2
  fi
  eval "$out"; unset out
  [ -n "${RUNTIME_API_URL:-}" ] && [ -n "${API_KEY:-}" ] && [ -n "${ADMIN_PASSWORD:-}" ] \
    || { echo "GATE runtime-api admin access: FAIL (missing credentials)"; return 2; }
  echo "GATE runtime-api admin access: ok"
}

list_json() { python3 "$CLI" list 2>"$WORK/list.err" > "$WORK/list.json" || { echo "FAIL list: $(errcode "$WORK/list.err")"; return 2; }; }

snapshot() {
  list_json || return 2
  python3 -c '
import hashlib, json, sys
out = []
for c in json.load(open(sys.argv[1])):
    env = c.get("environment") or {}
    out.append({k: c.get(k) for k in ("name","source","image","count","working_dir","command","run_as_user","run_as_group","fs_group")}
               | {"env_names": sorted(env),
                  "sha256_full_config": hashlib.sha256(json.dumps(c, sort_keys=True).encode()).hexdigest()})
print(json.dumps(out, indent=1))
' "$WORK/list.json" || return 2
  echo "== warm pods (no session_id)"
  kubectl -n openhands get deploy -l 'runtime_id,!session_id' \
    -o jsonpath='{range .items[*]}{.metadata.name} {.spec.template.spec.containers[0].image} ready={.status.readyReplicas}{"\n"}{end}'
}

anon_pull_ok() {  # $1 = ghcr.io/<owner>/<pkg>@sha256:...
  python3 - "$1" <<'PY'
import json, sys, urllib.request
ref = sys.argv[1]
host, rest = ref.split("/", 1)
repo, digest = rest.split("@", 1)
tok = json.load(urllib.request.urlopen(f"https://{host}/token?scope=repository:{repo}:pull&service={host}", timeout=20)).get("token", "")
req = urllib.request.Request(f"https://{host}/v2/{repo}/manifests/{digest}", method="HEAD", headers={
    "Authorization": f"Bearer {tok}",
    "Accept": "application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json"})
print(urllib.request.urlopen(req, timeout=20).status)
PY
}

disk_gate() {
  # kubelet config keys; unset means kubelet defaults (imageGCHighThresholdPercent=85, evictionHard nodefs.available<10%, imagefs.available<15%)
  local cfg=/run/k0s/kubelet/config.yaml
  echo "kubelet_gc_eviction_keys: $(grep -E 'imageGCHigh|imageGCLow|evictionHard|nodefs|imagefs' "$cfg" 2>/dev/null | tr -s ' ' | tr '\n' ';' || true)"
  python3 - "$NEW_COMPRESSED" "$NEW_UNPACKED" "$PER_SANDBOX" "$SANDBOXES" "$MARGIN_PCT" "$DISK_MAX_PCT" "$cfg" <<'PY'
import os, re, sys
nc, nu, ps, n, margin, cap = (int(x) for x in sys.argv[1:7])
txt = open(sys.argv[7]).read() if os.path.exists(sys.argv[7]) else ""
def num(key, default):
    m = re.search(rf"^\s*{key}:\s*(\d+)", txt, re.M); return int(m.group(1)) if m else default
gc_high = num("imageGCHighThresholdPercent", 85)
st = os.statvfs("/")
size, free = st.f_blocks * st.f_frsize, st.f_bavail * st.f_frsize
used = size - free
incr = (nc + nu + n * ps) * (100 + margin) // 100
proj = (used + incr) * 100 / size
limit = min(gc_high, 100 - 15, cap)   # stay under image GC, imagefs hard eviction (15% free), and the cap
print(f"disk_size={size} used={used} free={free} used_pct={used*100/size:.1f}")
print(f"gc_high_pct={gc_high} hard_eviction_free_pct=15 cap_pct={cap} limit_pct={limit}")
print(f"incremental_peak_est={incr} (new_compressed={nc} + new_unpacked={nu} + {n}x per_sandbox={ps}, +{margin}% margin)")
print(f"projected_used_pct={proj:.1f}")
print("GATE disk:", "ok" if proj < limit else "FAIL")
sys.exit(0 if proj < limit else 1)
PY
}

ownership() {  # requires $WORK/list.json; prints new|owned, or fails on collisions
  python3 - "$WORK/list.json" "$DEMO_NAME" "$DEMO_IMAGE_REPO" "${1:-}" <<'PY'
import json, sys
cfgs, name, repo, image = json.load(open(sys.argv[1])), sys.argv[2], sys.argv[3], sys.argv[4]
if not any(c.get("name") == "v1_current" for c in cfgs): print("GATE v1_current present: FAIL"); sys.exit(1)
if image:
    other = [c["name"] for c in cfgs if c.get("image") == image and c.get("name") != name]
    if other: print("GATE image ref unique: FAIL, used by", other); sys.exit(1)
same = [c for c in cfgs if c.get("name") == name]
if not same: print("GATE ownership: ok (new)"); print("STATE new"); sys.exit(0)
c = same[0]
if c.get("source") == "db" and str(c.get("image", "")).startswith(repo + "@"):
    print("GATE ownership: ok (existing demo-owned)"); print("STATE owned"); sys.exit(0)
print(f"GATE ownership: FAIL, {name} exists with source={c.get('source')} image={c.get('image')}"); sys.exit(1)
PY
}

precheck() {  # $1 image; returns nonzero if any gate fails
  local fail=0
  case "$1" in "$DEMO_IMAGE_REPO"@sha256:*) echo "GATE digest-pinned demo image: ok";; *) echo "GATE digest-pinned demo image: FAIL"; fail=1;; esac
  disk_gate || fail=1
  if code=$(anon_pull_ok "$1" 2>/dev/null) && [ "$code" = 200 ]; then echo "GATE anonymous pull: ok"
  else echo "GATE anonymous pull: FAIL (only runtime pull secret is the Replicated proxy secret 'openhands-registry')"; fail=1; fi
  creds || fail=1
  list_json && ownership "$1" || fail=1
  return $fail
}

case "$MODE" in
  precheck|"") ;;
  snapshot) creds >/dev/null || true ;;
  *) creds || { echo "ABORT: no runtime-api admin access, nothing changed"; exit 2; } ;;
esac

case "$MODE" in
  snapshot) snapshot; exit $? ;;
  precheck)
    precheck "${1:?image}"; rc=$?; echo "precheck_exit=$rc"; exit $rc ;;
  save)
    IMAGE="${1:?image}"; COUNT="${2:?count}"
    [ "$COUNT" -ge 0 ] 2>/dev/null && [ "$COUNT" -le 1 ] || { echo "FAIL count must be 0 or 1"; exit 1; }
    precheck "$IMAGE" || { echo "ABORT: precheck failed, nothing saved"; exit 1; }
    echo "== before"; snapshot || { echo "ABORT: before snapshot failed, nothing saved"; exit 1; }
    ownership "$IMAGE" >/dev/null || { echo "ABORT: ownership changed since precheck"; exit 1; }
    python3 "$CLI" template v1_current --image "$IMAGE" --count "$COUNT" --output "$WORK/cfg.json" 2>"$WORK/t.err" \
      || { echo "FAIL template: $(errcode "$WORK/t.err")"; exit 2; }
    python3 "$CLI" save "$DEMO_NAME" --file "$WORK/cfg.json" >"$WORK/s.out" 2>&1; rc=$?
    shred -u "$WORK/cfg.json" 2>/dev/null || rm -f "$WORK/cfg.json"
    grep '^Saved ' "$WORK/s.out" || { echo "FAIL save rc=$rc $(errcode "$WORK/s.out")"; exit 2; }
    sleep 5; echo "== after"; snapshot ;;
  delete)
    echo "== before"; snapshot || { echo "ABORT: before snapshot failed, nothing deleted"; exit 1; }
    state=$(ownership "" | sed -n 's/^STATE //p'); [ "$state" = owned ] || { echo "ABORT: $DEMO_NAME is not a demo-owned config (state=${state:-collision})"; exit 1; }
    python3 "$CLI" delete "$DEMO_NAME" >"$WORK/d.out" 2>&1 || { echo "FAIL delete $(errcode "$WORK/d.out")"; exit 2; }
    echo "deleted $DEMO_NAME"
    sleep 5; echo "== after"; snapshot ;;
  *) echo "usage: warm-config.sh precheck <image>|save <image> <count>|delete|snapshot"; exit 1 ;;
esac
