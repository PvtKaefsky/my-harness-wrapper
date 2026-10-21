# Django architecture

Instruction ID: `skill/django-patterns`.
Requires: Python, Django and project tests.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Trace models, QuerySets, services, serializers and views. Keep validation at request boundaries and database invariants in constraints. Use select_related/prefetch_related deliberately and bound pagination. Test transaction boundaries, permissions and query counts using the configured test database.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/django-patterns/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
