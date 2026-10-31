---
description: Deploy the application
---

# Deployment Workflow

> Legacy reference only. Use `/deploy` for the current guarded checklist. Do not execute production commands automatically.

Scoredrop deploys as a self-contained Docker image (embedded postgres). StartOS packaging is a separate repository — not built from this one.

1. **Build**

   ```bash
   docker build -t scoredrop .
   ```

2. **Run**

   ```bash
   docker compose up -d
   ```

   `docker-compose.yml` maps host port 3000 and persists `/data` (postgres data, `secret_key_base`, optional `config.yml` import).

3. **Migrations**

   `bin/docker-entrypoint` runs `db:prepare` on boot — no manual step. Back up the `/data` volume before schema-affecting deploys.

4. **Post-deploy checks**

   - `curl http://<host>:3000/up` → `200`
   - Status page shows a recent "Last poll"
   - Logs show `[poller] started` and clean ticks (no repeated error lines)
   - `/settings` has a valid ntfy URL/topic/token — send a test notification
