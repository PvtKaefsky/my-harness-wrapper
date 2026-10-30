#!/bin/bash
set -uo pipefail
LC_ALL=C

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SETTINGS="$ROOT/config/settings.json"
NAMES_FILE=${1:-}
show() { printf '%s' "$1" | LC_ALL=C tr '\n' ' ' | LC_ALL=C tr '\000-\037\177' '?'; }
SET_SHOW=$(show "$SETTINGS")
not_run() { echo "missing -> not run"; exit 2; }

echo "test -f $SET_SHOW -> $([ -f "$SETTINGS" ] && echo yes || echo no)"
echo "command -v jq -> $(show "$(command -v jq || echo none)")"
if [ -z "$NAMES_FILE" ]; then
  echo "tool names file argument -> absent"
  not_run
fi
FILE_SHOW=$(show "$NAMES_FILE")
echo "test -f $FILE_SHOW -> $([ -f "$NAMES_FILE" ] && echo yes || echo no)"
echo "test -r $FILE_SHOW -> $([ -r "$NAMES_FILE" ] && echo yes || echo no)"
if [ ! -f "$SETTINGS" ] || [ ! -f "$NAMES_FILE" ] || [ ! -r "$NAMES_FILE" ] || ! command -v jq >/dev/null 2>&1; then
  not_run
fi

M_ERRF=$(mktemp 2>/dev/null) || M_ERRF=/dev/null
MATCHERS=$(jq -r 'if type != "object" then error("top level is " + type)
  elif (.hooks | type) != "object" then error("hooks is " + (.hooks | type))
  else .hooks | to_entries[] | select(.key == "PreToolUse" or .key == "PostToolUse") | .key as $e
    | if (.value | type) != "array" then error($e + " is " + (.value | type)) else .value[] end
    | if type != "object" then error($e + " entry is " + type) else . end
    | (if has("matcher") then .matcher else "" end)
    | if type != "string" then error($e + " matcher is " + type)
      elif (explode | any(. < 32 or . == 127)) then error($e + " matcher carries a control character")
      else $e + "\t" + . end
  end' "$SETTINGS" 2>"$M_ERRF"); M_RC=$?
M_ERR=$(cat "$M_ERRF" 2>/dev/null); [ "$M_ERRF" = /dev/null ] || rm -f "$M_ERRF"
MATCHERS=${MATCHERS//$'\r'/}
M_COUNT=$(grep -a -c '' <<< "$MATCHERS"); [ -n "$MATCHERS" ] || M_COUNT=0
echo "jq PreToolUse and PostToolUse matchers of $SET_SHOW -> exit=$M_RC count=$M_COUNT$([ "$M_RC" -eq 0 ] || printf ' [%s]' "$(show "${M_ERR%%$'\n'*}")")"
if [ "$M_RC" -ne 0 ] || [ "$M_COUNT" -eq 0 ]; then
  not_run
fi
EVENTS_OK=yes
for EV in PreToolUse PostToolUse; do
  EV_COUNT=$(grep -a -c "^$EV"$'\t' <<< "$MATCHERS")
  echo "$EV entries -> $EV_COUNT"
  [ "$EV_COUNT" -gt 0 ] || EVENTS_OK=no
done
[ "$EVENTS_OK" = yes ] || not_run

HAVE=$(LC_ALL=C tr -d '\r' < "$NAMES_FILE" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -a -v '^$' | LC_ALL=C sort -u)
H_COUNT=$(grep -a -c '' <<< "$HAVE"); [ -n "$HAVE" ] || H_COUNT=0
echo "distinct tool names in $FILE_SHOW -> $H_COUNT"
if [ "$H_COUNT" -eq 0 ]; then
  not_run
fi

missing=0
MATCH_ALL=no
compared=0
uncompared=0
MATCHED=""
while IFS=$'\t' read -r EVENT MATCHER; do
  [ -n "${EVENT:-}" ] || continue
  echo "$EVENT matcher -> [$(show "$MATCHER")]"
  if [ -z "$MATCHER" ] || [ "$MATCHER" = "*" ]; then
    echo "$EVENT matcher [$(show "$MATCHER")] -> matches every tool, not compared"
    MATCH_ALL=yes
    continue
  fi
  REST=$MATCHER
  while :; do
    NAME=${REST%%|*}
    if ! [[ "$NAME" =~ ^[A-Za-z0-9_-]+$ ]]; then
      echo "$EVENT matcher alternative [$(show "$NAME")] -> not a literal tool name, not compared"
      uncompared=$((uncompared + 1))
    else
      compared=$((compared + 1))
      MATCHED="$MATCHED$NAME"$'\n'
      if grep -a -q -x -F -- "$NAME" <<< "$HAVE"; then
        echo "$EVENT matcher name $NAME in the tool names file -> yes"
      else
        echo "$EVENT matcher name $NAME in the tool names file -> no"
        echo "MISSING $NAME: named by the $EVENT matcher of $SET_SHOW, absent from $FILE_SHOW"
        missing=$((missing + 1))
      fi
    fi
    [ "$REST" != "${REST#*|}" ] || break
    REST=${REST#*|}
  done
done <<< "$MATCHERS"

unmatched=0
if [ "$MATCH_ALL" = yes ]; then
  echo "UNMATCHED check -> not run, a matcher matches every tool"
  HAVE=""
elif [ "$uncompared" -gt 0 ]; then
  echo "UNMATCHED check -> not run, $uncompared alternatives not compared"
  HAVE=""
fi
while IFS= read -r NAME; do
  case "$NAME" in mcp__github__*) ;; *) continue ;; esac
  if ! grep -a -q -x -F -- "$NAME" <<< "$MATCHED"; then
    echo "UNMATCHED $(show "$NAME"): in $FILE_SHOW, in no PreToolUse or PostToolUse matcher of $SET_SHOW"
    unmatched=$((unmatched + 1))
  fi
done <<< "$HAVE"

echo "compared -> $compared"
echo "uncompared -> $uncompared"
echo "unmatched mcp__github__ names -> $unmatched"
echo "missing -> $missing"
if [ "$missing" -gt 0 ]; then exit 1; fi
if [ "$compared" -eq 0 ] || [ "$uncompared" -gt 0 ]; then exit 2; fi
exit 0
