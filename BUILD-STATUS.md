# Build status: prepared-monorepo-demo

Last updated: 2026-10-12 (Opus 5.5 in Agent Canvas; Codex supervising).
Plan: `/Users/rajiv.shah/Code/install_replicate/demo-plans/root-monorepo/technical-plan.md`
(+ `evidence-and-decisions.md`). This file is the single place to check progress.

## Current milestone

**M3 in progress: the `image.yml` run is iterating on GitHub runners. M4 (`validate.yml`) is written and waits
for the first published image digest.**
The cold-path CI timings below are CI facts only. They are not the benchmark: no
prepared-vs-cold measurement exists yet.

| Milestone | State | Evidence |
|---|---|---|
| M0 Repo + Gemfile.lock resolved in CI | done | runs [38303322879](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38303322879), [38303482984](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38303482984) (`bootstrap/lockfile`); Ruby 3.4.11, Bundler 2.6.9, `x86_64-linux-gnu` only |
| M1 Rails server, events-svc (Rust), env tooling | done | `main` @ `5263a4b` |
| M2 CI: secret scan, server suite on PG 14/16/17, cargo test, red/green verifier + negative control | **done** | [run 38305813482](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38305813482) (`main`), [run 38305818289](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38305818289) (`reference/fix-recently-paid`), artifact `verifier-evidence` |
| M3 Fixtures, toolchain + prepared images, size report | **in progress** | See "M3 run log" below |
| M4 In-image validation (nested dockerd, prepared mode, isolation probe, induced-failure rollback, cold vs prepared timing) | written, not run | `.github/workflows/validate.yml`, `env/scripts/bench-ttfmt.sh` |
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
| [38310817702](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38310817702) | `54706f0` | **green: every gate passed, images pushed** | |

**M3 outputs (run 38310817702, artifact `image-report`):**

- **Prepared image:** `ghcr.io/rajistics-demo/prepared-monorepo-sandbox@sha256:3bd77810511472c318ac3348fd60bc461d8580d98a033f1493a124164a8fe377`
  (tag `54706f05e794-r38310817702-1`)
- **events-svc:** `ghcr.io/rajistics-demo/prepared-monorepo-events-svc@sha256:306f36710a2a9ceacd442053fef46af294406a175f455a48dd1678f0cb440614`
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
- Images: none published yet. Planned: `ghcr.io/rajistics-demo/prepared-monorepo-sandbox` and
  `ghcr.io/rajistics-demo/prepared-monorepo-events-svc`, new tags only, never overwritten.

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

1. Finish M3: get one green `image.yml` run, then record the digest, compressed and unpacked sizes, and peak
   runner disk from its `image-report` artifact.
2. M4: dispatch `validate.yml` with `image=<that digest>`. On a GitHub runner, `--privileged` plus a
   per-container `/var/lib/docker` volume stands in for Sysbox. It checks:
   - entrypoint health
   - `sudo` and `dockerd`
   - two concurrent prepared tasks plus the marker-write isolation probe
   - induced failure at `services_db`, leaving no containers or volumes
   - `oh-cleanup` leaving nothing behind
   - `oh-verify --mode prepared` PASS plus the negative control
   - TTFMT benchmark: unprepared cold vs prepared cold, each in a fresh sandbox, same runner and base SHA, n=1

## Blockers / open risks

- None blocking right now.
- Transient: one CI run (38305390512) failed when every `static.crates.io` download timed out inside the
  events-svc build. The same build passed in the concurrent and later runs. Cargo now retries with fewer
  connections.
- Risk: GitHub-hosted runner disk for a ~10 GB image plus `docker save` tarballs plus nested-Docker
  validation. This will be measured in M3; the EC2 fallback applies only if that measurement fails.
- Risk: whether nested dockerd works on GitHub-hosted runners for in-image validation (needs
  `--privileged`). If it does not, M4 moves to the EC2 builder.
