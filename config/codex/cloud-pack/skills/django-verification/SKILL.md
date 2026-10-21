# Django verification

Instruction ID: `skill/django-verification`.
Requires: Python, Django and repository lint/type/test tools.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Run the configured system checks, migration drift check and focused tests on isolated resources. Inspect generated migration operations and compatibility. Run available lint/type and coverage commands. Distinguish unapplied local test migrations from production state; never generate or apply live migrations merely to verify a change.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/django-verification/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
