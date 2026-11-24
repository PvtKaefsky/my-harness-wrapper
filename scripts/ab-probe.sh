#!/bin/bash
set -uo pipefail

usage() {
  echo "usage: ab-probe.sh <repo> <baseline-ref> <candidate-ref> [--runs N]" >&2
  exit 2
}

[ $# -eq 3 ] || [ $# -eq 5 ] || usage
REPO=$1 BASE_REF=$2 CAND_REF=$3 RUNS=1
if [ $# -eq 5 ]; then
  [ "$4" = --runs ] || usage
  RUNS=$5
fi
case $RUNS in '' | *[!0-9]* | 0*) usage ;; esac
case $REPO in -*) usage ;; esac
case $BASE_REF in -*) usage ;; esac
case $CAND_REF in -*) usage ;; esac

notrun() {
  echo "$1"
  echo "verdict -> not run"
  exit 2
}

dk() { MSYS_NO_PATHCONV=1 docker "$@"; }

hostpath() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}

for tool in git jq docker; do
  command -v "$tool" >/dev/null 2>&1 || notrun "command -v $tool -> none, probe not run"
done
server=$(dk info --format '{{.ServerVersion}}' 2>&1) || notrun "docker info -> exit=$?, probe not run: $server"
echo "docker info -> server $server"
compose=$(dk compose version --short 2>&1) || notrun "docker compose version -> exit=$?, probe not run: $compose"
echo "docker compose version -> $compose"

SCRATCH=$(mktemp -d) || notrun "mktemp -d -> exit=$?, probe not run"
TAG="ab-probe:$$-$RANDOM"
PROJECT="abprobe$$"
cleanup() {
  local ids
  ids=$(dk ps -aq --filter "label=com.docker.compose.project=$PROJECT" 2>/dev/null | tr -d '\r')
  if [ -n "$ids" ]; then dk rm -f $ids >/dev/null 2>&1; fi
  dk image rm -f "$TAG" >/dev/null 2>&1
  rm -rf -- "$SCRATCH"
}

dc() {
  local keep=("PATH=$PATH") v
  for v in HOME DOCKER_HOST DOCKER_CONTEXT DOCKER_CONFIG DOCKER_CERT_PATH DOCKER_TLS_VERIFY \
    SYSTEMROOT USERPROFILE APPDATA LOCALAPPDATA PROGRAMFILES ProgramData TEMP TMP; do
    [ -n "${!v:-}" ] && keep+=("$v=${!v}")
  done
  env -i "${keep[@]}" MSYS_NO_PATHCONV=1 PROBE_IMAGE="$TAG" PROBE_TREE="$1" PROBE_RESULTS="$2" \
    docker compose -f "$1/probe/compose.yaml" -p "$PROJECT" "${@:3}"
}
trap cleanup EXIT

clone() {
  local name=$1 ref=$2 sha
  sha=$(git -C "$REPO" rev-parse --verify --quiet "$ref^{commit}") || notrun "git rev-parse $ref -> not a commit, probe not run"
  git clone -q --no-checkout -c core.autocrlf=false "$REPO" "$SCRATCH/$name" 2>&1 || notrun "git clone $REPO -> exit=$?, probe not run"
  git -C "$SCRATCH/$name" -c core.autocrlf=false checkout -q --detach "$sha" 2>&1 || notrun "git checkout $sha -> exit=$?, probe not run"
  echo "$name -> $ref at $sha"
}

clone baseline "$BASE_REF"
clone candidate "$CAND_REF"

for f in Dockerfile compose.yaml checks.sh; do
  [ -f "$SCRATCH/candidate/probe/$f" ] || notrun "candidate probe/$f -> absent, probe not run"
done
if [ -L "$SCRATCH/candidate/probe" ] || find "$SCRATCH/candidate/probe" -type l | grep -q .; then
  notrun "candidate probe/ -> holds a symlink, probe not run"
fi
rm -rf -- "$SCRATCH/baseline/probe"
cp -R "$SCRATCH/candidate/probe" "$SCRATCH/baseline/probe" || notrun "cp candidate probe/ to baseline -> failed, probe not run"

PROBE_DIR=$(hostpath "$SCRATCH/candidate/probe")
if ! dk build -q -t "$TAG" -f "$PROBE_DIR/Dockerfile" "$PROBE_DIR" >"$SCRATCH/build.log" 2>&1; then
  tail -n 20 "$SCRATCH/build.log"
  notrun "docker build probe/Dockerfile -> failed, probe not run"
fi
echo "docker build probe/Dockerfile -> $TAG"

CONFIG_OK='(keys - ["name", "services"]) == []
  and (.services | keys) == ["checks"]
  and (.services.checks | (keys - ["command", "entrypoint", "image", "network_mode", "volumes",
      "working_dir", "user", "read_only", "tmpfs", "mem_limit", "pids_limit", "cpus"]) == []
    and .image == $tag
    and .network_mode == "none"
    and ((.volumes // []) | length) == 2
    and any(.volumes[]; .type == "bind" and .source == $tree and .target == "/work" and .read_only == true)
    and any(.volumes[]; .type == "bind" and .source == $results and .target == "/results"))'

RESULT_OK='type == "object" and (.id | type) == "string" and .id != ""
  and (.status == "pass" or .status == "fail") and (.seconds | type) == "number"'

run_tree() {
  local name=$1 run=$2 tree results config code
  tree=$(hostpath "$SCRATCH/$name")
  mkdir -p "$SCRATCH/results/$name-$run" || notrun "mkdir results -> failed, probe not run"
  results=$(hostpath "$SCRATCH/results/$name-$run")
  config=$(dc "$tree" "$results" config --format json 2>&1) ||
    notrun "docker compose config -> failed, probe not run: $config"
  printf '%s\n' "$config" | jq -e --arg tree "$tree" --arg results "$results" --arg tag "$TAG" "$CONFIG_OK" >/dev/null 2>&1 ||
    notrun "probe/compose.yaml -> breaks the probe contract, probe not run"
  dc "$tree" "$results" run --rm --no-deps -T checks >"$SCRATCH/results/$name-$run.log" 2>&1
  code=$?
  [ -f "$SCRATCH/results/$name-$run/checks.jsonl" ] ||
    notrun "run $name $run -> exit=$code, checks.jsonl absent, probe not run"
  jq -e -s "all(.[]; $RESULT_OK)" "$SCRATCH/results/$name-$run/checks.jsonl" >/dev/null 2>&1 ||
    notrun "run $name $run -> exit=$code, checks.jsonl unreadable, probe not run"
  echo "run $name $run -> exit=$code, checks=$(jq -s length "$SCRATCH/results/$name-$run/checks.jsonl" | tr -d '\r')"
}

i=1
while [ "$i" -le "$RUNS" ]; do
  run_tree baseline "$i"
  run_tree candidate "$i"
  i=$((i + 1))
done

READ='def runs($t): [$all[] | select(.tree == $t)];
  def statuses($t; $id): [runs($t)[] | ([.checks[] | select(.id == $id) | .status]
    | if length == 0 then "absent" elif index("fail") then "fail" else "pass" end)];
  def baseline($id): statuses("baseline"; $id)
    | if index("pass") then "pass" elif index("fail") then "fail" else "absent" end;
  def candidate($id): statuses("candidate"; $id)
    | if all(. == "absent") then "absent" elif all(. == "pass") then "pass" else "fail" end;
  [$all[].checks[].id] | unique[] as $id | [$id, baseline($id), candidate($id)] | @tsv'

all=$(cd "$SCRATCH/results" && for d in */; do
  d=${d%/}
  jq -c -s --arg tree "${d%-*}" '{tree: $tree, checks: .}' "$d/checks.jsonl"
done | jq -s -c .) || notrun "results -> unreadable, probe not run"

regressions=0 shown=0 failing=0
while IFS=$'\t' read -r id b c; do
  if [ "$b" = pass ] && [ "$c" != pass ]; then
    label=regression regressions=$((regressions + 1))
  elif [ "$b" != pass ] && [ "$c" = pass ]; then
    label=shown shown=$((shown + 1))
  elif [ "$b" = pass ]; then
    label=ok
  elif [ "$b" = fail ] && [ "$c" = fail ]; then
    label="failing on both" failing=$((failing + 1))
  else
    label="not passing" failing=$((failing + 1))
  fi
  echo "check $id baseline -> $b, candidate -> $c, $label"
done < <(jq -n -r --argjson all "$all" "$READ" | tr -d '\r')

if [ "$regressions" -gt 0 ]; then
  echo "verdict -> blocked, regressions=$regressions shown=$shown failing=$failing"
  exit 1
fi
echo "verdict -> no regression, regressions=0 shown=$shown failing=$failing"
exit 0
