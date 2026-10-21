# checkpoint

Instruction ID: `workflow/checkpoint`.
Requires: requirements of skill/verification-loop.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

Inputs: current task scope.
Read `skill/verification-loop` using the verified pack reader before applying these steps.

## Procedure

report current HEAD, staged tree, changed paths and checks in this conversation; do not create commits or persistent session storage

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `commands/checkpoint.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
