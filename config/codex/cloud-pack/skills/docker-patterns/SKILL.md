# Container review

Instruction ID: `skill/docker-patterns`.
Requires: Docker only when available; managed environment container policy.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Read the managed runtime container/network instructions before running a container. Review multistage builds, non-root users, pinned bases, minimal images, health checks and secret handling. Inspect volume and network scope. Build only task-authorized images with the existing proxy and CA trust; never mount managed configuration or elevate privileges.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/docker-patterns/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
