# go-test

Instruction ID: `workflow/go-test`.
Requires: requirements of skill/golang-testing.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

Inputs: behavior and affected package.
Read `skill/golang-testing` using the verified pack reader before applying these steps.

## Procedure

record table-test RED; implement GREEN; run package tests and supported race/coverage checks

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `commands/go-test.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
