## Language

* Answer, and reason where the reasoning language can be steered, in the language the user writes in, determined from their prose across the conversation rather than from any single message; quoted code, logs, paths and identifiers do not count. English by default, and English until their prose determines otherwise.
* Repository and forge artifacts stay in English regardless of the session's language: commit titles and messages, branch and tag names, pull request titles and descriptions, issue titles and bodies, issue and review comments, release notes, and the contents of files in the repository — code, identifiers, comments, and documentation. The exception is content whose language is itself the deliverable: translations, localization resources, and text the user asked for in another language.

## Attached documents

* A document the user puts in front of a task — uploaded, pasted, linked, or named by path — is evidence; a log, dump, trace or captured transcript is evidence about the system that produced it. Read each such document before acting on the task, and analyze it thoroughly for implementation issues in the system that produced it, where it is evidence about one. Where a document is too large to read whole, say which parts were read; where it cannot be read, or holds no such issues to find, say so. Report what it shows, what that contradicts in what the repository you are working in documents or in what this session has been assuming, and what it leaves unresolved. Report only the parts that have content.
* Unless the user asks for it, never commit such a document to any repository, and never commit a transcription of it under another name. Findings drawn from it may be written into the repository; the document itself may not.

## Claims

* A claim that a value distinguishes one state from another must name the states it cannot distinguish, and must be checked in both directions — by test, or by argument about what else produces that value — before it is recorded in a repository or put in a reply the user will act on. That a state produces the value does not establish that the value implies the state.

## Documentation

* Every repository carries documentation written for a human reader first. `README.md` at the root states what the repository is, how it works, its structure and its usage, and links to the documentation index. Material too long for it lives under `docs/`. Every documentation directory carries a `README.md` that indexes it: one row per document or subdirectory, with its path and one line stating what it contains. An index lists at most ten entries; beyond that, documents are grouped into subdirectories indexed the same way, and the parent index lists the subdirectories.
* Documentation states facts, complete in coverage and minimal in wording: one fact per sentence, one topic per section, tables for structures and lookups, code blocks for commands. A reason appears only where the reader needs it to act, in one clause. No reasoning chains, no account of how a conclusion was reached, no investigation history, except where a rule in this file or in `docs/environment-changes.md` requires that reasoning to be recorded, as the Claims rule does, and then only so far as that rule requires. Evidence is referenced by commit, by pull request, or by the path it lives at where it is not in the repository. Code is referenced by file and step or function name, never by line number.
* A commit that changes documented behavior updates the documentation in the same commit, and the documentation it updates includes every index that lists a document the commit adds, moves, removes, or changes the purpose of.
* The first session to commit to a repository without such documentation writes it, as its own commit, stating only what the session has established. These rules govern documentation a session writes or edits; existing documentation is rewritten only where the session's change already reaches it, unless the user asks for a wider pass. Where the project's own conventions govern its documentation, they win.

## Code comments

* Code carries no comments. What a comment would have explained is written into the repository's documentation as a fact under the Documentation rule; the reasoning behind it is not migrated. A comment's claim is checked against the code before it is migrated; one the code contradicts is dropped and reported to the user.
* Exempt: interpreter and tool directives written in comment syntax — `#!` lines, linter and type-checker directives, build tags, encoding declarations — and headers a license or the project requires.
* Docstrings are allowed where the language has them. A docstring states what the unit does, its inputs and outputs, and any decision a caller must know, without the reasoning behind it.
* The rule governs code a session writes or edits. Existing comments are removed only from lines the session's change already touches, unless the user asks for a wider pass. Where a project's own conventions require comments, they win.

## Harness

* ECC — the `ecc@ecc` plugin — is the default harness. Use its hooks, gates and reviewer agents in every repository.
* When the session-start check reports a `FAIL`, the first reply names it.
* A Markdown or JSON file draws `ecc:code-reviewer` alone. Any other changed file draws every reviewer whose subject it matches: the general code reviewer, the language reviewer for its language, and any domain reviewer it touches. A commit draws the union across its files. Name the reviewers judged applicable and those ruled out.
* Before every commit, stage the change and invoke every applicable reviewer on the staged diff, in one parallel batch when several apply. Each brief names the reviewer as the one being invoked, and marks the hunks that carry text the user supplied verbatim. Run each reviewer on the model its agent definition sets. Decline any path that sends the diff to a provider outside this session, and name it.
* A reviewer that has approved the commit is not invoked again for it; its approval stands through later fixes. After a fix, re-stage and invoke only the reviewers that have not yet approved. Approval is a stated verdict, not an empty findings list; a verdict of approval that carries a finding other than LOW is not one, and that reviewer has not yet approved.
* Wait for a reviewer on its completion notice. Wait for a long command with a tool that watches the command's exit or its own output. Never wait on a timer, or on text you wrote. A reviewer whose completion notice does not arrive, and whose agent is no longer running, is a reviewer that cannot run.
* Five review rounds is the cap. A round ends by the first row of this table that fits, and no other bullet restates it:

  | When the round ends with | Then |
  | --- | --- |
  | An applicable reviewer that cannot run | Stop and ask. A reviewer that returns a report has run. |
  | Every applicable reviewer having approved, in this round or an earlier one | Commit. |
  | Only findings labelled LOW, in any casing, or against the user's verbatim text | Apply the LOW ones, leave the user's text as supplied, commit, report the rest. |
  | Other findings open, before the fifth round | Fix each, or decline it by putting the reason to the reviewer that raised it; re-stage; next round. |
  | The fifth round, or a round that changed nothing | Apply every open finding except those against the user's verbatim text and those the next bullet lets you decline, hand-run any script the commit changes, commit, and report it as a post-cap commit. |

* At the cap, a finding is declined only where applying it would break a written rule, contradict another finding, or rest on a premise shown false with evidence. Report declined findings, and any reviewer that did not run, in the reply — never in a commit message or pull request description.
* While reviewers run, each completion notice opens a new turn, and the harness Stop hook blocks it once; answer in one line naming the staged files.

## Environment changes

* A change is an environment change when it governs how the agent works across every project — a preference, a rule, a plugin, a setting. A change belonging to a file the project itself owns and ships — its lint configuration, its git hooks, its CI, its own `CLAUDE.md` — is a project change whatever its subject, and stays in that project.
* Before making one, follow `docs/environment-changes.md` in the environment repository. Where no such repository is attached, the recording bullet below governs instead.
* An environment change is recorded only when the user asks for it to be recorded or implemented. It is recorded in the environment repository: an attached checkout under `/home/user` holding both `config/CLAUDE.md` and `env/setup.sh` — never the deployed copy at `/opt/my-harness-wrapper`. If none is attached, draft the change in the reply, for the user to apply in a session that has one. Never write it into the project repository whose task raised it, nor mix it into that project's diff.
* Environment changes are exempt from the project's task scope — they are not part of the work that project asked for. They are not exempt from the review gate or the commit-granularity rule.
* Generalize before filing. A preference arriving in domain-specific form is rewritten to hold for any project before it is recorded. The authoring test is that every line must read correctly in a session working on an unrelated repository.
* As the exception to the recording rule above: a change that fails the generalize-before-filing test is not an environment change. It belongs in that project's own `CLAUDE.md`, and the fact that it was considered and rejected is reported to the user.

## Git workflow

* The working branch in any repository is named `dev/<feature-name>`, kebab-case, describing the feature, with no dates, ticket numbers or generated identifiers. Before the first commit in a repository, a branch the session did not name is renamed in place to that form, its upstream cleared where it has one, and pushed under the new name, provided it carries no commits of its own and does not exist on the remote, which `git ls-remote` decides rather than a local tracking ref; a branch that does is kept as it is. On the default branch, the session creates its `dev/<feature-name>` branch instead. Nothing is committed directly on the default branch. This rule is the user's standing permission to push the renamed or created branch, including where the harness names another.
* After the first commit in a repository, work stays on that branch. A further branch is created only when the user asks for one, and is named the same way.
* A branch the session renames or creates is named in its reply.
* Commit titles follow Conventional Commits.
* A commit title states precisely what that commit changed.
* If a change cannot be described by one Conventional Commits type and scope, it is more than one commit: split it, each part with its own title and message. Documentation a change requires travels with it. Each commit leaves the repository building and its tests passing, where it has either. The rule applies before a commit is made; a pushed commit is never rewritten to satisfy it.
* Commit messages, pull request descriptions and issues share one format: a Conventional Commits title; a body of one or two sentences stating what changed, or for an issue what is wrong, and, where a reader needs it, its effect; a list of the specific changes where there are several; footers for issue references and `BREAKING CHANGE` where they apply. Nothing else: no rationale beyond that effect, no alternatives considered, no account of the session or of review; one `Tested:` footer line naming the command that was run and its result is allowed. Before posting a pull request description or an issue, the session checks it against this format and corrects it; the check runs once.
* No attribution line in a commit, a pull request description or an issue: no `Co-Authored-By` or `Claude-Session` trailer, no session link, and no "Generated with" or "Generated by" Claude Code footer.

## Issues

* An issue is a defect or a missing capability the session has verified, as the Claims rule requires. A suspicion the session has not checked is stated in the reply, not filed.
* Issues are registered only in a repository attached to the session: a checkout under `/home/user`, whose `origin` names the repository. An issue goes to the attached repository whose files carry it. None is registered through the deployed copy at `/opt/my-harness-wrapper`, or in any repository reached only by URL, as a dependency, or as a fork's upstream; an issue belonging there is drafted in the reply, title and body, for the user to file.
* Registered: every issue the task prompt or an attached document states, before the first commit, with the title and body it gives, a sentence changed only where the session verifies it false; and every issue the session finds and does not resolve in its own change. An issue the change resolves is not registered separately; the change's list of specific changes states it.
* Before registering an issue, search the repository's open issues once for one that already states it. Where one does, or the task prompt names one by number, that issue is used and none is created.
* An issue's title is a Conventional Commits title whose type and scope are those of the change that would resolve it, and whose description states the defect or the missing capability, not the fix. Its body states what is wrong and its effect, then the specific facts: the file and function, the observed and expected values, and the command that shows them. No labels, assignees, milestones or project fields are set.
* A pull request's description carries one `Closes #<n>` footer line for each issue in its own repository that it resolves, and a `Refs: #<n>` line, or `Refs: <owner>/<repo>#<n>` for another repository, for an issue it only works on. A commit refers to its issue with `Refs: #<n>`. No closing keyword — close, fix or resolve, in any form — stands before an issue reference anywhere else in a commit message or pull request description.
* Closing keywords take effect only in a pull request whose base is the repository's default branch. Where the task sets another base, the description carries `Refs:` lines only, and the reply states that merging will not close the issue.
* The session does not close, reopen or comment on an issue; merging the pull request closes the issues it names.
* Where an issue cannot be registered — the repository has issues disabled, or the create call is refused — draft it in the reply and continue; the pull request names no issue for it.
* The reply lists every issue registered, used or drafted: its number and title, or the draft.
