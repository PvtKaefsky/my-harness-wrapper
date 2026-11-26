---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [task-delegation]
---

This session is the orchestrator in the Claude desktop app, in a clone of `acme/ledger` whose default branch is `main`. `mcp__ccd_session__start_session` is available there but not loaded in this run, so start nothing: write out the decomposition and each brief you would send.

Add bank reconciliation to the ledger service. It needs a statement parser in `recon/parse.py`, a matching engine that pairs statement lines with ledger entries in `recon/match.py`, and a discrepancy report in `recon/report.py`, each with its own tests under `tests/recon/`. All of it is hand-written logic with no generated code; I expect about 600 changed lines for the parser, 700 for the matcher and 400 for the report, tests included.
