#!/bin/bash
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GATE="$ROOT/plugins/my-harness/hooks/web-guidance-gate.sh"
HOOKS="$ROOT/plugins/my-harness/hooks/hooks.json"
WEB_MARK='web-guidance-gate: modern-web-guidance applies only to web front-end work.'
TEL_MARK='web-guidance-gate: run the package with telemetry off: export DISABLE_TELEMETRY=1; '
fails=0

echo "test -f $GATE -> $([ -f "$GATE" ] && echo yes || echo no)"
echo "command -v jq -> $(command -v jq || echo none)"
echo "command -v git -> $(command -v git || echo none)"
if [ ! -f "$GATE" ] || ! command -v jq >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  echo "fail -> not run"
  exit 1
fi

ENTRY=$(jq -c '[.hooks.PreToolUse[]? | select(any(.hooks[]?; (.command | type) == "string" and (.command | contains("web-guidance-gate.sh"))))] | first // empty' "$HOOKS" 2>/dev/null)
MATCHER=$(printf '%s' "$ENTRY" | jq -r '.matcher // empty | strings' 2>/dev/null)
HOOK_CMD=$(printf '%s' "$ENTRY" | jq -r '[.hooks[] | .command | strings | select(contains("web-guidance-gate.sh"))] | first // empty' 2>/dev/null)
echo "PreToolUse matcher naming web-guidance-gate.sh in $HOOKS -> ${MATCHER:-none}"
if [ -z "$MATCHER" ] || [ -z "$HOOK_CMD" ]; then
  echo "fail -> not run"
  exit 1
fi

WORK=$(mktemp -d) || { echo "mktemp -d -> exit=$?, not run"; exit 1; }
trap 'rm -rf -- "$WORK"' EXIT
export GIT_CEILING_DIRECTORIES="$WORK"
DATA="$WORK/data"
MARKS="$DATA/web-guidance-sessions"
mkdir -p "$DATA" "$WORK/web/sub" "$WORK/py" "$WORK/ext" "$WORK/nogit" "$WORK/j2/templates" "$WORK/js" "$WORK/noext"
printf 'body{}\n' > "$WORK/web/style.css"
printf 'print(1)\n' > "$WORK/py/main.py"
printf '{"manifest_version": 3}\n' > "$WORK/ext/manifest.json"
printf '<p></p>\n' > "$WORK/j2/templates/index.html.j2"
printf 'x\n' > "$WORK/js/server.js"
printf 'x\n' > "$WORK/js/app.ts"
printf '{"name": "x"}\n' > "$WORK/noext/manifest.json"
for r in web py ext j2 js noext; do
  git -C "$WORK/$r" init -q && git -C "$WORK/$r" -c core.autocrlf=false add -A
done

NPX='npx -y modern-web-guidance@latest search "x"'

skill_in() { jq -n --arg s "$1" --arg c "$2" --arg i "$3" --arg a "${4:-}" '{session_id:$i,cwd:$c,hook_event_name:"PreToolUse",tool_name:"Skill",tool_input:({skill:$s} + (if $a == "" then {} else {args:$a} end))}'; }
bash_in() { jq -n --arg m "$1" --arg c "$2" --arg i "$3" '{session_id:$i,cwd:$c,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$m}}'; }

run_gate() { env -u DISABLE_TELEMETRY CLAUDE_PLUGIN_DATA="$DATA" ${TEL:+DISABLE_TELEMETRY=$TEL} bash "$GATE"; }
run_nodata() { env -u DISABLE_TELEMETRY -u CLAUDE_PLUGIN_DATA DISABLE_TELEMETRY=1 bash "$GATE"; }
run_hook() {
  local input tool
  input=$(cat)
  tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
  if ! printf '%s\n' "$tool" | grep -a -q -x -E -- "$MATCHER"; then return 0; fi
  printf '%s' "$input" | env -u DISABLE_TELEMETRY CLAUDE_PLUGIN_ROOT="$ROOT/plugins/my-harness" CLAUDE_PLUGIN_DATA="$DATA" DISABLE_TELEMETRY=1 bash -c "$HOOK_CMD"
}

run_case() {
  local label=$1 want=$2 input=$3 mark=${4:-} runner=${5:-run_gate} err got show verdict
  err=$(printf '%s' "$input" | "$runner" 2>&1 >/dev/null); got=$?
  show="exit=$got"
  verdict=pass
  if [ "$got" -ne "$want" ]; then
    verdict=FAIL
  elif [ -n "$mark" ]; then
    if printf '%s\n' "$err" | grep -a -q -F -- "$mark"; then
      show="exit=$got carrying the marker"
    else
      show="exit=$got without the marker"
      verdict=FAIL
    fi
  fi
  if [ "$verdict" = FAIL ]; then fails=$((fails + 1)); fi
  echo "$label -> expected exit=$want, actual $show, $verdict"
}

check() {
  local label=$1 verdict=pass
  shift
  if ! "$@"; then verdict=FAIL; fails=$((fails + 1)); fi
  echo "$label -> $verdict"
}

TEL=1
run_case 'skill in a repository with a .css file' 0 "$(skill_in modern-web-guidance:modern-web-guidance "$WORK/web" s1)"
check 'skill in a repository with a .css file, marker written' test -f "$MARKS/s1"
run_case 'skill in a repository with only .py files' 2 "$(skill_in modern-web-guidance:modern-web-guidance "$WORK/py" s2)" "$WEB_MARK"
check 'skill denied, no marker written' test ! -e "$MARKS/s2"
run_case 'skill in the .py repository, args naming app/templates/index.html' 0 "$(skill_in modern-web-guidance:modern-web-guidance "$WORK/py" s2 'dialog in app/templates/index.html')"
check 'args naming a web file, marker written' test -f "$MARKS/s2"
run_case 'skill in the .py repository, args naming main.py' 2 "$(skill_in modern-web-guidance:modern-web-guidance "$WORK/py" s3 'main.py')" "$WEB_MARK"
run_case 'npx in the .py repository, same session_id as the marker' 0 "$(bash_in "$NPX" "$WORK/py" s2)"
run_case 'npx in the .py repository, another session_id' 2 "$(bash_in "$NPX" "$WORK/py" s3)" "$WEB_MARK"
run_case 'skill with session_id ../x' 0 "$(skill_in modern-web-guidance:modern-web-guidance "$WORK/web" '../x')"
check 'session_id ../x, no file named x written' test -z "$(find "$WORK" -name x -print)"
check 'session_id ../x, marker directory holds only s1 and s2' test "$(ls -A "$MARKS" | tr '\n' ' ')" = 's1 s2 '

TEL=
run_case 'npx in the web repository, DISABLE_TELEMETRY unset' 2 "$(bash_in "$NPX" "$WORK/web" t1)" "$TEL_MARK$NPX"
run_case 'DISABLE_TELEMETRY=1 npx in the web repository' 0 "$(bash_in "DISABLE_TELEMETRY=1 $NPX" "$WORK/web" t1)"
run_case 'cd sub && DISABLE_TELEMETRY=1 npx ... retrieve' 0 "$(bash_in 'cd sub && DISABLE_TELEMETRY=1 npx -y modern-web-guidance@latest retrieve "y"' "$WORK/web" t1)"
run_case 'export DISABLE_TELEMETRY=1; npx' 0 "$(bash_in "export DISABLE_TELEMETRY=1; $NPX" "$WORK/web" t1)"
run_case 'DISABLE_TELEMETRY=1 true && npx' 2 "$(bash_in "DISABLE_TELEMETRY=1 true && $NPX" "$WORK/web" t1)" "$TEL_MARK"
run_case 'DISABLE_TELEMETRY=true npx' 0 "$(bash_in "DISABLE_TELEMETRY=true $NPX" "$WORK/web" t1)"
run_case 'DISABLE_TELEMETRY="1" npx' 0 "$(bash_in "DISABLE_TELEMETRY=\"1\" $NPX" "$WORK/web" t1)"
run_case 'export DISABLE_TELEMETRY=true; npx' 0 "$(bash_in "export DISABLE_TELEMETRY=true; $NPX" "$WORK/web" t1)"
run_case 'DISABLE_TELEMETRY=1 npx; npx' 2 "$(bash_in "DISABLE_TELEMETRY=1 $NPX; $NPX" "$WORK/web" t1)" "$TEL_MARK"
run_case 'DISABLE_TELEMETRY=1 true $(npx ...)' 2 "$(bash_in "DISABLE_TELEMETRY=1 true \$($NPX)" "$WORK/web" t1)" "$TEL_MARK"
run_case 'false && export DISABLE_TELEMETRY=1; npx' 2 "$(bash_in "false && export DISABLE_TELEMETRY=1; $NPX" "$WORK/web" t1)" "$TEL_MARK"
run_case '(export DISABLE_TELEMETRY=1); npx' 2 "$(bash_in "(export DISABLE_TELEMETRY=1); $NPX" "$WORK/web" t1)" "$TEL_MARK"
run_case 'npx split by a backslash-newline' 2 "$(bash_in 'npx -y \
modern-web-guidance@latest search "x"' "$WORK/web" t1)" "$TEL_MARK"
run_case 'npx --package=modern-web-guidance' 2 "$(bash_in 'npx --package=modern-web-guidance modern-web-guidance search "x"' "$WORK/web" t1)" "$TEL_MARK"
run_case 'if true; then npx ...; fi' 2 "$(bash_in "if true; then $NPX; fi" "$WORK/web" t1)" "$TEL_MARK"
run_case 'for x in 1; do DISABLE_TELEMETRY=1 npx ...; done' 0 "$(bash_in "for x in 1; do DISABLE_TELEMETRY=1 $NPX; done" "$WORK/web" t1)"
run_case 'timeout 5 npx' 2 "$(bash_in "timeout 5 $NPX" "$WORK/web" t1)" "$TEL_MARK"
for runner in npx.cmd pnpx bunx 'pnpm dlx' 'npm exec'; do
  run_case "$runner in the web repository, DISABLE_TELEMETRY unset" 2 "$(bash_in "$runner modern-web-guidance@latest search \"x\"" "$WORK/web" t1)" "$TEL_MARK"
done
TEL=1
CLEAR_MARK='web-guidance-gate: the command unsets DISABLE_TELEMETRY'
run_case 'DISABLE_TELEMETRY=1 DISABLE_TELEMETRY=0 npx' 2 "$(bash_in "DISABLE_TELEMETRY=1 DISABLE_TELEMETRY=0 $NPX" "$WORK/web" t1)" "$CLEAR_MARK"
run_case 'DISABLE_TELEMETRY=1 env -u DISABLE_TELEMETRY npx' 2 "$(bash_in "DISABLE_TELEMETRY=1 env -u DISABLE_TELEMETRY $NPX" "$WORK/web" t1)" "$CLEAR_MARK"
run_case 'unset DISABLE_TELEMETRY; npx' 2 "$(bash_in "unset DISABLE_TELEMETRY; $NPX" "$WORK/web" t1)" "$CLEAR_MARK"
run_case 'DISABLE_TELEMETRY=1 env -i npx' 2 "$(bash_in "DISABLE_TELEMETRY=1 env -i $NPX" "$WORK/web" t1)" "$CLEAR_MARK"
run_case 'git commit -m naming npx modern-web-guidance in the .py repository' 0 "$(bash_in "git commit -m \"docs: $NPX\"" "$WORK/py" s8)"
run_case 'grep for npx modern-web-guidance in the .py repository' 0 "$(bash_in 'grep -rn "npx modern-web-guidance" docs' "$WORK/py" s8)"
run_case 'skill in a repository tracking index.html.j2' 0 "$(skill_in modern-web-guidance:modern-web-guidance "$WORK/j2" s10)"
run_case 'skill in a repository tracking only .js and .ts files' 2 "$(skill_in modern-web-guidance:modern-web-guidance "$WORK/js" s11)" "$WEB_MARK"
run_case 'chrome-extensions with a manifest.json lacking manifest_version' 2 "$(skill_in modern-web-guidance:chrome-extensions "$WORK/noext" s12)" "$WEB_MARK"

run_case 'skill in the .py repository with args naming a web file, CLAUDE_PLUGIN_DATA unset' 0 "$(skill_in modern-web-guidance:modern-web-guidance "$WORK/py" s4 'templates/index.html')" '' run_nodata
check 'CLAUDE_PLUGIN_DATA unset, no marker written' test -z "$(find "$WORK" -name s4 -print)"
run_case 'npx in the .py repository after that call' 2 "$(bash_in "$NPX" "$WORK/py" s4)" "$WEB_MARK"
run_case 'skill outside any git repository' 2 "$(skill_in modern-web-guidance:modern-web-guidance "$WORK/nogit" s5)" "$WEB_MARK"
run_case 'chrome-extensions with a tracked manifest.json holding manifest_version' 0 "$(skill_in modern-web-guidance:chrome-extensions "$WORK/ext" s6)"
run_case 'modern-web-guidance with only that manifest.json' 2 "$(skill_in modern-web-guidance:modern-web-guidance "$WORK/ext" s7)" "$WEB_MARK"
run_case 'another plugin skill in the .py repository' 0 "$(skill_in humanizer:humanizer "$WORK/py" s8)"
run_case 'npx in the .py repository' 2 "$(bash_in "$NPX" "$WORK/py" s8)" "$WEB_MARK"
run_case 'env npx in the .py repository' 2 "$(bash_in "env $NPX" "$WORK/py" s8)" "$WEB_MARK"
run_case 'git clone of the package repository in the .py repository' 0 "$(bash_in 'git clone https://github.com/GoogleChrome/modern-web-guidance' "$WORK/py" s8)"
run_case 'ls' 0 "$(bash_in ls "$WORK/py" s8)"
run_case 'input that is not valid JSON' 0 'not json' 'web-guidance-gate: could not read the hook input'
run_case 'npx in the .py repository through the plugin hook' 2 "$(bash_in "$NPX" "$WORK/py" s8)" "$WEB_MARK" run_hook
run_case 'npx in the web repository through the plugin hook' 0 "$(bash_in "$NPX" "$WORK/web" s8)" '' run_hook
run_case 'skill in the .py repository through the plugin hook' 2 "$(skill_in modern-web-guidance:modern-web-guidance "$WORK/py" s9)" "$WEB_MARK" run_hook

echo "fail -> $fails"
[ "$fails" -eq 0 ]
