#!/bin/bash
set -uo pipefail

WEB_RE='\.(html|htm|css|scss|sass|less|jsx|tsx|vue|svelte|astro)(\.[A-Za-z0-9]+)?$'
START='(^|\$\(|`)[[:space:]({]*((then|do|else|elif|!)[[:space:]]+)?'
ASSIGN='([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
WRAP='((env|sudo|command|exec|nohup|time|timeout|xargs)[[:space:]]+([^[:space:]]+[[:space:]]+)*)?'
RUNNER='(npx|npx\.cmd|pnpx|bunx|pnpm[[:space:]]+dlx|npm[[:space:]]+exec)[[:space:]](.*[[:space:]=])?["'\'']?modern-web-guidance(@[^[:space:]"'\'']*)?["'\'']?([[:space:]]|$)'
OFF_RE='DISABLE_TELEMETRY=(1|true|"1"|"true"|'\''1'\''|'\''true'\'')'
RUN_RE="${START}${ASSIGN}${WRAP}${RUNNER}"
PREFIX_RE="${START}${ASSIGN}${OFF_RE}[[:space:]]+${ASSIGN}${WRAP}${RUNNER}"
EXPORT_RE="^[[:space:]{]*export[[:space:]]+([^[:space:]]+[[:space:]]+)*${OFF_RE}[[:space:]]*\$"
UNSET_RE='(unset|-u|--unset)[[:space:]=]+([^;&|]*[[:space:]])?DISABLE_TELEMETRY|(^|[^[:alnum:]_-])env[[:space:]]+([^;&|]*[[:space:]])?(-i|--ignore-environment)([[:space:]]|$)'
SEP_RE='(&&|\|\||[;&|])$'
WEB_DENY='modern-web-guidance applies only to web front-end work. In a repository without web files, call the skill again with args naming the web file the task creates or changes.'

say() { printf 'web-guidance-gate: %s\n' "$1" >&2; }
sanitize() { printf '%s' "$1" | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/; /g' | LC_ALL=C tr '\000-\037\177' '?'; }

INPUT=$(cat 2>/dev/null)
if ! command -v jq >/dev/null 2>&1; then
  say 'jq is not on PATH, so the call was not checked.'
  exit 0
fi
field() { printf '%s' "$INPUT" | jq -r "$1 // empty | strings" 2>/dev/null; }

if ! TOOL=$(printf '%s' "$INPUT" | jq -e -r 'if type == "object" then (.tool_name // "" | strings) else error end' 2>/dev/null); then
  say 'could not read the hook input, so the call was not checked.'
  exit 0
fi

SKILL=""
CMD=""
case "$TOOL" in
  Skill)
    SKILL=$(field .tool_input.skill)
    case "$SKILL" in modern-web-guidance:*) ;; *) exit 0 ;; esac ;;
  Bash)
    CMD=$(field .tool_input.command)
    case "$CMD" in *modern-web-guidance*) ;; *) exit 0 ;; esac
    GATED=no
    OFF=no
    BARE=no
    CLEAR=no
    PREV=';'
    while IFS= read -r line; do
      sep=""
      seg=$line
      if [[ $line =~ $SEP_RE ]]; then sep=${BASH_REMATCH[1]}; seg=${line%"$sep"}; fi
      if [[ $seg =~ $EXPORT_RE ]]; then
        case "$PREV|$sep" in ';|;'|';|&&'|';|') OFF=yes ;; esac
      elif [[ $seg =~ $RUN_RE ]]; then
        GATED=yes
        if [ "$OFF" = no ] && ! [[ $seg =~ $PREFIX_RE ]]; then BARE=yes; fi
      fi
      PREV=${sep:-;}
    done < <(printf '%s\n' "$CMD" | sed -e ':a' -e '/\\$/N' -e 's/\\\n//' -e 'ta' | sed -E 's/(&&|\|\||[;&|])/\1\n/g')
    [ "$GATED" = yes ] || exit 0
    while IFS= read -r a; do
      [[ $a =~ ^${OFF_RE}$ ]] || CLEAR=yes
    done < <(printf '%s\n' "$CMD" | grep -a -o -E -- 'DISABLE_TELEMETRY=[^[:space:];&|)`]*')
    if [[ $CMD =~ $UNSET_RE ]]; then CLEAR=yes; fi ;;
  *) exit 0 ;;
esac

SID=$(field .session_id)
CWD=$(field .cwd)
MARKER=""
if [ -n "${CLAUDE_PLUGIN_DATA:-}" ] && [[ $SID =~ ^[A-Za-z0-9_-]+$ ]]; then
  MARKER="$CLAUDE_PLUGIN_DATA/web-guidance-sessions/$SID"
fi

web_repo() {
  local top files f
  [ -n "$CWD" ] || return 1
  top=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || return 1
  files=$(git -C "$top" -c core.quotePath=false ls-files 2>/dev/null) || return 1
  if printf '%s\n' "$files" | grep -a -q -i -E -- "$WEB_RE"; then return 0; fi
  [ "$SKILL" = modern-web-guidance:chrome-extensions ] || return 1
  while IFS= read -r f; do
    if [ -f "$top/$f" ] && [ ! -L "$top/$f" ] && grep -a -q -F -- '"manifest_version"' "$top/$f" 2>/dev/null; then return 0; fi
  done < <(printf '%s\n' "$files" | grep -a -E -- '(^|/)manifest\.json$')
  return 1
}

args_name_web() {
  [ "$TOOL" = Skill ] || return 1
  field .tool_input.args | tr -s '[:space:]' '\n' \
    | sed -E "s/^[\"'(\`<]+//; s/[\"'),.;:!?\`>]+\$//" \
    | grep -a -q -i -E -- "(^|/)[^/]+$WEB_RE"
}

if ! { web_repo || args_name_web || { [ -n "$MARKER" ] && [ -f "$MARKER" ]; }; }; then
  say "$WEB_DENY"
  exit 2
fi

if [ "$TOOL" = Skill ]; then
  if [ -n "$MARKER" ]; then mkdir -p -- "${MARKER%/*}" 2>/dev/null && : > "$MARKER" 2>/dev/null; fi
  exit 0
fi

if [ "$CLEAR" = yes ]; then
  say 'the command unsets DISABLE_TELEMETRY or sets it to a value other than 1 or true; remove that and run the package with DISABLE_TELEMETRY=1.'
  exit 2
fi
case "${DISABLE_TELEMETRY:-}" in 1|true) exit 0 ;; esac
if [ "$BARE" = yes ]; then
  say "run the package with telemetry off: export DISABLE_TELEMETRY=1; $(sanitize "$CMD")"
  exit 2
fi
exit 0
