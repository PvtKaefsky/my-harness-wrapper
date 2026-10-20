# Java design

Instruction ID: `skill/java-coding-standards`.
Requires: project JDK and Maven/Gradle wrapper.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Inspect the configured language level and build. Prefer immutable values and clear null contracts; use Optional for appropriate return boundaries rather than fields everywhere. Preserve exception causes and resource cleanup. Run affected tests and project format/static-analysis checks; do not download a replacement JDK during verification.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/java-coding-standards/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
