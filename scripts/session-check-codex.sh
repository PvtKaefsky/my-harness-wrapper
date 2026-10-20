#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
delivery=0
bash "$root/scripts/verify-codex.sh" || delivery=$?
printf 'Instructions: %s/current/AGENTS.md\n' "${HARNESS_STATE_DIR-/workspace/.harness-wrapper}"
printf 'Read this file and the target repository AGENTS.md before starting the task.\n'
readiness=0
bash "$root/scripts/ecc-codex.sh" status || readiness=$?
if [ "$readiness" -ne 0 ] && [ "$readiness" -ne 2 ]; then
  printf 'ECC NOT READY: setup evidence could not be safely checked; ordinary project work blocked\n'
fi
if [ "$delivery" -ne 0 ]; then exit "$delivery"; fi
exit "$readiness"
