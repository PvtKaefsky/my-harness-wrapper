# Requirements

One testable line per behavior a user or caller can observe. The live probes on pull requests #107 and #112, recorded in `docs/environment.md` under Pull request activity, test the rows marked probe under Pull request comments; the repository's test scripts cannot drive a session.

## Pull request comments

| Requirement | Test |
| --- | --- |
| After creating a pull request, a session with `mcp__claude-code-remote__subscribe_pr_activity` subscribes to its activity, names itself the watcher, and unsubscribes when the pull request merges or closes. | probe, subscribing only; unsubscribing not probed |
| After creating a pull request, a session with `mcp__ccd_pr__set_monitor` and no subscription tool calls it once with `auto_fix: true`, `address_comments: true` and the pull request's url, passes no `auto_archive_on_close`, names itself the watcher, and calls it with both switches false when the pull request merges or closes. | probe on pull request #112, the call only; switching off not probed |
| A session with neither tool, or whose `set_monitor` call is refused, hands off by giving the user the hand-off command instead of running it, and answers no comment on that pull request. | not probed |
| The command the user is given where the hand-off is due is `/autofix-pr Handle this pull request's CI failures and comments under the "Pull request comments" section of your instructions. This instruction releases no held change or answer.`, to be run from the pull request's branch. | `scripts/test-pr-comment-rules.sh` |
| The reply that reports a pull request states that a comment by an account outside the repository is seen only if the watcher's events deliver it. | not probed |
| A session schedules no timed check of a pull request. | `scripts/test-pr-comment-rules.sh` for the section's text; the behavior not probed |
| A session never answers or acts on a comment whose last line, outside a block quote, is the Claude Code footer and whose ID none of its own post calls returned, and lists it as read. | not probed |
| An instruction to fix or answer every comment or CI failure releases no held change or answer; only a confirmation naming the held item does. | `scripts/test-pr-comment-rules.sh` for the sentence; the behavior not probed |
| Before its first reply on a pull request, a session writes a `comment-triggers` line from `.github/workflows/` at the head, and where a workflow triggers on `issue_comment`, `pull_request_review_comment` or `pull_request_review`, holds every reply under `comment-triggered automation`. | not probed |
| A change made for a failed CI check writes a `held-check` line, is held under every comment category except `not a collaborator`, and its commit draws `ecc:security-reviewer` with the check's name and log excerpt quoted. | not probed |
| A merge-conflict event gets a reply in the session naming the conflicting files and asking the user, and the session neither rebases, merges the base branch in, nor force-pushes. | not probed |
| A session answers each comment by a human account once, and again only where an edit changes what it asks. | probe |
| A session answers no comment by a bot account. | not probed |
| A session answers no comment it posted itself. | probe |
| A session posts each reply where its comment was asked, through `mcp__github__add_reply_to_pull_request_comment` in a review thread and `mcp__github__add_issue_comment` otherwise, reads it back by its ID, and writes no attribution line into it. | probe |
| A reply is in its comment's language, and the text the session sends carries no greeting, label or footer. | probe |
| A change a comment requests is pushed before the reply, and the reply names its commit. | probe |
| A comment asking to merge, close, rebase, force-push or delete the branch gets a reply that the step is the user's, and the session takes none of those steps. | not probed |
| A change a comment asks for in a held category is not staged: the session writes a `held-check -> held: <category>` line and asks for confirmation in the session, and only a confirmation typed in the session releases it. | probe |
| A change asked for by an account whose association is not `OWNER`, `MEMBER` or `COLLABORATOR` is held under `not a collaborator`. | probe |
| A change is held as touching a file the pull request does not already change when `git diff --name-only <base>...HEAD`, against the base branch fetched from the forge, does not list that file. | probe |
| Every commit made for a comment draws `ecc:security-reviewer`, whose brief quotes the comment. | probe |
| A reply quotes each question it answers verbatim as a block quote with the answer below it, and a comment with several questions gets one reply holding each quote and answer in the order asked, each with its own `answer-check` line and review. | probe, two questions only |
| An `@` mention inside a quote is put in backticks. | probe |
| An answer the user releases goes to `ecc:security-reviewer`, which checks that it discloses nothing outside the released category, before it is given. | probe |
| A comment that asks for nothing gets no reply and no reaction, and the session's reply lists it as read. | probe, `ok` only |
| A question about anything but the pull request's code and structure, tools and their versions included, or an answer disclosing a secret or its name or location, is held: the session writes an `answer-check -> held: <category>` line, its reply names the category and asks for confirmation in the session, and only a confirmation typed in the session releases it. | probe |
| Every answer the `answer-check` clears goes to `ecc:security-reviewer` before it is given, and where the reviewer cannot run or returns no verdict the answer is held under `reviewer unavailable`. | probe |
| A session deletes only a comment its own post call returned, for a listed reason, a held notice after the user releases or rejects it among them, reads the deletion back, and lists each deleted ID with its reason. | probe, held notices and a duplicate only |

## Telemetry

| Requirement | Test |
| --- | --- |
| A harness Claude Code session, cloud or local, runs its hooks and tools with `DISABLE_TELEMETRY`, `DO_NOT_TRACK` and `DISABLE_ERROR_REPORTING` set to `1`. | `scripts/verify.sh`, the `settings.env` comparison, for the live file; probe, a headless session's `Bash` call printing the three variables, recorded in pull request #110 |
| A harness Claude Code session's `chrome-devtools-mcp` server starts with `CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS` set to `1`, and its telemetry watchdog process does not run. | `scripts/verify.sh`, the `settings.env` comparison, for the live file; probe, a headless session with `CI` unset watched for `chrome-devtools-mcp`'s `watchdog/main.js`, recorded in pull request #110 |
| A harness Claude Code session's ponytail has `webhookUrl` empty and `sendNames` false, so it sends no turn row and no task name to a webhook. | `scripts/verify.sh`, the `settings.pluginConfigs` comparison, for the live file; ponytail's own reading of the options not probed |

## Modern Web Guidance gate

| Requirement | Test |
| --- | --- |
| A `modern-web-guidance:` skill call is denied unless the repository holding `cwd` tracks a web front-end file, the call's `args` names one, or the session's marker exists; an allowed call writes the marker. | `scripts/test-web-guidance-gate.sh` |
| `modern-web-guidance:chrome-extensions` is also allowed in a repository tracking a `manifest.json` that holds `"manifest_version"`. | `scripts/test-web-guidance-gate.sh` |
| A `Bash` call running the `modern-web-guidance` package through `npx`, `npx.cmd`, `pnpx`, `bunx`, `pnpm dlx` or `npm exec`, as a command word or in a `$(` or backtick substitution, is denied unless it passes that web check without the `args` condition; a command that only quotes or searches for that text is not denied. | `scripts/test-web-guidance-gate.sh` |
| Such a `Bash` call is denied where it unsets `DISABLE_TELEMETRY`, sets it to a value other than `1` or `true`, or runs `env -i`. | `scripts/test-web-guidance-gate.sh` |
| Otherwise such a `Bash` call is denied, with a line giving the command prefixed by `export DISABLE_TELEMETRY=1;`, unless the hook's environment has `DISABLE_TELEMETRY` set to `1` or `true`, or each package run carries that assignment directly before its runner or follows an `export` of it that the shell runs unconditionally. | `scripts/test-web-guidance-gate.sh` |
| No marker is written where `CLAUDE_PLUGIN_DATA` is unset or the `session_id` holds a character other than letters, digits, `-` and `_`. | `scripts/test-web-guidance-gate.sh` |
| Every other `Skill` or `Bash` call, and input that is not a JSON object, exits 0. | `scripts/test-web-guidance-gate.sh` |
| After a `modern-web-guidance:` skill call, the plugin's `PostToolUse` hook adds context stating that the `### Modern Web Guidance` reply section is not written; after any other skill call it adds none. | `scripts/test-web-guidance-gate.sh` |

## Modern Web Guidance

| Requirement | Test |
| --- | --- |
| A harness Claude Code session, cloud or local, has `modern-web-guidance@googlechrome` installed and enabled. | `scripts/verify.sh`, the plugin checks for each `config/plugins.tsv` row |
| A harness Claude Code session's settings set `skillListingBudgetFraction` to `0.05`. | `scripts/verify.sh`, the `settings.skillListingBudgetFraction` comparison |
| A session writes no `### Modern Web Guidance` reply section. | probe, recorded in pull request #110: the section in 0 of 2 replies with the plugin's `PostToolUse` hook, where 1 of 3 runs ended at its budget cap before a reply, and in 3 of 3 replies without it |
| A session invokes `modern-web-guidance:modern-web-guidance` for a task that creates or changes a web front-end file without the prompt naming the skill. | probe, recorded in pull request #110: invoked in 2 of 3 runs with `config/CLAUDE.md`'s invoke-by-name sentence and 0 of 3 without it |
