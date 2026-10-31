---
name: test
description: Select and run the narrowest relevant scoredrop Minitest tests safely
argument-hint: '[test path or example pattern]'
triggers:
  - user
  - model
---

Test the requested or recently changed behavior with the narrowest useful scope.

1. Inspect the affected code and nearby tests before choosing a command.
2. Prefer, in order: a specific test file, a specific test name, then the whole suite.
3. Commands (prefix with `mise exec --` if mise is not activated):
   - File: `bin/rails test test/models/match_test.rb`
   - Single test: `bin/rails test test/models/match_test.rb -n test_name`
   - Whole suite: `bin/rails test`
4. The test database is `scoredrop_test` on the local postgres (user `martin`); `bin/rails test` maintains the schema automatically. Never drop or reset databases manually.
5. Poller/service tests stub the API with fake client classes — do not hit the real sportscore.com API or ntfy server from tests.
6. To exercise the real pipeline manually, `bin/rails runner 'Poller.new.tick'` runs one synchronous cycle in development.
7. Do not hide failures or retry to make a genuine failure appear successful.
8. Report the exact commands, passing/failing counts, and whether failures look related to the change.
