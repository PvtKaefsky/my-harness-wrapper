#!/usr/bin/env bash
set -euo pipefail

git diff --cached --check || { printf 'FAIL STAGED_DIFF_CHECK_FAILED\n' >&2; exit 1; }
printf 'PASS staged diff whitespace check\n'
