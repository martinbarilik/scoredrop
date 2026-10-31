---
name: rails-implementation
description: Implement Rails changes using scoredrop architecture, conventions, tests, and focused verification
argument-hint: '<feature, bug, or change>'
triggers:
  - user
  - model
permissions:
  ask:
    - edit
    - write
---

Implement the requested Rails change with a minimal, working solution.

1. Read the relevant project rules under `.devin/rules/` and `AGENTS.md`.
2. Search for existing implementations, neighboring files, tests, and established abstractions before editing.
3. Trace the affected path: `Poller.tick` → `sync_team`/`process_tracked_matches` → notify, or request → controller → view, or `Setting`/`Subscription` persistence.
4. Confirm dependencies from `Gemfile.lock` before using them. Prefer existing libraries and plain Ruby objects.
5. Data comes only from `Sportscore::Client`; notifications only through `Ntfy::Publisher`. Respect the API rate budget and edge cache.
6. Preserve notification invariants: dedupe via `notified_*`/`NotifiedIncident`, never notify a first-discovered finished match, isolate per-team errors, keep external calls non-fatal to the loop.
7. Config lives in the DB (`Setting`/`Subscription`) — do not reintroduce file-based config as source of truth.
8. Keep the UI dependency-free ERB (no new frontend tooling); follow the existing sidebar/sections layout.
9. Write or update a focused Minitest test for changed behavior first when practical, then implement.
10. Run the narrowest relevant tests (`/test`). Verify boot with `bin/rails runner 'puts :ok'` when touching autoloaded paths — Zeitwerk requires file/constant alignment.
11. Review the final diff for unrelated edits, N+1 queries, exposed secrets, and missing edge cases.
12. Summarize the implementation, verification results, and remaining risks with precise file references.
