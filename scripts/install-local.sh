#!/bin/bash
set -uo pipefail

SRC=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd); SRC_RC=$?

if [ -z "${CLAUDE_CONFIG_DIR+set}" ]; then CCD_SHOW=unset
elif [ -z "$CLAUDE_CONFIG_DIR" ]; then CCD_SHOW="set but empty"
else CCD_SHOW="$CLAUDE_CONFIG_DIR"; fi
CONFIG_RAW="${CLAUDE_CONFIG_DIR-${HOME:-}/.claude}"
CONFIG_DIR=$CONFIG_RAW
CYGPATH=$(command -v cygpath || echo none)
if [ "$CYGPATH" != none ] && [ -n "$CONFIG_RAW" ]; then
  CONV=$(cygpath -u "$CONFIG_RAW" 2>/dev/null); CONV_RC=$?
  [ "$CONV_RC" -ne 0 ] || [ -z "$CONV" ] || CONFIG_DIR=$CONV
fi
case "$CONFIG_DIR" in
  /*) ;;
  *)
    echo "CLAUDE_CONFIG_DIR -> $CCD_SHOW"
    echo "\${CLAUDE_CONFIG_DIR-\$HOME/.claude} -> ${CONFIG_DIR:-empty}, not an absolute path"
    echo "fails -> 1"
    exit 1 ;;
esac
mkdir -p "$CONFIG_DIR"; MKDIR_RC=$?
LOG="$CONFIG_DIR/.my-harness-wrapper.install.log"

keep_first() {
  local backup="$1.pre-harness" rc
  if [ -e "$backup" ]; then echo "test -e $backup -> yes, kept from an earlier run"; return; fi
  cp -p "$1" "$backup"; rc=$?
  echo "cp -p $1 $backup -> exit=$rc"
  [ "$rc" -eq 0 ] || fails=$((fails + 1))
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

main() {
  local fails=0 rc ch_rc mv_rc rm_rc TMP MTMP
  echo "id -> $(id -u):$(id -g) HOME=${HOME:-}"
  echo "SRC -> exit=$SRC_RC value=${SRC:-}"
  [ "$SRC_RC" -eq 0 ] || fails=$((fails + 1))
  echo "CLAUDE_CONFIG_DIR -> $CCD_SHOW"
  echo "command -v cygpath -> $CYGPATH"
  echo "\${CLAUDE_CONFIG_DIR-\$HOME/.claude} -> $CONFIG_DIR"
  echo "mkdir -p $CONFIG_DIR -> exit=$MKDIR_RC"
  [ "$MKDIR_RC" -eq 0 ] || fails=$((fails + 1))
  echo "test -d $CONFIG_DIR -> $([ -d "$CONFIG_DIR" ] && echo yes || echo no)"
  echo "log -> $LOG"

  local JQ
  JQ=$(command -v jq || echo none)
  echo "command -v jq -> $JQ"
  [ "$JQ" != none ] || fails=$((fails + 1))

  local SRC_MD="$SRC/config/CLAUDE.md"
  echo "test -f $SRC_MD -> $([ -f "$SRC_MD" ] && echo yes || echo no)"
  if [ -f "$CONFIG_DIR/CLAUDE.md" ]; then
    cmp -s "$SRC_MD" "$CONFIG_DIR/CLAUDE.md"; rc=$?
    echo "cmp -s $SRC_MD $CONFIG_DIR/CLAUDE.md, before the copy -> exit=$rc"
    [ "$rc" -eq 0 ] || keep_first "$CONFIG_DIR/CLAUDE.md"
  else
    echo "test -f $CONFIG_DIR/CLAUDE.md, before the copy -> no"
  fi
  if [ -f "$SRC_MD" ]; then
    cp "$SRC_MD" "$CONFIG_DIR/CLAUDE.md"; rc=$?
    echo "cp $SRC_MD $CONFIG_DIR/CLAUDE.md -> exit=$rc"
    [ "$rc" -eq 0 ] || fails=$((fails + 1))
  else
    fails=$((fails + 1))
  fi

  local SRC_SETTINGS="$SRC/config/settings.json"
  local DST_SETTINGS="$CONFIG_DIR/settings.json"
  local MERGE='if length != 2 then error("expected one JSON document in each file, read \(length) in all") else .[0] * .[1] * {env: {HARNESS_DIR: $h}} end'
  local DIFFERS='if length == 2 and (.[0] | type) == "object" and (.[1] | type) == "object" then .[0] as $l | [.[1] | to_entries[] | .key as $k | select(($l | has($k)) and $l[$k] != .value) | $k] | join(" ") else "not compared" end'
  local MODE="" REPLACED
  echo "test -f $SRC_SETTINGS -> $([ -f "$SRC_SETTINGS" ] && echo yes || echo no)"
  echo "test -s $DST_SETTINGS -> $([ -s "$DST_SETTINGS" ] && echo yes || echo no)"
  if [ -s "$DST_SETTINGS" ]; then
    REPLACED=$(jq -s -r "$DIFFERS" "$DST_SETTINGS" "$SRC_SETTINGS" 2>/dev/null); rc=$?
    echo "delivered top-level keys whose live value differs -> exit=$rc value=[${REPLACED:-}]"
    local EVENTS EVENT PRIOR_HOOK
    EVENTS=$(jq -r 'if type == "object" and (.hooks | type) == "object" then .hooks | keys[] else empty end' "$SRC_SETTINGS" 2>/dev/null)
    while IFS= read -r EVENT; do
      [ -n "$EVENT" ] || continue
      PRIOR_HOOK=$(jq -c --arg e "$EVENT" 'if type == "object" and (.hooks | type) == "object" and (.hooks | has($e)) then .hooks[$e] else "absent" end' "$DST_SETTINGS" 2>/dev/null); rc=$?
      echo "jq -c .hooks.$EVENT $DST_SETTINGS, before the merge -> exit=$rc value=$(printf '%s' "$PRIOR_HOOK" | LC_ALL=C tr -d '\r' | LC_ALL=C tr '\n' ' ' | LC_ALL=C tr '\000-\037\177' '?')"
    done <<< "${EVENTS//$'\r'/}"
    keep_first "$DST_SETTINGS"
    MODE=$(stat -c %a "$DST_SETTINGS" 2>/dev/null || stat -f %Lp "$DST_SETTINGS" 2>/dev/null)
  fi
  case "$MODE" in ''|*[!0-7]*) MODE=600 ;; esac
  echo "mode for $DST_SETTINGS -> $MODE"
  if [ -f "$SRC_SETTINGS" ]; then
    TMP=$(mktemp "$DST_SETTINGS.XXXXXX"); rc=$?
    echo "mktemp $DST_SETTINGS.XXXXXX -> exit=$rc value=${TMP:-}"
    if [ "$rc" -ne 0 ] || [ -z "${TMP:-}" ]; then
      fails=$((fails + 1))
    else
      if [ -s "$DST_SETTINGS" ]; then
        jq -s --arg h "$SRC" "$MERGE" "$DST_SETTINGS" "$SRC_SETTINGS" > "$TMP"; rc=$?
        echo "jq -s --arg h $SRC '$MERGE' $DST_SETTINGS $SRC_SETTINGS -> exit=$rc"
      else
        jq -s --arg h "$SRC" "[{}] + . | $MERGE" "$SRC_SETTINGS" > "$TMP"; rc=$?
        echo "jq -s --arg h $SRC '[{}] + . | $MERGE' $SRC_SETTINGS -> exit=$rc"
      fi
      if [ "$rc" -eq 0 ]; then
        chmod "$MODE" "$TMP"; ch_rc=$?
        echo "chmod $MODE $TMP -> exit=$ch_rc"
        if [ "$ch_rc" -ne 0 ]; then
          fails=$((fails + 1))
          rm -f "$TMP"; rm_rc=$?
          echo "rm -f $TMP -> exit=$rm_rc"
          [ "$rm_rc" -eq 0 ] || fails=$((fails + 1))
        else
          mv "$TMP" "$DST_SETTINGS"; mv_rc=$?
          echo "mv $TMP $DST_SETTINGS -> exit=$mv_rc"
          [ "$mv_rc" -eq 0 ] || fails=$((fails + 1))
        fi
      else
        rm -f "$TMP"; rm_rc=$?
        echo "rm -f $TMP -> exit=$rm_rc"
        [ "$rm_rc" -eq 0 ] || fails=$((fails + 1))
        fails=$((fails + 1))
      fi
    fi
  else
    fails=$((fails + 1))
  fi
  echo "jq -r .env.HARNESS_DIR $DST_SETTINGS -> $(jq -r 'if type == "object" and (.env | type) == "object" then (.env.HARNESS_DIR // "absent") else "absent" end' "$DST_SETTINGS" 2>/dev/null || echo unreadable)"

  local kv key val prior
  for kv in "commit.gpgsign=false" "tag.gpgsign=false"; do
    key=${kv%%=*}; val=${kv#*=}
    prior=$(git config --global --get "$key" 2>/dev/null); rc=$?
    echo "git config --global --get $key -> exit=$rc value=${prior:-}"
    git config --global "$key" "$val"; rc=$?
    echo "git config --global $key $val -> exit=$rc"
    [ "$rc" -eq 0 ] || fails=$((fails + 1))
  done

  local CLI CLI_FROM mp_source plugin_id _rest rows=0
  local PLUGINS="$SRC/config/plugins.tsv"
  resolve_cli
  echo "command -v claude -> $(command -v claude || echo none)"
  echo "CLAUDE_CODE_EXECPATH -> ${CLAUDE_CODE_EXECPATH:-unset or empty}"
  echo "claude CLI -> ${CLI:-none} from $CLI_FROM"
  echo "test -f $PLUGINS -> $([ -f "$PLUGINS" ] && echo yes || echo no)"
  if [ -f "$PLUGINS" ]; then
    while IFS=$'\t' read -r -u 3 mp_source plugin_id _rest || [ -n "${mp_source:-}" ]; do
      mp_source=${mp_source%$'\r'}; plugin_id=${plugin_id%$'\r'}
      case "${mp_source:-}" in ''|'#'*) continue ;; esac
      echo "plugins.tsv marketplace_source=$mp_source plugin_id -> ${plugin_id:-empty}"
      [ -n "${plugin_id:-}" ] || { fails=$((fails + 1)); continue; }
      rows=$((rows + 1))
      if [ -z "$CLI" ]; then
        echo "claude plugin install $plugin_id -> not run, no CLI; run instead: claude plugin marketplace add $mp_source && claude plugin install $plugin_id --scope user --yes"
        fails=$((fails + 1))
        continue
      fi
      "$CLI" plugin marketplace add "$mp_source"; rc=$?
      echo "claude plugin marketplace add $mp_source -> exit=$rc"
      [ "$rc" -eq 0 ] || fails=$((fails + 1))
      "$CLI" plugin install "$plugin_id" --scope user --yes; rc=$?
      echo "claude plugin install $plugin_id --scope user --yes -> exit=$rc"
      [ "$rc" -eq 0 ] || fails=$((fails + 1))
    done 3< "$PLUGINS"
    echo "plugins.tsv rows carrying a plugin_id -> $rows"
  else
    fails=$((fails + 1))
  fi

  local SETUP="$SRC/env/setup.sh" VER_LINES VER_RC VERSION=""
  VER_LINES=$(grep -a '^export BOOTSTRAP_VERSION=' "$SETUP" 2>/dev/null); VER_RC=$?
  if [ "$VER_RC" -eq 0 ] && [ -n "$VER_LINES" ] && [ "$VER_LINES" = "${VER_LINES%%$'\n'*}" ]; then
    VERSION=${VER_LINES#export BOOTSTRAP_VERSION=}
    VERSION=${VERSION%"${VERSION##*[!$' \t']}"}
    case "$VERSION" in ''|*[!0-9A-Za-z._-]*) VERSION="" ;; esac
  fi
  echo "grep '^export BOOTSTRAP_VERSION=' $SETUP -> exit=$VER_RC value=${VERSION:-unread}"
  [ -n "$VERSION" ] || fails=$((fails + 1))

  local COMMIT GIT_EMAIL INSTALLED_AT
  COMMIT=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null); rc=$?
  echo "git -C $SRC rev-parse --short HEAD -> exit=$rc value=${COMMIT:-}"
  [ "$rc" -eq 0 ] || fails=$((fails + 1))
  GIT_EMAIL=$(git -C "$SRC" config --get user.email 2>/dev/null); rc=$?
  echo "git -C $SRC config --get user.email -> exit=$rc value=${GIT_EMAIL:-}"
  [ "$rc" -le 1 ] || fails=$((fails + 1))
  INSTALLED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ); rc=$?
  echo "date -u +%Y-%m-%dT%H:%M:%SZ -> exit=$rc value=${INSTALLED_AT:-}"
  [ "$rc" -eq 0 ] || fails=$((fails + 1))
  local MANIFEST="$CONFIG_DIR/.my-harness-wrapper.manifest.json"
  MTMP=$(mktemp "$MANIFEST.XXXXXX"); rc=$?
  echo "mktemp $MANIFEST.XXXXXX -> exit=$rc value=${MTMP:-}"
  if [ "$rc" -ne 0 ] || [ -z "${MTMP:-}" ]; then
    fails=$((fails + 1))
  else
    jq -n \
      --arg bootstrap_version "$VERSION" \
      --arg commit "${COMMIT:-}" \
      --arg config_dir "$CONFIG_DIR" \
      --arg git_user_email "${GIT_EMAIL:-}" \
      --arg installed_at "${INSTALLED_AT:-}" \
      --arg local_checkout "$SRC" \
      '{bootstrap_version: $bootstrap_version, commit: $commit, config_dir: $config_dir, git_user_email: $git_user_email, installed_at: $installed_at, local_checkout: $local_checkout}' \
      > "$MTMP"; rc=$?
    echo "jq -n > $MTMP -> exit=$rc"
    if [ "$rc" -eq 0 ]; then
      chmod 644 "$MTMP"; ch_rc=$?
      echo "chmod 644 $MTMP -> exit=$ch_rc"
      if [ "$ch_rc" -ne 0 ]; then
        fails=$((fails + 1))
        rm -f "$MTMP"; rm_rc=$?
        echo "rm -f $MTMP -> exit=$rm_rc"
        [ "$rm_rc" -eq 0 ] || fails=$((fails + 1))
      else
        mv "$MTMP" "$MANIFEST"; mv_rc=$?
        echo "mv $MTMP $MANIFEST -> exit=$mv_rc"
        [ "$mv_rc" -eq 0 ] || fails=$((fails + 1))
      fi
    else
      rm -f "$MTMP"; rm_rc=$?
      echo "rm -f $MTMP -> exit=$rm_rc"
      [ "$rm_rc" -eq 0 ] || fails=$((fails + 1))
      fails=$((fails + 1))
    fi
  fi
  echo "test -f $MANIFEST -> $([ -f "$MANIFEST" ] && echo yes || echo no)"

  [ "$fails" -le 255 ] || fails=255
  return "$fails"
}

( umask 077; : >> "$LOG" ) 2>/dev/null
chmod 600 "$LOG" 2>/dev/null
main 2>&1 | tee "$LOG"
PIPE_RCS=("${PIPESTATUS[@]}")
FAILS=${PIPE_RCS[0]}; TEE_RC=${PIPE_RCS[1]}
if [ "$TEE_RC" -ne 0 ]; then
  echo "tee $LOG -> exit=$TEE_RC"
  FAILS=$((FAILS + 1))
fi
echo "fails -> $FAILS" | tee -a "$LOG"
[ "$FAILS" -le 255 ] || FAILS=255
exit "$FAILS"
