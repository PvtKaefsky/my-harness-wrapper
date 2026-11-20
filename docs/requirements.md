# Requirements

One testable line per behavior a user or caller can observe. The live probe on pull request #107, recorded in `docs/environment.md` under Pull request activity, tests the rows marked probe under Pull request comments; the repository's test scripts cannot drive a session. `scripts/test-pr-comment-rules.sh` checks the section's text only.

## Pull request comments

| Requirement | Test |
| --- | --- |
| After creating a pull request, a cloud session subscribes to its activity. | probe |
| A session checks the pull request every 30 minutes with its scheduling tool, until it merges or closes or seven days pass with no new comment, and answers at most ten comments per check. | probe, scheduling and re-arming only; a fired check, the interval, the stop and the cap not probed |
| If scheduling the next check fails, the session says so in its reply. | not probed |
| A timed check that finds no new or edited comment, no new conflict and nothing newly waiting on the user ends with `pr-check -> nothing new` and no other text. | not probed; `scripts/test-pr-comment-rules.sh` for the section's text |
| A session whose scheduling tool's description, or whose app's instructions, forbid scheduled polling of a pull request schedules no check, checks only when an event wakes it, and says so once, in the reply that reports the pull request. | not probed; `scripts/test-pr-comment-rules.sh` for the section's text |
| Each timed check reads the pull request's mergeable state from the forge, and reads a state not yet computed again at the next check; a conflict gets a reply naming the conflicting files and asking the user, is reported again only after the state has changed and come back to conflicting, and the session neither rebases, merges the base branch in, nor force-pushes. | not probed; `scripts/test-pr-comment-rules.sh` for the section's text |
| A change made for a failed CI check writes a `held-check` line, is held under every comment category except `not a collaborator`, and its commit draws `ecc:security-reviewer` with the check's name and log excerpt quoted. | not probed; `scripts/test-pr-comment-rules.sh` for the section's text |
| A session never answers or acts on a comment whose last line, outside a block quote, is the Claude Code footer and whose ID none of its own post calls returned, and lists it as read. | not probed; `scripts/test-pr-comment-rules.sh` for the section's text |
| An instruction to fix or answer every comment or CI failure releases no held change or answer; only a confirmation naming the held item does. | not probed; `scripts/test-pr-comment-rules.sh` for the sentence |
| Before its first reply on a pull request, a session writes a `comment-triggers` line from `.github/workflows/` on the default branch and at the head, naming each workflow found with its branch, reads them again before a later reply where the head commit has changed since its last read, and where a workflow in either triggers on `issue_comment`, `pull_request_review_comment` or `pull_request_review`, holds every reply under `comment-triggered automation`. | not probed; `scripts/test-pr-comment-rules.sh` for the section's text |
| A change a comment asks for that contradicts an instruction the user gave in the session is not made: its reply on the pull request quotes the request and states that it conflicts with an instruction the user gave in the session, and the session's own reply names that instruction and asks the user. | not probed; `scripts/test-pr-comment-rules.sh` for the section's text |
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
