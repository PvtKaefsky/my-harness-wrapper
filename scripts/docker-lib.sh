#!/bin/bash

dk() { MSYS_NO_PATHCONV=1 docker "$@"; }

hostpath() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}

dkenv() {
  local keep=("PATH=$PATH") v
  for v in HOME DOCKER_HOST DOCKER_CONTEXT DOCKER_CONFIG DOCKER_CERT_PATH DOCKER_TLS_VERIFY \
    SYSTEMROOT USERPROFILE APPDATA LOCALAPPDATA PROGRAMFILES ProgramData TEMP TMP; do
    [ -n "${!v:-}" ] && keep+=("$v=${!v}")
  done
  env -i "${keep[@]}" MSYS_NO_PATHCONV=1 "$@"
}
