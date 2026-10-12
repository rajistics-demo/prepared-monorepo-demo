# server/ (Rails 8.1, Ruby 3.4.11)

## In a prepared OpenHands sandbox

Your task workspace is already prepared:

- a private checkout at the task commit
- installed gems
- three PostgreSQL servers (14, 16 and 17) and `events-svc`
- test databases restored only for this task

Use it:

```bash
# ports, bundle path, Compose project; sets OH_TASK_DIR and OH_REPO
source "${OH_TASK_ROOT:-/workspace/project/oh-tasks}/current/state/env.sh"
cd "$OH_REPO/server"
bin/rails test test/queries          # or a single file
```

Do not run `docker compose down`, `oh-cleanup` or `dev:bootstrap` in a
prepared task. The launcher owns teardown.

## Fixing a bug: the expected protocol

1. Reproduce. Write a regression test in a **new** file under `server/test/`
   that encodes the expected behavior from the task.
2. Run it with `oh-phase red --tests <file>`. It must fail on an assertion
   (not an error or a missing database). Commit the test alone.
3. Fix the application code under `server/app/` (or `server/lib/`, excluding
   `lib/tasks/dev_bootstrap.rake`). Do not change the test after step 2.
4. Run `oh-phase green --tests <file>`, then `oh-phase suite`. Commit the fix.
5. Report both commit SHAs. Acceptance comes from an independent verifier
   run in fresh databases, not from your own green run.

Never skip, weaken or delete tests to get green.

## Outside a prepared sandbox

See the repository `README.md` (`bundle install`, `docker compose up -d --wait`,
`AUTH_MODE=none bin/rails dev:bootstrap`).
