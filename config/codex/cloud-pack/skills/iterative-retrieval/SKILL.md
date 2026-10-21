# Bounded code discovery

Instruction ID: `skill/iterative-retrieval`.
Requires: repository file search/read tools.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Start with a concrete question and search relevant identifiers with rg. Read definitions and callers, mark missing context, then refine the query. Stop after three refinement passes or when evidence answers the question. Report paths and unresolved gaps. Supply this context explicitly if an authorized independent native reviewer needs it.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/iterative-retrieval/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
