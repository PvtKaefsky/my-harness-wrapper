# refactor-clean

Instruction ID: `workflow/refactor-clean`.
Requires: requirements of role/refactor-cleaner.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

Inputs: bounded cleanup candidates.
Read `role/refactor-cleaner` using the verified pack reader before applying these steps.

## Procedure

trace references and runtime entry points; remove only proven unused behavior; verify regressions and diff scope

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `commands/refactor-clean.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
