# Scoredrop

Self-hosted sport event notifier. Polls the free
[sportscore.com widget API](https://sportscore.com/developers/) for subscribed
teams and pushes [ntfy](https://ntfy.sh) notifications when a match **starts**
(primary), on **goals**, and at **fulltime**. StartOS packaging will live in a
separate repo; run it anywhere with Docker or directly via Rails.

- Ruby 4.0.7 / Rails 8.1, PostgreSQL (embedded in the container)
- No API key required for sportscore.com
- Web UI: sidebar with **Subscriptions** (status page), **Browse teams**
  (subscribe/unsubscribe), **Settings** (ntfy + notifications + polling)
- `/up` health check

## Pages

| Page                  | What it does                                                                                                                                              |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/` Subscriptions     | Subscribed teams (with unsubscribe), tracked matches (25 per page — live first, then upcoming soonest-first, then finished most-recent), last poll status |
| `/teams` Browse teams | League selector: football competitions + verify-a-slug box, all NHL teams, or all Slovak Extraliga teams                                                  |
| `/settings` Settings  | ntfy server, notification toggles, reminder, poll intervals                                                                                               |

## Configuration

All settings live in the database (`settings`/`subscriptions` tables) and are
managed from the **Settings** page — changes take effect on the next poll
cycle, no restart needed.

For convenience, if `config/scoredrop.yml` (or `SCOREDROP_CONFIG`; `/data/config.yml`
in Docker) exists on **first boot**, its contents are imported once — teams,
ntfy settings, intervals — and the file is ignored afterwards. Team slugs
with `nhl-`/`svk-` prefixes subscribe to NHL / Slovak Extraliga; anything
else is football. See
[`config/scoredrop.yml.example`](config/scoredrop.yml.example) for the format.

### Finding team slugs

The API has no team-listing endpoint, so the **Browse teams** page offers two
ways to find one:

- **By competition** — reads league standings (which include real team slugs)
  for the configured competitions; subscribe with one click.
- **Verify a slug** — covers what standings can't: newly promoted or cup-only
  teams absent from a table, teams in leagues not listed, and guessed slugs.
  It resolves the slug via the team endpoint and shows the real name + logo
  before you commit. Example: Slovan Bratislava plays in the Slovak Fortuna
  liga — not among the configured competitions — but checking
  `slovan-bratislava` resolves it and offers Subscribe.

Careful with short names: `barcelona` is Barcelona de Guayaquil — FC Barcelona
is `fc-barcelona`. An unverified bad slug just errors on every poll
(`Team not found` as the status-page error). Verify before subscribing.

## How it works

### The poller

The poller is a plain Ruby thread inside the web process — there is no cron
job or job queue. `config/initializers/poller.rb` starts it `after_initialize`
whenever the app boots under `rails server` (which includes `bin/dev` and
Puma in Docker). Console, `runner`, and test sessions do not start it; run one
cycle manually with `bin/rails runner 'Poller.new.tick'`. Set
`POLLER_ENABLED=false` to run web-only.

Each cycle fetches every subscribed team's fixtures, then the loop sleeps for
an adaptive interval: `poll_interval_seconds` while a tracked match is live or
near kickoff, `idle_poll_interval_seconds` otherwise. HTTP requests to the app
never trigger polls — the thread is the only driver. API errors are isolated
per team, and the loop survives crashes (logs + retries). Last poll time and
the most recent error are shown on the status page.

### Notifications

Every poll cycle the app fetches each subscribed team's fixtures
(`GET /api/widget/team/`) and tracks matches from 48h ago to 7 days ahead.
The fixture feeds only reliably list _upcoming_ matches — a match that kicked
off keeps reporting "upcoming" (or disappears) — so for every live or due
match the poller fetches `GET /api/widget/match/` directly, which carries the
authoritative status, score, and incidents.

Some matches never reach the feeds at all: the team endpoint caps at 30
farthest-out fixtures and drops live ones entirely. Since match slugs are
derivable (`{team}-vs-{opponent}`), every 15 minutes the poller probes the
detail endpoint for league pairings (opponents come from the standings
endpoint) and picks up anything inside the tracking window. Pairings whose
fixture is already tracked are skipped — the probe only runs while no
unfinished match is on record for that pairing.

Notifications fire on state transitions:

| Event                    | Trigger                                                                |
| ------------------------ | ---------------------------------------------------------------------- |
| Starting soon (optional) | `upcoming` and kickoff within `remind_minutes_before`                  |
| **Kickoff**              | `upcoming` → `live`                                                    |
| Goal                     | new `is_goal` incident in match detail (score-diff fallback)           |
| Fulltime                 | transition to `finished` (only for matches tracked from live/upcoming) |

Polling is adaptive: fast (`poll_interval_seconds`, default 120s) while a match
is live or due to start within `live_window_seconds` (including delayed
kickoffs), slow (`idle_poll_interval_seconds`, default 900s) otherwise — well
under the API's ~10k requests/day allowance.

Notes:

- API responses are edge-cached ~60s, so notifications can trail real time by a
  minute or two.
- If an ntfy publish fails, the notification is retried on the next poll
  cycle — events are only marked notified after a successful publish.
- Match urls on some sports (e.g. cricket) carry no id segment; the same
  fixture repeats across dates, so the internal match key includes the kickoff
  date in that case.
- Football uses sportscore; NHL uses the official NHL JSON endpoints; Slovak
  Extraliga uses HockeySlovakia's public pages. Browse teams offers all three
  leagues and subscriptions can mix them.
- Run exactly one instance: the embedded postgres and in-process poller are
  single-process — a second replica would send duplicate notifications.

### Hockey: schedule-first notifications

All NHL and Slovak Extraliga teams are discovered from their sources. Select the league on Browse teams; no API key is required.
`NhlClient` fetches the team directory once daily and each subscribed team's
season schedule at most every 12 hours. Both are cached in PostgreSQL, so
restarts and browsing do not reset the request budget. Subscribing fetches
that team's schedule immediately unless an unexpired cache exists.

`HockeyPoller` checks local notification deadlines every minute without making
schedule requests. Optional reminders use the configured minutes-before-start
setting. At scheduled kickoff, a separate scheduled-start notification fires
(not a claim that play has actually begun); starts more than 30 minutes old
are not replayed after downtime. No live hockey goal polling is performed.

Only games whose scheduled kickoff was at least three hours ago need a result
request. NHL results are cached per game date for an hour, shared by all teams.
Slovak results are cached per match for an hour.
Unfinished games retry hourly for up to 48 hours after kickoff. Known postponed
or cancelled games are skipped. First-discovered finished games do not notify;
final notifications require the game to have been seen before it finished
(upcoming or in-progress). Failed ntfy
publishes remain pending for another local tick. Schedule failures retry after
an hour. Football keeps its existing adaptive polling independently.

Schedule changes are only detected on refresh, so a last-minute postponement
can still produce a scheduled-start notification. The NHL schedule state is
shown as provided by the last refresh, not a continuously updated live score.

Slovak Extraliga uses `SlovakHockeyClient` to read HockeySlovakia's public
schedule and match pages. It discovers the current season and all teams from
the site, fetches the entire league schedule at most twice daily (shared by
all subscriptions), and converts Slovak local times using Europe/Bratislava
including daylight saving. Fixtures with unknown midnight start times are
skipped. A displayed score is not enough to declare a final result: the match
page must explicitly say the game has ended. This HTML integration can break
if the site changes; parsing failures are logged rather than inventing data.
TheSportsDB is not used because its free endpoints returned sample or
incomplete data. Czech and other hockey leagues are not implemented yet;
each needs its own verified provider, reusing the same notification scheduler.

After updating an existing installation, run `mise exec -- bin/rails db:migrate`
before starting the app. The Docker entrypoint prepares migrations on startup.

## Run with Docker

```sh
docker compose up --build
```

- Status page: http://localhost:3000
- Data volume `/data`: embedded postgres, generated `secret_key_base`
  (override with `SECRET_KEY_BASE` env if you like), optional `config.yml`
  one-time import
- Served as plain HTTP — a TLS proxy (e.g. StartOS) may sit in front. Optional
  env flags: `ASSUME_SSL=true` marks cookies `Secure` (only when every access
  path is HTTPS), `FORCE_SSL=true` redirects http→https in the app (normally
  the proxy does this).

## Building the image

The image is self-contained: app, embedded postgres, gems and assets — no
external services needed at runtime.

```sh
docker build -t scoredrop .
# or through compose (also starts the container):
docker compose up --build
```

Rebuild after code changes with `docker compose up -d --build` — the `/data`
volume keeps your settings, subscriptions and match history across rebuilds.
To run without compose:

```sh
docker run -d -p 3000:80 -v scoredrop-data:/data --name scoredrop scoredrop
```

### Publishing to Docker Hub

Tag with your Hub namespace and push:

```bash
# Login to Docker Hub
debian@debian:~$ docker login

# Set up buildx for multi-platform builds
debian@debian:~$ docker buildx create --use

# Build and push for multiple architectures
debian@debian:~$ docker buildx build --push \
--platform linux/arm64,linux/amd64 \
-t martinbarilik/scoredrop:0.1.0 \
-t martinbarilik/scoredrop:latest .
```

## Development

Requires [mise](https://mise.jdx.dev) (Ruby 4.0.7) and a local postgres
(`PGHOST`/`PGUSER`/`PGPASSWORD` env overrides supported).

```sh
mise install
bin/rails db:create db:migrate
bin/rails server     # poller runs in-process; POLLER_ENABLED=false to disable
bin/rails test
```

Handy while testing: `bin/rails runner 'Poller.new.tick'` runs one poll cycle
synchronously.
