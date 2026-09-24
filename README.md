# my-harness-wrapper

A configuration source for Claude Code cloud sessions. It is not an
application. It has no build, no package manifest and no CI. Its one test
script, `scripts/test-attribution-guard.sh`, is run by hand.

The repository holds one payload, `config/`, and the scripts that deliver it
into a session's Claude config directory.

## How delivery works

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
| `env/setup.sh` | The init script pasted into the environment dialog. It clones this repository and is the only version source. |
| `scripts/bootstrap.sh` | The delivery step. Run by the init script, and by hand only in a disposable session, since it mutates the live config directory. |
| `scripts/session-check.sh` | Reports what a session starts with. Run by the `SessionStart` hook in every session, and by hand. Reads the same `$HARNESS_DIR`. |
| `scripts/verify.sh` | Reports what bootstrap left behind. Run by hand. Reads the delivered copy at `$HARNESS_DIR`, `/opt/my-harness-wrapper` by default. |
| `scripts/attribution-guard.sh` | Blocks a pull request or issue body carrying a Claude Code attribution line, and tells the session to resend a description the create call returns with one. Run by the `PreToolUse` and `PostToolUse` hooks `config/settings.json` registers. |
| `scripts/test-attribution-guard.sh` | Runs the attribution guard in its own tree against a fixed set of cases, one line per case. Run by hand only. |
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

Set the four identity variables in the environment variables panel. A change
under `config/`, `scripts/` or `env/` bumps the `export BOOTSTRAP_VERSION=`
line of `env/setup.sh` in its last commit. After the merge to `main`, the
file's contents are pasted into the environment dialog unchanged. A version
number is never reused for different contents. Nothing needs attaching. The
full order, and the facts that fix it, are in `docs/runbook.md`.

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
