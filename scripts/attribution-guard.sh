#!/bin/bash
set -uo pipefail

RE='Generated (with|by) \[?Claude Code|claude\.ai/code/session_'

sanitize() { printf '%s' "$1" | LC_ALL=C tr '\n' ' ' | LC_ALL=C tr '\000-\037\177' '?'; }

block() {
  printf 'attribution-guard: matched line -> %s\n' "$(sanitize "$1")" >&2
  printf 'attribution-guard: remove that attribution line from the pull request body, then retry.\n' >&2
  exit 2
}

scan() {
  local hit
  hit=$(printf '%s\n' "$1" | grep -a -i -E -m1 -- "$RE" 2>/dev/null)
  if [ -n "$hit" ]; then block "$hit"; fi
}

INPUT=$(cat 2>/dev/null)
if [ -z "$INPUT" ]; then exit 0; fi
if ! command -v jq >/dev/null 2>&1; then exit 0; fi

TOOL=$(printf '%s' "$INPUT" | jq -r 'if type == "object" then (.tool_name // empty) else empty end' 2>/dev/null)
if [ -z "$TOOL" ]; then exit 0; fi

if [ "$TOOL" = Bash ]; then
  CMD=$(printf '%s' "$INPUT" | jq -r 'if (.tool_input | type) == "object" then (.tool_input.command // empty) else empty end' 2>/dev/null)
  if [ -z "$CMD" ]; then exit 0; fi
  PR_OP=no
  if printf '%s\n' "$CMD" | grep -a -q -E -- '(^|[^[:alnum:]_-])gh[[:space:]]+pr[[:space:]]+(create|edit)([^[:alnum:]_-]|$)'; then PR_OP=yes; fi
  if printf '%s\n' "$CMD" | grep -a -q -E -- '(^|[^[:alnum:]_-])gh[[:space:]]+api([[:space:]]|$)' \
     && printf '%s\n' "$CMD" | grep -a -q -E -- '/pulls([^[:alnum:]_-]|$)'; then PR_OP=yes; fi
  if [ "$PR_OP" != yes ]; then exit 0; fi
  scan "$CMD"
  while IFS= read -r BODY_FILE; do
    if [ -z "$BODY_FILE" ]; then continue; fi
    if [ ! -f "$BODY_FILE" ] || [ ! -r "$BODY_FILE" ]; then continue; fi
    scan "$(head -c 1048576 -- "$BODY_FILE" 2>/dev/null)"
  done < <(printf '%s\n' "$CMD" \
    | grep -a -o -E -- '--body-file[=[:space:]]+[^[:space:]]+|-F[=[:space:]]+[^[:space:]]+=@[^[:space:]]+|body=@[^[:space:]]+' \
    | sed -E 's/^--body-file[=[:space:]]+//; s/^.*=@//' \
    | sed -E 's/^["'"'"']+//; s/["'"'"']+$//')
else
  scan "$(printf '%s' "$INPUT" | jq -r 'if (.tool_input | type) == "object" or (.tool_input | type) == "array" then ([.tool_input | .. | strings] | .[]) else empty end' 2>/dev/null)"
fi
exit 0
