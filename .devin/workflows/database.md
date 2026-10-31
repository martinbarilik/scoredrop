---
description: Database operations
---

# Database Workflow

> Legacy reference only. Use `/database` for guided operations with destructive-command safeguards.

## Environments

- **Development/test**: local postgres `127.0.0.1:5432`, user `martin` (`~/.pgpass`), databases `scoredrop_development` / `scoredrop_test`. Env overrides: `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`.
- **Docker**: embedded postgres inside the container, PGDATA on the `/data` volume — back up the volume rather than dumping in place where convenient.

## Common tasks

```bash
bin/rails db:migrate:status    # pending migrations
bin/rails db:migrate           # development
bin/rails runner 'Match.count; Subscription.count'   # quick state probe
```

## Safety

- Never run `db:drop`, `db:reset`, `dropdb`, or `pg_dropcluster` — treat as destructive; require explicit user confirmation and a backup.
- Truncating `matches`/`notified_incidents` resets notification dedupe — the poller may re-notify; warn the user.
