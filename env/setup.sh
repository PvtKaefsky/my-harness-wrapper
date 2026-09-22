#!/bin/bash
set -uo pipefail
exec > /home/user/bootstrap.log 2>&1
export BOOTSTRAP_VERSION=0.1.7
echo "BOOTSTRAP_VERSION=$BOOTSTRAP_VERSION"

HARNESS_DIR=/opt/my-harness-wrapper
echo "HARNESS_DIR -> $HARNESS_DIR"
if [ -z "${HARNESS_REPO_URL+set}" ]; then URL_STATE=unset
elif [ -z "$HARNESS_REPO_URL" ]; then URL_STATE="set but empty"
else URL_STATE=set; fi
echo "HARNESS_REPO_URL -> $URL_STATE"
GIT_PATH=$(command -v git || echo none)
echo "command -v git -> $GIT_PATH"
echo "test -e $HARNESS_DIR -> $([ -e "$HARNESS_DIR" ] && echo yes || echo no)"

if [ "$URL_STATE" != set ]; then
  echo "bootstrap -> skipped, HARNESS_REPO_URL $URL_STATE"
  exit 0
fi
if [ "$GIT_PATH" = none ]; then
  echo "bootstrap -> skipped, git absent"
  exit 0
fi

git clone --depth 1 "$HARNESS_REPO_URL" "$HARNESS_DIR"; rc=$?
echo "git clone --depth 1 \$HARNESS_REPO_URL $HARNESS_DIR -> exit=$rc"
if [ "$rc" -ne 0 ]; then
  echo "bootstrap -> skipped, clone exit=$rc"
  exit 0
fi

echo "git -C $HARNESS_DIR log -1 --format='%h %cI' -> $(git -C "$HARNESS_DIR" log -1 --format='%h %cI' 2>&1)"
echo "test -f $HARNESS_DIR/scripts/bootstrap.sh -> $([ -f "$HARNESS_DIR/scripts/bootstrap.sh" ] && echo yes || echo no)"
if [ -f "$HARNESS_DIR/scripts/bootstrap.sh" ]; then
  bash "$HARNESS_DIR/scripts/bootstrap.sh"; echo "bootstrap_exit=$?"
else
  echo "bootstrap -> skipped, $HARNESS_DIR/scripts/bootstrap.sh absent"
fi
exit 0
