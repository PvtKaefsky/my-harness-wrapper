#!/bin/bash
set -uo pipefail

fails=0
echo "id -> $(id -u):$(id -g) HOME=${HOME:-}"

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd); rc=$?
echo "SRC -> exit=$rc value=${SRC:-}"
[ "$rc" -eq 0 ] || fails=$((fails + 1))

CONFIG_DIR=/root/.claude
mkdir -p "$CONFIG_DIR"; rc=$?
echo "mkdir -p $CONFIG_DIR -> exit=$rc"
[ "$rc" -eq 0 ] || fails=$((fails + 1))
echo "test -d $CONFIG_DIR -> $([ -d "$CONFIG_DIR" ] && echo yes || echo no)"

LINK=/home/user/.claude
echo "test -L $LINK -> $([ -L "$LINK" ] && echo yes || echo no)"
echo "test -d $LINK -> $([ -d "$LINK" ] && echo yes || echo no)"
if [ ! -e "$LINK" ] && [ ! -L "$LINK" ]; then
  ln -s "$CONFIG_DIR" "$LINK"; rc=$?
  echo "ln -s $CONFIG_DIR $LINK -> exit=$rc"
  [ "$rc" -eq 0 ] || fails=$((fails + 1))
fi
LINK_REAL=$(readlink -f "$LINK" 2>/dev/null)
CONFIG_REAL=$(readlink -f "$CONFIG_DIR" 2>/dev/null)
echo "readlink -f $LINK -> ${LINK_REAL:-unresolved-link}"
echo "readlink -f $CONFIG_DIR -> ${CONFIG_REAL:-unresolved-config}"
if [ "${LINK_REAL:-unresolved-link}" = "${CONFIG_REAL:-unresolved-config}" ]; then
  echo "$LINK resolves to $CONFIG_DIR -> yes"
else
  echo "$LINK resolves to $CONFIG_DIR -> no"
  fails=$((fails + 1))
fi

SRC_MD="$SRC/config/CLAUDE.md"
echo "test -f $SRC_MD -> $([ -f "$SRC_MD" ] && echo yes || echo no)"
if [ -f "$SRC_MD" ]; then
  cp "$SRC_MD" "$CONFIG_DIR/CLAUDE.md"; rc=$?
  echo "cp $SRC_MD $CONFIG_DIR/CLAUDE.md -> exit=$rc"
  [ "$rc" -eq 0 ] || fails=$((fails + 1))
else
  fails=$((fails + 1))
fi

SRC_SETTINGS="$SRC/config/settings.json"
DST_SETTINGS="$CONFIG_DIR/settings.json"
echo "command -v jq -> $(command -v jq || echo none)"
echo "test -f $SRC_SETTINGS -> $([ -f "$SRC_SETTINGS" ] && echo yes || echo no)"
echo "test -f $DST_SETTINGS -> $([ -f "$DST_SETTINGS" ] && echo yes || echo no)"
if [ -f "$SRC_SETTINGS" ] && [ -f "$DST_SETTINGS" ]; then
  TMP=$(mktemp "$DST_SETTINGS.XXXXXX"); rc=$?
  echo "mktemp $DST_SETTINGS.XXXXXX -> exit=$rc value=${TMP:-}"
  if [ "$rc" -ne 0 ] || [ -z "${TMP:-}" ]; then
    fails=$((fails + 1))
  else
    jq -s '.[0] * .[1]' "$DST_SETTINGS" "$SRC_SETTINGS" > "$TMP"; rc=$?
    echo "jq -s '.[0] * .[1]' $DST_SETTINGS $SRC_SETTINGS -> exit=$rc"
    if [ "$rc" -eq 0 ]; then
      chmod 644 "$TMP"; ch_rc=$?
      echo "chmod 644 $TMP -> exit=$ch_rc"
      if [ "$ch_rc" -ne 0 ]; then
        fails=$((fails + 1))
        rm -f "$TMP"; rm_rc=$?
        echo "rm -f $TMP -> exit=$rm_rc"
        [ "$rm_rc" -eq 0 ] || fails=$((fails + 1))
      else
        mv "$TMP" "$DST_SETTINGS"; mv_rc=$?
        echo "mv $TMP $DST_SETTINGS -> exit=$mv_rc"
        [ "$mv_rc" -eq 0 ] || fails=$((fails + 1))
      fi
    else
      rm -f "$TMP"; rm_rc=$?
      echo "rm -f $TMP -> exit=$rm_rc"
      [ "$rm_rc" -eq 0 ] || fails=$((fails + 1))
      fails=$((fails + 1))
    fi
  fi
elif [ -f "$SRC_SETTINGS" ]; then
  cp "$SRC_SETTINGS" "$DST_SETTINGS"; rc=$?
  echo "cp $SRC_SETTINGS $DST_SETTINGS -> exit=$rc"
  [ "$rc" -eq 0 ] || fails=$((fails + 1))
else
  fails=$((fails + 1))
fi

for kv in "commit.gpgsign=false" "tag.gpgsign=false"; do
  key=${kv%%=*}; val=${kv#*=}
  prior=$(git config --global --get "$key" 2>/dev/null)
  echo "git config --global --get $key -> ${prior:-unset}"
  git config --global "$key" "$val"; rc=$?
  echo "git config --global $key $val -> exit=$rc"
  [ "$rc" -eq 0 ] || fails=$((fails + 1))
done

PLUGINS="$SRC/config/plugins.tsv"
echo "command -v claude -> $(command -v claude || echo none)"
echo "test -f $PLUGINS -> $([ -f "$PLUGINS" ] && echo yes || echo no)"
if [ -f "$PLUGINS" ]; then
  while IFS=$'\t' read -r -u 3 mp_source plugin_id _rest || [ -n "${mp_source:-}" ]; do
    case "${mp_source:-}" in ''|'#'*) continue ;; esac
    echo "plugins.tsv marketplace_source=$mp_source plugin_id -> ${plugin_id:-empty}"
    [ -n "${plugin_id:-}" ] || { fails=$((fails + 1)); continue; }
    claude plugin marketplace add "$mp_source"; rc=$?
    echo "claude plugin marketplace add $mp_source -> exit=$rc"
    [ "$rc" -eq 0 ] || fails=$((fails + 1))
    claude plugin install "$plugin_id" --scope user --yes; rc=$?
    echo "claude plugin install $plugin_id --scope user --yes -> exit=$rc"
    [ "$rc" -eq 0 ] || fails=$((fails + 1))
  done 3< "$PLUGINS"
else
  fails=$((fails + 1))
fi

COMMIT=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null); rc=$?
echo "git -C $SRC rev-parse --short HEAD -> exit=$rc value=${COMMIT:-}"
[ "$rc" -eq 0 ] || fails=$((fails + 1))
GIT_EMAIL=$(git -C "$SRC" config --get user.email 2>/dev/null); rc=$?
echo "git -C $SRC config --get user.email -> exit=$rc value=${GIT_EMAIL:-}"
[ "$rc" -le 1 ] || fails=$((fails + 1))
INSTALLED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ); rc=$?
echo "date -u +%Y-%m-%dT%H:%M:%SZ -> exit=$rc value=${INSTALLED_AT:-}"
[ "$rc" -eq 0 ] || fails=$((fails + 1))
MANIFEST="$CONFIG_DIR/.my-harness-wrapper.manifest.json"
MTMP=$(mktemp "$MANIFEST.XXXXXX"); rc=$?
echo "mktemp $MANIFEST.XXXXXX -> exit=$rc value=${MTMP:-}"
if [ "$rc" -ne 0 ] || [ -z "${MTMP:-}" ]; then
  fails=$((fails + 1))
else
  jq -n \
    --arg bootstrap_version "${BOOTSTRAP_VERSION:-}" \
    --arg commit "${COMMIT:-}" \
    --arg config_dir "$CONFIG_DIR" \
    --arg git_user_email "${GIT_EMAIL:-}" \
    --arg installed_at "${INSTALLED_AT:-}" \
    '{bootstrap_version: $bootstrap_version, commit: $commit, config_dir: $config_dir, git_user_email: $git_user_email, installed_at: $installed_at}' \
    > "$MTMP"; rc=$?
  echo "jq -n > $MTMP -> exit=$rc"
  if [ "$rc" -eq 0 ]; then
    chmod 644 "$MTMP"; ch_rc=$?
    echo "chmod 644 $MTMP -> exit=$ch_rc"
    if [ "$ch_rc" -ne 0 ]; then
      fails=$((fails + 1))
      rm -f "$MTMP"; rm_rc=$?
      echo "rm -f $MTMP -> exit=$rm_rc"
      [ "$rm_rc" -eq 0 ] || fails=$((fails + 1))
    else
      mv "$MTMP" "$MANIFEST"; mv_rc=$?
      echo "mv $MTMP $MANIFEST -> exit=$mv_rc"
      [ "$mv_rc" -eq 0 ] || fails=$((fails + 1))
    fi
  else
    rm -f "$MTMP"; rm_rc=$?
    echo "rm -f $MTMP -> exit=$rm_rc"
    [ "$rm_rc" -eq 0 ] || fails=$((fails + 1))
    fails=$((fails + 1))
  fi
fi
echo "test -f $MANIFEST -> $([ -f "$MANIFEST" ] && echo yes || echo no)"

echo "fails -> $fails"
[ "$fails" -le 255 ] || fails=255
exit "$fails"
