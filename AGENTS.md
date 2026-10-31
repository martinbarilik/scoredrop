# AGENTS.md

Scoredrop — self-hosted sport event notifier. Rails 8.1 / Ruby 4.0.7 / PostgreSQL.

- All config lives in the DB (`settings`, `subscriptions` tables). `config/scoredrop.yml`
  is a **one-time import on first boot only**, not the source of truth.
- Notifications go out via ntfy (`Ntfy::Publisher`). Football uses the free
  sportscore.com widget API (`Sportscore::Client`); NHL uses `NhlClient` and
  `HockeyPoller` with persistent `FeedCache` records (12-hour schedules, hourly
  final-result checks after kickoff + 3 hours). Hockey reminders/starts use the DB.
- `Subscription.league` selects football, NHL or Slovak Extraliga. Hockey team
  slugs use `nhl-` / `svk-` prefixes and match keys use `nhl:` / `svk:` prefixes.
  No hockey live-goal polling.
- `SlovakHockeyClient` reads public HockeySlovakia pages: shared 12-hour league
  schedule, hourly result checks only after kickoff + 3 hours. Teams and current
  season are discovered dynamically. Final results require the explicit game-end
  marker; unknown start times are skipped. HTML changes can break this provider.
- The `Poller` runs as an in-process thread (see `config/initializers/poller.rb`);
  `POLLER_ENABLED=false` disables it. `bin/rails runner 'Poller.new.tick'` runs one
  cycle synchronously — useful for testing.
- Match urls on some sports carry no id segment; `Match.key_for` includes the kickoff
  date in that case — do not "simplify" it.
- Tests are Minitest (`bin/rails test`). Ruby is pinned by `mise.toml`; prefix commands
  with `mise exec --` or have mise activated.
- Focused project rules live in `.devin/rules/`, reusable workflows in `.devin/skills/`.
