# Swift concurrency review

Instruction ID: `skill/swift-concurrency-6-2`.
Requires: matching Swift compiler; Apple SDK for platform tests.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Inspect the configured Swift version before applying isolation features. Review actor boundaries, Sendable values, main-actor UI updates and structured task cancellation. Avoid detached tasks for shared mutable state. Test ordering and cancellation with available tooling; report SDK or compiler gaps without asserting runtime validation.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/swift-concurrency-6-2/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
