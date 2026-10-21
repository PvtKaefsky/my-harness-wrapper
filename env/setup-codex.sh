#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
case "${HARNESS_ENABLE_NATIVE_SKILLS-0}" in
  0|1) ;;
  *) printf 'FAIL NATIVE_SKILL_OPT_IN_INVALID\n' >&2; exit 1 ;;
esac
HARNESS_ENABLE_NATIVE_SKILLS=0 bash "$root/scripts/test-codex.sh"
HARNESS_ENABLE_NATIVE_SKILLS=0 bash "$root/scripts/test-codex-git-context.sh"
HARNESS_ENABLE_NATIVE_SKILLS=0 bash "$root/scripts/test-codex-identity.sh"
HARNESS_ENABLE_NATIVE_SKILLS=0 bash "$root/scripts/test-codex-attribution.sh"
HARNESS_ENABLE_NATIVE_SKILLS=0 bash "$root/scripts/test-cloud-pack.sh"
bash "$root/scripts/bootstrap-codex.sh"
bash "$root/scripts/session-check-codex.sh"
if [ "${HARNESS_ENABLE_NATIVE_SKILLS-0}" = 1 ]; then
  python3 -I "$root/scripts/provision-native-skills.py" install
fi
