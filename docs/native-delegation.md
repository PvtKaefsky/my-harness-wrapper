# Native task delegation

This procedure uses available native collaboration agents and verified briefs.
It registers no agents, plugins, hooks or provider integrations.
Role text does not create an agent.
The coordinator keeps decomposition, briefs, integration, review, commits and the reply.
Executors do the delegated subtasks.
Delegation records are reporting evidence and are not checked by `codex-local.py commit`.
The staged review protocol remains [native-review.md](native-review.md).

## Analyze and assign

Analyze each task once, before its first change or finding.
A task splits where either condition holds:

- It has two or more parts, each with its own files or question and its own acceptance check.
- Its parts draw different executors under the routing tables.

A task that stays whole is done by the coordinator.
Record one line for it:

```text
decomposition -> whole: <reason>
```

A task that splits has at most five subtasks.
Where more are needed, stop and ask the user.
Each coding subtask owns a named set of files.
Each analysis subtask owns one question.
No file or question belongs to two subtasks.
An executor may read anything and may edit only its owned files or answer only its owned question.
Each subtask has one acceptance check: a command with its expected result, or a statement evidence can settle.

Record each subtask's dependencies.
A coding subtask depends on another where its goal documents, tests, configures or calls what the other changes.
An analysis subtask depends on another where its question takes the other's findings as input.
Mutually dependent subtasks form one subtask.

## Routing and inventory

Use the coding table where the task permits repository changes.
Use the analysis table where it does not.
A subtask draws the first matching row.
A row whose required independent executor cannot run is passed over for the next matching row.
Before dispatch, inventory the actual native collaboration tools and independent agent availability.
Record the selected briefs, applicable agents, unavailable agents and the reasons for passing over a row.
Use the provider-defined or inherited models without a coordinator override.

| Coding subtask | Verified brief |
| --- | --- |
| Go build, compile or type failure with its dedicated resolver | `role/go-build-resolver` |
| Any other build or type failure | `role/build-error-resolver` |
| Tests written first | `role/tdd-guide` |
| End-to-end tests | `role/e2e-runner` |
| Documentation only | `role/doc-updater` |
| Removing dead code | `role/refactor-cleaner` |
| Behavior-preserving simplification | Harness executor brief below |
| Anything else | Harness executor brief below |

| Analysis subtask | Verified brief |
| --- | --- |
| A sweep across files or an execution-path trace | Harness executor brief below |
| Independent review of a diff | The matching shipped general, language and domain `role/*` briefs under `native-review.md` |
| Design options or a plan | `role/architect` for design options; `role/planner` for a plan |
| Research, a reproduction, a scratch probe or anything else | Harness executor brief below |

Where an analysis row names several briefs, select each one whose subject the question matches.
Restate the task's analysis-only limits in every analysis packet.
Analysis-only executors change no repository files.
The selected pack ships no dedicated code-simplifier or explorer brief.

Read selected pack briefs through the verified `codex-local.py read role/ID` reader.
Retain its emitted IDs, SHA-256 hashes and full instruction bodies.
The harness executor brief is shipped in this document, outside the vendored pack.
Read it from the verified installed release.
Its section bytes start at the UTF-8 `## Harness executor brief` heading and continue through the document's final byte, including its final newline.
Hash those exact bytes with SHA-256 and include their complete text in the dispatch packet.
Also retain the whole installed document's SHA-256.
An unreadable or unverified brief makes its executor unavailable; it does not authorize inventing a role or using unverified source text.

## Dispatch packet

Give the selected independent agent the complete packet through the provider's actual dispatch tool:

```text
Repository: absolute repository path
Base HEAD: exact source commit, or empty for an unborn repository
Subtask and attempt: named subtask; 1 or 2
Goal: one concrete implementation goal or analysis question
Owned files or question: exact exclusive ownership
Acceptance check: command and expected result, or evidence-settled statement
Task constraints: applicable project/user rules; user verbatim hunks explicitly marked, or NONE
Dependencies: each integrated prerequisite's owned-file diff or verified findings; NONE where absent
What not to touch: paths, settings, state and external actions outside this subtask
Verified brief: exact pack ID or installed document section, SHA-256 and full text
Installed document hash: whole-document SHA-256 when the harness brief is selected
Limits: commit, push and post nothing; register no issue; do not decompose or delegate; invoke no reviewer
Execution: read anything; edit only owned files or answer only the owned question
Deadline: thirty minutes from actual dispatch; provider completion waits at most sixty seconds each
Report: changed files or findings; evidence and actual acceptance output; open questions; not done
```

A dependent subtask is briefed only after each prerequisite has been integrated.
Pass the integrated diff or checked findings, not an unverified executor summary.
Where ownership or the acceptance check is missing, the executor changes nothing and reports the incomplete brief.
Do not use worktree isolation.

## Capture and run

Before the first executor runs, record `HEAD`, the branch, `git for-each-ref`, `git stash list`, `git diff --cached` and `git status --porcelain --untracked-files=all`.
Copy every listed existing file outside the repository as the snapshot.
Record listed deletions without a copy.
Retake the record before a second brief and before a dependent subtask runs.

| Subtasks | Execution |
| --- | --- |
| Disjoint files or separate questions, no shared build or test step, and no dependency between them | One parallel batch |
| All others | In dependency order |

Record the actual agent identity and provider dispatch reference.
Wait for the actual terminal completion notice or provider completion tool.
Each completion wait is at most sixty seconds and remains within the attempt's thirty-minute deadline.
An agent ID, timer, quiet file or empty findings list does not establish completion.
Retain the actual final response and completion reference.
Never invent a completion reference.
On a completion notice, report which subtasks remain running.

## Integrate

Integrate after each parallel batch and each separately run subtask.
For coding subtasks, perform these steps in order:

1. Compare `HEAD`, branch, refs and stash with the captured values.
   A difference also can come from another writer; it establishes a changed boundary, not who changed it.
   Stop and ask where any differs; do not repair refs or stashes.
2. Read each report and the complete diff of its owned files.
3. Compare the cached diff with the captured one.
   Where it changed and the original was empty, unstage every staged path.
   Where it changed and the original was nonempty, stop and ask.
4. Compare status and each snapshot file with its copy.
   Restore executor edits outside ownership to the captured state and record every restored path.
   Use the snapshot copy for a preexisting changed file and preserve a captured deletion as deleted.
   Restore other tracked files from `HEAD` and remove newly created unowned files.
   Verify resolved restoration targets stay inside the intended repository.
   Preserve unrelated work and stop and ask where another writer makes restoration ambiguous.
5. Where two executors' edits overlap in a file and cannot be separated, fail both subtasks.
   Restore that file from its snapshot or `HEAD` before either second brief.
6. Run each acceptance check yourself after restoring the boundary.

`git status` does not list ignored files, so this comparison does not observe edits to them.
An analysis subtask is integrated only after the coordinator checks each relied-on finding against its evidence.
An unanswered report question is answered by the coordinator or put to the user.
It is never dropped.

After every subtask is integrated, the coordinator alone stages the final bytes and obtains native staged-tree review under `native-review.md`.
The normal commit-granularity rule decides the commits, not subtask boundaries.
The coordinator alone uses the guarded commit command, pushes and posts within the task's authorization.
Implementation completion is not independent review approval.

## Failure and bounds

An attempt fails where its executor is unavailable, returns an error or empty report, misses its deadline, lacks actual terminal completion evidence, fails its acceptance check, edits outside ownership, leaves part of its goal undone, or changes nothing where a change was required.
Record unavailable agents from the actual inventory or the provider's stated failure.
Where no dispatch occurred, record no agent, dispatch or completion identifier.

Brief a failed subtask again once and name the failure.
Where its executor could not run, select the next matching available row for the second attempt.
A failed member of a parallel batch retries alone after the batch finishes.
A dependent subtask is not briefed before its prerequisite passes integration.
Do not launch a replacement while the original attempt is still running.
At the deadline, use actual provider interruption and confirm a terminal state before any retry.
Where terminal state cannot be confirmed, leave the subtask `BLOCKED`.

After the second failed attempt, the subtask is `BLOCKED`.
The coordinator does not do that subtask itself and commits nothing.
Subtasks depending on it are not dispatched.
Finish the remaining independent subtasks and checks, then report and ask the user.
A user decision does not fabricate missing completion or review evidence.

| Bound | Value |
| --- | --- |
| Decomposition analyses per task | One |
| Subtasks per task | At most five |
| Briefs and attempts per subtask | At most two |
| Levels of delegation | One |
| Executor attempt deadline | Thirty minutes from dispatch |
| Provider completion wait | At most sixty seconds |

Where a task cannot finish within these bounds, report and ask instead of continuing the loop.

## Report

The reply carries the decomposition table and actual provider references.
Commit messages and pull request descriptions do not carry it.

| Column | Contents |
| --- | --- |
| Subtask | Its goal |
| Owned files or question | Exact briefed ownership |
| Executor | Selected brief and actual agent; unavailable alternatives and reasons |
| Batch and dependencies | Run order, parallel batch if any, integrated prerequisites |
| Attempts | One or two; first failure where retried |
| Result | `passed` or `BLOCKED`; restored paths and answered or pending questions |
| Provider evidence | Actual dispatch and completion references, or the actual unavailable inventory/failure |
| Integration | Coordinator-run acceptance command and result, or checked evidence |

Retain full dispatch packets and actual terminal responses separately.
Brief hashes establish which instruction bytes were supplied, not whether an agent executed them.
Local records cannot authenticate provider identity, participation or transcript provenance.
Fresh-session discovery and automatic hook invocation remain separate evidence.

## Harness executor brief

You execute one delegated subtask under the coordinator's complete brief.
You do not run the coordinator's decomposition procedure.

### Read the brief

The brief states your goal, owned files or question, acceptance check, task constraints, integrated dependency evidence, exclusions and report shape.
Where ownership or the acceptance check is missing, change nothing and report that as an open question.
Follow the task's constraints and preserve text explicitly marked as the user's verbatim hunks.

### Execute

1. Read whatever is needed; reading is not limited to owned files.
2. Edit only the named owned files and create a file only where the brief names it.
   For an analysis-only subtask, change no repository files and answer only the owned question.
3. Work against the integrated prerequisite diffs or verified findings supplied in the brief.
4. Run the acceptance check and report its actual command and output.
5. Report an ownership conflict or missing prerequisite instead of extending your scope.

### Restrictions

- Commit, push and post nothing.
- Register no issue.
- Do not decompose the subtask or delegate any part of it.
- Invoke no reviewer.
- Do not edit outside the owned files or change Git refs, index, stashes or settings.
- Do not invent provider, completion, acceptance or review evidence.

Where a tool or hook blocks a call and asks for facts, supply those facts and retry the same call once.
Where it is blocked again, stop retrying and report the block under what was not done.
Never bypass a guard or change trust to make a call run.

### Report

Use the brief's report shape.
Where it supplies none, report:

- Files changed or findings, with the change or answer for each.
- Evidence for each, naming its file, commit or actual command and output.
  Always include the acceptance command and result.
- Open questions the brief left undecided.
- Each part not done and why, including blocked calls and required out-of-scope work.

Do not turn your implementation report into an independent-review approval.
