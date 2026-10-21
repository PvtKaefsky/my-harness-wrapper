# C++ tests

Instruction ID: `skill/cpp-testing`.
Requires: CMake/CTest or project test runner; configured sanitizers.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Write a failing behavioral test with the existing test framework. Isolate resources with fixtures and RAII, include ownership and lifetime boundaries, then make the smallest change and rerun the failing target. Run relevant CTest targets and available address/undefined-behavior sanitizers. Record compiler, target and sanitizer availability.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/cpp-testing/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
