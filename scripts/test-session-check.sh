#!/bin/bash
set -uo pipefail

CHECK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/session-check.sh"
fails=0

echo "test -f $CHECK -> $([ -f "$CHECK" ] && echo yes || echo no)"
echo "command -v git -> $(command -v git || echo none)"
if [ ! -f "$CHECK" ] || ! command -v git >/dev/null 2>&1; then
  echo "fail -> not run"
  exit 1
fi

WORK=$(mktemp -d) || { echo "mktemp -d -> exit=$?, not run"; exit 1; }
trap 'rm -rf -- "$WORK"' EXIT
mkdir -p "$WORK/config" "$WORK/harness"
printf '{"local_checkout":"%s"}\n' "$WORK/harness" > "$WORK/config/.my-harness-wrapper.manifest.json"

printf -v RLO '\342\200\256'
printf -v LRI '\342\201\246'
printf -v ZWSP '\342\200\213'

repo() {
  mkdir -p "$WORK/$1" && git -C "$WORK/$1" init -q && cd "$WORK/$1" || { echo "git init $1 -> failed, not run"; exit 1; }
}

run_check() {
  CLAUDE_CONFIG_DIR="$WORK/config" HARNESS_DIR="$WORK/harness" GIT_CEILING_DIRECTORIES="$WORK" bash "${1:-$CHECK}" 2>&1
}

expect() {
  local label=$1 want=$2 out got notes verdict=pass line
  out=$(run_check "${3:-}"); got=$?
  notes=$(printf '%s\n' "$out" | grep -a -c '^NOTE ')
  if [ "$got" -ne 0 ] || [ "$notes" -ne "$want" ] || printf '%s\n' "$out" | grep -a -q '^FAIL'; then verdict=FAIL; fi
  shift 3 2>/dev/null || shift $#
  for line in "$@"; do
    if ! printf '%s\n' "$out" | grep -a -q -x -F -- "$line"; then verdict=FAIL; label="$label, line [$line]"; fi
  done
  if [ "$verdict" = FAIL ]; then fails=$((fails + 1)); fi
  echo "$label -> expected exit=0, $want NOTE lines and no FAIL line, actual exit=$got and $notes NOTE lines, $verdict"
}

repo clean
mkdir -p a/b .claude/skills/s ignored
printf 'ignored/\n' > .gitignore
printf 'one\ntwo\n' | tee CLAUDE.md a/b/AGENTS.md .claude/skills/s/SKILL.md > /dev/null
printf '{}\n' > .mcp.json
printf 'a%sb\n' "$RLO" | tee README.md ignored/AGENTS.md a/NOTAGENTS.md .claude/notes.txt > /dev/null
TOP=$(git rev-parse --show-toplevel)
expect 'clean repository, U+202E only in ignored and unscanned files' 0 '' \
  "hidden-character scan $TOP -> git ls-files exit=0 files=4 bytes=27 notes=0"

repo nested
mkdir -p a/b
printf 'one\ntwo\na%sb\na%sb\n' "$RLO" "$RLO" > a/b/AGENTS.md
expect 'U+202E twice in a nested AGENTS.md' 1 '' 'NOTE hidden character U+202E at a/b/AGENTS.md:3'
cd a/b || exit 1
expect 'the same repository from its subdirectory' 1 '' 'NOTE hidden character U+202E at a/b/AGENTS.md:3'

repo 'a&b'
mkdir "x${RLO}y"
printf 'a%sb\n' "$RLO" > "x${RLO}y/AGENTS.md"
TOP=$(git rev-parse --show-toplevel)
expect 'an ampersand in the repository path and U+202E in a directory name' 1 '' \
  'NOTE hidden character U+202E at x???y/AGENTS.md:1' \
  "hidden-character scan $TOP -> git ls-files exit=0 files=1 bytes=6 notes=1"

git config core.fsmonitor 'touch fsmonitor-ran'
expect 'core.fsmonitor naming a command in the repository config' 1 ''
verdict=pass
if [ -e fsmonitor-ran ]; then verdict=FAIL; fails=$((fails + 1)); fi
echo "the core.fsmonitor command -> expected not run, actual $([ -e fsmonitor-ran ] && echo run || echo not run), $verdict"

repo tags
i=0
while [ "$i" -lt 60 ]; do printf "\\363\\240\\201\\$(printf '%o' $((128 + i)))\\n"; i=$((i + 1)); done > CLAUDE.md
printf 'a%sb\n' "$RLO" > a.md && mkdir z && mv a.md z/CLAUDE.md
expect '60 distinct tag characters in one file, U+202E in a later file' 51 '' \
  'NOTE hidden character U+E0040 at CLAUDE.md:1' \
  'NOTE hidden character U+E0071 at CLAUDE.md:50' \
  'NOTE hidden-character scan stopped at the cap of 50 NOTE lines, in CLAUDE.md'
out=$(SESSION_CHECK_HIDDEN_TIMEOUT=0.001 run_check); got=$?
notes=$(printf '%s\n' "$out" | grep -a -c '^NOTE ')
verdict=pass
if [ "$got" -ne 0 ] || [ "$notes" -ge 51 ] || ! printf '%s\n' "$out" | grep -a -q -x -E 'NOTE hidden-character scan stopped at the cap of 0\.001s \(exit=(124|137)\)'; then verdict=FAIL; fails=$((fails + 1)); fi
echo "the same repository with a 0.001 s bound -> expected exit=0, the time cap NOTE with exit=124 or 137 and under 51 NOTE lines, actual exit=$got and $notes NOTE lines, $verdict"

repo several
mkdir -p a .claude/agents
printf 'a%sb\n' "$RLO" > CLAUDE.md
printf 'x\na%sb%sc\n' "$RLO" "$LRI" > a/CLAUDE.md
printf 'x\n\na%sb\n' "$ZWSP" > .claude/agents/r.md
printf '{"a":"b\000c"}\n' > .mcp.json
git -c core.autocrlf=false add CLAUDE.md
expect 'two files sharing U+202E, a tracked file, U+200B and U+0000' 5 '' \
  'NOTE hidden character U+202E at CLAUDE.md:1' \
  'NOTE hidden character U+202E at a/CLAUDE.md:2' \
  'NOTE hidden character U+2066 at a/CLAUDE.md:2' \
  'NOTE zero-width character U+200B at .claude/agents/r.md:3' \
  'NOTE hidden character U+0000 at .mcp.json:1'

repo many
i=0
while [ "$i" -le 200 ]; do printf -v d 'd%03d' "$i"; mkdir "$d" && printf 'x\n' > "$d/AGENTS.md"; i=$((i + 1)); done
printf 'a%sb\n' "$RLO" > d200/AGENTS.md
printf 'a%sb\n' "$RLO" > d199/AGENTS.md
expect '201 files, U+202E in the 200th and the 201st' 2 '' \
  'NOTE hidden character U+202E at d199/AGENTS.md:1' \
  'NOTE hidden-character scan stopped at the cap of 200 files, before d200/AGENTS.md; 200 of 201 files scanned'

repo big
mkdir m z
printf 'a%sb\n' "$RLO" > AGENTS.md
head -c 5242880 /dev/zero | tr '\000' a > m/CLAUDE.md
printf 'a%sb\n' "$RLO" > z/AGENTS.md
expect 'a 5 MiB file after a 6-byte one' 2 '' \
  'NOTE hidden character U+202E at AGENTS.md:1' \
  'NOTE hidden-character scan stopped at the cap of 5242880 bytes (5 MiB), before m/CLAUDE.md; 1 of 3 files scanned'

mkdir -p "$WORK/plain" && cd "$WORK/plain" || exit 1
printf 'a%sb\n' "$RLO" > AGENTS.md
expect 'a directory outside a git repository' 0 '' \
  "git -C $PWD rev-parse --show-toplevel -> exit=128, hidden-character scan not run"

mkdir -p "$WORK/copy/scripts" && cp "$CHECK" "$WORK/copy/scripts/session-check.sh"
cd "$WORK/nested" || exit 1
expect 'hidden-chars.sh absent beside the script' 0 "$WORK/copy/scripts/session-check.sh" \
  "hidden-character scan -> not run, $WORK/copy/scripts/../git-hooks/lib/hidden-chars.sh could not be read"
mkdir -p "$WORK/copy/git-hooks/lib" && cp "$(dirname "$CHECK")/../git-hooks/lib/hidden-chars.sh" "$WORK/copy/git-hooks/lib/"
expect 'hidden-chars.tsv absent beside the script' 0 "$WORK/copy/scripts/session-check.sh" \
  "hidden-character scan -> not run, $WORK/copy/scripts/../git-hooks/lib/hidden-chars.tsv could not be applied"

echo "fail -> $fails"
[ "$fails" -eq 0 ]
