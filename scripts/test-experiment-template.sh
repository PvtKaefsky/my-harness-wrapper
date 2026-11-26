#!/bin/bash
set -uo pipefail

TEMPLATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/my-harness/skills/repository-setup/templates/python-experiment"
fails=0

PY=
for candidate in python3 python; do
  if "$candidate" -c 'import hydra, dotenv' > /dev/null 2>&1; then PY=$candidate; break; fi
done
echo "python with hydra-core and python-dotenv -> ${PY:-not importable}"
if [ -z "$PY" ]; then
  echo "skipped: env-example, completed, failed, interrupted, dirty, secrets, make experiment lookup; python with hydra-core and python-dotenv is not importable"
  echo "fail -> 0"
  exit 0
fi
echo "test -d $TEMPLATE -> $([ -d "$TEMPLATE" ] && echo yes || echo no)"
[ -d "$TEMPLATE" ] || { echo "fail -> not run"; exit 1; }

WORK=$(mktemp -d) || { echo "mktemp -d -> exit=$?, not run"; exit 1; }
trap 'rm -rf -- "$WORK"' EXIT
FIX=$WORK/fixture
cp -a "$TEMPLATE/." "$FIX"
mv "$FIX/src/package" "$FIX/src/fixturepkg"
grep -rl '<package>' "$FIX" | xargs sed -i 's/<package>/fixturepkg/g'
mkdir -p "$FIX/src/fixturepkg/hyp_9_fixture" "$FIX/research/HYP-9-fixture/experiments"
cat > "$FIX/src/fixturepkg/hyp_9_fixture/task.py" << 'EOF'
"""HYP-9: fixture task for scripts/test-experiment-template.sh."""

import time
from pathlib import Path


def run(seed, data_dir, run_dir, mode):
    """Raise for mode raise; for mode wait, touch run_dir/started and sleep."""
    if mode == "raise":
        raise RuntimeError("fixture failure")
    Path(run_dir, "started").touch()
    time.sleep(60)
EOF
for mode in raise wait; do
  printf 'task:\n  _target_: fixturepkg.hyp_9_fixture.task.run\n  mode: %s\n' "$mode" > "$FIX/research/HYP-9-fixture/experiments/$mode.yaml"
done
printf 'max_tokens: 512\nmaxTokens: 256\nprivate_key: fixture-private-key\napi-key: fixture-hyphen-key\nclientSecret: fixture-camel-secret\ndb:\n  host: db.local\n  password: fixture-db-password\nservices:\n  - name: tracker\n    access_token: fixture-list-token\n' \
  > "$FIX/research/HYP-9-fixture/experiments/secrets.yaml"
printf 'DATA_DIR=/fixture/data\nAPI_TOKEN=fixture-api-token\n' > "$FIX/.env"
cp "$FIX/research/HYP-1-example/experiments/baseline.yaml" "$FIX/research/HYP-9-fixture/experiments/baseline.yaml"
git -C "$FIX" init -q && git -C "$FIX" add -A &&
  git -C "$FIX" -c user.name=Fixture -c user.email=fixture@example.com commit -q -m fixture ||
  { echo "git init and commit $FIX -> failed, not run"; exit 1; }
HEAD_SHA=$(git -C "$FIX" rev-parse HEAD)

expect() {
  local verdict=pass
  [ "$2" = "$3" ] || { verdict=FAIL; fails=$((fails + 1)); }
  echo "$1 -> expected [$2], actual [$3], $verdict"
}

field() {
  "$PY" -c 'import json, sys; print(json.dumps(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$RUN/metadata.json" "$1"
}

start() {
  rm -rf "$FIX/runs"
  (cd "$FIX" && PYTHONPATH=src exec "$PY" -m fixturepkg.run "research/$1.yaml") > "$WORK/run.log" 2>&1 &
  PID=$!
}

finish() {
  wait "$PID"
  CODE=$?
  RUN=$(echo "$FIX"/runs/*)
  [ "$CODE" -eq 0 ] || tail -n 3 "$WORK/run.log"
}

has() {
  grep -q -F -- "$2" "$1" && echo yes || echo no
}

missing=$(grep -o 'oc.env:[A-Z0-9_]*' "$FIX/conf/config.yaml" | cut -d: -f2 | while read -r name; do
  grep -q "^$name=" "$FIX/.env.example" || printf '%s ' "$name"
done)
expect 'env-example: every oc.env name in conf/config.yaml is listed in .env.example' '' "$missing"

start HYP-1-example/experiments/baseline; finish
expect 'completed: exit code' 0 "$CODE"
expect 'completed: config.yaml written' yes "$([ -f "$RUN/config.yaml" ] && echo yes || echo no)"
expect 'completed: config.yaml holds the override seed' yes "$(has "$RUN/config.yaml" 'seed: 1')"
expect 'completed: status' '"completed"' "$(field status)"
expect 'completed: commit' "\"$HEAD_SHA\"" "$(field commit)"
expect 'completed: seed' 1 "$(field seed)"
expect 'completed: dirty' false "$(field dirty)"
expect 'completed: task wrote metrics.json into the run directory' yes "$([ -f "$RUN/metrics.json" ] && echo yes || echo no)"

start HYP-9-fixture/experiments/raise; finish
expect 'failed: exit code is not 0' yes "$([ "$CODE" -ne 0 ] && echo yes || echo no)"
expect 'failed: status' '"failed"' "$(field status)"
expect 'failed: dirty after an earlier run' false "$(field dirty)"

case $(uname -s) in
  MINGW* | MSYS* | CYGWIN*)
    echo "skipped: interrupted; $(uname -s) cannot deliver SIGTERM to a native Windows python"
    ;;
  *)
    start HYP-9-fixture/experiments/wait
    for _ in $(seq 100); do
      compgen -G "$FIX/runs/*/started" > /dev/null && break
      sleep 0.2
    done
    kill -TERM "$PID"
    finish
    expect 'interrupted: exit code is not 0' yes "$([ "$CODE" -ne 0 ] && echo yes || echo no)"
    expect 'interrupted: status' '"interrupted"' "$(field status)"
    ;;
esac

echo >> "$FIX/README.md"
start HYP-1-example/experiments/baseline; finish
git -C "$FIX" checkout -q -- README.md || fails=$((fails + 1))
expect 'dirty: exit code' 0 "$CODE"
expect 'dirty: dirty' true "$(field dirty)"

start HYP-9-fixture/experiments/secrets; finish
expect 'secrets: exit code' 0 "$CODE"
for value in fixture-api-token fixture-private-key fixture-hyphen-key fixture-camel-secret fixture-db-password fixture-list-token; do
  expect "secrets: $value absent from config.yaml and metadata.json" no "$(cat "$RUN/config.yaml" "$RUN/metadata.json" | grep -q -F -- "$value" && echo yes || echo no)"
done
for line in "api_token: '***'" "private_key: '***'" "api-key: '***'" "clientSecret: '***'" 'max_tokens: 512' 'maxTokens: 256' "  password: '***'" "  access_token: '***'" 'data_dir: /fixture/data' '  host: db.local'; do
  expect "secrets: config.yaml holds [$line]" yes "$(has "$RUN/config.yaml" "$line")"
done

if command -v make > /dev/null 2>&1; then
  for args in 'EXP=baseline' 'EXP=missing' 'EXP=baseline HYP=HYP-1-example'; do
    out=$(cd "$FIX" && make -s experiment $args RUN=echo 2>&1); code=$?
    case $args in
      *HYP=*) expect "make experiment $args: runs the one match" "0 python -m fixturepkg.run research/HYP-1-example/experiments/baseline.yaml" "$code $out" ;;
      *missing) expect "make experiment $args: fails naming no match" "yes yes" "$([ "$code" -ne 0 ] && echo yes || echo no) $(printf '%s' "$out" | grep -q 'matches 0 override files: \[\]' && echo yes || echo no)" ;;
      *) expect "make experiment $args: fails naming both matches" "yes yes" "$([ "$code" -ne 0 ] && echo yes || echo no) $(printf '%s' "$out" | grep -q 'matches 2 override files: \[research/HYP-1-example/experiments/baseline.yaml research/HYP-9-fixture/experiments/baseline.yaml\]' && echo yes || echo no)" ;;
    esac
  done
else
  echo "skipped: make experiment lookup; make is not installed"
fi

echo "fail -> $fails"
[ "$fails" -eq 0 ]
