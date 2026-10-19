#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
bash "$root/scripts/verify-codex.sh"
printf 'Instructions: %s/current/AGENTS.md\n' "${HARNESS_STATE_DIR-/workspace/.harness-wrapper}"
printf 'Read this file and the target repository AGENTS.md before starting the task.\n'
