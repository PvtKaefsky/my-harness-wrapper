#!/bin/bash
set -uo pipefail

OUT=/results/checks.jsonl
TREE=/tmp/probe-tree
LOGS=/tmp/probe-logs
SRC=/tmp/probe-install-src
: > "$OUT"
mkdir -p "$TREE" "$LOGS"
cp -a /work/. "$TREE"

record() {
  jq -n -c --arg id "$1" --arg status "$2" --argjson seconds "$3" \
    '{id: $id, status: $status, seconds: $seconds}' >> "$OUT"
  echo "check $1 -> $2 in ${3}s"
}

elapsed() {
  awk -v a="$1" -v b="$EPOCHREALTIME" 'BEGIN { printf "%.3f", b - a }'
}

last_line() {
  tail -n 1 "$1" | tr -d '\r'
}

for path in "$TREE"/scripts/test-*.sh; do
  [ -f "$path" ] || continue
  name=${path##*/}
  log="$LOGS/$name.log"
  start=$EPOCHREALTIME
  (cd "$TREE" && bash "scripts/$name") > "$log" 2>&1 < /dev/null
  code=$?
  status=fail
  [ "$code" -eq 0 ] && [ "$(last_line "$log")" = "fail -> 0" ] && status=pass
  echo "bash scripts/$name -> exit=$code, last line [$(last_line "$log")]"
  [ "$status" = pass ] || tail -n 20 "$log"
  record "$name" "$status" "$(elapsed "$start")"
done

start=$EPOCHREALTIME
status=fail
sha=$(git -C "$TREE" rev-parse --verify HEAD 2>&1); code=$?
echo "git -C $TREE rev-parse --verify HEAD -> exit=$code value=$sha"
if [ "$code" -eq 0 ] && git -c init.defaultBranch=main clone -q --no-checkout "$TREE" "$SRC" &&
  git -C "$SRC" checkout -q -B main "$sha"; then
  mkdir -p /home/user
  export GIT_AUTHOR_NAME=Probe GIT_AUTHOR_EMAIL=probe@example.com
  export GIT_COMMITTER_NAME=Probe GIT_COMMITTER_EMAIL=probe@example.com HARNESS_ASSIGNEE=probe
  HARNESS_REPO_URL=$SRC bash "$SRC/env/setup.sh" < /dev/null
  cat /home/user/bootstrap.log
  bash /opt/my-harness-wrapper/scripts/verify.sh > "$LOGS/verify.log" 2>&1 < /dev/null
  code=$?
  cat "$LOGS/verify.log"
  echo "bash /opt/my-harness-wrapper/scripts/verify.sh -> exit=$code, last line [$(last_line "$LOGS/verify.log")]"
  grep -q -x 'bootstrap_exit=0' /home/user/bootstrap.log && [ "$code" -eq 0 ] &&
    [ "$(last_line "$LOGS/verify.log")" = "fail -> 0" ] && status=pass
fi
record install "$status" "$(elapsed "$start")"
