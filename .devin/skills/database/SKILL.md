---
name: database
description: Inspect and guide scoredrop PostgreSQL operations with strict safeguards
argument-hint: '<status, migration, backup, or restore task>'
triggers:
  - user
permissions:
  deny:
    - Exec(pg_dropcluster)
    - Exec(dropdb)
    - Exec(rake db:drop)
    - Exec(rails db:drop)
    - Exec(rake db:reset)
    - Exec(rails db:reset)
---

Handle scoredrop database tasks conservatively.

1. Establish the environment and database first. Development/test use the local postgres at `127.0.0.1:5432` as user `martin` (databases `scoredrop_development`, `scoredrop_test`). The Docker image runs an embedded postgres whose PGDATA is `/data/postgres` — never wipe it in place of a restore.
2. Start with read-only inspection: `bin/rails db:migrate:status`, schema review, `psql` selects.
3. Migrations run via `bin/rails db:migrate` (dev) — never hand-edit `schema.rb`.
4. Treat restores, rollbacks, truncation, deletion, and bulk updates as destructive: describe the exact command, target, and impact, then wait for explicit confirmation.
5. Never execute `pg_dropcluster`, `dropdb`, `db:drop`, or `db:reset` through this skill.
6. Never expose database passwords or `.pgpass` contents.
7. Report inspected state, commands run, affected environment, and verification steps.
