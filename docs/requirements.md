# Requirements

One testable line per behavior a user or caller can observe. The live probe on pull request #107, recorded in `docs/environment.md` under Pull request activity, tests the rows marked probe; the repository's test scripts cannot drive a session.

## Pull request comments

| Requirement | Test |
| --- | --- |
| After creating a pull request, a cloud session subscribes to its activity. | probe |
| A session answers each comment whose author is the pull request's author once, and again only where an edit changes what it asks. | probe, unedited comments only |
| A session answers no comment by another account and no comment it posted itself. | probe, own comments only |
| A reply to an inline review comment sits in that comment's thread; any other reply is a conversation comment. | probe, conversation comments only |
| A reply is in its comment's language, and the text the session sends carries no greeting, label or footer. | probe |
| A change a comment requests is pushed before the reply, and the reply names its commit. | probe |
| A comment asking to merge, close, rebase, force-push or delete the branch gets a reply that the step is the user's, and the session takes none of those steps. | not probed |
| After `mcp__github__add_issue_comment`, `mcp__github__update_issue_comment` or `mcp__github__add_reply_to_pull_request_comment` returns, the attribution guard tells the session to read the comment back and, where its stored body carries an attribution line, not to retry and to give the text to the user. | `scripts/test-attribution-guard.sh` |
