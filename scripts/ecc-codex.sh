#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/codex-common.sh"
case "${1-}" in setup|status|skill-setup|skill-status) ;; *) codex_fail 'expected ECC setup, status, skill-setup or skill-status'; exit 1 ;; esac
[ "$#" -eq 1 ] || { codex_fail 'unexpected ECC arguments'; exit 1; }
codex_require_tools
codex_validate_path
codex_validate_state
if [ "$1" = setup ] || [ "$1" = skill-setup ]; then
  exec 9<> "$CODEX_WRAPPER_STATE/.lock"
  flock -w 10 -x 9
else
  exec 9< "$CODEX_WRAPPER_STATE/.lock"
  flock -w 10 -s 9
fi
codex_current_release
codex_validate_release
exec python3 "$CODEX_WRAPPER_ROOT/scripts/ecc-codex.py" "$1" "$CODEX_WRAPPER_STATE" \
  "$(git -C "$CODEX_WRAPPER_ROOT" rev-parse --verify 'HEAD^{commit}')" "$(codex_source_digest)"
