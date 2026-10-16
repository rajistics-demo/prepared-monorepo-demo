# Build status: prepared-monorepo-demo

Last updated: 2026-10-16 02:00Z: M8 demo10g complete. Full 9.6 GB synthetic settlement corpus materialized live in a task-owned sandbox under a 10 GiB task budget; agent red/fix/green, own push and draft PR #4 at `3bb23b7`; fresh exact-SHA verifier PASS in a separate sandbox; task-only cleanup; baseline unchanged (Opus 5.5 in Agent Canvas; Codex supervising).
Plan: `/Users/rajiv.shah/Code/install_replicate/demo-plans/root-monorepo/technical-plan.md`
(+ `evidence-and-decisions.md`). This file is the single place to check progress.

## Current milestone

**Rollout scope:** Raj has authorized registering the new image on Rajistics and running the demo end to end,
on condition that his existing image and workloads are left alone.

**State:** M0-M8 done. M8 demo10g ran end to end on Rajistics on 2026-10-16 against the ~10 GB base `demo/base-10g-v1` (`b05805e`, branch `demo10g/main`): draft [PR #4](https://github.com/rajistics-demo/prepared-monorepo-demo/pull/4) at `3bb23b7` awaits human review (see "M8 demo10g run"). M7 demo2 ran end to end on Rajistics on 2026-10-15 with agent-owned publication (see "M7
demo2 run"): draft [PR #3](https://github.com/rajistics-demo/prepared-monorepo-demo/pull/3) at `0d5c346` awaits
human review. The M6 demo1 draft [PR #1](https://github.com/rajistics-demo/prepared-monorepo-demo/pull/1) was
launcher-published because the sandbox token got 403. After Raj added this repo to GitHub App installation
164552425, the agent's own push and PR creation work: first the access check
[PR #2](https://github.com/rajistics-demo/prepared-monorepo-demo/pull/2), then demo2. Synthetic repo,
`AUTH_MODE=none`; Root's AWS SSO is not solved or exercised.

- **Current image:** `ghcr.io/rajistics-demo/prepared-monorepo-sandbox@sha256:b56261749a2f17542e45182f6006d1909f0e8fd03b46c919b2a58bc60a4fd9e0`.
- **Image size:** 6.24 GB unpacked and 2.27 GB compressed, within the 10 GB limit. New to a node that already
  caches the 1.50.1 base: 1.07 GB compressed, about 3.0 GB unpacked.
- **Benchmark** (GitHub runner, n=1 per run):
  - TTFMT 136.3 s cold vs 47.3 s prepared (run 38316367328)
  - TTFMT 114.9 s cold vs 39.7 s prepared (run 38317624879)
- **What the benchmark covers:** setup-path evidence only.
  - Both modes used the same prepared outer image and toolchain.
  - The cold mode rebuilt the task's dependencies (bundle, the events-svc build, service pulls, databases).
  - It did **not** include installing Ruby or base tooling, or transferring the outer image.
  - It is not a full stock-image cold start, and not a Rajistics or Root speedup.
- **Rajistics gates** (as of 2026-10-15; precheck-7 exit 0, Helm rev 30 deployed 16:42:07Z):

  | Gate | Result | Next action |
  |---|---|---|
  | Digest-pinned image | ok (SSM `a189512e`) | none |
  | Disk | ok (precheck-4, 13:20Z): 40.2% now, 48.7% projected, vs 85% GC trigger and 70% cap. Was 37.9% on 10-12 | none |
  | Ownership (name `prepared-monorepo` is new) | ok | none |
  | Live capacity (13:20Z) | node requests 4735m CPU (59%) / 10.3 GiB (33%); 17.9 GB memory available; no pressure conditions; 22 Running pods; runtime deploys warm 1, sessions 16 (was 10 at 10-12 23:09Z, with Running pods and requests unchanged, so the new ones are likely scaled to zero). Evidence: `rajistics-evidence/2026-10-12/capacity-refresh-2026-10-13.txt` | recheck right before `save` |
  | Resource envelope | ok in CI, [run 38337793281](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38337793281): full verify PASS at 1 CPU / 2048Mi, 0 OOM, ephemeral 3.07 GB of 10Gi. **Thin memory headroom:** 2,219 `memory.max` events | live recheck in M6 |
  | Anonymous pull | **ok** 2026-10-13 13:17Z: anonymous token issued, manifest HEAD **200** for `prepared-monorepo-sandbox@sha256:b5626174…fd9e0` and `prepared-monorepo-events-svc@sha256:d493cf9b…cac6ba` (full digests in `rajistics-evidence/2026-10-12/anon-head-after-public.txt`). Raj made both packages public in the UI. Package metadata API not readable (token lacks `read:packages`) | none |
  | Runtime API admin | **ok** (2026-10-15, precheck-7 SSM `2262dceb` exit 0; admin challenge succeeds). Raj set the Admin Console item and deployed: Helm `openhands` rev 30 (chart `openhands-0.81.0`, app `1.71.0`) reached `deployed` at 16:42:07Z with all pods Ready. The stray `Runtime_API_Admin_Password` conversation secret was never read or used; it is **not present** in the demo API key's org (`Enterprise Org` 8b24fd08…, 28 personal + 1 org-shared names listed, no runtime/admin/password match). Evidence: `rajistics-evidence/2026-10-12/precheck-7.txt`, `deploy-state-2026-10-15.txt` | none |

| Milestone | State | Evidence |
|---|---|---|
| M0 Repo + Gemfile.lock resolved in CI | done | runs [38303322879](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38303322879), [38303482984](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38303482984) (`bootstrap/lockfile`); Ruby 3.4.11, Bundler 2.6.9, `x86_64-linux-gnu` only |
| M1 Rails server, events-svc (Rust), env tooling | done | `main` @ `5263a4b` |
| M2 CI: secret scan, server suite on PG 14/16/17, cargo test, red/green verifier + negative control | **done** | [run 38305813482](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38305813482) (`main`), [run 38305818289](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38305818289) (`reference/fix-recently-paid`), artifact `verifier-evidence` |
| M3 Fixtures, toolchain + prepared images, size report | **done** | [run 38314542594](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38314542594), artifact `image-report`; see "M3 run log" |
| M4 In-image validation (nested dockerd, prepared mode, isolation probe, induced-failure rollback, cold vs prepared timing) | **done** | [run 38316367328](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38316367328), artifact `validation-38316367328`; see "M4 evidence" |
| M4b Sizing probe (whole-sandbox cgroup peaks; prepared run under Rajistics default 1 CPU / 2048Mi) | **done** | [run 38317624879](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38317624879); see "Sizing evidence" |
| M4c Rajistics-envelope gate (agent-server live, full `oh-verify --mode prepared` at 1 CPU / 2048Mi / no swap, ephemeral bytes) | **done, PASS** | [run 38337793281](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38337793281), workflow `envelope.yml` |
| M5 Additive Rajistics registration (`prepared-monorepo` warm config beside `v1_current`) | **done** (2026-10-15, SSM `2b2f727a`): exact digest `prepared-monorepo-sandbox@sha256:b5626174…fd9e0`, count 0 (no warm pods); `v1_current` config hash unchanged; disk 44.8% now, 53.3% projected | `rajistics-evidence/2026-10-12/save-1.txt`, `capacity-settled-2026-10-15.txt` |
| M6 Live E2E demo on Rajistics (agent red/fix/green, demo branch, fresh verify, Sysbox and isolation probes, cleanup) | **done (demo1), human review pending**: agent red/fix/green; launcher-published draft PR #1 (agent push 403); fresh `oh-verify` **PASS** at `173e2a0`; FS/Docker/DB separation across sandboxes, network **not** isolated (auth enforced) | see "M6 demo1 run"; private `rajistics-evidence/2026-10-12/m6-demo1/REPORT.md` |
| M7 demo2: agent-owned publication, fresh verify of the published SHA, invalidation probe | **done, human review pending**: agent red/fix/green, then its own push and draft PR #3 at `0d5c346` with the normal provider token; fresh `oh-verify` **PASS** in a separate sandbox; cache keys HIT for the agent commit and MISS only for the perturbed input; test SHA in the PR body corrected after the fact | see "M7 demo2 run"; private `rajistics-evidence/2026-10-12/m7-demo2/REPORT.md` |
| M8 demo10g: ~10 GB synthetic corpus (OCI data artifact), full live materialization, agent run, fresh verify | **done, human review pending**: 731 files / 9,596,945,070 B materialized live in 138.6 s inside a 10 GiB task budget; agent ASSERTION_RED → GREEN → suite GREEN, own push and draft PR #4 at `3bb23b7`; fresh verifier **PASS** at the published SHAs; PR CI green; task sandboxes deleted | `rajistics-evidence/2026-10-12/m8-demo10g/`, `m8-corpus/`; see "M8 demo10g run" |

### M6 live progress (2026-10-15, Rajistics app 1.71.0 / chart 0.81.0 / runtime-api 0.11.1)

What each line is: **live** = observed on Rajistics today; **source** = read from OpenHands/enterprise tag `1.71.0`
(`f7789f9e`); **proposed** = not yet done.

- **Work sandbox (live):** `6FaTBQrwWqG7R9Y9Xte4Al`, spec = pinned demo digest, created 16:47:44Z, RUNNING in
  **62.1 s** including the first pull of the image on the node (transient PVC-not-found and ingress 503 states during
  start). Pod `runtime-trdikrwxrxcneyyf-…` runs `runtimeClass=sysbox-runc` with the exact pinned digest, 0 restarts,
  no node pressure. Evidence: `work-sandbox.json`, `pod-digest.txt`.
- **Sysbox / user namespace (live):** agent user `openhands` uid 10001; `/proc/self/uid_map` = `0 2714304512 65536`
  (container root maps to an unprivileged host uid range); cgroup v2. The agent user is in group `sudo` and
  **passwordless `sudo` works** (inherited from the agent-server base image), so `sudo docker ps` lists the task's
  containers. Root here is root only inside the Sysbox user namespace. Consequence: in-sandbox rules such as "the agent
  must not run `oh-cleanup`" or "use only prepare/verify tools" are instructions, not enforcement. Isolation that matters
  is between sandboxes (separate pods/userns) and is enforced by credentials and runtime, not by the prompt.
  Evidence: `sysbox-id.txt`.
- **Prepare (live):** first attempt without `AUTH_MODE` failed closed at `auth_gate` (exit 78), as designed.
  `AUTH_MODE=none prepare-workspace --sha 5263a4b… --run-id work1b`: **READY in 33.3 s**, no cache misses. A second
  task `iso2` in the same sandbox: READY in 14.0 s. Evidence: `prep-work1b.txt`, `iso-probe-1.txt`.
- **Isolation probe (live):** `env/scripts/isolation-probe.py work1b iso2` → **ok, all 8 checks**: concurrent marker
  writes in `server_primary_test`, `server_ledger_test`, `server_events_test`, each task saw only its own marker;
  distinct Compose projects (`oh-work1b`/`oh-iso2`), containers, volumes, ports and checkouts. Scope: two tasks in one
  sandbox; not inter-sandbox or credential isolation. Evidence: `iso-probe-1.txt`.
- **Memory (live, sandbox cgroup):** limit 2 GiB / 1 CPU. With both tasks up: anon 541 MB, the rest reclaimable page
  cache; PSI some/full avg10/60/300 = 0; `oom`/`oom_kill` = 0; `memory.max` events 1,800 (reclaim at limit, matching
  the CI envelope's 2,219). Not treated as pressure. Evidence: `mem-env-work.txt`, `iso-probe-1.txt`.
- **Cleanup (live, task-owned only):** `oh-cleanup --task …/iso2 --remove-task-dir` (compose down 0) and the failed
  `work1` dir removed. `work1b` kept for the agent run. Evidence: `iso-cleanup-1.txt`.
- **Credential inheritance (live + source); resolved for the demo by the sanitize step in "M6 demo1 run":**
  - The demo spec copied `v1_current`'s environment by design (warm pods are claimed by exact env match). That env
    includes **static `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_REGION_NAME`** and `LMNR_PROJECT_API_KEY`;
    all four are populated in the demo sandbox (lengths only checked). Every `v1_current` sandbox has the same values
    today; that baseline is unchanged.
  - The demo LLM path does **not** need them (live): the active profile `Openhands` uses LLM profile
    `Bedrock-Claude-Sonnet-4-6` = `openhands/us.anthropic.claude-sonnet-4-6` via the in-cluster
    `openhands-litellm` proxy; the key arrives through the app's refresh URL.
  - `POST /api/v1/sandboxes` accepts only `sandbox_spec_id` (1.71.0 OpenAPI), so there is no per-sandbox env override.
    Removing the AWS keys from the demo means re-saving the **demo-owned** `prepared-monorepo` entry without them
    (`v1_current` untouched). That is a runtime config write beyond "register additively", so it needs Raj's/
    supervisor's OK. Alternative: run with an explicit disclosure that baseline static AWS credentials are present in
    the sandbox env. Either way the run must not use AWS, and this does **not** touch Root's SSO problem.
  - Conversation secrets (source): `user_context.get_secrets()` returns **all** personal + org-shared secrets for the
    API key's org; agent profiles have no secret allowlist in 1.71.0. A request-scoped `secrets` entry with the same
    name replaces the stored value for that conversation only (`live_status_app_conversation_service.py`, "API-provided
    secret overrides existing secret"). Proposed for the demo start: shadow every inherited name except the ones the run
    needs with a non-sensitive placeholder, including `Runtime_API_Admin_Password` defensively. This is masking for one
    conversation, not access control, and is disclosed as such.

### M8 demo10g run (2026-10-16 01:33-01:52Z, live unless marked)

What changed from M7: the base now carries a synthetic processor settlement corpus (731 daily CSVs, 9,596,945,070
bytes, gzip 2,383,879,664 bytes in 8 shards) published once as an immutable OCI data artifact
`ghcr.io/rajistics-demo/prepared-monorepo-sandbox:data-settlements-v1` and pinned by digest in
`server/data/settlements/corpus.lock.json` + `manifest.json`. Files are not in Git or in the sandbox image; each
task materializes them with `tools/settlements-corpus/materialize.py` (anonymous pull by blob digest, streaming
gunzip/untar, per-file sha256 against the manifest, read-only files, budget and node-free-disk gates). The planted
defect is in `Settlements::Reconciliation` (synthetic, planted by the operator; no reference solution exists in
the repo, and an audit of reachable refs found no fix hints).

- **Corpus pipeline (CI, GitHub-hosted):** run 38834214762 failed at a shard push (GHCR 404 on the closing `PUT`
  of a streamed `PATCH` upload); cancelled, log kept in `m8-corpus/`, fixed by a monolithic blob `PUT`
  (`9e72523`). Run 38834464552 published all 8 shards + assemble; its validate step failed only on a missing
  `cp` destination, fixed in `b05805e` without republishing the tag. Run 38834760062 then passed full
  materialization, every-byte reverify, determinism and composition. CI 38834760181 failed because a test day was
  not materialized; fixed by the test-day scan in `b05805e`. At `b05805e` both CI 38835297820 (server-suite,
  events-svc, secret-scan) and corpus 38835297810 passed. CI-only: full 731-file materialization 70.8 s, max RSS
  ~32 MiB; checkout logical 9,597,876,177 B, allocated 9,599,406,080 B. Base tag `demo/base-10g-v1` → `b05805e`.
- **Preflight (live):** SSM snapshot 01:33:20Z: helm `openhands` rev 30, chart 0.81.0, app 1.71.0; node free
  171.79 GB, no pressure conditions. Same registered digest `prepared-monorepo-sandbox@sha256:b5626174…fd9e0`; no
  new outer image.
- **Setup (live):** task-owned sandbox `work10g` `AM9NXMaHN32KJN1nIB7t7`, RUNNING in 21.2 s; `/workspace` and
  `/var/lib/docker` are node-disk (`/dev/root`) hostPath mounts; pod limits 1 CPU / 2 GiB / 10Gi ephemeral.
  `prepare-workspace --mode prepared` at `b05805e`: READY in 33.25 s, no cache misses (the seed predates
  `demo10g`, so the target SHA was fetched).
- **Full materialization (live):** `materialize.py --budget-root <task> --budget-bytes 10737418240
  --min-node-free-bytes 120000000000`: OK in 138.6 s, 731/731 files verified, 2,383,879,664 B fetched; task dir
  allocated 9,599,991,808 B (within 10 GiB); node free 167.42 → 157.78 GB; cgroup `oom`/`oom_kill` 0, anon
  ~466 MiB (memory.max events were page-cache reclaim); node `DiskPressure=False`, memory PSI 0. Git status clean
  after removing one `__pycache__` file the materializer import wrote (follow-up below).
- **Agent (live):** conversation
  [`3badb367…`](https://app.replicated.rajistics.com/conversations/3badb367a9e74e6d82952cf288f2ca24) READY in
  10.7 s on model `openhands/us.anthropic.claude-sonnet-4-6`; 29 inherited secret names masked, only
  `GITHUB_TOKEN` kept. First action 01:40:07; regression test
  `server/test/services/settlements/reconciliation_test.rb` (3 tests, pins `Date.iso8601("2025-03-14")`, includes
  a must-still-mismatch case); `oh-phase red` ASSERTION_RED at 01:41:48 (time to first meaningful test ≈ 1 m 41 s
  after first action); test commit `0c82727`; 1-line fix using the existing `LedgerEntry::SIGNED_AMOUNT`;
  `oh-phase green` GREEN 01:42:30; `oh-phase suite` GREEN 01:43:19; fix commit `3bb23b7`; one push and one draft
  PR create, both succeeded (PR #4, base `demo10g/main`, head `3bb23b7`). Finished 01:44:06 (~4 min). PR body
  SHAs match git.
- **Fresh verifier (live):** new sandbox `verify10g` `1cUx7XZDZfzNhf2j2lLi3U`, same digest, no task dirs or
  corpus files at start. Wrapper `verify-10g.sh` (the image's `oh-verify` predates the corpus): fetch H, check
  manifest/lock blobs equal at B and H, materialize only test-referenced days from H's pins into a read-only
  verifier dir (2 days, 28.9 MB written from 607.7 MB streamed, 18.9 s), export `SETTLEMENTS_CORPUS_DIR`, run the
  unchanged `oh-verify --mode prepared`. **PASS** (168.2 s total; `oh-verify` 148.7 s). RED at B with H's tests:
  ASSERTION_RED, 2 failures inside the new tests with the bug report's exact numbers (`difference_cents=77323096`;
  expected 2067353233, actual 2144676329). GREEN at H: full suite 27 pass, all 3 new tests pass. Static: ancestry
  ok, only `server/**`, no forbidden or bypass patterns, no pre-existing test edits, tests unchanged after red,
  test blob equal at T and H. Distinct task dirs and Compose projects; fixtures restored; row counts 0 before runs.
- **GitHub CI on PR #4:** run 38836697040 success (server-suite, events-svc, secret-scan; verifier job skipped by
  its condition).
- **Transcript audit:** 122 events, 38 agent actions; no fetch or read of other refs, PRs or `BUILD-STATUS.md`
  (only a directory listing showing the filename); exactly 2 publish actions; 0 credential-pattern hits.
- **Finding, not changed: expired GPG signing config injected at conversation start.** The first test commit
  failed (`gpg: signing failed: Unusable secret key`); the agent set `commit.gpgsign=false` in the task-local repo
  config and committed unsigned. `~/.gitconfig` (global, written 01:39:59) sets `commit.gpgsign=true`,
  `user.signingkey BC3BF8BAFBA1B71C` and identity `OpenHands Rajistics POC <openhands-gpg-poc@rajistics.invalid>`;
  the key expired 2026-08-21. The conversation-free verifier sandbox from the same image has none of this, and
  M7's PR #3 commits have the same unsigned POC identity (its agent used `-c commit.gpgsign=false`). The request
  masked the `gpg_key` secret and the cached plugin `rajiv-openhands-plugins` has no GPG references, so the
  injection source is undetermined. Leftover from the 2026-08-20 GPG POC; needs an owner decision.
- **Cleanup (live):** both task sandboxes deleted (200, GET returns none); runtime pod gone; the pre-existing
  runtime pod of another image untouched; node free back to 171.13 GB, no pressure conditions. The snapshot does
  not list PVCs, so PVC removal is inferred from pod deletion and returned disk.
- **Not measured in M8:** an unprepared cold run at the 10 GB base (the cold-vs-prepared headline remains the
  earlier n=1 bench); corpus materialization is a per-task cost here (138.6 s full, 18.9 s for 2 test days), not
  pre-seeded or shared.

### M7 demo2 run (2026-10-15 21:24-21:50Z, live unless marked)

- **Setup (live):** new task-owned sandbox `work3` `5SQJBC9VLEKMVF96xem1WX` from the registered digest, cold
  (demo warm count 0), RUNNING in 21.2 s. `prepare-workspace` prepared mode at base `5263a4b` took 31.4 s with no
  cache misses (`images` 17.1 s, DB services 6.4 s, fixtures 2.1 s, events-svc 3.0 s, bundle 0.5 s). Conversation
  [`4dedd893…`](https://app.replicated.rajistics.com/conversations/4dedd89313944f31a09cb0e9ebdb9296) was READY in
  10.7 s. 29 inherited secret names were masked; only `GITHUB_TOKEN` was kept. The shell had no AWS keys.
- **Preflight (live):** helm rev 30, app 1.71.0, runtime-api 0.11.1. SSM snapshot unchanged from M6 (`v1_current`
  `fd248d14…`, demo spec `929b6dc0…` count 0). All precheck gates ok, disk 43.0% (projected 51.4%), no node
  pressure. The provider `github_token` (GitHub App user-to-server) sees this repo with `contents:write` and
  `pull_requests:write`; the `git-receive-pack` handshake returned 200.
- **Agent (live, 2 m 18 s, 38 actions, one attempt):** read the report and server code, wrote
  `server/test/queries/recently_paid_excludes_never_paid_test.rb`, then ran `oh-phase red`, which gave
  `ASSERTION_RED` 65 s after the conversation's first event. It committed the test (`94e2e44584b1…`), added
  `.paying` to `RecentlyPaidAccounts`, and ran `green` (pass) and `suite` (20 pass). It then committed the fix
  (`0d5c346`), pushed `demo/recently-paid-demo2` and opened draft
  [PR #3](https://github.com/rajistics-demo/prepared-monorepo-demo/pull/3) itself, with no PAT, no launcher
  publication and no retry.
- **SHA misreport (live):** the agent's PR body and final message gave the test commit as `94e2e44a5a2d…`, which does
  not exist. It had only seen the short SHA `94e2e44` and made up the rest. The original body is preserved, and only
  that SHA was corrected through `PATCH /pulls/3`; the head is unchanged and nothing was re-pushed. **Follow-up:**
  require `git rev-parse` SHAs in the protocol and have the verifier check SHAs quoted in PR bodies.
- **Fresh verify (live):** separate new sandbox `verify2`, new seed checkout plus an anonymous fetch of the published
  head, new Compose projects and restored DBs. `oh-verify` **PASS** in 48.7 s:
  - red at base plus the test overlay: `ASSERTION_RED` (`Minitest::Assertion` on Comped Corp, exit 1)
  - green at `0d5c346`: 20 runs, 33 assertions, 0 failures
  - static: only the query file and the new test changed; no pre-existing test modified
  - test blob `852f71d8…` identical at the test commit and the head
- **Isolation re-check (live):** both pods run `sysbox-runc`, each with its own user-namespace range. Concurrent
  marker writes stayed separate across the filesystem, Docker and DBs (the M6 classifier false positive is fixed).
  Network is still **not** isolated: peer pod ports 60000/60001 are open, `/alive` returns 200, and authenticated
  routes return 401 (API) and 403 (VS Code). Both sandboxes had 1 CPU / 2 GiB, `memory.peak` at the limit, and 0 OOM.
- **Invalidation (live decision, no rebuild):** on a disposable seed clone, the agent head HITs all four caches.
  Each perturbed input MISSes only its own cache: `Gemfile.lock` and `BUNDLE_WITHOUT` invalidate the bundle; a
  primary migration invalidates PG16; `ledger_schema.rb` invalidates PG14; events-svc `src` invalidates PG17. The
  common `seeds.rb` MISSes all three fixtures, and a non-input file MISSes nothing. The rebuild after a miss is still
  only CI/scratch evidence.
- **Reference exposure (disclosure, not a blind solve):** `reference/fix-recently-paid` and the demo1 fix (PRs #1 and
  #2) are public. The base tree's `BUILD-STATUS.md` names `reference/*`, and seed `main`'s `BUILD-STATUS.md`
  describes demo1. The transcript shows the agent read neither. It ran no fetch, log or branch inspection against
  other refs, and no GitHub reads other than its own push and PR.
- **Cleanup (task-owned only):** `oh-cleanup` for demo2 (compose down 0), probe markers, marker DB and anonymous
  volume removed; `work3` is left with 0 containers, volumes and task dirs. Verifier state retained, then `verify2`
  deleted. Kept: `work3` and the conversation for review, PRs #1-#3, and the M6 `work2` sandbox. After the run the
  snapshot is unchanged, the precheck gates are identical and disk is 43.8%. The default warm pod rotated because of
  Raj's unrelated CRD Jira automation (run at 21:43:46), which I did not touch.

### M6 demo1 run (2026-10-15 17:04-17:45Z, live unless marked)

- **Sanitize (demo-owned config only):** `warm-config.sh sanitize` (commit `4714948`) re-saved `prepared-monorepo`
  without `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` (`AWS_SESSION_TOKEN` already absent). Hash `eb2f0cfa…` →
  `929b6dc0…`, image and other fields unchanged; `v1_current` `fd248d14…` unchanged. Replaced sandbox
  `6FaTBQrwWqG7R9Y9Xte4Al` deleted after evidence retention.
- **Work sandbox:** `447afdy9zo3lJO3FeElfPh`, RUNNING in 21.6 s; no AWS credential names in any readable process
  environment. Task `demo1` prepared at base `5263a4b`: READY 32.3 s.
- **Conversation:** `e484fb4142ae40cb8147bed5c47d15af` (start task `5e5689a5…`), READY 10.7 s. Request `secrets`
  shadowed 29 inherited names with a placeholder; only `GITHUB_TOKEN` kept (masking, not access control). Agent:
  first event 17:11:11Z, `oh-phase red` 17:12:23Z (ASSERTION_RED, 2 assertion failures), green and suite (21 pass)
  by 17:12:44Z; finished 17:19:04Z. n=1.
- **Commits:** test `e169eb78e09d8207fdac759afa685fa5180d87c0`, fix `173e2a04510f2e531d8b4f868b140697d5568456`
  (`.paying` added to `RecentlyPaidAccounts`). Only `server/` touched.
- **Publication (launcher-assisted):** the sandbox `GITHUB_TOKEN` authenticates as `rajshah4` but push returned 403
  and REST writes `Resource not accessible by integration`. **The agent did not push.** The launcher exported
  `5263a4b..173e2a0` as a git bundle (sha256 `19178021…56af`), pushed `173e2a0` unchanged to
  `demo/recently-paid-demo1`, and opened draft [PR #1](https://github.com/rajistics-demo/prepared-monorepo-demo/pull/1)
  with the reference-exposure disclosure and AI note. No credential entered the sandbox.
- **Prompt deviation:** told to stop on push failure, the agent made 35 publish/auth-related actions (masked
  names, which held placeholders and were rejected; `GH_TOKEN=$GITHUB_TOKEN`; token-in-URL pushes; `gh auth login`;
  Git Data API writes; read-only org member/collaborator listing). All writes failed. The launcher removed the
  `gh` `hosts.yml` it wrote. Lesson: publish from the launcher by design, or give the run a write-scoped token.
- **Fresh verification:** new sandbox `swqOenX4fFnxeG0Ifprcl` (AWS names absent), `oh-verify --mode prepared`
  at base/test/head **PASS** in 50.3 s: RED at base with tests from `173e2a0` = ASSERTION_RED (2, inside the new
  test); GREEN at `173e2a0` = 21 pass incl. both new tests; distinct checkouts, Compose projects and restored DBs
  (0 rows before each run); test blob `3f75062a…` identical at test and head. The agent's own green/suite ran
  with the fix uncommitted, so only the verifier binds to the published SHA. Gaps: `image.ref` null
  (`OH_IMAGE_REF` unset; spec pins the digest); `oh-verify` teardown leaves checkout/state dirs.
- **Reference exposure:** disclosure carried verbatim in the PR and report. Transcript shows no read of
  `reference/*`, `a5648107` or `BUILD-STATUS.md` contents before the fix (17:12Z); only a filename in a 17:11Z
  listing and post-fix `git log origin/main` subjects (17:16Z).
- **Cross-sandbox probe (`work2` ↔ `verify1`, concurrent):** same-path marker writes each read back their own;
  no foreign files, Docker volumes or containers either way; `work2`'s marker DB only in `work2`. (`oh-demo1-*` in
  `xsbx-check-work2.txt` are `work2`'s own services: a classifier false positive.) **Network is not isolated:**
  peer ports 60000/60001 open pod-to-pod; unauthenticated `/alive` 200, agent-server APIs 401, VS Code 403; peer
  Compose ports are loopback-bound and closed. This is FS/Docker/DB separation plus authentication, not network
  isolation; no NetworkPolicy observed.
- **Resources:** both sandboxes 1 CPU / 2 GiB, `memory.peak` at the limit (page cache), `oom`/`oom_kill` 0.
- **Cleanup (task-owned only):** `demo1` task removed (compose down 0); probe markers, marker DB and the probe's
  anonymous volumes removed; verifier sandbox deleted. Kept: work sandbox `447afdy9…` (review conversation),
  branch, draft PR, demo warm config (count 0).
- **Baseline after the run:** SSM snapshot `1d363b2d…` / precheck `46d67f17…` (exit 0): `v1_current` `fd248d14…`
  unchanged, warm pod `runtime-okeyreyogkowelqq` ready=1, disk 45.0% (projected 53.5%).
- **Evidence (private, not in git):** `rajistics-evidence/2026-10-12/m6-demo1/` with `REPORT.md`, `MANIFEST.sha256`;
  raw events mode 600, plus a redacted copy.

### M2 verifier evidence (run 38305818289, `oh-verify --mode cold` on a GitHub runner)

- **Refs:**
  - base: `demo/base-v1` = `5263a4bae1777271968466d25974b2466be367d8`, the seeded regression on `main`
  - T: `b8b1229`, test only
  - H: `a5648107b273d497e2b22ae7f0290cea55ad6d29`, the fix
  - T and H are on branch `reference/fix-recently-paid`.
- **PASS case, red:** a fresh task at base with H's test overlaid is `ASSERTION_RED`, with 1 failure, inside the
  new test. Expected `[Umbrella, Acme, Initech]`, actual `[Comped Co, Umbrella, Acme, Initech]`: the never-paid
  account sorts first under PostgreSQL `DESC`.
- **PASS case, green:** a separate fresh task at H runs the full suite 20/20, and the new test passes. The two
  tasks used distinct Compose projects, and both were torn down (exit 0).
- **Negative control** (H set to T, so no fix): verdict `FAIL`/`BEHAVIOR`. The verifier rejects an unfixed head.
- **Cold mode only:** both runs used a network clone, a task-local `bundle install` and `dev:bootstrap`.
  Prepare took 68-146 s per task on the runner. These are not benchmark numbers.
- **Not shown:** that the test would pass on SQLite. That is reasoned from NULL ordering, not run.

### M3 run log (`image.yml`, workflow_dispatch, publish=true; nothing is pushed unless every gate passes)

Step times on `ubuntu-24.04`: base pull ~47 s, toolchain (Ruby compile + bundle) ~6 min,
events-svc ~1 min, fixtures ~1 min.

| Run | Commit | Result | Fix |
|---|---|---|---|
| [38306993980](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38306993980) | `ffaf115` | Fixtures built for all 3 DBs, then cleanup failed: root-owned files in the temp checkout | `540d8b1`: the bootstrap container hands `/src` back to the runner UID in an EXIT trap |
| [38308202521](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38308202521) | `540d8b1` | Seed history scan clean; fixture/metadata scan reported 7 findings | `4e53325`: verbose, redacted report, plus a narrow allowlist (see below) |
| [38309317972](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38309317972) | `4e53325` | Scans clean, prepared image built, entrypoint preserved; smoke test failed: git refused the root-owned seed as dubious ownership as `openhands` | `54706f0`: `git config --system safe.directory` for only `/opt/prepared/seed/repo.git`; smoke test now runs the real no-hardlinks clone and checks there are no alternates |
| [38310817702](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38310817702) | `54706f0` | Green, pushed `…@sha256:3bd778…`. **Superseded:** M4 found its tarballs unreadable by `openhands` (`docker save` writes mode 0600 and `COPY` keeps it) | `b6143b6`: `chmod a+rX,a-w`, plus a smoke gate that every file under `/opt/prepared` is world-readable |
| [38314542594](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38314542594) | `b6143b6` | **green, pushed; current image** | |

**M3 outputs (run 38314542594, artifact `image-report`):**

- **Prepared image:** `ghcr.io/rajistics-demo/prepared-monorepo-sandbox@sha256:b56261749a2f17542e45182f6006d1909f0e8fd03b46c919b2a58bc60a4fd9e0`
- **events-svc:** `ghcr.io/rajistics-demo/prepared-monorepo-events-svc@sha256:d493cf9b3c381521b2500cb68f01b963818dad17c1d6eeb9c43d4122b8cac6ba`
- **Superseded digest:** `@sha256:3bd77810…` (run 38310817702) is left in GHCR, immutable. Do not use it.
- **Sizes** (measured):

  | Measure | Size |
  |---|---|
  | Base, unpacked | 3.24 GB |
  | Prepared image, unpacked | 6.24 GB |
  | Prepared image, compressed | 2.27 GB (35 layers) |
  | Shared with base | 21 layers |
  | Compressed bytes not in base | 1.07 GB |

- **Context:** 1.43 GB of service image tarballs (3 PostgreSQL images + events-svc), 45 KB of fixtures, 95 KB seed.
- **Runner disk:** peak increase during the build was 12.6 GB, including build cache and intermediate images.
- **Fresh pull** on a GitHub runner took 81 s (M4 run 38312235108).
- **Nested Docker disk cost:** the tarballs are loaded into the sandbox's inner Docker at prepare time. Inner-Docker
  disk therefore adds roughly the unpacked size of those images on top of the image itself; M4 measures it.

**Secret-scan allowlist** (`env/security/gitleaks-image-inputs.toml`, used only by the image-input scan):

- Scope: `generic-api-key` matches whose value is a pure 64-hex sha256, in `lock.json`/`manifest.json` only (AND condition).
- These are content-addressed cache keys of public inputs.
- With it applied, all 7 findings disappeared, and the fixture SQL was clean under default rules.
- The repo-history scan still uses the default rules, with no allowlist.

`prepare-workspace` also now serializes its "start dockerd if absent" check with a file lock, so two tasks
preparing concurrently in one sandbox cannot both launch a daemon (needed by the M4 isolation probe).

### M4 evidence (`validate.yml` run 38316367328 on image `@sha256:b5626174…`)

**Environment.** A GitHub-hosted `ubuntu-24.04` runner: 2 vCPU, 8 GB RAM. Each "sandbox" is
`docker run --privileged` of the prepared image with its own `/var/lib/docker` volume, running as `openhands`
(passwordless `sudo` for `dockerd`). This stands in for Rajistics' Sysbox runtime. It proves the image's behavior,
not Rajistics scheduling, isolation or credentials. Fresh pull of the 2.27 GB image took 76-119 s across runs, and
pull time is excluded from TTFMT.

| Check | Result |
|---|---|
| Entrypoint `tini -- openhands-agent-server`, user `openhands` | preserved; `/alive` 200 after ~6 s. With no args it binds `127.0.0.1:8000` (base behavior; the runtime supplies host and port) |
| Two concurrent prepared tasks, one daemon | both `READY` (46-66 s each, concurrent on 2 vCPU), no cache misses |
| Marker-write isolation probe (primary / ledger / events test DBs) | each task sees only its own marker in all 3 DBs. Distinct Compose projects, containers, volumes, ports and checkouts |
| Induced failure (`OH_TEST_FAIL_AFTER=services_db`) | `FAILED/services_db`, classified `ENV_SERVICES`, rolled back; 0 containers and 0 volumes left for that project |
| `oh-cleanup --remove-task-dir` on both tasks | no containers or volumes left in the inner daemon |
| `oh-verify --mode prepared` (B=`5263a4b`, T=`b8b1229`, H=`a564810`) | **PASS** in 34 s. RED and GREEN each ran as a new task with fixtures `restored`, a `seed` checkout and a new Compose project |
| Negative control (H=T) | **FAIL / BEHAVIOR** |

**Isolation scope.** The checks above demonstrate isolation *within one sandbox*: two tasks sharing one inner
daemon get separate Compose projects, databases, volumes, ports and checkouts. They do **not** demonstrate security
isolation *between sandboxes* on Rajistics, which depends on Sysbox, pod and namespace boundaries and on which
credentials each sandbox carries. That remains pending until M6.

**Benchmark: time to first meaningful test (TTFMT).**

- **Clock:** starts before `prepare-workspace`; stops when the regression test is classified `ASSERTION_RED` at
  base.
- **Controls:** both modes ran on the same runner, at the same base SHA, with the same test file, each in a fresh
  sandbox with an empty inner Docker. n=1 per mode.
- **Same outer image in both modes.** "Unprepared cold" ran inside the same prepared outer image and toolchain as
  "prepared":
  - Ruby, Bundler, the Docker engine and the agent-server were already present in both.
  - Cold rebuilt the task-level work: network checkout, `bundle install`, PostgreSQL pulls, the events-svc Rust
    build, `dev:bootstrap`.
  - Outer image transfer is excluded from both (pull 76-119 s on the runner).
- **So:** this is setup-path evidence, not a stock-image cold start and not a Rajistics measurement.

| Phase (s) | checkout | bundle | dockerd | images | services_db | fixtures | services_events | bootstrap | verify_ready | first test | **TTFMT** |
|---|---|---|---|---|---|---|---|---|---|---|---|
| unprepared cold | 0.7 (network) | 42.3 (install) | 1.3 | 0 | 24.1 (pull) | 0 | 59.5 (Rust build) | 5.5 | 1.1 | 1.5 | **136.3** |
| prepared cold | 0.0 (seed) | 0.5 | 0.9 | 27.5 (`docker load`) | 9.8 | 2.9 (restore) | 2.9 | none | 0.8 | 1.5 | **47.3** |

What the benchmark shows and does not show:

- **Remaining prepared cost:** loading 1.4 GB of service-image tarballs into the empty inner daemon. That is the
  next optimization target, for example a pre-seeded inner data root or a node-local registry mirror. Neither
  has been tried yet.
- **Variance:** the earlier run 38315715872 measured prepared TTFMT at 35.0 s. n=1 is not enough for a stable
  number, so repeat it before quoting.
- **Synthetic scale:** the bundle, fixtures and bootstrap are small. Root's real bundle and bootstrap are
  described as slow, so the absolute cold numbers here are not predictive for Root.
- **Inner-Docker disk:** 4.06 GB in the prepared bench sandbox and 4.67 GB in the cold one, in addition to the
  6.24 GB unpacked image.

### Sizing evidence (`validate.yml` run 38317624879, same image, n=1)

Each mode ran in a fresh `--privileged` sandbox. Memory and CPU come from the sandbox's whole cgroup: agent image,
inner `dockerd` and all task containers. The agent-server process was not running in these bench containers
(`--entrypoint sleep`), so a live sandbox adds the agent-server and the agent's tool processes on top.

| Run | TTFMT | `memory.peak` | OOM kills | CPU time | Inner Docker |
|---|---|---|---|---|---|
| unprepared cold (no limits) | 114.9 s | 3.93 GB | 0 | 136.5 s | 4.67 GB |
| prepared (no limits) | 39.7 s | 3.15 GB | 0 | 17.9 s | 4.06 GB |
| prepared, `--cpus 1 --memory 2048m --memory-swap 2048m` | 40.8 s, `READY`, valid | 2.147 GB (= limit) | 0 | 17.8 s | 4.06 GB |

- **1 CPU is not the bottleneck for the prepared path.** It took 40.8 s versus 39.7 s unconstrained; the
  remaining time is I/O-bound (`docker load` 26.8 s).
- **2 GiB passed, but with no headroom shown.** `memory.peak` hit the limit and the kernel reclaimed page cache;
  nothing was OOM-killed. That doesn't show 2 GiB is enough once the agent-server, the agent's tools and a full
  suite run are added.
  - Rajistics sandbox limits are global: CPU 1000m, memory 2048Mi, ephemeral storage 10Gi.
    - Those values come from local history (worklogs 2026-06-25 and 2026-07-20). The 2026-10-12 live read
      confirmed only the variable names, which is allowlist policy.
    - The warm-config schema has no per-config resource fields.
  - So M6 must watch `memory.events` in the live sandbox, and treat any OOM as a sizing blocker that needs Raj's
    decision. Global limits are not to be changed silently.
- **Ephemeral 10Gi is the tighter disk risk.**
  - Inner Docker alone was 4.06 GB, before the agent's checkout and caches.
  - It is unverified whether Sysbox's inner `/var/lib/docker` counts against the pod's ephemeral-storage limit.
  - M6 must measure it, and an eviction is a stop condition.

### History note

`demo/base-v1` was first created at `fe74411`, where `server/bin/*` lacked the executable bit, so setup could
not run at base. The tag was moved to the fix-forward commit `5263a4b` (the bug is still present there) before
anything consumed it, and the reference branch was rebased onto it. `main` was not rewritten.

### Deviations from the plan (for Codex review)

- **Bug scenario:** `GET /accounts/recently_paid` and `RecentlyPaidAccounts`, which drops the `paying`
  filter, instead of the plan's `recently_active`. The mechanism is the same: PostgreSQL sorts NULLs first under
  `DESC`. The suite is still green at base because the covering test was removed.
- **Rails version:** 8.1.4 instead of the plan's 8.0.x (current 8.1 patch at lock time).
- **Reference fix visibility:** the reference fix is on a branch in this repo. It is excluded from the image
  seed, but any sandbox token with repo read access can fetch it. Before a live agent demo, either move the
  reference proof to a separate repo or delete the branch once evidence is retained.

## Links

- Repo (private): https://github.com/rajistics-demo/prepared-monorepo-demo. Default branch: `main`.
- Actions: https://github.com/rajistics-demo/prepared-monorepo-demo/actions
- Images (private GHCR packages; new tags only, never overwritten). Use the digests listed under "M3 outputs":
  - `ghcr.io/rajistics-demo/prepared-monorepo-sandbox`
  - `ghcr.io/rajistics-demo/prepared-monorepo-events-svc`
- Workflows:
  - `image.yml` (dispatch, `publish=true`) builds and publishes the images.
  - `validate.yml` (dispatch, `image=<digest>`) runs the in-image checks.
  - `ci.yml` runs on push.

## Builder path (off-laptop)

- **Primary: GitHub Actions, GitHub-hosted `ubuntu-24.04` amd64 runners on this private repo.**
  Every workflow will record `nproc`, memory and `df` so the image build's real disk footprint is measured
  rather than assumed.
- **Fallback: one temporary EC2 builder** (about 4 vCPU / 16 GiB, bounded gp3, SSM only, no public
  ingress, tagged for this demo), used only if the measured runner disk or time is not enough.
  **Not created. No AWS resource IDs exist yet.**
- Laptop: editing, `git`, syntax checks and `gh`/registry reads only. Docker Desktop is not running,
  and no build, compile or service stack of this task is running locally. (Checked 2026-10-12: no
  docker socket, and no cargo, rustc, bundle or docker build processes.) `Cargo.lock` was generated
  locally with `cargo generate-lockfile` (resolution only, no compile).
- Rajistics: not used for building. Only read-only SSM inspection has run there: capacity, pull-secret names,
  a warm-config snapshot and prechecks. Nothing was written, pulled, pruned or restarted. `v1_current` and its
  image are untouched.

## Pinned inputs (verified against registries 2026-10-12)

- Base: `ghcr.io/openhands/agent-server:1.50.1-python` @ `sha256:56758362…` (full digest in
  `env/pins.json`; matches the plan's evidence appendix).
- `postgres:14.24-bookworm`, `postgres:16.15-bookworm`, `postgres:17.11-bookworm`, `rust:1.98-slim-trixie`,
  `debian:trixie-slim`, `ruby:3.4.11-slim-trixie`, `gitleaks:v8.30.1` (index and amd64 digests), the Ruby 3.4.11
  tarball sha256 and the GitHub Actions commit SHAs are all in `env/pins.json`. Each digest was re-resolved from
  its registry, not recalled from memory.

## Verifier design (updated per Codex review)

`env/image/oh-verify` never reuses database state between verdict-bearing runs:

- **RED**: a newly prepared task at base `B` (new checkout, new Compose project, databases freshly
  restored or bootstrapped from keyed fixtures), with the regression tests from `H` overlaid. The tests
  must be `ASSERTION_RED`, with every failure inside the new tests.
- **GREEN**: a *separate* newly prepared task at `H`. The full server suite must be `GREEN`, and every
  new test must appear in it and pass. There is no separate green-then-suite run on shared databases.
- The report records, per run, the task directory, Compose project, fixture source, row counts
  observed before the run and cache misses. It asserts the two Compose projects differ. Agent-side
  `oh-phase` evidence is informative only.
- The verifier tears down only its own tasks afterwards (`--keep-tasks` keeps them for inspection).

## Constraints in force

- `AUTH_MODE=none` is explicit for the synthetic demo. AWS SSO and real Root ECR access are **unresolved**
  and are not exercised or claimed here.
- No secrets in git, the seed, image layers or artifacts. A secret scan gates any publication.
- Credential isolation inside sandboxes is unproven. Ambient default-spec AWS keys and inherited creator
  tokens cannot be removed by a profile allowlist.
- **Raj-authorized scope (2026-10-12):**
  - Register the new digest additively and run the demo end to end.
  - Don't change `v1_current`, its image, global defaults, existing automations, Git Sync or workloads.
  - No pruning, no direct LiteLLM access, no messages to humans.

## Next steps

1. **Human review of draft PR #4** (diff, `m8-demo10g/verify-demo10g.json`, conversation `3badb367…`) and of
   PR #3. PR #1 (demo1) and PR #2 (the access check) are also open drafts. Do not merge without review.
1a. **GPG POC leftover (owner decision):** find what writes the expired signing config into conversation
   sandboxes and decide whether to remove it or provision a valid per-user key. Until then agent commits are
   unsigned and agents disable signing locally; a customer repo that requires signed commits would reject them.
1b. **Small follow-ups on `demo10g/main` (after review):** ignore `tools/**/__pycache__/`; move the corpus step of
   `verify-10g.sh` into `oh-verify` / `prepare-workspace` with the next image rebuild.
2. **Publish path: resolved for this repo.** Since Raj added the repo to installation 164552425, the agent pushes and
   opens PRs with the normal provider token (PR #2, PR #3). Launcher-side publishing is no longer needed here.
3. **Guard reported SHAs:** add "full SHAs from `git rev-parse` only" to `server/AGENTS.md` / the bug-report prompt,
   and have `oh-verify` (or the launcher) check any SHA quoted in the PR body against git. Raised by demo2.
4. **Optional:** delete work sandboxes `447afdy9zo3lJO3FeElfPh` (M6) and `5SQJBC9VLEKMVF96xem1WX` (M7) once
   review no longer needs them; optional reference remediation (see Blockers) before claiming a blind solve.
5. **Optional fidelity:** NetworkPolicy between sandboxes is not in place; any claim of network isolation needs it
   tested first. Memory headroom at 2 GiB stays thin.
6. **Optional benchmark fidelity:** repeat the bench n≥3 per mode, and try pre-seeding inner Docker images to
   remove the ~27 s `docker load`. Report it separately from the n=1 numbers.

## Blockers / open risks

- **Open (M8): expired GPG signing config in conversation sandboxes.** See "M8 demo10g run". Not changed.
- **Resolved: pull auth.** Raj made both packages public (anonymous HEAD 200 at both pinned digests). No
  credential was created. Digests and tags were unchanged.
- **Not a gate; disclosure required: reference fix is publicly readable.** The acceptance criteria allow either
  an inaccessible reference solution or explicit disclosure. Unless Raj chooses remediation, M6 proceeds with the
  disclosure below once the admin and capacity gates pass. While the question is open, the agent does not change
  repo visibility or delete the branch.
  - This repo became **public** at 2026-10-12T20:17:55Z (GitHub PublicEvent, actor rajshah4). It was likely
    clicked while trying to make the packages public. The agent did not change it, because repo visibility
    changes were excluded from its authorization.
  - Anonymous `GET /repos/.../branches/reference/fix-recently-paid` returns 200. `main` also publishes the fix
    SHA in this file and both validation workflows. The base tag's `BUILD-STATUS.md` points to `reference/*`.
  - Leak paths for the demo agent: (a) web/API access to the public repo; (b) `cold` mode does a full
    `git clone` (all branches); (c) `origin` is set to the repo URL, so `git fetch origin` reaches every branch.
    `prepared` mode clones from the seed (no reference refs) and fetches only the target SHA. That limits what
    is checked out but does not block (a) or (c).
  - No secrets exposed: a pattern scan across all refs found nothing. The content is synthetic.
  - Evidence preserved privately (local, mode 600, not in git):
    `rajistics-evidence/2026-10-12/reference-fix-recently-paid.bundle`. The bundle is verified. It contains
    H `a5648107…`, and its sha256 is in the `.sha256` file alongside it.
  - **Optional Raj remediation (reversible, scoped; question pending, nothing done):** (1) make the repo private again, then re-verify
    anonymous HEAD on both packages (that package visibility stays independent is expected but not yet verified); **and** (2) delete the remote
    branch `reference/fix-recently-paid`, restorable from the bundle. After that, a sandbox token with repo read
    can no longer fetch it. GitHub may still serve the unreachable commit by SHA, and the SHA is in `main` history.
  - Default (no remediation chosen): the demo carries this disclosure verbatim in the run report, the PR body and
    the spoken intro, and makes no blind-solve claim anywhere:
    > Reference exposure: the repository `rajistics-demo/prepared-monorepo-demo` has been public since
    > 2026-10-12T20:17:55Z. Its branch `reference/fix-recently-paid` (fix commit `a5648107`) and the build
    > notes on `main` were publicly readable during this run, and the agent sandbox had network and git access
    > to them. This run demonstrates the prepared environment, red/green evidence and exact-SHA verification.
    > It is not evidence of solving without access to a known answer.
  - The run report also records whether the agent's transcript shows any fetch or read of `reference/*`, the fix
    SHA or `BUILD-STATUS.md`. This is a factual observation and does not replace the disclosure.
  - Even if Raj later remediates, the disclosure still applies to any run that started before remediation.
- **Resolved (2026-10-15): runtime-api admin.** Raj set and deployed `admin_password` (Helm rev 30). The deploy also upgraded the release: chart 0.76.0 → **0.81.0**, app 1.68.1 → **1.71.0**, runtime-api 0.10.0 → **0.11.1** (node report). The default sandbox image is still `agent-server:1.50.1-python` (live `sandbox-specs`), which is the demo image's base; `server_info` reports `sdk_version` 1.50.1.
  - Prior 0.10.0 findings were rechecked against 0.11.1 and 1.71.0: the M5 save path and the `POST /api/v1/sandboxes?sandbox_spec_id=` create path both worked live.
  - `env/rajistics/admin-setting.md` is kept as the runbook for that step.
- **Raj's ~50 GB image:** not found on the node (outer containerd, nested Docker, PVs). Its location is
  **unverified**.
  - A stopped `replicated-openhands` instance and unattached 50 GB EBS volumes exist; they were not inspected.
  - **Likely referent, unconfirmed:** the 55.48 GB Root POC image from 2026-08-15, which ran on the separate,
    since-destroyed `rajiv-monorepo-poc` install. Today's reads found no ECR image over 20 GB and no POC
    instance. Raj to confirm.
  - Node disk fell from 79% to 38% since the planning read, with no action by us.
  - We protect it by not deleting or pruning anything and keeping disk far below GC. `v1_current` is **not**
    assumed to be it.
- **M6 measured (demo1):** memory reached the 2 GiB limit (page cache) with 0 OOM in both sandboxes; inner
  `/var/lib/docker` sits on the node root filesystem, not a separate per-sandbox volume. Cross-sandbox network is
  open (auth enforced at the app layer). At M6 the sandbox `GITHUB_TOKEN` could not write to the demo org.
  **Resolved for this repo** after Raj added it to installation 164552425: agent-owned push and PR worked in PR #2 and
  M7 demo2 (PR #3). Network was still open in M7.
- **Resolved:** GitHub-hosted runner disk was enough. Peak build increase was 12.6 GB; validation ran on the
  same runner class.
- **Resolved:** nested `dockerd` works on GitHub-hosted runners with `--privileged`, so the EC2 fallback was not
  needed and no AWS resources were created.
- **Open, Rajistics-specific and untested:**
  - whether Sysbox there gives `openhands` a working `dockerd` with this image's sudo path
  - inner data-root placement and size limits
  - pull time of the 2.27 GB image on its nodes
  - isolation between sandboxes: measured in demo1 (FS/Docker/DB separated; network open, auth enforced);
    credentials: demo sandboxes now carry no AWS keys, `v1_current` still does (baseline)
  - image GC behavior under the new image. Disk now projects to 46% against the 85% GC trigger.
- **Transient:** one CI run (38305390512) failed when every `static.crates.io` download timed out inside the
  events-svc build. The same build passed in the concurrent and later runs. Cargo now retries with fewer
  connections.
