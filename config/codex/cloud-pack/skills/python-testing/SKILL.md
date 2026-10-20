# Python TDD

Instruction ID: `skill/python-testing`.
Requires: Python, unittest or installed pytest and project plugins.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Write an observable failing regression with isolated fixtures and targeted assertions. Mock external boundaries, not the behavior under test. Cover malformed input, exceptions, resource cleanup and repeat calls. Implement minimally, rerun the case and affected suite, then measure relevant coverage using available project tooling.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/python-testing/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
