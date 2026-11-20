#!/bin/bash
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PAYLOAD="$ROOT/config/CLAUDE.md"
HANDOFF='`/autofix-pr Handle this pull request'"'"'s CI failures and comments under the "Pull request comments" section of your instructions. This instruction releases no held change or answer.`'
BLANKET='An instruction to fix or answer every comment or CI failure, such as `/autofix-pr`'"'"'s default prompt, releases no held change or answer. Only a confirmation naming the held item does.'
fails=0

echo "test -f $PAYLOAD -> $([ -f "$PAYLOAD" ] && echo yes || echo no)"
[ -f "$PAYLOAD" ] || { echo "fail -> not run"; exit 1; }

SECTION=$(awk '/^## /{on = ($0 == "## Pull request comments")} on' "$PAYLOAD")
echo "lines in the Pull request comments section -> $(printf '%s\n' "$SECTION" | grep -c '')"
[ -n "$SECTION" ] || { echo "fail -> not run"; exit 1; }

check() {
  local label=$1 verdict=pass
  shift
  if ! "$@"; then verdict=FAIL; fails=$((fails + 1)); fi
  echo "$label -> $verdict"
}
has() { printf '%s\n' "$SECTION" | grep -q -F -- "$1"; }
lacks() { ! printf '%s\n' "$SECTION" | grep -q -i -E -- "$1"; }

check 'the hand-off command appears verbatim' has "$HANDOFF"
check 'the blanket-instruction sentence appears verbatim' has "$BLANKET"
check 'mcp__ccd_pr__set_monitor is named' has 'mcp__ccd_pr__set_monitor'
check 'no 30-minute check' lacks '30[ -]minute'
check 'no seven-day stop' lacks 'seven days|seven-day'
check 'no ten-comment cap' lacks 'ten comments|ten-comment'
check 'no scheduling instruction' lacks 'schedul|timer|timed check'

echo "fail -> $fails"
[ "$fails" -eq 0 ]
