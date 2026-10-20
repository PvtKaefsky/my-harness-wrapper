#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/codex-common.sh"
codex_require_tools
codex_validate_path
python3 -I "$CODEX_WRAPPER_ROOT/scripts/pack-codex.py" verify
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
  --arg checkout "$CODEX_WRAPPER_ROOT" --arg pack "$(cat -- "$CODEX_WRAPPER_ROOT/config/codex/pack.sha256")" \
  '.source_commit == $commit and .source_sha256 == $digest and .version == $version and .source_checkout == $checkout and .pack_sha256 == $pack' \
  "$manifest" >/dev/null || { codex_fail 'source revision or adapter files changed; rerun env/setup-codex.sh'; exit 1; }
cmp -s -- "$CODEX_WRAPPER_ROOT/config/codex/AGENTS.md" "$CODEX_WRAPPER_RELEASE/AGENTS.md" || {
  codex_fail 'deployed instructions differ from the source payload'; exit 1;
}
printf 'PASS Codex payload, manifest, source revision, and adapter checksum\n'
if jq -e '.source_dirty' "$manifest" >/dev/null; then
  printf 'NOTE installation included uncommitted source; the commit alone does not reproduce it\n'
fi
printf 'SOURCE_AND_DELIVERY=VERIFIED\n'
printf 'WORKFLOW_INSTRUCTION_READ=REQUIRES_AGENT_TASK_EVIDENCE\n'
printf 'INDEPENDENT_NATIVE_REVIEW=REQUIRES_PROVIDER_INVOCATION\n'
printf 'AUTOMATIC_HOOKS=UNAVAILABLE_NOT_REGISTERED\n'
printf 'MCP_AND_CONNECTED_TOOLS=REQUIRES_CURRENT_PROVIDER_INVENTORY\n'
printf 'PROVIDER_NATIVE_SKILL_DISCOVERY=NOT_REGISTERED_BY_THIS_PACK\n'
printf 'UNVERIFIED fresh-task instruction consumption and provider execution\n'
printf 'PASS delivery verification; runtime integrations are not certified\n'
