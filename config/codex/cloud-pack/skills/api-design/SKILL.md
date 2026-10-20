# API contracts

Instruction ID: `skill/api-design`.
Requires: repository API tests.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Map resources and consumers before changing routes. Specify methods, status codes, pagination limits, filtering and a stable error envelope. Validate request boundaries and authorization for each resource. Test malformed inputs, missing objects, denied access and pagination boundaries; preserve compatibility or document the version change.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/api-design/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
