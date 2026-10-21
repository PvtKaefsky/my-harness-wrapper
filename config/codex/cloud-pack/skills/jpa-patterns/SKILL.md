# JPA data access

Instruction ID: `skill/jpa-patterns`.
Requires: project JDK, ORM tests and isolated database.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Review entity identity, ownership and cascade behavior. Detect N+1 reads, unbounded fetching and transaction leakage. Keep pagination deterministic and indexes aligned with access paths. Verify rollback, optimistic locking and query counts with isolated database tests; avoid schema auto-update against shared databases.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/jpa-patterns/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
