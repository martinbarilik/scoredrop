---
description: Set up development environment
---

# Development Environment Setup

> Legacy reference only. Use `/setup-dev` for current guidance. Privileged commands must be run by the user.

## Toolchain

1. **mise** (pins Ruby 4.0.7, `BUNDLE_PATH=vendor/bundle`)

   ```bash
   mise trust
   mise install
   gem install rails -v '~> 8.1.0'
   ```

2. **Gems**

   ```bash
   bundle install
   ```

## Database

PostgreSQL is required (local instance at `127.0.0.1:5432`, user `martin` — uses `~/.pgpass`). `database.yml` honors `PGHOST`/`PGPORT`/`PGUSER`/`PGPASSWORD`.

```bash
bin/rails db:create db:migrate
```

Databases: `scoredrop_development`, `scoredrop_test`.

## Run

```bash
bin/rails server    # or bin/dev — poller thread starts in-process
POLLER_ENABLED=false bin/rails server   # web only
```

Status page: http://localhost:3000 · health: http://localhost:3000/up

## Configure

Open `/settings` → set ntfy URL + topic (+ token if the server requires auth). Add team subscriptions via `/teams`.

## Tests

```bash
bin/rails test
```

## Docker alternative

```bash
docker compose up --build   # embedded postgres, /data volume
```
