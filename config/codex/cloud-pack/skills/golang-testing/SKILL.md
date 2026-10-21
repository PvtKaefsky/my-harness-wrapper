# Go TDD

Instruction ID: `skill/golang-testing`.
Requires: Go toolchain; race detector when supported.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Write table-driven tests with explicit success and error cases; use subtests and t.TempDir for isolation. Observe RED, implement minimally, then GREEN. Run focused tests, relevant go test -race and coverage where supported. Add fuzz cases or benchmarks when they exercise a real boundary; record unavailable race support.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/golang-testing/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
