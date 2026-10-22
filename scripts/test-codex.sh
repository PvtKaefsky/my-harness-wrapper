#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$root/scripts/codex-common.sh"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p -- "$work/source" "$work/private-home"
export GIT_CONFIG_GLOBAL="$work/private-home/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
cp -R -- "$root/.agents" "$root/config" "$root/scripts" "$root/env" "$root/docs" "$work/source/"
cp -- "$root/AGENTS.md" "$root/README.md" "$work/source/"
git -C "$work/source" init -q
git -C "$work/source" -c user.name=Test -c user.email=test@example.invalid \
  -c commit.gpgsign=false add .
git -C "$work/source" -c user.name=Test -c user.email=test@example.invalid \
  -c commit.gpgsign=false commit -qm 'test: initialize fixture'
export HARNESS_STATE_DIR="$work/state"
passes=0

expect_status() {
  local label=$1 expected=$2 actual output
  shift 2
  output=$(mktemp "$work/output.XXXXXXXXXX")
  if "$@" > "$output" 2>&1; then actual=0; else actual=$?; fi
  mv -- "$output" "$work/output"
  if [ "$actual" -ne "$expected" ]; then
    printf 'FAIL %s: expected exit=%s, actual=%s\n' "$label" "$expected" "$actual" >&2
    cat -- "$work/output" >&2
    exit 1
  fi
  passes=$((passes + 1))
  printf 'PASS %s\n' "$label"
}

bootstrap="$work/source/scripts/bootstrap-codex.sh"
verify="$work/source/scripts/verify-codex.sh"
session="$work/source/scripts/session-check-codex.sh"
guard="$work/source/scripts/check-codex-attribution.sh"

expect_status 'missing installation fails verification' 1 bash "$verify"
expect_status 'initial bootstrap' 0 bash "$bootstrap"
expect_status 'installed payload verifies' 0 bash "$verify"
first=$(readlink -- "$HARNESS_STATE_DIR/current")
expect_status 'repeat bootstrap' 0 bash "$bootstrap"
expect_status 'repeat bootstrap reuses the release' 0 test "$first" = "$(readlink -- "$HARNESS_STATE_DIR/current")"
expect_status 'startup verifies portable delivery and emits catalog' 0 bash "$session"
expect_status 'runtime integration limitations are reported' 0 grep -q '^UNVERIFIED ' "$work/output"

printf '\nlocal edit\n' >> "$HARNESS_STATE_DIR/current/AGENTS.md"
expect_status 'payload tampering fails verification' 1 bash "$verify"
expect_status 'bootstrap preserves modified payload' 1 bash "$bootstrap"
expect_status 'modified payload remains present' 0 grep -q 'local edit' "$HARNESS_STATE_DIR/current/AGENTS.md"
cp -- "$work/source/config/codex/AGENTS.md" "$HARNESS_STATE_DIR/current/AGENTS.md"

cp -- "$HARNESS_STATE_DIR/current/manifest.json" "$work/manifest.json"
printf '{}\n' > "$HARNESS_STATE_DIR/current/manifest.json"
expect_status 'malformed manifest fails verification' 1 bash "$verify"
expect_status 'bootstrap preserves malformed manifest' 1 bash "$bootstrap"
cp -- "$work/manifest.json" "$HARNESS_STATE_DIR/current/manifest.json"

mv -- "$HARNESS_STATE_DIR/current/AGENTS.md" "$work/saved-payload"
expect_status 'missing payload fails verification' 1 bash "$verify"
expect_status 'bootstrap preserves a release with a missing payload' 1 bash "$bootstrap"
ln -s -- "$work/saved-payload" "$HARNESS_STATE_DIR/current/AGENTS.md"
expect_status 'symlinked payload fails verification' 1 bash "$verify"
rm -- "$HARNESS_STATE_DIR/current/AGENTS.md"
mv -- "$work/saved-payload" "$HARNESS_STATE_DIR/current/AGENTS.md"
cat -- "$work/manifest.json" >> "$HARNESS_STATE_DIR/current/manifest.json"
expect_status 'multiple manifest documents fail verification' 1 bash "$verify"
cp -- "$work/manifest.json" "$HARNESS_STATE_DIR/current/manifest.json"

printf '\nupdated source\n' >> "$work/source/config/codex/AGENTS.md"
expect_status 'changed source is detected' 1 bash "$verify"
expect_status 'bootstrap refreshes changed source' 0 bash "$bootstrap"
expect_status 'updated payload verifies' 0 bash "$verify"
expect_status 'uncommitted installation is identified' 0 grep -q '^NOTE installation included uncommitted' "$work/output"
expect_status 'old release is retained' 0 test -f "$HARNESS_STATE_DIR/$first/AGENTS.md"

git -C "$work/source" -c user.name=Test -c user.email=test@example.invalid \
  -c commit.gpgsign=false commit -qam 'test: change source'
expect_status 'new source commit is detected' 1 bash "$verify"
expect_status 'bootstrap records the new revision' 0 bash "$bootstrap"
expect_status 'new revision verifies' 0 bash "$verify"

mkdir -- "$work/unowned"
printf 'keep\n' > "$work/unowned/personal.txt"
expect_status 'unowned directory is preserved' 1 env HARNESS_STATE_DIR="$work/unowned" bash "$bootstrap"
expect_status 'unowned contents remain present' 0 grep -q '^keep$' "$work/unowned/personal.txt"
expect_status 'relative state path is rejected' 1 env HARNESS_STATE_DIR=relative bash "$bootstrap"
expect_status 'empty state path is rejected' 1 env HARNESS_STATE_DIR= bash "$bootstrap"
expect_status 'root state path is rejected' 1 env HARNESS_STATE_DIR=/ bash "$bootstrap"
expect_status 'checkout state path is rejected' 1 env HARNESS_STATE_DIR="$work/source/state" bash "$bootstrap"
ln -s -- "$HARNESS_STATE_DIR" "$work/state-link"
expect_status 'symlink state path is rejected' 1 env HARNESS_STATE_DIR="$work/state-link" bash "$bootstrap"
expect_status 'state paths containing spaces are supported' 0 env HARNESS_STATE_DIR="$work/state with spaces" bash "$bootstrap"
expect_status 'state paths containing spaces verify' 0 env HARNESS_STATE_DIR="$work/state with spaces" bash "$verify"
expect_status 'state paths containing backslashes are supported' 0 env HARNESS_STATE_DIR="$work/state\\backslash" bash "$bootstrap"
expect_status 'state paths containing backslashes verify' 0 env HARNESS_STATE_DIR="$work/state\\backslash" bash "$verify"

mkdir -- "$work/interrupt-tools"
cat > "$work/interrupt-tools/mv" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
"$HARNESS_REAL_MV" "$@"
if [ "${*: -1}" = "$HARNESS_STATE_DIR/current" ]; then kill -TERM "$PPID"; fi
SHIM
chmod +x -- "$work/interrupt-tools/mv"
expect_status 'interruption immediately after publication is reported' 143 env \
  PATH="$work/interrupt-tools:$PATH" HARNESS_REAL_MV="$(command -v mv)" \
  HARNESS_STATE_DIR="$work/interrupted-state" bash "$bootstrap"
expect_status 'published release survives interruption' 0 env HARNESS_STATE_DIR="$work/interrupted-state" bash "$verify"

current=$(readlink -- "$HARNESS_STATE_DIR/current")
rm -- "$HARNESS_STATE_DIR/current"
ln -s -- "$work" "$HARNESS_STATE_DIR/current"
expect_status 'escaping current symlink is rejected' 1 bash "$verify"
expect_status 'bootstrap preserves escaping symlink' 1 bash "$bootstrap"
rm -- "$HARNESS_STATE_DIR/current"
ln -s -- "$current" "$HARNESS_STATE_DIR/current"

mkdir -- "$work/missing-tools"
ln -s -- "$(command -v dirname)" "$work/missing-tools/dirname"
expect_status 'missing dependencies fail bootstrap' 1 env PATH="$work/missing-tools" /bin/bash "$bootstrap"

printf 'A useful change.\n' > "$work/body.md"
expect_status 'clean body passes' 0 bash "$guard" "$work/body.md"
for footer in 'Co-Authored-By: Codex <codex@example.invalid>' \
  'Agent-Session: example' 'Codex-Session: example' \
  '_Generated by [Agent](https://example.invalid)_' \
  'Generated with Codex' 'Generated by OpenAI' \
  'https://example.invalid/code/session_example' 'https://chatgpt.com/codex/tasks/example'; do
  printf 'A useful change.\n\n%s\n' "$footer" > "$work/body.md"
  expect_status "attribution is blocked: $footer" 2 bash "$guard" "$work/body.md"
done
expect_status 'missing body fails instead of passing' 1 bash "$guard" "$work/absent.md"
expect_status 'missing body argument fails' 1 bash "$guard"
expect_status 'extra body arguments fail' 1 bash "$guard" "$work/body.md" extra
expect_status 'global Git config is not created' 0 test ! -e "$work/private-home/gitconfig"
printf 'PASS %s Codex adapter checks\n' "$passes"
