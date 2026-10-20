# Research before implementation

Instruction ID: `skill/search-first`.
Requires: repository search; optional approved connected search tools.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Search the repository, dependency manifests and existing tests for the needed behavior before adding code. Compare existing libraries and APIs using their pinned documentation. State the evidence and integration costs for reuse versus a small local implementation. Do not install packages or execute fetched examples as part of research.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/search-first/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
