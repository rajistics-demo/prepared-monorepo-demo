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
- Server tests name specific days. A test run reads only the days it names, so most bytes are read only by
  `materialize.py`.

## Where it comes from

CI (`.github/workflows/corpus.yml`, on a push to `corpus/<name>`) generates eight quarterly shards in parallel.
Each shard is a reproducible `tar.gz` (about 2.6 GB compressed in total) pushed by digest as a blob. One OCI
1.1 data artifact referencing the eight shards and `manifest.json` is then pushed under one new tag,
`data-<name>`, in the already-public synthetic package `ghcr.io/rajistics-demo/prepared-monorepo-sandbox`.

- It is a data artifact, not a container image: empty config, `artifactType`
  `application/vnd.rajistics.settlements-corpus.v1`, and a description annotation saying so.
- The workflow uses the repository's own `GITHUB_TOKEN` (`packages: write`), the same path `image.yml` uses.
  No visibility, credential or package-setting change is involved.
- The tag must not exist beforehand, and CI snapshots every existing tag's digest before and after the push
  and fails if anything other than the one new tag changed.
- `corpus.lock.json` pins the manifest hash, the artifact's manifest digest, and each shard blob's size and
  SHA-256. Consumers pull anonymously by blob digest, so the tag is only a label.

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
