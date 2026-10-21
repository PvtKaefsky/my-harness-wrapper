# Wrapper development

Read `config/codex/AGENTS.md` for the shared working rules and
`docs/environment-changes.md` before changing a shared policy.
Read `docs/codex.md` for the Codex delivery contract.

This checkout is the wrapper source repository.
This repository supports managed Codex Cloud only.
Use `feat/` branches for features and Conventional Commits for commit titles.
Code has no comments except interpreter, tool, and required license directives.
Update behavior documentation and the documentation index with each change.

Run `bash scripts/test-codex.sh`,
`bash scripts/test-codex-git-context.sh`, and
`bash scripts/test-codex-attribution.sh` after changing the Codex adapter.
Run `bash scripts/test-codex-identity.sh` after changing the identity guard.
Run `bash env/setup-codex.sh` to exercise its complete setup workflow.
Use `HARNESS_STATE_DIR` with an absolute scratch path when testing delivery.
Run `bash scripts/test-cloud-pack.sh` for pack and real-path acceptance checks.

Stage changes and obtain the independent reviews described in the shared rules
before committing.
Make commits with `bash scripts/commit-codex.sh` and the usual commit arguments.
When a required reviewer cannot run, finish implementation and tests, leave the
changes uncommitted, and report the unavailable reviewer.
