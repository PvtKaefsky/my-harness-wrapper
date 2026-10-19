#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -f "$1" ] || [ ! -r "$1" ]; then
  printf 'Usage: bash scripts/check-codex-attribution.sh BODY_FILE\n' >&2
  exit 1
fi
pattern='^[[:space:]]*(Co-Authored-By|Claude-Session|Codex-Session):|Generated (with|by)[[:space:]]+\[?(Claude Code|Codex|OpenAI)|claude\.ai/code/session_|chatgpt\.com/(codex|c)/'
if LC_ALL=C grep -aiEq -- "$pattern" "$1"; then
  printf 'FAIL attribution: remove author trailers, generated-by footers, and session links\n' >&2
  exit 2
else
  status=$?
  [ "$status" -eq 1 ] || { printf 'FAIL attribution: could not read the body\n' >&2; exit 1; }
fi
printf 'PASS attribution body\n'
