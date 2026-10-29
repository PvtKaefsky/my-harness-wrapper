# Environment

What the sandbox is, and what the delivery path may assume about it.

## Established facts

1. **Root-only container.** Setup scripts run as `uid=0` with `HOME=/root`.
   There is no `user` account. `/home/user` exists and is owned by `root:root`.
   Never use `runuser` or `su`, and never create accounts.
2. **The init script fetches the repository itself.** It clones
   branch `feat/claude-harness` of `$HARNESS_REPO_URL`, or of its own default
   where that variable is unset or empty, `--depth 1` into
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
of `feat/claude-harness` made at build time, not of the default branch. A
merged change therefore reaches the next build with no paste. No operator
action triggers that build. The pasted copy supplies the clone URL and the
version marker.

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
they can be stale. Fetch before comparing `HEAD` against
`origin/feat/claude-harness`.

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

A cloud session's system prompt carries this requirement, read in a probe at
`3abfe68`, `BOOTSTRAP_VERSION` `0.1.17`:

> Every comment, review, review reply, or issue comment you author MUST end
> with the Claude Code attribution footer … `---` /
> `_Generated by [Claude Code](https://claude.ai/code)_`. Include the footer
> yourself even when the tool you're using also adds it: the server strips
> duplicate footers before posting, so a model-included footer never stacks
> with a server-appended one.

A cloud session at `bb2b611`, `BOOTSTRAP_VERSION` `0.1.19`, carried the same
requirement. No post has tested the prompt's statement that the server strips a
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

Not measured. The session assigned the measurement declined to post a comment
without the footer its system prompt requires, so no test comment was posted or
deleted.

| Path | Body field | Footer appended by the path | An edit removes it |
| --- | --- | --- | --- |
| `gh issue comment` | `--body`, `-b`, `--body-file`, `-F` | not measured | not measured |
| `gh pr comment` | `--body`, `-b`, `--body-file`, `-F` | not measured | not measured |
| `gh pr review` | `--body`, `-b`, `--body-file`, `-F` | not measured | not measured |
| `gh api` | the `body` field | not measured | not measured |
| `mcp__github__add_issue_comment` | `body` | not measured | not measured |
| `mcp__github__update_issue_comment` | `body` | not measured | not measured |
| `mcp__github__add_reply_to_pull_request_comment` | `body` | not measured | not measured |
| `mcp__github__pull_request_review_write` | `body` | not measured | not measured |
| `mcp__github__add_comment_to_pending_review` | `body` | not measured | not measured |

No `PostToolUse` entry covers a comment, review or reply path.

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
| Node | v24.14.0, on `PATH` | session |
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
  `log mtime >= boot time -> yes, this session built the snapshot`. That line
  says a build ran in that container. It does not say which of the three
  triggers caused it, and it does not separate a build from any other write to
  `/home/user/bootstrap.log` after boot. A build at 17:47:23 in a session with a
  different single repository attached left the 17:42 build as the snapshot a
  later session with this repository attached restored.
* The shape of `tool_response` a `PostToolUse` hook receives for an MCP tool.
* Whether any comment, review or reply path appends the footer itself, and
  whether an edit removes one it appends.
* Which ECC release or CLI version, if any, installs `ecc@ecc`'s npm
  dependencies itself.
* Whether a `claude plugin install` of a later CLI version, or a delivered key
  of a different shape, preserves what this one did. The build settled the case
  it ran: bootstrap wrote `config/settings.json` whole before the CLI
  ran, and the delivered `hooks` array survived the CLI's rewrite.

