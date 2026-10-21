# Opt-in native skill delivery

The wrapper versions one native entry point: `harness-python-patterns`.
Its source directory is `config/codex/native-skills/harness-python-patterns/`.
The directory contains `SKILL.md`, `LICENSE` and `upstream.json` only.
The skill adds valid namespaced frontmatter to the exact reviewed `skills/python-patterns/SKILL.md` body from the Cloud pack.
Its MIT notice and source records preserve upstream `forever94yu/everything-codex-code@d468c521f1a76e7b05d446d805f6ad2afa8ed066`, package `1.7.0-codex.0`.
The pinned Cloud pack and its checksum remain unchanged.
The other 36 adapted skills have no native entry point in this delivery.

## Operator boundary

Normal setup writes no HOME files.
Only approved Environment preparation may opt in to the exact discovery pointer below.
Normal coding tasks must not install, repair or remove that pointer.
This exception grants no permission to change managed configuration, trust, other skills or target repositories.
No plugin upload, external installer, hook or additional executable skill resource is required.

```text
$HOME/.agents/skills/harness-python-patterns
  -> /workspace/my-harness-wrapper/config/codex/native-skills/harness-python-patterns
```

An alternate wrapper location must be the verified canonical source checkout executing the provisioner.
The checkout must have the wrapper origin and a conventional local `.git` directory.
The native files, pack verifier and pack anchors must match committed HEAD and index entries.
Uncommitted native-source preparation is rejected.
The checkout cannot be nested inside another repository.

The provisioner requires matching real/effective user IDs and HOME equal to the account database's canonical home.
The home must exist, belong to that user, have no writable group/other bits, and be outside repositories and managed configuration.
Symlink ancestors and foreign or writable discovery parents are refused.
Missing `.agents` and `skills` parents are created with mode `0700` only during opt-in installation.
Existing safe parents retain their modes and contents.
Empty platform placeholder `.git` directories in ancestors do not identify repositories.
Any `.git` marker in the home or discovery parents is refused.
Descriptor-relative directory opens reject symlinks; symlink creation never replaces an entry.
Directory locking has a ten-second bound.
A matching user-owned absolute pointer is preserved on repeat preparation.
Foreign files, directories, relative links and links to other sources are preserved and rejected.
The pointer's bytes and owner cannot authenticate which process originally created a matching link.
Concurrent hostile changes by the same account or changes to trusted wrapper code and anchors remain outside the ownership/checksum boundary.

## Prepare and publish

The operator selects the reviewed wrapper PR revision for an unmerged test and records its exact SHA.
The coding agent does not edit Environment settings or publish an Environment.
In Settings > Codex Cloud > Environments, select the Environment menu, then Edit.
Keep the wrapper attached at `/workspace/my-harness-wrapper` alongside a distinct target checkout.
Replace `/workspace/DISTINCT_TARGET_CHECKOUT` below with that actual attached target path.
Use this Install script only after approving the preparation exception:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd /workspace/my-harness-wrapper
native_target=/workspace/DISTINCT_TARGET_CHECKOUT
native_before=$(python3 -I scripts/check-native-preservation.py "$native_target")
printf 'PREPARATION_BEFORE %s\n' "$native_before"
HARNESS_ENABLE_NATIVE_SKILLS=1 bash env/setup-codex.sh
python3 -I scripts/provision-native-skills.py inspect
native_after=$(python3 -I scripts/check-native-preservation.py "$native_target")
printf 'PREPARATION_AFTER %s\n' "$native_after"
test "$native_before" = "$native_after"
```

The flag is command-scoped; do not configure it as a persistent task environment variable.
Setup runs its five real regression suites with native provisioning disabled inside those suites, verifies delivery, then installs the pointer.
Inspect the preparation output for `NATIVE_SKILL_SOURCE_VERIFIED` and `NATIVE_SKILL_LINK_VERIFIED` with the expected source and SHA-256.
These results establish source/pointer delivery only.
Require matching preparation before/after target snapshots and retain both output records.
The snapshot covers checkout contents as they exist before this wrapper Install script begins.
On a source, home, ownership, collision or permission failure, preserve the state and stop native preparation.
Do not elevate privileges or substitute another skill location.
The explicit verified pack reader remains available independently of pointer provisioning.
Resolve the operator boundary, save changes, select Republish, and start a new task.
Publishing captures the prepared filesystem; this does not establish that Cloud indexes the user-scope pointer.

## Read-only inspection and evidence

```bash
python3 -I /workspace/my-harness-wrapper/scripts/provision-native-skills.py source
python3 -I /workspace/my-harness-wrapper/scripts/provision-native-skills.py inspect
```

`source` verifies the committed checkout, pack, frontmatter, exact body, license and provenance without reading HOME.
`inspect` additionally verifies the pointer without creating directories or changing permissions.
`NATIVE_SKILL_LINK_ABSENT` and `NATIVE_SKILL_LINK_CONFLICT` exit 1.
Missing required native instructions report `NATIVE_SKILL_SOURCE_MISSING` and exit 1.
Neither command reports provider discovery, selection or invocation.
Source digests cannot distinguish an indexed skill from an ignored skill.
A matching pointer cannot distinguish a published snapshot from an unpublished preparation or an indexed skill from an ignored skill.
The linked source remains dependent on the attached wrapper checkout and its pinned revision.

| Gate | Required evidence |
| --- | --- |
| `FILES_VERIFIED` | Committed native files, valid metadata, exact body, MIT license and pinned provenance. |
| `LINK_PROVISIONED` | Expected pointer established in approved Environment preparation and preserved in the published snapshot. |
| `PROVIDER_DISCOVERED` | Fresh-task provider inventory identifies the user-scope skill and loaded origin before manual instruction reading. |
| `PROVIDER_INVOKED` | Actual native selector/dispatch evidence and the read-only smoke result. |
| `TARGET_UNCHANGED` | Matching before/after target file and Git metadata snapshots. |
| `HOSTED_CI_GREEN` | Executed successful required hosted steps at the reviewed PR revision and recorded tested merge SHA. |

## Fresh-task acceptance prompt

Replace `REVIEWED_WRAPPER_SHA` with the actual reviewed PR head SHA recorded by the operator.
This prompt is for a new task from the republished Environment, not the implementing task.

```text
Use the republished Codex Cloud Environment containing /workspace/my-harness-wrapper at REVIEWED_WRAPPER_SHA and a distinct attached target checkout. Work read-only. Do not install or repair skills, change trust, or write to the target or its Git metadata.
Before startup, record a read-only baseline snapshot of the distinct target with python3 -I /workspace/my-harness-wrapper/scripts/check-native-preservation.py /absolute/target. Retain the operator's matching preparation-before/preparation-after records separately; task snapshots cannot retroactively prove preparation preservation. Record the published Environment revision and actual wrapper HEAD. Run bash /workspace/my-harness-wrapper/scripts/session-check-codex.sh exactly once. Record the native source digest and pointer state using python3 -I /workspace/my-harness-wrapper/scripts/provision-native-skills.py inspect. This inspector verifies bytes without emitting SKILL.md contents.
Before opening SKILL.md or executing the explicit pack reader, inspect the actual provider-native skill inventory. Require harness-python-patterns as a user-scope skill and record its advertised path, resolved wrapper-owned origin and provider evidence reference. A shell directory listing is insufficient. If absent, stop native acceptance and report the specific observed blocker.
Then invoke exactly once: $harness-python-patterns Explain EAFP versus LBYL in two sentences. During this invocation, do not run commands or change files. Record the actual provider selection/dispatch ID or equivalent native evidence and the two-sentence response. A generic answer without native dispatch evidence fails acceptance.
After the invocation, repeat the wrapper's read-only target snapshot and require identical output. Record separate FILES_VERIFIED, LINK_PROVISIONED, PROVIDER_DISCOVERED, PROVIDER_INVOKED, TARGET_UNCHANGED and HOSTED_CI_GREEN states. Do not infer provider discovery from source or pointer checks. Assess automatic activation separately only if the provider exposes a measurable signal.
If the published snapshot drops the pointer, the provider ignores user-scope skills, or unavailable trust is required, report that exact blocker. Do not repair a target repository. The explicit verified reader remains the functional fallback. Keep wrapper issue #30 open pending independent runtime acceptance.
```

The preservation checker hashes regular file bytes, symlink text, directory entries and ownership/mode/inode/mtime metadata, including the conventional `.git` directory.
It executes no target Git command and follows no skill or repository symlink.
Access times are excluded because inspection reads files.
External Git directories and special files are unsupported and fail explicitly.

## Rollback

During approved Environment preparation, retain the reviewed wrapper source and run:

```bash
HARNESS_ENABLE_NATIVE_SKILLS=1 python3 -I /workspace/my-harness-wrapper/scripts/provision-native-skills.py remove
```

Removal verifies source, identity, safe parents, owner and exact pointer target before unlinking only that entry.
Foreign entries are preserved and rejected.
Safe parent directories and all other skills remain untouched.
Restore the default Install script from `codex.md`, save and Republish.
An absent pointer exits 1 with `NATIVE_SKILL_LINK_ABSENT`; no removal is needed in that state.
An unavailable or changed source blocks removal; restore the reviewed source or request an operator decision rather than deleting an unverified entry.

## Regression boundaries

`python3 -I scripts/tests/test_native_skills.py` runs real provisioning and one full real setup in a disposable committed wrapper clone, isolated HOME and dummy target.
Only account-database home lookup is injected to identify that scratch HOME; production exposes no home override.
Additional unit cases simulate ownership, permission denial and interruption at syscall boundaries.
The real user's HOME is never provisioned by these tests.
Tests compare source file/Git bytes, HEAD and status, and dummy target bytes and metadata.
The existing bootstrap may refresh source index inode/mtime and private mode without changing its bytes or staged state.
Fixture Git commands start with a private umask so that source permission checks are stable under the runner's default umask.
Tests also exercise deletion/restoration, conflicts, symlinks, opt-out, provenance, interrupted creation and fallback reads.
Scratch filesystem success does not establish Cloud snapshot retention or provider indexing.
The native suite is a separate required hosted step checked by the CI contract and its deletion regression.

References: [user-scope discovery and symlinked skills](https://learn.chatgpt.com/docs/build-skills), [Environment preparation and publication](https://learn.chatgpt.com/docs/environments/cloud-environments).
