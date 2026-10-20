#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$root/scripts/codex-common.sh"
python3 -I "$root/scripts/tests/test_cloud_pack.py"
