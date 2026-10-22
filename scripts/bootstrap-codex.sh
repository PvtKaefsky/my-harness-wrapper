#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/codex-common.sh"
codex_require_tools
codex_validate_path
python3 -I "$CODEX_WRAPPER_ROOT/scripts/pack-codex.py" verify
umask 077

version=$(cat -- "$CODEX_WRAPPER_ROOT/config/codex/version")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { codex_fail 'adapter version is invalid'; exit 1; }
commit=$(git -C "$CODEX_WRAPPER_ROOT" rev-parse --verify 'HEAD^{commit}')
digest=$(codex_source_digest)
dirty=false
if [ -n "$(git --no-optional-locks -C "$CODEX_WRAPPER_ROOT" status --porcelain --untracked-files=normal)" ]; then dirty=true; fi

if [ ! -e "$CODEX_WRAPPER_STATE" ] && [ ! -L "$CODEX_WRAPPER_STATE" ]; then
  mkdir -p -- "$(dirname -- "$CODEX_WRAPPER_STATE")"
  mkdir -m 700 -- "$CODEX_WRAPPER_STATE"
  printf '%s\n' "$CODEX_WRAPPER_OWNER" > "$CODEX_WRAPPER_STATE/.owner"
  mkdir -m 700 -- "$CODEX_WRAPPER_STATE/releases"
  : > "$CODEX_WRAPPER_STATE/.lock"
fi
codex_validate_state
exec 9<> "$CODEX_WRAPPER_STATE/.lock"
flock -w 10 -x 9 || { codex_fail 'setup lock timed out'; exit 1; }

if [ -e "$CODEX_WRAPPER_STATE/current" ] || [ -L "$CODEX_WRAPPER_STATE/current" ]; then
  codex_current_release
  codex_validate_release
  if jq -e --arg commit "$commit" --arg digest "$digest" --argjson dirty "$dirty" --arg checkout "$CODEX_WRAPPER_ROOT" \
    '.source_commit == $commit and .source_sha256 == $digest and .source_dirty == $dirty and .source_checkout == $checkout' \
    "$CODEX_WRAPPER_RELEASE/manifest.json" >/dev/null; then
    printf 'PASS Codex adapter already matches this checkout\n'
    exit 0
  fi
fi

release=$(mktemp -d "$CODEX_WRAPPER_STATE/releases/release.XXXXXXXXXX")
link=""
cleanup() {
  [ -z "$link" ] || rm -f -- "$link"
  if [ -n "$release" ] &&
    [ "$(readlink -- "$CODEX_WRAPPER_STATE/current" 2>/dev/null || true)" != "releases/${release##*/}" ]; then
    rm -rf -- "$release"
  fi
}
trap cleanup EXIT
cp -- "$CODEX_WRAPPER_ROOT/config/codex/AGENTS.md" "$release/AGENTS.md"
payload_digest=$(sha256sum < "$release/AGENTS.md" | cut -d ' ' -f 1)
jq -n --arg version "$version" --arg commit "$commit" --arg digest "$digest" \
  --arg payload "$payload_digest" --argjson dirty "$dirty" \
  --arg checkout "$CODEX_WRAPPER_ROOT" --arg pack "$(cat -- "$CODEX_WRAPPER_ROOT/config/codex/pack.sha256")" \
  '{schema_version: 2, adapter: "codex", version: $version, source_commit: $commit,
    source_checkout: $checkout, pack_sha256: $pack,
    source_dirty: $dirty, source_sha256: $digest, payload_sha256: $payload}' > "$release/manifest.json"
link="$release/current-link"
ln -s -- "releases/${release##*/}" "$link"
mv -Tf -- "$link" "$CODEX_WRAPPER_STATE/current"
link=""
release=""
printf 'PASS Codex adapter installed at %s/current\n' "$CODEX_WRAPPER_STATE"
