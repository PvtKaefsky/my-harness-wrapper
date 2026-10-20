# Spring Boot security

Instruction ID: `skill/springboot-security`.
Requires: project JDK and security tests.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Inspect security filter chains, authentication and method/resource authorization. Check CSRF applicability, CORS restrictions, input validation and output encoding. Review password hashing and secret references without exposing values. Test anonymous, authenticated and cross-tenant requests; report live identity-provider checks separately.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/springboot-security/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
