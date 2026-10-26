# Native staged review protocol

This procedure uses available Codex collaboration agents and verified role briefs.
It registers no agents, tool-event hooks or provider integrations.
The coordinator invokes the provider's actual collaboration tools; shell scripts only check local evidence consistency.
JSON cannot cryptographically authenticate provider identity, dispatch, completion or transcript provenance.
Retain the actual provider messages separately and report that limitation with acceptance results.

## Selection and bounds

1. Read applicable project rules and inspect `git diff --cached --stat` and the complete staged diff, including deletions and surrounding callers.
2. Run `codex-local.py review-requirements` in the task repository and record its `source_commit` and `tree`.
An unborn repository uses an empty source commit and `git diff --cached` for inspection; wrapper development uses the checked live main.
3. Add project-required language/domain roles to `required_roles`; the suffix/path mapping is a minimum, not exhaustive project analysis.
4. Inventory current native collaboration tools and independent agent availability before dispatch.
5. Select agents with the required expertise and pass verified role instructions; role text never creates an agent.
6. Name selected roles, extra project roles, inapplicable roles with reasons, and unavailable roles before review.

| Gate role | Verified brief | Selection |
| --- | --- | --- |
| `general` | `role/code-reviewer` | Every change, including Markdown and JSON. |
| `python` | `role/python-reviewer` | Changed or deleted Python files. |
| `shell` | `role/code-reviewer` | Changed or deleted shell files; explicitly request shell semantics review. |
| `security` | `role/security-reviewer` | Changes under `env/`, `scripts/` or `config/codex/`, plus project security rules. |
| `go` | `role/go-reviewer` | Changed or deleted Go files. |
| `database` | `role/database-reviewer` | Changed or deleted SQL files, migrations or project database rules. |
| `architecture`, `build`, `docs`, `e2e`, `go-build`, `planning`, `refactor`, `tdd`, `communication` | The corresponding verified `role/*` brief from the catalog | Project/task rules and actual staged scope. |

No dedicated shell or UI brief is shipped.
Use the general brief with explicit domain scope when it covers the required expertise.
An absent native agent with required expertise is `BLOCKED`; do not invent a role registration or substitute self-review.
An unsupported gate role fails `INDEPENDENT_REVIEW_ROLE_UNSUPPORTED`; resolve the mapping within project rules before committing.
One independent agent may cover several roles when each brief and domain is explicitly assigned and its completion names every role.
Use distinct reviewers for distinct review entries; duplicate reviewer, dispatch or completion identifiers fail closed.

The task has at most five review rounds, including rounds invalidated by changed staged bytes.
Each role has at most two dispatch attempts per round; retry once only after an explicit provider failure or terminal unavailable result.
Each round has a ten-minute completion deadline, observed with bounded provider completion waits of at most sixty seconds each.
A deadline or exhausted retry budget leaves that review `BLOCKED`, not approved.
Do not launch a replacement while the original dispatch is still running.
After the fifth round, leave changes uncommitted and request a user decision on unresolved findings.
A user decision does not fabricate missing approval or bypass the guarded commit gate.

## Dispatch packet

Read `workflow/code-review` and every selected `role/ID` through the verified pack reader.
Give every reviewer the following packet in the native provider invocation:

```text
Repository: absolute task repository path
Source HEAD: exact source_commit
Staged tree: exact tree
Round: 1..5; attempt: 1..2
Scope and risk: concrete task constraints and changed behavior
Assigned gate roles: explicit list
Verified briefs: exact IDs, emitted hashes and full verified instruction text
Project rules: applicable AGENTS.md and relevant constraints
User verbatim hunks: marked exact hunks, or NONE (task prose is not a code hunk)
Inspection: git diff SOURCE_HEAD STAGED_TREE; git show STAGED_TREE:path
Checks: actual commands/results supplied by implementer; independently verify as needed
Access: read-only; do not change files, index, refs, identity, hooks or settings
Response: source HEAD, staged tree, roles, APPROVED or NOT_APPROVED,
          findings with severity/path/evidence, inspected paths and executed checks
```

Confirm `git rev-parse HEAD` and `git write-tree` still match the packet before dispatch.
Review immutable tree blobs and surrounding code from that tree; working files can contain unstaged changes.
Dispatch independent reviewers in one parallel batch where supported.
Record actual agent identity and dispatch reference returned by the provider.
Record an existing-agent task invocation separately from agent availability.
Wait for provider completion notifications or completion tools and retain the actual final response.
An agent ID, quiet file, elapsed timer or empty findings list does not establish completed review or approval.
Do not invent a completion identifier; use the provider's task/completion message reference, or leave approval blocked if none is available.

## Status and receipts

| Status | Required observation | Still unproven |
| --- | --- | --- |
| `NATIVE_AGENT_AVAILABLE` | Current provider exposes a usable independent agent/tool. | No task was dispatched or reviewed. |
| `REVIEW_DISPATCHED` | Provider accepted the exact packet and returned an invocation reference. | No completion or approval. |
| `REVIEW_COMPLETED` | Actual terminal provider response with completion reference. | Verdict may be blocked or negative. |
| `TREE_APPROVED` | Every required role explicitly approves the same HEAD/tree with no findings above LOW. | Local JSON consistency cannot authenticate participation or guarantee commit success. |
| `GUARDED_COMMIT_PASSED` | Explicit `codex-local.py commit` returned zero after Git committed. | Hosted CI and fresh local-session acceptance remain separate. |

Save actual completion references and explicit verdicts in a private scratch record.
The `provider_receipt` is a structured transcription of actual provider evidence, not an authentication token.
Its fields must match the containing review and source HEAD exactly.
The gate requires schema version 2 and rejects older unstructured records.

```json
{
  "schema_version": 2,
  "source_commit": "EXACT_HEAD",
  "tree": "EXACT_STAGED_TREE",
  "provider": "native-codex",
  "implementer_id": "ACTUAL_IMPLEMENTER_ID",
  "required_roles": ["general"],
  "reviews": [{
    "reviewer_id": "ACTUAL_INDEPENDENT_AGENT_ID",
    "tree": "EXACT_STAGED_TREE",
    "roles": ["general"],
    "verdict": "APPROVED",
    "findings": [],
    "evidence": "Actual provider final response reference and verdict",
    "provider_receipt": {
      "provider": "native-codex",
      "status": "REVIEW_COMPLETED",
      "reviewer_id": "ACTUAL_INDEPENDENT_AGENT_ID",
      "source_commit": "EXACT_HEAD",
      "tree": "EXACT_STAGED_TREE",
      "roles": ["general"],
      "verdict": "APPROVED",
      "findings": [],
      "dispatch_id": "ACTUAL_PROVIDER_TASK_REFERENCE",
      "completion_id": "ACTUAL_PROVIDER_COMPLETION_REFERENCE",
      "transcript_ref": "Retained actual provider response location or message reference"
    }
  }]
}
```

Only copy verdicts actually returned by the reviewer.
Blocked responses, missing references, self-review, unsupported roles, duplicate identities, mismatched receipts and findings above LOW block committing.
A changed HEAD or staged tree invalidates the record; re-stage and obtain fresh approvals within the round budget.
Unstaged bytes are outside the approved tree and must not be described as reviewed.
Stop edits and other index/ref writers during the explicit gate; these scripts do not provide a repository-wide concurrency lock.
The gate checks HEAD/tree again after receipt validation, but cannot exclude an external writer racing Git after that check.
Run the guarded commit with the actual record, then require executed green hosted wrapper CI for the committed revision.
A pre-run billing/policy failure is an operator blocker and cannot be waived by local tests.

## Acceptance

Report source HEAD, reviewed tree, actual reviewer/task/completion IDs and verdicts, selected and unavailable roles, suite counts, isolated setup and guarded commit output.
Report deletion RED/GREEN for receipt consumption separately from genuine provider approval.
Synthetic records exercise rejection and acceptance branches in disposable repositories only.
Current-task staged reviews do not prove fresh local-session discovery or hook invocation.
Record fresh desktop and CLI evidence separately or report acceptance pending.
Explicit Git guards do not establish automatic Codex callback execution.
