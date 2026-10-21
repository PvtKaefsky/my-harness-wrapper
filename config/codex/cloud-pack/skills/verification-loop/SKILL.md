# Completion verification

Instruction ID: `skill/verification-loop`.
Requires: repository lint/type/build/test commands.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Inspect project-defined checks and choose the relevant bounded set. Run compilation, type/lint, focused tests and integration checks as applicable, recording commands, exits, case counts and unavailable tools. Inspect the final diff for scope, secrets, debug code and documentation drift. Require real staged independent reviews before committing. A passing local suite does not certify a published Cloud task.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/verification-loop/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
