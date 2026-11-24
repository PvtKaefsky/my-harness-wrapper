#!/bin/bash
set -uo pipefail

RUNNER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ab-probe.sh"
fails=0

echo "test -f $RUNNER -> $([ -f "$RUNNER" ] && echo yes || echo no)"
for tool in git jq; do
  echo "command -v $tool -> $(command -v "$tool" || echo none)"
done
if [ ! -f "$RUNNER" ] || ! command -v git >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "fail -> not run"
  exit 1
fi

WORK=$(mktemp -d) || { echo "mktemp -d -> exit=$?, not run"; exit 1; }
trap 'rm -rf -- "$WORK"' EXIT
BIN="$WORK/bin"
mkdir -p "$BIN/count"

cat > "$BIN/docker" <<'EOF'
#!/bin/bash
here=${0%/*}
mode=$(cat "$here/mode" 2>/dev/null)
case $1 in
  info)
    if [ "$mode" = nodaemon ]; then echo "Cannot connect to the Docker daemon" >&2; exit 1; fi
    echo 0.0.0-fake ;;
  build)
    if [ "$mode" = buildfail ]; then echo "build step failed" >&2; exit 1; fi
    echo sha256:fake ;;
  image | ps | rm) ;;
  compose)
    shift
    while [ $# -gt 0 ]; do case $1 in -f | -p) shift 2 ;; *) break ;; esac; done
    case $1 in
      version) echo 0.0.0-fake ;;
      config)
        env >> "$here/compose-env"
        jq -n --arg i "$PROBE_IMAGE" --arg t "$PROBE_TREE" --arg r "$PROBE_RESULTS" \
          '{name: "fake", services: {checks: {image: $i, network_mode: "none", volumes: [
            {type: "bind", source: $t, target: "/work", read_only: true},
            {type: "bind", source: $r, target: "/results"}]}}}' | jq "$(cat "$here/config.jq")" ;;
      run)
        key=$(printf '%s' "$PROBE_TREE" | tr -c 'A-Za-z0-9' _)
        n=$(( $(cat "$here/count/$key" 2>/dev/null || echo 0) + 1 ))
        echo "$n" > "$here/count/$key"
        [ "$mode" = absent ] && exit 0
        (cd "$PROBE_TREE" && FAKE_RUN=$n PROBE_OUT=$PROBE_RESULTS bash probe/checks.sh)
        out=$PROBE_RESULTS/checks.jsonl
        case $mode in
          malformed) echo 'not json' >> "$out" ;;
          skip) echo '{"id":"z","status":"skip","seconds":0}' >> "$out" ;;
          seconds) echo '{"id":"z","status":"pass","seconds":"1"}' >> "$out" ;;
        esac ;;
      *) exit 1 ;;
    esac ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$BIN/docker"

fake() {
  printf '%s\n' "$1" > "$BIN/mode"
  printf '%s\n' "${2:-.}" > "$BIN/config.jq"
}
fake ''

printf '[core]\n\tautocrlf = true\n' > "$WORK/gitconfig"
export GIT_CONFIG_GLOBAL="$WORK/gitconfig" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export AB_PROBE_CANARY=host-value

R="$WORK/fixture"
git init -q -b main "$R" && git -C "$R" config core.safecrlf false || { echo "git init -> failed, not run"; exit 1; }
cd "$R" || exit 1
printf 'ok\n' > a.txt
printf 'g\n' > g.txt
git add a.txt g.txt && git commit -q -m baseline

add_probe() {
  mkdir -p probe
  printf 'FROM debian:bookworm-slim\n' > probe/Dockerfile
  cat > probe/compose.yaml <<'EOF'
services:
  checks:
    image: ${PROBE_IMAGE}
    network_mode: none
    working_dir: /work
    command: ["bash", "probe/checks.sh"]
    volumes:
      - type: bind
        source: ${PROBE_TREE}
        target: /work
        read_only: true
      - type: bind
        source: ${PROBE_RESULTS}
        target: /results
EOF
  printf '%s\r\n' '#!/bin/bash' \
    'out=${PROBE_OUT:-/results}/checks.jsonl' \
    ': > "$out"' \
    'check() {' \
    '  local id=$1 status=fail' \
    '  shift' \
    '  if "$@"; then status=pass; fi' \
    '  printf '"'"'{"id":"%s","status":"%s","seconds":0}\n'"'"' "$id" "$status" >> "$out"' \
    '}' \
    'check a grep -q "^ok$" a.txt' \
    'check b test -f b.txt' \
    'if [ -f c.txt ]; then check c true; fi' \
    'check d false' \
    'check f test $(( ${FAKE_RUN:-1} % 2 )) -eq 1' \
    'if [ -f g.txt ]; then check g true; fi' \
    'if [ -f h.txt ]; then check h false; fi' > probe/checks.sh
  git add probe
}

git checkout -q -b regression main && add_probe
printf 'broken\n' > a.txt && git rm -q g.txt && git add a.txt && git commit -q -m regression
git checkout -q -b shown main && add_probe
printf 'b\n' > b.txt && printf 'c\n' > c.txt && printf 'h\n' > h.txt && git add b.txt c.txt h.txt && git commit -q -m shown
git checkout -q -b symlink shown
link=$(printf '%s' "$WORK/gitconfig" | git hash-object -w --stdin)
git update-index --add --cacheinfo "120000,$link,probe/.env" && git commit -q -m symlink
git checkout -q shown

cr=$'\r'
crlf_tree=$(tr -cd "$cr" < probe/checks.sh | wc -c)
crlf_blob=$(git cat-file -p shown:probe/checks.sh | tr -cd "$cr" | wc -c)
git clone -q "$R" "$WORK/plain" && git -C "$WORK/plain" checkout -q shown
crlf_plain=$(tr -cd "$cr" < "$WORK/plain/probe/checks.sh" | wc -c)
verdict=pass
if [ "$crlf_tree" -eq 0 ] || [ "$crlf_blob" -ne 0 ] || [ "$crlf_plain" -eq 0 ]; then verdict=FAIL; fails=$((fails + 1)); fi
echo "fixture probe/checks.sh CRLF lines -> working tree=$crlf_tree, blob=$crlf_blob, plain clone=$crlf_plain, expected >0, 0, >0, $verdict"
cd "$WORK" || exit 1

expect() {
  local label=$1 want=$2 out got verdict=pass line
  shift 2
  local args=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do args+=("$1"); shift; done
  shift
  out=$(PATH="$BIN:$PATH" bash "$RUNNER" "${args[@]}" 2>&1); got=$?
  [ "$got" -eq "$want" ] || verdict=FAIL
  for line in "$@"; do
    if ! printf '%s\n' "$out" | grep -q -x -F -- "$line"; then verdict=FAIL; label="$label, line [$line]"; fi
  done
  if [ "$verdict" = FAIL ]; then
    fails=$((fails + 1))
    printf '%s\n' "$out" | sed 's/^/  | /'
  fi
  echo "$label -> expected exit=$want, actual exit=$got, $verdict"
}

expect 'a check passing on the baseline fails or is absent on the candidate' 1 "$R" main regression -- \
  'check a baseline -> pass, candidate -> fail, regression' \
  'check g baseline -> pass, candidate -> absent, regression' \
  'verdict -> blocked, regressions=2 shown=0 failing=2'

expect 'a check the change adds, failing or absent on the baseline' 0 "$R" main shown -- \
  'check b baseline -> fail, candidate -> pass, shown' \
  'check c baseline -> absent, candidate -> pass, shown' \
  'check a baseline -> pass, candidate -> pass, ok' \
  'verdict -> no regression, regressions=0 shown=2 failing=2'

expect 'a check failing on both trees, and one absent on the baseline and failing' 0 "$R" main shown -- \
  'check d baseline -> fail, candidate -> fail, failing on both' \
  'check h baseline -> absent, candidate -> fail, not passing'

expect 'the CRLF-checked-out probe/checks.sh runs' 0 "$R" main shown -- \
  'run baseline 1 -> exit=0, checks=5' \
  'run candidate 1 -> exit=0, checks=7'

expect '--runs 2, a check passing once and failing once on each tree' 1 "$R" main shown --runs 2 -- \
  'check f baseline -> pass, candidate -> fail, regression' \
  'verdict -> blocked, regressions=1 shown=2 failing=2'

: > "$BIN/compose-env"
expect 'a host environment variable' 0 "$R" main shown --
verdict=pass
grep -q '^PROBE_TREE=' "$BIN/compose-env" || verdict=FAIL
grep -q '^AB_PROBE_CANARY=' "$BIN/compose-env" && verdict=FAIL
[ "$verdict" = FAIL ] && fails=$((fails + 1))
echo "AB_PROBE_CANARY in docker compose's environment -> expected absent beside PROBE_TREE, actual $(grep -q '^AB_PROBE_CANARY=' "$BIN/compose-env" && echo present || echo absent), $verdict"

fake nodaemon
expect 'no Docker daemon' 2 "$R" main shown -- \
  'verdict -> not run'

fake buildfail
expect 'a failed image build' 2 "$R" main shown -- \
  'docker build probe/Dockerfile -> failed, probe not run' \
  'verdict -> not run'

for patch in \
  '.services.checks.network_mode = "bridge"' \
  '.services.checks.environment = {"X": "1"}' \
  '.services.checks.env_file = ["x.env"]' \
  '.services.checks.privileged = true' \
  '.services.checks.image = "alpine"' \
  '.services.checks.volumes += [{"type": "bind", "source": "/", "target": "/host"}]' \
  '.services.checks.volumes[0].read_only = false' \
  '.services.checks.volumes[1].target = "/out"' \
  '.services.helper = {"image": "alpine"}' \
  '.secrets = {"k": {"file": "/k"}}'; do
  fake '' "$patch"
  expect "a compose config with $patch" 2 "$R" main shown -- \
    'probe/compose.yaml -> breaks the probe contract, probe not run'
done

fake absent
expect 'a run that writes no checks.jsonl' 2 "$R" main shown -- \
  'run baseline 1 -> exit=0, checks.jsonl absent, probe not run'

for mode in malformed skip seconds; do
  fake "$mode"
  expect "a checks.jsonl line, $mode" 2 "$R" main shown -- \
    'run baseline 1 -> exit=0, checks.jsonl unreadable, probe not run'
done

fake ''
git clone -q "$R" "$WORK/links" && git -C "$WORK/links" checkout -q symlink
if [ -L "$WORK/links/probe/.env" ]; then
  expect 'a candidate whose probe/.env is a symlink' 2 "$R" main symlink -- \
    'candidate probe/ -> holds a symlink, probe not run'
else
  echo "a candidate whose probe/.env is a symlink -> not run, this checkout creates no symlinks"
fi

expect 'a candidate without probe/' 2 "$R" shown main -- \
  'candidate probe/Dockerfile -> absent, probe not run'

echo "fail -> $fails"
[ "$fails" -eq 0 ]
