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

msg_case() {
  local id=$1 line=$2 want=$3 dir="$WORK/$1" err commit_rc got=accepted verdict=pass
  mkdir -p "$dir"
  REPO="$dir/repo"; GC="$dir/gitconfig"; TRIPLE=""
  : > "$GC"
  mkdir -p "$REPO"
  cgit init -q . >/dev/null 2>&1
  mkcopy "$dir/C" fixed
  cgit config core.hooksPath "$dir/C"
  echo x > "$REPO/f"
  cgit add f >/dev/null 2>&1
  err=$(cgit commit -q -m 'what changed, in one sentence.' -m "$line" 2>&1 >/dev/null); commit_rc=$?
  if [ "$commit_rc" -ne 0 ]; then
    got="exit=$commit_rc without the marker"
    if printf '%s\n' "$err" | grep -a -q -F -- "harness commit-msg: matched line -> $line"; then got=refused; fi
  fi
  if [ "$got" != "$want" ]; then verdict=FAIL; fails=$((fails + 1)); fi
  echo "$id commit message ending in '$line' -> expected $want, actual $got, $verdict"
}

msg_case M1 'Assisted-by: Claude (Anthropic)' refused
msg_case M2 'Generated-by: Claude Code' refused
msg_case M3 'AI-assisted: Claude' refused
msg_case M4 'Written-by: an Anthropic model' refused
msg_case M5 'Assisted-by: Copilot' accepted
msg_case M6 'the Assisted-by trailer is optional' accepted

RLO='\342\200\256'; LRI='\342\201\246'; TAG='\363\240\200\201'; NUL='\000'
ZWSP='\342\200\213'; WJ='\342\201\240'; BOM='\357\273\277'
EMOJI='\360\237\221\250\342\200\215\360\237\222\273'
HEBREW='\327\251\327\234\327\225\327\235\342\200\217'
SUBJECT='what changed, in one sentence.'

fresh() {
  DIR="$WORK/$1"
  REPO="$DIR/repo"; GC="$DIR/gitconfig"; TRIPLE=""
  mkdir -p "$REPO"
  : > "$GC"
  cgit init -q . >/dev/null 2>&1
  mkcopy "$DIR/C" fixed
  cgit config core.hooksPath "$DIR/C"
}

verdict() {
  local v=pass
  if [ "$3" != "$4" ]; then v=FAIL; fails=$((fails + 1)); fi
  echo "$1 $2 -> expected $3, actual $4, $v"
}

commit_check() {
  local id=$1 label=$2 want=$3 marker=$4 err rc state=accepted mark=absent
  shift 4
  cgit add -A >/dev/null 2>&1
  err=$(cgit commit -q "$@" 2>&1 >/dev/null); rc=$?
  [ "$rc" -eq 0 ] || state=refused
  case "$err" in *"$marker"*) mark=present ;; esac
  verdict "$id" "$label" "$want" "commit $state, '$marker' $mark${RUNS:+, own pre-commit runs=$(lines "$RUNS")}"
}

msg_hidden() {
  local id=$1 label=$2 want=$3 marker=$4
  fresh "$id"
  echo x > "$REPO/f"
  printf "$5" > "$DIR/msg"
  commit_check "$id" "commit message with $label" "$want" "$marker" -F "$DIR/msg"
}

file_hidden() {
  local id=$1 label=$2 want=$3 marker=$4
  fresh "$id"
  printf "$5" > "$REPO/f"
  commit_check "$id" "staged file with $label" "$want" "$marker" -m "$SUBJECT"
}

RUNS=""
CM='harness commit-msg: hidden character ->'
PC='harness pre-commit: hidden character ->'
msg_hidden C1 'U+202E on line 3' "commit refused, '$CM U+202E on line 3 of the commit message' present" "$CM U+202E on line 3 of the commit message" "$SUBJECT\n\nbody $RLO here\n"
msg_hidden C2 'U+2066' "commit refused, '$CM U+2066' present" "$CM U+2066" "$SUBJECT\n\nbody $LRI here\n"
msg_hidden C3 'U+E0001' "commit refused, '$CM U+E0001' present" "$CM U+E0001" "$SUBJECT\n\nbody $TAG here\n"
msg_hidden C4 'NUL' "commit refused, '$CM U+0000' present" "$CM U+0000" "$SUBJECT\n\nbody $NUL here\n"
msg_hidden C5 'a BOM at the start' "commit accepted, 'harness' absent" harness "$BOM$SUBJECT\n"
msg_hidden C6 'an emoji joined with U+200D' "commit accepted, 'harness' absent" harness "$SUBJECT\n\nbody $EMOJI here\n"
msg_hidden C7 'Hebrew text with U+200F' "commit accepted, 'harness' absent" harness "$SUBJECT\n\nbody $HEBREW here\n"
msg_hidden C8 'U+200B' "commit accepted, 'harness' absent" harness "$SUBJECT\n\nbody $ZWSP here\n"

file_hidden F1 'U+202E on line 2' "commit refused, '$PC U+202E at f:2' present" "$PC U+202E at f:2" "one\ntwo $RLO x\nthree\n"
fresh F2
printf 'one\ntwo\nthree\n' > "$REPO/a"
mkdir -p "$REPO/dir"
printf "one\ntwo\nthree $LRI x\n" > "$REPO/dir/b.txt"
commit_check F2 'two staged files, U+2066 on line 3 of the second' "commit refused, '$PC U+2066 at dir/b.txt:3' present" "$PC U+2066 at dir/b.txt:3" -m "$SUBJECT"
file_hidden F3 'U+E0001 on line 4' "commit refused, '$PC U+E0001 at f:4' present" "$PC U+E0001 at f:4" "one\ntwo\nthree\nfour $TAG x\n"
fresh F4
awk 'BEGIN { for (i = 0; i < 200; i++) printf "%049d\n", i }' > "$REPO/f"
printf "nul $NUL here\n" >> "$REPO/f"
commit_check F4 "staged file with NUL on line 201, after $(($(wc -c < "$REPO/f") - 10)) bytes of text" "commit refused, '$PC U+0000 at f:201' present" "$PC U+0000 at f:201" -m "$SUBJECT"
file_hidden F5 'a BOM at the start' "commit accepted, 'harness' absent" harness "${BOM}one\ntwo\n"
file_hidden F6 'an emoji joined with U+200D' "commit accepted, 'harness' absent" harness "one\ntwo $EMOJI x\n"
file_hidden F7 'Hebrew text with U+200F' "commit accepted, 'harness' absent" harness "one\ntwo $HEBREW x\n"
WARN='harness pre-commit: zero-width character'
file_hidden F8 'U+200B on line 2' "commit accepted, '$WARN U+200B at f:2' present" "$WARN U+200B at f:2" "one\ntwo $ZWSP x\n"
file_hidden F9 'U+2060 on line 3' "commit accepted, '$WARN U+2060 at f:3' present" "$WARN U+2060 at f:3" "one\ntwo\nthree $WJ x\n"
file_hidden F22 'U+200B on line 2 and U+202E on line 3' "commit refused, '$PC U+202E at f:3' present" "$PC U+202E at f:3" "one\ntwo $ZWSP x\nthree $RLO x\n"
file_hidden F10 'NUL in its first bytes and U+202E on line 2' "commit accepted, 'harness' absent" harness "a${NUL}b\ntwo $RLO x\n"

fresh F11
cgit config --unset core.hooksPath
printf "one\ntwo $RLO x\nthree\n" > "$REPO/f"
commit_check F11 'U+202E committed on line 2 while no harness hook is configured' "commit accepted, 'harness' absent" harness -m "$SUBJECT"
cgit config core.hooksPath "$DIR/C"
echo four >> "$REPO/f"
commit_check F12 'clean line added to the file that holds U+202E' "commit accepted, 'harness' absent" harness -m "$SUBJECT"
printf 'one\nthree\nfour\n' > "$REPO/f"
commit_check F13 'the U+202E line removed' "commit accepted, 'harness' absent" harness -m "$SUBJECT"

fresh F14
awk 'BEGIN { for (i = 1; i < 9000; i++) printf "%099d\n", i; printf "%097d", 0 }' > "$REPO/big.txt"
printf "$RLO" >> "$REPO/big.txt"
commit_check F14 "staged file of $(wc -c < "$REPO/big.txt" | tr -d ' ') bytes ending in U+202E" "commit refused, '$PC U+202E at big.txt:9000' present" "$PC U+202E at big.txt:9000" -m "$SUBJECT"

fresh F15
printf 'one\ntwo\nthree\n' > "$REPO/f"
commit_check F15 'clean first commit' "commit accepted, 'harness' absent" harness -m "$SUBJECT"
printf "one\ntwo $LRI x\nthree\n" > "$REPO/f"
commit_check F16 'U+2066 added on line 2 in a second commit' "commit refused, '$PC U+2066 at f:2' present" "$PC U+2066 at f:2" -m "$SUBJECT"

fresh F17
RUNS="$DIR/own.marker"
mkmark "$REPO/.git/hooks/pre-commit" "$RUNS"
echo x > "$REPO/f"
commit_check F17 "clean commit, repository's own pre-commit" "commit accepted, 'harness' absent, own pre-commit runs=1" harness -m "$SUBJECT"
fresh F18
RUNS="$DIR/own.marker"
mkmark "$REPO/.git/hooks/pre-commit" "$RUNS"
printf "one\ntwo $RLO x\n" > "$REPO/f"
commit_check F18 "U+202E staged, repository's own pre-commit" "commit refused, '$PC U+202E at f:2' present, own pre-commit runs=0" "$PC U+202E at f:2" -m "$SUBJECT"
fresh F19
RUNS="$DIR/own.marker"
printf '#!/bin/sh\necho ran >> "%s"\nexit 1\n' "$RUNS" > "$REPO/.git/hooks/pre-commit"
chmod +x "$REPO/.git/hooks/pre-commit"
echo x > "$REPO/f"
commit_check F19 "clean commit, repository's own pre-commit exits 1" "commit refused, 'harness' absent, own pre-commit runs=1" harness -m "$SUBJECT"
RUNS=""

NOT='so the staged changes were not checked'
fresh F20
rm "$DIR/C/lib/hidden-chars.tsv"
echo x > "$REPO/f"
commit_check F20 'clean commit, hidden-chars.tsv removed from the hooks' "commit refused, 'hidden-chars.tsv could not be applied, $NOT' present" "hidden-chars.tsv could not be applied, $NOT" -m "$SUBJECT"
fresh F21
rm "$DIR/C/lib/hidden-chars.sh"
echo x > "$REPO/f"
commit_check F21 'clean commit, hidden-chars.sh removed from the hooks' "commit refused, 'hidden-chars.sh could not be read, $NOT' present" "hidden-chars.sh could not be read, $NOT" -m "$SUBJECT"
fresh C9
rm "$DIR/C/lib/hidden-chars.tsv" "$DIR/C/pre-commit"
echo x > "$REPO/f"
commit_check C9 'clean commit, hidden-chars.tsv and the pre-commit hook removed from the hooks' "commit refused, 'so the message was not checked' present" 'so the message was not checked' -m "$SUBJECT"

fresh C10
cgit config --unset core.hooksPath
awk 'BEGIN { for (i = 1; i <= 9000; i++) printf "%099d\n", i }' > "$REPO/big.txt"
printf "$RLO\n" >> "$REPO/big.txt"
commit_check C10 'large file ending in a U+202E line committed while no harness hook is configured' "commit accepted, 'harness' absent" harness -m "$SUBJECT"
cgit config core.hooksPath "$DIR/C"
cgit config commit.cleanup scissors
: > "$REPO/big.txt"
printf '%s\n' "$SUBJECT" > "$DIR/msg"
GIT_EDITOR=true commit_check C11 'git commit -v showing a removed U+202E line in a large diff' "commit accepted, 'harness' absent" harness -v -e -F "$DIR/msg"

SOH='\001'
msg_hidden C12 'U+0001' "commit accepted, 'harness' absent" harness "$SUBJECT\n\nbody $SOH here\n"
msg_hidden C13 'U+0001, read for a shell warning' "commit accepted, 'warning:' absent" warning: "$SUBJECT\n\nbody $SOH here\n"
msg_hidden C14 'U+0001 then U+202E on line 3' "commit refused, '$CM U+202E on line 3 of the commit message' present" "$CM U+202E on line 3 of the commit message" "$SUBJECT\n\nbody $SOH and $RLO here\n"
msg_hidden C15 'U+0001 inside the words Co-Authored-By' "commit accepted, 'harness' absent" harness "$SUBJECT\n\nCo-Authored$SOH-By: Claude <noreply@anthropic.com>\n"
file_hidden F23 'U+0001 on line 2' "commit accepted, 'harness' absent" harness "one\ntwo $SOH x\n"
file_hidden F24 'U+0001 then U+202E on line 2' "commit refused, '$PC U+202E at f:2' present" "$PC U+202E at f:2" "one\ntwo $SOH and $RLO x\nthree\n"

echo "fail -> $fails"
[ "$fails" -eq 0 ]
