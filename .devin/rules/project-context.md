---
description: Scoredrop architecture and domain context
trigger: model_decision
---

# Scoredrop Architecture

Scoredrop is a self-hosted sport event notifier built with Rails 8.1.4, Ruby 4.0.7, and PostgreSQL. It polls the free sportscore.com widget API for subscribed teams and sends ntfy push notifications on match start (primary), goals, and fulltime. It is single-tenant — there is no authentication; it is meant to run on a LAN or behind a private reverse proxy.

## Core architecture

- `Sportscore::Client` (`app/services/sportscore/`) is the only data source: `GET /api/widget/{team,match,standings}` — no API key, ~60s edge cache, ~10k req/day limit.
- `Poller` (`app/services/poller.rb`) runs as a thread inside the Puma process (started by `config/initializers/poller.rb` under `Rails::Server`; `POLLER_ENABLED=false` disables). Adaptive interval: fast while a tracked match is live/near kickoff, slow otherwise.
- `Ntfy::Publisher` posts to a configurable ntfy server (URL + topic + optional Bearer token).
- `Setting` is a single-row model holding ntfy/notify/polling/sport config — re-read each poll cycle so UI edits need no restart.
- `Subscription` rows hold `team_slug` (+ cached name/logo). `Match` rows track fixtures with `notified_*` timestamps; `NotifiedIncident` dedupes goal notifications.
- `TeamDirectory` discovers teams via the standings endpoint (which returns `team_slug`); there is no teams-listing endpoint in the API.

## Organization

- Services live in `app/services/` (`poller.rb`, `team_directory.rb`, `sportscore/`, `ntfy/`).
- Web UI is intentionally minimal ERB: `StatusController` (`/`), `TeamsController` (`/teams`), `SettingsController` (`/settings`), sidebar layout.
- Minitest under `test/`; no fixtures — tests build records directly and use fake client/publisher classes.
- Docker: `Dockerfile` embeds postgres (PGDATA on `/data` volume); `bin/docker-entrypoint` initdb/starts it, persists `SECRET_KEY_BASE` on the volume, seeds `config.yml` for one-time import.

## Domain considerations

- Match urls differ per sport: `/football/match/{slug}/{id}/` vs `/cricket/match/{slug}/` — `Match.key_for`/`slug_for` handle both; id-less urls include the kickoff date in the key because fixtures repeat.
- A match first discovered as `finished` must NOT send a fulltime notification (would spam on subscribe); only finishes tracked from live/upcoming notify.
- API edge cache means statuses can disagree between endpoints and lag real time ~1-3 min.
- Team slugs are user-facing input: `barcelona` is Barcelona de Guayaquil, not FC Barcelona (`fc-barcelona`) — always verify via the directory/lookup path.

Use `/rails-implementation` for changes, `/review` for risk review, `/migration-review` for migrations.
