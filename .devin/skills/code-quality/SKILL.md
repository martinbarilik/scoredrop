---
name: code-quality
description: Run focused scoredrop checks on relevant files (no formatter is configured)
argument-hint: '[file or changed-files scope]'
triggers:
  - user
  - model
---

Check code quality using the smallest scope that covers the requested or changed files.

1. No RuboCop/htmlbeautifier/Prettier is configured — match surrounding style instead of introducing a formatter unasked.
2. Run `mise exec -- bin/rails test` on the test files covering changed code.
3. Sanity-check boot after structural changes: `mise exec -- bin/rails runner 'puts :ok'` catches autoload/NameError issues (e.g. Zeitwerk file/constant mismatches — one constant per expected path).
4. Do not reformat unrelated files or remove existing comments.
5. Report commands run, findings, and remaining issues.
