# Build status: prepared-monorepo-demo

Last updated: 2026-10-12, after M4 run 38316367328 (Opus 5.5 in Agent Canvas; Codex supervising).
Plan: `/Users/rajiv.shah/Code/install_replicate/demo-plans/root-monorepo/technical-plan.md`
(+ `evidence-and-decisions.md`). This file is the single place to check progress.

## Current milestone

**M3 and M4 done on GitHub-hosted runners. Next is M5: the proposed Rajistics registration config for Codex
review. Nothing has been registered or pulled on Rajistics.**

- **Current image:** `ghcr.io/rajistics-demo/prepared-monorepo-sandbox@sha256:b56261749a2f17542e45182f6006d1909f0e8fd03b46c919b2a58bc60a4fd9e0`.
- **Benchmark headline** (run 38316367328, n=1): TTFMT 136.3 s unprepared-cold vs 47.3 s prepared-cold (2.9x).
- **Benchmark scope:** synthetic repo, 2 vCPU GitHub runner, `--privileged` nested Docker. This is not a Rajistics
  or Root number.

| Milestone | State | Evidence |
|---|---|---|
| M0 Repo + Gemfile.lock resolved in CI | done | runs [38303322879](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38303322879), [38303482984](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38303482984) (`bootstrap/lockfile`); Ruby 3.4.11, Bundler 2.6.9, `x86_64-linux-gnu` only |
| M1 Rails server, events-svc (Rust), env tooling | done | `main` @ `5263a4b` |
| M2 CI: secret scan, server suite on PG 14/16/17, cargo test, red/green verifier + negative control | **done** | [run 38305813482](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38305813482) (`main`), [run 38305818289](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38305818289) (`reference/fix-recently-paid`), artifact `verifier-evidence` |
| M3 Fixtures, toolchain + prepared images, size report | **done** | [run 38314542594](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38314542594), artifact `image-report`; see "M3 run log" |
| M4 In-image validation (nested dockerd, prepared mode, isolation probe, induced-failure rollback, cold vs prepared timing) | **done** | [run 38316367328](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38316367328), artifact `validation-38316367328`; see "M4 evidence" |
| M5 Proposed Rajistics registration config + peak-disk evidence for Codex review | todo | none yet |

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

**Benchmark: time to first meaningful test (TTFMT).** The clock starts before `prepare-workspace` and stops when the
regression test is classified `ASSERTION_RED` at base. Both modes ran on the same runner, at the same base SHA,
with the same test file, each in a fresh sandbox with an empty inner Docker. n=1 per mode.

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
- Rajistics: not used for building. No changes made there, and Raj's existing ~50 GB image is untouched.

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
- No Rajistics pulls or registration, no automation deployment, and no messages to humans.

## Next steps

1. **M5, docs only (in progress next).** Write `env/rajistics/` as **proposed, not applied** registration
   material for Codex and Raj to review:
   - the sandbox-spec / warm-pool entry for the current digest
   - sizing: about 4 GB of inner-Docker disk on top of the 6.24 GB image, with 2 vCPU / 8 GB as the floor
     measured here
   - the image-pull secret requirement for a private GHCR package
   - the manual-trigger launcher contract
   - the evidence each step must produce

   Nothing is registered or pulled on Rajistics until Raj approves.
2. **Optional benchmark fidelity:** repeat the bench n≥3 per mode, and try pre-seeding inner Docker images to
   remove the 27.5 s `docker load`. Report it separately from the n=1 headline.
3. **Before any live agent demo:** move or delete `reference/fix-recently-paid` (see Deviations).

## Blockers / open risks

- **Nothing blocks M5.** Rajistics registration and the live agent run are gated on Raj's approval, and are not
  blocked technically as far as is known.
- **Resolved:** GitHub-hosted runner disk was enough. Peak build increase was 12.6 GB; validation ran on the
  same runner class.
- **Resolved:** nested `dockerd` works on GitHub-hosted runners with `--privileged`, so the EC2 fallback was not
  needed and no AWS resources were created.
- **Open, Rajistics-specific and untested:**
  - whether Sysbox there gives `openhands` a working `dockerd` with this image's sudo path
  - inner data-root placement and size limits
  - pull time of the 2.27 GB image on its nodes
  - whether a private GHCR package needs an image-pull secret there
- **Transient:** one CI run (38305390512) failed when every `static.crates.io` download timed out inside the
  events-svc build. The same build passed in the concurrent and later runs. Cargo now retries with fewer
  connections.
