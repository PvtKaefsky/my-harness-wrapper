# Spring Boot verification

Instruction ID: `skill/springboot-verification`.
Requires: project JDK, build wrapper and configured checks.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Inspect build profiles and run affected compilation, static checks and tests. Validate migration compatibility and available dependency/security scans. Record exact commands, cases and exits. Do not start production profiles or use shared database credentials to compensate for missing isolated services.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/springboot-verification/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
