# Requirements

One testable line per behavior a user or caller can observe. The live probe on pull request #107, recorded in `docs/environment.md` under Pull request activity, tests the rows marked probe under Pull request comments; the repository's test scripts cannot drive a session.

## Pull request comments

| Requirement | Test |
| --- | --- |
| After creating a pull request, a cloud session subscribes to its activity. | probe |
| A session checks the pull request every 30 minutes with its scheduling tool, until it merges or closes or seven days pass with no new comment, and answers at most ten comments per check. | probe, scheduling and re-arming only; a fired check, the interval, the stop and the cap not probed |
| If scheduling the next check fails, the session says so in its reply. | not probed |
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
| A harness Claude Code session, cloud or local, runs its hooks and tools with `DISABLE_TELEMETRY`, `DO_NOT_TRACK` and `DISABLE_ERROR_REPORTING` set to `1`. | `scripts/verify.sh`, the `settings.env` comparison, for the live file; for the process environment, a headless session's `Bash` call printing the three variables, not yet recorded |
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
