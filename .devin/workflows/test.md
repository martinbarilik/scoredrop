---
description: Run the test suite
---

# Testing Workflow

> Legacy reference only. Use `/test` for focused test selection and database safeguards.

## Running Tests (Minitest)

```bash
bin/rails test                                  # whole suite
bin/rails test test/models/match_test.rb        # one file
bin/rails test test/models/match_test.rb -n test_name   # one test
```

Prefix with `mise exec --` if mise is not activated in the shell.

## Notes

- The test database is `scoredrop_test`; `bin/rails test` maintains its schema automatically. Never drop/recreate it manually.
- Service tests use fake `Sportscore::Client`/publisher classes — never hit the real API or ntfy server in tests.
- Manual end-to-end check in development: `bin/rails runner 'Poller.new.tick'`.
