# Enabling the runtime-api warm-config admin API on Rajistics

Status: **prepared, not applied.** Raj must enter the credential himself.

## The setting

| | |
|---|---|
| Where | Admin Console, `https://admin.<base-domain>:30000` → **Config** → group **Sandbox Configuration** → **Runtime API Admin Password** |
| Config key | `admin_password`. Type `password`, no `when` condition, so it is always shown |
| Source, release-matched | OpenHands-Cloud `replicated/config.yaml` at tag `openhands/0.76.0` (`b26e442`), lines 1408-1412. Identical on `main` as of 2026-10-13 |
| Docs | [multiple-images-warm-pools](https://docs.openhands.dev/enterprise/custom-sandbox-images/multiple-images-warm-pools) Step 1 (VM Install). Its troubleshooting table maps `HTTP 403: Admin functionality is disabled` to this field |
| Installed release, live | Helm `openhands` rev 29, chart `openhands-0.76.0`, app `1.68.1`; `openhands-secrets` 0.1.24 rev 29. Both deployed 2026-10-05 20:24Z |

## Current state (live, metadata only)

- The `openhands/admin-password` Secret exists. Its single key `admin-password` is **empty**. The value was not
  read beyond the empty/set flag.
- `openhands-runtime-api` sets `ADMIN_PASSWORD` from `secretKeyRef admin-password/admin-password`. Its pod
  template carries `checksum/admin-password`.
- **Why the API is off:** runtime-api 0.10.0 (`management_fastapi.py` at `v0.10.0`/`aa95d4c`) treats an empty
  password as unset. The admin routes therefore return 403, matching `GET /api/admin/challenge` →
  `{"error":"Admin functionality is disabled"}`.
- **Why it's empty (unverified):** the config template default is `{{repl RandomString 32}}`, so the install or
  upgrade path left it blank. The likeliest cause is that the item was added after the original install.

## Proposed change

- **Change:** set `admin_password` to a new random value of at least 24 characters. Change **no other field.**
- **Who enters it:** Raj generates the value in his password manager and types it into the browser field.
  - It never goes into chat, files, git or SSM output.
  - Afterwards, `env/rajistics/node/warm-config.sh` reads it on the node from the Secret into the CLI's
    environment. It never echoes it.
- **Admin Console steps:** Save config → review the diff → Deploy → wait for Dashboard `Ready`.

**Expected diff.** Abort if the review shows anything else, for example a version change or other values.

| Object | Change |
|---|---|
| Release `openhands-secrets`: Secret `admin-password` | data changes |
| Release `openhands`: pod-template annotations | changes in 4 Deployments only |
| ↳ `openhands-runtime-api` | `checksum/admin-password` (source: `openhands.yaml:335`) |
| ↳ `openhands`, `openhands-integrations`, `openhands-mcp` | `checksum/config-secrets`. `admin_password` is one of the `secretsChecksum` inputs (`openhands.yaml:557`), and the chart templates add that annotation to these 3 Deployments |
| Everything else | unchanged. LiteLLM's `checksum/litellm-credentials` does not include `admin_password` |

## Restart and session impact

**What rolls.** Four pods restart. Each runs 1 replica with a surge-first rolling update, so a new pod becomes
Ready before the old one stops:

- `openhands`, `openhands-integrations` and `openhands-mcp`: 25%/25% rounds to maxUnavailable 0, maxSurge 1.
- `openhands-runtime-api`: 0/1.

**What users notice.** UI websockets reconnect, and a few seconds of app-server, MCP and integration-event
handoff. During the runtime-api swap, sandbox start or resume calls may need a retry.

**Not touched** (live: none of these are in the Helm releases):

- The 12 sandbox Deployments, which runtime-api creates (`managed-by` unset); 2 are running.
- Their PVCs.
- `agent-canvas`, `automation`, `plugin-directory`, Laminar, LiteLLM, MinIO, Keycloak and PostgreSQL. None
  carries an affected checksum.
- The `v1_current` warm config and its pod.

runtime-api 0.10.0 has no startup hook (`main.py` defines no lifespan or startup handler). Warm-pool, reaper and
garbage work run as separate jobs, so the restart does not reconcile or delete runtimes. (Source-verified.)

**Residual risk, unverified live:**

- An automation run or conversation active during the app-server swap may see transient callback errors.
- Mitigation: deploy when no automation run is in flight. At 02:31Z one session sandbox was running; its pod
  started 02:01Z. Afterwards confirm:
  - both pre-existing sandbox pods have unchanged start times
  - `v1_current` is byte-identical to `../rajistics-evidence/2026-10-12/warm-config-snapshot-before.txt`

**Rollback.**

- **How to disable again:** redeploy the previous Admin Console sequence from Version history. That rolls the
  same four pods.
- **Don't rely on clearing the field.** What KOTS does with a cleared `password` item whose `value` template is
  `RandomString` is unverified.
- **Leaving it enabled is low-risk:** admin routes require the password through a PBKDF2 challenge, and each
  challenge is single-use and expires after 5 minutes (per the docs' troubleshooting section).

## Scoped alternative if Raj declines the restart

There is no supported additive path without the admin API: the warm-config overlay is written only through it.
The Admin Console sandbox-image field would change the default for every conversation, which is out of scope.
Without the change, the live demo can't run on Rajistics.
