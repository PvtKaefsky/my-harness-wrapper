# Requirements

One testable line per behavior a user or caller can observe. The live probe in `docs/environment.md`, Pull request activity, tests the pull request rows; the repository's test scripts cannot drive a session.

## Pull request comments

| Requirement | Test |
| --- | --- |
| After creating a pull request, a cloud session subscribes to its activity. | probe |
| A session answers each comment whose author is the pull request's author once, and again only where an edit changes what it asks. | probe |
| A session answers no comment by another account and no comment it posted itself. | not probed |
| A reply to an inline review comment sits in that comment's thread; any other reply is a conversation comment. | probe |
| A reply is in its comment's language and carries no greeting, label or footer. | probe |
| A change a comment requests is pushed before the reply, and the reply names its commit. | probe |
| A comment asking to merge, close, rebase, force-push or delete the branch gets a reply that the step is the user's, and the session takes none of those steps. | not probed |
