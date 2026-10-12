#!/usr/bin/env bash
# Time-to-first-meaningful-test inside one sandbox (run as the sandbox user).
#
#   bench-ttfmt.sh <mode: cold|prepared> <base-sha> <test-file-on-disk> <repo-relative-test-path> <out.json>
#
# Clock starts before prepare-workspace and stops when the regression test has
# produced a classified result at base (expected ASSERTION_RED). The test file
# is supplied on disk so no git fetch of the test commit is inside the window;
# that stands in for the agent having written the test.
set -uo pipefail
mode="$1" base="$2" test_src="$3" test_rel="$4" out="$5"
task_root="${OH_BENCH_TASK_ROOT:-/tmp/oh-bench-$mode}"
export AUTH_MODE="${AUTH_MODE:-none}"

t0=$(date +%s.%N)
prepare-workspace --sha "$base" --mode "$mode" --run-id "bench-$mode" --task-root "$task_root" \
  > "/tmp/prep-$mode.json" 2> "/tmp/prep-$mode.err"
prep_rc=$?
t1=$(date +%s.%N)
task="$(readlink -f "$task_root/current" 2>/dev/null || true)"
red_rc=99
if [ "$prep_rc" -eq 0 ] && [ -n "$task" ]; then
  install -D -m 0644 "$test_src" "$task/repo/$test_rel"
  oh-phase red --tests "${test_rel#server/}" --task "$task" > "/tmp/red-$mode.txt" 2>&1
  red_rc=$?
fi
t2=$(date +%s.%N)

python3 - "$mode" "$prep_rc" "$red_rc" "$t0" "$t1" "$t2" "$task" "$out" <<'EOF'
import json, sys
from pathlib import Path
mode, prep_rc, red_rc, t0, t1, t2, task, out = sys.argv[1:]
t0, t1, t2 = float(t0), float(t1), float(t2)
state, red = {}, {}
if task:
    sp = Path(task) / "state" / "prepare.json"
    rp = Path(task) / "evidence" / "red.json"
    state = json.loads(sp.read_text()) if sp.exists() else {}
    red = json.loads(rp.read_text()) if rp.exists() else {}
rec = {
    "mode": mode, "prepare_exit": int(prep_rc), "red_exit": int(red_rc),
    "prepare_seconds": round(t1 - t0, 3), "first_test_seconds": round(t2 - t1, 3),
    "ttfmt_seconds": round(t2 - t0, 3),
    "red_classification": red.get("classification"), "red_ok": red.get("ok"),
    "red_counts": red.get("counts"), "head_sha": red.get("head_sha"),
    "prepare_state": state.get("state"), "phase_seconds": state.get("phases"),
    "facts": state.get("facts"), "cache_misses": state.get("cache_misses"),
    "valid": int(prep_rc) == 0 and red.get("classification") == "ASSERTION_RED" and bool(red.get("ok")),
}
Path(out).write_text(json.dumps(rec, indent=2) + "\n")
print(json.dumps({k: rec[k] for k in ("mode", "valid", "prepare_seconds", "first_test_seconds", "ttfmt_seconds",
                                       "red_classification", "cache_misses")}))
EOF
