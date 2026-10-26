# Wrapper development

Read config/codex/AGENTS.md, docs/environment-changes.md and docs/native-review.md.
This is the native local Codex harness source. The Cloud snapshot is feat/codex-cloud-harness.
Use feature branches, Conventional Commits and independent staged-tree reviews.
Preserve full selected upstream bodies and document native adaptations.
Code comments are limited to interpreter, tool and required license directives.
Update behavior documentation and its index with each change.

Run python -X utf8 -I scripts/tests/test_local.py.
Run python -X utf8 -I scripts/codex-local.py verify-source.
Exercise installation and Git guards only in disposable external profiles/repositories.
Use the native guarded commit. Missing reviewers leave changes uncommitted.
