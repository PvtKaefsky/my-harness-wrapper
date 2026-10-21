# build-fix

Instruction ID: `workflow/build-fix`.
Requires: requirements of role/build-error-resolver.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

Inputs: failing command and bounded log.
Read `role/build-error-resolver` using the verified pack reader before applying these steps.

## Procedure

reproduce failure; isolate one hypothesis; apply minimal fix; rerun the failing check and affected regression

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `commands/build-fix.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
