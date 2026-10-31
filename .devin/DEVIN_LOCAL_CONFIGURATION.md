# Devin Project Configuration

Scoredrop uses a small always-on rule, model-selected project context, focused skills, and guarded permissions.

## Structure

- `AGENTS.md` contains the short, mandatory instructions loaded for every session.
- `.devin/rules/*.md` contain focused context selected by the model when relevant.
- `.devin/skills/<name>/SKILL.md` contains reusable workflows that can be invoked as slash commands.
- `.devin/config.json` defines project permission safeguards.
- `.devin/workflows/` contains legacy reference files and is not the source of current slash commands.

## Skills

- `/rails-implementation` — implement Rails changes using scoredrop conventions and focused verification.
- `/test` — select and run the narrowest relevant Minitest tests.
- `/code-quality` — run focused checks (no formatter is configured; tests + boot sanity).
- `/review` — perform a read-only correctness, notification-safety, security, performance, and test review.
- `/migration-review` — perform a read-only PostgreSQL migration review.
- `/setup-dev` — guide local setup (mise, postgres, rails) without automatic privileged system changes.
- `/database` — inspect and guide database operations with destructive-command safeguards.
- `/deploy` — prepare a Docker/self-host deployment checklist without deploying automatically.

Skills with both `user` and `model` triggers may activate automatically when relevant. Sensitive setup, database, and deployment skills use only the `user` trigger.

## Rules

Keep rules concise because they consume context when activated. Put multi-step procedures in skills instead.

Rule files use explicit activation frontmatter:

```markdown
---
description: When this rule is relevant
trigger: model_decision
---
```

Mandatory constraints belong in the root `AGENTS.md`. Personal, uncommitted preferences belong in `AGENTS.local.md` and should be gitignored.

## Permissions

`.devin/config.json`:

- allows safe read-only Git inspection;
- asks before dependency installation, migrations, commits, and pushes;
- denies privileged commands, force pushes, hard resets, recursive forced deletion, and destructive database reset/drop commands.

## Maintenance

- Update `AGENTS.md` only for short constraints that must always apply.
- Update a focused rule when architecture or conventions change.
- Add or update a skill for repeatable procedures.
- Keep secrets, credentials, ntfy tokens, and machine-specific values out of committed configuration.
- Validate skill YAML frontmatter and `.devin/config.json` after changes.
- Remove legacy `.devin/workflows/` only after confirming no external tooling still depends on them.
