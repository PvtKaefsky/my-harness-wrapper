# Environment

What the sandbox is, and what the delivery path may assume about it.

## Established facts

1. **Root-only container.** Setup scripts run as `uid=0` with `HOME=/root`.
   There is no `user` account. `/home/user` exists and is owned by `root:root`.
   Never use `runuser` or `su`, and never create accounts.
2. **The init script fetches the repository itself.** It clones
   `$HARNESS_REPO_URL`, or its own default where that variable is unset or
   empty, `--depth 1` into `/opt/my-harness-wrapper`, and runs
   `scripts/bootstrap.sh` from there. No session needs the repository attached.
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
of the default branch made at build time. A merged change therefore reaches the
next build with no paste. No operator action triggers that build. The pasted
copy supplies the clone URL and the version marker.

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
they can be stale. Fetch before comparing `HEAD` against `origin/main`.

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
taking effect from a CLI version that sends no reminder at all. The Bash tool's description
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
alike. Whether they reach a local CLI session is unchecked, so a session outside
claude.ai may run without them.

A payload in context implies something wrote `/root/.claude/CLAUDE.md`. It does
not distinguish the init script's bootstrap run from any other writer of that
file, a hand-run of `scripts/bootstrap.sh` among them. Its absence does not
imply bootstrap did not run, the file being read at session start rather than
on demand.

## Diagnostic-output invariant

Every diagnostic line prints the predicate tested and the value observed, never
a conclusion about why. Write `test -f X -> no`, not `config repo not attached`.
A log that records conclusions records the author's model of the sandbox; a log
that records observations records the sandbox.

## Unresolved

* Which component rewrites `/root/.gitconfig`, and what triggers it.
* What triggers a rebuild. A session's check reported
  `log mtime >= boot time -> yes, this session built the snapshot`. That line
  says a build ran in that container. It does not say which of the three
  triggers caused it, and it does not separate a build from any other write to
  `/home/user/bootstrap.log` after boot. A build at 17:47:23 in a session with a
  different single repository attached left the 17:42 build as the snapshot a
  later session with this repository attached restored.
* The shape of `tool_response` a `PostToolUse` hook receives for an MCP tool.
* Whether a `claude plugin install` of a later CLI version, or a delivered key
  of a different shape, preserves what this one did. The build settled the case
  it ran: bootstrap wrote `config/settings.json` whole before the CLI
  ran, and the delivered `hooks` array survived the CLI's rewrite.

