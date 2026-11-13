# Native commands

Invoke scripts/codex-local.py with Python 3.12 in isolated UTF-8 mode.
--state selects an absolute owned state path before the subcommand.

| Command | Behavior |
| --- | --- |
| verify-source | Validate pack/anchor. |
| check-body FILE | Validate a prepared attribution-free forge body. |
| read --source ID | Verified source instruction reading during bootstrap. |
| read ID | Verified installed instruction reading. |
| install [--profile PATH] [--codex-home PATH] [--apply] | Plan/apply harness installation and listed third-party install/update commands. |
| doctor or session-check | Verify harness artifacts, check listed third-party presence and report missing provider evidence. |
| hook | Handle bounded JSON stdin events. |
| review-requirements | Emit staged HEAD/tree and roles. |
| approve-identity --apply | Record approved effective Git identity. |
| commit ARGS | Guard identity, arguments, attribution and review. |
| recover, rollback or uninstall --apply | Apply owned-state operations. |

## Third-party delivery

config/codex/addons.json is the single inventory read by install, doctor and session-check.
The file contains each item's upstream source and install/update command arrays.
Installation includes it in the immutable release runtime and source hash.
The adapter version is 2.5.0.

| Item | Source | Delivery owner |
| --- | --- | --- |
| ponytail | https://github.com/DietrichGebert/ponytail | Codex plugin store. |
| humanizer | https://github.com/blader/humanizer | Skills CLI global skill directory. |

Without --apply, install lists both command paths and executes none.
With --apply, it selects install or update from presence and runs the commands even when the harness release is already current.
Installer input and output remain connected to the caller.
Executables are resolved only through explicit absolute PATH directories.
Empty and relative PATH entries are ignored.
External commands run from the selected profile directory.
Each completed command reports PASS ADDON_COMMAND or FAIL ADDON_COMMAND with exit=N.
A nonzero exit stops installation.
Each item's commands are followed by a presence check.
Missing presence fails installation.
Upstream versions are unpinned.
The upstream CLIs fetch and update their sources.
Ponytail and humanizer bodies are not vendored into the pack.

### Initial installation

The inventory runs these commands in order:

```powershell
codex plugin marketplace add DietrichGebert/ponytail
codex plugin add ponytail@ponytail
npx skills add blader/humanizer --global --agent codex
```

### Updates

An installed ponytail uses these commands:

```powershell
codex plugin marketplace upgrade ponytail
codex plugin add ponytail@ponytail
```

A present humanizer uses the targeted Skills CLI update:

```powershell
npx skills update humanizer --global
```

The Skills CLI needs its tracking metadata to update humanizer.
A present SKILL.md does not establish update eligibility.

### Presence

Doctor and session-check report PASS ADDON_PRESENT or FAIL ADDON_MISSING for each listed item.
A missing item or failed presence query makes the command fail.

| Item | Presence criterion |
| --- | --- |
| ponytail | codex plugin list --json contains pluginId ponytail@ponytail with installed set to true in its installed list. |
| humanizer | The selected profile's .agents/skills/humanizer/SKILL.md is a file with no symlink or junction in its path. |

An available or uninstalled plugin entry does not establish presence.
Ponytail presence does not distinguish enabled from disabled installations.
Presence establishes neither hook trust, current upstream content, invocation nor fresh-session discovery.
HOOK_TRUST=REQUIRES_PROVIDER_EVIDENCE remains separate from presence.

### Ownership

Third-party files are excluded from harness artifact registration.
Ownership and registration checks remain unchanged.
Uninstall and rollback manage only harness artifacts.

## Pack maintenance and tests

scripts/build-pack.py builds offline into a new --output directory from pinned vendored bytes.
Catalog items with source_kind set to authored read sources under config/codex/authored/.
The builder checks their source-inventory.json commit against AUTHORED_PIN and each source against its recorded SHA-256.
A changed commit fails with AUTHORED_COMMIT_CHANGED.
A changed source fails with AUTHORED_SOURCE_CHANGED.
Authored packages use the Harness instructions heading.
Upstream packages retain the Upstream instructions heading and their existing verification.
Both package kinds retain the same Codex adapter.
The generated authored.json records the authored commit and raw-source hashes.
manifest.json records authored_commit beside upstream_commit and uses authored_paths for authored package records.
Pack.verify checks the pinned commits, source kinds and exclusive source mappings.
Upstream-only schema 3 predecessor packs may omit authored metadata.
An explicit catalog description becomes the installed skill description unchanged.
Without one, the installer retains the title-based description.
--upstream-checkout refreshes only upstream sources during explicit maintenance.
It performs no runtime fetching.
Validate the emitted manifest hash before updating its anchor.
scripts/tests/test_local.py uses disposable profiles and real temporary Git repositories.
Synthetic event/receipt tests do not prove provider execution.
