# code-review

Instruction ID: `workflow/code-review`.
Requires: requirements of role/code-reviewer.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

Inputs: staged tree and scope.
Read `role/code-reviewer` using the verified pack reader before applying these steps.

## Procedure

Follow docs/native-review.md in the attached wrapper. Inspect the actual staged tree and applicable project rules; use --requirements as minimum coverage and declare extra domain roles. Read each relevant verified brief, inventory actual native Codex collaboration tools and select independent reviewers. Dispatch one batch where supported with exact source HEAD/tree, scope, risk, project rules and marked verbatim user hunks. Bound review to five rounds and two dispatch attempts per role per round; wait for actual provider completion within the ten-minute round deadline. Retain reviewer, dispatch and completion references and explicit tree-bound verdicts. Keep availability, dispatch, completion, approval and guarded commit statuses separate. Missing roles, receipts or approval leave changes uncommitted. After staged edits, obtain fresh approvals; use only actual provider evidence with commit-codex.sh.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `commands/code-review.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
