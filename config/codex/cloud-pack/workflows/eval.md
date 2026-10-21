# eval

Instruction ID: `workflow/eval`.
Requires: requirements of skill/eval-harness.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

Inputs: behavior contract and cases.
Read `skill/eval-harness` using the verified pack reader before applying these steps.

## Procedure

define measurable capability and regression checks; include negative controls; execute available graders

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `commands/eval.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
