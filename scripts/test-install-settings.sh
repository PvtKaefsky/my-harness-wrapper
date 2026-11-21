#!/bin/bash
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALL=${1:-$ROOT/scripts/install-local.sh}
PAYLOAD="$ROOT/config/settings.json"
fails=0

LINE=$(grep -m 1 -E "^  local MERGE='" "$INSTALL")
[ -n "$LINE" ] || { echo "local MERGE= in $INSTALL -> absent"; echo "fail -> not run"; exit 1; }
MERGE=${LINE#*\'}; MERGE=${MERGE%\'}
echo "MERGE read from $INSTALL -> yes"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

check() {
  local label=$1 verdict=pass
  shift
  if ! "$@" >/dev/null; then verdict=FAIL; fails=$((fails + 1)); fi
  echo "$label -> $verdict"
}
merge() { jq -s --arg h /deploy --arg w no --arg v "" "$MERGE" "$1" "$PAYLOAD" > "$2"; }
allow() { jq -c '.permissions.allow' "$1"; }

printf '%s\n' '{"model":"x","permissions":{"allow":["Bash(ls:*)"],"deny":["Bash(rm:*)"]}}' > "$WORK/live.json"
merge "$WORK/live.json" "$WORK/first.json"; first_rc=$?
merge "$WORK/first.json" "$WORK/second.json"; second_rc=$?
check 'the merge runs on a live file holding another allow entry' [ "$first_rc" -eq 0 ]
check 'the existing allow entry survives' jq -e '.permissions.allow | index("Bash(ls:*)") != null' "$WORK/first.json"
check 'mcp__ccd_pr__set_monitor is added once' jq -e '[.permissions.allow[] | select(. == "mcp__ccd_pr__set_monitor")] | length == 1' "$WORK/first.json"
check 'the deny list survives' jq -e '.permissions.deny == ["Bash(rm:*)"]' "$WORK/first.json"
same() { [ "$second_rc" -eq 0 ] && cmp -s <(jq -S . "$WORK/first.json") <(jq -S . "$WORK/second.json"); }
check 'a second run changes nothing' same
echo "allow after the first run -> $(allow "$WORK/first.json")"
echo "allow after the second run -> $(allow "$WORK/second.json")"

printf '%s\n' '{"model":"x"}' > "$WORK/bare.json"
merge "$WORK/bare.json" "$WORK/bare-out.json"
check 'a live file with no permissions gains the entry' jq -e '.permissions.allow == ["mcp__ccd_pr__set_monitor"]' "$WORK/bare-out.json"

jq -s --arg h /deploy --arg w no --arg v "" "[{}] + . | $MERGE" "$PAYLOAD" > "$WORK/none-out.json"
check 'no live file gives the entry' jq -e '.permissions.allow == ["mcp__ccd_pr__set_monitor"]' "$WORK/none-out.json"

printf '%s\n' '{"permissions":{"allow":"Bash(ls:*)"}}' > "$WORK/string.json"
rejects() { ! merge "$1" "$WORK/rejected.json" 2>/dev/null; }
check 'a string permissions.allow fails the merge' rejects "$WORK/string.json"
printf '%s\n' '{"permissions":{"allow":{"a":"mcp__ccd_pr__set_monitor"}}}' > "$WORK/object.json"
check 'an object permissions.allow fails the merge' rejects "$WORK/object.json"
printf '%s\n' '{"permissions":"x"}' > "$WORK/perm-string.json"
check 'a string permissions fails the merge' rejects "$WORK/perm-string.json"

echo "fail -> $fails"
[ "$fails" -eq 0 ]
