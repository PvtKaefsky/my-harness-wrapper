# Requirements

One testable line per behavior a user or caller can observe. The live probe on pull request #107, recorded in `docs/environment.md` under Pull request activity, tests the rows marked probe; the repository's test scripts cannot drive a session.

## Pull request comments

| Requirement | Test |
| --- | --- |
| After creating a pull request, a cloud session subscribes to its activity. | probe |
| A session answers each comment whose author is the pull request's author once, and again only where an edit changes what it asks. | probe, unedited comments only |
| A session answers no comment by another account and no comment it posted itself. | probe, own comments only |
| A session posts each reply where its comment was asked, through `mcp__github__add_reply_to_pull_request_comment` in a review thread and `mcp__github__add_issue_comment` otherwise, reads it back by its ID, and writes no attribution line into it. | probe |
| A reply is in its comment's language, and the text the session sends carries no greeting, label or footer. | probe |
| A change a comment requests is pushed before the reply, and the reply names its commit. | probe |
| A comment asking to merge, close, rebase, force-push or delete the branch gets a reply that the step is the user's, and the session takes none of those steps. | not probed |
| A change a comment asks for in a held category is not staged: the session writes a `held-check -> held: <category>` line and asks for confirmation in the session, and only a confirmation typed in the session releases it. | probe, held path only |
| Every commit made for a comment draws `ecc:security-reviewer`, whose brief quotes the comment. | not probed |
| A reply quotes each question it answers verbatim as a block quote with the answer below it, and a comment with several questions gets one reply holding each quote and answer in the order asked, each with its own `answer-check` line and review. | probe, two questions only |
| An `@` mention inside a quote is put in backticks. | probe |
| An answer the user releases goes to `ecc:security-reviewer`, which checks that it discloses nothing outside the released category, before it is given. | probe |
| A comment that asks for nothing gets no reply and no reaction, and the session's reply lists it as read. | probe, `ok` only |
| A question about anything but the pull request's code and structure, tools and their versions included, or an answer disclosing a secret or its name or location, is held: the session writes an `answer-check -> held: <category>` line, its reply names the category and asks for confirmation in the session, and only a confirmation typed in the session releases it. | probe |
| Every answer the `answer-check` clears goes to `ecc:security-reviewer` before it is given, and where the reviewer cannot run the answer is held. | probe, reviewer available only |
| A session deletes only a comment its own post call returned, for a listed reason, a held notice after the user releases or rejects it among them, reads the deletion back, and lists each deleted ID with its reason. | probe, released held notice only |
