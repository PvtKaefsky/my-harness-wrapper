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
DEPLOY="$CONFIG_DIR/my-harness-wrapper"
HARNESS_REF=main
if [ -z "${HARNESS_REPO_URL+set}" ]; then URL_STATE=unset
elif [ -z "$HARNESS_REPO_URL" ]; then URL_STATE="set but empty"
else URL_STATE=set; fi
if [ "$URL_STATE" = set ]; then REPO_URL=$HARNESS_REPO_URL; URL_SOURCE=environment
else REPO_URL=https://github.com/PvtKaefsky/my-harness-wrapper.git; URL_SOURCE=default; fi

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

url_canon() {
  local u r m
  case "$1" in
    /*|[A-Za-z]:/*|[A-Za-z]:\\*) ;;
    *) printf '%s' "$1"; return ;;
  esac
  if [ "$CYGPATH" = none ]; then printf '%s' "$1"; return; fi
  u=$(cygpath -u -- "$1" 2>/dev/null); [ -n "$u" ] || u=$1
  r=$(readlink -f -- "$u" 2>/dev/null); [ -n "$r" ] || r=$u
  m=$(cygpath -m -l -- "$r" 2>/dev/null); [ -n "$m" ] || { printf '%s' "$1"; return; }
  printf '%s' "$m" | LC_ALL=C tr 'A-Z' 'a-z'
}

same_dir() {
  case "$1" in
    /*|[A-Za-z]:/*|[A-Za-z]:\\*) ;;
    *) return 1 ;;
  esac
  [ "$1" -ef "$2" ] || [ "$(url_canon "$1")" = "$(url_canon "$2")" ]
}

hooks_triple() {
  local out rc name value foreign="" live
  HOOKS_VALUE=$HOOKS_DIR
  if [ "$CYGPATH" != none ]; then
    out=$(cygpath -m -- "$HOOKS_DIR" 2>/dev/null); rc=$?
    echo "cygpath -m $HOOKS_DIR -> exit=$rc value=${out:-empty}"
    if [ "$rc" -eq 0 ] && [ -n "$out" ]; then HOOKS_VALUE=$out; else HOOKS_VALUE=""; fi
  fi
  echo "test -x $HOOKS_DIR/commit-msg -> $([ -x "$HOOKS_DIR/commit-msg" ] && echo yes || echo no)"
  while IFS= read -r name; do
    case "$name" in
      GIT_CONFIG_COUNT) [ "${!name}" = 1 ] ;;
      GIT_CONFIG_KEY_0) [ "${!name}" = core.hooksPath ] ;;
      GIT_CONFIG_VALUE_0) same_dir "${!name}" "$HOOKS_DIR" ;;
      *) false ;;
    esac || foreign="$foreign environment:$name=[$(first_line "${!name}")]"
  done < <(compgen -e | LC_ALL=C grep -a -E '^GIT_CONFIG_(COUNT|KEY_[0-9]+|VALUE_[0-9]+)$')
  if [ -s "$DST_SETTINGS" ]; then
    live=$(jq -r 'if type == "object" and (.env | type) == "object" then .env | to_entries[] | select(.key | test("^GIT_CONFIG_(COUNT|KEY_[0-9]+|VALUE_[0-9]+)$")) | "\(.key)\t\(.value | tostring)" else empty end' "$DST_SETTINGS" 2>/dev/null); rc=$?
    live=${live//$'\r'/}
    echo "jq GIT_CONFIG_* keys of .env in $DST_SETTINGS -> exit=$rc count=$(printf '%s' "$live" | grep -a -c '')"
    [ "$rc" -eq 0 ] || foreign="$foreign settings:unreadable"
    while IFS=$'\t' read -r name value; do
      [ -n "$name" ] || continue
      case "$name" in
        GIT_CONFIG_COUNT) [ "$value" = 1 ] ;;
        GIT_CONFIG_KEY_0) [ "$value" = core.hooksPath ] ;;
        GIT_CONFIG_VALUE_0) same_dir "$value" "$HOOKS_DIR" ;;
        *) false ;;
      esac || foreign="$foreign settings:$(first_line "$name")=[$(first_line "$value")]"
    done <<< "$live"
  fi
  echo "GIT_CONFIG_* the installer did not write ->${foreign:- none}"
  if [ -z "$HOOKS_VALUE" ]; then
    echo "env.GIT_CONFIG_COUNT, env.GIT_CONFIG_KEY_0, env.GIT_CONFIG_VALUE_0 -> not written, cygpath -m did not convert $HOOKS_DIR"
    return 1
  fi
  if [ ! -x "$HOOKS_DIR/commit-msg" ]; then
    echo "env.GIT_CONFIG_COUNT, env.GIT_CONFIG_KEY_0, env.GIT_CONFIG_VALUE_0 -> not written, $HOOKS_DIR/commit-msg absent or not executable"
    return 1
  fi
  if [ -n "$foreign" ]; then
    echo "env.GIT_CONFIG_COUNT, env.GIT_CONFIG_KEY_0, env.GIT_CONFIG_VALUE_0 -> not written, another GIT_CONFIG_* is set:$foreign"
    return 1
  fi
  out=$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$HOOKS_VALUE" git -C "$DEPLOY" config --get core.hooksPath 2>&1); rc=$?
  out=${out%$'\r'}
  echo "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=$HOOKS_VALUE git -C $DEPLOY config --get core.hooksPath -> exit=$rc value=[$(first_line "$out")]"
  if [ "$rc" -ne 0 ] || [ "$out" != "$HOOKS_VALUE" ]; then
    echo "env.GIT_CONFIG_COUNT, env.GIT_CONFIG_KEY_0, env.GIT_CONFIG_VALUE_0 -> not written, git did not read core.hooksPath from the GIT_CONFIG_* variables"
    return 1
  fi
  return 0
}

first_line() {
  printf '%s' "${1%%$'\n'*}" | LC_ALL=C tr '\000-\037\177' '?'
}

deploy() {
  local rc out cdup marker prior head want head_rc want_rc branch branch_rc st st_rc entries
  local flagged flag_rc url url_rc url_match payload_rc var was_set=""
  for var in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_ALTERNATE_OBJECT_DIRECTORIES; do
    [ -z "${!var+set}" ] || was_set="$was_set $var"
    unset "$var"
  done
  echo "repository-redirecting GIT_* variables set before the unset ->${was_set:- none}"
  echo "deployed copy -> $DEPLOY"
  echo "HARNESS_REF -> $HARNESS_REF"
  echo "HARNESS_REPO_URL -> $URL_STATE; clone URL from $URL_SOURCE"
  echo "command -v git -> $GIT"
  if [ "$GIT" = none ]; then fails=$((fails + 1)); return 1; fi
  case "$REPO_URL" in
    -*) echo "clone URL begins with - -> yes, refused"; fails=$((fails + 1)); return 1 ;;
  esac
  if [ ! -e "$DEPLOY" ] && [ ! -L "$DEPLOY" ]; then
    echo "test -e $DEPLOY -> no"
    git clone -q -c harness.installer=install-local --depth 1 --branch "$HARNESS_REF" -- "$REPO_URL" "$DEPLOY"; rc=$?
    echo "git clone -q -c harness.installer=install-local --depth 1 --branch $HARNESS_REF -- \$HARNESS_REPO_URL $DEPLOY -> exit=$rc"
    [ "$rc" -eq 0 ] || { fails=$((fails + 1)); return 1; }
  else
    echo "test -e $DEPLOY -> yes"
    echo "test -L $DEPLOY -> $([ -L "$DEPLOY" ] && echo yes || echo no)"
    echo "test -d $DEPLOY/.git -> $([ -d "$DEPLOY/.git" ] && echo yes || echo no)"
    if [ -L "$DEPLOY" ] || [ ! -d "$DEPLOY/.git" ]; then fails=$((fails + 1)); return 1; fi
    cdup=$(git -C "$DEPLOY" rev-parse --show-cdup 2>&1); rc=$?
    echo "git -C $DEPLOY rev-parse --show-cdup -> exit=$rc value=[$(first_line "$cdup")]"
    if [ "$rc" -ne 0 ] || [ -n "$cdup" ]; then fails=$((fails + 1)); return 1; fi
    marker=$(git -C "$DEPLOY" config --local --get harness.installer 2>&1); rc=$?
    echo "git -C $DEPLOY config --local --get harness.installer -> exit=$rc value=[$(first_line "$marker")]"
    if [ "$rc" -ne 0 ] || [ "$marker" != install-local ]; then fails=$((fails + 1)); return 1; fi
    prior=$(git -C "$DEPLOY" rev-parse HEAD 2>&1); rc=$?
    echo "git -C $DEPLOY rev-parse HEAD, before the refresh -> exit=$rc value=[$(first_line "$prior")]"
    git -C "$DEPLOY" remote set-url -- origin "$REPO_URL"; rc=$?
    echo "git -C $DEPLOY remote set-url -- origin \$HARNESS_REPO_URL -> exit=$rc"
    [ "$rc" -eq 0 ] || { fails=$((fails + 1)); return 1; }
    git -C "$DEPLOY" fetch -q --depth 1 origin "+refs/heads/$HARNESS_REF:refs/remotes/origin/$HARNESS_REF"; rc=$?
    echo "git -C $DEPLOY fetch -q --depth 1 origin +refs/heads/$HARNESS_REF:refs/remotes/origin/$HARNESS_REF -> exit=$rc"
    [ "$rc" -eq 0 ] || { fails=$((fails + 1)); return 1; }
    git -C "$DEPLOY" checkout -q -f -B "$HARNESS_REF" "refs/remotes/origin/$HARNESS_REF"; rc=$?
    echo "git -C $DEPLOY checkout -q -f -B $HARNESS_REF refs/remotes/origin/$HARNESS_REF -> exit=$rc"
    [ "$rc" -eq 0 ] || { fails=$((fails + 1)); return 1; }
    git -C "$DEPLOY" clean -q -ffdx; rc=$?
    echo "git -C $DEPLOY clean -q -ffdx -> exit=$rc"
    [ "$rc" -eq 0 ] || { fails=$((fails + 1)); return 1; }
  fi
  head=$(git -C "$DEPLOY" rev-parse HEAD 2>&1); head_rc=$?
  echo "git -C $DEPLOY rev-parse HEAD -> exit=$head_rc value=[$(first_line "$head")]"
  want=$(git -C "$DEPLOY" rev-parse "refs/remotes/origin/$HARNESS_REF" 2>&1); want_rc=$?
  echo "git -C $DEPLOY rev-parse refs/remotes/origin/$HARNESS_REF -> exit=$want_rc value=[$(first_line "$want")]"
  branch=$(git -C "$DEPLOY" symbolic-ref --short -q HEAD 2>&1); branch_rc=$?
  echo "git -C $DEPLOY symbolic-ref --short -q HEAD -> exit=$branch_rc value=[$(first_line "$branch")]"
  url=$(git -C "$DEPLOY" config --local --get remote.origin.url 2>&1); url_rc=$?
  if [ "$url_rc" -eq 0 ] && [ "$(url_canon "$url")" = "$(url_canon "$REPO_URL")" ]; then url_match=yes; else url_match=no; fi
  echo "git -C $DEPLOY config --local --get remote.origin.url equals \$HARNESS_REPO_URL -> exit=$url_rc $url_match"
  st=$(git -C "$DEPLOY" status --porcelain 2>&1); st_rc=$?
  if [ "$st_rc" -eq 0 ]; then
    entries=$(printf '%s' "$st" | grep -a -c '')
    echo "git -C $DEPLOY status --porcelain -> exit=0 entries=$entries"
  else
    echo "git -C $DEPLOY status --porcelain -> exit=$st_rc entries=unread value=[$(first_line "$st")]"
  fi
  out=$(git -C "$DEPLOY" ls-files -v 2>&1); flag_rc=$?
  flagged=$( [ "$flag_rc" -eq 0 ] && printf '%s\n' "$out" | grep -a -c -E '^([a-z]|S) ')
  echo "git -C $DEPLOY ls-files -v, entries marked skip-worktree or assume-unchanged -> exit=$flag_rc count=${flagged:-unread}$([ "$flag_rc" -eq 0 ] || printf ' value=[%s]' "$(first_line "$out")")"
  out=$(git -C "$DEPLOY" ls-files --error-unmatch -- config/CLAUDE.md config/settings.json config/plugins.tsv env/setup.sh 2>&1); payload_rc=$?
  echo "git -C $DEPLOY ls-files --error-unmatch config/CLAUDE.md config/settings.json config/plugins.tsv env/setup.sh -> exit=$payload_rc$([ "$payload_rc" -eq 0 ] || printf ' value=[%s]' "$(first_line "$out")")"
  echo "git -C $DEPLOY log -1 --format='%h %cI' -> $(first_line "$(git -C "$DEPLOY" log -1 --format='%h %cI' 2>&1)")"
  if [ "$head_rc" -ne 0 ] || [ "$want_rc" -ne 0 ] || [ -z "$head" ] || [ "$head" != "$want" ] \
    || [ "$branch_rc" -ne 0 ] || [ "$branch" != "$HARNESS_REF" ] || [ "$url_match" != yes ] \
    || [ "$st_rc" -ne 0 ] || [ -n "$st" ] || [ "$flag_rc" -ne 0 ] || [ "${flagged:-1}" != 0 ] \
    || [ "$payload_rc" -ne 0 ]; then
    fails=$((fails + 1)); return 1
  fi
  return 0
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

  local JQ GIT out failing=""
  JQ=$(command -v jq || echo none)
  echo "command -v jq -> $JQ"
  if [ "$JQ" = none ]; then
    failing="$failing jq"; fails=$((fails + 1))
  else
    out=$(jq -n 1 2>/dev/null); rc=$?
    out=${out%$'\r'}
    echo "jq -n 1 -> exit=$rc value=[$(first_line "$out")]"
    [ "$out" = 1 ] || { failing="$failing jq"; fails=$((fails + 1)); }
  fi
  GIT=$(command -v git || echo none)
  echo "command -v git -> $GIT"
  if [ "$GIT" = none ]; then
    failing="$failing git"; fails=$((fails + 1))
  else
    out=$(git --version 2>&1); rc=$?
    echo "git --version -> exit=$rc value=[$(first_line "$out")]"
    [ "$rc" -eq 0 ] || { failing="$failing git"; fails=$((fails + 1)); }
  fi
  echo "prerequisites failing ->${failing:- none}"
  if [ -n "$failing" ]; then
    echo "delivery -> stopped, not written: $DEPLOY, $CONFIG_DIR/CLAUDE.md, $CONFIG_DIR/settings.json, the global git config, the plugins, $CONFIG_DIR/.my-harness-wrapper.manifest.json"
    [ "$fails" -le 255 ] || fails=255
    return "$fails"
  fi

  if ! deploy; then
    echo "delivery -> stopped before $CONFIG_DIR/CLAUDE.md and $CONFIG_DIR/settings.json, the deployed copy step failed for $DEPLOY"
    [ "$fails" -le 255 ] || fails=255
    return "$fails"
  fi

  local SRC_MD="$DEPLOY/config/CLAUDE.md"
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

  local SRC_SETTINGS="$DEPLOY/config/settings.json"
  local DST_SETTINGS="$CONFIG_DIR/settings.json"
  local MERGE='if length != 2 then error("expected one JSON document in each file, read \(length) in all") else .[0] * .[1] * {env: ({HARNESS_DIR: $h} + (if $w == "yes" then {GIT_CONFIG_COUNT: "1", GIT_CONFIG_KEY_0: "core.hooksPath", GIT_CONFIG_VALUE_0: $v} else {} end))} end'
  local DIFFERS='if length == 2 and (.[0] | type) == "object" and (.[1] | type) == "object" then .[0] as $l | [.[1] | to_entries[] | .key as $k | select(($l | has($k)) and $l[$k] != .value) | $k] | join(" ") else "not compared" end'
  local MODE="" REPLACED
  local HOOKS_DIR="$DEPLOY/git-hooks" HOOKS_VALUE="" HOOKS_SET="" TRIPLE=no
  echo "test -f $SRC_SETTINGS -> $([ -f "$SRC_SETTINGS" ] && echo yes || echo no)"
  echo "test -s $DST_SETTINGS -> $([ -s "$DST_SETTINGS" ] && echo yes || echo no)"
  if hooks_triple; then TRIPLE=yes; else fails=$((fails + 1)); fi
  echo "write env.GIT_CONFIG_COUNT, env.GIT_CONFIG_KEY_0, env.GIT_CONFIG_VALUE_0 -> $TRIPLE"
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
        jq -s --arg h "$DEPLOY" --arg w "$TRIPLE" --arg v "${HOOKS_VALUE:-}" "$MERGE" "$DST_SETTINGS" "$SRC_SETTINGS" > "$TMP"; rc=$?
        echo "jq -s --arg h $DEPLOY --arg w $TRIPLE --arg v ${HOOKS_VALUE:-} '$MERGE' $DST_SETTINGS $SRC_SETTINGS -> exit=$rc"
      else
        jq -s --arg h "$DEPLOY" --arg w "$TRIPLE" --arg v "${HOOKS_VALUE:-}" "[{}] + . | $MERGE" "$SRC_SETTINGS" > "$TMP"; rc=$?
        echo "jq -s --arg h $DEPLOY --arg w $TRIPLE --arg v ${HOOKS_VALUE:-} '[{}] + . | $MERGE' $SRC_SETTINGS -> exit=$rc"
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
  local TRIPLE_BACK
  TRIPLE_BACK=$(jq -r 'if type == "object" and (.env | type) == "object" then [.env.GIT_CONFIG_COUNT, .env.GIT_CONFIG_KEY_0, .env.GIT_CONFIG_VALUE_0] | map(. // "absent" | tostring) | join("\t") else "absent\tabsent\tabsent" end' "$DST_SETTINGS" 2>/dev/null); rc=$?
  TRIPLE_BACK=${TRIPLE_BACK%$'\r'}
  echo "jq -r .env.GIT_CONFIG_COUNT, .env.GIT_CONFIG_KEY_0, .env.GIT_CONFIG_VALUE_0 $DST_SETTINGS -> exit=$rc value=[$(first_line "$TRIPLE_BACK")]"
  if [ "$TRIPLE" = yes ]; then
    if [ "$rc" -eq 0 ] && [ "$TRIPLE_BACK" = "1"$'\t'"core.hooksPath"$'\t'"$HOOKS_VALUE" ]; then
      HOOKS_SET=$HOOKS_VALUE
    else
      fails=$((fails + 1))
    fi
  fi

  local kv key val prior
  for kv in "commit.gpgsign=false" "tag.gpgsign=false"; do
    key=${kv%%=*}; val=${kv#*=}
    prior=$(git config --global --get "$key" 2>/dev/null); rc=$?
    echo "git config --global --get $key -> exit=$rc value=${prior:-}"
    git config --global "$key" "$val"; rc=$?
    echo "git config --global $key $val -> exit=$rc"
    [ "$rc" -eq 0 ] || fails=$((fails + 1))
  done

  local global_hp line ours=0 others=0
  global_hp=$(git config --global --get-all core.hooksPath 2>/dev/null); rc=$?
  global_hp=${global_hp//$'\r'/}
  echo "git config --global --get-all core.hooksPath, before -> exit=$rc value=[$(printf '%s' "$global_hp" | LC_ALL=C tr '\n' ' ' | LC_ALL=C tr '\000-\037\177' '?')]"
  [ "$rc" -le 1 ] || fails=$((fails + 1))
  if [ "$rc" -eq 0 ]; then
    while IFS= read -r line; do
      if same_dir "$line" "$HOOKS_DIR"; then ours=$((ours + 1)); else others=$((others + 1)); fi
    done <<< "$global_hp"
  fi
  echo "global core.hooksPath values naming $HOOKS_DIR -> $ours, other values -> $others"
  if [ "$rc" -gt 1 ]; then
    echo "git config --global --unset-all core.hooksPath -> not run, the global read failed (exit=$rc)"
  elif [ "$ours" -gt 0 ] && [ "$others" -eq 0 ]; then
    git config --global --unset-all core.hooksPath; rc=$?
    echo "git config --global --unset-all core.hooksPath -> exit=$rc"
    [ "$rc" -eq 0 ] || fails=$((fails + 1))
  elif [ "$ours" -gt 0 ]; then
    echo "git config --global --unset-all core.hooksPath -> not run, the global values also name another path"
    fails=$((fails + 1))
  else
    echo "git config --global --unset-all core.hooksPath -> not run, no global value names $HOOKS_DIR"
  fi
  global_hp=$(git config --global --get-all core.hooksPath 2>/dev/null); rc=$?
  global_hp=${global_hp//$'\r'/}
  echo "git config --global --get-all core.hooksPath, after -> exit=$rc value=[$(printf '%s' "$global_hp" | LC_ALL=C tr '\n' ' ' | LC_ALL=C tr '\000-\037\177' '?')]"
  [ "$rc" -le 1 ] || fails=$((fails + 1))
  if [ "$rc" -eq 0 ]; then
    ours=0
    while IFS= read -r line; do
      ! same_dir "$line" "$HOOKS_DIR" || ours=$((ours + 1))
    done <<< "$global_hp"
    if [ "$ours" -gt 0 ]; then
      echo "global core.hooksPath values naming $HOOKS_DIR, after -> $ours"
      [ "$others" -gt 0 ] || fails=$((fails + 1))
    fi
  fi

  local CLI CLI_FROM mp_source plugin_id _rest rows=0
  local PLUGINS="$DEPLOY/config/plugins.tsv"
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
        echo "bash $DEPLOY/scripts/plugin-dependencies.sh <CLI> $plugin_id -> not run, no CLI"
        fails=$((fails + 1))
        continue
      fi
      "$CLI" plugin marketplace add "$mp_source"; rc=$?
      echo "claude plugin marketplace add $mp_source -> exit=$rc"
      [ "$rc" -eq 0 ] || fails=$((fails + 1))
      "$CLI" plugin install "$plugin_id" --scope user --yes; rc=$?
      echo "claude plugin install $plugin_id --scope user --yes -> exit=$rc"
      [ "$rc" -eq 0 ] || fails=$((fails + 1))
      bash "$DEPLOY/scripts/plugin-dependencies.sh" "$CLI" "$plugin_id"; rc=$?
      echo "bash $DEPLOY/scripts/plugin-dependencies.sh $CLI $plugin_id -> exit=$rc"
      [ "$rc" -eq 0 ] || fails=$((fails + 1))
    done 3< "$PLUGINS"
    echo "plugins.tsv rows carrying a plugin_id -> $rows"
  else
    fails=$((fails + 1))
  fi

  local SETUP="$DEPLOY/env/setup.sh" VER_LINES VER_RC VERSION=""
  VER_LINES=$(grep -a '^export BOOTSTRAP_VERSION=' "$SETUP" 2>/dev/null); VER_RC=$?
  if [ "$VER_RC" -eq 0 ] && [ -n "$VER_LINES" ] && [ "$VER_LINES" = "${VER_LINES%%$'\n'*}" ]; then
    VERSION=${VER_LINES#export BOOTSTRAP_VERSION=}
    VERSION=${VERSION%"${VERSION##*[!$' \t']}"}
    case "$VERSION" in ''|*[!0-9A-Za-z._-]*) VERSION="" ;; esac
  fi
  echo "grep '^export BOOTSTRAP_VERSION=' $SETUP -> exit=$VER_RC value=${VERSION:-unread}"
  [ -n "$VERSION" ] || fails=$((fails + 1))

  local COMMIT GIT_EMAIL INSTALLED_AT
  COMMIT=$(git -C "$DEPLOY" rev-parse --short HEAD 2>/dev/null); rc=$?
  echo "git -C $DEPLOY rev-parse --short HEAD -> exit=$rc value=${COMMIT:-}"
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
      --arg core_hooks_path "$HOOKS_SET" \
      --arg git_user_email "${GIT_EMAIL:-}" \
      --arg installed_at "${INSTALLED_AT:-}" \
      --arg local_checkout "$DEPLOY" \
      '{bootstrap_version: $bootstrap_version, commit: $commit, config_dir: $config_dir, core_hooks_path: $core_hooks_path, git_user_email: $git_user_email, installed_at: $installed_at, local_checkout: $local_checkout}' \
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

{
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
}
