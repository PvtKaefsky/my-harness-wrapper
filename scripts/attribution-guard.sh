#!/bin/bash
set -uo pipefail

case "${BASH_SOURCE[0]}" in */*) GUARD_DIR=${BASH_SOURCE[0]%/*} ;; *) GUARD_DIR=. ;; esac
RE_FILE="$GUARD_DIR/../git-hooks/lib/attribution.ere"
{ RE=$(< "$RE_FILE"); } 2>/dev/null
RE=${RE%$'\r'}

sanitize() { printf '%s' "$1" | LC_ALL=C tr '\n' ' ' | LC_ALL=C tr '\000-\037\177' '?'; }

unchecked() {
  printf 'attribution-guard: %s, so the body was not checked.\n' "$1" >&2
  printf 'attribution-guard: restore %s from the harness repository, then retry.\n' "$(sanitize "$RE_FILE")" >&2
  exit 2
}

need_re() {
  if [ -z "$RE" ] || [ "$RE" != "${RE%%$'\n'*}" ]; then
    unchecked "$(sanitize "$RE_FILE") holds no single pattern line"
  fi
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

scan() {
  local hit rc
  need_re
  hit=$(printf '%s\n' "$1" | grep -a -i -E -m1 -- "$RE" 2>/dev/null); rc=$?
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
  hit=$(printf '%s' "$INPUT" | jq -r "$BODIES | .[]" 2>/dev/null | grep -a -i -o -E -m1 -- ".{0,80}($RE).{0,80}" 2>/dev/null | head -n 1)
  if [ -n "$hit" ]; then resend "matched line in the response body -> $(sanitize "$hit")"; fi
  COUNT=$(printf '%s' "$INPUT" | jq -r "$BODIES | length" 2>/dev/null)
  if [ -n "$COUNT" ] && [ "$COUNT" != 0 ]; then exit 0; fi
  FAILED=$(printf '%s' "$INPUT" | jq -r '.tool_response as $r | if ($r | type) == "object" and ($r.isError == true or ((($r.error | type) == "string" or ($r.error | type) == "object") and ($r.error | length) > 0)) then "yes" else "no" end' 2>/dev/null)
  if [ "$FAILED" = yes ]; then exit 0; fi
  resend 'the create response carries no string field named body, so the description was not checked.'
fi

if [ "$TOOL" = Bash ]; then
  CMD=$(printf '%s' "$INPUT" | jq -r 'if (.tool_input | type) == "object" then (.tool_input.command // empty) else empty end' 2>/dev/null)
  if [ -z "$CMD" ]; then exit 0; fi
  WRITE_OP=no
  SHORT_F=no
  if printf '%s\n' "$CMD" | grep -a -q -E -- '(^|[^[:alnum:]_-])gh[[:space:]]+(pr|issue)[[:space:]]+(create|edit)([^[:alnum:]_-]|$)'; then WRITE_OP=yes; SHORT_F=yes; fi
  if printf '%s\n' "$CMD" | grep -a -q -E -- '(^|[^[:alnum:]_-])gh[[:space:]]+(issue[[:space:]]+comment|pr[[:space:]]+(comment|review))([^[:alnum:]_-]|$)'; then WRITE_OP=yes; SHORT_F=yes; fi
  if printf '%s\n' "$CMD" | grep -a -q -E -- '(^|[^[:alnum:]_-])gh[[:space:]]+api([[:space:]]|$)' \
     && printf '%s\n' "$CMD" | grep -a -q -E -- '/(pulls|issues)([^[:alnum:]_-]|$)'; then WRITE_OP=yes; fi
  if [ "$WRITE_OP" != yes ]; then exit 0; fi
  scan "$CMD"
  while IFS= read -r BODY_FILE; do
    if [ -z "$BODY_FILE" ]; then continue; fi
    if [ ! -f "$BODY_FILE" ] || [ ! -r "$BODY_FILE" ]; then continue; fi
    scan "$(head -c 1048576 -- "$BODY_FILE" 2>/dev/null)"
  done < <({
      printf '%s\n' "$CMD" \
        | grep -a -o -E -- '--body-file[=[:space:]]+[^[:space:]]+|-F[=[:space:]]+[^[:space:]]+=@[^[:space:]]+|body=@[^[:space:]]+' \
        | sed -E 's/^--body-file[=[:space:]]+//; s/^.*=@//'
      if [ "$SHORT_F" = yes ]; then
        printf '%s\n' "$CMD" \
          | grep -a -o -E -- '(^|[[:space:]])-F[=[:space:]]*[^[:space:]]+' \
          | sed -E 's/^[[:space:]]*-F[=[:space:]]*//'
      fi
    } | sed -E 's/^["'"'"']+//; s/["'"'"']+$//')
else
  case "$TOOL" in
    mcp__github__push_files|mcp__github__create_or_update_file|mcp__github__delete_file|mcp__github__merge_pull_request|mcp__github__enable_pr_auto_merge)
      KEEP='if type == "object" then del(.content) | (if (.files | type) == "array" then .files |= map(if type == "object" then del(.content) else . end) else . end) else . end' ;;
    *) KEEP='.' ;;
  esac
  scan "$(printf '%s' "$INPUT" | jq -r "if (.tool_input | type) == \"object\" or (.tool_input | type) == \"array\" then ([.tool_input | $KEEP | .. | strings] | .[]) else empty end" 2>/dev/null)"
fi
exit 0
