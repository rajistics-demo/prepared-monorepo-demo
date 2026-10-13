# Rajistics registration (M5) and live demo (M6) runbook

Status 2026-10-12: **blocked at precheck, nothing applied.** Read-only gate output is in
`../../../rajistics-evidence/2026-10-12/precheck-3.txt` (outside this repo).

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
- **No ~50 GB image on the node.** Containerd holds 50 images totalling 19.5 GB; the largest is 1.6 GB. The
  workload image Raj asked us to protect is `v1_current` (`agent-server:1.50.1-python`, 1.2 GB), which is in use
  by the warm pod and sessions.
- **Can the pull evict it?** Even a full, non-deduplicated pull (2.27 GB compressed + 6.24 GB unpacked) stays far
  below the GC trigger, so pulling cannot cause GC to evict it.

## Smallest scoped remedies (each needs Raj's decision; none applied)

1. **Pull auth.** Pick one:
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
2. **Runtime-api admin.** Enable the warm-config admin API through the documented Admin Console setting that
   provisions `admin-password` (`WARM_RUNTIME_CONFIG_OVERLAY=1` is already on).
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
- **Agent prompt:** the bug report and expected behavior only.
  - `reference/fix-recently-paid` is deleted or moved first. Otherwise reference exposure is disclosed.
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
