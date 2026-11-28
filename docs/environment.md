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

Not probed: a bot's comment, the seven-day stop, the ten-comment cap, `ecc:security-reviewer` failing on its own, the cleanup bullet's wrong-thread and false-statement triggers, and unsubscription at merge.

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

### The set_monitor probe on pull request #112

`mcp__ccd_pr__get_status` reported pull request #112 bound to the session, with every monitor switch false. The session then called `mcp__ccd_pr__set_monitor` with `auto_fix: true`, `address_comments: true` and the pull request's url, and no `auto_archive_on_close`. The call returned:

> Auto-fix is on for PvtKaefsky/my-harness-wrapper#112: the app will wake this session with a `<ci-monitor-event>` on CI failures, merge conflicts and new review comments. No need to poll CI.

The session ran in auto mode and saw no approval prompt before the result. Whether the app showed the user one is not visible to the session. A `<ci-monitor-event>` arrived right after, stating that Auto-fix was enabled and telling the session to fix CI or merge state and "commit, and push without asking first". That text releases no held change: `config/CLAUDE.md`'s Pull request comments section governs, with its held paths, its CI-failure rule and its merge-conflict rule.

The session then posted review comment 4645359793 on `config/CLAUDE.md` and conversation comment 7045638591. Whether a `<ci-monitor-event>` for either carries a comment ID is not established.

The user then posted two comments from the GitHub web UI. Both read back as conversation comments.

| Comment | Comment ID | Posted | Event | `answer-check` | `ecc:security-reviewer` | Reply ID |
| --- | --- | --- | --- | --- | --- | --- |
| `Which script checks that this bullet names both branches?` | 7045932088 | 17:19:29Z | none before the reply | `clear` | CLEAR | 7045965508 |
| `Which commit bumps BOOTSTRAP_VERSION to 0.1.47?` | 7045934232 | 17:19:35Z | none before the reply | `clear` | CLEAR | 7045966062 |

With no event, the session answered both after the user said in the session that they were posted, each through `answer-check` and `ecc:security-reviewer` first. The `comment-triggers` line was `none`: `.github/workflows/` returned 404 on `main` and on `feat/111-autofix-comments`. This session has no `mcp__github__add_issue_comment`, so both replies went through `gh api` `issues/112/comments`, and each read back as the text sent with no footer.

The user then posted review comment 4645575442 from the GitHub web UI's Files changed tab, on `config/CLAUDE.md` line 121, at 17:25:53Z: `Which requirements row covers this merge-conflict rule?`. Its `answer-check` was `clear` and `ecc:security-reviewer` returned CLEAR. The reply went through `gh api` `pulls/112/comments/4645575442/replies` as review comment 4645588349, with `in_reply_to_id` 4645575442, and read back as the text sent with no footer.

No `<ci-monitor-event>` arrived for any comment on #112 as of 17:27:13Z, when the session read back reply 4645588349. That covers the session's probes 4645359793 and 7045638591, the user's 7045932088, 7045934232 and 4645575442, and the session's three replies. Two of those comments, the session's 4645359793 and the user's 4645575442, are review comments that start a thread. Whether such an event names a comment by its ID is not established.

### The Auto-fix delivery probe on pull request #112

Observed on 2026-11-21 in a local Claude desktop app Code session on Windows 11, with `CLAUDE_CODE_REMOTE` unset. Pull request #112, closed unmerged at `0c0f518`, was reopened and bound to the session, and `mcp__ccd_pr__set_monitor` was called with `auto_fix: true`, `address_comments: true` and the pull request's url. The app then sent a `<ci-monitor-event>` stating that Auto-fix was enabled, with no pull request number and no comment ID. The session was idle between comments, and the user typed nothing in it while waiting for an event.

The pull request's author is `PvtKaefsky`, the account `gh` is signed in with. The second account is `KrylovViktor`. Each row's author, association, kind and posted time come from the forge, read by `gh api`: the first three rows at 00:37:49Z, the rest at 00:41:45Z or 00:43:28Z.

| Comment | Comment ID | Author, association | Kind | Posted | Event | Comment ID in the event |
| --- | --- | --- | --- | --- | --- | --- |
| `[test-a]` | 7054284121 | `KrylovViktor`, `NONE` | conversation | 00:37:13Z | yes, by 00:39:27Z | no |
| `[test-b]` | 7054286374 | `KrylovViktor`, `NONE` | conversation | 00:37:20Z | yes, in the same event | no |
| `[test-c]` | 7054290632 | `PvtKaefsky`, `OWNER` | conversation | 00:37:35Z | none as of 00:50:15Z | |
| `[test-a]` | 4649359443 | `KrylovViktor`, `COLLABORATOR` | review, `config/CLAUDE.md` line 117 | 00:40:00Z | yes, by 00:41:45Z | yes |
| `[test-b]` | 7054343892 | `KrylovViktor`, `COLLABORATOR` | conversation | 00:40:27Z | yes, in the same event | no |
| `[test-c]` | 7054362345 | `PvtKaefsky`, `OWNER` | conversation | 00:41:27Z | none as of 00:50:15Z | |
| `[test-a2]` | 4649377682 | `KrylovViktor`, `COLLABORATOR` | review, `config/CLAUDE.md` line 117 | 00:42:48Z | yes, by 00:43:28Z | yes |
| `[test-c2]` | 4649379498 | `PvtKaefsky`, `OWNER` | review, `config/CLAUDE.md` line 117 | 00:43:06Z | none as of 00:50:15Z | |

Comments 7054284121, 7054286374 and 7054290632 were absent from the forge by 00:41:45Z. The session did not delete them.

| Field | A comment event's content |
| --- | --- |
| Heading | "PR #112 has N new review comments", for conversation comments as well |
| Entry line, conversation comment | `Comment N — PR comment, no inline thread`, with no ID |
| Entry line, review comment | `Comment N — comment_id=<id>, inline thread`, with the `gh api` replies endpoint |
| Quoted lines | the author's login, the path and line for a review comment, and the body |
| Instructions | the event tells the session to push a fix, reply on each inline thread through `gh api` with a closing line crediting Claude Code, and resolve the thread |

Every comment by `KrylovViktor` raised an event, as a collaborator and as a non-collaborator, in conversation and in review threads. No comment by `PvtKaefsky` raised one, which matches the earlier record on #112. `PvtKaefsky` is at once the pull request's author, the repository's owner and the account `gh` is signed in with, so this probe does not distinguish which of those excludes a comment. A conversation comment's event carries no ID, so the session finds it by listing the pull request's comments.

#### The live reply probe

Observed on 2026-11-21 in a second local Claude desktop app Code session on Windows 11, with `CLAUDE_CODE_REMOTE` unset, on #112 at head `4e81840`. `mcp__ccd_pr__get_status` reported the pull request already bound, with `auto_fix: false`. `mcp__ccd_pr__set_monitor` with `auto_fix: true`, `address_comments: true` and the url returned that Auto-fix was on. The Auto-fix-enabled `<ci-monitor-event>` followed; it told the session to commit and push without asking first, and the session did not.

| Step | Result |
| --- | --- |
| Before-binding listing | 8 conversation and 8 review comments listed once as read, none answered, the earlier session's replies 4649460432, 7054616892 and 4649460792 among them |
| Record | created at `<repo>/.git/pr-comments-PvtKaefsky-my-harness-wrapper-112.record`, under the directory `git rev-parse --git-common-dir` gives, with one `handled` line per comment, `reply` lines for the posted replies and `last_read` lines |
| `comment-triggers` | `none`: `.github/workflows` returns 404 on `main` (`1a201ae`) and at `4e81840` |
| Review comment `[test-d]` 4649873034 by `KrylovViktor`, `COLLABORATOR`, `config/CLAUDE.md` line 133, posted 02:05:09Z | found by the listing made when the user said in the session that the comments were posted; no `<ci-monitor-event>` and no queued notification as of 02:07:39Z; a `<ci-monitor-event>` carrying `comment_id=4649873034` arrived by 02:09:34Z, after the reply was posted |
| The late event | the record held 4649873034 as handled with an unchanged `updated_at`, so the session posted no second reply; the event told the session to push a fix, end a reply with `_🤖 Addressed by [Claude Code](https://claude.com/claude-code)_` and resolve the thread, and the session did none of them; the thread read `isResolved: false` and the head `4e81840` afterwards |
| Conversation comment `[test-e]` 7055623102 by `PvtKaefsky`, `OWNER`, posted 02:05:22Z | no event; found by the same listing |
| `answer-check` and review | `clear` for both; `ecc:security-reviewer` returned `VERDICT: clear` for each before posting |
| Attribution guard | `scripts/attribution-guard.sh` on the planned command with the real body exits 0; with a copy carrying `Co-Authored-By: Claude <noreply@anthropic.com>` it exits 2 and prints `attribution-guard: matched line -> Co-Authored-By: Claude <noreply@anthropic.com>`; nothing was posted from the copy |
| Reply in the review thread | `gh api -X POST repos/PvtKaefsky/my-harness-wrapper/pulls/112/comments/4649873034/replies -F body=@<literal absolute path>` returned 4649878801, `in_reply_to_id` 4649873034; the stored body equals the file byte for byte after line-ending normalisation, with no footer and no line crediting Claude Code |
| Conversation reply | `gh api -X POST repos/PvtKaefsky/my-harness-wrapper/issues/112/comments -F body=@<literal absolute path>` returned 7055638450; the stored body equals the file, with no footer |
| Thread state | `gh api graphql` `reviewThreads { isResolved }` reads `false` for the thread of 4649873034 |
| Push | local `HEAD`, `origin/feat/111-autofix-comments` and the pull request's head all read `4e81840` after the replies |
| Own reply in a later listing | 4649878801 was listed as updated since the last read and was counted as the session's own from the record |
| Deletion | `gh api -X DELETE repos/PvtKaefsky/my-harness-wrapper/issues/comments/7055638450` exited 0; reading it back returned HTTP 404 |

The deletion was made for this probe; none of the section's listed deletion reasons applied to 7055638450. The review comment's event arrived between 2.5 and 4.5 minutes after the comment, against under 2 minutes in the earlier probe. This probe does not show whether the delay came from the app or from the session being busy in a turn the user's message started.

#### The record and read-back probes

Observed on 2026-11-21 on #112 at head `01ae886`, in the same local session except where a row names the parent session, under the branch's Pull request comments section. Every post used `-F body=@<literal absolute path>` and passed the attribution guard check first: the real body exited 0, and a copy carrying `Co-Authored-By: Claude <noreply@anthropic.com>` exited 2 with `matched line ->`. A post whose response was discarded with `> /dev/null 2>&1` stood in for a timeout, since a real timeout cannot be caused on demand.

| Case | Result |
| --- | --- |
| Deleting a review reply | probe reply 4649944977 in the thread of 4649873034 was deleted with `gh api -X DELETE repos/PvtKaefsky/my-harness-wrapper/pulls/comments/4649944977`, exit 0; reading it back returned HTTP 404; the record kept the ID with a `deleted` entry after it |
| A missing record | the record was moved aside to `.git/pr-comments-PvtKaefsky-my-harness-wrapper-112.record.moved-aside-20261121`; after the user's question 7055801550 by `KrylovViktor`, the session said the record was missing, listed all 20 comments as read, answered none, and wrote a new record beginning `binding 2026-11-21T02:18:46Z record-missing` |
| The late event | a `<ci-monitor-event>` for 7055801550 arrived about 35 seconds after the comment; the record held it as read, so the session did not answer it |
| A comment the user names | when the user named 7055801550 in the session, the session answered it with 7055835441, whose stored body equals its file |
| An unreadable record | with the record overwritten by the line `not a record`, the next listing called the record unreadable, listed all 21 comments as read, answered none, and wrote a record beginning `binding 2026-11-21T02:22:19Z record-unreadable` |
| A rebuilt record | the record rebuilt at 02:18:46Z listed the session's earlier reply 4649878801 as `handled` only, and the one rebuilt at 02:22:19Z listed 4649878801 and 7055835441 as `handled` only, with no `reply` entry |
| A lost response that landed | the attempt began 02:22:55Z; the read-back found 7055859207 by `PvtKaefsky`, created 02:22:57Z, with a body equal to its file, counted it as the session's own, posted nothing again, and recorded `reply issue 7055859207 lost-response-readback` |
| A lost response beside a new comment | the attempt began 02:23:28Z; the read-back counted 7055867365 as the session's own and handled 7055881851 by `KrylovViktor` as new; after `comment-triggers -> none`, `answer-check -> clear` and `ecc:security-reviewer`, the session answered it with 7055898175 |
| A lost response beside a same-account comment | in the parent session, the attempt began 02:34:00Z; the read-back counted 7056003928 by `PvtKaefsky`, created 02:34:02Z, with a body equal to its file, as the session's own, and handled 7056010969 by `PvtKaefsky`, created 02:34:35Z in the same conversation, as new, since its body differs; after `comment-triggers -> none`, `answer-check -> clear` and `ecc:security-reviewer`, the session answered it with 7056037145, whose stored body equals its file |
| Cleanup | 4649944977, 7055835441, 7055859207, 7055867365, 7055898175, 7056003928 and 7056037145 each read back HTTP 404; 4649873034, 7055801550, 7055881851 and 7056010969 read back present |

`created_at` has one-second granularity, so a comment created in the same second the attempt began is not separated from one created just before it. A repost after a post that did not land was not shown, since all three discarded posts landed. The session's comparison stripped line endings and trailing newlines.

#### The switch-off probe on `PvtKaefsky/autofix-probe` #5

Observed on 2026-11-21 in local Claude desktop app Code sessions on Windows 11, with `CLAUDE_CODE_REMOTE` unset, under #112's Pull request comments section. A session opened scratch pull request `PvtKaefsky/autofix-probe` #5, which changes only `probe.txt`, from a clone in its scratchpad. That session's folder was a `my-harness-wrapper` worktree. The record was kept at `.git/pr-5-record.json` in the clone, not under the name the section gives.

| Step | Result |
| --- | --- |
| Switch-on, session on another repository | `mcp__ccd_pr__set_monitor` was refused twice, before and after the clone was added with `mcp__ccd_directory__request_directory`, with `PreToolUse:mcp__ccd_pr__set_monitor hook error: PvtKaefsky/autofix-probe#5 is on the session's PR bar, but its repository could not be matched to the session's folders, so Auto-fix can't be enabled for it; tell the user that they can switch it themselves on the PR bar, which works at once.`; no hook in `~/.claude/*.json` matches `set_monitor` or `ccd_pr` |
| Probe reply | held under `comment-triggered automation`: `comment-echo.yml` triggers on `issue_comment` on `main` and at the head; on the user's instruction it was not posted |
| Switch-on, session opened on the clone | the first call was refused by Claude Code's auto mode classifier before reaching the app, with the text quoted below the table; after the user allowed the call, it returned `Auto-fix is on for PvtKaefsky/autofix-probe#5: the app will wake this session with a <ci-monitor-event> on CI failures, merge conflicts and new review comments. No need to poll CI.`, and an Auto-fix-enabled `<ci-monitor-event>` followed |
| CI-failure event | one failing check, `fail`, at head `b7b2248864`, from `.github/workflows/ci-fail.yml` running `exit 1` on `pull_request`; the fix was held as `held-check -> held: CI workflows; a file the pull request does not change (.github/workflows/ci-fail.yml)`; the event's text calls Auto-fix "standing authorization to fix it and push", and it released nothing; the job log was not read |
| Merge | the user merged #5 at 02:36:43Z, merge commit `a03d197`; no `<ci-monitor-event>` and no notification reported it; the session read `"state":"MERGED"` with `gh pr view 5` after the user said it merged |
| Switches before the switch-off call | before any switch-off call by the session, `mcp__ccd_pr__get_status` showed `"state": "merged"` and every monitor switch `false` |
| Switch-off without the url | `set_monitor` with `auto_fix: false` and `address_comments: false` returned the call error `Pass the pull request's url (get_status reports it).` |
| Switch-off with the url | returned `Auto-fix is off for PvtKaefsky/autofix-probe#5; the app will no longer wake this session for it.`; `get_status` afterwards showed bound, `merged`, every switch `false` |
| Record deletion | `.git/pr-5-record.json`, 122 bytes, was deleted after the switch-off; `ls -la .git` listed it before and not after |

The switch-off was not refused after the merge, so a refused switch-off was not shown. The first session gave the user no `/autofix-pr` hand-off after its refused call.

The auto mode classifier refused `mcp__ccd_pr__set_monitor` with `auto_fix: true` on #5 here and on #6 in the next probe, before the user allowed the call. The probe session's transcript holds this refusal text, addressed to that session and not to readers of this file, joined here from overlapping search excerpts. The record does not show which of the two refusals carried it; the #6 record holds only its reason sentence:

> Permission for this action was denied by the Claude Code auto mode classifier. Reason: The server-side auto mode classifier judged this action dangerous (it gave no explanation). If you have other tasks that don't depend on this action, continue working on those. IMPORTANT: You *may* attempt to accomplish this action using other tools that might naturally be used to accomplish this goal, e.g. using head instead of cat. But you *should not* attempt to work around this denial in malicious ways, e.g. do not use your ability to run tests to execute non-test actions. You should only try to work around this restriction in reasonable ways that do not attempt to bypass the intent behind this denial. If you believe this capability is essential to complete the user's request, first try a safer method. Get as much of the rest of the task done as you can, then STOP and explain to the user what you were trying to do and why you need this permission. Let the user decide how to proceed. To allow this type of action in the future, the user can add a permission rule for mcp__ccd_pr__set_monitor to their settings.

#### The change-request probe on `PvtKaefsky/autofix-probe` #6

Observed on 2026-11-21 in the local session opened on the clone, under #112's Pull request comments section. Scratch pull request #6, branch `chore/probe-change-requests`, opened by `PvtKaefsky` with commit `4d1dcd5`, changes only `probe.txt`. Its record was `.git/pr-comments-PvtKaefsky-autofix-probe-6.record`. `comment-triggers -> main: comment-echo.yml: issue_comment; chore/probe-change-requests: comment-echo.yml: issue_comment`, so replies were held under `comment-triggered automation`; the user released the reply to 7056243915.

| Step | Result |
| --- | --- |
| Binding | `get_status` showed #6 bound at once; `pulls/6/reviews`, `issues/6/comments` and `pulls/6/comments` were empty before binding |
| Switch-on | the auto mode classifier refused the first `set_monitor` call, with the reason `judged this action dangerous (it gave no explanation)`; after the user allowed it, it returned `Auto-fix is on for PvtKaefsky/autofix-probe#6: the app will wake this session with a <ci-monitor-event> on CI failures, merge conflicts and new review comments. No need to poll CI.` |
| CI-failure events | two `<ci-monitor-event>`s for check `fail`, at heads `4d1dcd5` and `e800e1e`, each held as `held-check -> held: CI workflows; a file the pull request does not change (.github/workflows/ci-fail.yml)`; nothing staged |
| A change in the pull request's file | comment 7056243915 by `PvtKaefsky`, `OWNER`, asking for a line at the end of `probe.txt`, raised no event and was found by the listing made when the user said they had commented; `held-check -> clear`; commit `e800e1e`, with `ecc:code-reviewer` APPROVE and `ecc:security-reviewer` APPROVE, `held category: none`, was pushed before the reply; reply 7056293650, posted after the user's release, names `e800e1e`, and its stored body equals its file |
| A change outside the pull request's files | comment 7056302457 asking for a line in `README.md` drew `held-check -> held: a file the pull request does not change (README.md)`, from `git diff --name-only origin/main...HEAD` listing only `probe.txt`; `git status` read clean and `git diff --cached` empty; the later listing skipped 7056293650 as the session's own |
| A review body by the author | GitHub offered `PvtKaefsky`, the pull request's author, no "Request changes" on #6, so the user submitted a "Comment" review, 6002437644, state `COMMENTED`, with the body "Why does probe.txt now hold two lines starting with `case 5:`?" and no inline comment; no `<ci-monitor-event>` and no notification arrived; `issues/6/comments` and `pulls/6/comments` did not hold the body, and `pulls/6/reviews` did |
| A review body by a collaborator | `KrylovViktor`, `COLLABORATOR`, submitted review 6002459316, state `CHANGES_REQUESTED`, at 03:07:23Z, with the same question and no inline comment; a `<ci-monitor-event>` headed "PvtKaefsky/autofix-probe PR #6 has 1 new review comment" arrived, with the entry line `Comment 1 — review summary (changes requested), no inline thread`, the author and the body, and no comment or review ID; it told the session to push a fix, reply ending with a line crediting Claude Code, and resolve the thread, and the session did none of them; `issues/6/comments` and `pulls/6/comments` did not hold the body, `pulls/6/reviews` did, and `reviewDecision` read `CHANGES_REQUESTED` |
| Close | #6 was closed unmerged; `gh pr view 6` read `"state":"CLOSED","closedAt":"2026-11-21T03:08:23Z","mergedAt":null`; no `<ci-monitor-event>` and no notification reported the close |
| Switches before the switch-off call | before any switch-off call by the session, `get_status` showed `"state": "closed"` and `auto_fix`, `address_comments`, `auto_merge` and `auto_archive_on_close` all `false` |
| Switch-off with the url | returned `Auto-fix is off for PvtKaefsky/autofix-probe#6; the app will no longer wake this session for it.`; `get_status` afterwards was unchanged |
| Record deletion | `.git/pr-comments-PvtKaefsky-autofix-probe-6.record` was in the `.git` listing before the deletion and absent after |

Neither review body was answered, as the probe's brief directed. No conversation or inline comment by an account other than the author was posted on #6; on #112, such comments raised events.

#### The allow-rule probe on `PvtKaefsky/autofix-probe` #7

Observed on 2026-11-21 in a new local session opened on the clone, under #112's Pull request comments section at `c82262c`, with `~/.claude/settings.json` holding `{"allow":["mcp__ccd_pr__set_monitor"]}` under `permissions`. Scratch pull request #7, branch `chore/probe-set-monitor-allow`, changes one line of `probe.txt` at head `68fe6e2`.

| Step | Result |
| --- | --- |
| Switch-on | the session's first `set_monitor` call, with `auto_fix: true`, `address_comments: true` and the url, returned `Auto-fix is on for PvtKaefsky/autofix-probe#7: the app will wake this session with a <ci-monitor-event> on CI failures, merge conflicts and new review comments. No need to poll CI.`, with no auto mode classifier refusal and no approval prompt |
| CI-failure event | one `<ci-monitor-event>` reported check `fail` at head `68fe6e2`, the session's own; the fix was held as `held-check -> held: CI workflows; CI log not readable (check fail: gh run view --log-failed returned log not found: 136719969187)`; the line, quoted here without its inner backticks, should also have named `a file the pull request does not change`, since the fix would edit `.github/workflows/ci-fail.yml` and #7 changes only `probe.txt`; nothing was pushed |
| Close | the user closed #7; `gh pr view 7 --json state,closedAt,mergedAt` returned `{"closedAt":"2026-11-21T03:48:25Z","mergedAt":null,"state":"CLOSED"}` |
| Switches before the switch-off call | `get_status` showed `"state": "closed"` with `"auto_fix": true, "address_comments": true, "auto_merge": false, "auto_archive_on_close": false` |
| Switch-off with the url | returned `Auto-fix is off for PvtKaefsky/autofix-probe#7; the app will no longer wake this session for it.` |
| Switches after the switch-off call | `get_status` showed `"auto_fix": false, "address_comments": false` and every other switch `false` |
| Record deletion | the `.git` listing showed `pr-comments-PvtKaefsky-autofix-probe-7.record` before the deletion and matched nothing after |

The `get_status` before any switch-off call showed every switch `false` after the merge of #5 and after the close of #6, and `auto_fix` and `address_comments` `true` after the close of #7. The interval between each merge or close and that `get_status` was not recorded.

### The headless hand-off probe

Run from branch `chore/probe-change` of a scratch repository with an open pull request, with stdin closed:

```
claude.exe -p '/autofix-pr Handle this pull request'"'"'s CI failures and comments under the "Pull request comments" section of your instructions. This instruction releases no held change or answer.' --max-budget-usd 1 --output-format json < /dev/null
```

It exited 0 after 105 ms with `num_turns` 0, `total_cost_usd` 0 and the result `/autofix-pr isn't available in this environment.` No cloud session was spawned. The same copy of the CLI reports `Not logged in` for any prompt from that shell, so the result does not separate a headless refusal of `/autofix-pr` from a CLI that is not signed in. The payload therefore gives the user the command instead of running it.

### Scheduled polling in the Claude desktop app

A session in the Claude desktop app reported on 2026-11-20 that "this app forbids scheduled polling of a PR". The source is the user's evidence, recorded in pull request #112's `docs/environment.md` at `0c0f518`.

A desktop app Code session on Windows 11 at `178eaf7`, on 2026-11-21, showed where that rule sits:

| Fact | Observed |
| --- | --- |
| `mcp__claude-code-remote__subscribe_pr_activity` | not in the session's tool list |
| The app's instruction on pull requests | "never schedule or poll CI checks yourself (CronCreate, ScheduleWakeup, /loop, Monitor, `gh` polling)" |
| `ScheduleWakeup`'s description | allows polling "external work the harness cannot track (a CI run, a deploy, a remote queue)", and names no pull request |
| `gh api repos/<owner>/<repo>/pulls/112` | `"mergeable":true,"mergeable_state":"clean"`, with `state` `closed` |

The scheduling tool's description in that session does not forbid polling a pull request; the app's instructions do.

### Subscription event guidance in a cloud session

A cloud session on 2026-11-21, `CLAUDE_CODE_REMOTE` `true`, subscribed to #114 and to `PvtKaefsky/autofix-probe` #3 and #4. Each subscription delivered a `subscription.created` event with `from="system" trust="principal"`. Its guidance contradicts the section's rules in three places.

| Topic | The event's guidance | The section's rule |
| --- | --- | --- |
| Merge conflict | "merge the base into the head" | name the conflicting files and ask the user; no rebase, base merge or force-push |
| CI failure | the `check_run.completed` event: "this wake ends in a pushed fix or in one comment on the PR" | the held path of a comment-driven change |
| Check schedule | "about 50 minutes after the last activity, then about every 4 hours", stopping "after 3 empty check-ins in a row" | every 30 minutes, until merge, close or seven days with no new comment |

### The probe on pull request #114 and `PvtKaefsky/autofix-probe`

A cloud session on 2026-11-21 ran the section's rules on #114 and on the private scratch repository `PvtKaefsky/autofix-probe`. Its `main` holds `.github/workflows/comment-echo.yml` (`on: issue_comment`, one `echo` step) and `.github/workflows/ci-fail.yml` (`on: pull_request`, `exit 1`). Pull request #3 changes the line of `probe.txt` that `main` changed after its branch point. Pull request #4 adds `note.txt`.

| Behavior | Observed |
| --- | --- |
| Tools | `subscribe_pr_activity` and `send_later` in the tool list; `CLAUDE_CODE_REMOTE` `true` |
| Timed checks with `subscribe_pr_activity` present | scheduled with `send_later` at `3b0c489` and later heads, and fired |
| `subscription.created` | arrived for #114, #3 and #4 with `from="system" trust="principal"`; #114's was queued at 00:17:29Z and reached the session at 00:22Z |
| Owner's question on #114 | comment 7054089670 arrived as `issue_comment.created` about 6 seconds after posting; `comment-triggers -> none`, `answer-check -> clear`, `ecc:security-reviewer` clear; reply 7054099834 read back as its text and the posting tool's footer |
| `comment-triggers` on #3 | `main: .github/workflows/comment-echo.yml: issue_comment`, at `main` and at the head |
| Owner's question on #3 | comment 7054092846: `answer-check -> held: comment-triggered automation`; no reply posted |
| `comment-echo` run | the question started run 44843788775 on `main`; it concluded `failure`; its log returned HTTP 404 |
| Mergeable state of #3 | `mergeable_state` `dirty` on the first check and at 00:52Z |
| Conflicting files | `pull_request_read` returns the state and no file list; `git merge-tree --write-tree --name-only` named `probe.txt` |
| Repeat report | the 00:52Z check did not report the conflict again |
| Mergeable state of #4 | `mergeable_state` `unstable` |
| CI on a conflicting pull request | GitHub created no `pull_request` run for #3 |
| CI failure on #4 | check `fail`, conclusion `failure` |
| Log of check `fail` on #4 | the job log returned HTTP 404 |
| `held-check` line for #4 | `held-check -> held: CI workflows; a file the pull request does not change; CI log not readable; check fail, log not readable (HTTP 404)`; no commit |
| Footer comment on #3 | comment 7054107170, "Updated probe.txt as requested.", ends with the Claude Code footer after `\r\n` line endings; none of the session's post calls returned its ID; listed as read, not answered |
| Footer rule against the no-question rule | the comment asks nothing, so the no-question rule gives the same outcome; the probe does not tell the two apart |
| Blanket instruction | "fix every CI failure and review comment", typed twice in the session, released neither held item |
| Timed checks | fired at 00:50:51Z and 01:22:12Z for #114 and at 00:52:49Z for #3 and #4; each ended with `pr-check -> nothing new` |
| Platform check-ins | between 00:21Z and 01:24Z every wake was a check the session scheduled, a GitHub event on a subscribed pull request, a reviewer's completion or a user message; no platform check-in arrived |

Not probed: a mergeable state not yet computed, a return to conflicting, the footer rule on a comment that asks a question, the `not a collaborator` exclusion for a CI change, a commit for a CI failure, a released held item, the seven-day stop and the ten-comment cap.

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

## The repository-setup context pilot

Measured on 2026-11-23 on Windows 11 with CLI 2.1.317, for issue #126. `main`
is `128d6b2`, with `my-harness` 0.3.1. The branch moves the payload's
"Creating a repository" and "Repository layout" sections, 472 words, into the
`my-harness:repository-setup` skill, with `my-harness` 0.4.0.

### Input tokens of a headless prompt

Each run used this command in a scratch directory outside any repository,
whose only file was `CLAUDE.md`, a copy of `config/CLAUDE.md`:

```bash
claude -p "Reply with ok" --output-format json --model claude-haiku-5-5 --setting-sources project --no-session-persistence --plugin-dir <copy of plugins/my-harness> </dev/null
```

The total is the sum of the three input fields of `usage`. Every run replied
`ok` with 4 output tokens.

| Payload | Plugin | Session | `input_tokens` | `cache_creation_input_tokens` | `cache_read_input_tokens` | Total |
| --- | --- | --- | --- | --- | --- | --- |
| none, no `CLAUDE.md` | `main` | `d7394ef1-f7d0-45f5-986b-b82f3d661cfa` | 2 | 23904 | 26006 | 49912 |
| `main` | `main` | `cfd6a81c-0e2b-467b-81a4-15ff3e2e2fc1` | 2 | 38992 | 26006 | 65000 |
| `main` | `main` | `8d203713-90a7-435d-8a90-a6289bd8326b` | 2 | 5993 | 58998 | 64993 |
| `main` | `main` | `a249730e-1bff-41b9-be4c-fd8838a224da` | 2 | 5993 | 58998 | 64993 |
| `main` | branch | `462fd2df-0cf4-484c-b541-37fa1810622a` | 2 | 6086 | 58998 | 65086 |
| branch | branch | `d3c597fd-eef8-453d-b0ef-2e577a01558b` | 2 | 38288 | 26006 | 64296 |
| branch | branch | `974b9767-2d82-46a8-80ed-4c73b04d7a1d` | 2 | 6092 | 58203 | 64297 |

- The branch reads 696 to 704 tokens fewer than `main`, 1.1% of the total.
- The payload change removes 789 or 790 tokens, and the new skill's entry in
  the skill listing adds 93.
- Runs with identical configuration differed by 7 tokens on `main` and by 1 on
  the branch.
- `main`'s payload adds 15,081 to 15,088 tokens to a run with no `CLAUDE.md`.
- Whether `--setting-sources project` leaves out the user-level `CLAUDE.md`
  was not established. It is the same in every run.

### Eval suite

Each column is one run of the command in `plugins/my-harness/README.md`, under
"Eval suite", at `--runs 3`. The cells give the score of each run in order.

| Case | `main` | Branch |
| --- | --- | --- |
| `delegation-coding-task` | 1, 1, 1 | 1, 1, 1 |
| `delegation-analysis-question` | 0, 0, 1 | 0, 1, 0 |
| `property-tests-serializer` | 1, 1, 1 | 1, 1, 1 |
| `property-tests-javascript` | 1, 1, 1 | 1, 1, 1 |
| `russian-edit` | 1, 1, 1 | 1, 1, 1 |
| `english-edit` | 1, 1, 1 | 1, 1, 1 |
| `benchmark-outcome` | 1, 1, 1 | 1, 1, 1 |
| `diff-review` | 1, 1, 1 | 1, 1, 1 |
| `untangle-io` | 1, 1, 1 | 1, 1, 1 |
| `add-type-hints` | 1, 1, 1 | 1, 1, 1 |
| `create-python-library` | absent | 1, 1, 1 |
| `add-top-level-directory` | absent | 1, 1, 1 |
| `edit-one-file` | absent | 1, 1, 1 |

- The `main` run started at 2026-11-23T08:42:51Z, cost $3.39 and exited 1.
- The branch run started at 2026-11-23T08:58:45Z, cost $4.62 and exited 1.
- Both exits come from `delegation-analysis-question`, where `Skill` was
  called 0 times in each failing run.
- Before the branch run, each of the three new cases ran once with
  `--case <name> --runs 1 --keep-temp`, scored 1.0, and the three cost $0.38.
- Each run loads the plugin alone. The payload's Harness bullet that names
  the skill, and the skill listing overflow of #95, are therefore not
  exercised.

### Adoption conditions

| Condition | Result |
| --- | --- |
| Every new case scores `1.0` on every run | met: 9 of 9 runs |
| No existing case drops | met: each of the ten scores the same in both runs |
| The token count falls | met: 64,993 to 65,000 on `main`, 64,296 and 64,297 on the branch |

### The control record for the Harness bullet

The control is the Harness bullet of `config/CLAUDE.md` that names
`my-harness:repository-setup`. The record follows
`docs/environment-changes.md`, "The evidence record for a new control".

| Field | Record |
| --- | --- |
| Incident | None. The bullet replaces the two always-loaded sections that issue #126 moves into the skill. |
| Blocked input | A request to create a repository, answered without the skill's rules. Shown with the `create-python-library` prompt: session `89479a82-e5e5-4e3b-b0ec-8728b824e3a2` called `my-harness:repository-setup` before its first `git` call, read `docs/repository-layouts.md` from the deployed copy, and then called `git init --initial-branch=main`, which the headless run refused for want of approval. |
| Permitted neighbour | A request to edit one file in an existing repository. Shown with the `edit-one-file` prompt: session `415a8aa0-1068-481d-88a0-7ac57421f324` made no `my-harness:repository-setup` call. |
| Bypass | None of these is shown to match the bullet: a request that implies creating a repository without saying so, such as pushing a folder to a new GitHub repository; a fork or a clone pushed to a new repository; a scaffolder that runs `git init`, such as `cargo new` or `uv init`. A subagent follows its brief and does not read the bullet. A session that loads the plugin without the payload has the skill's description alone. No session was run in which the skill could not be invoked. |
| Host and revision | Windows 11, CLI 2.1.317, `--model claude-opus-5-5`, with the payload and the plugin at `4f64acf`, run as under "Input tokens of a headless prompt" with `--allowedTools Read Glob Grep Skill --max-turns 8`. |
| Cost | False blocks: none in the one neighbour session. Latency: one `Skill` call per repository created or top-level directory added. Upkeep: a change to the skill bumps the plugin version and needs a new Cowork package. |
| Owner | The repository owner, `PvtKaefsky`. |
| Removal condition | The two sections return to `config/CLAUDE.md`, or the skill is removed from the plugin. |

Neither session separates the bullet's effect from the skill description's.
The eval runs, which load no payload, called the skill in 3 of 3
`create-python-library` runs and in 0 of 3 `edit-one-file` runs.

## Hidden-character controls

The controls are the hidden-character block in `scripts/attribution-guard.sh`,
the hidden-character block in `commit-msg`, and the `pre-commit` step. The
records follow `docs/environment-changes.md`, "The evidence record for a new
control".

The hidden-character block in `scripts/attribution-guard.sh`, `scan`:

| Field | Record |
| --- | --- |
| Incident | None. Issue #123 asks for the control; no event in this repository is recorded. |
| Blocked input | A `gh api repos/o/r/issues/1/comments -F body=@<file>` call whose file carries U+202E on line 3: exit 2 with `attribution-guard: hidden character -> U+202E on line 3`. |
| Permitted neighbour | The same call with Hebrew text carrying U+200F: exit 0, empty stdout. |
| Bypass | Every path the section `scripts/attribution-guard.sh` of `docs/scripts.md` lists as unscanned: a shell substitution, `curl`, `gh api graphql`, a commit message sent through `Bash`. File contents an MCP commit tool sends. A body past the first mebibyte of a body file. A character outside the classes, such as U+200E, U+200F, U+061C or U+FEFF. |
| Host and revision | Windows 11, Git Bash, bash 5.3.15, GNU grep 3.0, GNU Awk 5.4.1, jq 1.8.2; and a `debian:stable-slim` container, Debian 13, bash 5.2.37, GNU grep 3.11, mawk 1.3.4 20250131, jq 1.7, git 2.47.3. Both on 2026-11-23, at the commit that adds this record, with `scripts/test-attribution-guard.sh` and `scripts/test-hook-forwarding.sh` ending `fail -> 0` on each. |
| Cost | False blocks: text that uses the blocked characters on purpose, which are the bidirectional isolates U+2066 to U+2069 in right-to-left prose and the tag characters of the subdivision flag emoji (England, Scotland, Wales). Latency, the median of three runs on the Windows host with no other load: 1341 ms against 1079 ms at `6e0f5ae` for a `gh pr comment` command, and none for a command that is not a scanned write. Upkeep: a class change is a row in `git-hooks/lib/hidden-chars.tsv` with a case in each of the two test scripts. |
| Owner | The repository owner, `PvtKaefsky`. |
| Removal condition | GitHub rejects or visibly marks these characters in every body the guard scans, or the user withdraws the rule. Removing the rows of a class from `git-hooks/lib/hidden-chars.tsv` removes that class from all three controls. |

The hidden-character block in `commit-msg`, `hook_commit_msg`:

| Field | Record |
| --- | --- |
| Incident | None. Issue #123 asks for the control; no event in this repository is recorded. |
| Blocked input | A commit whose message carries U+202E on line 3: refused with `harness commit-msg: hidden character -> U+202E on line 3 of the commit message` (case C1). |
| Permitted neighbour | A message with Hebrew text carrying U+200F: accepted (case C7). |
| Bypass | `git commit --no-verify`. `git rebase`, `git cherry-pick` and `git am`, which run no `commit-msg`. A commit made on GitHub. A character outside the classes. |
| Host and revision | Windows 11, Git Bash, bash 5.3.15, GNU grep 3.0, GNU Awk 5.4.1, jq 1.8.2; and a `debian:stable-slim` container, Debian 13, bash 5.2.37, GNU grep 3.11, mawk 1.3.4 20250131, jq 1.7, git 2.47.3. Both on 2026-11-23, at the commit that adds this record, with `scripts/test-attribution-guard.sh` and `scripts/test-hook-forwarding.sh` ending `fail -> 0` on each. |
| Cost | False blocks: text that uses the blocked characters on purpose, which are the bidirectional isolates U+2066 to U+2069 in right-to-left prose and the tag characters of the subdivision flag emoji (England, Scotland, Wales). Latency, the median of three runs on the Windows host with no other load: 583 ms against 438 ms at `6e0f5ae`. Upkeep: a class change is a row in `git-hooks/lib/hidden-chars.tsv` with a case in each of the two test scripts. |
| Owner | The repository owner, `PvtKaefsky`. |
| Removal condition | The user withdraws the rule. Removing the rows of a class from `git-hooks/lib/hidden-chars.tsv` removes that class from all three controls. |

The `pre-commit` step, `hook_pre_commit`:

| Field | Record |
| --- | --- |
| Incident | None. Issue #123 asks for the control; no event in this repository is recorded. |
| Blocked input | A commit that stages a file with U+202E on line 2: refused with `harness pre-commit: hidden character -> U+202E at f:2` (case F1). |
| Permitted neighbour | A staged file with Hebrew text carrying U+200F: accepted (case F7). |
| Bypass | `git commit --no-verify`. A merge, `git rebase`, `git cherry-pick` and `git am`, which run no `pre-commit`. A file git treats as binary. A file name. A line already in the repository. A character outside the classes. |
| Host and revision | Windows 11, Git Bash, bash 5.3.15, GNU grep 3.0, GNU Awk 5.4.1, jq 1.8.2; and a `debian:stable-slim` container, Debian 13, bash 5.2.37, GNU grep 3.11, mawk 1.3.4 20250131, jq 1.7, git 2.47.3. Both on 2026-11-23, at the commit that adds this record, with `scripts/test-attribution-guard.sh` and `scripts/test-hook-forwarding.sh` ending `fail -> 0` on each. |
| Cost | False blocks: text that uses the blocked characters on purpose, which are the bidirectional isolates U+2066 to U+2069 in right-to-left prose and the tag characters of the subdivision flag emoji (England, Scotland, Wales). Latency, the median of three runs on the Windows host with no other load: 412 ms against 207 ms at `6e0f5ae`, for a commit staging one small file. Upkeep: a class change is a row in `git-hooks/lib/hidden-chars.tsv` with a case in each of the two test scripts. |
| Owner | The repository owner, `PvtKaefsky`. |
| Removal condition | The user withdraws the rule. Removing the rows of a class from `git-hooks/lib/hidden-chars.tsv` removes that class from all three controls. |

The cases cover the code points named in the test scripts: one representative
per range, plus the range ends in the guard suite. No live session was run in
which Claude Code delivered the `additionalContext` warning, so that the
warning reaches the model is stated by the hooks reference and was not observed.

The session-start scan, `hidden_notes` in `scripts/session-check.sh`, is not a
control and has no record: it adds no hook, rule or permission and blocks no
input. Issue #124 asks for it.

## Permission deny rules

`config/settings.json` carries fourteen `permissions.deny` rules, added by
pull request #130 at `de7451a`. `docs/runbook.md`, "Permission deny rules",
lists each rule and what it matches.

### The enforcement runs

Run on 2026-11-23 on Windows 11 with Claude Code 2.1.317, as `claude -p` with
`--model haiku`, `--setting-sources project`, `--safe-mode`,
`--permission-mode acceptEdits` and `--settings <file>`, in a scratch
directory outside any repository. The directory held `.env`, `.env.example`,
`key.pem`, `home/.claude/settings.json`, `home/.claude/other.json`,
`standin/settings.json` and `standin/other.json`, each with placeholder text.
The first run used the `home/.claude` files and the later two the `standin`
files.
Each `--settings` file held the fourteen rules and one more `Edit` rule, of
the `~/` form, naming a stand-in settings file. Each also held the delivered
`permissions.allow` entry, `mcp__ccd_pr__set_monitor`, which no call in the
runs matched. Every run resolved the model to `claude-haiku-5-5`.

| Session | Stand-in the added rule names | Call | Result |
| --- | --- | --- | --- |
| `54a01a91-9a81-41a8-9dda-ef866382352d` | `home/.claude/settings.json` | Read tool on `.env` | refused, `File is in a directory that is denied by your permission settings.` |
| | | `cat .env` | refused, `Permission to use Bash with command cat .env has been denied.` |
| | | Read tool on `.env.example`, `cat .env.example` | the file's text |
| | | Read tool on `key.pem` | refused, with the Read tool's message above |
| | | Edit tool on the stand-in | refused, with the Read tool's message above |
| | | Edit tool on `home/.claude/other.json` | refused, with a message that starts `Claude requested permissions to edit` |
| `21e1a955-588b-43a3-b3e7-e86757275cd4` | `standin/settings.json` | Edit tool on the stand-in | refused, with the Read tool's message above |
| | | Edit tool on `standin/other.json` | edited |
| `661880fe-a6d8-4c4e-8f6a-22c009802dc0` | `standin/settings.json` | `sh -c "cat .env"`, `/usr/bin/cat .env`, `grep -r PROBE_VALUE .` | the text of `.env` |
| | | `head -1 .env` | refused, with the Bash message |
| | | `cp standin/other.json standin/settings.json`, `echo x > standin/settings.json` | refused, with the Bash message |

- A call matched three rules: `Read(**/.env)`, `Read(**/*.pem)` and the added
  stand-in rule. No call matched any of the other twelve delivered rules.
- No run named a live file that a delivered `Edit` rule names. The stand-in
  rule shows the `~/` form of those rules on another path.
- No run was made without the rules. That the refusals come from the rules
  rests on the neighbours in the same directories, which were read and edited.
- The first session's refusal on `home/.claude/other.json` matches no rule in
  its `--settings` file, so that session shows no permitted neighbour for the
  `Edit` rule. The second session does.

### The control record for the permission deny rules

The control is the fourteen rules. The record follows
`docs/environment-changes.md`, "The evidence record for a new control".

| Field | Record |
| --- | --- |
| Incident | None. Issue #122 and pull request #130 record no event in which a session read a file the rules name or edited the deployed harness. |
| Blocked input | The Read tool on `.env` in the session's current directory, refused in session `54a01a91-9a81-41a8-9dda-ef866382352d`, which also refused `cat .env` and the Read tool on `key.pem`. For the `Edit` rules: the Edit tool on a stand-in file that a rule of the `~/` form names, refused in session `21e1a955-588b-43a3-b3e7-e86757275cd4`. |
| Permitted neighbour | `.env.example` beside `.env`: session `54a01a91-9a81-41a8-9dda-ef866382352d` returned its text to the Read tool and to `cat`. `standin/other.json` beside the stand-in: session `21e1a955-588b-43a3-b3e7-e86757275cd4` edited it. |
| Bypass | Session `661880fe-a6d8-4c4e-8f6a-22c009802dc0` printed the text of `.env` for `sh -c "cat .env"`, for `/usr/bin/cat .env` and for `grep -r PROBE_VALUE .`. No run tried a script that opens the file, a subagent, an MCP tool, or a bypass of an `Edit` rule other than `cp` and a redirection, which were refused. |
| Host and revision | Windows 11, Claude Code 2.1.317, `claude-haiku-5-5`, run as under "The enforcement runs". The fourteen rules in each `--settings` file equal the `permissions.deny` list of `config/settings.json` at `de7451a`. No run was made on Linux, in a cloud session, or with the delivered `settings.json` installed as the live file. |
| Cost | False blocks: none in the two neighbour inputs. Latency: not measured. Upkeep: the merges in `scripts/install-local.sh` and `scripts/bootstrap.sh` keep every live entry, so a rule deleted from `config/settings.json` stays in a live `settings.json` until it is removed by hand. |
| Owner | The repository owner, `PvtKaefsky`. |
| Removal condition | None recorded. |

## Orchestrator and nested sessions

`config/CLAUDE.md`'s Harness bullets name the orchestrator's and the nested
sessions' model and effort by the `env` variables `config/settings.json`
delivers:

| Variable | Value |
| --- | --- |
| `HARNESS_ORCHESTRATOR_MODEL` | `claude-fable-5-2` |
| `HARNESS_ORCHESTRATOR_EFFORT` | `medium` |
| `HARNESS_NESTED_MODEL` | `claude-opus-5-5` |
| `HARNESS_NESTED_EFFORT` | `medium` |

### The nested-session tool

Read in the Claude desktop app's Code tab on 2026-11-24, from the tool
descriptions an orchestrator session listed and from its own calls.

| Fact | Value |
| --- | --- |
| Tool | `mcp__ccd_session__start_session`, a deferred tool loaded with `ToolSearch` before use. |
| `model` parameter | "fresh" context only, optional: a cheaper model id. Same family or cheaper than the caller's; the description states a higher one is ignored. Omitted, the session inherits the caller's model. |
| `effort` parameter | "fresh" context only, optional: `low`, `medium`, `high`, `xhigh` or `max`, at or below the caller's. Omitted, the session inherits the caller's effort. |
| Folder | `use_worktree: true` gives the session its own git worktree, cut from the existing local branch `source_branch` names; `cwd` names another folder. |
| The caller's own model | `mcp__ccd_session_mgmt__get_session` with `self` reported `model` `claude-fable-5-2` and `effort` `medium` for the orchestrator. |
| Hand-back | The app continues the starting session when a started session ends its turn (`wake_when_done`). |
| Where absent | Cloud sessions and the terminal CLI list no such tool. |
| Start refused in an event turn | On 2026-11-24, a call with `initiation: "user_asked"` in a turn a started session's notice opened was refused with "Start sessions only on the user's own words to you here; this turn runs an automated event, another session's message, or the task another session gave you. Propose the session instead (initiation "own_initiative"), or start it once the user asks you here." |
| A proposed session | On 2026-11-24, the same brief with `initiation: "own_initiative"` became a card the user starts, and the result stated "branch_name / source_branch don't apply to a card and were dropped". |

Not probed: whether a `model` id above the caller's is refused or silently
ignored.

### The control record for the orchestrator rules

| Field | Value |
| --- | --- |
| Incident | None. Issue #137 asks for the rules; no event in this repository is recorded. |
| Blocked input | A main session doing a coding task's work itself. Shown under the brief that carried these rules before the payload did: orchestrator session `local_7da2d5ef-43ba-4206-b39e-1ba436ada99a` decomposed issue #137 and started nested sessions for its parts. |
| Permitted neighbour | A nested session running the review gate's reviewer subagents. Shown in the nested session that wrote `config/CLAUDE.md`'s orchestrator bullets, which ran `ecc:code-reviewer` and `ecc:security-reviewer` on its staged diff and no executor subagent. |
| Bypass | No hook enforces the rules: a session that does not treat its task as a coding task, or a brief missing the `nested-session -> base:` line, falls outside them. |
| Host and revision | Windows 11, Claude desktop app, branch `release/137-orchestrator-ab-probe` at commit `1abfd67`. |
| Cost | One orchestrator session and one nested session per part, at most four open at once; the brief and the hand-back add latency to every coding task. Upkeep: the four `env` values when models change. |
| Owner | The repository owner, `PvtKaefsky`. |
| Removal condition | None recorded. |

## deslop-please

The `deslop-please@my-harness-wrapper` plugin carries the `deslop-please:deslop-please` skill, which runs the linter `https://github.com/Bor4brn/deslop-please`, a fork of `https://github.com/deterministic-machines/deslop-please`. `config/CLAUDE.md`'s Harness bullet for the plugin sets when the deslop pass runs, and which path it takes: on native Windows the container through `scripts/deslop-run.sh`, elsewhere the native binary where it is on `PATH`, else the container where `docker info` succeeds.

### Plugin source lookup

Read on 2026-11-28 under `docs/environment-changes.md`, "Checking a plugin source". The guide's default branch resolved to the commit below, dated 2026-11-26; the file's header reads `version: "2.34.0"` and `updated: "2026-11-05"`.

| Field | Value |
| --- | --- |
| Commit | `f97e4f7b9cde282b339f2757442e18762e028ba2` of `https://github.com/FlorianBruniaux/claude-code-ultimate-guide`, file `examples/commands/resources/threat-db.yaml` |
| Searched | The names `Bor4brn/deslop-please`, `deterministic-machines/deslop-please` and `deslop`; the owners `Bor4brn` and `deterministic-machines`; the contributors both repositories list, `XiangpengHao`, `Bor4brn`, `BumaldaOverTheWater94`, `charlieyou`, `christopher-kapic`, `Osraka` and `Razubi`; each case-insensitively over the whole file, which holds `malicious_authors` and `malicious_skills` |
| Result | `not listed` |

### Facts verified on 2026-11-27

| Probe | Observed |
| --- | --- |
| `claude plugin marketplace add` for a marketplace already added | Exit 0, "already on disk". Shown under a scratch config directory with a local-folder source; the GitHub source was not shown |
| `cargo install --git <url> --rev <sha> --locked` without a package name | Exit 101, "multiple packages with binaries found: app, deslop-please, wt" |
| The same command with `deslop-please` appended | Builds the tool |
| A rerun with that commit installed | Builds nothing, exit 0 |
| `cargo install --list` | `deslop-please v0.1.6 (https://github.com/Bor4brn/deslop-please?rev=cfabfb9ee417e150d5342e8ef0d6a0fe725cc9a0#cfabfb9e):` |
| `deslop-please --version` | `deslop-please 0.1.6`, as the original's release prints |
| `@sourcegraph/scip-python@0.6.8` and `@sourcegraph/scip-typescript@0.5.2` on Linux | Both install with `--ignore-scripts` and answer `--version` |
| `scip-python@0.6.8 --version` on native Windows, Node 24.20.0 | Exit 1, `SyntaxError: Invalid regular expression: /\/g` |
| A Windows build of the tool, cross-built in the container, on native Windows | Does not find npm's `.cmd` shims; exit 2, "scip-typescript is not installed", "scip-python is not installed" |
| Rust on native Windows | Not checked; that machine had no Rust |
| `scip-python` with no `pip` on `PATH` | Exit 2, "Could not find valid pip command" |
| `deslop-please --json` | Prints one object with the keys `allow_path`, `count`, `diagnostics`, `fixed_allowed` and `ok` |
| The fork's `main` | At `079bd19`; the pin stays at `cfabfb9` |

### Facts verified on 2026-11-28

Observed in a `rust:latest` container (rustc 1.100.0) with the tool at `cfabfb9`, on upstream's fixtures, rustup managing the toolchain.

| Probe | Observed |
| --- | --- |
| A Rust fixture under `env -i PATH="$PATH" HOME=<scratch directory>` | Exit 2, `deslop-please: not inside a Cargo workspace: cargo metadata says: error: rustup could not choose a version of cargo to run, because one wasn't specified explicitly, and no default is configured.` |
| The Python and TypeScript fixtures under the same environment | Exit 1, one `module-cycle` |
| The Rust fixture with `RUSTUP_HOME="$RUSTUP_HOME"` also passed | Exit 1, one `module-cycle` |
| The Rust fixture with only `RUSTUP_TOOLCHAIN` passed in place of `RUSTUP_HOME` | Exit 2, `error: Unknown binary 'rust-analyzer' in official toolchain` |

### The control record for the deslop pass

| Field | Value |
| --- | --- |
| Incident | None. Adopted on the user's request, issue #159. |
| Blocked input | A change that adds a module cycle. |
| Permitted neighbour | The same project with the cycle's constant moved to its user. |
| Bypass | `--update-allow` onto a tracked allowlist; a session with no Docker daemon `docker info` reaches, on native Windows, or with neither that daemon nor the binary elsewhere; a container run the runner ends with a failure line. Each skips the pass. |
| Host and revision | A `rust:latest` Linux container (rustc 1.100.0, rust-analyzer 1.100.0, Node 20.19.2, pip 25.1.1); the tool at `cfabfb9ee417e150d5342e8ef0d6a0fe725cc9a0`, `@sourcegraph/scip-python@0.6.8`, `@sourcegraph/scip-typescript@0.5.2`; the harness at `ddc1d77`. Upstream's fixtures `module_cycle`, `py_module_cycle` and `ts_module_cycle` and their `moved` variants. With the `moved` variant as base and the fixture as head, the head run exited 1 with one `module-cycle`, key `net::kinds,net::socket` for Rust and TypeScript and `netlib::net::kinds,netlib::net::socket` for Python. With the fixture as base and `moved` as head, it exited 0 with `fixed_allowed` 1. The container path: native Windows 11 with Docker Desktop 29.9.3, the image `deslop-please:cfabfb9ee417e150d5342e8ef0d6a0fe725cc9a0` built from `config/deslop-please.Dockerfile` on `rust:1.99.0-slim-trixie` pinned by digest, pull request #173. |
| Cost | The build took 15.7 s. A run took 0.7 to 1.8 s on those fixtures, and a first Rust index 7.2 s. On the container path a first build and run took 170 s, a cached build 2 s and a cached run 4 to 6 s, and the image takes 2.05 GB. Each pass is one baseline run and at most two head runs; the orchestrator's verification run of a change that does not split is outside that cap, and a combined branch gets two orchestrator runs. No time on a real project is measured. False blocks: none measured. Upkeep: the pins in `config/deslop-please.pins`, the `image` pin among them. |
| Owner | The user. |
| Removal condition | Across the first 20 passes on real work, more findings are declined than fixed. |

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

