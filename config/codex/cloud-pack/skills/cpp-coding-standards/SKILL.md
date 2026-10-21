# C++ design

Instruction ID: `skill/cpp-coding-standards`.
Requires: project C++ compiler and build system.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Inspect the configured C++ standard. Prefer RAII, value semantics and explicit ownership; identify lifetime, iterator and exception-safety hazards. Keep interfaces small and conversions explicit. Verify the affected build targets and available sanitizers; report unsupported toolchains instead of changing the build standard.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/cpp-coding-standards/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
