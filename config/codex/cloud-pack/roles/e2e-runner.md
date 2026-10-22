# End-to-end testing

Instruction ID: `role/e2e-runner`.
Requires: repository read/diff tools; independent native agent only for an independent review.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

This role brief does not create an agent. Follow docs/native-review.md in the attached wrapper for bounded role selection, native dispatch and provider receipts. For independent review, pass this verified brief to an available independent native Codex agent with source HEAD, exact staged tree, assigned roles, scope, risk, project rules and marked user-supplied verbatim hunks. Inspect immutable staged tree blobs; do not edit files or the index. A self-review cannot approve its own work.

## Procedure

Identify a critical user journey and available browser tooling. Use isolated data and semantic locators. Record browser/service versions, failures and bounded traces; distinguish unavailable execution from passing cases.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation. A review must name source HEAD, staged tree and assigned roles and give APPROVED or NOT_APPROVED, with severity and evidence for every finding. Return inspected paths and actual checks. The coordinator must retain the actual provider dispatch/completion references separately; never invent them. Findings above LOW, a blocked review or no explicit approval block committing.

Adapted from `agents/e2e-runner.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
