---
name: harness-python-patterns
description: Review Python design, EAFP versus LBYL, resource ownership, typing, and exceptional paths using the shared wrapper's audited Python patterns.
---

# Python design

Instruction ID: `skill/python-patterns`.
Requires: Python and repository checks.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Use explicit data contracts, context managers for resource ownership and generators for bounded streaming. Use EAFP when failure is an expected narrow exception, and LBYL where validation clarifies the interface; avoid broad exception swallowing. Review mutable defaults, typing boundaries and thread/process safety. Test empty, invalid and exceptional paths with the configured runner.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/python-patterns/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
