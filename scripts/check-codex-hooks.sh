#!/usr/bin/env bash
set -euo pipefail

hooks=$(git rev-parse --path-format=absolute --git-path hooks)
for hook in pre-commit prepare-commit-msg commit-msg post-commit post-rewrite post-index-change reference-transaction; do
  if [ -x "$hooks/$hook" ] && [ -f "$hooks/$hook" ]; then
    printf 'FAIL COMMIT_HOOK_REVIEW_BOUNDARY: active %s may change the reviewed state; do not disable it to bypass this gate\n' "$hook" >&2
    exit 1
  fi
done
printf 'PASS no active mutation-capable commit hooks\n'
