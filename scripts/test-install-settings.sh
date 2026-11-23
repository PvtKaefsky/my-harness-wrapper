#!/bin/bash
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALL=${1:-$ROOT/scripts/install-local.sh}
BOOTSTRAP=${2:-$ROOT/scripts/bootstrap.sh}
VERIFY=${3:-$ROOT/scripts/verify.sh}
PAYLOAD="$ROOT/config/settings.json"
fails=0

program() {
  local line
  line=$(grep -m 1 -E "^ *(local )?MERGE='" "$1")
  line=${line#*\'}
  printf '%s' "${line%\'}"
}
MERGE=$(program "$INSTALL")
[ -n "$MERGE" ] || { echo "MERGE= in $INSTALL -> absent"; echo "fail -> not run"; exit 1; }
echo "MERGE read from $INSTALL -> yes"
CLOUD=$(program "$BOOTSTRAP")
[ -n "$CLOUD" ] || { echo "MERGE= in $BOOTSTRAP -> absent"; echo "fail -> not run"; exit 1; }
echo "MERGE read from $BOOTSTRAP -> yes"
CARRIES=$(sed -n '/^settings_carries() {$/,/^}$/p' "$VERIFY")
[ -n "$CARRIES" ] || { echo "settings_carries in $VERIFY -> absent"; echo "fail -> not run"; exit 1; }
eval "$CARRIES"
echo "settings_carries read from $VERIFY -> yes"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

check() {
  local label=$1 verdict=pass
  shift
  if ! "$@" >/dev/null; then verdict=FAIL; fails=$((fails + 1)); fi
  echo "$label -> $verdict"
}
merge() { jq -s --arg h /deploy --arg w no --arg v "" "$MERGE" "$1" "$PAYLOAD" > "$2"; }
cloud() { jq -s "$CLOUD" "$1" "$PAYLOAD" > "$2"; }
once() { jq -e -s --arg k "$1" '.[0].permissions[$k] as $n | all(.[1].permissions[$k][]; . as $x | [$n[] | select(. == $x)] | length == 1)' "$2" "$PAYLOAD"; }
show() { jq -c ".permissions.$1" "$2"; }

printf '%s\n' '{"model":"x","permissions":{"allow":["Bash(ls:*)"],"deny":["Bash(rm:*)","Read(**/.env)"]}}' > "$WORK/live.json"
merge "$WORK/live.json" "$WORK/first.json"; first_rc=$?
merge "$WORK/first.json" "$WORK/second.json"; second_rc=$?
check 'the merge runs on a live file holding other allow and deny entries' [ "$first_rc" -eq 0 ]
check 'the existing allow entry survives' jq -e '.permissions.allow | index("Bash(ls:*)") != null' "$WORK/first.json"
check 'every payload allow entry is there once' once allow "$WORK/first.json"
check 'the existing deny entries survive' jq -e '.permissions.deny[:2] == ["Bash(rm:*)", "Read(**/.env)"]' "$WORK/first.json"
check 'every payload deny entry is there once' once deny "$WORK/first.json"
same() { [ "$second_rc" -eq 0 ] && cmp -s <(jq -S . "$WORK/first.json") <(jq -S . "$WORK/second.json"); }
check 'a second run changes nothing' same
echo "allow after the first run -> $(show allow "$WORK/first.json")"
echo "allow after the second run -> $(show allow "$WORK/second.json")"
echo "deny after the first run -> $(show deny "$WORK/first.json")"
echo "deny after the second run -> $(show deny "$WORK/second.json")"

cloud "$WORK/live.json" "$WORK/cloud.json"
agree() { cmp -s <(jq -S .permissions "$WORK/first.json") <(jq -S .permissions "$WORK/cloud.json"); }
check 'the bootstrap merge gives the same permissions' agree

printf '%s\n' '{"model":"x"}' > "$WORK/bare.json"
merge "$WORK/bare.json" "$WORK/bare-out.json"
check 'a live file with no permissions gains the payload entries' jq -e -s '.[0].permissions == .[1].permissions' "$WORK/bare-out.json" "$PAYLOAD"

jq -s --arg h /deploy --arg w no --arg v "" "[{}] + . | $MERGE" "$PAYLOAD" > "$WORK/none-out.json"
check 'no live file gives the payload entries' jq -e -s '.[0].permissions == .[1].permissions' "$WORK/none-out.json" "$PAYLOAD"

rejects() { ! merge "$1" "$WORK/rejected.json" 2>/dev/null && ! cloud "$1" "$WORK/rejected.json" 2>/dev/null; }
for key in allow deny; do
  printf '{"permissions":{"%s":"Bash(ls:*)"}}\n' "$key" > "$WORK/string.json"
  check "a string permissions.$key fails both merges" rejects "$WORK/string.json"
  printf '{"permissions":{"%s":{"a":"Bash(ls:*)"}}}\n' "$key" > "$WORK/object.json"
  check "an object permissions.$key fails both merges" rejects "$WORK/object.json"
done
printf '%s\n' '{"permissions":"x"}' > "$WORK/perm-string.json"
check 'a string permissions fails both merges' rejects "$WORK/perm-string.json"

HELPER=$(sed -n '/^first_line() {$/,/^}$/p' "$INSTALL")
PRIOR=$(sed -n '/^  PERM_PRIOR=/,/^  \[ -n "\$PERM_PRIOR" \]/p' "$INSTALL")
LOOP=$(sed -n '/^  for PERM_KEY in allow deny; do$/,/^  done$/p' "$INSTALL")
eval "$HELPER"
logs() {
  local DST_SETTINGS=$1 SRC_SETTINGS=$PAYLOAD fails=0 rc PERM_PRIOR PERM_KEY PERM_BACK PERM_ADDED
  eval "$PRIOR"
  merge "$DST_SETTINGS" "$WORK/logged.json" 2>/dev/null && mv "$WORK/logged.json" "$DST_SETTINGS"
  eval "$LOOP"
  echo "fails=$fails"
}
logged() { printf '%s\n' "$LOG" | grep -c -F -e "$1"; }
cp "$WORK/live.json" "$WORK/log.json"
LOG=$(logs "$WORK/log.json")
check 'the log names the allow entry added' [ "$(logged '.permissions.allow '"$WORK"'/log.json -> exit=0 entries=2 added=["mcp__ccd_pr__set_monitor"]')" -eq 1 ]
check 'the log names the deny entries added' [ "$(logged ' entries=15 added=["Read(**/.env.local)",')" -eq 1 ]
check 'the log prints no live entry' [ "$(logged 'Bash(')" -eq 0 ]
LOG=$(logs "$WORK/log.json")
check 'the log of a second run names nothing added' [ "$(logged ' added=[]')" -eq 2 ]
LOG=$(logs "$WORK/string.json")
check 'the log of a failed merge reads missing and counts two failures' [ "$(logged ' added=missing')$(logged 'fails=2')" = 21 ]

carry() { [ "$(settings_carries "$2" "$3" "$4")" = "$1" ]; }
check 'verify passes a live permissions with extra entries' carry 'carries' "$WORK/first.json" "$PAYLOAD" permissions
jq '.permissions.deny |= map(select(. != "Read(**/*.pem)"))' "$WORK/first.json" > "$WORK/short-deny.json"
check 'verify fails a live deny list missing a delivered entry' carry 'does not carry' "$WORK/short-deny.json" "$PAYLOAD" permissions
jq '.permissions.allow = ["Bash(ls:*)"]' "$WORK/first.json" > "$WORK/short-allow.json"
check 'verify fails a live allow list missing a delivered entry' carry 'does not carry' "$WORK/short-allow.json" "$PAYLOAD" permissions
printf '%s\n' '{"x":["a"]}' > "$WORK/want-x.json"
printf '%s\n' '{"x":["a","b"]}' > "$WORK/live-x.json"
check 'verify keeps equality for an array under another key' carry 'does not carry' "$WORK/live-x.json" "$WORK/want-x.json" x

echo "fail -> $fails"
[ "$fails" -eq 0 ]
