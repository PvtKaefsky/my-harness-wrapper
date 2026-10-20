# ECC setup diagnostics

## Scope and deployment

ECC is required for ordinary Codex coding tasks.
Issue [#22](https://github.com/PvtKaefsky/my-harness-wrapper/issues/22) remains open.
This change instruments a native installation feasibility test.
It does not certify full ECC integration.

The existing four-line Environment launcher in `docs/codex.md` stays unchanged.
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
| `${HARNESS_STATE_DIR-/workspace/.harness-wrapper}/ecc-setup/diagnostic.log` | Bounded redacted phase, attempt, exit, and diagnostic details. |

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

Fresh-task acceptance still requires discovering and safely invoking a loaded
representative ECC skill, such as asking `$configure-ecc` for options without
applying configuration.
Plugin listing and readable `SKILL.md` alone cannot satisfy that acceptance.
Hook trust and execution require separate supported verification.
This task does not approve hooks, publish an Environment, or merge its PR.

## Regression coverage

`bash scripts/test-codex-ecc.sh` is registered in the setup workflow.
Its fixtures execute isolated copies of `env/setup-codex.sh` followed by
`scripts/session-check-codex.sh` as separate processes.
The copied suite entry points are replaced with successful stubs to avoid
recursive suite execution; the real suites run independently and in complete
setup validation.
Only the fake native CLI uses the isolated test HOME.
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

References:

* [Pinned native ECC guide](https://github.com/affaan-m/ECC/blob/76aaa77df6adc5b889e689007bf99b9a4f74af34/.codex-plugin/README.md)
* [Pinned native manifest](https://github.com/affaan-m/ECC/blob/76aaa77df6adc5b889e689007bf99b9a4f74af34/.codex-plugin/plugin.json)
