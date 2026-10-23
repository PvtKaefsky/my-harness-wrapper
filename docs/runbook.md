# Explicit safety checkpoints

Run the startup check once at task start and read its policy/catalog output.
Select an instruction ID with the pack reader and apply it within task scope.
Run relevant project checks after changes.
Before a commit, check the final diff, stage exact changes and obtain applicable independent native reviews in one batch where supported.
A missing required reviewer leaves changes uncommitted.
Review is bounded to five rounds; unresolved findings after that bound require a user decision.

## Review evidence

From the target repository, inspect the staged tree and applicable roles:

```bash
python3 -I /workspace/my-harness-wrapper/scripts/check-codex-review.py --requirements
```

Every change requires general review.
Changed Python files require Python review.
Changed shell files require shell review.
Changes under `env/`, `scripts/` or `config/codex/` require security review.
Other applicable language/domain reviewers remain required by the shared policy even when the mechanical suffix mapping cannot identify them.
The current migration needs general, Python, shell and security review.
Go, database and UI reviewers are inapplicable to this migration's implementation.

Use [the native review protocol](native-review.md) for role selection, bounded dispatch, provider completion receipts and schema version 2 evidence.
The mechanical requirements are minimum coverage; add roles required by project rules and actual staged behavior.
Shell review uses the verified general brief with explicit shell scope; no dedicated shell agent is registered.
Capture the actual reviewer identity, dispatch reference, completion reference and explicit verdict for the exact source HEAD and staged tree.
Set `HARNESS_REVIEW_FILE` to the absolute private scratch record path before the commit command.
Missing receipts, duplicate/self-review, stale trees/HEAD, unsupported roles, missing coverage and findings above LOW block committing.
After editing staged bytes, obtain fresh approvals within the five-round budget.
The local JSON checks cannot cryptographically authenticate provider participation.
Synthetic review records test gate behavior only.

## Commit and forge bodies

Prepare a message/body file and run:

```bash
bash /workspace/my-harness-wrapper/scripts/check-codex-attribution.sh /absolute/scratch/body.txt
bash /workspace/my-harness-wrapper/scripts/check-codex-identity.sh
HARNESS_REVIEW_FILE=/absolute/scratch/review.json bash /workspace/my-harness-wrapper/scripts/commit-codex.sh -F /absolute/scratch/body.txt
```

The commit command first rejects active mutation-capable Git hooks, then checks explicit identity, staged whitespace, message attribution and staged review evidence before Git.
Active pre-commit, message, post-commit, post-rewrite, post-index-change and reference-transaction hooks are an operator boundary because they can change reviewed bytes or refs.
The guard resolves the effective hooks path and refuses before executing them.
Do not disable or bypass project hooks to satisfy this gate; leave the change uncommitted and request a supported review/commit decision.
It preserves the caller's Git context and signing configuration.
It accepts explicit message/file, signing, cleanup and output options for the reviewed staged tree.
It rejects pathspecs, automatic staging, amendment and author overrides because those could bypass reviewed-tree or identity checks.
An explicit message is required and checked for attribution.
The attribution checker rejects co-author/session trailers, generated-by footers and configured session-link patterns.
Its generalized patterns are conservative and can reject quoted examples.
It is an explicit text check, not automatic interception.
Raw Git or forge calls can bypass these scripts; shared policy requires the explicit checkpoints.

## Hosted wrapper checks

`.github/workflows/codex.yml` runs on pushes and pull requests.
The workflow uses JSON serialization of YAML so its local contract checks need no YAML dependency.
The `Wrapper regression` job has read-only contents permission and a twenty-minute timeout.
Checkout is pinned, disables credential persistence and Git safe-directory changes, and selects `github.sha`.
The identity step compares checked-out HEAD with `GITHUB_SHA` before testing.
For pull requests this is GitHub's tested merge commit; record it separately from the PR branch SHA and the run API's `head_sha`.
Each of the five existing suites, native skill suite, real-path repository native source check and full `env/setup-codex.sh` has a named Bash step.
Setup uses a fresh canonical `/tmp/wrapper-ci.XXXXXX/state` outside checkouts, homes and managed configuration.
The runner retains scratch state until disposal.
No upstream installer runs and no target repository is changed.
Required steps use Bash failure propagation without `continue-on-error` or result masking.
Later skipped steps after a failure do not count as executed checks.
The final step runs the focused workflow/evidence contract tests.

Run local contract checks:

```bash
python3 -I scripts/check-hosted-ci.py workflow .github/workflows/codex.yml
python3 -I scripts/tests/test_hosted_ci.py
```

After pushing, read GitHub's actual run and job records for that source revision.
Save raw run JSON and the complete jobs response in private scratch files using the connected tools or `gh api`.
Record every required step's name, timestamps and conclusion; use job logs for explicit exits where available.
GitHub step summaries expose conclusions rather than numeric exit codes.
An unavailable log leaves the numeric exit unknown.
For a push run, check the supplied records with:

```bash
python3 -I scripts/check-hosted-ci.py run /absolute/scratch/run.json /absolute/scratch/jobs.json PUSH_SHA
```

The checker requires completed successful run/job/required steps and matching API source/run identities.
It checks supplied records, not their authenticity; retain trusted GitHub URLs and retrieved records.
It does not fetch GitHub, certify checkout log contents, publish an Environment, or certify hooks, skills or reviews.
For a PR run also inspect checkout logs against its tested merge SHA.
Synthetic passing records establish the checker's behavior only.
Required-check branch protection remains an operator setting; this workflow does not change it.

A failed job with no executed steps is not a hosted test run or evidence of a failing suite.
Read its check annotation before attributing the failure.
When GitHub reports account billing or spending restrictions, CI acceptance is `BLOCKED`.
Only the account operator can correct GitHub Actions billing/spending problems.
The pending action is to correct the reported account restriction and then rerun the wrapper checks at the reviewed revision.
Do not hide the failed conclusion or replace it with local fixture results.

## Native repository acceptance boundary

Use [native skill delivery](native-skills.md) for wrapper-working-root selection, offline source checks and the operator-only fresh-task acceptance prompt.
The historical HOME preparation route failed with `OSError(30): Read-only file system` and is inapplicable to that managed runtime.
Require actual wrapper repository selection; report `WRAPPER_WORKING_ROOT_UNAVAILABLE` when unsupported.
An unmerged branch can be selected only if the UI supports it; otherwise the operator must decide merge/publication.
Preserve both checkouts and require provider inventory and dispatch separately from source bytes and explicit reads.
Inventory a target-rooted task separately; wrapper-rooted success does not establish global discovery.
Neither local suites nor hosted CI certify provider-native discovery or invocation.
Issue #30 remains open until independent runtime acceptance.
