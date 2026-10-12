# Agent instructions

## Module routing

- Most tasks touch one module. Work only in the module named by the task
  (`module: server`, `web` or `mobile`). If a fix seems to need another
  module, stop and say so instead of editing it.
- `server/` has its own `AGENTS.md`; read it before working there.
- `web/` and `mobile/` are placeholders with no build or tests.

## Never edit

`env/`, `.github/` and `services/` belong to the environment, not to tasks.
In `server/`, the bootstrap, auth gate, database config, schemas,
`test/test_helper.rb` and `test/support/` are environment files too. The
verifier rejects changes to them.

## Credentials

Never print, copy or commit credentials. `AUTH_MODE=none` is the only mode
this demo uses. Do not try to make AWS authentication pass, and do not
change `bin/auth-check`.
