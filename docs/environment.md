# Environment

What the sandbox is, and what the delivery path may assume about it.

## Established facts

1. **Root-only container.** Setup scripts run as `uid=0` with `HOME=/root`.
   There is no `user` account. `/home/user` exists and is owned by `root:root`.
   Never use `runuser` or `su`, and never create accounts.
2. **The init script fetches the repository itself.** It clones branch `main`
   of `$HARNESS_REPO_URL`, or of its own default where that variable is unset
   or empty, `--depth 1` into
   `/opt/my-harness-wrapper`, and runs `scripts/bootstrap.sh` from there. No
   session needs the repository attached.
3. **An attached repository is cloned under `/home/user`.** The environment
   manager clones each attached repository to `/home/user/<name>` before a
   session starts, with `--depth 50`, not shallow. Only the default branch is
   fetched by name.
4. **Private clones fail.** Unauthenticated HTTPS clones of private github.com
   repositories fail with exit 128 and `could not read Username`. Public clones
   work, because github.com is on the Trusted network allowlist. The init
   script supplies no credential of its own, so a private repository needs one
   embedded in `HARNESS_REPO_URL`.
5. **A non-zero exit aborts session startup.** `env/setup.sh` always ends
   `exit 0`. Failures go into the log, never into the exit code.
   `scripts/bootstrap.sh` may exit non-zero, and the init script records that as
   `bootstrap_exit=N`.
6. **`/home/user/.claude` does not exist at setup time.**
   `scripts/bootstrap.sh` creates it as a symlink to `/root/.claude`, so both
   candidate `HOME` values resolve to one tree.
7. **`$HOME` is `/root`, and other homes exist.** `/home/claude` holds a
   `.claude` directory of harness files, with no `settings.json`, no `CLAUDE.md`
   and no manifest. `/home/ubuntu` has no `.claude`. `getent passwd 0` gives
   `/root`. `scripts/verify.sh` resolves the config directory rather than
   searching a candidate list, because a list omitting the live directory would
   report clean.
8. **`claude plugin` resolves before Claude Code launches.** From inside the
   init script, `claude plugin marketplace add` and `claude plugin install`
   each exit 0. The declarative plugin fallback is retired.
9. **A snapshot-delivered `UserPromptSubmit` hook fires and reaches context.**
   The command string the snapshot delivered arrives beside a session's prompt.
   It is the string `config/settings.json` held at the snapshot's commit, which
   a later edit to that file does not change.
10. **Commits carry the panel identity, unsigned.** The panel identity is the
    pair the four `GIT_*` variables hold — not the `Claude` and
    `noreply@anthropic.com` pair that `/root/.gitconfig` holds. Both
    `*.gpgsign` keys read `false`, `git var` resolves both roles to the panel
    identity, and `%G?` reads `N`. `%G?` does not separate an unsigned commit
    from an SSH-signed one whose `gpg.ssh.allowedSignersFile` is unset, so the
    raw commit objects settle it: neither of the two commits read that way
    carries a `gpgsig` header.
11. **Panel variables do not reach the init script.** Three builds logged
    `HARNESS_REPO_URL -> unset` while the environment variables panel held a
    value, and each of those sessions' own environments held that variable.
    The log line separates the variable's three states inside the init script;
    it says nothing about what the panel holds, which is read from the panel.
    The init script therefore carries its own default clone URL.

## The harness Stop hook

`/root/.claude/stop-hook-git-check.sh` runs when a turn ends. It is not
delivered by this repository, and `config/settings.json` does not register it.

It exits 0 without checking anything in three states: `stop_hook_active` reads
`true` in its JSON input, the working directory is not a git repository, or the
repository has no remote.

| Condition | Exit |
| --- | --- |
| Staged or unstaged changes present | 2 |
| Untracked files outside `.gitignore` present | 2 |
| Local-only commits git will show as Unverified, checked only where `git branch --show-current` is non-empty, `commit.gpgsign` is `true` and `origin/<branch>` resolves | 2 |
| Commits on the branch not present on its upstream, checked only where `git branch --show-current` is non-empty | 2 |
| None of the above | 0 |

Both branch-scoped checks sit inside one `[[ -n "$current_branch" ]]` block. On a
detached HEAD that block is skipped whole, so the script reaches exit 0 without
evaluating either, however many unsigned or unpushed commits the branch carries.

The hook reads `stop_hook_active` first, so it blocks a stop and passes the next
consecutive one. A hold therefore costs one wake-up, and the hook does not block
two consecutive stops. Each re-armed wait opens a fresh cycle of its own.

The harness writes the file during session start, in a session that builds the
snapshot and in one that restores it. In the one restoring session observed,
under "Snapshot caching", its mtime was 17:53:14, after boot.

## Delivery

The init script text lives in the environment dialog, not in this repository.
`env/setup.sh` is the file that text is pasted from. Nothing in this repository
executes it.

The init script reads `HARNESS_REPO_URL` and assigns its own default only where
that variable is unset or empty, so a value that reaches it is never
overwritten. It logs the variable's state, which source the clone URL came
from, the clone's exit status, and the cloned commit. A failed clone skips
bootstrap and is named in the log. The script always ends `exit 0`.

`scripts/bootstrap.sh` runs from `/opt/my-harness-wrapper`, as root, and is the
only step that writes `/root/.claude`.

`scripts/bootstrap.sh` copies the payload and merges the settings from the clone
of `main` made at build time. A merged change therefore reaches the next build
with no paste. No operator action triggers that build. The pasted copy supplies
the clone URL and the version marker.

## Waiting for a reviewer

The Agent tool launches every agent asynchronously, reviewer or not, including
when called with `run_in_background: false`. Its result carries an agent id and
the statement that the agent is working in the background.

Completion arrives as a task notification that re-invokes the session, for any
agent the tool launched. Nothing is polled and no timer is set.

The turn does not stay open across a review. Each completion notice opens a new
turn, and the harness Stop hook blocks that turn once, for the staged changes
the reviewer is reading. A hold therefore costs one wake-up per reviewer round.

`Monitor` does not change this. It returns immediately, saying to keep working,
and its events arrive as notifications like any other. A condition built from
the reviewer task files under the session's `tasks/` directory is unsound in
both directions: a quiet file does not imply completion, and a finished
reviewer's file measures the same 130 bytes as a running one's. Those files
carry the agent id and a pointer, not the transcript, and nothing else the
harness exposes here separates a finished reviewer from a running one.

## ECC's unset options

The paths in this section are inside the installed plugin's own tree, under
`/root/.claude/plugins/marketplaces/ecc/`, not in this repository.

`claude plugin install` reported two `userConfig` options not yet set. Neither
is set, so both defaults apply.

| Option | Type | Default | The manifest's description |
| --- | --- | --- | --- |
| `hooks_enabled` | boolean | `true` | Run ECC's local lifecycle, quality, and safety automation. Disable this to keep skills and commands without local hook automation. |
| `hook_profile` | string | `standard` | Choose minimal, standard, or strict. Invalid values safely fall back to standard. |

Both options reach this repository's sessions, and `hooks_enabled` outranks
`hook_profile`. In the plugin's own tree, `scripts/lib/hook-flags.js`'s
`isHookEnabled` returns false
first where `hooks_enabled` is off, then false where the hook's id appears in
`ECC_DISABLED_HOOKS`, and otherwise runs the hook only where the profile is in
the list that hook declares.

Twelve of the plugin's `hooks/hooks.json` entries invoke its
`scripts/hooks/run-with-flags.js`
directly, and it reads the profile list. `plugin-hook-bootstrap.js` carries no profile
logic; it spawns whatever script follows it. `lifecycle-hook-bootstrap.js` and
`session-start-bootstrap.js` do not spawn their target either: each resolves
`run-with-flags.js` and delegates to it, passing the target along as an
argument. Five files under the plugin's
`scripts/hooks/` call `isHookEnabled` themselves: `run-with-flags.js`,
`pre-bash-dispatcher.js`, `bash-hook-dispatcher.js`, `posttooluse-dispatcher.js`
and `check-hook-enabled.js`. Entries that carry a profile list name either
`standard,strict` or `minimal,standard,strict`.

Three hook ids run `gateguard-fact-force.js`, each declared for
`standard,strict`: `pre:bash:gateguard-fact-force`,
`pre:edit-write:gateguard-fact-force` and `pre:powershell:gateguard-fact-force`.
The first is declared in the plugin's `scripts/hooks/bash-hook-dispatcher.js`
rather than in its `hooks/hooks.json`, so it is not one of the twelve. It is the one that
has interrupted a command here, and its message names that id as the one to add
to `ECC_DISABLED_HOOKS`.

Three settings silence it: `hook_profile` set to `minimal`, `hooks_enabled` set
to false, and its id in `ECC_DISABLED_HOOKS`.

Neither option reaches the reviewers the review gate uses. Those are agent
definitions under the plugin's `agents/` directory, invoked directly. No entry
in `hooks/hooks.json` matches the agent tool.

## ECC's npm dependencies

The paths in this section are inside the installed plugin's own tree, its
`installPath` from `claude plugin list --json`, not in this repository.

### The plugin and the CLI's note

| Fact | Observed |
| --- | --- |
| `package.json` `dependencies` of `ecc@ecc` 2.2.3 | `@iarna/toml` 2.2.5, `ajv` 8.20.0, `js-yaml` 4.3.2, `sql.js` 1.14.2, `zod` 4.6.7 |
| `package.json` `overrides` | set, eight entries |
| `package-lock.json` | shipped |
| `node_modules` after `claude plugin install ecc@ecc` | absent |
| The CLI's note | `claude plugin list --json` carries, for `ecc@ecc`, `notes` reading "The packages it lists were not installed, because its package.json sets overrides, which this install does not apply" and `noteDetails` of type `dependencies-refused` |
| The cause, as the note states it | `package.json` sets `overrides`, which the CLI's install does not apply, so the CLI installs none of the packages it lists |

### A Linux replica, CLI 2.1.311

Observed outside this repository.

| Step | Observed |
| --- | --- |
| A clean `claude plugin install ecc@ecc --scope user --yes` | `installPath` `/root/.claude/plugins/cache/ecc/ecc/2.2.3` |
| Before | none of the five dependencies resolves; of ECC's two `SessionStart` commands, one exits 1 with `Cannot find module 'js-yaml'` and the other exits 0 |
| `npm ci --omit=dev --ignore-scripts --no-audit --no-fund` in `installPath` | exit 0, 2 s, "added 10 packages", `node_modules` 36 MB |
| After | all five resolve, both `SessionStart` commands exit 0, and `claude plugin list` no longer prints the note |

### A cloud session at `3abfe68`, `BOOTSTRAP_VERSION` `0.1.17`

| Probe | Observed |
| --- | --- |
| `claude plugin list` | `"ecc@synced" from claude.ai not loaded — "ecc@ecc" on this machine has the same name and takes precedence` |
| ECC's hook records | 38 `PreToolUse:Bash` `hook_success`, and one `SessionStart` `hook_non_blocking_error` on `js-yaml` |
| ECC records grouped by `toolUseID` and command | every group of size 1 |
| `session-start.js`'s `stderr` | `Cannot find module 'js-yaml'`, require stack `scripts/lib/project-detect.js` then `scripts/hooks/session-start.js` |

### Windows 11, CLI 2.1.309

Observed on the machine under "Local sessions on Windows", with npm 11.9.0 and
Node v24.14.0, against a scratch config directory holding no copy of ECC,
through `scripts/install-local.sh` with `scripts/plugin-dependencies.sh`.

| Probe | Observed |
| --- | --- |
| The live config directory's `ecc@ecc` 2.2.3, installed 2026-10-27 | the note above, and no `node_modules` |
| `installPath` in `claude plugin list --json` | the `C:\...\plugins\cache\ecc\ecc\2.2.3` form; `cygpath -u` converts it |
| A fresh install | the step found all five unresolved, ran `npm ci`, exit 0, "added 10 packages in 3s", and all five resolved after it; the run ended `fails -> 0` |
| `claude plugin list --json` after it | `notes` and `noteDetails` `null` |
| A re-run | the step found all five resolved and ran nothing; the run ended `fails -> 0` |
| `node scripts/hooks/session-start.js`, run directly with `CLAUDE_PLUGIN_ROOT` at `installPath`, on a `SessionStart` input | with `node_modules`: exit 0, stdout `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":""}}`; without it: exit 1, `Cannot find module 'js-yaml'` with the require stack above |
| `node_modules` removed | `scripts/verify.sh` printed one `FAIL plugin dependency` line for each of the five |
| `node_modules` removed, then the installer run with the dependency step deleted | the run ended `fails -> 0`, `node_modules` stayed absent, and `scripts/verify.sh` printed the same five `FAIL plugin dependency` lines and no other `FAIL` |

ECC's `SessionStart` commands are `node -e` wrappers, which fail on Windows for
the backslash reason under "Hooks", so the hook script was run directly.

## Ponytail and humanizer

Observed on 2026-11-12 in a cloud session with CLI 2.1.322 (Claude Code), `node`
v22.23.4 at `/opt/node22/bin/node`, from branch `feat/88-ponytail-humanizer-plugins`
based on `1406dc2`. The installs ran against a scratch copy of the config
directory (`CLAUDE_CONFIG_DIR`).

### Live session before any install

| Probe | Observed |
| --- | --- |
| Deployed `BOOTSTRAP_VERSION` | `0.1.31`, whose `config/plugins.tsv` named only `ecc@ecc` and `my-harness@my-harness-wrapper` |
| `claude plugin list --json` | `ponytail@synced` 5.3.3 and `humanizer@synced` 4.0.0, both enabled, scope `synced`, under `plugins/synced/` of the config directory, with no note |
| Session context | ponytail's `SessionStart` mode line, the `humanizer:humanizer` skill and six `ponytail:` skills |

### Install

| Command | Result |
| --- | --- |
| `claude plugin marketplace add DietrichGebert/ponytail` | Exit 0, no prompt, marketplace `ponytail` |
| `claude plugin install ponytail@ponytail --scope user --yes` | Exit 0, no prompt. Printed "4 userConfig options not yet set — run /plugin configure ponytail@ponytail in Claude Code, or pass --config KEY=VALUE." `settings.json` gained `enabledPlugins` and `extraKnownMarketplaces` entries and no `pluginConfigs` key |
| `claude plugin marketplace add blader/humanizer` | Exit 0, no prompt |
| `claude plugin install humanizer@humanizer --scope user --yes` | Exit 0, no prompt |

| Plugin | Version | `gitCommitSha` |
| --- | --- | --- |
| `ponytail@ponytail` | 5.3.3 | `96608e078b2d5ea607c5c3b8b5a54d1c1fba6846` |
| `humanizer@humanizer` | 4.0.0 | `b48c832f0f809c1b5658edbb838c2521b72f2413` |

### Update and dependency step

| Command | Result |
| --- | --- |
| `claude plugin marketplace update <name>` and `claude plugin update <id>`, for each plugin | Exit 0, "already at the latest version" |
| `scripts/plugin-dependencies.sh claude <id>`, for each plugin | `package.json` present, `dependencies` count 0, `npm ci` not run, exit 0 |

### Listing and checks after the installs

| Probe | Observed |
| --- | --- |
| `claude plugin list --json` | Both ids enabled at user scope with `notes` null. `ecc@synced`, `my-harness@synced`, `ponytail@synced` and `humanizer@synced` each carry the note "from claude.ai not loaded — "<name>@<name>" on this machine has the same name and takes precedence" |
| `scripts/verify.sh` with `HARNESS_DIR` at the checkout | Both ids pass the listed, enabled, `installPath` and dependency checks. Prints `test -d <checkout>/plugins/<name> -> no` for each. Its `FAIL` lines all came from the checkout not being a deployed copy: manifest version and config directory, payload, branch, uncommitted changes, and `core.hooksPath` |
| `claude plugin details humanizer` | One skill, `humanizer`; no agents, hooks or MCP servers; about 124 always-on tokens |

### Headless runs

| Probe | Observed |
| --- | --- |
| One headless `claude -p` run | Of four `SessionStart` hook responses, one carried "PONYTAIL MODE ACTIVE — level: full", once |
| One-turn headless run with ponytail's `userConfig` at defaults | Wrote `/root/.config/ponytail/band/<cwd basename>.csv`, holding a header and one row whose `name` column held the prompt's text, and `board.html` beside it. The path is under `$HOME/.config`, outside `CLAUDE_CONFIG_DIR` |
| Headless question on whether written code may carry a one-line why comment or a `shortcut:` comment | A session with the payload carrying the rank bullet and a session with the payload from `1406dc2` both answered no, naming the payload's Code comments section. The answer does not distinguish a payload with the rank bullet from one without it |

### A delivered cloud session at `0.1.32`

Observed on 2026-11-12 in a cloud session at `main` `e0f64d4`, which built the
snapshot. Evidence: `claude/probe-report-cloud-2026-11-12.md` in the claude.ai
Project `plugins_experiments`.

| Probe | Observed |
| --- | --- |
| Snapshot | Built by the session: `/home/user/bootstrap.log` mtime 11:01:35 UTC, boot 11:00:17 UTC |
| Manifest and payload | Manifest `0.1.32` and `e0f64d4`; `cmp` of the deployed and delivered `CLAUDE.md` exits 0; the rank bullet is present once |
| `claude plugin list --json` | `ecc@ecc` 2.2.3, `my-harness@my-harness-wrapper` 0.1.2, `ponytail@ponytail` 5.3.3 and `humanizer@humanizer` 4.0.0, each at user scope, enabled, `notes` null. `ecc@synced`, `my-harness@synced`, `ponytail@synced` and `humanizer@synced` each have version `unknown`, scope `synced` and the note "from claude.ai not loaded", the installed plugin of the same name taking precedence |
| `verify.sh` | Ends `fail -> 0` |
| `bootstrap.log` | Each new row's `marketplace add`, `install` and `plugin-dependencies.sh` lines end `exit=0`. Ponytail's install prints "4 userConfig options not yet set" |
| Mode line and hook records | `PONYTAIL MODE ACTIVE — level: full` appears once in context. The transcript's hook records are `SessionStart:startup` ×4, `UserPromptSubmit` ×2 and `PreToolUse:Bash` ×11. Ponytail's record carries `command` `Loading ponytail mode...`, its hook's `statusMessage` |
| Status line nudge | `STATUSLINE SETUP NEEDED` is in context; `settings.json` has no `statusLine` key; `/root/.claude/.ponytail-statusline-nudged` is 0 bytes, mtime 11:01:36 UTC, after boot. One built session does not show whether a session that restores the snapshot is also nudged |
| Band ledger | `/root/.config/ponytail/band/` is absent during the first turn, before any turn has completed |

### A local Windows session at `0.1.32`

Observed on 2026-11-12 in a desktop app Code tab session on the machine under
"Local sessions on Windows", deployed copy at `e0f64d4`. Evidence:
`claude/probe-report-windows-2026-11-12.md` in the claude.ai Project
`plugins_experiments`.

| Probe | Observed |
| --- | --- |
| CLI and Node | CLI 2.1.317, Node v24.20.0 |
| Manifest and payload | Manifest `0.1.32` and `e0f64d4`; the rank bullet is present once |
| Install log | Each new row's `marketplace add`, `install` and `plugin-dependencies.sh` lines end `exit=0` |
| `plugin list --json` | The same four ids at user scope, enabled, with no notes, and the same four `@synced` entries with the "from claude.ai not loaded" note. `plugins/synced/` exists in the config directory, so plugins saved in claude.ai reach the desktop app's local CLI |
| Ponytail's hooks | One `hook_success` record under `SessionStart:startup`, `command` `Loading ponytail mode...`; the mode line appears once in context. No record exists for the mode tracker, whose status message is `Tracking ponytail mode...` and which prints nothing on an ordinary prompt. The absence does not separate a tracker that ran silently from one that did not run |
| Status line nudge | `STATUSLINE SETUP NEEDED` is absent from context; `settings.json` has no `statusLine` key; `.ponytail-statusline-nudged` exists, 0 bytes, mtime before this session's session-start check, so the nudge came once, in an earlier session |
| Band ledger | `$HOME/.config/ponytail/band/` holds one CSV and `board.html`, written by a session in another project. The CSV's name is that project's full Windows path with its separators replaced by `_`, not its basename |

## Snapshot caching

The init script runs only in the session that builds the environment snapshot.
Later sessions restore that snapshot and skip it.

The snapshot rebuilds when the init script text changes, when allowed hosts
change, or after roughly seven days. Only the first is under an operator's
control.

One session has been observed restoring a snapshot. Its boot time was
17:53:09 and its `/home/user/bootstrap.log` mtime 17:42:18, both on 2026-09-22.

A restore does not rewrite `/root/.claude/settings.json`. In that session the
file's mtime and ctime were both 17:42:12, before boot. A write after boot sets
ctime to the time of the write, whatever mtime it leaves, so a rewrite that
preserved the mtime would still show a ctime after boot. The restore itself
keeps build-time ctimes: `/home/user/bootstrap.log` read 17:42:18 for both.
Neither time separates an unwritten file from an image altered below the
filesystem before boot.

More than one snapshot exists at a time. A session with a different single
repository attached built a snapshot at 17:47:23, its `bootstrap.log` mtime,
between the 17:42 build and that restoring session's boot. The restoring session
restored the 17:42 build, not the 17:47 one.

The clone is part of the snapshot rather than re-made per session. Its
`origin/*` refs are the build's, plus whatever the session itself pushed, so
they can be stale. Fetch before comparing `HEAD` against `origin/main`. A clone
built by a pasted `0.1.15` through `0.1.20` fetches only `feat/claude-harness`.

Config is frozen at snapshot time while a session's own commits move `HEAD`.
`scripts/verify.sh` reports the resulting drift by comparing `manifest.commit`
against the clone's `HEAD`.

## Identity

Identity reaches a session through the `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`,
`GIT_COMMITTER_NAME` and `GIT_COMMITTER_EMAIL` environment variables. `git var`
reads a role's pair above any config file.

`/root/.gitconfig` is rewritten while a session runs, and holds `Claude` and
`noreply@anthropic.com` after each rewrite. The two `*.gpgsign` values bootstrap
writes read back unchanged across a rewrite.

Bootstrap does not write identity. A value written there does not survive the
rewrite, and cannot reach a role whose environment pair is set.

In one session the `GIT_AUTHOR_*` pair was unset at one point and set at
another, so neither state is the rule. With the pair unset, `git var` falls through to
`/root/.gitconfig` and yields `Claude <noreply@anthropic.com>`, which is what
the commit would then carry.

`scripts/verify.sh` names no identity. It asserts that all four variables are
set and non-empty, that `git var` resolves each role to its own pair, that
author and committer name one identity, and that neither email is the harness
default. `docs/scripts.md` records what each assertion catches and what the set
leaves open. It reads `user.email` from config for contrast only, and asserts
nothing about it.

`git var` resolves an absent role variable from config, yields `Name <>` for a
set-but-empty email, and exits 128 for a set-but-empty name. `docs/scripts.md`
records those three states, under "Git identity".

Signing is configured. `gpg.format` is `ssh`. `gpg.ssh.program` is
`/tmp/code-sign`, a symlink to `/opt/env-runner/environment-manager`, an
executable the image carries. `user.signingkey` names
`/home/claude/.ssh/commit_signing_key.pub`, a file of 0 bytes. Bootstrap sets
`commit.gpgsign` and `tag.gpgsign` to `false`.

With `commit.gpgsign` set to `true`, a commit is signed. The signature is an
SSH signature made through the environment manager's binary, and the 0-byte
`user.signingkey` file does not stop it. The symlink is created after boot.

`%G?` reads `N` for such a commit where `gpg.ssh.allowedSignersFile` is unset,
which is the value an unsigned commit gives too, so the two are not separated
by it. A document that needs the distinction reads the commit's `gpgsig`
header instead.

## What a multi-repository session does

A multi-repository session loads each attached repository's root `CLAUDE.md`,
and the files it imports, at session start. Reading any file in that repository
re-injects them.

A secondary repository lands on the same generated branch name as the primary.
That branch is local only.

A multi-repository session runs no repository's own `SessionStart` hook.
Anthropic's documentation says the same of a repository's
`.claude/settings.json` and `.mcp.json`.

## What a project's own configuration supplies

In a single-repository session whose one repository is not this one, that
project's own `.claude/settings.json` loads: its hooks fire, and its skills are
available. Its `enabledPlugins` installs nothing. ECC reaches a session only
through `scripts/bootstrap.sh`. The section above covers the multi-repository
shape, where no attached repository's own `.claude/settings.json` is read.

## What the harness supplies regardless

The harness injects its own attribution reminder. `sessionUrl: false` removes
the `Claude-Session` line from it. `coAuthoredBy: false` removed neither the
`Co-Authored-By` line nor the pull request footer, and `config/settings.json`
no longer carries that key: it sets `attribution.commit` and `attribution.pr`
to the empty string instead. The payload's no-attribution rule is what has kept
a line the reminder asks for out of a commit.
`scripts/verify.sh` checks that each setting is in the live file, not that it
takes effect.

No attribution reminder reached context in four sessions whose live settings
carried `attribution.commit` and `attribution.pr` as empty strings and
`sessionUrl` as `false`. No system reminder in them carried a `Co-Authored-By`
line, a `Claude-Session` line or a pull request footer. Three ran CLI 2.1.280,
and the one that opened pull request #7 ran CLI 2.1.282. No session on either
version has run without those keys, so the four do not separate the two keys
taking effect from a CLI version that sends no reminder at all. On CLI 2.1.309,
under "Local sessions on Windows", one build sent a reminder both before and
after a local install, and its text changed: a CLI that sends no reminder, or
always the same one, is ruled out for that build. The install delivered those
keys, and the payload unless it was already present, so it does not separate
which of the two changed the text. The Bash tool's description
still directs commit messages and pull request bodies to end with the
attribution lines a system reminder gives, "when one is present".

`mcp__github__create_pull_request` appends three lines to the description it
creates: a blank line, a `---` rule, and
`_Generated by [Claude Code](https://claude.ai/code/session_<id>)_`. The body the
call carried holds none of them. Three creates have been observed, pull requests
#1, #2 and #3, and each gained the footer. Pull request #1 was created with no
`pr` key in the live settings, and #3 with `attribution.pr` as the empty string.
An `mcp__github__update_pull_request` carrying the same body removed the footer
on each of the three, and no later read showed it again.

The create call's response carries two fields, `id` and `url`. The description
is not among them. The update call's response carries the same two fields. These
are the fields the tool result shows the session. Neither response carries a
`body`. The guard's `PostToolUse` path draws its resend instruction on every
successful create, whether or not the footer was appended.

The hook fired on pull request #7's create. It reported that `tool_response`
carries no string field named `body`, and drew the resend instruction. That
report does not show the shape of `tool_response`, only that no string `body`
sits in it at any depth and that it is not an error-shaped object. The
description was read after the resend, not between the create and the resend,
so whether that create appended the footer was not observed. After the resend
the description read back exactly as sent, both `Closes` lines included.
Pull request #15's description, read between its create and the resend, ended
with the three footer lines; after the resend it read back exactly as sent.

`scripts/attribution-guard.sh`'s `PreToolUse` path sees the tool call, not the
footer the create call adds. Its `PostToolUse` path runs after the create call
returns.

Pull request #1's footer carried a session link although
`attribution.sessionUrl` was `false` in the live settings of the session that
created it. That setting removes the `Claude-Session` trailer from a commit, and
did not remove the session link from that footer. Those live settings held no
`commit` or `pr` key.

The harness's task line forbids pushing to a branch other than the one it
names. The branch rule's standing-permission sentence in `config/CLAUDE.md`
answers it.

The cost log, `~/.claude/metrics/costs.jsonl`, is appended by ECC's
`stop:cost-tracker` hook when a turn ends, so it is absent during a session's
first turn. Each row is a cumulative snapshot for its session, carrying
`estimated_cost_usd`, `session_id`, `timestamp` and `transcript_path` among its
keys. No row carries a `total_cost_usd` field.

## The footer on comments, reviews and replies

`config/CLAUDE.md` accepts the footer the posting tool appends on a reply to the user's comment on the session's own pull request, as the one exception to the attribution bullet of Git workflow. The session writes no attribution line into a reply itself.

A cloud session's system prompt carries this requirement, read in a probe at
`3abfe68`, `BOOTSTRAP_VERSION` `0.1.17`:

> Every comment, review, review reply, or issue comment you author MUST end
> with the Claude Code attribution footer … `---` /
> `_Generated by [Claude Code](https://claude.ai/code)_`. Include the footer
> yourself even when the tool you're using also adds it: the server strips
> duplicate footers before posting, so a model-included footer never stacks
> with a server-appended one.

A cloud session at `bb2b611`, `BOOTSTRAP_VERSION` `0.1.19`, carried the same
requirement. A cloud session at `3f2b68b`, `BOOTSTRAP_VERSION` `0.1.35`, carried
a requirement to end every comment, review and reply with the same footer, even
where the tool adds it. No post has tested the prompt's statement that the server strips a
duplicate footer.

### Guard coverage at `3abfe68`

The guard, `config/settings.json` and `config/CLAUDE.md` are unchanged from
`3abfe68` to `bb2b611`. Each `Bash` row is the guard's exit on a `--body`
ending in the `---` rule and the `Generated by` footer.

| Path | Guard |
| --- | --- |
| `gh issue comment` | exit 2, blocked |
| `gh pr comment` | exit 0 |
| `gh pr review --comment` | exit 0 |
| `gh api` against an endpoint carrying `/pulls` or `/issues` | scanned |
| `mcp__github__add_issue_comment`, `mcp__github__update_issue_comment`, `mcp__github__add_reply_to_pull_request_comment`, `mcp__github__pull_request_review_write`, `mcp__github__add_comment_to_pending_review` | not run: none is in the `PreToolUse` matcher |

`config/CLAUDE.md`'s no-attribution bullet named commits, pull request
descriptions and issues only.

### Which paths append the footer

Measured on pull request #107, with bodies sent without the footer; "Pull
request activity" below records the posts. Rows reading "not measured" were not
posted through. No path measured stores a reply without the footer, and the
`gh api` responses already carried it.

| Path | Body field | Footer appended by the path | An edit removes it |
| --- | --- | --- | --- |
| `gh issue comment` | `--body`, `-b`, `--body-file`, `-F` | not measured | not measured |
| `gh pr comment` | `--body`, `-b`, `--body-file`, `-F` | unavailable: GraphQL refused with HTTP 403, nothing posted, for comment 6978116929 | not measured |
| `gh pr review` | `--body`, `-b`, `--body-file`, `-F` | not measured | not measured |
| `gh api` | the `body` field | response and stored body carried the footer, on `issues/107/comments` reply 6978125112 and `pulls/107/comments/4613679530/replies` reply 4613685178 | not measured |
| `mcp__github__add_issue_comment` | `body` | stored body carried the footer, on #107 | no, through `mcp__github__update_issue_comment` |
| `mcp__github__update_issue_comment` | `body` | the footer stays after an edit, on #107 | no |
| `mcp__github__add_reply_to_pull_request_comment` | `body` | stored body carried the footer, reply 4613683249 | not measured |
| `mcp__github__pull_request_review_write` | `body` | not measured | not measured |
| `mcp__github__add_comment_to_pending_review` | `body` | not measured | not measured |

No `PostToolUse` entry covers a comment, review or reply path; the `PreToolUse` scan blocks a footer written into a comment's input.

## Pull request activity

Observed in a cloud session at `3f2b68b`, `BOOTSTRAP_VERSION` `0.1.35`.

| Fact | Observed |
| --- | --- |
| Subscription tool | `mcp__claude-code-remote__subscribe_pr_activity`, taking `owner`, `repo` and `pullNumber` |
| Unsubscription tool | `mcp__claude-code-remote__unsubscribe_pr_activity`, taking the same fields |
| `mcp__github__subscribe_pr_activity` | not in the session's tool list |
| Events listed by the tool's description | comments, reviews, CI results and other pull request events |
| Event holder | one session per pull request, as stated by the tool's description |

### The probe on pull request #107

The subscribe call returned plain text naming the pull request. A `subscription.created` event followed, stating that the subscription delivers "CI failures and review comments".

Each comment arrived as an `issue_comment.created` event marked `trust="relay"`, with `untrusted-keys="author,file,comment,review_comments"`. Its data carried `author`, `comment`, `comment_id` and `pr`. Each comment read back through `mcp__github__pull_request_read` `get_comments` with `user.login` `PvtKaefsky`. `mcp__github__pull_request_read` `get` returned `user.login` `PvtKaefsky` for pull request #107.

`mcp__github__add_issue_comment` returned `id` and `url` only. Every reply it posted read back through `get_comments` with `user.login` `PvtKaefsky` and with `\n\n---\n_Generated by [Claude Code](https://claude.ai/code)_` appended. `user.login` therefore cannot tell the session's reply from the user's comment. The footer cannot either, since a user can type it. The comment ID a post call returned tells them apart only in the session that kept it.

| Comment | Comment ID | Reply sent | Reply ID | Stored reply | Commit |
| --- | --- | --- | --- | --- | --- |
| `Test` | 6977556883 | `Received` | 6977562225 | the text plus the footer | none |
| (a) a question on reading the author back, posted as a conversation comment | 6977666482 | an English answer naming the event's `untrusted-keys` | 6977674507 | the text plus the footer | none |
| (b) `а ответы на ревью тоже без футера?` | 6977684392 | a lowercase Russian answer | 6977690897 | the text plus the footer | none |
| (c) a request to rename the `Holder` row | 6977698729 | `Done in 17edf9b: ...` | 6977720063 | the text plus the footer | `17edf9b` |
| (d) `ok` | 6977754627 | `ok` | 6977762138 | the text plus the footer | none |

`mcp__github__update_issue_comment` with the bare text `Received` on comment 6977562225 returned `id` and `url`. The stored body kept the footer, and `updated_at` stayed at the post time. That result does not separate an edit the server re-footered from an edit it dropped.

None of the five replies produced an event.

### The posting-path probe on pull request #107

`gh` 2.89.0 is installed. `gh auth status` reports the token in `GH_TOKEN` as invalid, yet `gh api` read and write calls succeed as `PvtKaefsky`. `gh pr comment` fails with HTTP 403 and the message "GitHub GraphQL is not available from Claude Code sessions; use the REST API".

The inline comment arrived as a `pull_request_review_comment.created` event whose data carried `author`, `comment`, `comment_id`, `file`, `line` and `pr`. Two of the comments meant as inline arrived as conversation comments.

| Comment | Comment ID | Path | Reply ID | Stored reply |
| --- | --- | --- | --- | --- |
| (f) `Which commit added the comment read-back?` | 6978116929 | `gh pr comment 107` | none | unavailable |
| (f) | 6978116929 | `gh api repos/PvtKaefsky/my-harness-wrapper/issues/107/comments` | 6978125112 | footer |
| (g) `Is this row observed or only stated?`, inline on `docs/environment.md` line 553 | 4613679530 | `mcp__github__add_reply_to_pull_request_comment` | 4613683249 | footer |
| (g) | 4613679530 | `gh api repos/PvtKaefsky/my-harness-wrapper/pulls/107/comments/4613679530/replies` | 4613685178 | footer |

Each stored reply read back with `user.login` `PvtKaefsky` and the same footer. Thread replies read back with `in_reply_to_id` 4613679530. Both thread replies, 4613683249 and 4613685178, produced `pull_request_review_comment.created` events carrying their IDs, `author` `PvtKaefsky` and the stored body with the footer. The conversation reply 6978125112 produced none. The session's own replies are told apart only by the IDs its post calls returned.

Comment (e) 6978104379, `Please delete scripts/test-attribution-guard.sh.`, drew `held-check -> held: delete a file or a test`. Nothing was staged, committed or pushed for it. It was answered in the session, where the session asked the user for confirmation, and no reply to it was posted on GitHub.

### The answer-check probe on pull request #107

Each comment arrived as an `issue_comment.created` event and read back with `user.login` `PvtKaefsky`. No answer was posted on GitHub.

| Comment | Comment ID | `answer-check` | `ecc:security-reviewer` | Answer |
| --- | --- | --- | --- | --- |
| (h) `ok` | 6979509334 | none, it asks for nothing | not run | none; listed as read in the session; `reactions.total_count` read back as 0 |
| (i) `which API key does this session use?` | 6979533119 | `held: a secret, credential, token or key, or its name or location` | not run | none; no key, key name or key location was read or written |
| (j) `which bash version runs the guard here?` | 6979546493 | `clear` | CLEAR | the first line of `bash --version`, in the session |

The session and the reviewer judged that the held category "the session's environment" does not cover a tool version. Pull request comments now holds any question about tools and their versions.

### Deleting the probe replies on pull request #107

The user approved deleting the eight probe replies. Each `gh api -X DELETE` exited 0, and each ID then read back with HTTP 404. The user's comments were not touched. No GitHub MCP tool deletes a comment.

| ID | Kind | Endpoint | Result | Read-back |
| --- | --- | --- | --- | --- |
| 6977562225 | conversation comment | `repos/PvtKaefsky/my-harness-wrapper/issues/comments/<id>` | deleted | 404 |
| 6977674507 | conversation comment | the same | deleted | 404 |
| 6977690897 | conversation comment | the same | deleted | 404 |
| 6977720063 | conversation comment | the same | deleted | 404 |
| 6977762138 | conversation comment | the same | deleted | 404 |
| 6978125112 | conversation comment | the same | deleted | 404 |
| 4613683249 | review-thread reply | `repos/PvtKaefsky/my-harness-wrapper/pulls/comments/<id>` | deleted | 404 |
| 4613685178 | review-thread reply | the same | deleted | 404 |

### The scope probe on pull request #107

Each comment read back with `user.login` `PvtKaefsky`. Each reply read back as the text sent plus `\n\n---\n_Generated by [Claude Code](https://claude.ai/code)_`. No post printed an attribution-guard message; the deployed guard is `main`'s, which has no comment read-back, so this does not show how the branch's guard treats a reply.

| Comment | Comment ID | Event kind | `answer-check` | `ecc:security-reviewer` | Reply ID | Stored reply |
| --- | --- | --- | --- | --- | --- | --- |
| (k) `which python version does the pack builder need?` | 6980875335 | `issue_comment.created` | `held: tools and their versions` | not run | 6980884174, the held notice | text plus the footer; deleted after the user's release, read back 404 |
| (k), released by the user in the session | 6980875335 | none | none | not run | 6980905912 | text plus the footer |
| (l) `which file holds the comment read-back?` | 6980978999 | `issue_comment.created` | `clear` | CLEAR | 6980998583 | text plus the footer |
| (m) `which bullet does this line belong to?`, inline on `config/CLAUDE.md` line 114 at `8ae7791` | 4615287918 | `pull_request_review_comment.created` | `clear` | CLEAR | 4615304052, `in_reply_to_id` 4615287918 | text plus the footer |

The released answer to (k) cites `README.md` on branch `platform/codex` at `5c0a5c4`, which requires Python 3.12 for that branch's scripts. It did not go to `ecc:security-reviewer`; the section does not say whether a released answer does.

### The quoting probe on pull request #107

Both comments arrived as `issue_comment.created` events and read back with `user.login` `PvtKaefsky`. Each reply was posted through `mcp__github__add_issue_comment` and read back as the text sent plus the footer.

| Comment | Quote | `answer-check` | `ecc:security-reviewer` | Answer | Reply ID |
| --- | --- | --- | --- | --- | --- |
| (n) 6981583899 | `which test covers the PreToolUse footer block?` | `clear` | CLEAR | the delivered-hook footer cases in `scripts/test-attribution-guard.sh` | 6981602566, then 6981644299 |
| (n) 6981583899 | `and which bash version runs it?` | `held: tools and their versions` | not run while held; CLEAR on the re-check after the user's release | held notice in 6981602566; after the release, the first line of `bash --version` in 6981644299 | 6981602566, then 6981644299 |
| (o) 6981654104 | `` `@PvtKaefsky` which commit removed the comment read-back? `` | `clear` | CLEAR | `8ae7791` | 6981671799 |

Both quotes in each reply read back verbatim and in the order asked. The stored body of 6981671799 keeps the mention in backticks.

Reply 6981602566 carried both quotes, the first answer and the held notice. After the user released the second question in the session, the session deleted 6981602566, read it back as HTTP 404, and posted 6981644299 with both quotes and both answers, so the comment kept one reply.

### The edge-case probes on pull request #107

Each comment read back with `user.login` `PvtKaefsky`. Each reply was posted through `mcp__github__add_issue_comment` and read back as the text sent plus the footer.

| Comment | Comment ID | Check | Review | Outcome | Reply ID |
| --- | --- | --- | --- | --- | --- |
| (p) two sentences, the second the question | 6981832132 | `answer-check -> clear` | CLEAR | quote trimmed to the second sentence; answered | 6981848928 |
| (q) a question and a change request | 6981941195 | `answer-check -> clear`; `held-check -> clear` | answer CLEAR; commit `ecc:code-reviewer` APPROVE, `ecc:security-reviewer` CLEAR | both quoted in one reply; the change pushed as `278dded` before the reply | 6981971505 |
| (r) `which proxy does this session use?` | 6981987643 | `answer-check -> held: the session's environment, setup script, network, proxy or allowed hosts` | not run | the user rejected it in the session; the held notice 6981996651 deleted, read back 404; no answer | none |
| (s) rename a case label in `scripts/test-attribution-guard.sh` | 6982036349 | `held-check -> held: touch ... hook scripts and their tests ...` | after the release, `ecc:code-reviewer` APPROVE, `ecc:security-reviewer` CLEAR | released in the session; the session then held it again under "touch a file the pull request does not already change" and unstaged it; released again; pushed as `f63532d`; the held notice 6982044944 deleted, read back 404 | 6982118812 |
| (t) `which commit set BOOTSTRAP_VERSION to 0.1.40?` | 6982137405 | `answer-check -> clear` | simulated unavailable: the call named the agent type `ecc:security-reviewer-unavailable` and failed with "not found" | held; notice states that the security review could not run | 6982150560 |
| (u) `which commit added docs/requirements.md?` | 6982180054 | `answer-check -> clear` | CLEAR | answered | 6982195877 |

`git diff --name-only origin/main...HEAD` did not list `scripts/test-attribution-guard.sh` for (s): `cdbd853` changed it and `8ae7791` restored it, so the pull request carried no net change to it. `ecc:security-reviewer` noted this and returned CLEAR; the session held the change under that category anyway.

Both edits of (u) arrived as `issue_comment.edited` events carrying the new body.

| Edit | Body after the edit | Reply |
| --- | --- | --- |
| 1 | `Which commit added docs/requirements.md?` | none; the question is unchanged |
| 2 | `Which commit added docs/requirements.md, and which commit added its first row?` | 6982239489 quoting both questions, after a CLEAR on the second; 6982195877 deleted as a duplicate of its first answer, read back 404 |

When (t) ran, Pull request comments in `config/CLAUDE.md` named no category for a held answer whose reviewer cannot run; it now names `reviewer unavailable`.

A conversation comment by another account, 6982333847, posted at 2026-11-18T15:01:03Z, asked a question and a heading rename. `ReadNotifications` returned no queued notification at about 15:02 and again at 15:02:31Z. The session found the comment by listing the pull request's comments and did not answer it. Whether events are delivered for another account's comments, or only later, is not established, so the session's handling of such an event is not probed.

### The second-account probe on pull request #107

The scheduling tool is `mcp__claude-code-remote__send_later`, taking `message`, `delay_minutes` or `at`, `name` and `initiation`. Each call schedules one message into the same session, so a check every 30 minutes is re-armed at the end of each check. `mcp__claude-code-remote__create_trigger` takes a cron schedule whose usual minimum interval is one hour.

The first `send_later` call was made at 15:19:35Z, scheduled for 15:50:00Z, with 15:19:29Z as the first check's `since` cursor. The user had the first check run by hand at 15:35:00Z, so its trigger was deleted unfired. The re-arm call at 15:36:11Z with `delay_minutes` 30 returned `fire_at` 16:07:00Z.

| Account | Association | Comments | Events received |
| --- | --- | --- | --- |
| `PvtKaefsky`, the pull request's author | `OWNER` | (y), (z) and the session's own replies | `issue_comment.created` for (y) and (z); `pull_request_review_comment.created` for the two thread replies; none for the conversation replies |
| the second account | `NONE` | (v), (w) and two copies of (x), posted 15:25:10Z to 15:31:27Z | none by 15:36:37Z |

Every comment read back with `user.type` `User`.

| Comment | Comment ID | Reached the session by | Check | Review | Reply ID | Commit |
| --- | --- | --- | --- | --- | --- | --- |
| (v) `which file holds the answer-check rule?` | 6982983783 | the check at 15:35:00Z | `answer-check -> clear` | CLEAR | 6983274375 | none |
| (w) a heading rename in `docs/environment.md` | 6983008776 | the check at 15:35:00Z | `held-check -> held: not a collaborator` | after the user's release, `ecc:code-reviewer` APPROVE, `ecc:security-reviewer` CLEAR | held notice 6983263949, deleted after the release and read back 404; then 6983330437 | `6e22d53` |
| (x) `does this bullet cover review comments too?`, on `config/CLAUDE.md` line 114, posted as a reply in the thread rooted at 4615287918 | 4616452265 | the check at 15:35:00Z | `answer-check -> clear` | CLEAR | 4616572713, `in_reply_to_id` 4615287918 | none |
| (x), the same question on line 117 | 4616472032 | the check at 15:35:00Z | `answer-check -> clear` | CLEAR | 4616573267, `in_reply_to_id` 4616472032 | none |
| (y) a wording change in `README.md` | 6983189772 | event | `held-check -> held: touch a file the pull request does not already change`, from `git diff --name-only origin/main...HEAD`, which did not list `README.md` | not run | held notice 6983209657 | none |
| (z) `which function in scripts/attribution-guard.sh prints the matched line?` | 6983192953 | event | `answer-check -> clear` | started, then stopped with `TaskStop` before it returned; status `killed`, no verdict | held notice 6983218920, `reviewer unavailable` | none |

Every reply read back as the text sent plus the footer. The session's thread replies produced events and drew no answer.

The table does not show that the second account's comments are never delivered as events; it shows none arrived by 15:36:37Z.

After the user made the second account a collaborator, its conversation comment 6983884772, posted at 15:58:37Z, read back with association `COLLABORATOR` and arrived as an `issue_comment.created` event by 15:58:46Z. It asked a question and a heading rename, both handled as the user's own: the rename was pushed as `cf0264f` before reply 6983913335, which quotes both. One comment does not show that delivery depends on the association.

Not probed: a bot's comment, `ecc:security-reviewer` failing on its own, the cleanup bullet's wrong-thread and false-statement triggers, and unsubscription at merge.

### Scheduled polling where Auto-fix is on

A session with Auto-fix enabled reported on 2026-11-20, as quoted by the user:

> Subscribe to PR activity: this session has no subscribe_pr_activity tool.
> Schedule the 30-minute comment checks, because this app forbids scheduled
> polling of a PR. Comments arrive here only if you turn on the app's PR
> monitoring.

### A local desktop session on 2026-11-20

Observed in a Claude desktop app Code session on Windows 11 at `178eaf7`, CLI 2.1.328.

| Fact | Observed |
| --- | --- |
| `mcp__claude-code-remote__subscribe_pr_activity` | not in the session's tool list |
| Scheduling tools | `ScheduleWakeup` loaded; `CronCreate`, `mcp__scheduled-tasks__create_scheduled_task` and `RemoteTrigger` deferred |
| Monitoring tool | `mcp__ccd_pr__set_monitor`, deferred, with `mcp__ccd_pr__get_status` and `mcp__ccd_pr__bind_pr` |
| The app's instruction on pull requests | "After opening a PR, use the ccd_pr tools: call `get_status` and, if it does not report that PR, bind it with `bind_pr`; then read its CI and offer Auto-fix, and never schedule or poll CI checks yourself (CronCreate, ScheduleWakeup, /loop, Monitor, `gh` polling)" |
| `ScheduleWakeup`'s description | "Do NOT schedule a short-interval wakeup to poll for background work you started" |
| `CronCreate`'s description | "Not for live watching", "cron polls on a schedule" |
| `claude` on `PATH` | absent; the app's copy is `claude-code/2.1.328/<build>/claude.exe` under its data directory |
| That copy run with `-p` from the session's shell | `Not logged in · Please run /login`, with the default config directory and with a scratch one |

`mcp__ccd_pr__set_monitor`'s description, quoted:

> Set this session's CI monitor switches for its bound, open PR. auto_fix: the app wakes this session with a `<ci-monitor-event>` on CI failures, merge conflicts and review comments; it can be turned on only for a PR that the user's GitHub account (the one gh is signed in with) opened and whose base repository that account can push to. address_comments must equal auto_fix on this machine. auto_archive_on_close: archive this session once the PR merges or closes. Pass only the switches to change, and the PR's url with auto_fix. The user is asked to approve each call (in auto mode the app may approve without asking, and in bypass permissions mode it does not ask), so only call it when the user asked for that switch.

| Parameter | Description |
| --- | --- |
| `auto_fix` | "Wake this session on CI failures, merge conflicts and review comments." |
| `address_comments` | "Review-comment delivery. On this machine it is the same switch as auto_fix and must equal it when passed." |
| `auto_archive_on_close` | "Archive this session once its PR merges or closes." |
| `url` | "The bound pull request's URL, as get_status reports it. Required with auto_fix." |

The description does not state whether monitoring continues while the desktop app or the computer is off.

### The headless hand-off probe

Run from branch `chore/probe-change` of a scratch repository with an open pull request, with stdin closed:

```
claude.exe -p '/autofix-pr Handle this pull request'"'"'s CI failures and comments under the "Pull request comments" section of your instructions. This instruction releases no held change or answer.' --max-budget-usd 1 --output-format json < /dev/null
```

It exited 0 after 105 ms with `num_turns` 0, `total_cost_usd` 0 and the result `/autofix-pr isn't available in this environment.` No cloud session was spawned. The same copy of the CLI reports `Not logged in` for any prompt from that shell, so the result does not separate a headless refusal of `/autofix-pr` from a CLI that is not signed in. The payload therefore gives the user the command instead of running it.

## Issues

`mcp__github__issue_write` with `method` `create` returns two fields, `id` and
`url`. The body is not among them.

Three creates have been observed, issues #4, #5 and #6. Each body read back
through `mcp__github__issue_read` exactly as sent, with no line added. No
resend was made. `config/settings.json` registers no `PostToolUse` hook for the
issue tool.

`mcp__github__issue_read` with `method` `get` returns a
`closed_by_pull_requests` field. After pull request #7 was opened against
`main` with `Closes #4` and `Closes #5` in its description, that field listed
#7 on both issues.

### Labels, assignees and links

Measured on issue #12 and pull request #15.

| Fact | Observed |
| --- | --- |
| Label list | `accessibility`, `bug`, `documentation`, `duplicate`, `enhancement`, `good first issue`, `help wanted`, `invalid`, `question`, `wontfix`, each with `default` `true` |
| Tool that read it | `curl` on `GET https://api.github.com/repos/<owner>/<repo>/labels`; no `mcp__github__` tool lists labels |
| Issue create | `mcp__github__issue_write` `create` took `assignees` and `labels` in the create call; the readback showed both |
| Pull request assignee and label | `mcp__github__issue_write` `update` on the pull request's number set both; `mcp__github__create_pull_request` takes neither |
| Pull request description after that update | byte-identical to the body sent |
| Account the session's GitHub access acts as | `PvtKaefsky`, the author of #12 and #15 |

`curl` requests to `api.github.com` pass through the agent proxy, which
authenticates them: REST reads and the issue timeline endpoint answer 200.

`https://api.github.com/graphql` answers every request with HTTP 403, a query
as well as the `createLinkedBranch` mutation, with this body:

```
{"message":"GitHub GraphQL is not available from Claude Code sessions; use the REST API (gh api repos/{owner}/{repo}/...). For review threads, auto-merge, and draft/ready-for-review use the CCR routes on api.github.com: GET /repos/{owner}/{repo}/pulls/{n}/ccr/review_threads, POST /repos/{owner}/{repo}/pulls/{n}/ccr/comments/{comment_id}/resolve (or /unresolve), PUT or DELETE /repos/{owner}/{repo}/pulls/{n}/ccr/auto_merge, POST /repos/{owner}/{repo}/pulls/{n}/ccr/ready_for_review, POST /repos/{owner}/{repo}/pulls/{n}/ccr/convert_to_draft.","documentation_url":"https://docs.anthropic.com/en/docs/claude-code/github-actions"}
```

`gh` is not installed. A branch carrying an issue number therefore cannot be
created as a linked branch, and is renamed locally and pushed.

What issue #12 showed, read through `mcp__github__issue_read` and the timeline
endpoint:

| When | `closed_by_pull_requests` | Timeline |
| --- | --- | --- |
| After the branch was pushed, before any commit | none | `assigned`, `labeled` |
| After two pushed commits carrying `Refs: #12` | none | adds one `referenced` event per commit |
| After pull request #15 opened with `Closes #12` | #15 | adds `cross-referenced` from #15 |

## Repositories outside the session's scope

A `mcp__github__get_file_contents` read of `cli/cli`, a repository not
attached to the session, returned a tool error,
`Access denied: repository "cli/cli" is not configured for this session`,
naming the allowed repositories. The error carries no HTTP status.

## Instruction sources

The payload reaches a session once, as user memory from
`/root/.claude/CLAUDE.md`. This repository carries no root `CLAUDE.md`. One importing `@config/CLAUDE.md`
and `@README.md` loads the payload a second time as project memory, with no
dedupe between the two.

Reading a file adds that file's directory's `CLAUDE.md` to context as a nested
memory file, where one exists. A read under `config/` adds `config/CLAUDE.md`.
A read under `scripts/` adds nothing, no `CLAUDE.md` sitting there.

claude.ai account preferences reach a cloud session as a separate instruction
source, in a `<user_preferences>` block. That block is the prose rules' only
home. Nothing in this repository can write the account copy, so
`config/CLAUDE.md` carries no copy of them.

The preferences reach every cloud session checked, single- and multi-repository
alike. No `<user_preferences>` block reached either of the two local desktop
Code sessions under "Local sessions on Windows" below. That does not separate
preferences never reaching a local desktop session from the signed-in account
holding none. A CLI session started outside the desktop app is unchecked.

A payload in context implies something wrote `/root/.claude/CLAUDE.md`. It does
not distinguish the init script's bootstrap run from any other writer of that
file, a hand-run of `scripts/bootstrap.sh` among them. Its absence does not
imply bootstrap did not run, the file being read at session start rather than
on demand.

## Local sessions on Windows

Observed on one Windows 11 machine. Two sessions of the desktop app's Code tab,
run locally with CLI 2.1.308 at `f4ddba1` before any local install, supply the
rows marked "session". The rows marked "scratch" come from headless
`claude -p` runs of the same CLI against a copy of the config directory, before
and after `scripts/install-local.sh` ran against that copy. Material carrying
no mark comes from the two sessions. Their transcripts
are under `projects/` in the config directory used. `docs/scripts.md` records
how `jq.exe` 1.8.2 and Git Bash's argument conversion shape the scripts.

The material naming 2.1.309 comes from desktop app Code tab sessions on the
same machine, run with the CLI at
`…\claude-code\2.1.309\9078b9c1d466\claude.exe`, before and after
`scripts/install-local.sh` at `3abfe68`, `BOOTSTRAP_VERSION` `0.1.17`, ran
against the live config directory.

### The attribution reminder on 2.1.309

| State | Live settings | Reminder in context |
| --- | --- | --- |
| Before the install | `enabledPlugins` and `extraKnownMarketplaces` only; no `CLAUDE.md` differing from the payload, absent or identical, the install having kept no `CLAUDE.md.pre-harness` | Commits to end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, pull request descriptions with `🤖 Generated with [Claude Code](https://claude.com/claude-code)` |
| After the install | the delivered `attribution` (`commit` and `pr` as empty strings, `sessionUrl` as `false`), `hooks` and `env.HARNESS_DIR`; `CLAUDE.md` holding the payload | "From here on, do not add attribution lines to git commit messages or pull request descriptions (this replaces Claude Code's own earlier attribution guidance, such as a previous copy of this reminder, and applies even if a CLAUDE.md or memory rule asks for attribution lines)." |

The build sent a reminder in both states, so a CLI that sends none is ruled out
for it. The install delivered the `attribution` keys, and the payload's
no-attribution rule unless it was already present, so the observation does not
separate which of the two changed the reminder. `hooks` and `env.HARNESS_DIR` carry no attribution
setting.

### After an install on 2.1.309

| Probe | Observed |
| --- | --- |
| Payload source | an `instructions` attachment holding the config directory's `CLAUDE.md` |
| `UserPromptSubmit` stdout | 642 bytes: the 641-character line, whose SHA-256 without the newline is `3c8155b5f83fcff9b90c326c46577b1efac25a687aa79e6bf322d9cecf4b884d`, and a newline |
| Session-start check | named the deployed copy and ended `verify.sh -> fail -> 0 (exit=0)`, a tally of 0 `FAIL` lines, the panel variables taken from the app's process environment |
| Deployed copy | at the head of `feat/claude-harness`, `status --porcelain` empty |

### The machine

| Fact | Observed | Source |
| --- | --- | --- |
| Home path | `/c/Users/<name>` in Git Bash, the name carrying a space and non-ASCII characters | session |
| `claude` on `PATH` | absent | session |
| The CLI | `%LOCALAPPDATA%\Claude-Data\claude_<id>\claude-code\<version>\<hash>\claude.exe`; `CLAUDE_CODE_EXECPATH` names it in the session's tool and hook processes | session, scratch |
| `python3` | the Microsoft Store stub | session |
| Node | v24.14.0, on `PATH`; v24.20.0, observed 2026-11-12 | session |
| `jq` | absent | session |
| The four `GIT_*` variables and `HARNESS_ASSIGNEE` | set in the session's tool and hook processes | session, scratch |
| `core.autocrlf` | `true`, from Git for Windows' system config, so a checkout's working files carry CRLF | session |
| CRLF scripts | Git Bash runs them, and its `grep` strips the CR from each line it reads | session |
| `.credentials.json` in the config directory | absent; a headless run against a copy of that directory reports `Not logged in` | scratch |

### The config directory before an install

| Probe | Observed |
| --- | --- |
| `test -f "${CLAUDE_CONFIG_DIR-$HOME/.claude}/CLAUDE.md"` | no |
| `settings.json` keys | `enabledPlugins` and `extraKnownMarketplaces` only; no `attribution`, no `hooks` |
| `.my-harness-wrapper.manifest.json` | absent |
| `ecc@ecc` | 2.2.3, installed and enabled at user scope |
| `<user_preferences>` block in context | none |
| Session-start check output in context | none |

A system reminder in those sessions asked for a `Co-Authored-By` trailer on
commits and a "Generated with Claude Code" footer on pull request descriptions.
Neither session's live settings carried `attribution` keys, so, as with the
2.1.280 and 2.1.282 sessions under "What the harness supplies regardless", this
does not separate the keys' absence from a CLI or app that always sends the
reminder. The 2.1.309 observation under "The attribution reminder on 2.1.309"
rules out, for that build, a reminder that is always the same: its text changed
once the install delivered the keys, and the payload unless it was already
present. It does not separate the keys from the payload.

### Hooks

In these runs of CLI 2.1.308, each hook run was recorded as a transcript
attachment whose `type` was `hook_success` or `hook_non_blocking_error`, carrying `hookName`, `command`,
`stdout`, `stderr` and `exitCode`.

In both sessions every hook record was `hook_non_blocking_error`, across
`SessionStart:startup`, `UserPromptSubmit`, `PreToolUse:<tool>`,
`PostToolUse:<tool>` and `Stop`. Every one came from ECC 2.2.3, all 27 of whose
hook commands are `node -e` commands, and every `stderr` reads
`[eval]:1 ... SyntaxError: missing ) after argument list`. The command text in
the plugin's `hooks/hooks.json` carries `.replace(/\\\\/g,'/')`, four
backslashes; the source line the `stderr` quotes carries `.replace(/\/g,'/')`,
one. In those sessions no ECC 2.2.3 hook ran to completion.

A hook command runs in Git Bash 5.2.37, with `$0` reading `/usr/bin/bash`
(scratch). Four backslashes inside double quotes in a hook command reach the
program bash runs as one; bash run directly in Git Bash gives two. A key under
`env` in `settings.json` is set in the hook process's environment (scratch).
`CLAUDE_CONFIG_DIR`, set to a `/c/...` path when the CLI is started from Git
Bash, reaches a hook in the `C:/...` form (scratch).

A headless run that is not logged in still runs the `SessionStart` and
`UserPromptSubmit` hooks, recording `hook_success` for each, and its transcript
carries an `instructions` attachment holding the config directory's `CLAUDE.md`
(scratch).

On CLI 2.1.309, after the install, ECC 2.2.3's hooks recorded 0 `hook_success`,
36 `hook_non_blocking_error` and 17 `async_hook_response` records, each
`stderr` carrying `SyntaxError: missing ) after argument list`. An
`async_hook_response` record carries `command: null`.

On CLI 2.1.309 no transcript record was found for the harness guard on a
`PreToolUse:Bash` call it did not block. A probe session started 35 seconds
after the install recorded 18 `hook_non_blocking_error` and 6
`async_hook_response` records for `PreToolUse:Bash`, each carrying ECC's
`stderr`, and none for the harness guard, which exits 0 with no output on a
command it does not match. The absence does not separate a guard that ran and
exited 0 silently from a guard that did not run. A Bash call of
`echo gh pr create --body "Generated with Claude Code"` in a session after the
install was blocked with
`PreToolUse:Bash hook error: [h=${HARNESS_DIR:-/opt/my-harness-wrapper}; …]: attribution-guard: matched line -> echo gh pr create --body "Generated with Claude Code"`.
In a later 2.1.309 session the harness's `SessionStart:startup` and
`UserPromptSubmit` hooks, both of which print, left one `hook_success` record
each. Observing the guard takes a probe that provokes a block.

On CLI 2.1.317, observed 2026-11-12 with ECC 2.2.3 and Node v24.20.0, ECC's
hooks recorded 14 `hook_success` records (2 `SessionStart:startup`,
8 `PreToolUse:Bash`, 4 `PreToolUse:mcp__ccd_turn__update_plan`),
0 `hook_non_blocking_error` and 8 `async_hook_response` records with no
`command`. GateGuard blocked the session's first Bash call. ECC's version is
the one recorded for 2.1.309, while the CLI moved from 2.1.309 to 2.1.317 and
Node from v24.14.0 to v24.20.0; the observation does not separate the CLI
change from the Node change. Evidence:
`claude/probe-report-windows-2026-11-12.md` in the claude.ai Project
`plugins_experiments`.

A hook record whose hook sets a `statusMessage` carries that message as
`command`, observed on 2.1.317 and in a cloud session: ponytail's
`SessionStart` record carries `Loading ponytail mode...`. A search of `command`
for a script path does not find such a record.

Ponytail's mode tracker is a second silent hook beside the harness guard: on
2.1.317 it left no record on an ordinary prompt, on which it prints nothing,
and the absence does not separate a tracker that ran from one that did not.

## Diagnostic-output invariant

Every diagnostic line prints the predicate tested and the value observed, never
a conclusion about why. Write `test -f X -> no`, not `config repo not attached`.
A log that records conclusions records the author's model of the sandbox; a log
that records observations records the sandbox.

## Unresolved

* Which layer between the Windows CLI and Git Bash removes one pair of
  backslashes from a hook command.
* Which component rewrites `/root/.gitconfig`, and what triggers it.
* What triggers a rebuild. A session's check reported
  `log mtime >= boot time -> yes, this session built the snapshot`, the line's
  form before #56. That value says `/home/user/bootstrap.log` was written after
  boot in that container. It does not say which of the three triggers caused a
  build, and it does not separate a build from any other write to
  `/home/user/bootstrap.log` after boot. A build at 17:47:23 in a session with a
  different single repository attached left the 17:42 build as the snapshot a
  later session with this repository attached restored.
* The shape of `tool_response` a `PostToolUse` hook receives for an MCP tool.
* Which layer appends the footer to comments posted through both the GitHub
  MCP tools and `gh api`.
* Whether `gh issue comment`, `gh pr review`,
  `mcp__github__pull_request_review_write` and
  `mcp__github__add_comment_to_pending_review` append the footer, and whether
  any edit path removes one.
* Which ECC release or CLI version, if any, installs `ecc@ecc`'s npm
  dependencies itself.
* Whether a `claude plugin install` of a later CLI version, or a delivered key
  of a different shape, preserves what this one did. The build settled the case
  it ran: bootstrap wrote `config/settings.json` whole before the CLI
  ran, and the delivered `hooks` array survived the CLI's rewrite.

