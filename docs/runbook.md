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

Give reviewers the exact staged tree, relevant brief, task constraints and marked user-supplied verbatim hunks.
Wait for actual provider completion.
Record their real results in a private scratch JSON file and set `HARNESS_REVIEW_FILE` to its absolute path for the commit command:

```json
{
  "tree": "STAGED_TREE_ID",
  "source_commit": "CURRENT_HEAD",
  "provider": "native-codex",
  "implementer_id": "ACTUAL_IMPLEMENTER_ID",
  "reviews": [
    {
      "reviewer_id": "ACTUAL_NATIVE_REVIEWER_ID",
      "tree": "STAGED_TREE_ID",
      "roles": ["general"],
      "verdict": "APPROVED",
      "findings": [],
      "evidence": "Actual provider completion reference and verdict"
    }
  ]
}
```

Include entries covering every required role.
A reviewer ID must differ from the implementer ID.
Findings above LOW, stale trees/HEAD, missing roles or missing explicit approval block committing.
After editing staged bytes, obtain updated approvals for the new tree.
The JSON checker validates declared evidence consistency; it cannot authenticate provider identities or prove that a supplied transcript is genuine.
The agent must retain actual provider results and must not fabricate approvals.
Synthetic review records in tests establish local gate behavior only.

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
