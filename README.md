# my-harness-wrapper

A configuration source for Claude Code sessions, cloud and local. It is not
an application. It has no build, no package manifest and no CI. Its one test
script, `scripts/test-attribution-guard.sh`, is run by hand.

The repository holds one payload, `config/`, and the scripts that deliver it
into a session's Claude config directory.

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
   directory's `settings.json` with `env.HARNESS_DIR` set to the deployed copy,
   sets both `*.gpgsign` keys to `false` globally, sets the global
   `core.hooksPath` to the deployed copy's `git-hooks/`, installs the plugins named in
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
| `config/settings.json` | Settings merged into the config directory's `settings.json`. Its hook commands run the scripts under `${HARNESS_DIR:-/opt/my-harness-wrapper}`. |
| `config/plugins.tsv` | The plugins bootstrap installs. |
| `env/setup.sh` | The init script pasted into the environment dialog. It clones this repository and is the only version source. |
| `scripts/bootstrap.sh` | The delivery step. Run by the init script, and by hand only in a disposable session, since it mutates the live config directory. |
| `scripts/install-local.sh` | The local delivery step. Run by the user from any checkout. Writes `${CLAUDE_CONFIG_DIR-$HOME/.claude}`, the deployed copy under it, and the global git config. |
| `scripts/plugin-dependencies.sh` | Installs a delivered plugin's npm dependencies where any is unresolved, and runs nothing otherwise. Run by both delivery scripts after each plugin's install. Needs `npm` only where it installs. |
| `scripts/session-check.sh` | Reports what a session starts with. Run by the `SessionStart` hook in every session, and by hand. Reads the same `$HARNESS_DIR`. |
| `scripts/verify.sh` | Reports what bootstrap left behind. Run by hand. Reads the delivered copy at `$HARNESS_DIR`, `/opt/my-harness-wrapper` by default. |
| `scripts/attribution-guard.sh` | Blocks a pull request, issue, comment, review or review reply body carrying a Claude Code attribution line, and tells the session to resend a description the create call returns with one. Run by the `PreToolUse` and `PostToolUse` hooks `config/settings.json` registers. |
| `scripts/test-attribution-guard.sh` | Runs the attribution guard in its own tree against a fixed set of cases, directly and through the `PreToolUse` hook the tree's `config/settings.json` registers, one line per case. Run by hand only. |
| `git-hooks/` | The git hooks the global `core.hooksPath` names, one file per hook name git looks up. `commit-msg` rejects a message carrying a Claude Code attribution line; every hook then runs the repository's own hook of that name. `git-hooks/lib/attribution.ere` is the pattern both it and the attribution guard read. |
| `scripts/check-hook-matchers.sh` | Compares the tool names the attribution guard's hook matchers name with a file of a session's tool names. Run by hand only. |
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

### Make an environment change

A rule that governs how the agent works across every project belongs in
`config/CLAUDE.md`, on a `<prefix>/<words>` or `<prefix>/<n>-<words>` branch
named for the task or its one issue, past the review gate. That file's
Environment changes section decides where a change belongs, and
`docs/runbook.md` carries the before-commit procedure.

## Documentation

`docs/README.md` indexes every document under `docs/`.
