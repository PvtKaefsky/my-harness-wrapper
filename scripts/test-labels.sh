#!/bin/bash
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$DIR/labels.sh"
REAL="$DIR/../.github/labels.json"
fails=0

echo "test -f $SCRIPT -> $([ -f "$SCRIPT" ] && echo yes || echo no)"
echo "command -v jq -> $(command -v jq || echo none)"
if [ ! -f "$SCRIPT" ] || ! command -v jq >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  echo "fail -> not run"
  exit 1
fi

WORK=$(mktemp -d) || { echo "mktemp -d -> exit=$?, not run"; exit 1; }
trap 'cd "$DIR" && rm -rf -- "$WORK"' EXIT
export CALLS="$WORK/calls" FIX="$WORK/fix"
SHA=0123456789abcdef0123456789abcdef01234567
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/bin/bash
echo "gh $*" >> "$CALLS"
path=${!#}
case "$1 ${2:-}" in
  "label list") cat "$FIX/labels.json"; exit ;;
  "label create")
    [ -e "$FIX/no-create" ] && { echo "HTTP 403: Resource not accessible by integration" >&2; exit 1; }
    exit 0 ;;
  "pr view" | "issue view") cat "$FIX/item.json"; exit ;;
  "pr edit" | "issue edit") exit 0 ;;
  "pr diff") cat "$FIX/diff.txt"; exit ;;
esac
[ "$1" = api ] || { echo "stub gh: unexpected call" >&2; exit 1; }
case $path in
  'repos/{owner}/{repo}') echo '{"default_branch":"main"}' ;;
  'repos/{owner}/{repo}/commits/'*)
    [ -e "$FIX/no-commit-${path##*/}" ] && { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
    echo '{}' ;;
  'repos/{owner}/{repo}/contents/.github/workflows?ref='*)
    [ -e "$FIX/wf-error" ] && { echo "gh: Server Error (HTTP 500)" >&2; exit 1; }
    ref=${path##*ref=}
    [ -d "$FIX/wf/$ref" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
    for f in "$FIX/wf/$ref"/*; do jq -n --arg p ".github/workflows/${f##*/}" '{type: "file", path: $p}'; done | jq -s . ;;
  'repos/{owner}/{repo}/contents/.github/workflows/'*)
    ref=${path##*ref=} name=${path%%\?*}
    cat "$FIX/wf/$ref/${name##*/}" ;;
  *) echo "stub gh: unexpected api path" >&2; exit 1 ;;
esac
STUB
chmod +x "$WORK/bin/gh"

cat > "$WORK/labels.json" <<'JSON'
{"families": [
  {"name": "type", "mode": "single", "labels": [
    {"name": "type/feat", "color": "a2eeef", "description": "Type feat"},
    {"name": "type/fix", "color": "d73a4a", "description": "Type fix"}]},
  {"name": "size", "mode": "single", "labels": [
    {"name": "size/M", "color": "fef2c0", "description": "Band M"},
    {"name": "size/L", "color": "f9c48c", "description": "Band L"}]},
  {"name": "area", "mode": "several", "paths": {"config/": "area/config", "scripts/": "area/scripts", "docs/": "area/docs"}, "labels": [
    {"name": "area/config", "color": "1d76db", "description": "Changes under config/"},
    {"name": "area/scripts", "color": "1d76db", "description": "Changes under scripts/"},
    {"name": "area/docs", "color": "1d76db", "description": "Changes under docs/"}]},
  {"name": "research", "mode": "several", "labels": [],
    "pattern": {"name": "hyp/<n>", "color": "006b75", "description": "Works on hypothesis HYP-<n>"}},
  {"name": "signal", "mode": "several", "labels": [
    {"name": "review/escalation", "color": "d93f0b", "description": "Escalated"},
    {"name": "agent/reviewed", "color": "ededed", "description": "Reviewed"},
    {"name": "wontfix", "color": "ffffff", "description": "Will not be fixed"}]}
]}
JSON

fixture() {
  rm -rf -- "$FIX"
  mkdir -p "$FIX"
  : > "$CALLS"
  printf '%s\n' "$1" > "$FIX/labels.json"
  printf '{"labels": %s, "headRefOid": "%s", "baseRefName": "release"}\n' "${2:-[]}" "$SHA" > "$FIX/item.json"
}

workflow() {
  mkdir -p "$FIX/wf/$1"
  printf '%s\n' "$3" > "$FIX/wf/$1/$2"
}

run() {
  OUT=$(PATH="$WORK/bin:$PATH" bash "$SCRIPT" "$@" 2>&1)
  CODE=$?
}

expect() {
  local label=$1 want=$2 verdict=pass kind text
  shift 2
  [ "$CODE" -eq "$want" ] || { verdict=FAIL; label="$label, exit $CODE"; }
  while [ $# -gt 0 ]; do
    kind=$1 text=$2
    shift 2
    case $kind in
      out) grep -qxF -- "$text" <<<"$OUT" || { verdict=FAIL; label="$label, no output [$text]"; } ;;
      call) grep -qxF -- "$text" "$CALLS" || { verdict=FAIL; label="$label, no call [$text]"; } ;;
      nocall) ! grep -qF -- "$text" "$CALLS" || { verdict=FAIL; label="$label, call with [$text]"; } ;;
    esac
  done
  [ "$verdict" = pass ] || { fails=$((fails + 1)); printf '%s\n' "$OUT" | sed 's/^/  | /'; }
  echo "$label -> $verdict"
}

L='--file '"$WORK/labels.json"
HAVE='[{"name":"type/feat","color":"A2EEEF","description":"Type feat"},{"name":"type/fix","color":"000000","description":"Type fix"},{"name":"keep-me","color":"111111","description":"Unlisted"},{"name":"size/L","color":"f9c48c","description":"Band L"}]'

fixture "$HAVE"
run sync $L
expect 'sync creates missing labels, updates changed ones and leaves unlisted ones' 1 \
  call 'gh label create size/M --color fef2c0 --description Band M' \
  call 'gh label create type/fix --color d73a4a --description Type fix --force' \
  out 'label type/feat -> unchanged' \
  out 'label agent/reviewed -> refused: name or description refers to AI, an agent, Claude or a model' \
  nocall 'create type/feat' nocall 'keep-me' nocall 'agent/reviewed' nocall 'delete' nocall 'edit'

jq '.families[0].labels += [{"name": "keep-me", "description": "Unlisted"}]' "$WORK/labels.json" > "$WORK/nocolour.json"
fixture "$HAVE"
run sync --file "$WORK/nocolour.json"
expect 'sync reports a listed label without a colour' 1 \
  out 'label keep-me -> not updated: colour is not six hex digits' nocall 'keep-me'

fixture "$HAVE" '[{"name":"type/fix"},{"name":"size/M"},{"name":"review/escalation"},{"name":"keep-me"}]'
run apply pr 7 $L --add type/feat --add size/L --remove review/escalation
expect 'apply replaces the label of each single family and removes a cleared signal' 0 \
  call 'gh pr edit 7 --add-label=type/feat --add-label=size/L --remove-label=type/fix --remove-label=size/M --remove-label=review/escalation' \
  nocall 'keep-me' nocall 'label create'

fixture "$HAVE"
run apply pr 7 $L --add size/L --add size/M
expect 'apply refuses a second label of one single family in one call' 1 \
  out 'label size/M -> refused: family size already takes size/L in this call' \
  call 'gh pr edit 7 --add-label=size/L'

fixture "$HAVE"
run apply pr 7 $L --add agent/reviewed --add wontfix --add unlisted --add type/feat
expect 'apply refuses attribution, never-apply and unlisted labels' 1 \
  out 'label agent/reviewed -> refused: name or description refers to AI, an agent, Claude or a model' \
  out 'label wontfix -> refused: on the never-apply list' \
  out "label unlisted -> refused: not listed in $WORK/labels.json" \
  call 'gh pr edit 7 --add-label=type/feat' nocall 'agent/reviewed' nocall 'wontfix'

fixture "$HAVE"
workflow "$SHA" label.yml 'on:
  pull_request:
    types: [labeled]
jobs:
  x:
    if: github.event.label.name == '"'"'type/feat'"'"'
  y:
    runs-on: ubuntu-latest'
run apply pr 7 $L --add type/feat --add size/L
expect 'apply refuses every label while a head workflow triggers on labeled' 1 \
  out 'workflow .github/workflows/label.yml at '"$SHA"' -> label trigger=1, label test=1' \
  out 'label type/feat -> refused: a workflow triggers on or tests this label' \
  out 'label size/L -> refused: a workflow triggers on or tests this label' nocall ' edit '

fixture "$HAVE"
workflow "$SHA" gate.yml 'on: pull_request
jobs:
  x:
    if: contains(github.event.pull_request.labels.*.name, '"'"'TYPE/FEAT'"'"')'
run apply pr 7 $L --add type/feat --add size/L
expect 'apply refuses only the label a workflow tests, matching its name case-insensitively' 1 \
  out 'workflow .github/workflows/gate.yml at '"$SHA"' -> label trigger=0, label test=1' \
  out 'label type/feat -> refused: a workflow triggers on or tests this label' \
  call 'gh pr edit 7 --add-label=size/L' nocall '--add-label=type/feat'

fixture "$HAVE"
workflow "$SHA" prefix.yml 'on:
  pull_request:
    types: [labeled]
jobs:
  x:
    if: startsWith(github.event.label.name, '"'"'size/'"'"')'
run apply pr 7 $L --add type/feat
expect 'apply refuses every label while a workflow tests label names other than by a literal compare' 1 \
  out 'label type/feat -> refused: a workflow triggers on or tests this label' nocall ' edit '

for case in "github.event.label.name != 'size/L'" "!contains(github.event.pull_request.labels.*.name, 'size/L')" \
  "github.event.label.name == 'size/L' || true" "github.event['label'].name == 'size/L'"; do
  fixture "$HAVE"
  workflow "$SHA" cond.yml "on:
  pull_request:
    types: [labeled]
jobs:
  x:
    if: $case"
  run apply pr 7 $L --add type/feat
  expect "apply refuses every label while a labeled workflow tests [$case]" 1 \
    out 'label type/feat -> refused: a workflow triggers on or tests this label' nocall ' edit '
done

fixture "$HAVE"
workflow release target.yml 'on:
  pull_request_target:
    types: [labeled]'
run apply pr 7 $L --add size/L
expect 'apply refuses a label a base-branch workflow triggers on' 1 \
  out 'workflow .github/workflows/target.yml at release -> label trigger=1, label test=0' \
  out 'label size/L -> refused: a workflow triggers on or tests this label' nocall ' edit '

fixture "$HAVE"
workflow main issues.yml 'on:
  issues:
  pull_request:
    types: [opened]'
run apply issue 3 $L --add type/feat
expect 'apply refuses issue labels while a workflow names the issues event' 1 \
  out 'label type/feat -> refused: a workflow triggers on or tests this label' nocall ' edit '

fixture "$HAVE"
touch "$FIX/no-commit-$SHA"
run apply pr 7 $L --add size/L
expect 'apply refuses labels when the head commit cannot be read' 1 \
  out 'label size/L -> refused: workflow scan incomplete' nocall ' edit '

fixture "$HAVE"
workflow main any.yml 'on: { pull_request: { types: [opened, labeled] } }'
run apply pr 7 $L --add size/L
expect 'apply refuses every label while a default-branch workflow fires on any label' 1 \
  out 'label size/L -> refused: a workflow triggers on or tests this label' nocall ' edit '

fixture "$HAVE" '[{"name":"size/M"}]'
workflow main ci.yml 'on: push
jobs:
  x:
    if: contains(github.event.pull_request.labels.*.name, '"'"'size/M'"'"')'
run apply pr 7 $L --add size/L
expect 'apply refuses a label whose removal a workflow tests' 1 \
  out 'label size/L -> refused: removing another size label: a workflow triggers on or tests this label' nocall ' edit '

fixture "$HAVE"
touch "$FIX/wf-error"
run apply pr 7 $L --add size/L
expect 'apply refuses labels when the workflow scan fails' 1 \
  out 'label size/L -> refused: workflow scan incomplete' nocall ' edit '

fixture "$HAVE"
touch "$FIX/no-create"
run apply pr 7 $L --add hyp/12 --add size/L
expect 'without permission to create labels apply adds only existing ones' 1 \
  out 'label hyp/12 -> refused: missing from the repository and not created: exit=1: HTTP 403: Resource not accessible by integration' \
  call 'gh pr edit 7 --add-label=size/L'
run sync $L
expect 'without permission to create labels sync reports each one' 1 \
  out 'label size/M -> not created: exit=1: HTTP 403: Resource not accessible by integration'

fixture "$HAVE" '[{"name":"size/L"}]'
touch "$FIX/no-create"
run apply pr 7 $L --add size/M --add size/L
expect 'a single-family label that cannot be created leaves the family label in place' 1 \
  out 'label size/M -> refused: missing from the repository and not created: exit=1: HTTP 403: Resource not accessible by integration' \
  out 'label size/L -> already present' nocall ' edit '

fixture "$HAVE" '[{"name":"x,y"}]'
run apply pr 7 $L --remove 'x,y'
expect 'apply refuses to remove a name holding a comma' 1 \
  out 'label x,y -> refused: name is empty, starts with a dash or holds a comma or control character' nocall ' edit '

fixture "$HAVE"
run apply issue 3 $L --add hyp/12 --add hyp/0 --add hyp/x
expect 'apply creates a pattern label on an issue, scanning the default branch only' 1 \
  call 'gh label create hyp/12 --color 006b75 --description Works on hypothesis HYP-12' \
  call 'gh issue view 3 --json labels' call 'gh issue edit 3 --add-label=hyp/12' \
  out "label hyp/0 -> refused: not listed in $WORK/labels.json" nocall "ref=$SHA" nocall 'ref=release'

git init -q "$WORK/repo" && cd "$WORK/repo" || { echo "git init -> failed, not run"; exit 1; }
mkdir -p config scripts docs
git -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m base && git tag base
touch config/a scripts/b
git add . && git -c user.name=t -c user.email=t@example.com commit -q -m change
fixture "$HAVE" '[{"name":"area/docs"},{"name":"area/config"}]'
printf 'config/x\nscripts/y\n' > "$FIX/diff.txt"
run apply pr 7 $L --areas
expect 'apply sets the area labels from the pull request diff, not the local checkout' 0 \
  out 'area labels from gh pr diff 7 -> area/config area/scripts' \
  call 'gh pr diff 7 --name-only' \
  call 'gh pr edit 7 --add-label=area/scripts --remove-label=area/docs' \
  call 'gh label create area/scripts --color 1d76db --description Changes under scripts/'

printf 'docs/z\n' > "$FIX/diff.txt"
run apply pr 7 $L --areas
expect 'apply ignores the paths the local HEAD changes' 0 \
  out 'area labels from gh pr diff 7 -> area/docs' \
  call 'gh pr edit 7 --remove-label=area/config'

run apply issue 3 $L --areas
expect 'apply refuses --areas on an issue' 2 nocall 'issue view'

jq 'del(.families[].paths)' "$WORK/labels.json" > "$WORK/nopaths.json"
fixture "$HAVE" '[{"name":"keep-me"},{"name":"area/docs"}]'
printf 'config/x\n' > "$FIX/diff.txt"
run apply pr 7 --file "$WORK/nopaths.json" --areas
expect 'apply --areas with no path map removes no label' 0 \
  out 'area labels from gh pr diff 7 -> none' nocall ' edit '

fixture '[]'
run sync --file "$REAL"
want=$(jq '[.families[] | .labels[]?] | length' "$REAL" | tr -d '\r')
got=$(grep -c ' -> created$' <<<"$OUT")
[ "$got" = "$want" ] || CODE=9
expect "the harness label file passes every check and creates its $want labels" 0

echo "fail -> $fails"
[ "$fails" -eq 0 ]
