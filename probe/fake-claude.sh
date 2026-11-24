#!/bin/bash
set -uo pipefail

STATE=${FAKE_CLAUDE_DIR:?}/plugins.json
ADDED=$FAKE_CLAUDE_DIR/marketplaces
SETTINGS=${HOME:?}/.claude/settings.json
[ -f "$STATE" ] || echo '[]' > "$STATE"
touch "$ADDED"

case "$# ${1:-} ${2:-} ${3:-}" in
  "1 --version  ") echo "0.0.0 (probe fake claude)" ;;
  "3 plugin list --json") cat "$STATE" ;;
  "4 plugin marketplace add") [ -n "$4" ] && echo "$4" >> "$ADDED" ;;
  "6 plugin install "*)
    id=$3 name=${3%%@*} dir=$FAKE_CLAUDE_DIR/plugins/${3%%@*} version=0.0.0
    [ "$4 $5 $6" = "--scope user --yes" ] || exit 1
    case $name in "" | */* | .*) exit 1 ;; esac
    [ "$(grep -c '' "$ADDED")" -gt "$(jq length "$STATE")" ] || exit 1
    mkdir -p "$dir" || exit 1
    if [ -d "${FAKE_CLAUDE_REPO:?}/plugins/$name" ]; then
      cp -a "$FAKE_CLAUDE_REPO/plugins/$name/." "$dir" || exit 1
      version=$(jq -r .version "$dir/.claude-plugin/plugin.json") || exit 1
    fi
    jq --arg id "$id" --arg v "$version" --arg p "$dir" \
      '[.[] | select(.id != $id)] + [{id: $id, version: $v, scope: "user", enabled: true, installPath: $p}]' \
      "$STATE" > "$STATE.new" && mv "$STATE.new" "$STATE" || exit 1
    jq --arg id "$id" '.enabledPlugins[$id] = true' "$SETTINGS" > "$SETTINGS.new" &&
      mv "$SETTINGS.new" "$SETTINGS" ;;
  *) echo "probe fake claude: unsupported arguments: $*" >&2; exit 1 ;;
esac
