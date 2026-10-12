# prepared-monorepo-demo

A small, **wholly synthetic** monorepo used to demonstrate OpenHands working
on a database-backed Rails bug inside a prepared sandbox image. It is an
*analog* of a customer setup, not a copy of it, and contains no customer code
or data.

```text
server/              Rails 8.1 API (the only module with real code and tests)
web/  mobile/        placeholders, so the repo has the shape of a monorepo
services/events-svc  small Rust service; owns the events database schema
env/                 prepared sandbox image, setup, fixtures, verifier
```

## What the server needs

`server/` talks to three PostgreSQL servers of different major versions:

| Logical DB | PostgreSQL | Owner of the schema |
|---|---|---|
| primary | 16 | Rails migrations (`db/schema.rb`) |
| ledger | 14 | Rails migrations (`db/ledger_schema.rb`) |
| events | 17 | `services/events-svc` (SQL migrations it applies at startup) |

Rails' multi-database test boot needs all three, and setup must wait for
`events-svc` to have migrated the events databases.

## Developer setup (the slow path)

```bash
cd server
bundle install
docker compose up -d --wait
AUTH_MODE=none bin/rails dev:bootstrap   # custom task that replaces db:setup
bin/rails test
```

`dev:bootstrap` runs an auth gate first (`bin/auth-check`). `AUTH_MODE` must be
set explicitly. `AUTH_MODE=none` is for this synthetic demo only and checks no
AWS credentials. **AWS SSO is not solved by this repo.** `AUTH_MODE=aws-sso`
fails closed unless a human has already logged in.

## Prepared path

`env/` builds an image `FROM` a pinned OpenHands agent-server release that
carries:

- a read-only git seed
- a keyed, pre-installed gem bundle
- the service images as tarballs
- keyed database fixtures

`prepare-workspace --sha <commit>` then gives each task:

- its own checkout
- its own Compose project
- databases restored privately for that task

`oh-verify` re-checks a fix at exact SHAs in fresh tasks. See `BUILD-STATUS.md`
for what has actually been built and measured.
