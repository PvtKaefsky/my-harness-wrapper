#!/usr/bin/env bash

CODEX_WRAPPER_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
CODEX_WRAPPER_STATE=${HARNESS_STATE_DIR-/workspace/.harness-wrapper}
CODEX_WRAPPER_OWNER=my-harness-wrapper/codex/v1

codex_clear_git_context() {
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_QUARANTINE_PATH GIT_GRAFT_FILE \
    GIT_SHALLOW_FILE GIT_NAMESPACE GIT_PREFIX GIT_INTERNAL_SUPER_PREFIX \
    GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_CONFIG_SYSTEM GIT_TEMPLATE_DIR
}

codex_clear_git_context

codex_fail() {
  printf 'FAIL %s\n' "$*" >&2
  return 1
}

codex_require_tools() {
  local tool
  for tool in git jq sha256sum mktemp realpath flock cmp; do
    command -v "$tool" >/dev/null || { codex_fail "dependency: $tool is unavailable"; return 1; }
  done
}

codex_validate_path() {
  case "$CODEX_WRAPPER_STATE" in
    /*) ;;
    *) codex_fail 'HARNESS_STATE_DIR must be an absolute path'; return 1 ;;
  esac
  [ "$CODEX_WRAPPER_STATE" != / ] || { codex_fail 'HARNESS_STATE_DIR cannot be /'; return 1; }
  [ "$(realpath -m -- "$CODEX_WRAPPER_STATE")" = "$CODEX_WRAPPER_STATE" ] || {
    codex_fail 'HARNESS_STATE_DIR must be canonical and contain no symlinks'; return 1;
  }
  case "$CODEX_WRAPPER_STATE/" in
    "$CODEX_WRAPPER_ROOT/"*) codex_fail 'state must be outside the source checkout'; return 1 ;;
  esac
}

codex_validate_state() {
  [ -d "$CODEX_WRAPPER_STATE" ] && [ ! -L "$CODEX_WRAPPER_STATE" ] || {
    codex_fail 'state directory is absent or is a symlink; run env/setup-codex.sh'; return 1;
  }
  [ -f "$CODEX_WRAPPER_STATE/.owner" ] && [ ! -L "$CODEX_WRAPPER_STATE/.owner" ] &&
    [ "$(cat -- "$CODEX_WRAPPER_STATE/.owner")" = "$CODEX_WRAPPER_OWNER" ] || {
      codex_fail 'state directory is not owned by this adapter; preserve it and choose another HARNESS_STATE_DIR'; return 1;
    }
  [ -d "$CODEX_WRAPPER_STATE/releases" ] && [ ! -L "$CODEX_WRAPPER_STATE/releases" ] &&
    [ -f "$CODEX_WRAPPER_STATE/.lock" ] && [ ! -L "$CODEX_WRAPPER_STATE/.lock" ] || {
      codex_fail 'state layout is invalid'; return 1;
    }
}

codex_source_digest() {
  (
    cd -- "$CODEX_WRAPPER_ROOT" || exit
    sha256sum -- config/codex/AGENTS.md config/codex/version env/setup-codex.sh \
      scripts/codex-common.sh scripts/bootstrap-codex.sh scripts/verify-codex.sh \
      scripts/session-check-codex.sh scripts/check-codex-attribution.sh \
      scripts/check-codex-identity.sh scripts/commit-codex.sh | sha256sum | cut -d ' ' -f 1
  )
}

codex_current_release() {
  local target
  [ -L "$CODEX_WRAPPER_STATE/current" ] || { codex_fail 'current release is not a symlink'; return 1; }
  target=$(readlink -- "$CODEX_WRAPPER_STATE/current") || return
  [[ "$target" =~ ^releases/release\.[a-zA-Z0-9]+$ ]] || {
    codex_fail 'current release points outside the managed release layout'; return 1;
  }
  CODEX_WRAPPER_RELEASE="$CODEX_WRAPPER_STATE/$target"
  [ -d "$CODEX_WRAPPER_RELEASE" ] && [ ! -L "$CODEX_WRAPPER_RELEASE" ] || {
    codex_fail 'current release is absent or is a symlink'; return 1;
  }
}

codex_validate_release() {
  local manifest="$CODEX_WRAPPER_RELEASE/manifest.json" payload="$CODEX_WRAPPER_RELEASE/AGENTS.md" expected
  [ -f "$manifest" ] && [ ! -L "$manifest" ] && [ -f "$payload" ] && [ ! -L "$payload" ] || {
    codex_fail 'release payload or manifest is absent or is a symlink'; return 1;
  }
  jq -e -s '
    length == 1 and (.[0] |
      type == "object" and .schema_version == 1 and .adapter == "codex" and
      (.version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
      (.source_commit | type == "string" and test("^[0-9a-f]{40,64}$")) and
      (.source_dirty | type == "boolean") and
      (.source_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
      (.payload_sha256 | type == "string" and test("^[0-9a-f]{64}$")))
  ' "$manifest" >/dev/null || { codex_fail 'manifest is malformed'; return 1; }
  expected=$(jq -r '.payload_sha256' "$manifest") || return
  [ "$(sha256sum < "$payload" | cut -d ' ' -f 1)" = "$expected" ] || {
    codex_fail 'deployed payload differs from its manifest; preserve local edits before reinstalling'; return 1;
  }
}
