#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
bash "$root/scripts/verify-codex.sh"
printf 'Instructions: %s/current/AGENTS.md\n' "${HARNESS_STATE_DIR-/workspace/.harness-wrapper}"
printf 'Read the delivered policy and target repository AGENTS.md before starting the task.\n'
cat -- "$root/config/codex/cloud-pack/CATALOG.md"
printf 'WORKFLOW_CATALOG_CONSUMED=EMITTED_FOR_AGENT_READ; agent selection/application still requires task evidence\n'
