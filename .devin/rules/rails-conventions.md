---
description: Rails, Ruby, and testing conventions for scoredrop
trigger: model_decision
---

# Rails Conventions

- Follow Rails 8.1.4 and Ruby 4.0.7 syntax while matching surrounding code.
- PostgreSQL via `pg`; background work is the in-process `Poller` thread — no Sidekiq/ActiveJob backend is configured.
- Services are plain Ruby objects in `app/services/` — keep them focused and injectable (`Poller.new(client:, publisher:, settings:)` pattern).
- Use Ruby's `Net::HTTP` for HTTP requests; do not add another HTTP library without an established project need.
- External calls must have short timeouts and must never crash the poller — wrap per-item errors like `sync_team`/`notify_goals` do.
- Never notify twice for the same event: dedupe via `notified_*` timestamps / `NotifiedIncident` rows, and only notify transitions actually observed.
- UI text is plain English ERB — the app has no locale files; do not introduce i18n unless asked.
- Tests are Minitest in `test/`. No fixtures: create records directly; stub the API with small fake client classes, not a mocking gem.
- Keep views dependency-free (no frontend build); the auto-refresh meta tag is the chosen mechanism.
- Use existing dependencies. Respect versions in `Gemfile.lock`.
- Run the narrowest relevant checks through `/test` and `/code-quality`.
