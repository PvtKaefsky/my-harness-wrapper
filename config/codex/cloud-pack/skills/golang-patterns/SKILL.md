# Go design

Instruction ID: `skill/golang-patterns`.
Requires: Go toolchain and project build/tests.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Keep small consumer-owned interfaces and useful zero values. Wrap errors with context and preserve errors.Is/As behavior. Propagate context cancellation and bound goroutine lifetimes. Test failure/cancellation paths and race-sensitive shared state; use the project formatter, vet and tests without mutating global Go settings.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/golang-patterns/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
