# my-harness-wrapper

Shared working policy and ECC workflows for native local Codex on Windows.
Python 3.12, native Git and a signed-in local Codex app or CLI are required.
PowerShell is the normal Windows shell; Bash, WSL, jq and administrator access are not required.

The upstream pin is forever94yu/everything-codex-code at d468c521f1a76e7b05d446d805f6ad2afa8ed066.
Full bodies are retained for 37 skills, 14 reviewers, 21 workflows and 24 rules.
The wrapper adapts native wiring and preserves source hashes/licenses.
It is a selected distribution, not the complete upstream plugin.

## Usage

Inspect the installation before applying it:

    py -3.12 -X utf8 -I scripts/codex-local.py install
    py -3.12 -X utf8 -I scripts/codex-local.py install --apply

Open a fresh local chat and invoke harness-workflow-plan or a native skill.
Trust new hook definitions through Codex before claiming automatic startup.
Existing config.toml, authentication, models, permissions and Git settings are preserved.
Target repositories need no harness files.

## Structure

| Path | Purpose |
| --- | --- |
| AGENTS.md | Wrapper development rules. |
| config/codex/AGENTS.md | Shared working policy. |
| config/codex/pack/ | Full-body pack and integrity manifest. |
| config/codex/upstream/ | Exact selected source bytes and license. |
| scripts/ | Native runtime, offline builder and tests. |
| docs/ | [Documentation index](docs/README.md). |

## Verification

    py -3.12 -X utf8 -I scripts/codex-local.py verify-source
    py -3.12 -X utf8 -I scripts/tests/test_local.py

GitHub Actions checks Windows and portable Linux behavior separately.
Fresh desktop/CLI acceptance and real-profile activation belong to the user.
The old implementations remain on feat/codex-cloud-harness and feat/claude-harness.
