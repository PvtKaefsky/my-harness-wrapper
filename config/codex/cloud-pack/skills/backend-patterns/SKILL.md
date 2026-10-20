# Backend architecture

Instruction ID: `skill/backend-patterns`.
Requires: repository runtime and integration tests.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Trace request, service, repository and external-service boundaries. Keep transactions around related writes, parameterize queries and bound result sets. Check N+1 access, cache invalidation, timeouts and idempotency. Test rollback, retry and partial external failure using isolated test services.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/backend-patterns/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
