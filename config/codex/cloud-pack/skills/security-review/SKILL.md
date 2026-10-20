# Security review

Instruction ID: `skill/security-review`.
Requires: repository read/diff tools; optional installed scanners.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Map assets, entry points and trust boundaries. Review authentication, authorization, injection, path traversal, SSRF, secrets, unsafe deserialization and dependency changes. Give each finding an exploit path, affected location and severity. Run configured scanners only when available. Test positive and negative authorization paths and avoid exposing secret values in findings.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/security-review/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
