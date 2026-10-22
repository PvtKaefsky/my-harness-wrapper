# Repository-scoped native skill experiment

The provider-selected working repository for this experiment is `PvtKaefsky/my-harness-wrapper`.
A distinct attached target is used only for read-only acceptance.
A sibling wrapper is not a discovery root when the provider selects the target as its working repository.
Changing shell directories does not change the provider's active skill context.
This experiment does not establish user-global or cross-repository discovery.
[Issue #30](https://github.com/PvtKaefsky/my-harness-wrapper/issues/30) remains open pending evidence of its claimed cross-repository behavior.

## Source contract

The audited source of truth is `config/codex/native-skills/harness-python-patterns/`.
The regular checked-in discovery package is `.agents/skills/harness-python-patterns/` in this wrapper.
Both contain exactly `SKILL.md`, `LICENSE` and `upstream.json`.
Every discovery byte must match the audited source, including frontmatter, instruction body, MIT notice and provenance serialization.
The name is `harness-python-patterns`.
The instruction body matches the reviewed Cloud pack's `skills/python-patterns/SKILL.md`.
The provenance pins `forever94yu/everything-codex-code@d468c521f1a76e7b05d446d805f6ad2afa8ed066`, package `1.7.0-codex.0`.
No upstream files are fetched to create this package.
The explicit fallback pack, fork pin and reviewed body remain unchanged.
The other 36 adapted skills remain explicit reads.

```bash
python3 -I /workspace/my-harness-wrapper/scripts/check-native-source.py
```

This read-only validator checks the actual wrapper path and its audited source without reading HOME or emitting instruction contents.
It requires the wrapper origin, a canonical non-nested checkout with a conventional local `.git` directory, safe ancestors and user-owned non-executable regular files.
It rejects symlink components, extra files, changed bytes and any native or pack-anchor bytes that differ from committed HEAD and index entries.
Uncommitted preparation fails even when the working files match one another.
`NATIVE_SKILL_SOURCE_MISSING` names an absent required source.
`NATIVE_REPOSITORY_BYTES_MODIFIED` names a discovery file differing from the audited source.
`NATIVE_SKILL_SOURCE_UNTRACKED` names an absent, differently staged or non-regular index entry.
`NATIVE_SKILL_SOURCE_UNCOMMITTED` names bytes differing from HEAD.
`NATIVE_SKILL_PATH_UNSAFE`, `NATIVE_SKILL_SOURCE_UNSAFE` and `NATIVE_REPOSITORY_PACKAGE_INCOMPLETE` name unsafe paths, unsafe files and unexpected package contents.
The wrapper delivery fingerprint includes root `.agents` as well as the existing policy, pack, scripts and documentation scope.
Deleting or changing a discovery file invalidates previously delivered source verification.
Matching source hashes cannot distinguish a provider-indexed package from an ignored package.
Changes to trusted validation code and its anchors remain outside the checksum trust boundary.

## Managed runtime boundary

The operator reported that actual managed Environment preparation failed to create `$HOME/.agents` with `OSError(30): Read-only file system`.
The HOME opt-in cannot operate in that preparation runtime.
Do not rerun it as acceptance or substitute an Environment symlink, target-local skill, plugin, user/admin installation or configuration change.
Ordinary repository files require no writable HOME and no runtime package creation.
Default `env/setup-codex.sh` remains offline and leaves `HARNESS_ENABLE_NATIVE_SKILLS` unset or `0`.
The coding agent does not edit or publish the Environment.

## Operator preparation

Require a reviewed PR and actual completed successful hosted run, job and required steps for the reviewed revision or PR test merge.
Record the approved tree, PR head and tested merge SHA separately.
Select the reviewed wrapper branch for a test Environment only if the UI supports that selection.
If unmerged selection is unavailable, report the required merge/publication decision; do not assume an unmerged ref can be selected.
Keep the wrapper and a distinct target checkout attached.
Restore the default offline Install script from [Codex delivery](codex.md), without the HOME opt-in.
Take wrapper and target snapshots with `scripts/check-native-preservation.py` before and after preparation and retain both records.
The preparation snapshot boundary starts immediately before the Install script.
Publish or republish only by operator decision.
Launch a new managed Cloud task with the wrapper as the actual provider-selected working repository.
If that selection is unsupported, report `WRAPPER_WORKING_ROOT_UNAVAILABLE`.

## Fresh-task acceptance prompt

Replace `REVIEWED_WRAPPER_SHA` and `/absolute/target` with the recorded revision and distinct attached target.
Supply the publication/version and preparation snapshot records to the new task.
Do not run this acceptance in the implementing task.

```text
Work read-only in a new managed Cloud task whose actual provider-selected working repository is PvtKaefsky/my-harness-wrapper at REVIEWED_WRAPPER_SHA, with the distinct attached target at /absolute/target. Do not change files, Git metadata, configuration, hooks, trust, HOME, CODEX_HOME or provider settings. Do not install or repair anything.
Record the published Environment/version, actual wrapper HEAD and provider-selected repository evidence. A shell pwd or cd is insufficient. If wrapper working-root selection is unavailable, report WRAPPER_WORKING_ROOT_UNAVAILABLE and stop native acceptance.
Before manually opening any SKILL.md or calling the explicit reader, inspect actual native provider inventory. Require a repository-scope entry named harness-python-patterns rooted at /workspace/my-harness-wrapper/.agents/skills/harness-python-patterns. Record the advertised scope, path and provider evidence reference. If inventory is absent, unsupported or lacks that entry, report the exact inventory-stage failure and stop native acceptance. Do not read Markdown to manufacture discovery evidence.
Take read-only baseline snapshots of both checkouts using python3 -I /workspace/my-harness-wrapper/scripts/check-native-preservation.py /workspace/my-harness-wrapper and the same command with /absolute/target. Retain the operator's preparation snapshots separately. Run bash /workspace/my-harness-wrapper/scripts/session-check-codex.sh exactly once and python3 -I /workspace/my-harness-wrapper/scripts/check-native-source.py. These checks emit no full skill instruction contents and do not establish native discovery.
Invoke exactly once: $harness-python-patterns Explain EAFP versus LBYL in two sentences.
During this invocation run no commands and write no files. Record actual provider selection/dispatch evidence, its invocation ID or equivalent reference, completion and the two-sentence result. A generic answer without dispatch evidence fails invocation acceptance.
Then, only if the provider safely supports using the already attached target without changing the active wrapper skill context, analyze one Python path there read-only. Report the inspected path and finding, active provider context and evidence for whether the skill remains natively invocable. Do not repeat the smoke invocation. If unsupported or unobserved, report that limit; do not switch contexts silently.
Repeat both checkout snapshots and compare every digest with its baseline. Record FILES_VERIFIED, PROVIDER_DISCOVERED, PROVIDER_INVOKED, WRAPPER_UNCHANGED, TARGET_UNCHANGED and HOSTED_CI_GREEN separately with evidence references. On failure report the stage and preserve both checkouts. Manual Markdown reading, explicit pack reads, source hashes and file presence are not native dispatch.
Inventory a separately launched target-rooted task independently. Do not infer target-rooted or global discovery from wrapper-rooted success. Keep issue #30 open until its claimed cross-repository behavior has actual evidence.
```

| Gate | Required evidence |
| --- | --- |
| `FILES_VERIFIED` | Committed regular discovery files equal audited source; valid body, metadata, license and provenance. |
| `PROVIDER_DISCOVERED` | Fresh-task provider inventory identifies the wrapper-rooted repository-scope entry before manual reading. |
| `PROVIDER_INVOKED` | Actual native dispatch/completion evidence and the read-only two-sentence result. |
| `WRAPPER_UNCHANGED` / `TARGET_UNCHANGED` | Matching pre/post file and Git metadata snapshots of both checkouts. |
| `HOSTED_CI_GREEN` | Completed successful run, job and required executed steps at the reviewed revision/test merge. |

The preservation checker hashes regular bytes, symlink text, directory entries and ownership/mode/inode/mtime metadata, including `.git`.
It executes no target Git commands and follows no symlinks.
Access times are excluded because inspection reads files.
External Git directories and special files fail explicitly.

## Retained HOME experiment

`scripts/provision-native-skills.py` remains disabled by default and inapplicable to this managed preparation runtime.
Its `source` action verifies only the audited `config/codex` package; use `check-native-source.py` for repository discovery bytes.
Its `inspect` action additionally checks the historical user-scope pointer without writes.
Its `install` and `remove` actions require explicit operator-approved preparation with `HARNESS_ENABLE_NATIVE_SKILLS=1` in a separately supported runtime.
That historical pointer is `$HOME/.agents/skills/harness-python-patterns` to the verified wrapper's `config/codex/native-skills/harness-python-patterns` directory.
The provisioner requires canonical account HOME, matching user IDs, safe owned parents outside repositories/managed configuration, descriptor-relative no-follow opens and a ten-second lock bound.
It preserves collisions and unrelated skills, creates missing discovery parents privately, and never replaces foreign entries.
Removal unlinks only an owned absolute pointer with the exact verified target.
A matching pointer does not authenticate its creator or establish publication, indexing or invocation.
No HOME installation or removal command is part of this experiment's preparation or acceptance.

## Offline regression boundaries

`python3 -I scripts/tests/test_native_skills.py` tests the exact repository path in disposable clean committed wrapper fixtures.
It covers missing, mutated, stale, untracked, staged, executable and symlinked files, exact license/provenance bytes and fingerprint deletion/mutation detection.
Deletion and single instruction-byte mutation must fail with named diagnostics; restoration must pass.
Full default setup and the explicit fallback reader from a separate synthetic repository preserve strict wrapper, target and scratch-HOME snapshots.
Bootstrap disables optional Git locks when reading status so it does not refresh source index metadata.
The historical provisioner tests use only isolated scratch HOME with account lookup injected; production has no home override.
No test installs into the real user's HOME or changes an attached target.
Local and hosted source checks prove delivery bytes, not provider inventory or dispatch.

References: [skill discovery locations](https://learn.chatgpt.com/docs/build-skills), [Environment preparation and publication](https://learn.chatgpt.com/docs/environments/cloud-environments).
