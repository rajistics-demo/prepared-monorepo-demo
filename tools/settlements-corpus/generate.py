#!/usr/bin/env python3
"""Deterministic synthetic payment-processor settlement corpus (stdlib only).

One CSV per settlement day, 2024-01-01..2025-12-31, laid out as
server/data/settlements/YYYY/MM/settlements-YYYY-MM-DD.csv. All content is
derived from SCHEMA and the date; there is no wall-clock or host input.

  generate.py shard --shard K --of 8 --out shard-K.tar.gz --manifest-out shard-K.json
      Stream shard K's days into a reproducible tar.gz (no expanded files on disk).
  generate.py day --date 2025-03-14 --out file.csv
      Write one day (used by CI determinism checks).
  generate.py assemble --release-tag T --repo OWNER/NAME --out-dir DIR shard-*.json
      Merge shard manifests into manifest.json and corpus.lock.json.

Shards are calendar quarters (8 for two years). Day sizes follow integer
weekday/month weights scaled to DATA_TARGET_BYTES, so the total is fixed by
construction; each file stops at the last full row that fits its target.
"""
import argparse
import gzip
import hashlib
import io
import json
import sys
import tarfile
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

SCHEMA = "settlements-v1"
START = date(2024, 1, 1)
END = date(2025, 12, 31)
DATA_TARGET_BYTES = 9_597_000_000
SHARDS = 8
HEADER = ("batch_id,processor_ref,account_id,policy_ref,txn_type,card_brand,card_last4,auth_code,"
          "amount_cents,fee_cents,net_cents,currency,captured_at,settled_on,descriptor\n")
WEEKDAY_W = (112, 106, 104, 103, 108, 86, 81)  # Mon..Sun
MONTH_W = (104, 103, 102, 100, 98, 97, 96, 97, 98, 100, 102, 103)
BRANDS = ("visa",) * 11 + ("mastercard",) * 6 + ("amex",) * 2 + ("discover",)
ACCOUNTS = 60_000
ROWS_PER_BATCH = 2_500
REFUND_THRESHOLD = 2_294  # of 65536, about 3.5% of rows are refunds


def days(start=START, end=END):
    d = start
    while d <= end:
        yield d
        d += timedelta(days=1)


def weight(d: date) -> int:
    return WEEKDAY_W[d.weekday()] * MONTH_W[d.month - 1]


TOTAL_WEIGHT = sum(weight(d) for d in days())


def target_bytes(d: date) -> int:
    return DATA_TARGET_BYTES * weight(d) // TOTAL_WEIGHT


def rel_path(d: date) -> str:
    return f"{d:%Y}/{d:%m}/settlements-{d.isoformat()}.csv"


class Rng:
    """xorshift64* seeded from sha256(SCHEMA:date); fixed across Python versions."""

    def __init__(self, d: date):
        self.s = int.from_bytes(hashlib.sha256(f"{SCHEMA}:{d.isoformat()}".encode()).digest()[:8], "big") or 1

    def next(self) -> int:
        s = self.s
        s ^= (s >> 12)
        s ^= (s << 25) & 0xFFFFFFFFFFFFFFFF
        s ^= (s >> 27)
        self.s = s
        return (s * 0x2545F4914F6CDD1D) & 0xFFFFFFFFFFFFFFFF

    def below(self, n: int) -> int:
        return (self.next() >> 16) % n


def generate_day(d: date):
    """Return (bytes, stats) for one settlement day."""
    rng = Rng(d)
    limit = target_bytes(d)
    out = [HEADER]
    size = len(HEADER)
    stats = {"rows": 0, "charges": 0, "refunds": 0, "charge_cents": 0, "refund_cents": 0, "fee_cents": 0}
    midnight = datetime(d.year, d.month, d.day, tzinfo=timezone.utc)
    ymd = f"{d:%Y%m%d}"
    settled = d.isoformat()
    i = 0
    while True:
        account = 1 + rng.below(ACCOUNTS)
        refund = (rng.next() >> 48) < REFUND_THRESHOLD
        amount = 4_500 + rng.below(37_501)
        lag = 1 + (2 if d.weekday() == 0 and rng.below(3) == 0 else 0)
        captured = midnight - timedelta(days=lag) + timedelta(seconds=rng.below(86_400))
        if refund:
            amount = 500 + rng.below(amount - 499)
            fee, net, kind, ref, desc = 0, -amount, "refund", f"re_{ymd}{i:07d}{rng.below(1 << 24):06x}", "SYNTHINS*REFUND"
        else:
            fee = (amount * 29 + 500) // 1000 + 30
            net, kind, ref, desc = amount - fee, "charge", f"ch_{ymd}{i:07d}{rng.below(1 << 24):06x}", "SYNTHINS*PREMIUM"
        line = (f"B{ymd}-{i // ROWS_PER_BATCH:03d},{ref},{account},POL-{account:06d}-{account * 7919 % 97:02d},{kind},"
                f"{BRANDS[rng.below(len(BRANDS))]},{rng.below(10_000):04d},{rng.below(1 << 24):06X},"
                f"{amount},{fee},{net},USD,{captured:%Y-%m-%dT%H:%M:%SZ},{settled},{desc}\n")
        if size + len(line) > limit:
            break
        out.append(line)
        size += len(line)
        i += 1
        stats["rows"] += 1
        stats["fee_cents"] += fee
        if refund:
            stats["refunds"] += 1
            stats["refund_cents"] += amount
        else:
            stats["charges"] += 1
            stats["charge_cents"] += amount
    data = "".join(out).encode("ascii")
    assert len(data) == size
    stats["ledger_net_cents"] = stats["charge_cents"] - stats["refund_cents"]
    return data, stats


def shard_days(k: int):
    year, quarter = START.year + (k - 1) // 4, (k - 1) % 4
    first = date(year, 3 * quarter + 1, 1)
    last = date(year + 1, 1, 1) - timedelta(days=1) if quarter == 3 else date(year, 3 * quarter + 4, 1) - timedelta(days=1)
    return list(days(first, last))


class _HashWriter(io.RawIOBase):
    def __init__(self, f):
        self.f, self.h, self.n = f, hashlib.sha256(), 0

    def writable(self):
        return True

    def write(self, b):
        self.h.update(b)
        self.n += len(b)
        return self.f.write(b)


def cmd_shard(a):
    entries = []
    raw = 0
    with open(a.out, "wb") as f:
        hw = _HashWriter(f)
        with gzip.GzipFile(filename="", mode="wb", fileobj=hw, compresslevel=a.level, mtime=0) as gz:
            with tarfile.open(fileobj=gz, mode="w|", format=tarfile.USTAR_FORMAT) as tar:
                for d in shard_days(a.shard):
                    data, stats = generate_day(d)
                    info = tarfile.TarInfo(rel_path(d))
                    info.size, info.mtime, info.mode, info.uid, info.gid = len(data), 0, 0o444, 0, 0
                    info.uname = info.gname = ""
                    tar.addfile(info, io.BytesIO(data))
                    raw += len(data)
                    entries.append({"path": rel_path(d), "settled_on": d.isoformat(), "bytes": len(data),
                                    "sha256": hashlib.sha256(data).hexdigest(), **stats})
                    print(f"{d} {len(data)} rows={stats['rows']}", file=sys.stderr)
    name = Path(a.out).name
    doc = {"schema": SCHEMA, "shard": a.shard, "files": entries,
           "asset": {"name": name, "bytes": hw.n, "sha256": hw.h.hexdigest(), "raw_bytes": raw,
                     "files": len(entries), "compresslevel": a.level}}
    Path(a.manifest_out).write_text(json.dumps(doc, indent=1) + "\n")


def cmd_day(a):
    data, stats = generate_day(date.fromisoformat(a.date))
    Path(a.out).write_bytes(data)
    print(json.dumps({"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), **stats}))


def cmd_assemble(a):
    shards = sorted((json.loads(Path(p).read_text()) for p in a.shard_manifests), key=lambda s: s["shard"])
    if [s["shard"] for s in shards] != list(range(1, SHARDS + 1)):
        sys.exit(f"expected shards 1..{SHARDS}, got {[s['shard'] for s in shards]}")
    files = [f for s in shards for f in s["files"]]
    if [f["settled_on"] for f in files] != [d.isoformat() for d in days()]:
        sys.exit("shard manifests do not cover every day exactly once")
    keys = ("rows", "charges", "refunds", "charge_cents", "refund_cents", "fee_cents", "ledger_net_cents", "bytes")
    gen_sha = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    manifest = {"schema": SCHEMA, "generator_sha256": gen_sha, "data_target_bytes": DATA_TARGET_BYTES,
                "layout": "server/data/settlements/<path>", "header": HEADER.strip().split(","),
                "totals": {k: sum(f[k] for f in files) for k in keys} | {"files": len(files)}, "files": files}
    out = Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    mbytes = (json.dumps(manifest, indent=1) + "\n").encode()
    (out / "manifest.json").write_bytes(mbytes)
    base = f"https://github.com/{a.repo}/releases/download/{a.release_tag}"
    lock = {"schema": SCHEMA, "release_tag": a.release_tag, "repo": a.repo,
            "manifest_sha256": hashlib.sha256(mbytes).hexdigest(), "generator_sha256": gen_sha,
            "assets": [s["asset"] | {"shard": s["shard"], "url": f"{base}/{s['asset']['name']}",
                                     "first_day": s["files"][0]["settled_on"], "last_day": s["files"][-1]["settled_on"]}
                       for s in shards]}
    (out / "corpus.lock.json").write_text(json.dumps(lock, indent=1) + "\n")
    t = manifest["totals"]
    print(f"files={t['files']} bytes={t['bytes']} rows={t['rows']} refunds={t['refunds']} "
          f"compressed={sum(s['asset']['bytes'] for s in shards)}")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("shard")
    s.add_argument("--shard", type=int, required=True)
    s.add_argument("--of", type=int, default=SHARDS)
    s.add_argument("--out", required=True)
    s.add_argument("--manifest-out", required=True)
    s.add_argument("--level", type=int, default=6)
    d = sub.add_parser("day")
    d.add_argument("--date", required=True)
    d.add_argument("--out", required=True)
    m = sub.add_parser("assemble")
    m.add_argument("--release-tag", required=True)
    m.add_argument("--repo", required=True)
    m.add_argument("--out-dir", required=True)
    m.add_argument("shard_manifests", nargs="+")
    a = ap.parse_args()
    if a.cmd == "shard":
        if a.of != SHARDS or not 1 <= a.shard <= SHARDS:
            sys.exit(f"--of must be {SHARDS} and 1 <= --shard <= {SHARDS}")
        cmd_shard(a)
    elif a.cmd == "day":
        cmd_day(a)
    else:
        cmd_assemble(a)


if __name__ == "__main__":
    main()
