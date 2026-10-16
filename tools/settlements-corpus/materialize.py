#!/usr/bin/env python3
"""Materialize the settlement corpus into a checkout with streaming verification (stdlib only).

  materialize.py [--dest DIR] [--only 2025-03-14,...] [--only-from-tests server/test]
                 [--budget-root /workspace --budget-bytes N] [--min-node-free-bytes N]
                 [--report out.json] [--verify-only]

Inputs are the committed server/data/settlements/manifest.json and corpus.lock.json
at the checked-out commit. The lock pins the manifest's sha256 and each release
asset's size and sha256; the manifest pins every file's size and sha256.

Each needed shard is fetched over HTTPS and piped straight through gzip and tar
into the destination: no archive or partial expanded copy is retained. Every file
is written to a hidden .part name, checked against the manifest, then renamed and
made read-only. When the stream ends, the asset hash must match the lock. On any
mismatch, the files written from that shard in this run are deleted and the run
fails (exit 4).

Budget gates (exit 3, nothing written past the gate):
  --budget-root/--budget-bytes  allocated bytes already under the root plus the bytes
      this run will add must stay within the budget. This is the demo's own ceiling,
      because the sandbox PVC request is not enforced on this cluster.
  --min-node-free-bytes  free bytes on the destination filesystem must stay above
      this floor after the planned write. Re-checked after every file, so the run
      aborts and removes its partial file before the node approaches disk pressure.

Exit codes: 0 ok, 2 usage/manifest pin error, 3 budget gate, 4 verification failure,
5 network failure after retries.
"""
import argparse
import hashlib
import json
import os
import re
import sys
import tarfile
import time
import urllib.request
from pathlib import Path

CHUNK = 1 << 20
DATE_RE = re.compile(r"\b(20(?:24|25)-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01]))\b")


class Gate(Exception):
    code = 3


class Verify(Exception):
    code = 4


class Net(Exception):
    code = 5


def now():
    return time.monotonic()


def allocated(root: Path) -> int:
    total = 0
    for dirpath, dirnames, filenames in os.walk(root, onerror=lambda e: None):
        for name in filenames + dirnames:
            try:
                total += os.lstat(os.path.join(dirpath, name)).st_blocks * 512
            except OSError:
                pass
    return total


def node_free(path: Path) -> int:
    st = os.statvfs(path)
    return st.f_bavail * st.f_frsize


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(CHUNK), b""):
            h.update(chunk)
    return h.hexdigest()


class HashingReader:
    def __init__(self, resp):
        self.resp, self.h, self.n = resp, hashlib.sha256(), 0

    def read(self, size=-1):
        b = self.resp.read(size if size and size > 0 else CHUNK)
        self.h.update(b)
        self.n += len(b)
        return b


def load(manifest_path: Path, lock_path: Path):
    mbytes = manifest_path.read_bytes()
    lock = json.loads(lock_path.read_text())
    if hashlib.sha256(mbytes).hexdigest() != lock["manifest_sha256"]:
        print("FAIL manifest sha256 does not match corpus.lock.json", file=sys.stderr)
        sys.exit(2)
    manifest = json.loads(mbytes)
    return manifest, lock


def wanted_days(args, manifest):
    all_days = [f["settled_on"] for f in manifest["files"]]
    picked = set()
    if args.only:
        picked |= set(args.only.split(","))
    if args.only_from_tests:
        for p in Path(args.only_from_tests).rglob("*.rb"):
            picked |= set(DATE_RE.findall(p.read_text(errors="ignore")))
    if not args.only and not args.only_from_tests:
        return set(all_days)
    picked &= set(all_days)
    return picked


def present_ok(path: Path, entry, deep: bool) -> bool:
    try:
        if path.stat().st_size != entry["bytes"]:
            return False
    except FileNotFoundError:
        return False
    return sha256_file(path) == entry["sha256"] if deep else True


def fetch_shard(asset, entries_by_path, need, dest: Path, floor: int, report):
    """Stream one asset into dest. Returns list of written paths. Raises on failure (after rollback)."""
    written = []
    t0 = now()
    req = urllib.request.Request(asset["url"], headers={"User-Agent": "settlements-corpus-materialize/1"})
    try:
        resp = urllib.request.urlopen(req, timeout=120)
    except Exception as e:  # noqa: BLE001
        raise Net(f"{asset['name']}: {e}") from e
    first_byte = now() - t0
    reader = HashingReader(resp)
    try:
        with tarfile.open(fileobj=reader, mode="r|gz") as tar:
            for m in tar:
                entry = entries_by_path.get(m.name)
                if entry is None or not m.isreg() or m.name.startswith("/") or ".." in m.name.split("/"):
                    raise Verify(f"{asset['name']}: unexpected member {m.name!r}")
                if m.name not in need:
                    continue
                if m.size != entry["bytes"]:
                    raise Verify(f"{m.name}: tar size {m.size} != manifest {entry['bytes']}")
                final = dest / m.name
                final.parent.mkdir(parents=True, exist_ok=True)
                part = final.with_name("." + final.name + ".part")
                h = hashlib.sha256()
                src = tar.extractfile(m)
                with open(part, "wb") as out:
                    for chunk in iter(lambda: src.read(CHUNK), b""):
                        h.update(chunk)
                        out.write(chunk)
                if h.hexdigest() != entry["sha256"]:
                    part.unlink(missing_ok=True)
                    raise Verify(f"{m.name}: sha256 mismatch")
                if final.exists():
                    final.chmod(0o644)
                os.replace(part, final)
                final.chmod(0o444)
                written.append(final)
                if node_free(dest) < floor:
                    raise Gate(f"node free space fell below floor {floor} after {m.name}")
        while reader.read(CHUNK):
            pass
        if reader.n != asset["bytes"] or reader.h.hexdigest() != asset["sha256"]:
            raise Verify(f"{asset['name']}: asset bytes/sha256 do not match corpus.lock.json")
    except BaseException:
        for p in written:
            p.chmod(0o644)
            p.unlink(missing_ok=True)
        for p in dest.rglob(".*.part"):
            p.unlink(missing_ok=True)
        raise
    finally:
        resp.close()
    report["shards"].append({"name": asset["name"], "shard": asset["shard"], "compressed_bytes": reader.n,
                             "files_written": len(written), "bytes_written": sum(p.stat().st_size for p in written),
                             "first_byte_seconds": round(first_byte, 3), "seconds": round(now() - t0, 3)})
    return written


def du_pair(root: Path):
    logical = alloc = files = 0
    for p in root.rglob("*.csv"):
        st = p.stat()
        logical += st.st_size
        alloc += st.st_blocks * 512
        files += 1
    return {"files": files, "logical_bytes": logical, "allocated_bytes": alloc}


def main():
    here = Path(__file__).resolve().parents[2]
    ap = argparse.ArgumentParser()
    ap.add_argument("--dest", default=str(here / "server/data/settlements"))
    ap.add_argument("--manifest", default=str(here / "server/data/settlements/manifest.json"))
    ap.add_argument("--lock", default=str(here / "server/data/settlements/corpus.lock.json"))
    ap.add_argument("--only", help="comma-separated settlement days")
    ap.add_argument("--only-from-tests", help="materialize only days referenced by *.rb files under this dir")
    ap.add_argument("--budget-root")
    ap.add_argument("--budget-bytes", type=int)
    ap.add_argument("--min-node-free-bytes", type=int, default=60 * 10**9)
    ap.add_argument("--report")
    ap.add_argument("--verify-only", action="store_true", help="re-hash present files; download nothing")
    ap.add_argument("--retries", type=int, default=2)
    args = ap.parse_args()
    if bool(args.budget_root) != bool(args.budget_bytes):
        ap.error("--budget-root and --budget-bytes go together")

    dest = Path(args.dest)
    dest.mkdir(parents=True, exist_ok=True)
    manifest, lock = load(Path(args.manifest), Path(args.lock))
    entries_by_path = {f["path"]: f for f in manifest["files"]}
    days = wanted_days(args, manifest)
    report = {"schema": manifest["schema"], "manifest_sha256": lock["manifest_sha256"], "dest": str(dest),
              "days_requested": len(days), "shards": [], "started_unix": time.time()}
    t0 = now()
    try:
        needed = {f["path"] for f in manifest["files"] if f["settled_on"] in days}
        if args.verify_only:
            bad = [p for p in sorted(needed) if not present_ok(dest / p, entries_by_path[p], deep=True)]
            report["verify_only"] = {"checked": len(needed), "bad": bad[:20], "bad_count": len(bad)}
            if bad:
                raise Verify(f"{len(bad)} file(s) missing or not matching the manifest, first {bad[0]}")
        else:
            missing = {p for p in needed if not present_ok(dest / p, entries_by_path[p], deep=False)}
            planned = sum(entries_by_path[p]["bytes"] for p in missing)
            planned_alloc = sum(-(-entries_by_path[p]["bytes"] // 4096) * 4096 for p in missing)
            free = node_free(dest)
            report["gates"] = {"planned_bytes": planned, "planned_allocated_bytes": planned_alloc,
                               "node_free_before": free, "node_floor": args.min_node_free_bytes}
            if free - planned_alloc < args.min_node_free_bytes:
                raise Gate(f"node free {free} - planned {planned_alloc} < floor {args.min_node_free_bytes}")
            if args.budget_root:
                used = allocated(Path(args.budget_root))
                report["gates"] |= {"budget_root": args.budget_root, "budget_bytes": args.budget_bytes,
                                    "budget_used_before": used}
                if used + planned_alloc > args.budget_bytes:
                    raise Gate(f"budget: used {used} + planned {planned_alloc} > {args.budget_bytes}")
            for asset in lock["assets"]:
                need = {p for p in missing if asset["first_day"] <= entries_by_path[p]["settled_on"] <= asset["last_day"]}
                if not need:
                    continue
                for attempt in range(args.retries + 1):
                    try:
                        fetch_shard(asset, entries_by_path, need, dest, args.min_node_free_bytes, report)
                        break
                    except Net as e:
                        if attempt == args.retries:
                            raise
                        print(f"retry {attempt + 1} after network error: {e}", file=sys.stderr)
                        time.sleep(5 * (attempt + 1))
            still = [p for p in needed if not present_ok(dest / p, entries_by_path[p], deep=False)]
            if still:
                raise Verify(f"{len(still)} needed file(s) absent after materialization, first {still[0]}")
            report["node_free_after"] = node_free(dest)
            if args.budget_root:
                report["budget_used_after"] = allocated(Path(args.budget_root))
        report["status"] = "OK"
        rc = 0
    except (Gate, Verify, Net) as e:
        report["status"], report["error"] = type(e).__name__.upper(), str(e)
        print(f"FAIL {report['status']}: {e}", file=sys.stderr)
        rc = e.code
    report["seconds"] = round(now() - t0, 3)
    report["dest_csv"] = du_pair(dest)
    report["compressed_bytes_fetched"] = sum(s["compressed_bytes"] for s in report["shards"])
    if args.report:
        Path(args.report).parent.mkdir(parents=True, exist_ok=True)
        Path(args.report).write_text(json.dumps(report, indent=1) + "\n")
    print(json.dumps({k: report[k] for k in ("status", "seconds", "days_requested", "dest_csv",
                                             "compressed_bytes_fetched") if k in report}))
    return rc


if __name__ == "__main__":
    sys.exit(main())
