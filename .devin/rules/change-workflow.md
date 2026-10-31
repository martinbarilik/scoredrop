---
description: Required documentation and verification steps for every change
trigger: model_decision
---

# Documentation and Verification

- Every internal change (architecture, services, models, config, poller behavior) must be documented in `README.md` when it affects how the app works, is configured, deployed, or operated. Skip it only for changes invisible to users/operators.
- Every frontend/UI change must likewise be reflected in `README.md` — update the Pages table or relevant section when adding/removing pages or changing what a page does.
- Every change must be validated by running tests — the narrowest relevant file/test is enough (`/test`); run the full suite for anything touching shared paths (`Poller`, `Match`, `Setting`, `Subscription`).
- If a change makes existing tests irrelevant or breaks expected behavior, update the tests rather than leaving stale coverage.
