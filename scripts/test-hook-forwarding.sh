#!/bin/bash
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC="$ROOT/git-hooks"
OLD=5f3f87a
fails=0

echo "test -f $SRC/lib/dispatch.sh -> $([ -f "$SRC/lib/dispatch.sh" ] && echo yes || echo no)"
echo "command -v timeout -> $(command -v timeout || echo none)"
if [ ! -f "$SRC/lib/dispatch.sh" ] || ! command -v timeout >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  echo "fail -> not run"
  exit 1
fi

WORK=$(mktemp -d) || { echo "mktemp -d -> exit=$?, not run"; exit 1; }
trap 'rm -rf -- "$WORK"' EXIT

OLD_DISPATCH="$WORK/old-dispatch.sh"
git -C "$ROOT" show "$OLD:git-hooks/lib/dispatch.sh" > "$OLD_DISPATCH" 2>/dev/null; old_rc=$?
echo "git -C $ROOT show $OLD:git-hooks/lib/dispatch.sh -> exit=$old_rc"

mkcopy() {
  [ ! -d "$1" ] || return 0
  cp -R "$SRC" "$1"
  if [ "$2" = old ]; then cp "$OLD_DISPATCH" "$1/lib/dispatch.sh"; fi
}

mkmark() {
  printf '#!/bin/sh\necho ran >> "%s"\nexit 0\n' "$2" > "$1"
  chmod +x "$1"
}

cgit() {
  (
    cd "$REPO" || exit 99
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
    export GIT_CONFIG_GLOBAL="$GC" GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
    if [ -n "${TRIPLE-}" ]; then export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$TRIPLE"; fi
    timeout -k 2 10 git "$@"
  )
}

lines() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }

run_case() {
  local id=$1 label=$2 local_kind=$3 global_kind=$4 triple_kind=$5 want_extra=${6:-}
  local dir="$WORK/$id" add_rc commit_rc own extra verdict=pass
  mkdir -p "$dir"
  REPO="$dir/repo"; GC="$dir/gitconfig"; TRIPLE=""
  : > "$GC"
  mkdir -p "$REPO"
  cgit init -q . >/dev/null 2>&1
  own="$dir/own.marker"; extra="$dir/extra.marker"
  mkmark "$REPO/.git/hooks/commit-msg" "$own"
  local spec kind path
  for spec in "local:$local_kind" "global:$global_kind" "triple:$triple_kind"; do
    kind=${spec#*:}
    [ -n "$kind" ] || continue
    case "$kind" in
      C-fixed) mkcopy "$dir/C" fixed; path="$dir/C" ;;
      C-old) mkcopy "$dir/C" old; path="$dir/C" ;;
      D-fixed) mkcopy "$dir/D" fixed; path="$dir/D" ;;
      D-old) mkcopy "$dir/D" old; path="$dir/D" ;;
      P) mkdir -p "$dir/P"; mkmark "$dir/P/commit-msg" "$extra"; path="$dir/P" ;;
    esac
    case "${spec%%:*}" in
      local) cgit config core.hooksPath "$path" ;;
      global) cgit config --global core.hooksPath "$path" ;;
      triple) TRIPLE=$path ;;
    esac
  done
  echo x > "$REPO/f"
  cgit add f >/dev/null 2>&1; add_rc=$?
  cgit commit -q -m 'what changed, in one sentence.' >/dev/null 2>&1; commit_rc=$?
  local own_n extra_n want_own=1 want_extra_n=0
  own_n=$(lines "$own"); extra_n=$(lines "$extra")
  if [ "$want_extra" = P ]; then want_own=0; want_extra_n=1; fi
  if [ "$add_rc" -ne 0 ] || [ "$commit_rc" -ne 0 ] || [ "$own_n" -ne "$want_own" ] || [ "$extra_n" -ne "$want_extra_n" ]; then verdict=FAIL; fails=$((fails + 1)); fi
  echo "$id $label -> expected add=0 commit=0 repository hook runs=$want_own plain hook runs=$want_extra_n, actual add=$add_rc commit=$commit_rc repository hook runs=$own_n plain hook runs=$extra_n, $verdict"
}

run_case T1 'local C (fixed), global D (fixed)' C-fixed D-fixed ""
if [ "$old_rc" -eq 0 ]; then
  run_case T2 "local C at $OLD, global D (fixed)" C-old D-fixed ""
  run_case T3 "local C (fixed), global D at $OLD" C-fixed D-old ""
else
  echo "T2 local C at $OLD, global D (fixed) -> $OLD:git-hooks/lib/dispatch.sh unreadable, FAIL"
  echo "T3 local C (fixed), global D at $OLD -> $OLD:git-hooks/lib/dispatch.sh unreadable, FAIL"
  fails=$((fails + 2))
fi
run_case T4 'local D, global D' D-fixed D-fixed ""
run_case T5 'command-scope triple D, local plain directory P' P "" D-fixed P
run_case T6 'command-scope triple C, local D' D-fixed "" C-fixed

echo "fail -> $fails"
[ "$fails" -eq 0 ]
