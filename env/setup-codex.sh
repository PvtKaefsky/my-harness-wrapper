#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
bash "$root/scripts/test-attribution-guard.sh"
bash "$root/scripts/test-codex.sh"
bash "$root/scripts/test-codex-git-context.sh"
bash "$root/scripts/test-codex-identity.sh"
bash "$root/scripts/test-codex-ecc.sh"
bash "$root/scripts/bootstrap-codex.sh"
if bash "$root/scripts/ecc-codex.sh" setup; then
  printf 'ECC native setup probe completed; task skill acceptance remains UNVERIFIED\n'
else
  result=$?
  [ "$result" -eq 2 ] || exit "$result"
  printf 'ECC NOT READY; diagnostic-only bootstrap exception; ordinary project work blocked\n'
fi
bash "$root/scripts/verify-codex.sh"
