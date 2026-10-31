# Known Bugs & Issues

Findings from a codebase review (2026-10-31). Ordered by severity.

## Bugs

### 1. ~~Football fulltime is suppressed when start notifications are disabled~~ FIXED

`Poller#notify_finished` proxies "was tracked" through
`notified_started_at || notified_reminded_at`
(`app/services/poller.rb` ~line 335). But `notify_started` only sets that
flag when `settings.notify?(:start)` is on *and* the publish succeeds.

Consequences:

- A user with only "Fulltime" checked (reminders off) gets **zero**
  fulltime notifications — every tracked live→finished match is skipped.
- If the kickoff publish fails transiently (ntfy down), the fulltime
  notification is also suppressed forever.

Hockey solved this correctly with `schedule_tracked_at` (set at discovery,
not at notification) — see `HockeyPoller#process` and the test
"final notifications work when start notifications are disabled" in
`test/services/hockey_poller_test.rb`.

Suggested fix: in `upsert_match`, when a **new** record is first saved
with `status: finished`, set `notified_finished_at = Time.current` — then
`notify_finished` only needs the `finished? && notified_finished_at.nil?`
check, and the "first-discovered-finished" invariant is preserved without
extra columns. Add a test mirroring the hockey one.

**Fixed (2026-10-31):** implemented as suggested — `upsert_match` stamps
`notified_finished_at` on first-seen-finished records; `notify_finished`
no longer depends on `notified_started_at`/`notified_reminded_at`. A
first-seen-`live` match that later finishes now also notifies. Covered by
"fulltime fires when start notifications are disabled" and "fulltime
still fires when the kickoff publish failed" in `poller_test.rb`.

### 2. ~~ntfy config changes never apply to football notifications without restart~~ FIXED

`Poller#publisher` is memoized (`@publisher ||=`), but `run!` uses one
`Poller` instance for the process lifetime — the first publish snapshots
ntfy settings forever (`app/services/poller.rb` ~line 106). The comment
claims it is "rebuilt per call in production", and the settings page
promises "Changes take effect on the next poll cycle" — neither is true
for football.

Hockey doesn't have this bug — a fresh `HockeyPoller` is built each tick.

Suggested fix: drop the `||=` and rebuild from `settings` each call.

**Fixed (2026-10-31):** `@publisher ||` — the injected publisher is still
used when present, otherwise a fresh `Ntfy::Publisher` is built from the
current `Setting` row on every publish. Covered by "publisher is rebuilt
from current settings, not memoized" in `poller_test.rb`.

### 3. ~~Opponent sweep re-probes already-known matches every 15 minutes~~ FIXED

`discover_for` hits the match endpoint for every league pairing every
sweep, including matches already tracked and linked
(`app/services/poller.rb` ~line 168). For a 20-team league that's
~19 calls/sub/15min (~76/hour) — the largest single API budget consumer —
and it doubles when two subscribed teams share a league.

The probe slug equals the stored `Match.slug` for football, so a
`next if Match.exists?(slug: slug)` before the API call eliminates most
of it.

**Fixed (2026-10-31):** `discover_for` skips pairings where the
subscription already tracks an *unfinished* match with that slug
(finished ones must not skip — the slug then resolves to the next
fixture). Covered by "opponent sweep skips pairings with a tracked
unfinished match" in `poller_test.rb`.

### 4. ~~`Poller.last_error` is never cleared~~ FIXED

Set on any per-team failure but only overwritten by the *next* error
(`app/services/poller.rb` ~line 57). One transient failure leaves a stale
error on the status page indefinitely. Clear it at the start (or
successful end) of `tick`.

**Fixed (2026-10-31):** cleared at the start of each `tick`, so it always
reflects the most recent cycle. Covered by "last_error is cleared once a
clean tick runs" in `poller_test.rb`.

## Minor / hardening

All fixed (2026-10-31) unless noted:

- **~~`FeedCache.fetch` race~~ FIXED**: `find_by` → `new` → `update!`
  could raise `RecordNotUnique` on the unique `key` index when the
  request-thread `refresh` and the poller thread fetched the same key
  concurrently. Replaced with a single atomic `upsert(..., unique_by: :key)`.
- **~~Status regression~~ FIXED**: `upsert_match` unconditionally applied
  `payload["status"]` — stale feed data could flip a `finished` match back
  to `upcoming`. `finished` is now terminal (feed payload can't regress
  it), and nil payload scores no longer wipe stored scores.
- **~~`notify_goals` fallback dead code~~ FIXED**: bigger than the
  original nil-`away_score` `TypeError` note — the score-diff fallback
  compared `payload` vs `match` scores *after* `sync_match_detail` had
  already applied that same payload, so the diff was always 0 and
  incident-less goal notifications never fired (retry semantics were
  broken the same way). Rewritten to use `score:H:A` rows in
  `notified_incidents` as the watermark: first observed scoreline is a
  silent baseline, unseen scorelines above it publish once, and a failed
  publish leaves no row so it retries. `away_score` nil handled via `to_i`.
- **~~YAML import ignores league prefixes~~ FIXED**: `teams:` entries
  starting `nhl-`/`svk-` now import as `nhl`/`extraliga` subscriptions;
  invalid slugs log a warning and are skipped instead of aborting the
  rest of the import.
- **~~Hockey in-progress discovery gap~~ FIXED**: a game first synced as
  `in_progress` now gets `schedule_tracked_at`, so its final notifies.
- **~~`params[:check].strip`~~ FIXED**: `.to_s.strip` — no 500 on a
  crafted non-string param.
- **~~`Setting.instance` singleton race~~ FIXED**: `first || create!(id: 1)`
  with a `RecordNotUnique` fallback — concurrent first-boot creators can
  no longer produce two settings rows.
- **ntfy token** is rendered back into page source via `value=` on the
  settings form — acceptable for a local unauthenticated app, noted for
  completeness.
