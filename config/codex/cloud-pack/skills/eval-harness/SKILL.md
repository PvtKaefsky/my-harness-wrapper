# Behavior evaluations

Instruction ID: `skill/eval-harness`.
Requires: repository test runner; optional real provider evaluator.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Define capability and regression cases with observable pass criteria before implementation. Prefer deterministic code checks for exact contracts. Use model judgment only when a real evaluator is available and identify it separately. Include negative controls and deletion mutations; report failures and sample bounds rather than inferring reliability from one run.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/eval-harness/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
