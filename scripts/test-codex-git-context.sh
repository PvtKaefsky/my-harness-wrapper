#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$root/scripts/codex-common.sh"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export GIT_CONFIG_GLOBAL="$work/global-config"
export GIT_CONFIG_NOSYSTEM=1
mkdir -- "$work/victim"
git -C "$work/victim" init -q
printf 'preserve committed file\n' > "$work/victim/committed.txt"
git -C "$work/victim" add .
git -C "$work/victim" -c user.name=Test -c user.email=test@example.invalid \
  -c commit.gpgsign=false commit -qm 'test: preserve caller repository'
printf 'preserve staged file\n' > "$work/victim/staged.txt"
git -C "$work/victim" add staged.txt
printf 'preserve working file\n' > "$work/victim/local.txt"
head_before=$(git -C "$work/victim" rev-parse HEAD)
index_before=$(sha256sum < "$work/victim/.git/index")
files_before=$(cd -- "$work/victim" && sha256sum -- committed.txt staged.txt local.txt)
objects_before=$(find "$work/victim/.git/objects" -type f | sort)

if ! env GIT_DIR="$work/victim/.git" GIT_WORK_TREE="$work/victim" \
  GIT_COMMON_DIR="$work/victim/.git" GIT_INDEX_FILE="$work/victim/.git/index" \
  GIT_OBJECT_DIRECTORY="$work/victim/.git/objects" \
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.worktree GIT_CONFIG_VALUE_0="$work/victim" \
  bash "$root/scripts/test-codex.sh" > "$work/output" 2>&1; then
  cat -- "$work/output" >&2
  exit 1
fi
[ "$head_before" = "$(git -C "$work/victim" rev-parse HEAD)" ] || { codex_fail 'caller HEAD changed'; exit 1; }
[ "$index_before" = "$(sha256sum < "$work/victim/.git/index")" ] || { codex_fail 'caller index changed'; exit 1; }
[ "$files_before" = "$(cd -- "$work/victim" && sha256sum -- committed.txt staged.txt local.txt)" ] || {
  codex_fail 'caller working files changed'; exit 1;
}
[ "$objects_before" = "$(find "$work/victim/.git/objects" -type f | sort)" ] || { codex_fail 'caller object files changed'; exit 1; }

env HARNESS_STATE_DIR="$work/source-state" bash "$root/scripts/bootstrap-codex.sh" > "$work/bootstrap-output"
expected=$(git -C "$root" rev-parse HEAD)
recorded=$(env GIT_DIR="$work/victim/.git" GIT_WORK_TREE="$work/victim" \
  GIT_INDEX_FILE="$work/victim/.git/index" HARNESS_STATE_DIR="$work/source-state" \
  bash "$root/scripts/bootstrap-codex.sh" && jq -r '.source_commit' "$work/source-state/current/manifest.json")
[ "${recorded##*$'\n'}" = "$expected" ] || { codex_fail 'bootstrap selected the caller repository'; exit 1; }
env GIT_DIR="$work/victim/.git" GIT_WORK_TREE="$work/victim" \
  GIT_INDEX_FILE="$work/victim/.git/index" HARNESS_STATE_DIR="$work/source-state" \
  bash "$root/scripts/verify-codex.sh" > "$work/verify-output"
printf 'PASS inherited Git selectors preserve caller HEAD, index, objects, and working files\n'
printf 'PASS bootstrap and verification select their source checkout\n'
