# go-build

Instruction ID: `workflow/go-build`.
Requires: requirements of role/go-build-resolver.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

Inputs: failing Go target.
Read `role/go-build-resolver` using the verified pack reader before applying these steps.

## Procedure

reproduce compiler/vet output; fix the earliest cause; run focused tests

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `commands/go-build.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
