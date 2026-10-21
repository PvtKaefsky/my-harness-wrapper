# PostgreSQL review

Instruction ID: `skill/postgres-patterns`.
Requires: SQL files; optional isolated PostgreSQL connection.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Trace query inputs, row-level authorization, indexes and transaction isolation. Parameterize values and cap reads. Use read-only explain on authorized representative data; executing analyze needs a safe test database. Test tenant isolation, null handling and rollback. Report unavailable database evidence rather than inventing query plans.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/postgres-patterns/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
