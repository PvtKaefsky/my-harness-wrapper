#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/codex-common.sh"
codex_require_tools
codex_validate_path
codex_validate_state
exec 9< "$CODEX_WRAPPER_STATE/.lock"
flock -w 10 -s 9 || { codex_fail 'verification lock timed out'; exit 1; }
codex_current_release
codex_validate_release

manifest="$CODEX_WRAPPER_RELEASE/manifest.json"
commit=$(git -C "$CODEX_WRAPPER_ROOT" rev-parse --verify 'HEAD^{commit}')
digest=$(codex_source_digest)
version=$(cat -- "$CODEX_WRAPPER_ROOT/config/codex/version")
jq -e --arg commit "$commit" --arg digest "$digest" --arg version "$version" \
  '.source_commit == $commit and .source_sha256 == $digest and .version == $version' \
  "$manifest" >/dev/null || { codex_fail 'source revision or adapter files changed; rerun env/setup-codex.sh'; exit 1; }
cmp -s -- "$CODEX_WRAPPER_ROOT/config/codex/AGENTS.md" "$CODEX_WRAPPER_RELEASE/AGENTS.md" || {
  codex_fail 'deployed instructions differ from the source payload'; exit 1;
}
printf 'PASS Codex payload, manifest, source revision, and adapter checksum\n'
if jq -e '.source_dirty' "$manifest" >/dev/null; then
  printf 'NOTE installation included uncommitted source; the commit alone does not reproduce it\n'
fi
printf 'UNVERIFIED managed-task instruction loading, ECC reviewers, and automatic hooks\n'
printf 'PASS delivery verification; runtime integrations are not certified\n'
