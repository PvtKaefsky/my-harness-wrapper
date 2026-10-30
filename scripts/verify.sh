#!/bin/bash
set -uo pipefail

REPO=${HARNESS_DIR:-/opt/my-harness-wrapper}
HARNESS_REF=main
HARNESS_MAIL="noreply@anthropic.com"
run() { echo "\$ $*"; "$@" 2>&1; echo "exit=$?"; }
sanitize() { printf '%s' "$1" | LC_ALL=C tr '\n' ' ' | LC_ALL=C tr '\000-\037\177' '?'; }
cap() { printf '%s' "${1%%$'\n'*}" | LC_ALL=C cut -b 1-120; }
settings_probe() {
  jq -S -c --arg k "$2" 'if type != "object" then {state: ("top level is " + type)}
    elif (has($k) | not) then {state: "key absent"}
    else {state: "present", value: .[$k]} end' "$1" 2>/dev/null
}
settings_carries() {
  local live_docs want_docs
  live_docs=$(jq -c -s . "$1" 2>/dev/null) || return 2
  want_docs=$(jq -c -s . "$2" 2>/dev/null) || return 2
  printf '%s\n%s\n' "$live_docs" "$want_docs" | jq -n -r --arg k "$3" '
    input as $live | input as $want |
    if ($live | length) != 1 then "live file holds " + ($live | length | tostring) + " JSON documents"
    elif ($want | length) != 1 then "delivered file holds " + ($want | length | tostring) + " JSON documents"
    else $live[0] as $L | $want[0] as $W
      | if ($L | type) != "object" then "live top level is " + ($L | type)
        elif ($W | type) != "object" then "delivered top level is " + ($W | type)
        elif ($L | has($k) | not) then "absent from the live file"
        elif ($W | has($k) | not) then "absent from the delivered file"
        elif ((({($k): $L[$k]}) * ({($k): $W[$k]}))[$k]) == $L[$k] then "carries"
        else "does not carry" end
    end' 2>/dev/null
}
resolve_cli() {
  local found base cand
  found=$(command -v claude 2>/dev/null)
  if [ -n "$found" ]; then CLI=$found; CLI_FROM=PATH; return; fi
  if [ -n "${CLAUDE_CODE_EXECPATH:-}" ] && [ -f "$CLAUDE_CODE_EXECPATH" ]; then
    CLI=$CLAUDE_CODE_EXECPATH; CLI_FROM=CLAUDE_CODE_EXECPATH; return
  fi
  if [ -n "${LOCALAPPDATA:-}" ] && [ "$CYGPATH" != none ]; then
    base=$(cygpath -u "$LOCALAPPDATA" 2>/dev/null)
    found=$(for cand in "$base"/Claude-Data/claude_*/claude-code/*/*/claude.exe; do
      [ -f "$cand" ] && printf '%s\n' "$cand"
    done | sort -V | tail -n 1)
    if [ -n "$found" ]; then CLI=$found; CLI_FROM="the highest-sorting desktop app CLI under LOCALAPPDATA"; return; fi
  fi
  CLI=""; CLI_FROM=none
}
canon_path() {
  local u r m
  [ -n "$1" ] || return 1
  if [ "$CYGPATH" = none ]; then readlink -f "$1" 2>/dev/null; return; fi
  u=$(cygpath -u -- "$1" 2>/dev/null); [ -n "$u" ] || u=$1
  r=$(readlink -f -- "$u" 2>/dev/null); [ -n "$r" ] || return 1
  m=$(cygpath -m -l -- "$r" 2>/dev/null); [ -n "$m" ] || return 1
  printf '%s' "$m" | LC_ALL=C tr 'A-Z' 'a-z'
}
hook_run() {
  if [ -n "$HOOK_HARNESS_DIR" ]; then HARNESS_DIR=$HOOK_HARNESS_DIR bash -c "$1"
  else env -u HARNESS_DIR bash -c "$1"; fi
}
guard_clean_check() {
  local input=$1 in_rc=$2 cmd=$3 cmd_rc=$4 event=$5 what=$6 err rc show ok=no
  if [ "$in_rc" -ne 0 ] || [ -z "$input" ]; then
    show="sample input not built (jq exit=$in_rc)"
  elif [ "$cmd_rc" -ne 0 ] || [ -z "$cmd" ]; then
    show="no $event command in $LIVE_SETTINGS references attribution-guard.sh (jq exit=$cmd_rc)"
  else
    err=$(printf '%s' "$input" | hook_run "$cmd" 2>&1 >/dev/null); rc=$?
    if [ "$rc" -eq 0 ]; then
      show="exit=0"; ok=yes
    else
      show="exit=$rc [$(sanitize "$(cap "$err")")]"
    fi
  fi
  echo "run the live $event command on $what -> $show"
  if [ "$ok" != yes ]; then
    echo "FAIL $event attribution guard: expected exit=0 from the live $event command in $LIVE_SETTINGS on $what, actual $show"
    fail=1
  fi
}
plugin_deps_check() {
  local id=$1 raw rc count p conv p_show names name
  local name_re='^(@[A-Za-z0-9_~-][A-Za-z0-9._~-]*/)?[A-Za-z0-9_~-][A-Za-z0-9._~-]*$'
  raw=$(printf '%s' "$PLUGIN_JSON" | jq -r --arg id "$id" 'if type == "array" then [.[] | select(.id == $id) | .installPath | strings] | unique | .[] else error("top level is " + type) end' 2>/dev/null); rc=$?
  raw=${raw//$'\r'/}
  count=$(printf '%s' "$raw" | grep -a -c '')
  echo "jq installPath of $id from claude plugin list --json -> exit=$rc count=$count value=[$(sanitize "$raw")]"
  if [ "$rc" -ne 0 ] || [ "$count" != 1 ]; then
    echo "FAIL plugin installPath: expected one installPath for $id from claude plugin list --json, actual jq exit=$rc count=$count"
    fail=1
    return
  fi
  p=$raw
  if [ "$CYGPATH" != none ]; then
    conv=$(cygpath -u "$raw" 2>/dev/null) && [ -n "$conv" ] && p=$conv
  fi
  p_show=$(sanitize "$p")
  case "$p" in
    /*) ;;
    *) echo "FAIL plugin installPath: expected an absolute installPath for $id, actual [$p_show]"
       fail=1
       return ;;
  esac
  echo "test -d $p_show -> $([ -d "$p" ] && echo yes || echo no)"
  if [ ! -d "$p" ]; then
    echo "FAIL plugin installPath: expected a directory at the installPath of $id, actual [$p_show] absent"
    fail=1
    return
  fi
  echo "test -f $p_show/package.json -> $([ -f "$p/package.json" ] && echo yes || echo no)"
  [ -f "$p/package.json" ] || return
  names=$(jq -r 'if type != "object" then error("top level is " + type)
    elif (has("dependencies") | not) then empty
    elif (.dependencies | type) != "object" then error("dependencies is " + (.dependencies | type))
    else .dependencies | keys[] end' "$p/package.json" 2>/dev/null); rc=$?
  names=${names//$'\r'/}
  echo "jq .dependencies keys $p_show/package.json -> exit=$rc count=$(printf '%s' "$names" | grep -a -c '')"
  if [ "$rc" -ne 0 ]; then
    echo "FAIL plugin dependencies: expected an object or no dependencies key in $p_show/package.json of $id, actual jq exit=$rc"
    fail=1
    return
  fi
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if ! [[ "$name" =~ $name_re ]]; then
      echo "FAIL plugin dependency: expected a package name matching $name_re in $p_show/package.json of $id, actual [$(sanitize "$name")]"
      fail=1
      continue
    fi
    if [ -f "$p/node_modules/$name/package.json" ]; then
      echo "test -f $p_show/node_modules/$name/package.json -> yes"
    else
      echo "test -f $p_show/node_modules/$name/package.json -> no"
      echo "FAIL plugin dependency: expected $name, declared by $id, to resolve at $p_show/node_modules/$name/package.json, actual absent"
      fail=1
    fi
  done <<< "$names"
}

run id
echo "HOME -> ${HOME:-}"
run ls -ld ~/.claude /root/.claude /home/user/.claude
echo "command -v jq -> $(command -v jq || echo none)"
if [ -z "${CLAUDE_CONFIG_DIR+set}" ]; then CCD_SHOW=unset
elif [ -z "$CLAUDE_CONFIG_DIR" ]; then CCD_SHOW="set but empty"
else CCD_SHOW="$CLAUDE_CONFIG_DIR"; fi
echo "CLAUDE_CONFIG_DIR -> $CCD_SHOW"
LIVE_DIR="${CLAUDE_CONFIG_DIR-${HOME:-/root}/.claude}"
echo "\${CLAUDE_CONFIG_DIR-\$HOME/.claude} -> ${LIVE_DIR:-empty}"
CYGPATH=$(command -v cygpath || echo none)
if [ "$CYGPATH" != none ] && [ -n "$LIVE_DIR" ]; then
  LIVE_CONV=$(cygpath -u "$LIVE_DIR" 2>/dev/null); LIVE_CONV_RC=$?
  echo "cygpath -u $LIVE_DIR -> exit=$LIVE_CONV_RC value=${LIVE_CONV:-empty}"
  [ "$LIVE_CONV_RC" -ne 0 ] || [ -z "$LIVE_CONV" ] || LIVE_DIR=$LIVE_CONV
fi
case "${LIVE_DIR:-}" in
  /*) ;;
  *) echo "FAIL live config dir path: expected an absolute path, actual ${LIVE_DIR:-empty}"; exit 1 ;;
esac
if [ "$CYGPATH" = none ]; then CANON_HOW="readlink -f"
else CANON_HOW="readlink -f, cygpath -m -l, ASCII lowercased"; fi
LIVE_REAL=$(canon_path "$LIVE_DIR")
echo "$CANON_HOW $LIVE_DIR -> $(sanitize "${LIVE_REAL:-unresolved}")"

resolve_cli
echo "command -v claude -> $(command -v claude || echo none)"
echo "CLAUDE_CODE_EXECPATH -> ${CLAUDE_CODE_EXECPATH:-unset or empty}"
echo "claude CLI -> ${CLI:-none} from $CLI_FROM"
if [ -n "$CLI" ]; then
  run "$CLI" --version
  echo "\$ claude plugin list --json"
  PLUGIN_JSON=$("$CLI" plugin list --json 2>/dev/null); PLUGIN_RC=$?
else
  PLUGIN_JSON=""; PLUGIN_RC=127
fi
echo "claude plugin list --json -> exit=$PLUGIN_RC"
PLUGIN_IDS=$(printf '%s' "$PLUGIN_JSON" | jq -r 'if type == "array" then (.[] | .id // empty) else empty end' 2>/dev/null); IDS_RC=$?
PLUGIN_IDS=${PLUGIN_IDS//$'\r'/}
PLUGIN_ARRAY=$(printf '%s' "$PLUGIN_JSON" | jq -r 'type' 2>/dev/null)
echo "jq type of that output -> ${PLUGIN_ARRAY:-unreadable}"
if [ "$PLUGIN_RC" -ne 0 ]; then CLI_PLUGINS=unknown
elif [ "$PLUGIN_ARRAY" != array ] || [ "$IDS_RC" -ne 0 ]; then CLI_PLUGINS=unknown
elif [ -z "$PLUGIN_IDS" ]; then CLI_PLUGINS=no
else CLI_PLUGINS=yes; fi
echo "CLI_PLUGINS -> $CLI_PLUGINS"
echo "plugin ids -> $(sanitize "${PLUGIN_IDS:-none}")"

LIVE_SETTINGS_STATE=$(jq -r 'if type == "object" then (if has("enabledPlugins") then "key present" else "key absent" end) else "top level is " + type end' "$LIVE_DIR/settings.json" 2>/dev/null)
if [ ! -f "$LIVE_DIR/settings.json" ]; then LIVE_SETTINGS_STATE="file absent"
elif [ -z "$LIVE_SETTINGS_STATE" ]; then LIVE_SETTINGS_STATE="unreadable or no JSON document"
elif [ "$LIVE_SETTINGS_STATE" != "${LIVE_SETTINGS_STATE%%$'\n'*}" ]; then LIVE_SETTINGS_STATE="more than one JSON document"
fi
echo "$LIVE_DIR/settings.json enabledPlugins -> $LIVE_SETTINGS_STATE"
case "$LIVE_SETTINGS_STATE" in
  "key present") HAS_EP=yes ;;
  "key absent") HAS_EP=no ;;
  *) HAS_EP=unknown ;;
esac
echo "HAS_EP -> $HAS_EP"

MANIFEST="$LIVE_DIR/.my-harness-wrapper.manifest.json"
echo "test -f $MANIFEST -> $([ -f "$MANIFEST" ] && echo yes || echo no)"
if [ ! -f "$MANIFEST" ]; then
  echo "FAIL manifest: expected .my-harness-wrapper.manifest.json in $LIVE_DIR, actual absent"
  exit 1
fi
run cat "$MANIFEST"

fail=0

want_commit=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null)
have_commit=$(jq -r '.commit // ""' "$MANIFEST" 2>/dev/null)
if [ "${have_commit:-unresolved-manifest}" != "${want_commit:-unresolved-repo}" ]; then
  echo "FAIL manifest.commit: expected ${want_commit:-unresolved-repo} from git -C $REPO rev-parse --short HEAD, actual ${have_commit:-unresolved-manifest}"
  fail=1
fi

SETUP="$REPO/env/setup.sh"
WANT_FROM="the export BOOTSTRAP_VERSION= line of $SETUP"
echo "test -f $SETUP -> $([ -f "$SETUP" ] && echo yes || echo no)"
EXPORT_LINES=$(grep -a '^export BOOTSTRAP_VERSION=' "$SETUP" 2>/dev/null); EXPORT_RC=$?
if [ "$EXPORT_RC" -gt 1 ]; then
  WANT_STATE=unread; WANT_SHOW="not read (grep exit=$EXPORT_RC)"
elif [ "$EXPORT_RC" -eq 1 ]; then
  WANT_STATE=unread; WANT_SHOW="no such line (grep exit=1)"
elif [ -z "$EXPORT_LINES" ]; then
  WANT_STATE=unread; WANT_SHOW="matched but produced no output (grep exit=0)"
elif [ "$EXPORT_LINES" != "${EXPORT_LINES%%$'\n'*}" ]; then
  WANT_STATE=unread
  WANT_SHOW="more than one line [$(sanitize "$EXPORT_LINES")] (grep exit=0)"
else
  want_version=${EXPORT_LINES#export BOOTSTRAP_VERSION=}
  want_version=${want_version%"${want_version##*[!$' \t']}"}
  case "$want_version" in
    '')
      WANT_STATE=unread; WANT_SHOW="present and empty (grep exit=0)" ;;
    *[!0-9A-Za-z._-]*)
      WANT_STATE=unread
      WANT_SHOW="unparsed value [$(sanitize "$want_version")] (grep exit=0)" ;;
    *)
      WANT_STATE=value; WANT_SHOW="[$want_version]" ;;
  esac
fi
echo "grep '^export BOOTSTRAP_VERSION=' $SETUP -> $WANT_SHOW"
case "$WANT_STATE" in
  value) ;;
  unread)
    echo "FAIL expected version: expected one 'export BOOTSTRAP_VERSION=' line in $SETUP carrying a value of [0-9A-Za-z._-], actual $WANT_SHOW"
    fail=1 ;;
  *)
    echo "FAIL expected version: expected a known internal state, actual [$WANT_STATE]"
    fail=1 ;;
esac
VER_PROG='if type != "object" then "!top level is " + type
elif (has("bootstrap_version") | not) then "!field absent"
elif .bootstrap_version == null then "!field null"
elif (.bootstrap_version | type) != "string" then "!field is " + (.bootstrap_version | type)
else "=" + .bootstrap_version end'
have_version=$(jq -r "$VER_PROG" "$MANIFEST" 2>/dev/null); VER_RC=$?
if [ "$VER_RC" -ne 0 ]; then
  VER_SHOW="unreadable (jq exit=$VER_RC)"; VER_STATE=fail
elif [ -z "$have_version" ]; then
  VER_SHOW="no JSON document (jq exit=0)"; VER_STATE=fail
elif [ "$have_version" != "${have_version%%$'\n'*}" ]; then
  VER_SHOW="multiple values extracted [$(printf '%s' "$have_version" | tr '\n' ' ')] (jq exit=0)"; VER_STATE=fail
else
  case "$have_version" in
    '!'*) VER_SHOW="${have_version#!} (jq exit=0)"; VER_STATE=fail ;;
    '=')  VER_SHOW="present and empty (jq exit=0)"; VER_STATE=note ;;
    '='*) VER_SHOW="${have_version#=}"; VER_STATE=compare ;;
    *)    VER_SHOW="unrecognised extraction [$have_version]"; VER_STATE=fail ;;
  esac
fi
echo "jq .bootstrap_version $MANIFEST -> $VER_SHOW"
echo "test -f /home/user/bootstrap.log -> $([ -f /home/user/bootstrap.log ] && echo yes || echo no)"
if [ -f /home/user/bootstrap.log ]; then
  BLOG_LINE=$(grep -m1 '^BOOTSTRAP_VERSION=' /home/user/bootstrap.log 2>/dev/null); BLOG_RC=$?
  if [ "$BLOG_RC" -eq 0 ]; then BLOG_SHOW="$BLOG_LINE"
  elif [ "$BLOG_RC" -eq 1 ]; then BLOG_SHOW="no BOOTSTRAP_VERSION line (grep exit=1)"
  else BLOG_SHOW="unreadable (grep exit=$BLOG_RC)"; fi
  echo "grep -m1 '^BOOTSTRAP_VERSION=' /home/user/bootstrap.log -> $BLOG_SHOW"
fi
case "$VER_STATE" in
  fail)
    echo "FAIL manifest.bootstrap_version: expected a string version in $MANIFEST, actual $VER_SHOW"
    fail=1 ;;
  note|compare)
    if [ "$WANT_STATE" != value ]; then
      echo "compare manifest.bootstrap_version against $WANT_FROM -> no, no expectation was read"
    elif [ "$VER_STATE" = note ]; then
      echo "NOTE manifest.bootstrap_version: expected $want_version from $WANT_FROM, actual $VER_SHOW; not counted into the exit status"
    elif [ "$VER_SHOW" != "$want_version" ]; then
      echo "FAIL manifest.bootstrap_version: expected $want_version from $WANT_FROM, actual $VER_SHOW"
      fail=1
    else
      echo "compare manifest.bootstrap_version against $WANT_FROM -> yes, both $want_version"
    fi ;;
  *)
    echo "FAIL manifest.bootstrap_version: expected a known internal state, actual [$VER_STATE]"
    fail=1 ;;
esac

if [ "$CLI_PLUGINS" = unknown ]; then
  echo "FAIL live config dir agreement: expected claude plugin list --json to report a plugin state, actual could not tell (exit=$PLUGIN_RC, type ${PLUGIN_ARRAY:-unreadable})"
  fail=1
elif [ "$HAS_EP" = unknown ]; then
  echo "FAIL live config dir agreement: expected a readable object in $LIVE_DIR/settings.json, actual $LIVE_SETTINGS_STATE"
  fail=1
elif [ "$HAS_EP" != "$CLI_PLUGINS" ]; then
  echo "FAIL live config dir agreement: expected claude plugin list and $LIVE_DIR/settings.json to agree, actual plugins-listed=$CLI_PLUGINS and enabledPlugins=$HAS_EP"
  fail=1
fi

MAN_RAW=$(jq -r '.config_dir // ""' "$MANIFEST" 2>/dev/null); MAN_RC=$?
if [ "$MAN_RC" -ne 0 ]; then
  MAN_DIR=""; MAN_SHOW="unreadable (jq exit=$MAN_RC)"
elif [ -z "$MAN_RAW" ]; then
  MAN_DIR=""; MAN_SHOW="absent or empty"
else
  MAN_DIR="$MAN_RAW"; MAN_SHOW="$MAN_RAW"
  if [ "$CYGPATH" != none ]; then
    MAN_CONV=$(cygpath -u "$MAN_RAW" 2>/dev/null) && [ -n "$MAN_CONV" ] && MAN_DIR=$MAN_CONV && MAN_SHOW="$MAN_RAW, cygpath -u $MAN_CONV"
  fi
  case "$MAN_DIR" in /*) ;; *) MAN_SHOW="$MAN_RAW (not an absolute path)"; MAN_DIR="" ;; esac
fi
echo "jq -r .config_dir $MANIFEST -> $MAN_SHOW"
MAN_REAL=$([ -n "$MAN_DIR" ] && canon_path "$MAN_DIR")
if [ "${LIVE_REAL:-unresolved-live}" != "${MAN_REAL:-unresolved-manifest}" ]; then
  echo "FAIL manifest.config_dir: expected $LIVE_DIR (resolves to $(sanitize "${LIVE_REAL:-unresolved}")), actual $MAN_SHOW (resolves to $(sanitize "${MAN_REAL:-unresolved}"))"
  fail=1
fi

DELIVERED_MD="$REPO/config/CLAUDE.md"
LIVE_MD="$LIVE_DIR/CLAUDE.md"
echo "test -f $DELIVERED_MD -> $([ -f "$DELIVERED_MD" ] && echo yes || echo no)"
echo "test -f $LIVE_MD -> $([ -f "$LIVE_MD" ] && echo yes || echo no)"
if [ ! -f "$DELIVERED_MD" ]; then
  echo "FAIL payload: expected a file at $DELIVERED_MD, actual absent"
  fail=1
elif [ ! -f "$LIVE_MD" ]; then
  echo "FAIL payload: expected $LIVE_MD delivered from $DELIVERED_MD, actual absent"
  fail=1
else
  cmp -s "$DELIVERED_MD" "$LIVE_MD"; CMP_RC=$?
  echo "cmp -s $DELIVERED_MD $LIVE_MD -> exit=$CMP_RC"
  case "$CMP_RC" in
    0) echo "compare payload against $DELIVERED_MD -> yes, the live file is identical" ;;
    1) echo "FAIL payload: expected $LIVE_MD identical to $DELIVERED_MD, actual differs"
       fail=1 ;;
    *) echo "FAIL payload: expected cmp to compare $LIVE_MD against $DELIVERED_MD, actual cmp exit=$CMP_RC"
       fail=1 ;;
  esac
fi

DELIVERED_SETTINGS="$REPO/config/settings.json"
LIVE_SETTINGS="$LIVE_DIR/settings.json"
echo "test -f $DELIVERED_SETTINGS -> $([ -f "$DELIVERED_SETTINGS" ] && echo yes || echo no)"
echo "test -f $LIVE_SETTINGS -> $([ -f "$LIVE_SETTINGS" ] && echo yes || echo no)"
SKEYS=$(jq -r 'if type == "object" then keys_unsorted[] else empty end' "$DELIVERED_SETTINGS" 2>/dev/null); SKEYS_RC=$?
SKEYS=${SKEYS//$'\r'/}
if [ "$SKEYS_RC" -ne 0 ] || [ -z "$SKEYS" ]; then
  echo "FAIL settings: expected a JSON object with at least one key in $DELIVERED_SETTINGS, actual jq exit=$SKEYS_RC with $(printf '%s' "$SKEYS" | grep -a -c '') keys"
  fail=1
fi
echo "keys delivered by $DELIVERED_SETTINGS -> $(sanitize "${SKEYS:-none}")"
while IFS= read -r SKEY || [ -n "${SKEY:-}" ]; do
  [ -n "${SKEY:-}" ] || continue
  WANT_SET=$(settings_probe "$DELIVERED_SETTINGS" "$SKEY"); SWANT_RC=$?
  HAVE_SET=$(settings_probe "$LIVE_SETTINGS" "$SKEY"); SHAVE_RC=$?
  if [ "$SHAVE_RC" -ne 0 ] || [ -z "$HAVE_SET" ]; then
    HAVE_SHOW="unreadable (jq exit=$SHAVE_RC)"
  else
    HAVE_SHOW="$(sanitize "$HAVE_SET")"
  fi
  if [ "$SWANT_RC" -ne 0 ] || [ -z "$WANT_SET" ]; then
    echo "FAIL settings.$SKEY: expected a value from $DELIVERED_SETTINGS, actual no expectation could be read (jq exit=$SWANT_RC)"
    fail=1
    continue
  fi
  case "$WANT_SET" in
    *'"state":"present"'*) ;;
    *)
      echo "FAIL settings.$SKEY: expected $SKEY present in $DELIVERED_SETTINGS, actual $(sanitize "$WANT_SET")"
      fail=1
      continue ;;
  esac
  CARRY=$(settings_carries "$LIVE_SETTINGS" "$DELIVERED_SETTINGS" "$SKEY"); CARRY_RC=$?
  if [ "$CARRY_RC" -ne 0 ] || [ -z "$CARRY" ]; then
    CARRY_SHOW="not determined (jq exit=$CARRY_RC)"
  else
    CARRY_SHOW="$(sanitize "$CARRY")"
  fi
  if [ "$CARRY" != "carries" ]; then
    echo "FAIL settings.$SKEY: expected $LIVE_SETTINGS to carry $(sanitize "$WANT_SET") from $DELIVERED_SETTINGS, actual $HAVE_SHOW, $CARRY_SHOW"
    fail=1
  else
    echo "compare settings.$SKEY against $DELIVERED_SETTINGS -> yes, the live value carries it"
  fi
done <<SKEYS_EOF
$SKEYS
SKEYS_EOF

HOOK_HARNESS_DIR=$(jq -r 'if type == "object" and (.env | type) == "object" then (.env.HARNESS_DIR // empty | strings) else empty end' "$LIVE_SETTINGS" 2>/dev/null); HOOK_HD_RC=$?
HOOK_HARNESS_DIR=${HOOK_HARNESS_DIR%$'\r'}
echo "jq -r .env.HARNESS_DIR $LIVE_SETTINGS -> exit=$HOOK_HD_RC value=$(sanitize "${HOOK_HARNESS_DIR:-absent}")"
if [ -n "$HOOK_HARNESS_DIR" ]; then
  HOOK_REAL=$(canon_path "$HOOK_HARNESS_DIR")
  REPO_REAL=$(canon_path "$REPO")
  if [ "${HOOK_REAL:-unresolved-hook}" != "${REPO_REAL:-unresolved-repo}" ]; then
    echo "FAIL hook harness dir: expected env.HARNESS_DIR in $LIVE_SETTINGS to name $REPO (resolves to $(sanitize "${REPO_REAL:-unresolved}")), actual $(sanitize "$HOOK_HARNESS_DIR") (resolves to $(sanitize "${HOOK_REAL:-unresolved}"))"
    fail=1
  else
    echo "compare env.HARNESS_DIR against $REPO -> yes, both resolve to $(sanitize "$REPO_REAL")"
  fi
fi

GUARD_OK=no
GUARD_MARK='attribution-guard: matched line ->'
GUARD_BODY='what changed, in one sentence.

_Generated by [Claude Code](https://claude.ai/code)_'
GUARD_INPUT=$(jq -n --arg c "gh pr create --title t --body \"$GUARD_BODY\"" '{tool_name:"Bash",tool_input:{command:$c}}' 2>/dev/null); GUARD_IN_RC=$?
GUARD_CMD=$(jq -r 'if type == "object" then ([.hooks.PreToolUse[]?.hooks[]? | select(.type == "command") | .command | select(type == "string" and contains("attribution-guard.sh"))] | .[0] // empty) else empty end' "$LIVE_SETTINGS" 2>/dev/null); GUARD_CMD_RC=$?
if [ "$GUARD_IN_RC" -ne 0 ] || [ -z "$GUARD_INPUT" ]; then
  GUARD_SHOW="sample input not built (jq exit=$GUARD_IN_RC)"
elif [ "$GUARD_CMD_RC" -ne 0 ] || [ -z "$GUARD_CMD" ]; then
  GUARD_SHOW="no PreToolUse command in $LIVE_SETTINGS references attribution-guard.sh (jq exit=$GUARD_CMD_RC)"
else
  GUARD_ERR=$(printf '%s' "$GUARD_INPUT" | hook_run "$GUARD_CMD" 2>&1 >/dev/null); GUARD_RC=$?
  if [ "$GUARD_RC" -ne 2 ]; then
    GUARD_SHOW="exit=$GUARD_RC"
  elif printf '%s\n' "$GUARD_ERR" | grep -a -q -F -- "$GUARD_MARK"; then
    GUARD_SHOW="exit=2 carrying $GUARD_MARK"
    GUARD_OK=yes
  else
    GUARD_SHOW="exit=2 without $GUARD_MARK [$(sanitize "$GUARD_ERR")]"
  fi
fi
echo "run the live PreToolUse command on a gh pr create body carrying the footer -> $GUARD_SHOW"
if [ "$GUARD_OK" != yes ]; then
  echo "FAIL PreToolUse attribution guard: expected exit=2 carrying $GUARD_MARK from the live PreToolUse command in $LIVE_SETTINGS on a gh pr create body carrying the footer, actual $GUARD_SHOW"
  fail=1
fi
CLEAN_BODY='what changed, in one sentence.'
CLEAN_INPUT=$(jq -n --arg c "gh pr create --title t --body \"$CLEAN_BODY\"" '{tool_name:"Bash",tool_input:{command:$c}}' 2>/dev/null); CLEAN_IN_RC=$?
guard_clean_check "$CLEAN_INPUT" "$CLEAN_IN_RC" "$GUARD_CMD" "$GUARD_CMD_RC" PreToolUse "a gh pr create body without the footer"

POST_OK=no
POST_MARK='attribution-guard: matched line in the response body ->'
POST_INPUT=$(jq -n --arg b "$GUARD_BODY" '{hook_event_name:"PostToolUse",tool_name:"mcp__github__create_pull_request",tool_input:{body:"what changed, in one sentence."},tool_response:{body:$b}}' 2>/dev/null); POST_IN_RC=$?
POST_CMD=$(jq -r 'if type == "object" then ([.hooks.PostToolUse[]?.hooks[]? | select(.type == "command") | .command | select(type == "string" and contains("attribution-guard.sh"))] | .[0] // empty) else empty end' "$LIVE_SETTINGS" 2>/dev/null); POST_CMD_RC=$?
if [ "$POST_IN_RC" -ne 0 ] || [ -z "$POST_INPUT" ]; then
  POST_SHOW="sample input not built (jq exit=$POST_IN_RC)"
elif [ "$POST_CMD_RC" -ne 0 ] || [ -z "$POST_CMD" ]; then
  POST_SHOW="no PostToolUse command in $LIVE_SETTINGS references attribution-guard.sh (jq exit=$POST_CMD_RC)"
else
  POST_ERR=$(printf '%s' "$POST_INPUT" | hook_run "$POST_CMD" 2>&1 >/dev/null); POST_RC=$?
  if [ "$POST_RC" -ne 2 ]; then
    POST_SHOW="exit=$POST_RC"
  elif printf '%s\n' "$POST_ERR" | grep -a -q -F -- "$POST_MARK"; then
    POST_SHOW="exit=2 carrying $POST_MARK"
    POST_OK=yes
  else
    POST_SHOW="exit=2 without $POST_MARK [$(sanitize "$POST_ERR")]"
  fi
fi
echo "run the live PostToolUse command on a create response whose body carries the footer -> $POST_SHOW"
if [ "$POST_OK" != yes ]; then
  echo "FAIL PostToolUse attribution guard: expected exit=2 carrying $POST_MARK from the live PostToolUse command in $LIVE_SETTINGS on a create response whose body carries the footer, actual $POST_SHOW"
  fail=1
fi
POST_CLEAN_INPUT=$(jq -n --arg b "$CLEAN_BODY" '{hook_event_name:"PostToolUse",tool_name:"mcp__github__create_pull_request",tool_input:{body:$b},tool_response:{body:$b}}' 2>/dev/null); POST_CLEAN_IN_RC=$?
guard_clean_check "$POST_CLEAN_INPUT" "$POST_CLEAN_IN_RC" "$POST_CMD" "$POST_CMD_RC" PostToolUse "a create response whose body carries no footer"

echo "test -f $REPO/config/plugins.tsv -> $([ -f "$REPO/config/plugins.tsv" ] && echo yes || echo no)"
if [ -f "$REPO/config/plugins.tsv" ]; then
  while IFS=$'\t' read -r -u 3 mp_source plugin_id _rest || [ -n "${mp_source:-}" ]; do
    mp_source=${mp_source%$'\r'}; plugin_id=${plugin_id%$'\r'}
    case "${mp_source:-}" in ''|'#'*) continue ;; esac
    [ -n "${plugin_id:-}" ] || continue
    if [ "$CLI_PLUGINS" = unknown ]; then
      echo "FAIL plugin: expected an id list from claude plugin list --json to test $plugin_id against, actual could not tell"
      fail=1
      continue
    fi
    FOUND=no
    while IFS= read -r have_id || [ -n "${have_id:-}" ]; do
      [ "$have_id" = "$plugin_id" ] && FOUND=yes
    done <<IDS_EOF
$PLUGIN_IDS
IDS_EOF
    if [ "$FOUND" = yes ]; then
      echo "plugin_id $plugin_id in claude plugin list --json -> yes"
      plugin_deps_check "$plugin_id"
    else
      echo "FAIL plugin: expected $plugin_id from $REPO/config/plugins.tsv among the installed ids, actual $(sanitize "${PLUGIN_IDS:-none}")"
      fail=1
    fi
  done 3< "$REPO/config/plugins.tsv"
else
  echo "FAIL config/plugins.tsv: expected a file at $REPO/config/plugins.tsv, actual absent"
  fail=1
fi

git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; REPO_RC=$?
echo "git -C $REPO rev-parse --git-dir -> exit=$REPO_RC"
RGIT=(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_OBJECT_DIRECTORY -u GIT_COMMON_DIR -u GIT_ALTERNATE_OBJECT_DIRECTORIES git)
STATUS_TIMEOUT=10
if command -v timeout >/dev/null 2>&1; then TO=(timeout "$STATUS_TIMEOUT"); else TO=(); fi
COPY_TOP=no
if [ "$REPO_RC" -ne 0 ]; then
  COPY_SHOW="repo unreadable (git rev-parse exit=$REPO_RC)"
else
  TOP_RAW=$("${RGIT[@]}" -C "$REPO" rev-parse --show-toplevel 2>/dev/null); TOP_RC=$?
  TOP_REAL=$([ -n "$TOP_RAW" ] && canon_path "$TOP_RAW")
  REPO_TOP_REAL=$(canon_path "$REPO")
  if [ "$TOP_RC" -ne 0 ] || [ -z "$TOP_RAW" ]; then
    COPY_SHOW="unreadable (git exit=$TOP_RC)"
  elif [ -z "$TOP_REAL" ]; then
    COPY_SHOW="no, the top level [$(sanitize "$(cap "$TOP_RAW")")] did not resolve through canon_path"
  elif [ "$TOP_REAL" != "${REPO_TOP_REAL:-unresolved-repo}" ]; then
    COPY_SHOW="no, the top level is [$(sanitize "$(cap "$TOP_RAW")")]"
  else
    COPY_SHOW=yes; COPY_TOP=yes
  fi
fi
echo "git -C $REPO rev-parse --show-toplevel names $REPO -> $COPY_SHOW"
BRANCH_OUT=""; BRANCH_RC=""
if [ "$COPY_TOP" != yes ]; then
  BRANCH_SHOW="not read, top level check $COPY_SHOW"
else
  BRANCH_OUT=$("${RGIT[@]}" -C "$REPO" symbolic-ref -q HEAD 2>/dev/null); BRANCH_RC=$?
  if [ "$BRANCH_RC" -eq 1 ]; then
    BRANCH_SHOW="detached HEAD (git exit=1)"
  elif [ "$BRANCH_RC" -ne 0 ]; then
    BRANCH_SHOW="unreadable (git exit=$BRANCH_RC)"
  else
    BRANCH_SHOW="[$(sanitize "$(cap "$BRANCH_OUT")")]"
  fi
fi
echo "git -C $REPO symbolic-ref -q HEAD -> $BRANCH_SHOW"
if [ "$COPY_TOP" != yes ] || [ "$BRANCH_RC" != 0 ] || [ "$BRANCH_OUT" != "refs/heads/$HARNESS_REF" ]; then
  echo "FAIL deployed copy branch: expected [refs/heads/$HARNESS_REF] from git -C $REPO symbolic-ref -q HEAD, actual $BRANCH_SHOW"
  fail=1
fi
STATUS_OK=no
FLAG_SHOW="not read"
if [ "$COPY_TOP" != yes ]; then
  STATUS_SHOW="not read, top level check $COPY_SHOW"
else
  STATUS_ERRF=$(mktemp 2>/dev/null)
  if [ -z "${STATUS_ERRF:-}" ]; then
    STATUS_SHOW="not read, mktemp produced no file"
  else
    STATUS_OUT=$(${TO[@]+"${TO[@]}"} "${RGIT[@]}" -C "$REPO" -c core.fsmonitor=false -c core.quotePath=true --no-optional-locks status --porcelain --untracked-files=all --ignore-submodules=none 2>"$STATUS_ERRF"); STATUS_RC=$?
    STATUS_ERR=$(cat "$STATUS_ERRF" 2>/dev/null)
    rm -f "$STATUS_ERRF"
    if [ "$STATUS_RC" -eq 124 ] && [ "${#TO[@]}" -gt 0 ]; then
      STATUS_SHOW="timed out after ${STATUS_TIMEOUT}s (exit=124)"
    elif [ "$STATUS_RC" -ne 0 ]; then
      STATUS_SHOW="unreadable (git exit=$STATUS_RC) [$(sanitize "$(cap "$STATUS_ERR")")]"
    elif [ -n "$STATUS_ERR" ]; then
      STATUS_SHOW="unreadable, git wrote to stderr [$(sanitize "$(cap "$STATUS_ERR")")] (git exit=0)"
    elif [ -z "$STATUS_OUT" ]; then
      STATUS_SHOW="no entries (git exit=0)"; STATUS_OK=yes
    else
      STATUS_COUNT=$(printf '%s\n' "$STATUS_OUT" | grep -a -c '')
      STATUS_FIRST=$(printf '%s\n' "$STATUS_OUT" | head -n 5 | LC_ALL=C cut -b 1-120 | {
        IFS= read -r l; s=$l
        while IFS= read -r l; do s="$s | $l"; done
        printf '%s' "$s"
      })
      STATUS_SHOW="$STATUS_COUNT entries, the first up to 5 at up to 120 bytes each [$(sanitize "$STATUS_FIRST")] (git exit=0)"
    fi
  fi
  FLAG_OUT=$("${RGIT[@]}" -C "$REPO" ls-files -v 2>/dev/null); FLAG_RC=$?
  if [ "$FLAG_RC" -ne 0 ]; then
    FLAG_SHOW="unreadable (git exit=$FLAG_RC)"; STATUS_OK=no
  else
    FLAG_COUNT=$(printf '%s\n' "$FLAG_OUT" | LC_ALL=C grep -a -c -E '^([a-z]|S) ')
    FLAG_SHOW=$FLAG_COUNT
    [ "$FLAG_COUNT" = 0 ] || STATUS_OK=no
  fi
fi
echo "git -C $REPO status --porcelain --untracked-files=all --ignore-submodules=none -> $STATUS_SHOW"
echo "git -C $REPO ls-files -v, entries marked skip-worktree or assume-unchanged -> $FLAG_SHOW"
if [ "$STATUS_OK" != yes ]; then
  echo "FAIL deployed copy changes: expected no entries from git -C $REPO status --porcelain --untracked-files=all --ignore-submodules=none and no entry marked skip-worktree or assume-unchanged, actual status $STATUS_SHOW, marked $FLAG_SHOW"
  fail=1
fi
REMOTE_TIMEOUT=5
REMOTE_REF="refs/heads/$HARNESS_REF"
DEPLOYED=""; REMOTE_HEAD=""
if [ "$REPO_RC" -ne 0 ]; then
  DEPLOYED_SHOW="not read, repo unreadable (git rev-parse exit=$REPO_RC)"
else
  DEPLOYED_OUT=$("${RGIT[@]}" -C "$REPO" rev-parse --verify -q HEAD 2>/dev/null); DEPLOYED_RC=$?
  if [ "$DEPLOYED_RC" -eq 0 ] && [[ "$DEPLOYED_OUT" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]; then
    DEPLOYED=$DEPLOYED_OUT; DEPLOYED_SHOW="[$DEPLOYED]"
  else
    DEPLOYED_SHOW="unreadable (git exit=$DEPLOYED_RC) [$(sanitize "$(cap "$DEPLOYED_OUT")")]"
  fi
fi
echo "git -C $REPO rev-parse --verify -q HEAD -> $DEPLOYED_SHOW"
if [ "$REPO_RC" -ne 0 ]; then
  REMOTE_SHOW="not read, repo unreadable (git rev-parse exit=$REPO_RC)"
elif ! command -v timeout >/dev/null 2>&1; then
  REMOTE_SHOW="not read, command -v timeout -> none"
else
  ORIGIN_URL=$("${RGIT[@]}" -C "$REPO" config --get remote.origin.url 2>/dev/null); ORIGIN_RC=$?
  if [ "$ORIGIN_RC" -ne 0 ] || [ -z "$ORIGIN_URL" ]; then
    REMOTE_SHOW="not read, git -C $REPO config --get remote.origin.url -> exit=$ORIGIN_RC$([ "$ORIGIN_RC" -ne 0 ] || printf ' value=empty')"
  else
    REMOTE_OUT=$(cd / && GIT_TERMINAL_PROMPT=0 timeout -k 2 "$REMOTE_TIMEOUT" "${RGIT[@]}" ls-remote -- "$ORIGIN_URL" "$REMOTE_REF" </dev/null 2>/dev/null); REMOTE_RC=$?
    REMOTE_OUT=${REMOTE_OUT//$'\r'/}
    REMOTE_LINE=$(printf '%s\n' "$REMOTE_OUT" | LC_ALL=C grep -a -E "^([0-9a-f]{40}|[0-9a-f]{64})"$'\t'"$REMOTE_REF\$" | head -n 1)
    if [ "$REMOTE_RC" -eq 124 ] || [ "$REMOTE_RC" -eq 137 ]; then
      REMOTE_SHOW="not read, timed out after ${REMOTE_TIMEOUT}s (exit=$REMOTE_RC)"
    elif [ "$REMOTE_RC" -ge 125 ] && [ "$REMOTE_RC" -le 127 ]; then
      REMOTE_SHOW="not read (timeout or env exit=$REMOTE_RC)"
    elif [ "$REMOTE_RC" -ne 0 ]; then
      REMOTE_SHOW="not read (git exit=$REMOTE_RC)"
    elif [ -z "$REMOTE_LINE" ]; then
      REMOTE_SHOW="not read, no $REMOTE_REF line (git exit=0)"
    else
      REMOTE_HEAD=${REMOTE_LINE%%$'\t'*}; REMOTE_SHOW="[$REMOTE_HEAD]"
    fi
  fi
fi
echo "git ls-remote -- <origin URL of $REPO> $REMOTE_REF, under timeout ${REMOTE_TIMEOUT}s -> $REMOTE_SHOW"
if [ -z "$REMOTE_HEAD" ]; then
  echo "NOTE remote $HARNESS_REF head: expected a head from git ls-remote -- <origin URL of $REPO> $REMOTE_REF, actual $REMOTE_SHOW; not counted into the exit status"
elif [ -z "$DEPLOYED" ]; then
  echo "NOTE remote $HARNESS_REF head: expected the deployed commit from git -C $REPO rev-parse --verify -q HEAD to compare against $REMOTE_HEAD, actual $DEPLOYED_SHOW; not counted into the exit status"
elif [ "$DEPLOYED" != "$REMOTE_HEAD" ]; then
  echo "NOTE remote $HARNESS_REF head: expected the deployed commit $DEPLOYED to equal the head of $REMOTE_REF on origin, actual $REMOTE_HEAD; not counted into the exit status"
else
  echo "compare the deployed commit against the head of $REMOTE_REF on origin -> yes, both $DEPLOYED"
fi
CFG_MAIL=$(git -C "$REPO" config --get user.email 2>/dev/null); CFG_RC=$?
if [ "$REPO_RC" -ne 0 ]; then
  CFG_SHOW="repo unreadable (git rev-parse exit=$REPO_RC); any value here would come from global scope"
elif [ "$CFG_RC" -eq 1 ]; then
  CFG_SHOW="unset (git exit=1)"
elif [ "$CFG_RC" -ne 0 ]; then
  CFG_SHOW="unreadable (git exit=$CFG_RC)"
elif [ -z "$CFG_MAIL" ]; then
  CFG_SHOW="present with empty or absent value (git exit=0)"
elif [ "$CFG_MAIL" != "${CFG_MAIL%%$'\n'*}" ]; then
  CFG_SHOW="multiple lines [$(sanitize "$CFG_MAIL")] (git exit=0)"
else
  CFG_SHOW="[$(sanitize "$CFG_MAIL")]"
fi
echo "git -C $REPO config --get user.email -> $CFG_SHOW (not asserted; shown for contrast)"

ident_var_state() {
  if [ -z "${!1+set}" ]; then printf 'unset'
  elif [ -z "${!1}" ]; then printf 'set but empty'
  else printf 'set'; fi
}

ROLE_IDENT_AUTHOR=""
ROLE_IDENT_COMMITTER=""
ROLE_PARSED_AUTHOR=no
ROLE_PARSED_COMMITTER=no
for IDENT_ROLE in AUTHOR COMMITTER; do
  IDENT_N="GIT_${IDENT_ROLE}_NAME"; IDENT_E="GIT_${IDENT_ROLE}_EMAIL"
  N_STATE=$(ident_var_state "$IDENT_N"); E_STATE=$(ident_var_state "$IDENT_E")
  echo "$IDENT_N -> $N_STATE, $IDENT_E -> $E_STATE (git var GIT_${IDENT_ROLE}_IDENT reads this pair at highest precedence)"
  if [ "$N_STATE" != set ] || [ "$E_STATE" != set ]; then
    echo "FAIL git ${IDENT_ROLE} variables: expected $IDENT_N and $IDENT_E each set and non-empty, actual $N_STATE and $E_STATE"
    fail=1
  fi
  IDENT_RAW=$(git -C "$REPO" var "GIT_${IDENT_ROLE}_IDENT" 2>/dev/null); IDENT_RC=$?
  IDENT_PARSED=no
  if [ "$REPO_RC" -ne 0 ]; then
    IDENT_SHOW="repo unreadable (git rev-parse exit=$REPO_RC)"
  elif [ "$IDENT_RC" -ne 0 ]; then
    IDENT_SHOW="unreadable (git var exit=$IDENT_RC)"
  elif [ -z "$IDENT_RAW" ]; then
    IDENT_SHOW="empty (git var exit=0)"
  elif [ "$IDENT_RAW" != "${IDENT_RAW%%$'\n'*}" ]; then
    IDENT_SHOW="multiple lines [$(sanitize "$IDENT_RAW")] (git var exit=0)"
  else
    case "$IDENT_RAW" in
      *"> "*) IDENT_SHOW="$(sanitize "${IDENT_RAW%> *}>")"; IDENT_PARSED=yes ;;
      *) IDENT_SHOW="unparseable [$(sanitize "$IDENT_RAW")] (git var exit=0)" ;;
    esac
  fi
  echo "git -C $REPO var GIT_${IDENT_ROLE}_IDENT -> $IDENT_SHOW"
  if [ "$IDENT_PARSED" != yes ]; then
    echo "FAIL git ${IDENT_ROLE} identity: expected an identity of the form Name <email> from git -C $REPO var GIT_${IDENT_ROLE}_IDENT, actual $IDENT_SHOW"
    fail=1
  elif [ "$N_STATE" = set ] && [ "$E_STATE" = set ]; then
    WANT_IDENT="$(sanitize "${!IDENT_N} <${!IDENT_E}>")"
    if [ "$IDENT_SHOW" != "$WANT_IDENT" ]; then
      echo "FAIL git ${IDENT_ROLE} identity: expected $WANT_IDENT from $IDENT_N and $IDENT_E, actual $IDENT_SHOW"
      fail=1
    else
      echo "compare GIT_${IDENT_ROLE}_IDENT against $IDENT_N and $IDENT_E -> yes, git resolves the pair"
    fi
  fi
  if [ "$IDENT_PARSED" = yes ]; then
    IDENT_MAIL=${IDENT_SHOW##*<}; IDENT_MAIL=${IDENT_MAIL%>}
    if [ "$IDENT_MAIL" = "$HARNESS_MAIL" ]; then
      echo "FAIL git ${IDENT_ROLE} identity: expected an email other than the harness default $HARNESS_MAIL, actual $IDENT_SHOW"
      fail=1
    fi
  fi
  eval "ROLE_IDENT_${IDENT_ROLE}=\$IDENT_SHOW"
  eval "ROLE_PARSED_${IDENT_ROLE}=\$IDENT_PARSED"
done
if [ "$ROLE_PARSED_AUTHOR" != yes ] || [ "$ROLE_PARSED_COMMITTER" != yes ]; then
  echo "compare GIT_AUTHOR_IDENT against GIT_COMMITTER_IDENT -> not run, author parsed $ROLE_PARSED_AUTHOR and committer parsed $ROLE_PARSED_COMMITTER"
elif [ "$ROLE_IDENT_AUTHOR" != "$ROLE_IDENT_COMMITTER" ]; then
  echo "FAIL git identity agreement: expected GIT_AUTHOR_IDENT and GIT_COMMITTER_IDENT to name one identity, actual $ROLE_IDENT_AUTHOR and $ROLE_IDENT_COMMITTER"
  fail=1
else
  echo "compare GIT_AUTHOR_IDENT against GIT_COMMITTER_IDENT -> yes, both $ROLE_IDENT_AUTHOR"
fi
ASSIGNEE_STATE=$(ident_var_state HARNESS_ASSIGNEE)
if [ "$ASSIGNEE_STATE" != set ]; then
  echo "HARNESS_ASSIGNEE -> $ASSIGNEE_STATE"
  echo "FAIL HARNESS_ASSIGNEE: expected a GitHub login set and non-empty, actual $ASSIGNEE_STATE"
  fail=1
else
  ASSIGNEE_SHOW="[$(sanitize "$HARNESS_ASSIGNEE")]"
  echo "HARNESS_ASSIGNEE -> $ASSIGNEE_SHOW"
  ASSIGNEE_WHY=""
  case "$HARNESS_ASSIGNEE" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-]*) ASSIGNEE_WHY="$ASSIGNEE_WHY, a character other than a letter, digit or hyphen" ;;
  esac
  case "$HARNESS_ASSIGNEE" in
    -*|*-) ASSIGNEE_WHY="$ASSIGNEE_WHY, a leading or trailing hyphen" ;;
  esac
  case "$HARNESS_ASSIGNEE" in
    *--*) ASSIGNEE_WHY="$ASSIGNEE_WHY, consecutive hyphens" ;;
  esac
  ASSIGNEE_LEN=$(printf '%s' "$HARNESS_ASSIGNEE" | LC_ALL=C wc -c | tr -d ' ')
  if [ "$ASSIGNEE_LEN" -gt 39 ]; then
    ASSIGNEE_WHY="$ASSIGNEE_WHY, $ASSIGNEE_LEN bytes"
  fi
  if [ -n "$ASSIGNEE_WHY" ]; then
    echo "FAIL HARNESS_ASSIGNEE: expected a GitHub login of at most 39 letters, digits and single hyphens with no leading or trailing hyphen, actual $ASSIGNEE_SHOW with${ASSIGNEE_WHY#,}"
    fail=1
  fi
fi
for SIGN_KEY in commit.gpgsign tag.gpgsign; do
  have_sign=$(git -C "$REPO" config --get "$SIGN_KEY" 2>/dev/null); SIGN_RC=$?
  if [ "$REPO_RC" -ne 0 ]; then
    SIGN_SHOW="repo unreadable (git rev-parse exit=$REPO_RC)"
  elif [ "$SIGN_RC" -eq 1 ]; then
    SIGN_SHOW="unset (git exit=1)"
  elif [ "$SIGN_RC" -ne 0 ]; then
    SIGN_SHOW="unreadable (git exit=$SIGN_RC)"
  elif [ -z "$have_sign" ]; then
    SIGN_SHOW="present with empty or absent value (git exit=0)"
  elif [ "$have_sign" != "${have_sign%%$'\n'*}" ]; then
    SIGN_SHOW="multiple lines [$(sanitize "$have_sign")] (git exit=0)"
  else
    SIGN_SHOW="[$(sanitize "$have_sign")]"
  fi
  echo "git -C $REPO config --get $SIGN_KEY -> $SIGN_SHOW"
  if [ "$REPO_RC" -ne 0 ] || [ "$have_sign" != "false" ]; then
    echo "FAIL git $SIGN_KEY: expected [false] from git -C $REPO config --get $SIGN_KEY, actual $SIGN_SHOW"
    fail=1
  fi
done
echo "manifest.git_user_email -> $(jq -r '.git_user_email // ""' "$MANIFEST" 2>/dev/null)"

echo "fail -> $fail"
exit "$fail"
