# go-review

Instruction ID: `workflow/go-review`.
Requires: requirements of role/go-reviewer.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

Inputs: staged Go paths and tree.
Read `role/go-reviewer` using the verified pack reader before applying these steps.

## Procedure

review Go correctness and concurrency; run available checks; return tree-bound findings and verdict

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `commands/go-review.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
