#!/bin/bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL=$ROOT/plugins/my-harness/skills/repository-setup
T=$SKILL/templates
LAYOUTS=$ROOT/docs/repository-layouts.md
fails=0

expect() {
  local verdict=pass
  [ "$2" = "$3" ] || { verdict=FAIL; fails=$((fails + 1)); }
  echo "$1 -> expected [$2], actual [$3], $verdict"
}

WORK=$(mktemp -d) || { echo "mktemp -d -> exit=$?, not run"; echo "fail -> not run"; exit 1; }
trap 'rm -rf -- "$WORK"' EXIT

named=$( { grep -h -o '`templates/[^`]*`' "$SKILL/SKILL.md" "$LAYOUTS" | tr -d '`'
  awk '/^## /{ on = ($0 == "## Documentation roles") } on && /^\| `/ { n = split($0, c, "|"); print "templates/" c[n - 1] }' "$LAYOUTS" | tr -d '` ' ; } | sort -u)
for path in $named; do
  expect "template $path named by SKILL.md or docs/repository-layouts.md exists" yes "$([ -e "$SKILL/$path" ] && echo yes || echo no)"
done
expect "template paths named" yes "$([ "$(printf '%s\n' "$named" | grep -c .)" -ge 10 ] && echo yes || echo no)"

unlisted=$(jq -r '(.families[] | select(.paths) | .labels | map(.name)) as $l | .families[] | select(.paths) | .paths[] | select(. as $p | $l | index($p) | not)' "$T/github/labels.json" 2>&1)
expect "github/labels.json parses and every area path maps to a listed label" "" "$unlisted"

commit() {
  git -C "$1" -c core.autocrlf=false add -A && git -C "$1" -c user.name=Fixture -c user.email=fixture@example.com commit -q -m fixture
}

checks() {
  rm -f "$WORK/checks.jsonl"
  CHECKS_WORK=$1 CHECKS_OUT=$WORK/checks.jsonl bash "$T/probe/checks.sh" > "$WORK/checks.log" 2>&1
}

status() {
  jq -r --arg id "$1" 'select(.id == $id) | .status' "$WORK/checks.jsonl" 2>/dev/null | tr -d '\r'
}

R=$WORK/repo
mkdir -p "$R/docs/specs" "$R/tests"
git -C "$R" init -q
printf '# Fixture\n\n## Quick Start\n\n```sh quickstart\ntest -f marker.txt\necho ok\n```\n' > "$R/README.md"
touch "$R/marker.txt"
sed 's/<PREFIX>/RATELIMIT/g' "$T/docs/specs/component.md" > "$R/docs/specs/ratelimit.md"
printf 'def test_ratelimit_1_allows_first_request():\n    pass\n\n\ndef test_ratelimit_2_rejects_burst():\n    pass\n' > "$R/tests/test_ratelimit.py"
commit "$R"

checks "$R"
expect "quickstart on a fixture whose Quick Start passes" pass "$(status quickstart)"
expect "spec-trace on a fixture whose scenarios each name a test" pass "$(status spec-trace)"

sed -i 's/test -f marker.txt/test -f missing.txt/' "$R/README.md"
commit "$R"
checks "$R"
expect "quickstart with the README command broken" fail "$(status quickstart)"

printf '\n```sh quickstart-offline\ntest -f marker.txt\n```\n' >> "$R/README.md"
commit "$R"
checks "$R"
expect "quickstart runs the offline block where README.md has one" pass "$(status quickstart)"

git -C "$R" rm -q marker.txt && commit "$R" && touch "$R/marker.txt"
checks "$R"
expect "quickstart ignores an untracked file in the working tree" fail "$(status quickstart)"

sed -i 's/test_ratelimit_2_rejects_burst/test_rejects_burst/' "$R/tests/test_ratelimit.py"
commit "$R"
checks "$R"
expect "spec-trace with a scenario's test renamed" fail "$(status spec-trace)"
expect "spec-trace names the ID without a test" yes "$(grep -q -x 'spec-trace -> RATELIMIT-2 names no test' "$WORK/checks.log" && echo yes || echo no)"

sed -i 's/test_ratelimit_1_allows_first_request/test_ratelimit_10_allows_first_request/' "$R/tests/test_ratelimit.py"
commit "$R"
checks "$R"
expect "spec-trace does not match RATELIMIT-1 to a test named for RATELIMIT-10" yes "$(grep -q -x 'spec-trace -> RATELIMIT-1 names no test' "$WORK/checks.log" && echo yes || echo no)"

git -C "$R" checkout -q HEAD~2 -- tests/test_ratelimit.py
sed -i 's/^| RATELIMIT-2 |/| RATELIMIT-1 |/' "$R/docs/specs/ratelimit.md"
commit "$R"
checks "$R"
expect "spec-trace with a scenario ID repeated" fail "$(status spec-trace)"
expect "spec-trace names the repeated ID" yes "$(grep -q -x 'spec-trace -> RATELIMIT-1 repeated' "$WORK/checks.log" && echo yes || echo no)"

sed -i '1s/.*/Status: rejected/' "$R/docs/specs/ratelimit.md"
commit "$R"
checks "$R"
expect "spec-trace skips a spec whose status is not active" pass "$(status spec-trace)"

PY=
for candidate in python3 python; do
  if "$candidate" -c 'import ast, unittest' > /dev/null 2>&1; then PY=$candidate; break; fi
done
echo "python -> ${PY:-not found}"
if [ -z "$PY" ]; then
  echo "skipped: architecture-test pass, forbidden import, missing path; python is not found"
else
  A=$WORK/arch
  mkdir -p "$A/tests" "$A/src/app/domain" "$A/src/app/adapters"
  sed 's/<package>/app/g' "$T/architecture-test/tests/test_architecture.py" > "$A/tests/test_architecture.py"
  touch "$A/src/app/__init__.py" "$A/src/app/domain/__init__.py" "$A/src/app/adapters/__init__.py" "$A/src/app/adapters/db.py"
  printf 'import json\nfrom . import values\n' > "$A/src/app/domain/model.py"
  touch "$A/src/app/domain/values.py"
  arch() {
    (cd "$A" && "$PY" -m unittest discover -s tests > "$WORK/arch.log" 2>&1) && echo pass || echo fail
  }
  expect "architecture test on a fixture that keeps its rule" pass "$(arch)"
  printf 'from ..adapters import db\n' >> "$A/src/app/domain/model.py"
  expect "architecture test with a relative import the rule forbids" fail "$(arch)"
  printf 'import json\n' > "$A/src/app/domain/model.py"
  sed -i 's#"src/app/adapters"#"src/app/missing"#' "$A/tests/test_architecture.py"
  expect "architecture test with a rule naming a missing path" fail "$(arch)"
  expect "architecture test names the missing path" yes "$(grep -q 'src/app/missing named by a rule does not exist' "$WORK/arch.log" && echo yes || echo no)"
fi

echo "fail -> $fails"
[ "$fails" -eq 0 ]
