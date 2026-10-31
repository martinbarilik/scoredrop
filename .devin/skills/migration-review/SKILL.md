---
name: migration-review
description: Review scoredrop Rails migrations for PostgreSQL safety without executing them
argument-hint: '<migration file or proposed schema change>'
triggers:
  - user
  - model
permissions:
  ask:
    - edit
    - write
  deny:
    - Exec(rake db:migrate)
    - Exec(rails db:migrate)
    - Exec(rake db:rollback)
    - Exec(rails db:rollback)
---

Review the migration or proposed schema change without editing files or running it.

1. Check reversibility, rollback limitations, and compatibility with existing application code.
2. Assess table locks, rewrites, long transactions, backfills, defaults, `NOT NULL`, index creation, and uniqueness enforcement.
3. Check foreign keys, data types, datetime semantics, and existing invalid or duplicate data.
4. Separate schema changes from large data backfills where production safety requires it.
5. Verify indexes match actual query predicates (e.g. `matches.status`, `matches.kickoff_at`, `matches.key` uniqueness).
6. For notification state columns (`notified_*`), confirm defaults preserve the "never notify twice / only observed transitions" invariants — a wrongly-defaulted flag can spam or suppress notifications.
7. Identify deployment ordering requirements for backward-compatible releases (the poller and web run in one process, but the Docker image may run an older schema mid-deploy).
8. Never execute migrations. Report blocking issues first, then safer alternatives and verification/rollback steps.
