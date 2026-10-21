# Database migrations

Instruction ID: `skill/database-migrations`.
Requires: project migration runner and isolated test database.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Inspect current schema, readers and writers. Plan expand/migrate/contract steps and safe rollback before changing schema. Bound backfills and lock duration; use the database-supported concurrent index path where appropriate. Test upgrades on disposable representative data and verify old/new application compatibility. Never apply a migration to a live database without authorization.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/database-migrations/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
