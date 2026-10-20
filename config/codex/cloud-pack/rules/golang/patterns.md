# golang patterns

Instruction ID: `rule/golang/patterns`.
Requires: project-defined tools; read-only review remains available.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Choose patterns from existing project code. Keep data access and business behavior separate, expose narrow interfaces and make boundary failure explicit. Avoid speculative abstractions. Use the repository Go formatter, vet and tests; review goroutine cancellation and race checks.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `rules/golang/patterns.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
