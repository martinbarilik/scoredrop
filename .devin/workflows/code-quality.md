---
description: Code quality and checks
---

# Code Quality Workflow

> Legacy reference only. Use `/code-quality` for focused checks that avoid unrelated changes.

No RuboCop/htmlbeautifier/Prettier is configured in this project — match surrounding style; do not introduce a formatter unasked.

```bash
bin/rails test                                   # suite (prefix: mise exec --)
bin/rails runner 'puts :ok'                      # boot/autoload sanity
```

Checklist for a change:

- Relevant tests pass for the touched code.
- New constants/files obey Zeitwerk naming (one constant per expected path).
- No secrets or tokens in code, logs, or fixtures.
- No unrelated reformatting or removed comments.
