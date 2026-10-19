#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
bash "$root/scripts/test-attribution-guard.sh"
bash "$root/scripts/test-codex.sh"
bash "$root/scripts/test-codex-git-context.sh"
bash "$root/scripts/bootstrap-codex.sh"
bash "$root/scripts/session-check-codex.sh"
