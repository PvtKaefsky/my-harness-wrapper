# orchestrate

Instruction ID: `workflow/orchestrate`.
Requires: requirements of role/planner.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

Inputs: task and proposed roles.
Read `role/planner` using the verified pack reader before applying these steps.

## Procedure

plan at most three role handoffs; use native independent agents only when actually available and authorized; otherwise perform sequential analysis and label it self-analysis; preserve independent commit-review requirements

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `commands/orchestrate.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
