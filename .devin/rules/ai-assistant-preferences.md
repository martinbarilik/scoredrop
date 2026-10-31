---
description: Scoredrop implementation and communication preferences
trigger: model_decision
---

# Implementation Preferences

- Be concise and cite precise files and lines when explaining code.
- Investigate the root cause and existing patterns before proposing or making changes.
- Prefer minimal, focused changes with tests for changed behavior.
- Avoid N+1 queries. Prefer `NOT EXISTS` for non-existence checks.
- Use Ruby's `Net::HTTP` for HTTP requests; do not add another HTTP library without an established project need.
- Respect the ~10k req/day sportscore API budget and ~60s edge cache when choosing poll behavior.
- Never expose secrets; the ntfy token is the only credential — keep it out of logs and test fixtures.
- Preserve existing comments. Add comments only for non-obvious behavior.
- If the user asks only for advice, do not edit. If they ask to implement, fix, update, add, or change something, make the requested edits and verify them.
