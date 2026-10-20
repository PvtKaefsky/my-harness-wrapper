# Deployment review

Instruction ID: `skill/deployment-patterns`.
Requires: repository build/test tools; deployment access only if authorized.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Review the build artifact, health/readiness checks, secret delivery, graceful shutdown and rollback path. Compare rolling, canary or blue-green strategy to the actual system. Verify configuration and tests locally; produce an operator checklist with measurable rollback triggers. Deploy only when the task explicitly authorizes it.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/deployment-patterns/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
