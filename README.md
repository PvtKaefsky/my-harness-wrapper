# my-harness-wrapper

This repository delivers shared workflows and working policy for managed Codex Cloud.
The published Environment includes this checkout at `/workspace/my-harness-wrapper`.
Its start skill runs a read-only integrity check and directs the agent to the delivered policy and a lazy workflow catalog.
The selected workflow is read explicitly from the wrapper, including when the task concerns an unrelated attached repository.

The Cloud pack is a curated derivative of `forever94yu/everything-codex-code` at `d468c521f1a76e7b05d446d805f6ad2afa8ed066`, package `1.7.0-codex.0`.
It contains 37 skills, 14 role briefs, 21 explicit workflows and 24 rule files.
These counts describe readable instructions, not registered provider components.
The upstream MIT license, source paths, source hashes, exclusion inventory and derivative hashes accompany the pack.

Setup writes only wrapper-owned delivery state, normally `/workspace/.harness-wrapper`.
It runs no upstream installer and writes no user, managed configuration, plugin-cache or target-repository files.
A missing wrapper checkout is a dependency failure.
A matching checksum proves matching bytes, not agent use or provider acceptance.

## Usage

After the operator publishes the Environment, ask: “apply workflow plan from the shared Codex pack”.
The agent reads verified instructions through:

```bash
python3 -I /workspace/my-harness-wrapper/scripts/pack-codex.py read workflow/plan
```

Project-local `AGENTS.md` and higher-priority instructions remain authoritative.
Independent native reviewers must actually run before commits; role files do not create reviewers.
The pack installs no automatic hooks, native skill selectors or MCP servers.

## Structure

| Path | Purpose |
| --- | --- |
| `AGENTS.md` | Wrapper development policy. |
| `config/codex/` | Shared policy, version, manifest anchor and audited workflow pack. |
| `env/setup-codex.sh` | Complete offline checks and delivery setup. |
| `scripts/` | Integrity, startup, explicit safety gates and isolated regression suites. |
| `docs/` | [Documentation index](docs/README.md). |

Use the verbatim Environment fields and fresh-task acceptance steps in [Codex delivery](docs/codex.md).
A merged PR does not publish an Environment.

GitHub Actions runs the wrapper suites and isolated full setup on pushes and pull requests.
Use [the runbook](docs/runbook.md) to inspect actual hosted job steps and external billing blockers.
Report each Cloud capability with its own [evidence state](docs/codex.md#capability-evidence).
