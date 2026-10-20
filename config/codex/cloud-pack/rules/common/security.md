# common security

Instruction ID: `rule/common/security`.
Requires: project-defined tools; read-only review remains available.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Validate untrusted inputs, parameterize queries, enforce object/tenant permissions and avoid logging secrets. Check allowed and denied paths. Report scanner and service availability honestly. Project and higher-priority policies remain authoritative.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `rules/common/security.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
