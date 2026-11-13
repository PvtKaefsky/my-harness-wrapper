# Native and third-party skills

## Harness packages

The catalog generates 62 skill/workflow packages and 14 reviewer TOML definitions.
Names begin with harness-. Models inherit the parent.
Selected original bodies remain intact with a Codex adapter preface and native metadata.
Original bytes/license live under config/codex/upstream.
source-inventory.json retains the original audit/exclusion evidence.

Harness-authored bytes live under config/codex/authored/skills/.
config/codex/authored/source-inventory.json records their source commit and SHA-256 values.
Their packages use the Harness instructions heading and retain the same Codex adapter.
Their installed descriptions equal their source front-matter descriptions.
Existing packages retain their generated descriptions.

| Catalog ID | Installed skill |
| --- | --- |
| skill/python-property-model-tests | harness-python-property-model-tests |
| skill/edit-russian-technical-text | harness-edit-russian-technical-text |
| skill/quick-human-readable-review | harness-quick-human-readable-review |
| skill/python-fp-refactor | harness-python-fp-refactor |

Skills install in the user's .agents/skills; agents install in CODEX_HOME/agents.
The wrapper need not be the provider-selected target repository.
The wrapper-root duplicate experiment is removed.
Collisions and changed owned packages are preserved and reported.
Package counts are not provider discovery. Desktop and CLI need separate fresh-session evidence.

## Third-party delivery

config/codex/addons.json lists the upstream ponytail plugin and humanizer skill.
The upstream commands manage their files outside the harness artifact registry.

| Item | Codex form | Invocation or location |
| --- | --- | --- |
| ponytail | ponytail@ponytail plugin with skills and lifecycle hooks. | $ponytail:ponytail-review and the plugin's other namespaced skills. |
| humanizer | Third-party skill. Upstream ships no Codex plugin manifest. | The profile's .agents/skills/humanizer/SKILL.md. |

Ponytail's upstream default is full.
The harness writes no mode setting.
The operator trusts its two lifecycle hooks in /hooks before opening a fresh chat.
Doctor checks installed presence and cannot see hook trust.

## Instruction rank

The wrapper and target policy and native harness skills outrank ponytail and humanizer.
This rank covers their skills and hook-injected context in sessions and subagents.
Ponytail's comment rules give way to Code comments.
