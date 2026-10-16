# Synthetic settlement corpus

The `demo10g/*` line of this repo has a data-heavy checkout of about 9.6 GB (decimal). Nearly all of that is
synthetic payment-processor settlement files that the server's settlements code reads. It is not 9.6 GB of
source code. The code and Git history are a few MB.

| Component | Where | Size | In Git |
|---|---|---|---|
| Code + history | tracked files, `.git` | a few MB | yes |
| Corpus pins | `server/data/settlements/manifest.json`, `corpus.lock.json` | under 1 MB | yes |
| Settlement files | `server/data/settlements/YYYY/MM/settlements-YYYY-MM-DD.csv` | ~9.597 GB, 731 files | no (git-ignored) |
| Git LFS | none | 0 | no |

## What the data is

One CSV per settlement day, 2024-01-01 to 2025-12-31. Each row is a premium charge or a refund, with fields
including account id, amount, processor fee, net amount, capture time and settlement day. All values are
synthetic, generated from a fixed seed per day by `generate.py`. No real customer or payment data is involved.

## Who reads it

- `materialize.py` streams every byte once and checks it against the manifest's SHA-256.
- `Settlements::DayFile` re-checks a day's SHA-256 before parsing it.
- `Settlements::LedgerPoster` posts a day's rows into the ledger database (PostgreSQL 14) as credits and debits.
- `Settlements::Reconciliation` compares the ledger with the processor file for a day.
- `bin/rails settlements:post[DAY]` and `bin/rails settlements:reconcile[DAY]` expose both steps.
- Server tests post and reconcile specific days. A test run reads only the days it names, so most bytes are read
  only during verification.

## Where it comes from

CI (`.github/workflows/corpus.yml`) generates eight quarterly shards in parallel. Each shard is a reproducible
`tar.gz` streamed straight to a release asset on this public repository: no expanded copy is kept, and no
Git LFS or package-visibility change is needed. The lock pins the manifest hash, and each asset's size and
SHA-256. A release tag is never overwritten.

## Materializing

```bash
python3 tools/settlements-corpus/materialize.py \
  --budget-root /workspace --budget-bytes 10737418240 --min-node-free-bytes 60000000000
```

- Shards are piped straight through gzip and tar into the destination. Each file lands under a `.part` name,
  is checked, then renamed read-only. A failed shard is rolled back.
- `--only DAY,...` or `--only-from-tests server/test` fetch just the days that tests name.
- `--verify-only` re-hashes what is present.
- Point the app at a shared, verified, read-only copy with `SETTLEMENTS_CORPUS_DIR=/path`. Each day is still
  checked against the manifest committed at the checked-out SHA.
- The budget gate is the demo's own ceiling. The sandbox's PVC request is not enforced on the Rajistics cluster
  (hostpath, no quota), so this script enforces it.
