---
name: deploy
description: Prepare a scoredrop Docker/self-host deployment checklist without deploying automatically
argument-hint: '[target environment]'
triggers:
  - user
permissions:
  deny:
    - Exec(sudo)
    - Exec(git push)
---

Prepare or review a scoredrop deployment; do not perform it automatically.

1. Confirm the target: local `docker compose`, a Docker host, or a future StartOS package (packaging is a separate repo — not this one).
2. Inspect repository status, migrations, and dependency changes since the running deployment.
3. Require a clean, reviewed commit (or explicit working-tree acknowledgement) before presenting deploy commands.
4. Build path: `docker build -t scoredrop .` → `docker compose up -d`. The image embeds postgres; the `main`/`/data` volume holds PGDATA, `secret_key_base`, and optional `config.yml` import.
5. Highlight migration impact and require a volume backup (or pg_dump) before schema-affecting deploys.
6. Post-deploy checks: `GET /up` returns 200, status page shows a recent "Last poll", poller log lines `[poller] started` / `notify`, and a test notification reaches the configured ntfy topic.
7. Stop on any failed prerequisite and report the blocker.
8. Return a checklist the user executes; never claim deployment succeeded without observed verification.
