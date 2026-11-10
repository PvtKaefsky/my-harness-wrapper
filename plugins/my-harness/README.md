# my-harness

A Claude Code plugin. It makes a session analyze each task for decomposition
and delegate each subtask to a routed subagent. The marketplace
`my-harness-wrapper`, at the repository root, lists it.

## Contents

| Path | Role |
| --- | --- |
| `.claude-plugin/plugin.json` | The manifest: name `my-harness` and the version. |
| `skills/task-delegation/SKILL.md` | The whole procedure: what a delegated session does, analysis, ownership, routing, the brief, running, integration, failure, the report and the bounds. |
| `skills/task-delegation/references/routing.md` | The coding and analysis routing tables. |
| `agents/executor.md` | The agent for a coding subtask no specialist matches. |
| `agents/analyst.md` | The agent for an analysis subtask no specialist matches. |
| `hooks/hooks.json` | A `UserPromptSubmit` hook printing one line that points every prompt at the skill. |

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

## Install

In Claude Code:

```
/plugin install my-harness --marketplace PvtKaefsky/my-harness-wrapper
```

A change to any file here bumps `version` in `.claude-plugin/plugin.json`.
