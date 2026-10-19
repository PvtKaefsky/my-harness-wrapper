#!/usr/bin/env bash
set -euo pipefail

failed=0
for variable in GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL; do
  value=${!variable-}
  if [[ ! "$value" =~ [^[:space:]] ]]; then
    printf 'FAIL identity: %s must be set and nonempty in the environment\n' "$variable" >&2
    failed=1
  fi
done
[ "$failed" -eq 0 ] || exit 1

for role in AUTHOR COMMITTER; do
  name="GIT_${role}_NAME"
  email="GIT_${role}_EMAIL"
  expected="${!name} <${!email}>"
  if ! actual=$(git var "GIT_${role}_IDENT" 2>/dev/null); then
    printf 'FAIL identity: Git could not resolve %s\n' "$role" >&2
    exit 1
  fi
  if [[ "$actual" != "$expected "* ]]; then
    printf 'FAIL identity: Git %s does not match %s and %s\n' "$role" "$name" "$email" >&2
    exit 1
  fi
done
if [ "$GIT_AUTHOR_NAME" != "$GIT_COMMITTER_NAME" ] || [ "$GIT_AUTHOR_EMAIL" != "$GIT_COMMITTER_EMAIL" ]; then
  printf 'FAIL identity: author and committer must name the same environment identity\n' >&2
  exit 1
fi
printf 'PASS Git author and committer match the required environment identity\n'
