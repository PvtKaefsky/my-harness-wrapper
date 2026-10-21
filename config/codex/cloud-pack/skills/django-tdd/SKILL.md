# Django TDD

Instruction ID: `skill/django-tdd`.
Requires: Python, pytest-django or repository runner; test database.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Write a failing API/model test using the existing factories and test database. Cover permissions, validation and transaction rollback. Implement the smallest fix, rerun that case, then the affected module. Measure coverage with installed tooling and the project threshold; do not disable migrations or weaken settings to make tests pass.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/django-tdd/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
