#!/bin/bash
set -uo pipefail

OUT=${CHECKS_OUT:-/results/checks.jsonl}
WORK=${CHECKS_WORK:-/work}
LIMIT=600
: > "$OUT"

record() {
  printf '{"id":"%s","status":"%s","seconds":%s}\n' "$1" "$2" "$3" >> "$OUT"
  echo "check $1 -> $2 in ${3}s"
}

elapsed() {
  awk -v a="$1" -v b="$EPOCHREALTIME" 'BEGIN { printf "%.3f", b - a }'
}

start=$EPOCHREALTIME
status=fail
scratch=$(mktemp -d)
if git clone -q "$WORK" "$scratch/tree"; then
  block=quickstart-offline
  tr -d '\r' < "$scratch/tree/README.md" 2> /dev/null | grep -q -x '```sh quickstart-offline' || block=quickstart
  command=$(awk -v open="\`\`\`sh $block" '{ sub(/\r$/, "") } $0 == open { on = 1; next } on && /^```/ { exit } on' "$scratch/tree/README.md" 2> /dev/null)
  echo "quickstart -> README.md block [sh $block]: ${command:-none}"
  if [ -n "$command" ]; then
    (cd "$scratch/tree" && timeout -k 10 "$LIMIT" bash -euo pipefail -c "$command" < /dev/null)
    code=$?
    echo "quickstart -> exit=$code"
    [ "$code" -eq 0 ] && status=pass
  fi
fi
rm -rf -- "$scratch"
record quickstart "$status" "$(elapsed "$start")"

start=$EPOCHREALTIME
status=pass
shopt -s nullglob
specs=()
for spec in "$WORK"/docs/specs/*.md; do
  if [ "$(head -n 1 "$spec" | tr -d '\r')" = "Status: active" ]; then
    specs+=("$spec")
  else
    echo "spec-trace -> ${spec#"$WORK"/} skipped, first line is not Status: active"
  fi
done
shopt -u nullglob
mapfile -t tests < <(git -C "$WORK" ls-files | grep -E '(^|/)(tests?|__tests__)/|(^|/)test_[^/]*$|_test\.[^/]+$|\.(test|spec)\.[^/]+$|Tests?\.[^/]+$')
ids=
[ "${#specs[@]}" -gt 0 ] && ids=$(awk '{ sub(/\r$/, "") } /^## / { on = ($0 == "## Scenarios") } on && match($0, /^[|] *[A-Z][A-Z0-9]*-[0-9]+ *[|]/) { id = substr($0, RSTART, RLENGTH); gsub(/[| ]/, "", id); print id }' "${specs[@]}")
echo "spec-trace -> ${#specs[@]} specs, $(printf '%s' "$ids" | grep -c .) scenario IDs, ${#tests[@]} test files"
for id in $(printf '%s\n' "$ids" | sort | uniq -d); do
  echo "spec-trace -> $id repeated"
  status=fail
done
for id in $(printf '%s\n' "$ids" | sort -u); do
  pattern="(^|[^A-Za-z0-9])${id%-*}[-_]${id##*-}([^0-9]|$)"
  [ "${#tests[@]}" -gt 0 ] && (cd "$WORK" && grep -q -i -E -- "$pattern" "${tests[@]}") && continue
  echo "spec-trace -> $id names no test"
  status=fail
done
record spec-trace "$status" "$(elapsed "$start")"
