# Operator runbook

## Install and activate

Review the source, run install without --apply and inspect every destination/conflict.
The plan includes the ponytail plugin and humanizer skill from config/codex/addons.json.
Applying the plan runs their upstream install or update commands as well as installing the harness.
Node, npx and Codex plugin add/list and marketplace add/upgrade commands must be available.
Use --profile/--codex-home only for deliberate alternate roots.
--profile selects the Node/Skills home.
--codex-home selects the Codex home, including its plugin store.
Alternate profiles also redirect child app data, XDG config/cache/state and npm cache/config paths.
CODEX_HOME alone does not redirect the Skills CLI's global home.
If the default state parent is writable by another principal, choose --state under a new private directory beneath a safe profile ancestor; preserve existing directory permissions.
The coding agent exercises disposable profiles only. Do not copy auth into fixtures.

    py -3.12 -X utf8 -I scripts/codex-local.py install
    py -3.12 -X utf8 -I scripts/codex-local.py install --apply
    py -3.12 -X utf8 -I scripts/codex-local.py doctor

Review/trust exact hook definitions in Codex's supported interface.
The operator opens /hooks in Codex and trusts ponytail's two lifecycle hooks after installation.
The harness writes no ponytail mode setting.
Ponytail's upstream default is full.
Open a fresh local target chat and confirm policy, skill invocation, reviewers and callbacks separately.
Confirm ponytail's mode line, $ponytail:ponytail-review and the listed humanizer skill in that fresh chat.
Repeat in CLI; one surface does not establish another.
Doctor reports presence and cannot see hook trust or prove current upstream content.

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
These operations manage harness artifacts; Codex and the Skills CLI retain ownership of third-party files.
Unexpected concurrent edits stop recovery rather than being overwritten.
Keep old releases until acceptance completes.
Record source/release hashes, Codex version, actual suite counts/exits, discovery and hook events.
Use a new real target chat for a read-only plan and an authorized disposable repository for genuine review/commit.
Merge, release and real-profile activation remain user decisions.
