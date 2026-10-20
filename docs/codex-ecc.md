# ECC setup diagnostics

## Scope and deployment

ECC is required for ordinary Codex coding tasks.
Issue [#22](https://github.com/PvtKaefsky/my-harness-wrapper/issues/22) remains open.
The native installation probe and temporary one-skill feasibility experiment
retain separate setup evidence.
It does not certify full ECC integration.

The existing four-line Environment launcher and saved startup field in
`docs/codex.md` stay unchanged.
`env/setup-codex.sh` owns the setup probe.
No Environment UI edit or manual log copying is needed.
The source must reach the selected checkout before the next actual Environment
setup run to capture setup-phase evidence.
Opening a PR does not rebuild or publish an Environment.
Neither a task-shell run nor a mocked CLI establishes setup-phase permissions
or persistence into fresh tasks.

## Evidence paths

| Path | Contents |
| --- | --- |
| `${HARNESS_STATE_DIR-/workspace/.harness-wrapper}/ecc-setup/status.json` | Structured status for the latest setup probe. |
| `${HARNESS_STATE_DIR-/workspace/.harness-wrapper}/ecc-setup/diagnostic.log` | Bounded redacted native phase, attempt, exit, and diagnostic details. |
| `${HARNESS_STATE_DIR-/workspace/.harness-wrapper}/ecc-skill-probe/status.json` | Separate one-skill setup placement record; never runtime discovery acceptance. |
| `${HARNESS_STATE_DIR-/workspace/.harness-wrapper}/ecc-skill-probe/diagnostic.log` | Bounded redacted skill placement events, checks, and blockers. |
| `${HARNESS_STATE_DIR-/workspace/.harness-wrapper}/ecc-skill-probe/scope.json` | Private write-once binding to the initial placement HOME and destination. |

Evidence lives outside source repositories and immutable delivery releases.
It is excluded from Git and the adapter release manifest.
The existing adapter ownership marker and state lock still govern the state.
The ECC directory is private to its owner.
Evidence files are atomically replaced mode-0600 regular files.
Symlinked paths and nonregular evidence targets are rejected.
Unrecognized state directories are not adopted or repaired.
Scratch tests use a new absolute `HARNESS_STATE_DIR` outside checkouts.

The status records schema version, run ID, setup phase, source commit and
fingerprint, selected upstream source and SHA, timestamps, completeness,
CLI version, per-phase events and exit codes, effective revision, registration,
cache, idempotence, previous setup presence, setup attempts, and error category.
The fresh-task plugin list, skill invocation, hook trust, and hook execution
remain separate unverified fields.
`already_present_at_setup` means the setup CLI listed ECC before this probe.
It does not mean a later task loaded ECC.
`install_attempted_in_setup` includes the native marketplace registration
attempt; `marketplace_add_attempted` and `plugin_add_attempted` separate the
two commands.
The status binds the log with SHA-256.
A matching fingerprint distinguishes the checked source bytes from stale bytes.
It does not authenticate the author or reproduce dirty source from its commit.

## Native setup probe

After the required regression suites and wrapper bootstrap, setup invokes
`scripts/ecc-codex.sh setup` once.
It verifies the actual executable's version and help for native marketplace
add/list and plugin add/list, including `--ref` and `--json`.
It inspects existing registrations before attempting changes.
Conflicting or unverifiable existing ECC source/ref registrations are preserved
and reported as not ready.
Unrelated marketplaces are preserved and checked after registration.

The selected source is `affaan-m/ECC` at
`76aaa77df6adc5b889e689007bf99b9a4f74af34` (ECC 2.2.3).
The probe uses only these native modification commands:

```bash
codex plugin marketplace add affaan-m/ECC --ref 76aaa77df6adc5b889e689007bf99b9a4f74af34 --json
codex plugin add ecc@ecc --json
```

Unsupported pinning is a failure without a floating-source fallback.
`alreadyAdded` alone is not revision evidence.
The probe checks the effective listed source, the readable marketplace Git
revision, and the repository-root marketplace entry.
An undiscoverable revision is `UNVERIFIED`.
Registration must expose an installed, enabled `ecc@ecc` at version 2.2.3.
The native cache inspected is
`${CODEX_HOME:-$HOME/.codex}/plugins/cache/ecc/ecc/2.2.3`.
The probe does not relocate `CODEX_HOME` or edit native configuration directly.
The cached manifest must match the selected marketplace manifest.
Its skills, MCP, hooks, icon, logo, and screenshot references must resolve inside
the cache and match the corresponding marketplace bytes.
The representative `skills/configure-ecc/SKILL.md` must be readable.
Cache validation does not execute cached code, MCP servers, skills, or hooks.
After a successful first pass, one repeat registration/install pass checks
idempotence and cache validity.
An earlier failure stops the probe without an unbounded retry.

## Bounds and privacy

The probe has a 180-second command budget.
Native add commands each have a 30-second limit.
Other commands each have a ten-second limit.
Captured stdout and stderr together are capped at 64 KiB per command.
Oversized output fails the command rather than accepting truncated JSON.
Each retained event detail is capped at 4 KiB.
The log is capped at 128 KiB and structured status at 192 KiB.
Cache reference comparisons are capped at 10,000 entries and 32 MiB per reference.
Output is captured in memory and redacted before any diagnostic write.
URLs are removed, including authenticated URLs and query strings.
Credential header/key lines and recognized GitHub/OpenAI token forms are removed.
Environment values, credential files, and authorization headers are never
deliberately collected.
Redaction is conservative pattern matching, not a guarantee for arbitrary
unrecognized secret formats printed by external commands.
Useful stderr, exit codes, and errors remain available within these bounds.
The probe never uses shell tracing or dumps the environment.

Error categories are `CLI incompatibility`, `permission/configuration`,
`network/proxy`, `packaging/cache`, and `unknown`.
Classification is a diagnostic heuristic, not proof of a platform limitation.
The command detail remains the evidence for the failure.

## Setup and task statuses

| Status | Meaning and action |
| --- | --- |
| `native_registration: VERIFIED` and `cache: VERIFIED` | Both setup passes verified native registration and referenced cache bytes; fresh-task discovery remains unverified. |
| `ECC NOT READY` | Ordinary work is blocked; report the unavailable stage and retained paths. |
| `ECC_SETUP_EVIDENCE_MISSING` | Retained files were not found; installation attempts are unknown, including a possible setup-snapshot boundary. |
| `ECC_SETUP_EVIDENCE_STALE` | Source commit, source fingerprint, or selected upstream SHA differs; a new setup run is required. |
| `ECC_SETUP_EVIDENCE_INCOMPLETE` | The probe was interrupted or log/status do not describe one complete record. |
| `ECC_SETUP_EVIDENCE_INACCESSIBLE_OR_INVALID` | Evidence cannot be safely read or validated; do not infer readiness. |
| `UNVERIFIED` | The recorded run did not demonstrate that capability. |
| `NOT OBSERVED` | Actual Cloud setup or fresh-task acceptance was unavailable to the validating session. |

Progress is published before each command and after each result.
TERM/INT retain a failed incomplete record.
A hard kill can leave the last checkpoint or mismatched log/status, which task
startup rejects.
A nonzero native command produces `ECC NOT READY` and expected diagnostic exit 2.
Only that expected probe exit is tolerated by setup.
Storage-safety failures and existing required wrapper checks remain fatal.
Setup ends with `scripts/verify-codex.sh`, which certifies delivery only.
A successful setup script never implies `ECC READY`.

The existing startup instructions invoke `scripts/session-check-codex.sh`.
It checks wrapper integrity and independently reads and validates the persisted
setup record under a shared lock, displaying a concise redacted summary and paths.
Delivery failures retain their nonzero status while stale ECC evidence is still
reported.
It runs no native plugin modification commands.
It currently returns readiness exit 2 even after a simulated registration/cache
success, because supported fresh-task skill acceptance is not implemented.
Task-visible plugin listings, installed cache validity, actual skill invocation,
and trusted/executed hooks are distinct stages.
The shell check cannot observe a conversational skill invocation.
A future supported acceptance mechanism is needed before it can report ready.

An explicitly authorized diagnostic task may inspect or instrument these stages
under the diagnostic-only bootstrap exception.
It must report not-ready status and cannot progress ordinary project work or
waive the independent review gate.
If diagnostics cannot satisfy readiness, report the evidence and stop ordinary
work under `config/codex/AGENTS.md`.
Independent native reviewers remain independent of ECC acceptance.

## Rebuild and acceptance

Re-running the repository setup replaces the latest diagnostic record and
performs at most one repeat-check pass after initial success.
Older delivery releases remain unchanged.
A changed source fingerprint makes previous diagnostics stale.
The next actual Environment setup run exercises its own permissions and CLI.
Its retained record must then be checked by a fresh Cloud task.
If files do not survive that boundary, startup reports missing evidence.
No restoration mechanism is invented or configured by this change.

The bounded experiment requires the specific provider-dispatched
`$python-patterns` action below.
It does not establish full-ECC fresh-task acceptance.
Plugin listing and readable `SKILL.md` alone cannot satisfy that acceptance.
Hook trust and execution require separate supported verification.
This task does not approve hooks, publish an Environment, or merge its PR.

## Temporary user-skill experiment

This experiment refers to issue #22 and leaves it open.
It is a diagnostic-only exception to the ordinary-task readiness gate.
Only Environment setup calls `scripts/ecc-codex.sh skill-setup`.
The wrapper owns the offline source in `config/codex/ecc-python-patterns/`.
It promotes the byte-identical regression fixtures from wrapper commit
`348d838668adee598ec360aff203a23e686b771d`, with no duplicate test copy.
This deliberate limited vendoring supplies exactly one skill and its MIT license.
It does not authorize a copy of the ECC repository or its native plugin.
Setup and deterministic tests consume the same source bytes.
`source.json` records `affaan-m/ECC`, the exact GitHub commit, upstream file paths,
checksums and the 2026-10-20 direct forge comparison record.
Hash equality alone cannot establish upstream provenance.
The source bytes and metadata participate in `codex_source_digest`.
Missing or symlinked source files contribute a named unavailable-path fingerprint.
The skill-source reader validates metadata and both pinned hashes before placement.
It performs no network fetch, native CLI command or marketplace lookup.
Native setup and its failure evidence remain separate and unchanged.
A missing marketplace path, failed native registration or incomplete native record
cannot prevent the independent skill source from being checked.
Reject the PR if an independently pinned network-fetching skill source is preferred.

The selected upstream directory is `skills/python-patterns` at the pinned SHA.
Inspection at that revision found only `SKILL.md` and no local resource references.
Its frontmatter name is `python-patterns`.
Its unchanged bytes have SHA-256
`103e0130dac33a49d26705fc5a2df804980fcab6a0138d65bc7f370a987d49f6`.
The EAFP/LBYL description exercise needs no commands, scripts, or dependencies.
The only extra delivered file is the unchanged upstream MIT `LICENSE` notice,
SHA-256 `326146379f01bb137c0a5d3c54770c1aa31076705c8b88a7f6b26a460f6221b2`.
The skill's frontmatter and contents are not rewritten.
The bundled source directory contains exactly `SKILL.md`, `LICENSE` and `source.json`.
Only the first two files are delivered to user scope.
No other skills, agent definitions, MCP servers, hooks, plugin manifests, or
installers are copied into user scope.
The Codex-owned source directory is outside provider discovery roots.

The only destination is `$HOME/.agents/skills/python-patterns` for the execution user.
`HOME` must already exist as an ordinary owned user directory.
Setup checks actual HOME writability with an exclusive private temporary file;
mode bits alone do not establish writability.
Existing `.agents` and `.agents/skills` must be ordinary owned directories.
HOME and both scope parents must be owner-readable/searchable/writable and not
writable by group or others.
Setup creates only missing `.agents` and `.agents/skills` parents mode 0700,
relative to validated open directory descriptors without following symlinks.
Existing contents and modes are preserved; unsafe paths are never repaired.
The write-once HOME binding precedes scope-parent creation.
A different HOME is rejected before scope creation.
The scope is reopened and its device/inode compared before and after placement.
Every path component is opened without following symlinks.
Ancestors must belong to the execution user or the filesystem root's owner and
cannot be writable by group or others unless sticky, as with `/tmp`.
The root owner is read from `/` to support mapped UIDs in managed containers.
The destination cannot be inside a source or target repository.
Missing HOME, unsafe ancestors, read-only scope, changed HOME and symlink escape
produce BLOCKED without path redirection or sudo.
Setup creates the intended skill directory mode 0700 and files mode 0600.
Bounded file writes are published without replacing preexisting files.
An existing skill is reused only when a complete prior wrapper placement record,
the same HOME/destination, exact bounded contents, ownership, modes, and hashes match.
Even byte-identical preexisting content without that record is a collision.
Conflicting and interrupted placements are preserved rather than repaired or deleted.
The scope binding is written before touching the destination and is never replaced.
Blocked or interrupted attempt records cannot redirect a later retry to another HOME.
A missing binding alongside any existing attempt record is BLOCKED and is not
reinitialized, including when HOME changed or the record is incomplete.
Malformed or unsafe binding is a fatal evidence-storage error and is preserved.

The independent `ecc-skill-probe` record binds its log with SHA-256 and records
wrapper source identity, upstream pin, exact source and destination, skill name,
source/delivered checksums, destination owner/mode, prior presence, safe delivery,
and setup completeness.
It uses the existing state validation, exclusive setup lock, bounded redaction,
private evidence files, and atomic evidence replacement.
Skill setup performs bounded local filesystem operations and runs no source commands.
Each copied file is capped at 64 KiB.
Source and destination directory listings stop at the first excess entry.
Native discovery, invocation, MCP, and hook trust/execution remain UNVERIFIED.
No placement state is called runtime VERIFIED or ECC READY.
Unsafe evidence storage remains fatal; expected placement blockers return 2 and
allow delivery verification to finish.

Task startup calls `scripts/ecc-codex.sh skill-status` under the shared state lock.
It validates the setup record and compares actual ordinary destination bytes,
owner and modes without opening their text into the conversational context.
It performs no installation or repair and writes no task-time evidence.
Its output is the task-time observation; it does not retrospectively prove setup.
It returns 2 even when every filesystem check passes.

| Boundary/status | Evidence and interpretation |
| --- | --- |
| Setup `PLACED` / `ECC_SKILL_SETUP_PLACED` | Setup copied pinned bytes, or reused a matching previously owned placement; provider loading is unverified. |
| Setup `BLOCKED` / `ECC_SKILL_SETUP_BLOCKED` | Named source, scope, ownership, permission, or collision blocker; preserve state. |
| `ECC_SKILL_PINNED_SOURCE_UNAVAILABLE` | Bundled source directory is absent; native marketplace state cannot supply a fallback. |
| `ECC_SKILL_SOURCE_SKILL_ABSENT`, `ECC_SKILL_SOURCE_LICENSE_ABSENT` | Required bundled file is absent. |
| `ECC_SKILL_SOURCE_SKILL_BYTES_MISMATCH`, `ECC_SKILL_SOURCE_LICENSE_BYTES_MISMATCH` | Bundled file does not match its pinned checksum. |
| `ECC_SKILL_HOME_WRITE_FAILED` | Actual exclusive HOME write failed; mode bits did not establish writability. |
| `ECC_SKILL_SCOPE_PARENT_MISSING`, `ECC_SKILL_SCOPE_PATH_UNSAFE` | Scope parent is missing during measurement or unsafe to open; startup never creates it. |
| `ECC_SKILL_SCOPE_CHANGED`, `ECC_SKILL_DESTINATION_CHANGED` | The reopened path no longer identifies the open scope or destination; preserve it. |
| `ECC_SKILL_FILES_PERSISTED` | This process found matching ordinary files at the recorded HOME path; local fixture observations do not prove Cloud persistence. |
| `ECC_SKILL_PLACEMENT_MISSING` | Setup evidence or delivered files are absent; no placement/persistence acceptance. |
| `ECC_SKILL_EVIDENCE_INCOMPLETE`, `ECC_SKILL_EVIDENCE_STALE`, `ECC_SKILL_EVIDENCE_INVALID` | Partial, stale, or malformed setup evidence blocks measurement. |
| `ECC_SKILL_HOME_CHANGED`, `ECC_SKILL_BYTES_CHANGED`, `ECC_SKILL_MEASUREMENT_BLOCKED` | Current path/bytes or safe measurement differ; do not repair from task startup. |
| `ECC_SKILL_NATIVE_DISCOVERY_NOT_OBSERVED` | Shell measurement cannot observe provider inventory/selectors. |
| `ECC_SKILL_INVOCATION_UNVERIFIED` | Shell measurement cannot observe a provider-dispatched skill action. |

A checksum match distinguishes equal from changed bytes; it cannot distinguish
scanned, unscanned, or actually invoked skills.
Provider inventory must name `python-patterns` with the matching source/path;
a duplicate name at another scope is insufficient.
A provider invocation marker and relevant read-only response establish skill use;
a manually read skill or an agent's unsupported assertion cannot establish it.
Plugin listing absence alone does not disprove filesystem skill discovery.
One-skill success cannot certify the ECC plugin, MCP, reviewers, or hooks.

## Operator publication and fresh-task acceptance

The operator reviews and merges the PR, then republishes the Environment using
the existing launcher and saved startup instructions, then starts a fresh task.
A repository merge does not publish an Environment.
Any necessary UI field change is a separate operator decision.
Local fixture results precede this boundary and claim no live Cloud acceptance.
The user decides whether to retain or extend this temporary mechanism afterward.

Use this follow-up task after publication:

```text
Diagnostic-only acceptance for Refs: #22; ordinary project work stays blocked.
Record the actual wrapper checkout SHA and config/codex/version.
Run scripts/session-check-codex.sh once; exit 2 is expected.
Read both retained ecc-setup and ecc-skill-probe status/log records.
Inspect the provider-native skill inventory/selectors BEFORE manually opening
SKILL.md; retain bounded exact output and the python-patterns source/path.
Then record actual HOME, destination, owner/mode and SHA-256; compare to setup.
Attempt exactly one provider-native action if its dispatch path is available:
$python-patterns Explain EAFP versus LBYL in two sentences without executing
commands or modifying anything.
Record its provider invocation marker and response separately from file hashes.
Report missing inventory items or absent dispatch markers as BLOCKED with exact
bounded output; neither is a successful discovery or invocation.
If no invocation path is exposed, record BLOCKED and exact discovery output.
Record native plugin listing, MCP, hooks and reviewers separately as observed
or UNVERIFIED; keep ECC NOT READY and issue #22 open.
Do not install, repair, move, register or trust anything from this task.
```

The expected transitions are setup PLACED, fresh-task file MATCH, then separately
provider discovery and actual invocation, or a named blocker at any boundary.
Read the inventory before manually reading skill text to avoid treating copied
text as evidence that the provider loaded the skill.
If the user-level path fails live, report that exact outcome and the next
architecture choice for the user's decision; do not auto-install elsewhere.
Native plugin-state disappearance was observed in a prior live task; its precise
platform lifecycle mechanism remains unestablished.

## Regression coverage

`bash scripts/test-codex-ecc.sh` and `bash scripts/test-codex-ecc-skill.sh` are
registered in the setup workflow.
Its fixtures execute isolated copies of `env/setup-codex.sh` followed by
`scripts/session-check-codex.sh` as separate processes.
The copied suite entry points are replaced with successful stubs to avoid
recursive suite execution; the real suites run independently and in complete
setup validation.
The fake CLI uses an explicit isolated native `CODEX_HOME`.
Placement uses an isolated test `HOME`; neither selects the managed native home.
Its fabricated marketplace Git metadata and cache are deterministic fixtures,
not Cloud installation evidence.
The tests cover CLI and installation failures, source/ref conflicts, cache and
listing failures, nested malformed metadata, special cache files, looping
references, entry bounds,
interruption, repetition, privacy, unsafe and stale evidence,
and successful registration without task skill acceptance.
Deletion regressions disable the probe call and startup consumption separately.
They require failures named `ECC_SETUP_EVIDENCE_MISSING` and
`ECC_TASK_READINESS_NOT_CONSUMED`, then verify restored behavior.

The skill suite checks native read-only failure without a marketplace path,
secure missing-parent creation, unrelated contents, repetition and parent metadata,
missing/wrong bundled skill or license, invalid source metadata, independence from
absent/divergent native source bytes, absent HOME, read-only and symlinked scope,
unsafe HOME ancestors, colliding and byte-identical unowned skills, partial/log-mismatched
evidence, changed bytes/permissions, repeated HOME differences, missing or unsafe
scope bindings, and unsafe evidence storage.
It runs real setup and separate task processes with the pinned upstream bytes.
Deletion of the real setup placement call must produce
`ECC_SKILL_PLACEMENT_MISSING`; deletion of task measurement must produce
`ECC_SKILL_FILES_NOT_PERSISTED`; deletion of the discovery instruction produces
`ECC_SKILL_TASK_MEASUREMENT_NOT_CONSUMED`; reinstatement must pass.
Deleting the independent source-selection route reinstates the native-source
prerequisite and must fail the primary read-only regression with
`ECC_SKILL_PINNED_SOURCE_UNAVAILABLE`.
Deleting parent creation must fail it with `ECC_SKILL_SCOPE_PARENT_MISSING`.
Each deletion is confined to disposable fixture source and restored before a
passing setup/startup acceptance rerun.
A blocked source attempt without a binding uses a fresh scratch state after
restoration, preserving the missing-binding rejection policy.
No fixture invokes a native provider skill.

References:

* [Pinned native ECC guide](https://github.com/affaan-m/ECC/blob/76aaa77df6adc5b889e689007bf99b9a4f74af34/.codex-plugin/README.md)
* [Pinned native manifest](https://github.com/affaan-m/ECC/blob/76aaa77df6adc5b889e689007bf99b9a4f74af34/.codex-plugin/plugin.json)

* [Codex documented local skill scopes](https://learn.chatgpt.com/docs/build-skills)
* [Codex Cloud setup/task lifecycle](https://learn.chatgpt.com/docs/environments/cloud-environment)
* [Pinned python-patterns](https://github.com/affaan-m/ECC/blob/76aaa77df6adc5b889e689007bf99b9a4f74af34/skills/python-patterns/SKILL.md)
