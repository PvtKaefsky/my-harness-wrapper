# my-harness-wrapper

A configuration source for Claude Code sessions, cloud and local. It is not
an application. It has no build, no package manifest and no CI. Its twelve test
scripts, `scripts/test-attribution-guard.sh`,
`scripts/test-web-guidance-gate.sh`, `scripts/test-pr-comment-rules.sh`,
`scripts/test-orchestrator-rules.sh`, `scripts/test-team-practice-rules.sh`,
`scripts/test-install-settings.sh`, `scripts/test-hook-forwarding.sh`,
`scripts/test-session-check.sh`, `scripts/test-ab-probe.sh`,
`scripts/test-labels.sh`, `scripts/test-experiment-template.sh` and
`scripts/test-repository-templates.sh`, are run by hand and by the A/B probe.

The repository holds one payload, `config/`, and the scripts that deliver it
into a session's Claude config directory. It also holds two plugins, which
those scripts install from `config/plugins.tsv`: `plugins/my-harness/`, which
is packaged for upload to claude.ai for Cowork sessions, and
`plugins/deslop-please/`, which is not.
`config/plugins.tsv` also names four third-party plugins, ECC, ponytail,
humanizer and Modern Web Guidance, which those scripts install from their
upstream marketplaces. Ponytail and humanizer are packaged for upload to
claude.ai for Cowork sessions, as `ponytail.plugin` and `humanizer.plugin`,
from upstream commits. `modern-web-guidance.plugin` is packaged the same way.
Whether Cowork loads it is not verified.
`docs/runbook.md` carries the steps.

## How delivery works

### Cloud sessions

1. The cloud environment runs the init script stored in its dialog. That text
   is a copy of `env/setup.sh`; the dialog holds the text, not a reference to
   this repository.
2. The init script writes `/home/user/bootstrap.log` and clones branch `main`
   of this repository `--depth 1` into `/opt/my-harness-wrapper`. The clone
   URL comes from `HARNESS_REPO_URL`, or from the script's own default where
   that variable is unset or empty.
3. The init script runs `scripts/bootstrap.sh` from that clone. A failed clone
   skips that step and is named in the log.
4. `scripts/bootstrap.sh` creates `/root/.claude`, symlinks `/home/user/.claude`
   to it where that path is absent, copies `config/CLAUDE.md` there, merges
   `config/settings.json` there, sets both `*.gpgsign` keys to `false`
   globally, sets the global `core.hooksPath` to `git-hooks/` in the clone,
   installs the plugins named in `config/plugins.tsv`, runs
   `scripts/plugin-dependencies.sh` after each plugin's install, and writes
   `/root/.claude/.my-harness-wrapper.manifest.json`.
5. Claude Code launches and reads `/root/.claude`, which `/home/user/.claude`
   also resolves to.

The init script fetches this repository itself, so no session needs it
attached. It runs only in the session that builds the environment snapshot.
Every later session restores that snapshot and skips it, keeping the
`/opt/my-harness-wrapper` clone that build made. A change under `config/`,
`scripts/` or `env/` therefore reaches a session only after a rebuild. The only
rebuild an operator controls is a change to the pasted init script text.

### Local sessions

1. The user runs `scripts/install-local.sh` in Git Bash, or in bash elsewhere,
   from any checkout of this repository.
2. It clones branch `main` `--depth 1` into the deployed copy,
   `${CLAUDE_CONFIG_DIR-$HOME/.claude}/my-harness-wrapper`, or brings an
   existing deployed copy to that branch's remote head, clean. The clone URL
   follows the init script's rule. A failed clone or refresh stops the run
   before anything else is written.
3. From the deployed copy, it copies `config/CLAUDE.md` into
   `${CLAUDE_CONFIG_DIR-$HOME/.claude}`, merges `config/settings.json` into that
   directory's `settings.json` with `env.HARNESS_DIR` set to the deployed copy
   and `env.GIT_CONFIG_COUNT`, `env.GIT_CONFIG_KEY_0` and `env.GIT_CONFIG_VALUE_0`
   setting `core.hooksPath` to the deployed copy's `git-hooks/` for the git
   commands Claude Code sessions start, sets both `*.gpgsign` keys to `false`
   globally, unsets a global `core.hooksPath` naming the deployed copy's
   `git-hooks/`, installs the plugins named in
   `config/plugins.tsv`, runs the deployed copy's
   `scripts/plugin-dependencies.sh` after each plugin's install, and writes the
   manifest with a `local_checkout` field naming the deployed copy.

The dependency step reads each plugin's `installPath` from
`claude plugin list --json`. Where a name in that plugin's `package.json`
`dependencies` has no `node_modules/<name>/package.json` there, it runs
`npm ci --omit=dev --ignore-scripts --no-audit --no-fund` in that path; where
every name resolves, it runs nothing. The CLI installs `ecc@ecc` 2.2.3 without
its npm dependencies, which ECC's `SessionStart` hook needs.
4. Every Claude Code session started after that reads the directory. Its hook
   commands run the scripts in the deployed copy, through `HARNESS_DIR`.

The invoking checkout is not read for delivery, so a branch switch or an edit
in it changes no session. Merged changes reach local sessions only after the
installer runs again.

The default branch `main` holds this harness. Branch `platform/codex` holds the
Codex adapter. Cloud builds run `main`'s scripts as root, and local sessions'
hooks run them as the user, so write access to `main` is code execution in
every session.

## Structure

| Path | Role |
| --- | --- |
| `config/CLAUDE.md` | The instruction payload, delivered as `CLAUDE.md` in the config directory: `/root/.claude` in the cloud, `${CLAUDE_CONFIG_DIR-$HOME/.claude}` locally. |
| `config/settings.json` | Settings merged into the config directory's `settings.json`. It turns Claude Code's telemetry and error reports off and empties ponytail's webhook. Its `permissions.deny` rules refuse reads of secret files and edits of the deployed harness, and both installers add its `permissions.allow` and `permissions.deny` entries to the live lists without removing any. Its hook commands run the scripts under `${HARNESS_DIR:-/opt/my-harness-wrapper}`. |
| `config/plugins.tsv` | The plugins bootstrap installs. |
| `.claude-plugin/marketplace.json` | The plugin marketplace `my-harness-wrapper`. It lists the two plugins under `plugins/`. `claude plugin marketplace add` reads it. |
| `plugins/my-harness/` | The `my-harness` plugin: the `task-delegation`, `python-property-model-tests`, `edit-russian-technical-text`, `quick-human-readable-review`, `python-fp-refactor`, `repository-setup` and `research-workflow` skills, the project templates under `skills/repository-setup/templates/`, the `executor` and `analyst` agents, a `UserPromptSubmit` hook, a `PreToolUse` hook running the Modern Web Guidance gate `hooks/web-guidance-gate.sh`, and an eval suite under `evals/`. `plugins/my-harness/README.md` describes it. |
| `plugins/deslop-please/` | The `deslop-please` plugin: the `deslop-please` skill, which runs the deslop pass with the third-party linter `deslop-please`, and an eval suite under `evals/`. It has no hook. `plugins/deslop-please/README.md` describes it. |
| `env/setup.sh` | The init script pasted into the environment dialog. It clones this repository and is the only version source. |
| `scripts/bootstrap.sh` | The delivery step. Run by the init script, and by hand only in a disposable session, since it mutates the live config directory. |
| `scripts/install-local.sh` | The local delivery step. Run by the user from any checkout. Writes `${CLAUDE_CONFIG_DIR-$HOME/.claude}`, the deployed copy under it, and the global git config's signing keys. |
| `scripts/plugin-dependencies.sh` | Installs a delivered plugin's npm dependencies where any is unresolved, and runs nothing otherwise. Run by both delivery scripts after each plugin's install. Needs `npm` only where it installs. |
| `scripts/session-check.sh` | Reports what a session starts with, and prints a `NOTE` line for each hidden character in the working repository's instruction files. Run by the `SessionStart` hook in every session, and by hand. Reads the same `$HARNESS_DIR`. |
| `scripts/test-session-check.sh` | Runs the `scripts/session-check.sh` of its own tree in scratch repositories against the hidden-character scan's cases, one line per case. Run by hand only. |
| `scripts/verify.sh` | Reports what bootstrap left behind. Run by hand. Reads the delivered copy at `$HARNESS_DIR`, `/opt/my-harness-wrapper` by default. |
| `scripts/attribution-guard.sh` | Blocks a pull request, issue, comment, review or review reply body, or a commit a GitHub tool makes, carrying a Claude Code attribution line or a block-class hidden character, and tells the session to resend a description the create call returns with an attribution line. Run by the `PreToolUse` and `PostToolUse` hooks `config/settings.json` registers. |
| `scripts/test-attribution-guard.sh` | Runs the attribution guard in its own tree against a fixed set of cases, the hidden-character cases among them, directly and through the `PreToolUse` hook the tree's `config/settings.json` registers, one line per case. Run by hand only. |
| `scripts/test-web-guidance-gate.sh` | Runs the Modern Web Guidance gate of its own tree in scratch repositories against a fixed set of cases, directly and through the `PreToolUse` hook `plugins/my-harness/hooks/hooks.json` registers, one line per case. Run by hand only. |
| `scripts/test-pr-comment-rules.sh` | Checks the Pull request comments section of a `config/CLAUDE.md`, its own tree's unless an argument names another, for the subscription, the 30-minute check, the rules issue #113 adds and the cloud and local paths issue #111 adds, one line per check. Run by hand only. |
| `scripts/test-orchestrator-rules.sh` | Checks the Harness, Git workflow, A/B probes and Pull request comments sections of a `config/CLAUDE.md`, its own tree's unless an argument names another, for the orchestrator, nested-session, combined-branch and probe rules issue #137 adds, and checks that the file names no model, one line per check. Run by hand only. |
| `scripts/test-team-practice-rules.sh` | Checks the Language, Claims, Documentation, Writing code, Harness, Git workflow, Pull request comments and Issues sections of a `config/CLAUDE.md`, its own tree's unless an argument names another, for the team practice and label rules issue #146 adds, one line per check. Run by hand only. |
| `scripts/labels.sh` | Syncs a repository's `.github/labels.json` to the forge with `sync`, and applies its labels to one pull request or issue with `apply`, refusing a label a workflow triggers on or tests. Run by sessions from the deployed copy, and by hand. |
| `scripts/test-labels.sh` | Runs the `scripts/labels.sh` of its own tree with a stub `gh`, one line per case. Run by hand only. |
| `scripts/test-experiment-template.sh` | Runs the `repository-setup` skill's Python experiment template on a fixture project, one line per case. Needs Python with `hydra-core` and `python-dotenv`, and skips every case without them. Run by hand only. |
| `scripts/test-repository-templates.sh` | Checks that every template the `repository-setup` skill or `docs/repository-layouts.md` names exists, and runs the template probe checks and architecture test on fixtures, one line per case. Run by hand only. |
| `.github/labels.json` | This repository's label families, in the schema `scripts/labels.sh` reads. |
| `scripts/test-install-settings.sh` | Runs the settings merge programs of its own tree's `scripts/install-local.sh` and `scripts/bootstrap.sh`, and the `settings_carries` function of its `scripts/verify.sh`, on sample live files. It checks that existing allow and deny entries survive, that each delivered entry is added once, that a second run changes nothing, that a shape that is not an array fails, that `verify.sh` passes a live list with extra entries and fails one missing a delivered entry, and that it passes the `env` both merges write and fails one with another value, one line per check. Three optional arguments name other copies of the three scripts. Run by hand only. |
| `scripts/test-hook-forwarding.sh` | Runs the `git-hooks/` of its own tree in scratch repositories through six `core.hooksPath` cases, six commit-message cases and the hidden-character cases C1 to C11 and F1 to F22, one line per case. Run by hand only. |
| `git-hooks/` | The git hooks `core.hooksPath` names: globally in the cloud, and locally only for the git commands Claude Code sessions start. One file per hook name git looks up. `commit-msg` rejects a message carrying a Claude Code attribution line or a block-class hidden character, and `pre-commit` rejects a staged change that adds one; every hook then runs the hook of that name git would run without the harness. `git-hooks/lib/attribution.ere` is the pattern both it and the attribution guard read. |
| `scripts/check-hook-matchers.sh` | Compares the tool names the attribution guard's hook matchers name with a file of a session's tool names. Run by hand only. |
| `scripts/ab-probe.sh` | The A/B probe runner. Runs a project's `probe/checks.sh` in Docker on a baseline and a candidate commit of a repository, using the candidate's `probe/` for both, prints one line per check and a verdict, and exits 1 on a regression and 2 where the probe could not run. Run by hand. |
| `scripts/test-ab-probe.sh` | Runs the `scripts/ab-probe.sh` of its own tree against a fixture repository with a fake `docker`, one line per case. Needs no Docker and no network. Run by hand only. |
| `probe/` | This repository's A/B probe: `Dockerfile`, `compose.yaml`, `checks.sh` and `fake-claude.sh`, which `scripts/ab-probe.sh` runs on two commits. Its checks are one per `scripts/test-*.sh` and an install check, which runs `env/setup.sh` and `scripts/verify.sh` with a fake `claude` CLI. `docs/scripts.md` describes it. |
| `.gitattributes` | The line-ending rule. Git checks out every file it detects as text with LF line endings, on every platform. |
| `README.md` | This file. |
| `docs/` | Documentation. |

## The config/plugins.tsv format

One plugin per line, in two tab-separated fields.

| Field | Value |
| --- | --- |
| `marketplace_source` | Anything `claude plugin marketplace add` accepts. |
| `plugin_id` | `name@marketplace`. |

Blank lines and lines beginning with `#` are skipped. Both scripts skip them
the same way. `docs/scripts.md` carries where the two loops diverge.

## Usage

### Deploy a change

Set the four identity variables and `HARNESS_ASSIGNEE` in the environment
variables panel. A change under `config/`, `scripts/` or `env/` bumps the
`export BOOTSTRAP_VERSION=` line of `env/setup.sh` in its last commit. After
the merge to `main`, the file's contents are pasted into the environment
dialog unchanged. A version number is never reused for different contents.
Nothing needs attaching. The full order, and the facts that fix it, are in
`docs/runbook.md`.

### Install or update locally

Git Bash, Node with `npm`, `git` and `jq` are prerequisites. From any
checkout, on any branch:

```
bash scripts/install-local.sh
```

The exit status is the failure count. `docs/runbook.md` carries the
prerequisites and how to read the log.

### Verify a session

```
bash /opt/my-harness-wrapper/scripts/verify.sh
```

Locally, against the deployed copy:

```
d="${CLAUDE_CONFIG_DIR-$HOME/.claude}/my-harness-wrapper"; HARNESS_DIR="$d" bash "$d/scripts/verify.sh"
```

Exit 0 means no check failed. A `NOTE` line can appear alongside it and does
not set the exit status. `docs/runbook.md` decodes each `FAIL` and `NOTE`
line.

### Probe two commits

```
bash scripts/ab-probe.sh . origin/main HEAD
```

It needs Docker with Compose. A `regression` line and exit 1 mean a check
passing on the first commit fails or is missing on the second.

### Sync a repository's labels

From a checkout of a repository that tracks `.github/labels.json`:

```
bash <harness>/scripts/labels.sh sync
```

It creates each listed label the repository lacks and updates each that
differs, and touches no other label.

### Make an environment change

A rule that governs how the agent works across every project belongs in
`config/CLAUDE.md`, on a `<prefix>/<words>` or `<prefix>/<n>-<words>` branch
named for the task or its one issue, past the review gate. That file's
Environment changes section decides where a change belongs, and
`docs/runbook.md` carries the before-commit procedure.

## Documentation

`docs/README.md` indexes every document under `docs/`.
