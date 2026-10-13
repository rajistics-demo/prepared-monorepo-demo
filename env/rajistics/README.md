# Rajistics registration (M5) and live demo (M6) runbook

Status 2026-10-13 02:50Z: **blocked at precheck, nothing applied on Rajistics.** Two Raj-only browser steps
remain:

1. Make the two GHCR packages public. Raj approved this; GitHub offers only a UI path (see below).
2. Set the Runtime API Admin Password ([`admin-setting.md`](admin-setting.md)).

Read-only gate output is in `../../../rajistics-evidence/2026-10-12/precheck-3.txt` (outside this repo).

## What is proposed

Add one warm runtime config **beside** the existing `v1_current`. Nothing else changes.

| Field | Value |
|---|---|
| name | `prepared-monorepo` (the only name `warm-config.sh` will save or delete) |
| image | `ghcr.io/rajistics-demo/prepared-monorepo-sandbox@sha256:b56261749a2f17542e45182f6006d1909f0e8fd03b46c919b2a58bc60a4fd9e0` |
| template | the CLI's documented template for the image, unchanged apart from name/image/count |
| warm count | 0 for the demo, so no idle pod or pull until a sandbox is requested; 1 only if Raj wants it pre-warmed |
| resources | the global sandbox defaults (1000m CPU, 2048Mi, 10Gi ephemeral). The schema has no per-config override |

Not touched: `v1_current`, its image `agent-server:1.50.1-python`, the global default image, resource defaults,
pull secrets, automations, Git Sync and running sessions.

Tools:

- **`ssm-run.sh <mode> [args]`** runs `node/warm-config.sh` on the node through SSM (AWS-RunShellScript) and
  propagates its exit code.
- **`warm-config.sh`** wraps the official `runtime-api-configs` CLI. It takes the source from
  OpenHands/extensions `main`, pinned by commit and reviewed.
  - The ownership marker for the config is the exact name plus the exact demo image digest. Any other config
    with that name is a collision, and the wrapper aborts.
  - `save` checks, in order: `precheck`, then a before-snapshot, then ownership, then save, then an
    after-snapshot. `delete` requires `STATE owned`.

## Gate results (SSM `a189512e`, 2026-10-12)

| Gate | Result | Evidence |
|---|---|---|
| Digest-pinned image | ok | |
| Disk | ok | details below |
| Ownership | ok | `STATE new`: no config named `prepared-monorepo` |
| Pull | **FAIL** | both GHCR packages are private (anonymous token 401, manifest 403). The only pull secret the runtime uses is the Replicated proxy secret `openhands-registry`; every current image comes through `images.r9.all-hands.dev/proxy/...` |
| Runtime-api admin | **FAIL** | the `admin-password` secret is empty; `GET /api/admin/challenge` returns 403 "Admin functionality is disabled". The warm-config CLI cannot authenticate, so nothing can be saved through the supported path |

Disk gate details:

- **Root volume:** 310.9 GB, 37.9% used, 193 GB free. kubelet image GC high threshold 85%, hard eviction
  `nodefs.available` 15%, both defaults (no overrides in the kubelet config).
- **Estimated incremental peak:** 26.4 GB, made up of:
  - the new image's compressed and unpacked layers not shared with the cached 1.50.1 base (1.07 GB + 3.00 GB)
  - 3 concurrent sandboxes at 5.67 GB each (inner Docker 4.67 GB plus task data)
  - a 25% margin
- **Projected peak:** 46.4% used, under the wrapper's 70% cap and well below the GC threshold. The 70% cap is a
  policy margin, not measured capacity.
- **The ~50 GB image Raj mentioned has not been found. Its location is unverified.** It must not be equated with
  `v1_current`. Bounded, metadata-only reads, 2026-10-13 02:31-02:45Z:
  - **Outer containerd:** 50 images totalling 19.5 GB; the largest is 1.5 GiB.
  - **Nested Docker:** `/var/lib/sysbox` holds 151 KB. No host Docker is installed.
  - **Large directories:** `/var/lib/embedded-cluster/k0s` 96.6 GB (containerd content, snapshots and pod
    writable layers; no single image is that size). PV root 33.0 GB, largest PVC 14.0 GB.
  - **Other hosts:** EC2 describe shows a **stopped** `replicated-openhands` instance (`i-0ec7a418dcb06cfcc`,
    200 GB gp3) and unattached 50 GB volumes. They were not started or inspected, and might hold it.
  - **Disk use fell today:** from 227G (79%, planning read on 2026-10-12) to 110G (38%). The journal shows
    7,384 volume teardowns since 2026-10-12, but routine cronjob pods are included, so that count doesn't
    pinpoint the cause.
  - Today's planning record listed 98 paused sandboxes; 12 sandbox Deployments remain, all created
    2026-10-11 or later. That is consistent with runtime-api deleting paused sandboxes and their PVCs at its
    86,400 s deletion time.
  - None of this was caused by us: every task action on Rajistics was read-only.
  - **Likely referent, from agent memory (unconfirmed by Raj):** the 2026-08-15 Root POC custom image.
    - ECR digest `sha256:c285ebc5…`, 53.16 GB compressed / 55.48 GB expanded.
    - It ran on a *separate* install (`app.replicated-monorepo.rajistics.com`, host `rajiv-monorepo-poc`), not on
      this node.
    - Memory records that its ECR repository was removed on 2026-08-21 and the POC host later destroyed.
    - Read-only checks on 2026-10-13 are consistent with that: no `rajiv-monorepo-poc` instance, and no ECR image
      over 20 GB in us-west-2 or us-east-1 (us-west-2 has no repositories).
    - If this is the image Raj means, it is not on Rajistics and this rollout cannot affect it.
  - If the image lived inside a sandbox (its PVC or nested Docker), it may have been reclaimed before this work
    started. Only Raj can say where it was.
- **The new pull alone can't trigger GC.** A full, non-deduplicated pull (2.27 GB compressed + 6.24 GB unpacked)
  stays far below the 85% image-GC trigger.

## Smallest scoped remedies (each needs Raj's decision; none applied)

1. **Pull auth.** **Raj chose (a) on 2026-10-13.**
   - **Why it's still pending:** GitHub has no REST endpoint for package visibility, only the package settings
     UI. The agent's browser has no GitHub session, and `GITHUB_TOKEN` lacks package scopes.
   - **Handoff:** for each package, open its settings page → Danger Zone → **Change visibility** → Public, then
     type the package name to confirm.
     - https://github.com/orgs/rajistics-demo/packages/container/prepared-monorepo-sandbox/settings
     - https://github.com/orgs/rajistics-demo/packages/container/prepared-monorepo-events-svc/settings
   - **Irreversible:** making a package public cannot be undone.
   - **Org policy:** if the Public option is unavailable, the organization's package-creation policy must allow
     public packages.
   - **Verify afterwards:** `anon-head.sh` must return HEAD 200 for both pinned digests (baseline in
     `anon-head-before-visibility.txt`: no anonymous token, HEAD 401).

   The three options considered:
   - **(a) Make the two GHCR packages public.**
     - What's in them: the contents are synthetic, gitleaks-scanned, and carry no credentials or seed secrets.
     - What it changes: package visibility only.
     - Raj's call: he owns the `rajistics-demo` org.
   - **(b) Proxy the images through the Replicated vendor registry**, the same path `v1_current` already uses.
     - What it changes: vendor-side image configuration.
     - Effect on the cluster: no new in-cluster credential.
   - **(c) Add a `ghcr.io` pull secret in the runtime namespace**, holding a read-only `read:packages` token, and
     have runtime-api attach it.
     - Credential: creates a new credential.
     - Unverified: whether runtime-api 0.10.0 supports attaching a per-registry pull secret.
     - Recommendation: least preferred.
2. **Runtime-api admin.** Set **Config → Sandbox Configuration → Runtime API Admin Password** (`admin_password`).
   - Full evidence, expected diff, restart impact (4 pods roll; sandboxes untouched) and handoff are in
     [`admin-setting.md`](admin-setting.md).
   - `WARM_RUNTIME_CONFIG_OVERLAY=1` is already on.
   - This is a deployment-setting change and reconciles runtime-api.
   - Not attempted: no `kubectl patch`, no `set env`, no hand-made secret.
   - **Alternative that is not additive:** setting the custom image in the Admin Console sandbox-image field
     would change the default for every conversation, so it is out of scope.

## Apply and roll back (only after both gates pass)

```bash
# from repo root; INSTANCE_ID / AWS_REGION as in ssm-run.sh
env/rajistics/ssm-run.sh precheck <digest-ref>   # must print precheck_exit=0
env/rajistics/ssm-run.sh save <digest-ref> 0     # snapshot before, save, snapshot after
env/rajistics/ssm-run.sh snapshot                # v1_current must be byte-identical to the before snapshot
# rollback
env/rajistics/ssm-run.sh delete                  # refuses unless STATE owned
```

Record the SSM command IDs, the before and after snapshots, and the saved config in BUILD-STATUS.

## M6 acceptance (live demo, after M5)

- **Sandbox:** started from `prepared-monorepo` through the supported per-conversation sandbox-spec path.
  - A narrow launcher is allowed only if the automation preset can't select it. Label it as proposed
    orchestration.
  - Check the image digest the pod actually runs.
- **Sysbox:** `dockerd` comes up under Sysbox as `openhands`.
  - Record the inner data root, `df`, `memory.events` and ephemeral-storage usage.
  - Any OOM or eviction stops the run.
- **Task isolation:** two tasks in one sandbox each see only their own markers in all three databases.
- **Cross-sandbox probe:** a second sandbox can't see the first one's containers, volumes or ports. Record which
  credentials each sandbox carries; this is observed, not claimed.
- **Memory envelope:**
  - CI envelope run [38337793281](https://github.com/rajistics-demo/prepared-monorepo-demo/actions/runs/38337793281)
    passed: full prepared verify PASS at 1 CPU / 2048Mi / no swap, agent-server live, 0 OOM kills, ephemeral 3.07
    GB of 10Gi.
  - **But it hit `memory.max` 2,219 times.**
  - So the plan is to run the demo agent with terminal, file editor and task tracker only, no browser tool
    (Chromium).
    - Mechanism: a new demo-owned agent profile `prepared-monorepo-demo` with that `tools` list, passed as
      `agent_profile_id` on `POST /api/v1/app-conversations`.
    - The 1.68.1 OpenAPI has `OpenHandsAgentProfile.tools` and `AppConversationStartRequest.agent_profile_id`. That
      is schema-verified, not live-tested.
    - The profile is never activated as Raj's default, and is deleted at cleanup.
    - If the server ignores the tool list, the browser tool's presence is disclosed and memory watched.
  - Any `oom_kill > 0` live stops the run.
- **Agent prompt:** the bug report and expected behavior only.
  - `reference/fix-recently-paid` is deleted or moved first. Otherwise reference exposure is disclosed, using the
    verbatim text in BUILD-STATUS (Blockers), and no blind-solve claim is made. As of 2026-10-13 the default is
    disclosure, because the repo is public.
- **Agent work:**
  - writes the regression test
  - shows an `ASSERTION_RED` at base
  - fixes the code and runs the DB-backed tests
  - pushes a new `demo/*` branch and opens a draft PR
- **Fresh verification:** `oh-verify --mode prepared` runs on the published SHA in a new task, with freshly
  restored databases. The agent's own green result is informative only.
- **Retained evidence:** conversation URL, diff, verifier JSON, SHA and digest.
- **Cleanup:** `oh-cleanup` for demo tasks, stop the demo sandboxes, `delete` the warm config if Raj doesn't
  want to keep it.
- **Always true:** `AUTH_MODE=none`; Root SSO and ECR stay unresolved. Any TTFMT measured on Rajistics is
  reported separately as n=1.
