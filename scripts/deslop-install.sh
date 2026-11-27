#!/bin/bash
set -uo pipefail

case "${BASH_SOURCE[0]}" in */*) SELF_DIR=${BASH_SOURCE[0]%/*} ;; *) SELF_DIR=. ;; esac
SELF_DIR=$(cd "$SELF_DIR" && pwd)
PINS="$SELF_DIR/../config/deslop-please.pins"
cd / || exit 1
URL_RE='^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'
REV_RE='^[0-9a-f]{40}$'
PKG_RE='^@[a-z0-9._-]+/[a-z0-9._-]+@[0-9]+\.[0-9]+\.[0-9]+$'
fails=0
URL=""
REV=""
INDEXERS=()

show() { local LC_ALL=C; local s=${1//[[:cntrl:]]/?}; printf '%s' "$s"; }

run_logged() {
  local l
  "$@" 2>&1 | while IFS= read -r l || [ -n "$l" ]; do show "${l%$'\r'}"; echo; done
  return "${PIPESTATUS[0]}"
}

finish() {
  echo "deslop-install fails -> $fails"
  [ "$fails" -le 255 ] || fails=255
  exit "$fails"
}

echo "test -f $PINS -> $([ -f "$PINS" ] && echo yes || echo no)"
if [ -f "$PINS" ]; then
  while IFS='=' read -r key value || [ -n "${key:-}" ]; do
    value=${value%$'\r'}
    case "$key" in
      url) URL=$value ;;
      rev) REV=$value ;;
      indexer) INDEXERS+=("$value") ;;
    esac
  done < "$PINS"
fi
echo "read $PINS -> url=[$(show "$URL")] rev=[$(show "$REV")] indexers=[$(show "${INDEXERS[*]-}")]"
valid=yes
[[ "$URL" =~ $URL_RE ]] || valid=no
[[ "$REV" =~ $REV_RE ]] || valid=no
[ "${#INDEXERS[@]}" -gt 0 ] || valid=no
for pkg in "${INDEXERS[@]}"; do [[ "$pkg" =~ $PKG_RE ]] || valid=no; done
echo "pins match $URL_RE, $REV_RE and $PKG_RE -> $valid"
if [ "$valid" != yes ]; then
  fails=$((fails + 1))
  finish
fi

BUILD="cargo install --git $URL --rev $REV --locked deslop-please"
CARGO=$(command -v cargo || echo none)
echo "command -v cargo -> $(show "$CARGO")"
if [ "$CARGO" = none ]; then
  echo "$BUILD -> skipped, no cargo"
else
  run_logged cargo install --git "$URL" --rev "$REV" --locked deslop-please; rc=$?
  echo "$BUILD -> exit=$rc"
  [ "$rc" -eq 0 ] || fails=$((fails + 1))
  LIST=$(cargo install --list 2>&1); list_rc=$?
  LINE=""
  while IFS= read -r l; do
    case "$l" in "deslop-please v"*) LINE=${l%$'\r'} ;; esac
  done <<< "$LIST"
  echo "cargo install --list -> exit=$list_rc line=[$(show "$LINE")]"
  pinned=no
  case "$LINE" in *"($URL?rev=$REV#"*) pinned=yes ;; esac
  echo "cargo install --list names $URL?rev=$REV -> $pinned"
  if [ "$rc" -eq 0 ] && { [ "$list_rc" -ne 0 ] || [ "$pinned" != yes ]; }; then fails=$((fails + 1)); fi
fi

NPM=$(command -v npm || echo none)
NODE=$(command -v node || echo none)
echo "command -v npm -> $(show "$NPM")"
echo "command -v node -> $(show "$NODE")"
skip=""
if [ "$NODE" != none ]; then
  NODE_VER=$(node --version 2>&1); rc=$?
  NODE_VER=${NODE_VER%%$'\n'*}
  echo "node --version -> exit=$rc value=[$(show "$NODE_VER")]"
  major=${NODE_VER#v}
  major=${major%%.*}
  case "$major" in ''|*[!0-9]*) major=0 ;; esac
  [ "$rc" -eq 0 ] || major=0
  [ "$major" -ge 18 ] || skip="Node older than 18 or unreadable"
fi
[ "$NODE" != none ] || skip="no node"
[ "$NPM" != none ] || skip="no npm"
for pkg in "${INDEXERS[@]}"; do
  INSTALL="npm install -g --ignore-scripts --no-audit --no-fund $pkg"
  if [ -n "$skip" ]; then
    echo "$INSTALL -> skipped, $skip"
    continue
  fi
  run_logged npm install -g --ignore-scripts --no-audit --no-fund "$pkg"; rc=$?
  echo "$INSTALL -> exit=$rc"
  [ "$rc" -eq 0 ] || fails=$((fails + 1))
  bin=${pkg#*/}
  bin=${bin%@*}
  path=$(command -v "$bin" || echo none)
  echo "command -v $bin -> $(show "$path")"
  if [ "$path" != none ]; then
    out=$("$bin" --version 2>&1); rc=$?
    out=${out%%$'\n'*}
    out=${out%$'\r'}
    echo "$bin --version -> exit=$rc value=[$(show "$out")]"
  fi
done
finish
