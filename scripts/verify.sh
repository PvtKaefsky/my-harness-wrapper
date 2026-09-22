#!/bin/bash
set -uo pipefail

REPO=${HARNESS_DIR:-/opt/my-harness-wrapper}
HARNESS_MAIL="noreply@anthropic.com"
run() { echo "\$ $*"; "$@" 2>&1; echo "exit=$?"; }
sanitize() { printf '%s' "$1" | LC_ALL=C tr '\n' ' ' | LC_ALL=C tr '\000-\037\177' '?'; }
settings_probe() {
  jq -S -c --arg k "$2" 'if type != "object" then {state: ("top level is " + type)}
    elif (has($k) | not) then {state: "key absent"}
    else {state: "present", value: .[$k]} end' "$1" 2>/dev/null
}
settings_carries() {
  jq -n -r --arg k "$3" --slurpfile live "$1" --slurpfile want "$2" '
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
case "${LIVE_DIR:-}" in
  /*) ;;
  *) echo "FAIL live config dir path: expected an absolute path, actual ${LIVE_DIR:-empty}"; exit 1 ;;
esac
LIVE_REAL=$(readlink -f "$LIVE_DIR" 2>/dev/null)
echo "readlink -f $LIVE_DIR -> ${LIVE_REAL:-unresolved}"

run claude --version

echo "\$ claude plugin list --json"
PLUGIN_JSON=$(claude plugin list --json 2>/dev/null); PLUGIN_RC=$?
echo "claude plugin list --json -> exit=$PLUGIN_RC"
PLUGIN_IDS=$(printf '%s' "$PLUGIN_JSON" | jq -r 'if type == "array" then (.[] | .id // empty) else empty end' 2>/dev/null); IDS_RC=$?
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
  case "$MAN_DIR" in /*) ;; *) MAN_SHOW="$MAN_RAW (not an absolute path)"; MAN_DIR="" ;; esac
fi
echo "jq -r .config_dir $MANIFEST -> $MAN_SHOW"
MAN_REAL=$([ -n "$MAN_DIR" ] && readlink -f "$MAN_DIR" 2>/dev/null)
if [ "${LIVE_REAL:-unresolved-live}" != "${MAN_REAL:-unresolved-manifest}" ]; then
  echo "FAIL manifest.config_dir: expected $LIVE_DIR (resolves to ${LIVE_REAL:-unresolved}), actual $MAN_SHOW (resolves to ${MAN_REAL:-unresolved})"
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

GUARD_OK=no
GUARD_MARK='attribution-guard: matched line ->'
GUARD_BODY='what changed, in one sentence.

_Generated by [Claude Code](https://claude.ai/code)_'
GUARD_INPUT=$(jq -n --arg c "gh pr create --title t --body \"$GUARD_BODY\"" '{tool_name:"Bash",tool_input:{command:$c}}' 2>/dev/null); GUARD_IN_RC=$?
GUARD_CMD=$(jq -r 'if type == "object" then ([.hooks.PreToolUse[]?.hooks[]? | select(.type == "command") | .command] | .[0] // empty) else empty end' "$LIVE_SETTINGS" 2>/dev/null); GUARD_CMD_RC=$?
if [ "$GUARD_IN_RC" -ne 0 ] || [ -z "$GUARD_INPUT" ]; then
  GUARD_SHOW="sample input not built (jq exit=$GUARD_IN_RC)"
elif [ "$GUARD_CMD_RC" -ne 0 ] || [ -z "$GUARD_CMD" ]; then
  GUARD_SHOW="no PreToolUse command in $LIVE_SETTINGS (jq exit=$GUARD_CMD_RC)"
else
  GUARD_ERR=$(printf '%s' "$GUARD_INPUT" | bash -c "$GUARD_CMD" 2>&1 >/dev/null); GUARD_RC=$?
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

echo "test -f $REPO/config/plugins.tsv -> $([ -f "$REPO/config/plugins.tsv" ] && echo yes || echo no)"
if [ -f "$REPO/config/plugins.tsv" ]; then
  while IFS=$'\t' read -r -u 3 mp_source plugin_id _rest || [ -n "${mp_source:-}" ]; do
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
