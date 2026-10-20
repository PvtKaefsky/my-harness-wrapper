# Frontend patterns

Instruction ID: `skill/frontend-patterns`.
Requires: project frontend runtime, type checker and tests.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Inspect component responsibilities and state ownership. Prefer composition, isolate asynchronous effects and handle loading, empty, failure and cancellation states. Review keyboard access and semantic HTML. Test user-visible behavior and relevant responsive layouts using the available browser; measure performance before adding memoization.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/frontend-patterns/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
