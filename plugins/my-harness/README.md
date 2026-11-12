# my-harness

A Claude Code plugin. It ships the task-delegation procedure, which makes a
session analyze each task for decomposition and delegate each subtask to a
routed subagent. It also ships four general skills. The marketplace
`my-harness-wrapper`, at the repository root, lists it.

## Contents

| Path | Role |
| --- | --- |
| `.claude-plugin/plugin.json` | The manifest: name `my-harness` and the version. |
| `skills/task-delegation/SKILL.md` | The whole procedure: what a delegated session does, analysis, ownership, routing, the brief, running, integration, failure, the report and the bounds. |
| `skills/task-delegation/references/routing.md` | The coding and analysis routing tables. |
| `skills/python-property-model-tests/SKILL.md` | Writing Python tests that a unit keeps a property across many inputs or operation sequences: tool choice, property kinds, input strategies, state machines, failing examples and CI determinism. |
| `skills/edit-russian-technical-text/SKILL.md` | Rules for editing Russian technical prose while keeping its meaning, terms and requirements, with before and after examples. |
| `skills/quick-human-readable-review/SKILL.md` | The shape of a summary of a finished stage of work or an experiment series: outcome, confirmed results, open questions and next step. |
| `skills/python-fp-refactor/SKILL.md` | Steps for moving the decisions in Python code that mixes them with I/O or state into functions on values, keeping its behaviour. |
| `agents/executor.md` | The agent for a coding subtask no specialist matches. |
| `agents/analyst.md` | The agent for an analysis subtask no specialist matches. |
| `hooks/hooks.json` | A `UserPromptSubmit` hook printing one line that points every prompt at the `task-delegation` skill. |

## Agents

| Agent | Tools | Model |
| --- | --- | --- |
| `my-harness:executor` | `Read`, `Write`, `Edit`, `Bash`, `Grep`, `Glob` | `inherit` |
| `my-harness:analyst` | `Read`, `Grep`, `Glob`, `Bash`, `WebSearch`, `WebFetch` | `inherit` |

Neither tool list carries `Agent`, so neither agent can start a subagent.

## The hook

The hook command is `printf '%s\n' '<line>'`, run by the shell Claude Code
runs hook commands in. A hook command that fails prints nothing, and the
prompt goes on without the line.

## Delivery

| Session | How the plugin arrives |
| --- | --- |
| Claude Code, cloud and local | The harness installers install `my-harness@my-harness-wrapper`, named in `config/plugins.tsv`. |
| Cowork | The user uploads the packaged plugin through claude.ai. `docs/runbook.md` carries the packaging steps and what is verified about them. |

By hand, in Claude Code:

```
/plugin install my-harness --marketplace PvtKaefsky/my-harness-wrapper
```

A change to any file here bumps `version` in `.claude-plugin/plugin.json`.
`scripts/verify.sh` compares the installed version with that field.
