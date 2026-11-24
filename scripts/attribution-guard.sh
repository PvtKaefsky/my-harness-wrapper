#!/bin/bash
set -uo pipefail

case "${BASH_SOURCE[0]}" in */*) GUARD_DIR=${BASH_SOURCE[0]%/*} ;; *) GUARD_DIR=. ;; esac
RE_FILE="$GUARD_DIR/../git-hooks/lib/attribution.ere"
{ RE=$(< "$RE_FILE"); } 2>/dev/null
RE=${RE%$'\r'}
HIDDEN_LIB="$GUARD_DIR/../git-hooks/lib/hidden-chars.sh"
HIDDEN_FILE="$GUARD_DIR/../git-hooks/lib/hidden-chars.tsv"
WARN=""
. "$HIDDEN_LIB" 2>/dev/null || hidden_swap() { cat; }

sanitize() { printf '%s' "$1" | LC_ALL=C tr '\n' ' ' | LC_ALL=C tr '\000-\037\177' '?'; }

unchecked() {
  printf 'attribution-guard: %s, so the body was not checked.\n' "$1" >&2
  printf 'attribution-guard: restore %s from the harness repository, then retry.\n' "$(sanitize "${2:-$RE_FILE}")" >&2
  exit 2
}

need_re() {
  if [ -z "$RE" ] || [ "$RE" != "${RE%%$'\n'*}" ]; then
    unchecked "$(sanitize "$RE_FILE") holds no single pattern line"
  fi
}

undecoded() {
  printf 'attribution-guard: --input file %s %s, so the body was not checked.\n' "$(sanitize "$1")" "$2" >&2
  printf 'attribution-guard: send a JSON body of at most 1 MiB that jq can parse, then retry.\n' >&2
  exit 2
}

block() {
  printf 'attribution-guard: matched line -> %s\n' "$(sanitize "$1")" >&2
  printf 'attribution-guard: remove that attribution line from the body, then retry.\n' >&2
  exit 2
}

resend() {
  printf 'attribution-guard: %s\n' "$1" >&2
  printf 'attribution-guard: resend the description this create call sent, unchanged, through mcp__github__update_pull_request.\n' >&2
  exit 2
}

hidden() {
  printf 'attribution-guard: hidden character -> %s on line %s\n' "$1" "$2" >&2
  printf 'attribution-guard: remove that character from the body, then retry.\n' >&2
  exit 2
}

scan() {
  local hit rc found action line cp
  need_re
  if ! declare -F hidden_scan >/dev/null; then unchecked "$(sanitize "$HIDDEN_LIB") could not be read" "$HIDDEN_LIB"; fi
  found=$(hidden_swap | hidden_scan "$HIDDEN_FILE") || unchecked "$(sanitize "$HIDDEN_FILE") could not be applied" "$HIDDEN_FILE"
  while IFS=$'\t' read -r action line cp; do
    if [ "$action" = block ]; then hidden "$cp" "$line"; fi
    if [ "$action" != warn ]; then continue; fi
    hit="attribution-guard: zero-width character $cp on line $line of the body; it was sent as written."
    case "$WARN" in *"$hit"*) ;; *) WARN="${WARN:+$WARN }$hit" ;; esac
  done <<< "$found"
  hit=$(printf '%s\n' "$1" | tr '\r' '\n' | grep -a -i -E -- "$RE" 2>/dev/null | sed -n 1p); rc=$?
  if [ "$rc" -gt 1 ]; then unchecked "grep could not apply the pattern (exit=$rc)"; fi
  if [ -n "$hit" ]; then block "$hit"; fi
}

INPUT=$(cat 2>/dev/null)
if [ -z "$INPUT" ]; then exit 0; fi
if ! command -v jq >/dev/null 2>&1; then exit 0; fi

TOOL=$(printf '%s' "$INPUT" | jq -r 'if type == "object" then (.tool_name // empty) else empty end' 2>/dev/null)
if [ -z "$TOOL" ]; then exit 0; fi

EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
if [ "$EVENT" = PostToolUse ]; then
  if [ "$TOOL" != mcp__github__create_pull_request ]; then exit 0; fi
  if [ "$(printf '%s' "$INPUT" | LC_ALL=C wc -c)" -gt 1048576 ]; then
    resend 'the hook input exceeds 1 MiB, so the description was not checked.'
  fi
  BODIES='[.tool_response | ., (.. | strings | try fromjson catch empty)] | [.[] | .. | objects | select(has("body")) | .body | strings]'
  need_re
  hit=$(printf '%s' "$INPUT" | jq -r "$BODIES | .[]" 2>/dev/null | tr '\r' '\n' | grep -a -i -o -E -m1 -- "$RE" 2>/dev/null | head -n 1)
  if [ -n "$hit" ]; then resend "matched line in the response body -> $(sanitize "$hit")"; fi
  COUNT=$(printf '%s' "$INPUT" | jq -r "$BODIES | length" 2>/dev/null)
  if [ -n "$COUNT" ] && [ "$COUNT" != 0 ]; then exit 0; fi
  FAILED=$(printf '%s' "$INPUT" | jq -r '.tool_response as $r | if ($r | type) == "object" and ($r.isError == true or ((($r.error | type) == "string" or ($r.error | type) == "object") and ($r.error | length) > 0)) then "yes" else "no" end' 2>/dev/null)
  if [ "$FAILED" = yes ]; then exit 0; fi
  resend 'the create response carries no string field named body, so the description was not checked.'
fi

if [ "$TOOL" = Bash ]; then
  CMD_FILTER='if (.tool_input | type) == "object" then (.tool_input.command // empty) else empty end'
  CMD=$(printf '%s' "$INPUT" | jq -r "$CMD_FILTER" 2>/dev/null | LC_ALL=C tr -d '\000')
  if [ -z "$CMD" ]; then exit 0; fi
  WRITE_OP=no
  SHORT_F=no
  if printf '%s\n' "$CMD" | grep -a -c -E -- '(^|[^[:alnum:]_-])gh[[:space:]]+(pr|issue)[[:space:]]+(create|edit)([^[:alnum:]_-]|$)' >/dev/null; then WRITE_OP=yes; SHORT_F=yes; fi
  if printf '%s\n' "$CMD" | grep -a -c -E -- '(^|[^[:alnum:]_-])gh[[:space:]]+(issue[[:space:]]+comment|pr[[:space:]]+(comment|review))([^[:alnum:]_-]|$)' >/dev/null; then WRITE_OP=yes; SHORT_F=yes; fi
  if printf '%s\n' "$CMD" | grep -a -c -E -- '(^|[^[:alnum:]_-])gh[[:space:]]+api([[:space:]]|$)' >/dev/null \
     && printf '%s\n' "$CMD" | grep -a -c -E -- '/(pulls|issues)([^[:alnum:]_-]|$)' >/dev/null; then WRITE_OP=yes; fi
  if [ "$WRITE_OP" != yes ]; then exit 0; fi
  scan "$CMD" < <(printf '%s' "$INPUT" | jq -r "$CMD_FILTER" 2>/dev/null)
  while IFS= read -r BODY_FILE; do
    KIND=${BODY_FILE%%:*}
    BODY_FILE=${BODY_FILE#*:}
    if [ -z "$BODY_FILE" ]; then continue; fi
    if [ ! -f "$BODY_FILE" ] || [ ! -r "$BODY_FILE" ]; then continue; fi
    BODY=$(head -c 1048576 -- "$BODY_FILE" 2>/dev/null | LC_ALL=C tr -d '\000')
    scan "$BODY" < <(head -c 1048576 -- "$BODY_FILE" 2>/dev/null)
    if [ "$KIND" = J ]; then
      if [ "$(LC_ALL=C wc -c < "$BODY_FILE")" -gt 1048576 ]; then undecoded "$BODY_FILE" 'exceeds 1 MiB'; fi
      BODY=${BODY#$'\xef\xbb\xbf'}
      DECODED=$(printf '%s' "$BODY" | jq -r '.. | strings' 2>/dev/null | LC_ALL=C tr -d '\000'); JQ_RC=$?
      case "${BODY#"${BODY%%[![:space:]]*}"}" in
        [\{\[]*) if [ "$JQ_RC" -ne 0 ]; then undecoded "$BODY_FILE" "is not JSON jq can parse (jq exit=$JQ_RC)"; fi ;;
      esac
      scan "$DECODED" < <(printf '%s' "$BODY" | jq -r '.. | strings' 2>/dev/null)
    fi
  done < <({
      printf '%s\n' "$CMD" \
        | grep -a -o -E -- '--body-file[=[:space:]]+[^[:space:]]+|-F[=[:space:]]+[^[:space:]]+=@[^[:space:]]+|body=@[^[:space:]]+' \
        | sed -E 's/^--body-file[=[:space:]]+//; s/^.*=@//; s/^/R:/'
      printf '%s\n' "$CMD" \
        | grep -a -o -E -- '--input[=[:space:]]+[^[:space:]]+' \
        | sed -E 's/^--input[=[:space:]]+//; s/^/J:/'
      if [ "$SHORT_F" = yes ]; then
        printf '%s\n' "$CMD" \
          | grep -a -o -E -- '(^|[[:space:]])-F[=[:space:]]*[^[:space:]]+' \
          | sed -E 's/^[[:space:]]*-F[=[:space:]]*//; s/^/R:/'
      fi
    } | sed -E 's/^([RJ]:)["'"'"']+/\1/; s/["'"'"']+$//')
else
  case "$TOOL" in
    mcp__github__push_files|mcp__github__create_or_update_file|mcp__github__delete_file|mcp__github__merge_pull_request|mcp__github__enable_pr_auto_merge)
      KEEP='if type == "object" then del(.content) | (if (.files | type) == "array" then .files |= map(if type == "object" then del(.content) else . end) else . end) else . end' ;;
    *) KEEP='.' ;;
  esac
  TEXTS="if (.tool_input | type) == \"object\" or (.tool_input | type) == \"array\" then ([.tool_input | $KEEP | .. | strings] | .[]) else empty end"
  scan "$(printf '%s' "$INPUT" | jq -r "$TEXTS" 2>/dev/null | LC_ALL=C tr -d '\000')" < <(printf '%s' "$INPUT" | jq -r "$TEXTS" 2>/dev/null)
fi
if [ -n "$WARN" ]; then jq -cn --arg c "$WARN" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}'; fi
exit 0
