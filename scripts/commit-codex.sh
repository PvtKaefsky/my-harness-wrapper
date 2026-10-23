#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
bash "$root/scripts/check-codex-hooks.sh"
bash "$root/scripts/check-codex-identity.sh"
bash "$root/scripts/check-codex-preflight.sh"
command -v python3 >/dev/null || { printf 'FAIL dependency: python3 is unavailable\n' >&2; exit 1; }
python3 -I "$root/scripts/check-codex-commit-args.py" "$@"
python3 -I "$root/scripts/check-codex-review.py"
git commit "$@"
printf 'GUARDED_COMMIT_PASSED commit=%s\n' "$(git rev-parse HEAD)"
