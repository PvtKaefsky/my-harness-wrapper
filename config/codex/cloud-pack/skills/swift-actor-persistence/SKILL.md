# Swift persistence review

Instruction ID: `skill/swift-actor-persistence`.
Requires: Swift toolchain and project tests if available.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Review actor isolation around mutable persistent state, atomic writes and recovery from partial data. Make encoding errors and version migrations explicit. Test concurrent access, missing/corrupt files and cancellation with isolated storage. Linux Cloud may support reading the design while Apple-specific execution remains unavailable.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/swift-actor-persistence/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
