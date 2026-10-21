# End-to-end testing

Instruction ID: `skill/e2e-testing`.
Requires: installed browser automation, browser binaries and isolated application services.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Choose one critical user journey and use semantic locators. Seed isolated data, wait on observable state and capture bounded failure traces. Diagnose flaky timing before retrying; do not hide failures with indefinite retries or quarantine. Report browser/service availability, exact case counts and artifact paths without claiming absent browsers ran.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/e2e-testing/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
