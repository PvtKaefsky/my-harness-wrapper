#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$root/scripts/codex-common.sh"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export GIT_CONFIG_GLOBAL="$work/global-config"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME='Environment Identity'
export GIT_AUTHOR_EMAIL=environment@example.invalid
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
git config --global user.name 'Global Fallback'
git config --global user.email fallback@example.invalid
git init -q "$work/repository"
cd -- "$work/repository"
printf 'staged contents\n' > file.txt
git add file.txt
before=$(sha256sum < .git/index)
checker="$root/scripts/check-codex-identity.sh"
committer="$root/scripts/commit-codex.sh"
passes=0

expect_status() {
  local label=$1 expected=$2 actual
  shift 2
  if "$@" > "$work/output" 2>&1; then actual=0; else actual=$?; fi
  if [ "$actual" -ne "$expected" ]; then
    printf 'FAIL %s: expected exit=%s, actual=%s\n' "$label" "$expected" "$actual" >&2
    cat -- "$work/output" >&2
    exit 1
  fi
  passes=$((passes + 1))
  printf 'PASS %s\n' "$label"
}

expect_status 'valid identity passes despite different global settings' 0 bash "$checker"
for variable in GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL; do
  expect_status "$variable unset blocks the commit" 1 env -u "$variable" bash "$committer" -m blocked
  expect_status "$variable empty blocks the commit" 1 env "$variable=" bash "$committer" -m blocked
  expect_status "$variable whitespace-only blocks the commit" 1 env "$variable= " bash "$committer" -m blocked
done
expect_status 'all missing identity variables block global fallback' 1 env \
  -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
  bash "$committer" -m blocked
expect_status 'different role identities block the commit' 1 env GIT_COMMITTER_EMAIL=different@example.invalid \
  bash "$committer" -m blocked
expect_status 'Git-normalized identity blocks the commit' 1 env \
  GIT_AUTHOR_NAME=$'Environment\nIdentity' GIT_COMMITTER_NAME=$'Environment\nIdentity' \
  bash "$committer" -m blocked
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  printf 'FAIL rejected commit changed HEAD\n' >&2
  exit 1
fi
[ "$before" = "$(sha256sum < .git/index)" ] || { printf 'FAIL rejected commit changed index\n' >&2; exit 1; }
printf 'PASS rejected commits leave HEAD unborn and the index unchanged\n'
passes=$((passes + 1))
export HARNESS_REVIEW_FILE="$work/review.json"
python3 -I - "$HARNESS_REVIEW_FILE" <<'PY'
import json
import subprocess
import sys
tree = subprocess.check_output(['git', 'write-tree'], text=True).strip()
json.dump({'tree': tree, 'source_commit': '', 'provider': 'native-codex', 'implementer_id': 'fixture-author', 'reviews': [{'reviewer_id': 'fixture-reviewer', 'tree': tree, 'verdict': 'APPROVED', 'findings': [], 'roles': ['general'], 'evidence': 'Synthetic local identity-test fixture, not provider acceptance.'}]}, open(sys.argv[1], 'w'))
PY
expect_status 'valid identity permits the commit' 0 env GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false bash "$committer" -m 'test: guarded commit'
expected="$GIT_AUTHOR_NAME <$GIT_AUTHOR_EMAIL>"
[ "$(git show -s --format='%an <%ae>')" = "$expected" ] || { printf 'FAIL unexpected commit author\n' >&2; exit 1; }
[ "$(git show -s --format='%cn <%ce>')" = "$expected" ] || { printf 'FAIL unexpected commit committer\n' >&2; exit 1; }
printf 'PASS committed author and committer use the environment identity\n'
passes=$((passes + 1))
python3 -I - "$HARNESS_REVIEW_FILE" <<'PY'
import json
import subprocess
import sys
p = sys.argv[1]
with open(p) as stream:
    record = json.load(stream)
record['source_commit'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
with open(p, 'w') as stream:
    json.dump(record, stream)
PY
expect_status 'underlying Git failure is preserved' 1 env GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false bash "$committer" -m 'test: nothing staged'
grep -q 'nothing to commit' "$work/output" || { printf 'FAIL expected actual Git failure\n' >&2; exit 1; }
printf 'PASS %s identity guard checks\n' "$passes"
