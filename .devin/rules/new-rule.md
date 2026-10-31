---
description: Scoredrop file layout and formatting conventions
trigger: model_decision
---

# File Layout and Formatting

- Follow surrounding code and existing abstractions before introducing a new pattern.
- Keep views in `app/views/`, models in `app/models/`, controllers in `app/controllers/`, and services in `app/services/` (external integrations namespaced, e.g. `sportscore/`, `ntfy/`).
- No formatter is configured (RuboCop/Prettier were skipped at scaffold) — match the existing 2-space standardrb-style Ruby instead of adding tooling without asking.
- Use hyphens for CSS classes; styles live in `app/assets/stylesheets/application.css`.
- No inline `style="..."` attributes in views — define a CSS class in `application.css` instead.
- Preserve existing comments. Add comments only for non-obvious behavior.
- Keep one empty line above any `return`, `return if`, or `return unless` when it follows other code.
