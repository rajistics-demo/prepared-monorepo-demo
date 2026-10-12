# Build status: prepared-monorepo-demo

Last updated: 2026-10-12 (Opus 5.5 in Agent Canvas; Codex supervising).
Plan: `/Users/rajiv.shah/Code/install_replicate/demo-plans/root-monorepo/technical-plan.md`
(+ `evidence-and-decisions.md`). This file is the single place to check progress.

## Current milestone

**M1: source and environment tooling written, not yet executed.** Nothing in
M1 has been run end to end yet. No test, image or timing results exist, and
none are claimed.

| Milestone | State | Evidence |
|---|---|---|
| M0 Repo + Gemfile.lock resolved in CI | done | runs [38303322879](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38303322879), [38303482984](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38303482984) on branch `bootstrap/lockfile`; lock is Ruby 3.4.11, Bundler 2.6.9, platform `x86_64-linux-gnu` only |
| M1 Rails server, events-svc (Rust), env tooling | written locally, uncommitted | `server/`, `services/events-svc/`, `env/` |
| M2 CI: server suite on PG 14/16/17, cargo test, red at base / green at fix | next | none yet |
| M3 Fixtures, toolchain + prepared images, size report | todo | none yet |
| M4 Off-instance validation inside the image (nested dockerd, prepare, isolation probe, oh-verify, induced-failure rollback, cold vs prepared timing) | todo | none yet |
| M5 Proposed Rajistics registration config + peak-disk evidence for Codex review | todo | none yet |

## Links

- Repo (private): https://github.com/rajistics-demo/prepared-monorepo-demo
  Its default branch is temporarily `bootstrap/lockfile` because it was the first branch pushed; it
  will be switched to `main` when `main` is pushed (a settings change on this new repo only).
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

1. Add the remaining source: `web/` and `mobile/` placeholders, repo `README.md`/`AGENTS.md`, bug scenario
   tag (`demo/base-v1` on `main`) and a reference fix on `reference/*` (excluded from the seed).
2. Add CI `ci.yml`: server suite against PG 14/16/17 service containers, `cargo test` for events-svc, and
   red-at-base / green-at-reference-fix as a pinned, bounded-permission workflow.
3. Commit and push `main` and switch the default branch. Run CI and fix until it is green for real.
4. CI `image.yml`: toolchain image, then fixtures through service containers, assemble the context, build
   the prepared image FROM the pinned base, push a new tag, and record compressed size, unpacked size
   and runner disk usage.
5. In-image validation workflow (`validate-image.sh`): nested dockerd, prepare, isolation probe,
   induced-failure rollback, oh-verify, plus cold vs prepared timings.

## Blockers / open risks

- None blocking right now.
- Risk: GitHub-hosted runner disk for a ~10 GB image plus `docker save` tarballs plus nested-Docker
  validation. This will be measured in step 4; the EC2 fallback applies only if that measurement fails.
- Risk: whether nested dockerd works on GitHub-hosted runners for in-image validation (needs
  `--privileged`). If it does not, M4 moves to the EC2 builder.
