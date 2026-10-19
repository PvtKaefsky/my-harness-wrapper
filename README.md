# my-harness-wrapper

A configuration source for Claude Code and Codex cloud sessions. It is not an
application. It has no build, no package manifest and no CI. Its test scripts
are run by hand or by the Codex setup script.

The repository holds a Claude payload in `config/`, a Codex payload in
`config/codex/`, and separate scripts that deliver each one.
The Codex adapter delivers shared instructions, verifies their integrity, and
provides a commit command that checks the environment's Git identity.
It does not install ECC or register automatic hooks.
Its setup, startup, limitations, and exact Environment UI text are in
[`docs/codex.md`](docs/codex.md).

## How Claude delivery works

1. The cloud environment runs the init script stored in its dialog. That text
   is a copy of `env/setup.sh`; the dialog holds the text, not a reference to
   this repository.
2. The init script writes `/home/user/bootstrap.log` and clones this repository
   `--depth 1` into `/opt/my-harness-wrapper`. The clone URL comes from
   `HARNESS_REPO_URL`, or from the script's own default where that variable is
   unset or empty.
3. The init script runs `scripts/bootstrap.sh` from that clone. A failed clone
   skips that step and is named in the log.
4. `scripts/bootstrap.sh` creates `/root/.claude`, symlinks `/home/user/.claude`
   to it where that path is absent, copies `config/CLAUDE.md` there, merges
   `config/settings.json` there, sets both `*.gpgsign` keys to `false`
   globally, installs the plugins named in `config/plugins.tsv`, and writes
   `/root/.claude/.my-harness-wrapper.manifest.json`.
5. Claude Code launches and reads `/root/.claude`, which `/home/user/.claude`
   also resolves to.

The init script fetches this repository itself, so no session needs it
attached. It runs only in the session that builds the environment snapshot.
Every later session restores that snapshot and skips it, keeping the
`/opt/my-harness-wrapper` clone that build made. A change under `config/`,
`scripts/` or `env/` therefore reaches a session only after a rebuild. The only
rebuild an operator controls is a change to the pasted init script text.

## Structure

| Path | Role |
| --- | --- |
| `config/CLAUDE.md` | The instruction payload, delivered as `/root/.claude/CLAUDE.md`. |
| `config/settings.json` | Settings merged into `/root/.claude/settings.json`. |
| `config/plugins.tsv` | The plugins bootstrap installs. |
| `config/codex/` | The Codex instruction payload and adapter version. |
| `AGENTS.md` | Development instructions for Codex working in this repository. |
| `env/setup.sh` | The init script pasted into the environment dialog. It clones this repository and is the only version source. |
| `env/setup-codex.sh` | Tests and installs the Codex adapter from the attached checkout. |
| `scripts/bootstrap.sh` | The delivery step. Run by the init script, and by hand only in a disposable session, since it mutates the live config directory. |
| `scripts/session-check.sh` | Reports what a session starts with. Run by the `SessionStart` hook in every session, and by hand. Reads the same `$HARNESS_DIR`. |
| `scripts/verify.sh` | Reports what bootstrap left behind. Run by hand. Reads the delivered copy at `$HARNESS_DIR`, `/opt/my-harness-wrapper` by default. |
| `scripts/attribution-guard.sh` | Blocks a pull request or issue body carrying a Claude Code attribution line, and tells the session to resend a description the create call returns with one. Run by the `PreToolUse` and `PostToolUse` hooks `config/settings.json` registers. |
| `scripts/test-attribution-guard.sh` | Runs the attribution guard in its own tree against a fixed set of cases, one line per case. Run by hand only. |
| `scripts/*codex*.sh` | Codex delivery, verification, explicit attribution checking, and regression tests. |
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

### Prepare Codex

Attach this repository at `/workspace/my-harness-wrapper`, then run:

```bash
bash /workspace/my-harness-wrapper/env/setup-codex.sh
```

Save the startup instructions from `docs/codex.md` in the Codex environment.
The setup script prepares files; the saved startup instructions tell the agent
to read the deployed policy in each task.
Verification of those files does not establish that a managed task loaded them.

Make commits from the target repository through the identity guard:

```bash
bash /workspace/my-harness-wrapper/scripts/commit-codex.sh -F /tmp/commit-message.txt
```

All four author and committer identity variables must be set in the environment.
The guard rejects missing identity before Git can use global defaults.
It is an explicit command; it does not install a Git hook.

### Deploy a Claude change

Set the four identity variables and `HARNESS_ASSIGNEE` in the environment
variables panel. A change under `config/`, `scripts/` or `env/` bumps the
`export BOOTSTRAP_VERSION=` line of `env/setup.sh` in its last commit. After
the merge to `main`, the file's contents are pasted into the environment dialog
unchanged. A version number is never reused for different contents. Nothing
needs attaching. The full order, and the facts that fix it, are in
`docs/runbook.md`.

### Verify a session

```
bash /opt/my-harness-wrapper/scripts/verify.sh
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
