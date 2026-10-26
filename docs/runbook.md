# Operator runbook

## Install and activate

Review the source, run install without --apply and inspect every destination/conflict.
Use --profile/--codex-home only for deliberate alternate roots.
The coding agent exercises disposable profiles only. Do not copy auth into fixtures.

    py -3.12 -X utf8 -I scripts/codex-local.py install
    py -3.12 -X utf8 -I scripts/codex-local.py install --apply
    py -3.12 -X utf8 -I scripts/codex-local.py doctor

Review/trust exact hook definitions in Codex's supported interface.
Open a fresh local target chat and confirm policy, skill invocation, reviewers and callbacks separately.
Repeat in CLI; one surface does not establish another.

## Guarded commit

Inspect the target's effective identity, then approve it:

    py -3.12 -X utf8 -I <wrapper>/scripts/codex-local.py approve-identity --apply

The command records identity without rewriting Git configuration.
Stage, obtain actual independent native reviews under native-review.md and retain completion evidence.
Set HARNESS_REVIEW_FILE to the truthful schema-version-2 receipt.
Use the native commit command with permitted Git message/signing arguments.
Missing approval or mutation-capable project Git hooks leave work uncommitted.

## Recovery and acceptance

Use recover --apply for an interrupted journal, rollback --apply for its predecessor, or uninstall --apply.
Unexpected concurrent edits stop recovery rather than being overwritten.
Keep old releases until acceptance completes.
Record source/release hashes, Codex version, actual suite counts/exits, discovery and hook events.
Use a new real target chat for a read-only plan and an authorized disposable repository for genuine review/commit.
Merge, release and real-profile activation remain user decisions.
