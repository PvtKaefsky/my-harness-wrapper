# typescript testing

Instruction ID: `rule/typescript/testing`.
Requires: project-defined tools; read-only review remains available.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Use meaningful isolated tests for observable behavior and errors. For behavioral changes, establish failing regression evidence before the fix where practical. Run project-defined checks and coverage thresholds. Use configured TypeScript type/lint/tests; inspect promises, schema validation and UI effect boundaries.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `rules/typescript/testing.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
