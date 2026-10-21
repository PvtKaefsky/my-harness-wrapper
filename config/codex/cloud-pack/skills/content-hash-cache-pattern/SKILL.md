# Content hash caches

Instruction ID: `skill/content-hash-cache-pattern`.
Requires: repository hash/cache tests.

Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.

## Procedure

Key cached results by content digest plus parser/version inputs, rather than a mutable path alone. Separate cache storage from processing. Define eviction and atomic publication, and reject untrusted serialized objects. Test identical bytes at distinct paths, changed content at one path, missing entries, corrupt entries and concurrent publication.

## Completion report

Report the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation.

Adapted from `skills/content-hash-cache-pattern/SKILL.md` at upstream `d468c521f1a76e7b05d446d805f6ad2afa8ed066`; see `LICENSE` and `upstream.json`.
