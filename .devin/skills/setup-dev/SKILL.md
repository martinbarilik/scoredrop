---
name: setup-dev
description: Guide scoredrop development setup without making privileged system changes automatically
argument-hint: '[setup area or problem]'
triggers:
  - user
permissions:
  deny:
    - Exec(sudo)
---

Help the user set up the scoredrop development environment safely.

1. Check current state with non-destructive commands before proposing changes.
2. Toolchain: `mise.toml` pins Ruby 4.0.7 and `BUNDLE_PATH=vendor/bundle`. `mise trust` + `mise install`, then `gem install rails -v '~> 8.1.0'` if `rails` is missing, then `bundle install`.
3. Database: local postgres at `127.0.0.1:5432`, user `martin` (credentials via `~/.pgpass`). Databases: `scoredrop_development`, `scoredrop_test`. `PGHOST`/`PGPORT`/`PGUSER`/`PGPASSWORD` env overrides are supported in `database.yml`.
4. App: `bin/rails db:create db:migrate`, then `bin/rails server` (poller in-process; `POLLER_ENABLED=false` to disable) or `bin/dev`.
5. Docker path: `docker compose up --build` — embedded postgres, `/data` volume, port 3000→80.
6. ntfy: needs URL + topic (+ token if the server requires auth) on `/settings`; a test publish can be run via `bin/rails runner` with `Ntfy::Publisher`.
7. Never execute `sudo`, edit system config, or alter certificates. Show the command and ask the user to run it.
8. Never place secrets in tracked files or conversation output.
9. Report completed checks, user-run steps, and a verification command per stage.
