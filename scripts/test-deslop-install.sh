#!/bin/bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/deslop-install.sh"
PINS="$ROOT/config/deslop-please.pins"
URL=https://github.com/Bor4brn/deslop-please
REV=cfabfb9ee417e150d5342e8ef0d6a0fe725cc9a0
BUILD="cargo install --git $URL --rev $REV --locked deslop-please"
NPM_PY="npm install -g --ignore-scripts --no-audit --no-fund @sourcegraph/scip-python@0.6.8"
NPM_TS="npm install -g --ignore-scripts --no-audit --no-fund @sourcegraph/scip-typescript@0.5.2"
LISTED="deslop-please v0.1.6 ($URL?rev=$REV#cfabfb9e):"
fails=0

echo "test -f $SCRIPT -> $([ -f "$SCRIPT" ] && echo yes || echo no)"
if [ ! -f "$SCRIPT" ]; then
  echo "fail -> not run"
  exit 1
fi

WORK=$(mktemp -d) || { echo "mktemp -d -> exit=$?, not run"; exit 1; }
trap 'rm -rf -- "$WORK"' EXIT

write_stub() {
  printf '#!/bin/bash\nprintf "%%s\\n" "%s $*" >> "$STUB_CALLS"\n%s\n' "$2" "$3" > "$1/$2"
  chmod +x "$1/$2"
}

make_bin() {
  local dir="$WORK/$1" tool
  mkdir -p "$dir"
  shift
  for tool in "$@"; do
    case "$tool" in
      cargo) write_stub "$dir" cargo 'if [ "$1 ${2:-}" = "install --list" ]; then printf "%s\n" "$STUB_LIST"; exit 0; fi; echo building; exit "${STUB_BUILD_RC:-0}"' ;;
      npm) write_stub "$dir" npm 'exit "${STUB_NPM_RC:-0}"' ;;
      node) write_stub "$dir" node 'printf "%s\n" "${STUB_NODE:-v24.20.0}"' ;;
      scip-python) write_stub "$dir" scip-python 'echo "SyntaxError: Invalid regular expression"; exit 1' ;;
      scip-typescript) write_stub "$dir" scip-typescript 'echo 0.5.2' ;;
    esac
  done
}

make_bin all cargo npm node scip-python scip-typescript
make_bin nocargo npm node scip-python scip-typescript
make_bin nonpm cargo node
make_bin nonode cargo npm

run() {
  : > "$WORK/calls"
  OUT=$(env -i STUB_CALLS="$WORK/calls" STUB_LIST="$LISTED" "$@" "$BASH" "$SCRIPT" 2>&1)
  RC=$?
  CALLS=$(cat "$WORK/calls")
}

check() {
  local label=$1 verdict=pass
  shift
  "$@" || { verdict=FAIL; fails=$((fails + 1)); }
  echo "$label -> $verdict"
}

has_line() { printf '%s\n' "$OUT" | grep -a -q -x -F -- "$1"; }
calls_are() { [ "$CALLS" = "$(printf '%s\n' "$@")" ] || { printf 'calls -> [%s]\n' "$CALLS"; return 1; }; }
cargo_calls() { printf '%s\n' "$CALLS" | grep -a -c '^cargo '; }
npm_calls() { printf '%s\n' "$CALLS" | grep -a -c '^npm '; }

expected_pins=$(printf '%s\n' "url=$URL" "rev=$REV" indexer=@sourcegraph/scip-python@0.6.8 indexer=@sourcegraph/scip-typescript@0.5.2)
check "the pins file holds the URL, the commit and the two indexers" [ "$(tr -d '\r' < "$PINS")" = "$expected_pins" ]

run PATH="$WORK/all"
check "every tool present: exit 0, last line fails -> 0" eval '[ "$RC" -eq 0 ] && [ "${OUT##*$'"'"'\n'"'"'}" = "deslop-install fails -> 0" ]'
check "every tool present: the calls are the pinned build with --rev, the list, the two pinned indexers and their --version" \
  calls_are "$BUILD" "cargo install --list" "node --version" "$NPM_PY" "scip-python --version" "$NPM_TS" "scip-typescript --version"
check "every tool present: the build line and its exit are logged" has_line "$BUILD -> exit=0"
check "every tool present: the list line names the pin" has_line "cargo install --list names $URL?rev=$REV -> yes"
check "every tool present: --ignore-scripts on both indexers, logged" eval 'has_line "$NPM_PY -> exit=0" && has_line "$NPM_TS -> exit=0"'
check "a nonzero scip-python --version is logged and counts no failure" has_line "scip-python --version -> exit=1 value=[SyntaxError: Invalid regular expression]"
check "scip-typescript --version is logged" has_line "scip-typescript --version -> exit=0 value=[0.5.2]"

run PATH="$WORK/nocargo"
check "no cargo: exit 0, a skip, no cargo call" eval '[ "$RC" -eq 0 ] && has_line "$BUILD -> skipped, no cargo" && [ "$(cargo_calls)" -eq 0 ] && [ "$(npm_calls)" -eq 2 ]'

run PATH="$WORK/nonpm"
check "no npm: exit 0, a skip per indexer, no npm call" eval '[ "$RC" -eq 0 ] && has_line "$NPM_PY -> skipped, no npm" && has_line "$NPM_TS -> skipped, no npm" && [ "$(npm_calls)" -eq 0 ]'

run PATH="$WORK/nonode"
check "no node: exit 0, a skip per indexer, no npm call" eval '[ "$RC" -eq 0 ] && has_line "$NPM_PY -> skipped, no node" && [ "$(npm_calls)" -eq 0 ]'

run PATH="$WORK/all" STUB_NODE=v16.20.2
check "Node v16.20.2: exit 0, a skip per indexer, no npm call" eval '[ "$RC" -eq 0 ] && has_line "$NPM_TS -> skipped, Node older than 18 or unreadable" && [ "$(npm_calls)" -eq 0 ]'

run PATH="$WORK/all" STUB_NODE=v18.0.0
check "Node v18.0.0: both indexers installed" eval '[ "$RC" -eq 0 ] && [ "$(npm_calls)" -eq 2 ]'

run PATH="$WORK/all" STUB_BUILD_RC=101 STUB_LIST=
check "a failed build: exit 1, fails -> 1" eval '[ "$RC" -eq 1 ] && has_line "$BUILD -> exit=101" && has_line "deslop-install fails -> 1"'

run PATH="$WORK/all" STUB_NPM_RC=1
check "two failed indexer installs: exit 2" eval '[ "$RC" -eq 2 ] && has_line "$NPM_PY -> exit=1"'

run PATH="$WORK/all" "STUB_LIST=deslop-please v0.1.6:"
check "a list without the pin: reported, fails -> 1" eval '[ "$RC" -eq 1 ] && has_line "cargo install --list -> exit=0 line=[deslop-please v0.1.6:]" && has_line "cargo install --list names $URL?rev=$REV -> no"'

mkdir -p "$WORK/copy/scripts" "$WORK/copy/config"
cp "$SCRIPT" "$WORK/copy/scripts/"
printf 'url=%s\nrev=main\nindexer=@sourcegraph/scip-python@0.6.8\n' "$URL" > "$WORK/copy/config/deslop-please.pins"
: > "$WORK/calls"
OUT=$(env -i STUB_CALLS="$WORK/calls" PATH="$WORK/all" "$BASH" "$WORK/copy/scripts/deslop-install.sh" 2>&1); RC=$?
CALLS=$(cat "$WORK/calls")
check "a rev that is no 40-hex commit: exit 1, no call" eval '[ "$RC" -eq 1 ] && [ -z "$CALLS" ] && has_line "deslop-install fails -> 1"'

echo "fail -> $fails"
[ "$fails" -eq 0 ]
