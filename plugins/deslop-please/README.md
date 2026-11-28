# deslop-please

A Claude Code plugin with one skill, `deslop-please:deslop-please`. The skill
tells a session when and how to run the third-party structure linter
`deslop-please`, from `https://github.com/Bor4brn/deslop-please`, on a change
in a Rust, Python, TypeScript or JavaScript repository, and what to do with
each finding the change introduces. The marketplace `my-harness-wrapper`, at
the repository root, lists it.

The plugin ships no binary. `scripts/deslop-install.sh` installs the
`deslop-please` binary and its indexers at the versions
`config/deslop-please.pins` names, and installs nothing on native Windows.
`scripts/deslop-run.sh` runs the same pinned tool in a Linux container, the
pass's container path. The plugin ships no hook, and it is not packaged for
Cowork.

| Host | Path the pass takes |
| --- | --- |
| Native Windows | The container |
| Elsewhere, `deslop-please` on `PATH` | The native binary |
| Elsewhere, no binary, `docker info` succeeding | The container |
| Elsewhere, neither | None: the pass is skipped |

## Contents

| Path | Role |
| --- | --- |
| `.claude-plugin/plugin.json` | The manifest: name `deslop-please` and the version. |
| `skills/deslop-please/SKILL.md` | The deslop pass: its rank, the path rule and the container runner's contract, the baseline in a scratch checkout of the merge base, the head run and its exit codes on each path, the fallback on exit 2, the step for each finding and the decline grounds, the six lints per language, the allowlist rule, the cap of two head runs and the orchestrator's runs, the report line, what is not adopted from upstream, and native Windows. |
| `evals/` | The eval suite: one case directory per row of the case table under "Eval suite", each with a `prompt.md`, `graders/skill.md` and the reply graders that table names. |
| `evals/.gitignore` | Keeps `results/`, which each eval run writes, out of git. |

## Eval suite

Each case's `prompt.md` is a request to run the pass, and a case cannot run
commands. It sets `max_turns: 8` and `allowed_tools: [Read, Glob, Grep,
Skill]`. The `module-cycle-python` and `migrations-wide-directory` prompts
carry the repository's tree, the change, the baseline run's `wrote <N>
entries` line and the head run's JSON inline, and state that the runs were
made on Linux. That output is written by hand in the format the tool at commit
`cfabfb9` printed on Linux on 2026-11-27; no run of the tool on these cases
recorded it. `graders/skill.md` is `type: tool_used` on `tool: Skill`, with an
`input_match` for `deslop-please` alone. A run scores `1.0` only where every
grader passes.

| Case | The prompt carries | Reply graders |
| --- | --- | --- |
| `module-cycle-python` | a Python repository whose branch adds a `module-cycle` between `shop::catalog` and `shop::pricing` through the constant `CURRENCY`, and a baseline `module-cycle` in `shop::billing` | `graders/fix.md`, a regex for `CURRENCY` within 300 characters of "move", "extract", "lift" or "relocate"; `graders/baseline-count.md`, a regex for "baseline" and the count 1 on one line; `graders/baseline-untouched.md`, a regex that fails where a `shop/billing/` file name is followed on the next lines by a code block |
| `migrations-wide-directory` | a Django project whose branch adds the 16th entry of `orders/migrations/`, and a `wide-directory` finding on it | `graders/decline.md`, a regex for "decline" within 300 characters of "Django" or "framework"; `graders/files-kept.md`, an LLM grader that the reply moves, splits, squashes, merges or deletes no migration file |
| `path-native-windows` | a TypeScript repository on a host where `uname -s` prints `MINGW64_NT-10.0-26200`, `command -v deslop-please` finds a binary, `docker info` exits 0 and `HARNESS_DIR` names the deployed copy; it asks for the baseline and head commands | `graders/container-baseline.md`, a regex for `deslop-run.sh` and `--update-allow` on one line; `graders/container-head.md`, a regex for `deslop-run.sh`, `--allow` and `--json` on one line; `graders/no-native.md`, an LLM grader that the reply takes the container path through `deslop-run.sh` and not the native binary |

Run it from the repository root, with an output directory outside the
repository:

```bash
claude plugin eval plugins/deslop-please --trust-plugin --no-publish --ablation none --model claude-opus-5-5 --runs 3 --output-dir <scratch dir> </dev/null
```

The LLM graders run on the default judge model, `haiku`.

### Measured scores

Measured for pull request #172 with CLI 2.1.317, `--model claude-opus-5-5`
and `--runs 3`, against this plugin at version 0.1.0. The run cost $3.14.

| Case | Score | Runs passed |
| --- | --- | --- |
| `module-cycle-python` | 1.0 | 3 of 3 |
| `migrations-wide-directory` | 1.0 | 3 of 3 |
| `path-native-windows` | 1.0 | 3 of 3 |
