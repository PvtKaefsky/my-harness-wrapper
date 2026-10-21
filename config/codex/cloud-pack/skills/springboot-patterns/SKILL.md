# Spring Boot architecture

Instruction ID: `skill/springboot-patterns`.
Requires: project JDK and Maven/Gradle tests.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Trace controller, validation, service and repository boundaries. Keep transaction ownership explicit and external calls bounded. Review configuration profiles, structured error responses and observability without secret leakage. Test request validation, authorization and failure rollback using the existing integration-test strategy.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/springboot-patterns/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
