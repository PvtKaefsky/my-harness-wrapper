# Go review

Instruction ID: `role/go-reviewer`.
Requires: repository read/diff tools; independent native agent only for an independent review.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

This role brief does not create an agent. For independent review, pass it to an available native Codex reviewer with the staged tree ID, scope and user-supplied verbatim hunks. A self-review cannot approve its own work.

## Procedure

Check error wrapping, context propagation, goroutine ownership, race/deadlock risks, interfaces and allocation bounds. Inspect table tests and use build/vet/race commands only when the toolchain supports them.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation. A review must name the staged tree and give APPROVED or NOT_APPROVED, with severity and evidence for every finding. Findings above LOW or no explicit approval block committing.

Adapted from `agents/go-reviewer.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
