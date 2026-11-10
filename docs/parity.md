# Claude parity

Comparison source: feat/claude-harness at 53f08f306d4784940cc9c7b48d0d2372accf0a12.
Its bootstrap delivers CLAUDE.md, merges settings and installs affaan-m/ECC.

| Claude behavior | Local Codex equivalent | Necessary adaptation |
| --- | --- | --- |
| Shared CLAUDE.md | Managed AGENTS.md section | Discovery and project precedence. |
| ECC skills/slash commands | Full selected native skill/workflow bodies | Namespaced skill invocation. |
| Reviewer Markdown | Full selected roles in TOML | Native agent schema and completion. |
| Startup check | SessionStart hook | Codex event format and explicit trust. |
| Prompt reminder | UserPromptSubmit hook | Native payload/output. |
| Attribution/raw commit guard | PreToolUse hook | Tested structured bodies and direct Git commands only. |
| Independent staged review | Native agents and guarded commit | Real HEAD/tree-bound provider evidence. |
| No attribution | Explicit message/body checks | Report actual coverage. |
| Environment identity | Approved effective local Git identity | Preserve existing Git settings. |
| Bootstrap manifest | Immutable local release/manifest | No snapshot/republish boundary. |

Repository creation and layout comparison source: main's PR #68 merge at 32a3506e5b2f710a0ddc1c1e2c9407b29d0bcec7.

| Claude behavior | Local Codex equivalent | Necessary adaptation |
| --- | --- | --- |
| Repository creation | User-requested local initialization on main, README.md first, empty private GitHub repository and later pull requests | The first commit uses the guarded commit and native unborn review; refusal stops the session. No hooks, Git configuration, protection or repository settings are changed. |
| Repository layout | Shared repository-layouts.md, single-application or grouped apps/ and libs/, existing layouts preserved | The installer delivers the unchanged document in each release; AGENTS.md renders its path from {{HARNESS_ROOT}}. |

Delegation comparison source: main's PR #74 merge at 88d6fe688371a95235dc1541d51d1f675ecda3e0.

| Claude behavior | Local Codex equivalent | Necessary adaptation |
| --- | --- | --- |
| Task decomposition and implementation delegation | Native collaboration agents use verified pack roles or the hashed executor brief in each installed release | AGENTS.md renders {{HARNESS_ROOT}}/docs/native-delegation.md. Native tools provide inventory and actual dispatch/completion references. Attempts last at most thirty minutes. Completion waits last at most sixty seconds. The coordinator integrates owned-file edits, then uses native review and guarded commits. Delegation records are not guard-enforced. |

The obsolete upstream installer/config template is not run or copied.
It selects old models/config fields and unrelated MCP defaults.
Automatic learning, tmux-only execution, external services and upstream executable hooks are not silently enabled.
Explicit guards remain the commit boundary; callbacks protect only tested supported events.
The selected port claims no complete ECC runtime parity or enforcement outside Codex.
