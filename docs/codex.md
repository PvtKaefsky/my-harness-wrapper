# Codex Cloud delivery

## Contract

The Environment includes `/workspace/my-harness-wrapper` as readable versioned source.
Setup verifies the pinned Cloud pack and publishes the shared policy into wrapper-owned state.
Task startup verifies source, delivery, manifest and the catalog before the agent selects full instructions.
Unrelated target repositories need no setup edits, symlinks or discovery directories.
A sibling wrapper checkout is not a provider-native skill discovery root for another repository.

`HARNESS_STATE_DIR` defaults to `/workspace/.harness-wrapper`.
An override must be absolute, canonical, free of symlinks and outside every Git checkout, personal home and managed configuration.
Existing ancestor ownership and permissions are checked before any directory or file is created.
State directories and files must belong to the task user and have private permissions.
Existing unowned, incomplete, unsafe or modified state is rejected and preserved.
Setup does not repair it or remove unrelated contents.
If an older published snapshot has incompatible state, preserve it and choose a new state path explicitly, updating the start skill's policy path to match, or have the operator prepare a clean Environment build.
The default paths do not change silently.

Bootstrap holds an exclusive lock with a ten-second wait bound.
Verification holds a shared lock with the same bound.
A complete release is prepared privately and `current` is switched atomically.
Repeated setup reuses matching source/dirty-state releases.
Published and older releases are preserved, including interruption immediately after publication.

```text
/workspace/.harness-wrapper/
  .owner
  .lock
  releases/release.<id>/
    AGENTS.md
    manifest.json
  current -> releases/release.<id>
```

The delivery manifest records schema, adapter version, source checkout, source commit, source fingerprint, installation dirty flag, policy hash and pack-manifest hash.
The source fingerprint covers root policy/README plus `config/codex`, `env`, `scripts` and `docs`, excluding Python bytecode caches.
Inherited Git repository/index/object/config selectors are cleared for wrapper-source and fixture operations.
Harness Python uses isolated mode (`-I`) to ignore inherited import selectors and adjacent shadow modules.
The guarded commit command preserves the caller's repository context.

The pack manifest is anchored by `config/codex/pack.sha256`.
It lists each delivered artifact hash and upstream path mapping.
`upstream.json` records exact pinned Git-blob hashes, package identity, per-source audit hits and inclusion/exclusion reasons.
Validation rejects path traversal, symlink components, extra/missing files, changed bytes, stale pins, duplicate IDs, broken mappings and prohibited instruction patterns.
The pattern checks are bounded audit defenses, not a general prompt-injection detector.
The reviewed pin and committed hash anchor are the source of trust.
An attacker who replaces both trusted code and its anchors is outside this checksum contract.

## Environment fields

Attach `PvtKaefsky/my-harness-wrapper` at `/workspace/my-harness-wrapper` alongside task repositories.
Use the reviewed migration branch only for an operator-controlled unmerged test; use `main` after merge.
Set `install_script` verbatim:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd /workspace/my-harness-wrapper
bash env/setup-codex.sh
```

Set `start_skill` verbatim:

```text
The shared wrapper source is /workspace/my-harness-wrapper.
If that checkout or its session-check script is absent, report WRAPPER_DEPENDENCY_MISSING and request operator attachment; do not pretend the shared harness is configured.
Run bash /workspace/my-harness-wrapper/scripts/session-check-codex.sh once at task start.
If it fails, report the named failure and investigate before relying on the shared pack; do not install or repair it from a target-repository task.
Read /workspace/.harness-wrapper/current/AGENTS.md and the emitted workflow catalog before working on the task.
Read and apply the target repository's applicable AGENTS.md files; project-local policy and higher-priority platform/user instructions remain authoritative.
Select a matching ID from the shared catalog, then run python3 -I /workspace/my-harness-wrapper/scripts/pack-codex.py read ID and apply the verified instructions and linked brief within the task's existing authorization.
Use existing checkouts under /workspace; create a Git worktree only if the user explicitly requests one.
Work only in the repository relevant to the task; change the wrapper source only for a requested wrapper change.
Do not install into user or managed configuration, change provider trust, or create discovery directories or symlinks in target repositories.
Inventory actual native reviewers, skills, hooks and connected tools before relying on those capabilities; this pack registers none of them.
Before committing, obtain applicable independent native reviews of the exact staged tree and use the guarded commit command with actual review evidence; if a required reviewer is unavailable, finish implementation and tests and leave changes uncommitted.
At completion report the selected workflow, concrete output, checks, and separate observed/unavailable provider capabilities; a checksum is not runtime acceptance.
```

The start skill is agent-facing instruction text, not a shell lifecycle hook.
Its delivery and consumption require actual task evidence.
Setup is offline and runs no upstream installer.
Default setup writes no personal home, managed configuration, shared plugin cache or target-project files.
The only HOME exception is the operator-approved preparation pointer described in [native skill delivery](native-skills.md).
Normal tasks do not install or repair it; source/link verification never proves provider discovery.

## Readiness

| Field or result | Meaning |
| --- | --- |
| Shell exit 0; `SOURCE_AND_DELIVERY=VERIFIED` | Local bytes, source commit/checkout and delivery contract match. |
| `WORKFLOW_INSTRUCTION_READ=REQUIRES_AGENT_TASK_EVIDENCE` | Shell verification has not proved conversational reading or use. |
| Reader `WORKFLOW_INSTRUCTION_READ id=...` | The explicit reader emitted verified instruction bytes; useful task output remains separate evidence. |
| `INDEPENDENT_NATIVE_REVIEW=REQUIRES_PROVIDER_INVOCATION` | Required actual approvals are checked before a commit. |
| `AUTOMATIC_HOOKS=UNAVAILABLE_NOT_REGISTERED` | No automatic shell hooks are installed or trusted by setup. |
| `MCP_AND_CONNECTED_TOOLS=REQUIRES_CURRENT_PROVIDER_INVENTORY` | Real connected tools depend on the current provider; no fork server is installed. |
| `PROVIDER_NATIVE_SKILL_DISCOVERY=NOT_REGISTERED_BY_THIS_PACK` | Direct file reading provides workflows without claiming native selectors. |
| Nonzero; `PACK_MISSING` | The checkout's pack or integrity manifest is missing; no delivery acceptance. |
| Nonzero; other named integrity/state failure | Preserve state and investigate within authorized wrapper scope. |

A checksum match cannot distinguish agent use from non-use.
A local source commit cannot distinguish a current remote base from a stale checkout.
A dirty installation is reported and is not reproducible from its recorded commit alone.
Local fixtures cannot distinguish fresh-task provider availability from unavailable registration.

## Capability evidence

Report each capability separately as `OBSERVED_PASS`, `OBSERVED_FAIL`, `BLOCKED`, `UNSUPPORTED` or `NOT_OBSERVED`.
`OBSERVED_PASS` requires the capability's own executed evidence.
`OBSERVED_FAIL` requires an executed check that fails that capability.
`BLOCKED` names the external action or unavailable prerequisite preventing the check.
`UNSUPPORTED` names a capability absent from this delivery contract.
`NOT_OBSERVED` names a supported or possible behavior without current execution evidence.
Every row records the evidence reference and the stronger claim still unproven.
No comparison, inventory count or unrelated passing capability supplies a numerical grade or a substitute.

| Capability | Evidence required for its own claim | Limit |
| --- | --- | --- |
| Local suites | Source SHA, command, exit and case count from actual suite logs | Local success does not establish hosted execution. |
| Hosted CI | Workflow/run/job IDs, source identities, executed step names and conclusions from GitHub plus failing exit from logs where available | YAML tests, an empty step list, neutral or skipped conclusions do not pass hosted acceptance. |
| Environment setup | Full setup exit, canonical isolated state path and delivery verification | A local setup does not publish an Environment or establish a fresh-task start skill. |
| Live Cloud instruction use | Verified instruction ID/read reference and concrete task output | Installed Markdown and matching hashes do not establish conversational use. |
| Native skills | Actual provider discovery/dispatch evidence | The pack registers no selectors; the separate opt-in native pointer requires fresh-task acceptance in `native-skills.md`. |
| Independent provider review | Native invocation/completion, reviewer identity, explicit approval and exact staged tree | Mock receipts and a passing JSON checker do not establish provider review. |
| Automatic hooks | Actual registered/trusted event and its provider execution evidence | This pack provisions no automatic hooks; explicit commands are not hook events. |
| Connected MCP tools | Current tool inventory and successful authorized invocation reference | Pack files do not register servers or prove other tools work. |

A failure or blocker applies to its own capability.
Other workstreams remain independently testable.
Hosted operations and billing guidance are in [the runbook](runbook.md).

## Post-merge acceptance

1. Review and merge the migration PR on `main`; issue #22 remains unchanged historical context.
2. Open Settings > Codex Cloud > Environments, choose this Environment's menu, then Edit.
3. Ensure the wrapper and a separate target repository are attached; set the exact fields above and the existing identity/assignee variables.
4. Let Codex prepare and test the Environment, save changes, then select Republish.
5. Start a new Cloud task from that published Environment with both repositories; existing tasks retain their own state.
6. Record actual wrapper HEAD, version, manifest/source hashes, startup exit and delivered policy/catalog bytes. A missing wrapper must report `WRAPPER_DEPENDENCY_MISSING`.
7. In the separate target repository ask “apply workflow plan from the shared Codex pack; inspect this repository read-only and propose one bounded improvement.” Read `workflow/plan` through the verified wrapper reader and record the concrete plan without changing the target. An authorized later coding task may instead exercise TDD and record actual RED/GREEN commands and cases.
8. Inventory provider-native reviewer/skill/hook/MCP tools without changing trust or configuration. Invoke applicable independent native reviewers on an actual staged change only when that task authorizes edits; for this read-only acceptance, record reviewer availability and any bounded native read-only review invocation separately. Record provider invocation IDs, completion, verdicts and unavailable stages.
9. Confirm no setup/discovery files appeared in the target repository. Record the Environment publication/version and new task evidence before describing any advertised capability as fresh-task supported.

A merged GitHub PR does not publish an Environment.
This migration's local setup and current-task observations do not certify that operator boundary.
If a required workflow tool or native reviewer is absent, record the exact blocker; do not claim that capability passed.

References rechecked for this migration:

- [Cloud preparation, start skill and republishing](https://learn.chatgpt.com/docs/environments/cloud-environments).
- [Skill discovery locations](https://learn.chatgpt.com/docs/build-skills).
- [Hook support and trust](https://learn.chatgpt.com/docs/hooks).
- [Plugin packaging and surface-specific capabilities](https://developers.openai.com/plugins/build/plugins).
