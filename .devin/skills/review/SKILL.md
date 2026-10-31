---
name: review
description: Review scoredrop changes for correctness, notification-safety, security, performance, and missing tests
argument-hint: '[file, diff, or feature scope]'
triggers:
  - user
  - model
permissions:
  ask:
    - edit
    - write
---

Review the requested scope without modifying files.

1. Establish the intended behavior and inspect the complete relevant diff or code path.
2. Report only actionable findings, ordered by severity, with precise file and line references.
3. Notification correctness — the core invariants:
   - Events must fire once: dedupe through `notified_*` timestamps and `NotifiedIncident`.
   - A match first discovered as `finished` must not produce a fulltime notification.
   - `Match.key_for`/`slug_for` must handle both url shapes (`/match/{slug}/{id}/` and id-less `/match/{slug}/`).
   - Poll intervals must stay within the ~10k req/day API budget.
4. Poller robustness: per-team/per-match errors isolated, external call timeouts set, the loop can't die silently (top-level rescue + retry).
5. Security: no secrets in logs/code; this is an unauthenticated local app — flag anything that weakens that assumption accidentally (e.g. CSRF-exposed mutating endpoints are acceptable locally, but note them).
6. Check N+1 queries, unbounded queries (status page limits to 50), and unnecessary API calls.
7. Check test coverage asserts outcomes (notifications emitted/suppressed), not implementation details.
8. If no findings remain, say so and state residual testing or operational risk.
