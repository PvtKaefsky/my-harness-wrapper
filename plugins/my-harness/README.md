# my-harness

A Claude Code plugin. It ships the task-delegation procedure, under which an
orchestrator session delegates every part of a coding task to nested sessions,
and a session without a nested-session tool delegates each subtask to a routed
subagent. It also ships six other skills, and a gate that limits the
Modern Web Guidance plugin to web front-end work. The marketplace
`my-harness-wrapper`, at the repository root, lists it.

## Contents

| Path | Role |
| --- | --- |
| `.claude-plugin/plugin.json` | The manifest: name `my-harness` and the version. |
| `skills/task-delegation/SKILL.md` | The whole procedure: which section a session follows; the limits of a nested session and of a delegated subagent; a question; the orchestrated path, with the orchestrator's actions, scratch files, models, decomposition with a major change's spec and documentation nested sessions, the combined branch, the nested-session brief, running, verification, the ponytail review, the merge, the combined pull request, the A/B probe, bounds and report; the review budget, the labels each session applies, the research escalation and the deslop pass, with who runs it on which branch and the native or container path; and the subagent path, with its deslop pass and ponytail review before a pull request opens. |
| `skills/task-delegation/references/routing.md` | The routing tables of the subagent path: coding, for a session with no nested-session tool, and analysis, for an analysis-only session. |
| `skills/python-property-model-tests/SKILL.md` | Writing Python tests that a unit keeps a property across many inputs or operation sequences: tool choice, property kinds, input strategies, state machines, failing examples and CI determinism. |
| `skills/edit-russian-technical-text/SKILL.md` | Rules for editing Russian technical prose while keeping its meaning, terms and requirements, with before and after examples. |
| `skills/quick-human-readable-review/SKILL.md` | The shape of a summary of a finished stage of work or an experiment series: outcome, confirmed results, open questions and next step. |
| `skills/python-fp-refactor/SKILL.md` | Steps for moving the decisions in Python code that mixes them with I/O or state into functions on values, keeping its behaviour. |
| `skills/repository-setup/SKILL.md` | The order in which a session creates a repository, the top-level layout rules for a new repository and for a top-level directory added to an existing one, and which template each kind of repository takes. |
| `skills/repository-setup/templates/` | The files the skill copies into a project: `docs/` (component spec, specs index, glossary, architecture, benchmark record), `research/` (project and per-hypothesis records), `architecture-test/` (a Python architecture test), `python-experiment/` (the Python experiment layer, whose `README.md` lists its files), `probe/checks.sh` (the `quickstart` and `spec-trace` checks) and `github/labels.json` (the project label families). `scripts/test-repository-templates.sh` and `scripts/test-experiment-template.sh` test them. |
| `skills/research-workflow/SKILL.md` | What the agent decides and what it only proposes in research work: the boundary with the researcher, the modes, the task specification, stages S0 to S6, change categories, escalation, records and the definition of done. |
| `skills/research-workflow/references/stages.md` | Each stage's actions by mode, and the agent's rules for it. |
| `skills/research-workflow/references/records.md` | The `research/` layout, IDs and statuses, runs, provenance and documentation events. |
| `agents/executor.md` | The agent for a coding subtask no specialist matches, in a session with no nested-session tool. |
| `agents/analyst.md` | The agent for an analysis subtask no specialist matches, in an analysis-only session such as Cowork. |
| `hooks/hooks.json` | A `UserPromptSubmit` hook printing one line that points every prompt at the `task-delegation` skill, a `PreToolUse` hook with matcher `Skill\|Bash`, and a `PostToolUse` hook with matcher `Skill`, each running `hooks/web-guidance-gate.sh` with a 10-second timeout. |
| `hooks/web-guidance-gate.sh` | The gate: denies a `modern-web-guidance:` skill call or a run of the `modern-web-guidance` package outside web front-end work, and a package run with telemetry on; after a `modern-web-guidance:` skill call, adds context stating that the skill's reply section is not written. |
| `evals/` | The eval suite: one case directory per row of the case table under "Eval suite", each with a `prompt.md`, `graders/skill.md` and the reply graders that table names. |
| `evals/.gitignore` | Keeps `results/`, which each eval run writes, out of git. |

## Agents

| Agent | Tools | Model |
| --- | --- | --- |
| `my-harness:executor` | `Read`, `Write`, `Edit`, `Bash`, `Grep`, `Glob` | `inherit` |
| `my-harness:analyst` | `Read`, `Grep`, `Glob`, `Bash`, `WebSearch`, `WebFetch` | `inherit` |

Neither tool list carries `Agent`, so neither agent can start a subagent.

## The hooks

The `UserPromptSubmit` hook command is `printf '%s\n' '<line>'`, run by the
shell Claude Code runs hook commands in. A hook command that fails prints
nothing, and the prompt goes on without the line.

The `PreToolUse` hook command is
`bash "${CLAUDE_PLUGIN_ROOT}/hooks/web-guidance-gate.sh"`. It runs in every
session that loads this plugin, Cowork included, and needs `bash`, `jq` and
`git` there. The gate exits 2 with one stderr line to deny a call, and 0 for
every other call. Its marker files are under
`${CLAUDE_PLUGIN_DATA}/web-guidance-sessions/`. The `PostToolUse` hook runs
the same command; after a `modern-web-guidance:` skill call it prints one
`additionalContext` object and exits 0. `docs/scripts.md`, under
`plugins/my-harness/hooks/web-guidance-gate.sh`, carries its rules, and
`scripts/test-web-guidance-gate.sh` tests it.

## Eval suite

The suite measures whether each skill is invoked on a prompt its description
matches, and not invoked on a nearby prompt it does not. The five
`repository-setup` "invoke" cases, the five `task-delegation` cases and the
four `research-workflow` "invoke" cases also check the final reply for rules
the skill carries. No other case grades a skill's output.

Each case's `prompt.md` is a request worded as a user would type it, with its
material inline, and sets `max_turns: 8` and
`allowed_tools: [Read, Glob, Grep, Skill]`. Its grader `graders/skill.md`
is `type: tool_used` on `tool: Skill`, with an `input_match` for that skill
alone. An "invoke" case passes a run that calls the skill at least once. A "not
invoke" case adds `min: 0`, `max: 0` and `arm: both`, and passes a run that never
calls it. `task-delegation` has no "not invoke" case, because its description
applies to every task.

Those cases carry `type: regex` graders on the final reply as well, and a run
scores `1.0` only where every grader passes.

| Grader | Cases | Passes where the final reply |
| --- | --- | --- |
| `graders/layout-document.md` | `create-python-library`, `add-top-level-directory` | names `repository-layouts.md` or "layout document", in any casing |
| `graders/initial-branch.md` | `create-python-library` | holds `git init --initial-branch=main` |
| `graders/decomposition.md` | `delegation-coding-task` | holds `decomposition -> nested: 1` |
| `graders/brief.md` | `delegation-coding-task` | holds `nested-session -> base: main` |
| `graders/ponytail.md` | `delegation-coding-task` | holds `ponytail-review` followed later by "merg" or the word "ready", in any casing |
| `graders/decomposition.md` | `delegation-analysis-question` | holds `decomposition -> whole` |
| `graders/unavailable.md` | `delegation-no-nested-tool` | holds `nested-sessions -> unavailable` |
| `graders/no-nested-brief.md` | `delegation-analysis-question`, `delegation-no-nested-tool` | does not hold `nested-session -> base:` |
| `graders/budget.md` | `delegation-coding-task`, `delegation-oversized-task` | holds, on one line, "budget" and a number followed by "lines", "counted lines" or "changed lines", in any casing |
| `graders/review-guide.md` | `delegation-coding-task` | holds "review guide" or "assumptions it rests on", in any casing |
| `graders/decomposition.md` | `delegation-oversized-task` | holds `decomposition -> nested:` with a count of 4 or more |
| `graders/briefs.md` | `delegation-oversized-task` | holds two `nested-session -> base:` lines whose base is not `main` |
| `graders/merge.md` | `delegation-over-budget-part` | holds `ponytail-review` followed later by a merge of `#12`, in any casing |
| `graders/description-line.md` | `delegation-over-budget-part` | holds 740, 500 and "over", "exceed" or "above" within 200 characters, in any casing |
| `graders/not-returned.md` | `delegation-over-budget-part` | does not hold "send it back", "return it back", "send #12 back" or "return #12 back" without "not", "n't", "never" or "or" just before it |
| `graders/proposal.md` | `research-improve-approved` | holds `Proposal:` |
| `graders/question.md` | `research-ambiguous-design` | holds a line with `norm`, `reading`, `step 3`, `which` or `what` followed by `?`, in any casing |
| `graders/additional.md` | `research-core-additional` | holds a Markdown heading or bold label starting with "Additional", in any casing |
| `graders/causation.md` | `research-core-additional` | states that a correlation does not establish causation |
| `graders/escalate.md` | `research-new-hyperparameter` | holds "experimental change" or `Proposal:`, in any casing |
| `graders/hydra-config.md` | `setup-experiment-layer` | holds `conf/config.yaml` |
| `graders/make-target.md` | `setup-experiment-layer` | holds `make experiment` or `experiment EXP=` |
| `graders/run-metadata.md` | `setup-experiment-layer` | holds `metadata.json` |
| `graders/spec-path.md` | `setup-spec-template` | holds a `docs/specs/` path whose name holds `ratelimit`, `rate-limit` or `rate_limit`, in any casing |
| `graders/status-line.md` | `setup-spec-template` | holds the line `Status: active` |
| `graders/scenario-id.md` | `setup-spec-template` | holds a table cell holding only an ID such as `RATELIMIT-1` |
| `graders/import-walk.md` | `setup-architecture-test` | holds `ast.`, `import-linter` or `importlinter` |
| `graders/path-assertion.md` | `setup-architecture-test` | holds `is_dir(`, `.exists(`, `isdir(`, "does not exist" or "must exist" |

A run has no deployed copy of the harness, so the layout document cannot be
read in it.

`claude plugin eval` cannot start nested sessions: a run lists no
nested-session tool. The `task-delegation` graders therefore check the
decomposition line, the briefs, the budget, the review guide and the steps to
the merge the final reply states, never the tool calls. The
`delegation-coding-task`, `delegation-oversized-task` and
`delegation-over-budget-part` prompts state that the session is an
orchestrator in the desktop app and ask for the decomposition, the briefs or
the steps to the merge in place of the calls.

| Case | Skill | Expected | The prompt carries |
| --- | --- | --- | --- |
| `delegation-coding-task` | `task-delegation` | invoke | a statement that the session is an orchestrator in the desktop app, a Python script, a request to add a `--dry-run` flag and document it, and a request for each step up to the merge |
| `delegation-analysis-question` | `task-delegation` | invoke | a short Python function and a question about why it returns `None` for an empty list |
| `delegation-no-nested-tool` | `task-delegation` | invoke | a statement that the session is the terminal CLI with no nested-session tool, a Python script, and a request to plan a `--limit` flag and its test |
| `delegation-oversized-task` | `task-delegation` | invoke | a statement that the session is an orchestrator in the desktop app, and a bank reconciliation feature of about 600, 700 and 400 hand-written lines in three files |
| `delegation-over-budget-part` | `task-delegation` | invoke | a statement that the session is an orchestrator on the combined branch `release/recon`, a nested report of pull request #12 at 740 counted lines against a budget of 500, and a request for the steps to its merge and its line in the combined description |
| `research-improve-approved` | `research-workflow` | invoke | an approved `design.md`, the quantizer code and a request to improve the algorithm by normalizing the weights |
| `research-ambiguous-design` | `research-workflow` | invoke | an approved design whose step 3 says "scale each codeword by the norm of its cluster", the update function and a request to implement that step |
| `research-core-additional` | `research-workflow` | invoke | a 12-run table and a request for the analysis sections of `results.md`, the core analysis being compression ratio against codebook size, split by dataset |
| `research-new-hyperparameter` | `research-workflow` | invoke | an approved `evaluation.md` with one hyperparameter and a request to add a temperature and sweep it |
| `research-hypothesis-library` | `research-workflow` | not invoke | a Python `normalize_path` and a request for a Hypothesis `@given` test |
| `property-tests-serializer` | `python-property-model-tests` | invoke | a Python `encode`/`decode` pair and a request for tests |
| `property-tests-javascript` | `python-property-model-tests` | not invoke | a JavaScript function and a request for Jest tests |
| `russian-edit` | `edit-russian-technical-text` | invoke | a Russian technical paragraph and a request in Russian to make it clearer |
| `english-edit` | `edit-russian-technical-text` | not invoke | an English technical paragraph and a request to make it clearer |
| `benchmark-outcome` | `quick-human-readable-review` | invoke | the results of three benchmark runs and a request for their outcome |
| `diff-review` | `quick-human-readable-review` | not invoke | a unified diff and "Review this diff." |
| `untangle-io` | `python-fp-refactor` | invoke | a Python function that reads a file, decides prices and writes a result, and a request to untangle it |
| `add-type-hints` | `python-fp-refactor` | not invoke | a Python function mixing I/O and decisions, and a request to add type hints and change nothing else |
| `create-python-library` | `repository-setup` | invoke | a statement that the folder is empty and a request to set up a local repository for a Python library |
| `add-top-level-directory` | `repository-setup` | invoke | the tree of a Python library repository and a request for a release script in a new top-level directory |
| `edit-one-file` | `repository-setup` | not invoke | one Python function from an existing repository and a request to rename a parameter in that file only |
| `setup-experiment-layer` | `repository-setup` | invoke | the tree of a Python research project and a request for the experiment layer, listing every file |
| `setup-spec-template` | `repository-setup` | invoke | the tree of a repository with `docs/specs/` and a request for the rate limiter's spec |
| `setup-architecture-test` | `repository-setup` | invoke | a dependency rule from `docs/architecture.md`, the tree of a Python repository and a request for a test enforcing it |

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

Every run of the final version of each case below scored 1.0 with
`--model claude-opus-5-5` and `--ablation none`: the five `research-*` cases,
two runs per "invoke" case and three for `research-hypothesis-library`, in
pull request #149; the three `setup-*` cases, `create-python-library` and
`add-top-level-directory` in pull request #151; and the five `delegation-*`
cases in pull request #152.

The `task-delegation` cases were measured on 2026-11-24 with CLI 2.1.317,
`--model claude-opus-5-5`, `--ablation none`, `--runs 3` and
`--case 'delegation-*'`, against this plugin at version 0.5.0 at commit
`5f52555`. The run cost $1.54 and exited 0.

| Case | Score | Runs passed | Cost (USD) |
| --- | --- | --- | --- |
| `delegation-coding-task` | 1.0 | 3 of 3 | 0.60 |
| `delegation-analysis-question` | 1.0 | 3 of 3 | 0.44 |
| `delegation-no-nested-tool` | 1.0 | 3 of 3 | 0.50 |

The other cases were measured on 2026-11-23 with CLI 2.1.317,
`--model claude-opus-5-5`, `--ablation none` and `--runs 3`, against this
plugin at version 0.4.0.

| Case | Score | Runs passed | Cost (USD) |
| --- | --- | --- | --- |
| `property-tests-serializer` | 1.0 | 3 of 3 | 0.59 |
| `property-tests-javascript` | 1.0 | 3 of 3 | 0.39 |
| `russian-edit` | 1.0 | 3 of 3 | 0.26 |
| `english-edit` | 1.0 | 3 of 3 | 0.26 |
| `benchmark-outcome` | 1.0 | 3 of 3 | 0.39 |
| `diff-review` | 1.0 | 3 of 3 | 0.35 |
| `untangle-io` | 1.0 | 3 of 3 | 0.39 |
| `add-type-hints` | 1.0 | 3 of 3 | 0.27 |
| `create-python-library` | 1.0 | 3 of 3 | 0.43 |
| `add-top-level-directory` | 1.0 | 3 of 3 | 0.39 |
| `edit-one-file` | 1.0 | 3 of 3 | 0.34 |

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
