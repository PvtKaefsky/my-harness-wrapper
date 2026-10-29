#!/bin/bash
set -uo pipefail

CLI=${1:-}
PLUGIN_ID=${2:-}
NAME_RE='^(@[A-Za-z0-9_~-][A-Za-z0-9._~-]*/)?[A-Za-z0-9_~-][A-Za-z0-9._~-]*$'

sanitize() { printf '%s' "$1" | LC_ALL=C tr '\n' ' ' | LC_ALL=C tr '\000-\037\177' '?'; }

check_names() {
  local name
  MISSING=""
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ -f "$P/node_modules/$name/package.json" ]; then
      echo "test -f $P_SHOW/node_modules/$name/package.json -> yes"
    else
      echo "test -f $P_SHOW/node_modules/$name/package.json -> no"
      MISSING="$MISSING $name"
    fi
  done <<< "$NAMES"
}

ID_SHOW=$(sanitize "$PLUGIN_ID")
echo "plugin dependencies of ${ID_SHOW:-empty} -> claude CLI $(sanitize "${CLI:-none}")"
if [ -z "$PLUGIN_ID" ] || [ -z "$CLI" ]; then
  echo "plugin dependencies -> not run, plugin_id or CLI empty"
  exit 1
fi

LIST=$("$CLI" plugin list --json 2>/dev/null); rc=$?
echo "claude plugin list --json -> exit=$rc"
[ "$rc" -eq 0 ] || exit 1
RAW=$(printf '%s' "$LIST" | jq -r --arg id "$PLUGIN_ID" 'if type == "array" then [.[] | select(.id == $id) | .installPath | strings] | unique | .[] else error("top level is " + type) end' 2>/dev/null); rc=$?
RAW=${RAW//$'\r'/}
COUNT=$(printf '%s' "$RAW" | grep -a -c '')
echo "jq installPath of $ID_SHOW from claude plugin list --json -> exit=$rc count=$COUNT value=[$(sanitize "$RAW")]"
if [ "$rc" -ne 0 ] || [ "$COUNT" != 1 ]; then exit 1; fi

P=$RAW
if command -v cygpath >/dev/null 2>&1; then
  CONV=$(cygpath -u "$RAW" 2>/dev/null); rc=$?
  echo "cygpath -u $(sanitize "$RAW") -> exit=$rc value=[$(sanitize "$CONV")]"
  [ "$rc" -ne 0 ] || [ -z "$CONV" ] || P=$CONV
fi
P_SHOW=$(sanitize "$P")
case "$P" in
  /*) ;;
  *) echo "installPath $P_SHOW is an absolute path -> no"; exit 1 ;;
esac
echo "test -d $P_SHOW -> $([ -d "$P" ] && echo yes || echo no)"
[ -d "$P" ] || exit 1

PKG="$P/package.json"
echo "test -f $P_SHOW/package.json -> $([ -f "$PKG" ] && echo yes || echo no)"
if [ ! -f "$PKG" ]; then
  echo "npm ci in $P_SHOW -> not run, no package.json"
  exit 0
fi
NAMES=$(jq -r 'if type != "object" then error("top level is " + type)
  elif (has("dependencies") | not) then empty
  elif (.dependencies | type) != "object" then error("dependencies is " + (.dependencies | type))
  else .dependencies | keys[] end' "$PKG" 2>/dev/null); rc=$?
NAMES=${NAMES//$'\r'/}
echo "jq .dependencies keys $P_SHOW/package.json -> exit=$rc count=$(printf '%s' "$NAMES" | grep -a -c '')"
[ "$rc" -eq 0 ] || exit 1
while IFS= read -r name; do
  [ -n "$name" ] || continue
  if ! [[ "$name" =~ $NAME_RE ]]; then
    echo "dependency name [$(sanitize "$name")] matches $NAME_RE -> no"
    exit 1
  fi
done <<< "$NAMES"

check_names
echo "unresolved dependencies of $ID_SHOW ->${MISSING:- none}"
if [ -z "$MISSING" ]; then
  echo "npm ci in $P_SHOW -> not run, every declared dependency resolves"
  exit 0
fi

NPM=$(command -v npm || echo none)
echo "command -v npm -> $NPM"
[ "$NPM" != none ] || exit 1
( cd -- "$P" && npm ci --omit=dev --ignore-scripts --no-audit --no-fund ) 2>&1; rc=$?
echo "npm ci --omit=dev --ignore-scripts --no-audit --no-fund in $P_SHOW -> exit=$rc"
check_names
echo "unresolved dependencies of $ID_SHOW after npm ci ->${MISSING:- none}"
if [ "$rc" -ne 0 ] || [ -n "$MISSING" ]; then exit 1; fi
exit 0
