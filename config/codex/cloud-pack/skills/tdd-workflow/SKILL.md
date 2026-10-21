# Test-driven implementation

Instruction ID: `skill/tdd-workflow`.
Requires: repository test runner and authorized project edits.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Define the observable behavior and write a focused failing test. Run it and record the expected failure cause (RED), implement the smallest change (GREEN), then refactor while keeping it green. Cover boundaries and error paths using isolated fixtures. Run relevant existing suites and project coverage thresholds. A command that could not execute is BLOCKED, not RED; never weaken a test to hide a defect.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/tdd-workflow/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
