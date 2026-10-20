# Shared workflow pack

The pinned upstream is `forever94yu/everything-codex-code` at `d468c521f1a76e7b05d446d805f6ad2afa8ed066`, package `1.7.0-codex.0`.
The MIT license is preserved in `config/codex/cloud-pack/LICENSE`.
The pack has 37 adapted skills, 14 role briefs, 21 explicit workflows and 24 rule files.
Source inventory counts are 58 skills, 14 agents, 35 commands, 11 hook scripts and 30 rule Markdown files.
No source inventory count describes native Cloud-loaded components.

`CATALOG.md` is the small startup router.
`catalog.json` is the complete lazy inventory with exact relative paths, inputs, dependencies and source mappings.
Use explicit requests such as “apply workflow tdd from the shared Codex pack”.
Read `workflow/tdd` with `pack-codex.py read`; it also emits the linked skill.
Roles can be passed to real native reviewers, but a role file is not a spawned agent.
The communication-triage role accepts supplied messages and drafts only; connected access and sending require separate authorization.
Swift and container workflows support inspection even when SDK/container execution is unavailable; their execution steps report the missing tools.

## Capabilities after publication

| Capability | Delivery contract | Additional acceptance |
| --- | --- | --- |
| Policy/catalog and pinned workflow reads from another task repository | Explicit wrapper paths; no target setup writes | Fresh task must have the wrapper and consume the start skill. |
| Planning, code inspection and domain review instructions | Readable in each task with valid delivery and file tools | Agent must read/apply the selected instructions and report output. |
| TDD, build, format, type and security checks | Explicit bounded workflow steps | Requires each target's actual configured tools and services. |
| Independent staged review | Actual native reviewers plus tree-bound evidence required | Native provider invocation/completion and approval; no self-approval fallback. |
| Commits with active project Git commit/index/reference hooks | Refused before hook execution to preserve the reviewed tree | Operator decision; never disable hooks to bypass the gate. |
| Native skill selectors | Not registered by this pack | Sibling checkout reads are not discovery; no selector claim. |
| Automatic hooks | Unavailable through this delivery | No shell-hook trust or lifecycle interception is provisioned. |
| Fork MCP servers | Unavailable through this delivery | Requires separate real provider registration and acceptance. |
| Connected GitHub tools | Real provider tools, separate from the fork | Inventory and successful authorized invocation in the current task. |

## Hook outcomes

Every upstream hook script is excluded from execution.
The following are explicit deterministic equivalents or unavailable behaviors; none is automatic.

| Upstream script | Classification and trigger |
| --- | --- |
| `session-start.js` | Explicit equivalent: operator start skill invokes session integrity/catalog check once. |
| `post-edit-format.js` | Explicit equivalent: run target's configured formatter/check during verification. |
| `post-edit-typecheck.js` | Explicit equivalent: run target's configured type checker during verification. |
| `check-console-log.js` | Explicit equivalent: inspect staged debug/log changes in the precommit review. |
| `post-edit-console-warn.js` | Explicit equivalent: inspect final debug/log changes during verification. |
| `doc-file-warning.js` | Explicit equivalent: verify documentation scope/indexes during review. |
| `pre-write-doc-warn.js` | Explicit equivalent: check documentation policy before requested doc edits. |
| `session-end.js` | Explicit equivalent: completion report with checks/limits; no persistent session store. |
| `pre-compact.js` | Unavailable lifecycle event; a conversational progress note has no automatic trigger. |
| `suggest-compact.js` | Unavailable automatic compaction observation. |
| `evaluate-session.js` | Unavailable automatic learning and persistent observer state. |

## Excluded source instructions

Each source file is named in `upstream.json` with its hash and status.
The rule distribution README and five shell-hook rules are excluded; their installation/event assumptions do not apply.
Installer/configuration examples are hashed for provenance but are not copied into executable configuration.

| Skill | Exclusion reason |
| --- | --- |
| `article-writing` | General publishing workflow is outside this coding pack. |
| `autonomous-loops` | Requires unsupported autonomous runtime/process orchestration. |
| `clickhouse-io` | Analytics-specific workflow deferred; no configured ClickHouse execution contract. |
| `configure-ecc` | Installer and user/project configuration writes violate the read-only delivery boundary. |
| `content-engine` | Social publishing workflow is outside this coding pack. |
| `continuous-learning-v2` | Persistent observer and instinct stores are not provisioned. |
| `continuous-learning` | Persistent observation hooks and learned user state are not provisioned. |
| `cost-aware-llm-pipeline` | External model routing, pricing and API budget state require a separate integration. |
| `foundation-models-on-device` | Requires an on-device Apple framework runtime unavailable in this Cloud execution contract. |
| `frontend-slides` | Presentation conversion and design workflow is outside this coding pack. |
| `investor-materials` | Fundraising documents are outside this coding pack. |
| `investor-outreach` | Fundraising communication is outside this coding pack. |
| `liquid-glass-design` | Apple-specific visual design requires SDK/device evidence outside this Cloud contract. |
| `market-research` | Market research and its data integrations are outside this coding pack. |
| `nutrient-document-processing` | Requires a separately authorized external document service and credentials. |
| `plankton-code-quality` | Assumes a separate automatic lint/hook installation; use explicit project verification instead. |
| `project-guidelines-example` | Example project policy must not override unrelated target repositories. |
| `security-scan` | Assumes an external scanner installation/integration; adapted security review uses only available project tools. |
| `skill-stocktake` | Assumes installed skill inventory and local skill-management state absent from this pack. |
| `strategic-compact` | Assumes compaction hooks and persistent session state; completion reports remain conversational. |
| `visa-doc-translate` | Sensitive document translation workflow is outside this coding pack. |

| Workflow template | Exclusion reason |
| --- | --- |
| `claw` | Requires persistent session/instinct stores or process managers not provisioned by this pack. |
| `evolve` | Requires persistent session/instinct stores or process managers not provisioned by this pack. |
| `instinct-export` | Requires persistent session/instinct stores or process managers not provisioned by this pack. |
| `instinct-import` | Requires persistent session/instinct stores or process managers not provisioned by this pack. |
| `instinct-status` | Requires persistent session/instinct stores or process managers not provisioned by this pack. |
| `multi-backend` | Requires external model orchestration unavailable through this read-only pack. |
| `multi-execute` | Requires external model orchestration unavailable through this read-only pack. |
| `multi-frontend` | Requires external model orchestration unavailable through this read-only pack. |
| `multi-plan` | Requires external model orchestration unavailable through this read-only pack. |
| `multi-workflow` | Requires external model orchestration unavailable through this read-only pack. |
| `pm2` | Requires persistent session/instinct stores or process managers not provisioned by this pack. |
| `projects` | Requires persistent session/instinct stores or process managers not provisioned by this pack. |
| `promote` | Requires persistent session/instinct stores or process managers not provisioned by this pack. |
| `sessions` | Requires persistent session/instinct stores or process managers not provisioned by this pack. |

## Maintenance

Review an intentional upstream pin change as source code, not a floating update.
Fetch the selected revision into a scratch checkout and verify its exact commit and package version.
Review source risk hits and topic projections, dependency statements and exclusions.
The builder reads exact Git blobs and runs no upstream code.
In a disposable wrapper checkout, start with an absent `cloud-pack` destination and run `python3 -I scripts/build-cloud-pack.py /absolute/pinned/upstream`.
Compare every derived diff, source hash and inventory change, then run all suites and real setup.
The builder refuses an existing destination instead of overwriting it.
Commit reviewed pin/hash changes only after staged independent review.
Environment publication and fresh-task acceptance remain separate operator actions.
