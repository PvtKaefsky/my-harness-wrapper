#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$root/scripts/codex-common.sh"
exec python3 -B "$root/scripts/tests/test_codex_ecc_skill.py"
