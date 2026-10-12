# Build status: prepared-monorepo-demo

Last updated: 2026-10-12 (Opus 5.5 in Agent Canvas; Codex supervising).
Plan: `/Users/rajiv.shah/Code/install_replicate/demo-plans/root-monorepo/technical-plan.md`
(+ `evidence-and-decisions.md`). This file is the single place to check progress.

## Current milestone

**M2 done, with real CI evidence. M3 next: fixtures, toolchain and prepared images, size report.**
The cold-path CI timings below are CI facts only. They are not the benchmark: no
prepared-vs-cold measurement exists yet.

| Milestone | State | Evidence |
|---|---|---|
| M0 Repo + Gemfile.lock resolved in CI | done | runs [38303322879](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38303322879), [38303482984](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38303482984) (`bootstrap/lockfile`); Ruby 3.4.11, Bundler 2.6.9, `x86_64-linux-gnu` only |
| M1 Rails server, events-svc (Rust), env tooling | done | `main` @ `5263a4b` |
| M2 CI: secret scan, server suite on PG 14/16/17, cargo test, red/green verifier + negative control | **done** | [run 38305813482](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38305813482) (`main`), [run 38305818289](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38305818289) (`reference/fix-recently-paid`), artifact `verifier-evidence` |
| M3 Fixtures, toolchain + prepared images, size report | next | none yet |
| M4 In-image validation (nested dockerd, prepared mode, isolation probe, induced-failure rollback, cold vs prepared timing) | todo | none yet |
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

1. CI `image.yml` (M3):
   - Build the toolchain image.
   - Build the fixtures through service containers.
   - Publish events-svc to GHCR.
   - Assemble the context and build the prepared image FROM the pinned base.
   - Push new, immutable tags.
   - Record compressed size, unpacked size and runner disk usage.
2. In-image validation workflow (M4, `validate-image.sh`):
   - nested dockerd
   - prepared-mode prepare
   - isolation probe
   - induced-failure rollback
   - `oh-verify --mode prepared`
   - cold vs prepared timings on the same runner class

## Blockers / open risks

- None blocking right now.
- Transient: one CI run (38305390512) failed when every `static.crates.io` download timed out inside the
  events-svc build. The same build passed in the concurrent and later runs. Cargo now retries with fewer
  connections.
- Risk: GitHub-hosted runner disk for a ~10 GB image plus `docker save` tarballs plus nested-Docker
  validation. This will be measured in M3; the EC2 fallback applies only if that measurement fails.
- Risk: whether nested dockerd works on GitHub-hosted runners for in-image validation (needs
  `--privileged`). If it does not, M4 moves to the EC2 builder.
