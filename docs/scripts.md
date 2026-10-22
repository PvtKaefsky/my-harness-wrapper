# Scripts and regression checks

| Path | Interface and result |
| --- | --- |
| `env/setup-codex.sh` | Runs all five suites, bootstraps delivery, checks startup and optionally provisions one preparation pointer; no network installer. |
| `scripts/bootstrap-codex.sh` | Validates pack/state, locks delivery and publishes or reuses an immutable release. |
| `scripts/verify-codex.sh` | Read-only delivery/source checks and separate capability status fields. |
| `scripts/session-check-codex.sh` | Verifies and emits policy location plus the actual lazy catalog bytes. |
| `scripts/codex-common.sh` | Git selector isolation, safe state paths, ownership, locking helpers and manifest checks. |
| `scripts/pack-codex.py` | `verify`, `fingerprint`, or `read ID`; bounded pinned pack validation and explicit instruction reading. |
| `scripts/check-native-source.py` | Read-only real-path repository package equality, safety and committed HEAD/index validation; no HOME access. |
| `scripts/provision-native-skills.py` | Offline `source`/`inspect` checks and opt-in preparation-only `install`/`remove` for one user-scope pointer. |
| `scripts/check-native-preservation.py` | Read-only target file/Git snapshot digest; no target Git commands or writes. |
| `scripts/build-cloud-pack.py` | Offline maintainer projection build from an exact clean upstream checkout into an absent destination. |
| `scripts/pack-projection.json` | Audited topic rewrites, dependencies and source mappings used by the build. |
| `scripts/check-codex-hooks.sh` | Refuses active commit/index/reference hooks without disabling them. |
| `scripts/check-codex-preflight.sh` | Bounded staged diff whitespace check before commit. |
| `scripts/check-codex-review.py` | Checks schema version 2 tree-bound verdict/receipt consistency and declared project role coverage, or reports minimum `--requirements` and role brief mapping; cannot authenticate provider evidence. |
| `scripts/check-codex-identity.sh` | Requires all four explicit identity variables and matching resolved Git roles. |
| `scripts/check-codex-attribution.sh` | Checks a prepared body; exits 0 for clean text, 2 for matching attribution, 1 for unreadable input. |
| `scripts/check-codex-commit-args.py` | Rejects tree/identity-changing commit arguments and checks explicit message attribution. |
| `scripts/commit-codex.sh` | Explicit identity and independent review checks, then Git in the caller's repository; prints `GUARDED_COMMIT_PASSED` only after Git succeeds. |

## Hosted CI checks

| Path | Interface and result |
| --- | --- |
| `.github/workflows/codex.yml` | Hosted push/PR job invoking the five existing suites, native skill suite, real-path repository source check, isolated full setup and CI contract tests. |
| `scripts/check-hosted-ci.py` | `workflow PATH` validates the bounded workflow contract; `run RUN_JSON JOBS_JSON EXPECTED_SHA` checks supplied GitHub execution records. |
| `scripts/tests/test_hosted_ci.py` | Local contract tests covering required commands, permissions, timeout, unmasked exit 37, stale checkout, inherited Git-context preservation, empty/skipped/failing steps and rejected non-CI claims. |

The deletion test removes the Cloud pack invocation in a disposable workflow file.
It requires exit 1 with `HOSTED_SUITE_COVERAGE_MISSING: Cloud pack suite`, restores the invocation, and requires exit 0.
Fabricated hook/skill status strings cannot substitute for hosted execution records.
These tests certify local validator behavior, not provider hook/skill execution or genuine hosted runs.

## Suites

```bash
bash scripts/test-codex.sh
bash scripts/test-codex-git-context.sh
bash scripts/test-codex-identity.sh
bash scripts/test-codex-attribution.sh
bash scripts/test-cloud-pack.sh
python3 -I scripts/tests/test_native_skills.py
HARNESS_STATE_DIR=/absolute/new/scratch-state bash env/setup-codex.sh
```

The delivery suite exercises immutable releases, tampering, interruption, stale source/commit, safe paths, missing tools and attribution.
The Git-context suite checks caller HEAD, index, object files and working files under inherited Git selectors.
The identity suite uses temporary repositories and a private Git configuration to check blocked and valid commits.
The attribution suite tests clean, forbidden and unreadable bodies.
The pack suite checks real setup/startup/read paths, source/index/integrity failures, duplicate IDs, malicious instructions, unsafe paths/state, target preservation and review enforcement.
Its disposable setup fixtures replace only suite runners with no-op boundaries to avoid recursive suite invocation; production setup runs the real suites.
Fixture repositories and synthetic reviewer records do not establish Cloud provider acceptance.

Pack, manifest, setup delivery, startup catalog, identity enforcement and review enforcement each have bounded deletion RED/GREEN cases.
Deletion changes occur only in disposable fixtures and are restored before GREEN verification.
Omitting catalog bytes triggers `WORKFLOW_CATALOG_NOT_CONSUMED` task acceptance even if delivery verification passes.
The test runner's exception supplies that named acceptance failure; the shell cannot prove conversational consumption.
No suite writes personal configuration, managed runtime files or attached target repositories.

The native suite covers exact repository-path bytes and committed index, deletion/mutation RED/GREEN, unsafe files, fingerprint changes, safe scratch-HOME provisioning, target preservation, interruption and explicit fallback reads.
Its default and opt-in real setup cases run all five existing suites without stubs.
Default setup and the fallback reader from a separate synthetic repository must preserve strict wrapper, target and scratch-HOME bytes and metadata.
The retained HOME provisioner is disabled by default and inapplicable to the reported managed preparation runtime.
See [native delivery](native-skills.md) for the account-lookup test boundary and provider acceptance limits.

The review suite rejects absent/mismatched provider receipts, missing proof, duplicate identities/completions, self-review, stale HEAD/tree, unsupported roles, missing project coverage, empty/blocked verdicts, findings above LOW and invalid identity.
Renamed/deleted source paths retain minimum role coverage.
The provider-receipt deletion case removes consumption from a scratch copy of the real checker, requires `PROVIDER_RECEIPT_CONSUMPTION_OMITTED` acceptance RED, restores rejection of missing receipts and passes a synthetic valid guarded commit for GREEN.
That GREEN verifies local gate behavior only, never genuine independent approval.

Native fixtures disable automatic Git garbage collection and maintenance in their private scratch Git configuration before initializing repositories.
This prevents background object pruning from racing strict byte/metadata snapshots on newer Git versions.
The complete snapshots and preservation assertions remain unchanged.
Attached repository and user Git configuration are not changed.
