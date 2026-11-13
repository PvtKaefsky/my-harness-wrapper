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
| `evals/` | The eval suite: one case directory per row of the table under "Eval suite", each with a `prompt.md` and `graders/skill.md`. |
| `evals/.gitignore` | Keeps `results/`, which each eval run writes, out of git. |

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

## Eval suite

The suite measures whether each skill is invoked on a prompt its description
matches, and not invoked on a nearby prompt it does not. It does not grade a
skill's output.

Each case's `prompt.md` is a request worded as a user would type it, with its
material inline, and sets `max_turns: 8` and
`allowed_tools: [Read, Glob, Grep, Skill]`. Its one grader, `graders/skill.md`,
is `type: tool_used` on `tool: Skill`, with an `input_match` for that skill
alone. An "invoke" case passes a run that calls the skill at least once. A "not
invoke" case adds `min: 0`, `max: 0` and `arm: both`, and passes a run that never
calls it. `task-delegation` has no "not invoke" case, because its description
applies to every task.

| Case | Skill | Expected | The prompt carries |
| --- | --- | --- | --- |
| `delegation-coding-task` | `task-delegation` | invoke | a Python script and a request to add a `--dry-run` flag and document it |
| `delegation-analysis-question` | `task-delegation` | invoke | a short Python function and a question about why it returns `None` for an empty list |
| `property-tests-serializer` | `python-property-model-tests` | invoke | a Python `encode`/`decode` pair and a request for tests |
| `property-tests-javascript` | `python-property-model-tests` | not invoke | a JavaScript function and a request for Jest tests |
| `russian-edit` | `edit-russian-technical-text` | invoke | a Russian technical paragraph and a request in Russian to make it clearer |
| `english-edit` | `edit-russian-technical-text` | not invoke | an English technical paragraph and a request to make it clearer |
| `benchmark-outcome` | `quick-human-readable-review` | invoke | the results of three benchmark runs and a request for their outcome |
| `diff-review` | `quick-human-readable-review` | not invoke | a unified diff and "Review this diff." |
| `untangle-io` | `python-fp-refactor` | invoke | a Python function that reads a file, decides prices and writes a result, and a request to untangle it |
| `add-type-hints` | `python-fp-refactor` | not invoke | a Python function mixing I/O and decisions, and a request to add type hints and change nothing else |

Run it from the repository root, with an output directory outside the
repository:

```bash
claude plugin eval plugins/my-harness --trust-plugin --no-publish --ablation none --model claude-opus-5-5 --runs 3 --output-dir <scratch dir> </dev/null
```

`--ablation none` keeps the `Skill` graders in the score; under the default
`with-without` they are reported as indicators only, by
`claude plugin eval --help` on CLI 2.1.322. A case scoring below `1.0`
makes the command exit 1. No CI job runs the suite, because each run spends
model usage.

### What a run leaves out

Each run is a `claude -p` child that loads this plugin alone, with no
`CLAUDE.md`, user settings, other plugins or memory. The plugin's own hooks,
`UserPromptSubmit` among them, load with it, by the Claude Code docs page
"Test plugins with evals"; the measured runs kept no trace showing the hook's
output. A run therefore does not reproduce the skill
listing overflow of #95, where ECC's skills pushed the `my-harness`
descriptions out of the listing.

### What a score shows

An "invoke" case's pass shows that the skill was called; it does not show that
the output followed the skill. With `skills/quick-human-readable-review/`
deleted from a scratch copy of this plugin, `benchmark-outcome` scored 0 in 1
run, so that case's pass requires the skill to be present. A "not invoke"
case's pass does not separate a description that excludes the prompt from a
skill that is missing.

### Measured scores

Measured on 2026-11-12 with CLI 2.1.322, `--model claude-opus-5-5`,
`--ablation none` and `--runs 3`, against the skills as merged at `58e5e2d`.
The suite cost $3.60 and exited 1.

| Case | Score | Runs passed | Cost (USD) |
| --- | --- | --- | --- |
| `delegation-coding-task` | 1.0 | 3 of 3 | 0.32 |
| `delegation-analysis-question` | 0.33 | 1 of 3 | 0.24 |
| `property-tests-serializer` | 1.0 | 3 of 3 | 0.59 |
| `property-tests-javascript` | 1.0 | 3 of 3 | 0.41 |
| `russian-edit` | 1.0 | 3 of 3 | 0.33 |
| `english-edit` | 1.0 | 3 of 3 | 0.27 |
| `benchmark-outcome` | 1.0 | 3 of 3 | 0.39 |
| `diff-review` | 1.0 | 3 of 3 | 0.36 |
| `untangle-io` | 1.0 | 3 of 3 | 0.41 |
| `add-type-hints` | 1.0 | 3 of 3 | 0.29 |

In the two failing `delegation-analysis-question` runs, `Skill` was called 0
times.

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
