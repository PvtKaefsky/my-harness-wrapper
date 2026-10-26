# Native commands

Invoke scripts/codex-local.py with Python 3.12 in isolated UTF-8 mode.
--state selects an absolute owned state path before the subcommand.

| Command | Behavior |
| --- | --- |
| verify-source | Validate pack/anchor. |
| check-body FILE | Validate a prepared attribution-free forge body. |
| read --source ID | Verified source instruction reading during bootstrap. |
| read ID | Verified installed instruction reading. |
| install [--profile PATH] [--codex-home PATH] [--apply] | Plan/apply user installation. |
| doctor or session-check | Verify installation and report missing provider evidence. |
| hook | Handle bounded JSON stdin events. |
| review-requirements | Emit staged HEAD/tree and roles. |
| approve-identity --apply | Record approved effective Git identity. |
| commit ARGS | Guard identity, arguments, attribution and review. |
| recover, rollback or uninstall --apply | Apply owned-state operations. |

scripts/build-pack.py builds offline into a new --output directory from pinned vendored bytes.
--upstream-checkout is explicit maintenance, never runtime fetching.
Validate the emitted manifest hash before updating its anchor.
scripts/tests/test_local.py uses disposable profiles and real temporary Git repositories.
Synthetic event/receipt tests do not prove provider execution.
