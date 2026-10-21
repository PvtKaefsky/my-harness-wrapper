# Swift dependency injection

Instruction ID: `skill/swift-protocol-di-testing`.
Requires: Swift toolchain and project tests.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Identify external dependencies behind small protocols and inject test implementations through constructors. Keep mocks local to each test and verify observable behavior, not private calls. Test failures and asynchronous cancellation. Run the project test targets if supported; report missing Apple frameworks separately.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/swift-protocol-di-testing/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
