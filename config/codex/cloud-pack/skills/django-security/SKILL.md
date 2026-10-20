# Django security

Instruction ID: `skill/django-security`.
Requires: Django system checks and project security tests.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Inspect authentication, per-object permissions, CSRF handling, template escaping and parameterized queries. Review secure cookies, HTTPS redirects, allowed hosts and production debug settings without printing secret values. Use project checks and tests to demonstrate both allowed and denied behavior; report deployment-only checks separately.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/django-security/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
