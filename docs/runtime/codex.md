# Local delivery contract

State defaults to LOCALAPPDATA/my-harness-wrapper/codex.
The effective CODEX_HOME supplies AGENTS.md, hooks.json and agents/.
The interactive user's .agents/skills receives namespaced regular-file packages.
No target installation, symlink privilege or administrator setup is required.

Dry-run writes no profile/state files. Apply rejects unowned collisions and modified owned files.
Installation checks pack hashes, ownership, ordinary files and reparse-point boundaries.
A complete private release and active.json are published under a bounded lock.
Releases retain runtime hashes, artifact snapshots and their predecessor.
Source updates never silently replace installed runtime.

Interrupted writes retain a journal; recover restores only expected owned writes.
Rollback restores a predecessor or uninstalls the first release.
Rollback verifies predecessor runtime bytes and permissions before restoring its registrations.
Catalog retirement records are transaction-only and never remain active package ownership.
Recovery authenticates both sides of an interrupted transition.
Uninstall preserves unrelated policy bytes and hook entries.
Merging JSON can change formatting; unchanged files restore their original bytes.
A nonempty global AGENTS.override.md is a shadowing conflict.
config.toml, auth, models, sandbox/approval settings and trust databases are never edited.

| Result | Established | Still unproven |
| --- | --- | --- |
| PACK_SOURCE_VERIFIED | Anchored pack bytes match. | Remote freshness or agent use. |
| SOURCE_AND_DELIVERY=VERIFIED | Installed runtime/registrations match. | Native discovery/invocation. |
| WORKFLOW_INSTRUCTION_READ | Verified instructions were emitted. | Native dispatch. |
| HOOK_TRUST=REQUIRES_PROVIDER_EVIDENCE | Trust was not inferred from files. | Automatic callback execution. |
| NATIVE_DISCOVERY=REQUIRES_FRESH_PROVIDER_SESSION | Native packages exist. | Actual provider loading. |
| GUARDED_COMMIT_PASSED | Explicit guard and Git succeeded. | Receipt authenticity or hosted CI. |

Retain actual provider evidence separately.
Local execution still uses the signed-in Codex service; it is not offline inference.
