#!/bin/bash
set -uo pipefail

NEVER='duplicate|invalid|wontfix|question|good first issue|help wanted'
ATTRIB='(^|[^a-z0-9])(ai|a\.i\.|agents?|agentic|claude|anthropic|models?|llms?|gpt|chatgpt|copilot|bots?)([^a-z0-9]|$)'
LABEL_REF="github\.event\.label|github\.event *\[|\.labels|\[ *'labels?' *\]"
IFLINE="^[[:space:]]*if:[[:space:]]*(\\\$\\{\\{[[:space:]]*)?(github\.event\.label\.name *== *'[^']*'|'[^']*' *== *github\.event\.label\.name|contains\( *github\.event\.(pull_request|issue)\.labels\.\*\.name *, *'[^']*' *\))([[:space:]]*\\}\\})?[[:space:]]*\$"

usage() {
  echo "usage: labels.sh sync [--file FILE] [--repo OWNER/REPO]" >&2
  echo "       labels.sh apply pr <n> [--file FILE] [--repo OWNER/REPO] [--areas] [--add LABEL]... [--remove LABEL]..." >&2
  echo "       labels.sh apply issue <n> [--file FILE] [--repo OWNER/REPO] [--add LABEL]... [--remove LABEL]..." >&2
  exit 2
}

notrun() {
  echo "$1"
  echo "labels -> not run"
  exit 2
}

jqr() { jq "$@" | tr -d '\r'; }

CMD=${1:-}
shift 2>/dev/null
KIND= NUM=
case $CMD in
  sync) ;;
  apply)
    [ $# -ge 2 ] || usage
    KIND=$1 NUM=$2
    shift 2
    case $KIND in pr | issue) ;; *) usage ;; esac
    case $NUM in '' | *[!0-9]* | 0*) usage ;; esac
    ;;
  *) usage ;;
esac

FILE= REPO= AREAS_FROM_PR=
ADD=() DEL=()
while [ $# -gt 0 ]; do
  if [ "$1" = --areas ]; then
    [ "$KIND" = pr ] || usage
    AREAS_FROM_PR=1
    shift
    continue
  fi
  [ $# -ge 2 ] || usage
  case $1 in
    --file) FILE=$2 ;;
    --repo) REPO=$2 ;;
    --add) ADD+=("$2") ;;
    --remove) DEL+=("$2") ;;
    *) usage ;;
  esac
  [ "$CMD" = apply ] || [ "$1" = --file ] || [ "$1" = --repo ] || usage
  shift 2
done

for tool in git jq gh; do
  command -v "$tool" >/dev/null 2>&1 || notrun "command -v $tool -> none"
done
if [ -n "$REPO" ]; then
  [[ $REPO =~ ^[A-Za-z0-9-]+/[A-Za-z0-9_.-]+$ && ${REPO#*/} != . && ${REPO#*/} != .. ]] || usage
  export GH_REPO=$REPO
fi
if [ -z "$FILE" ]; then
  top=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r') || notrun "git rev-parse --show-toplevel -> not a git repository"
  FILE=$top/.github/labels.json
fi
jq -e '.families | type == "array" and all(.[]; (.name | type == "string") and .name != "" and (.mode == "single" or .mode == "several"))' "$FILE" >/dev/null 2>&1 ||
  notrun "jq .families $FILE -> missing, not an array, or a family without a name or a single or several mode"
echo "label file -> $FILE"

ERR=$(mktemp) || notrun "mktemp -> failed"
trap 'rm -f -- "$ERR"' EXIT

ghout() { gh "$@" 2>"$ERR"; }
gherr() { head -n 1 "$ERR" | tr -d '\r'; }

badname() {
  [[ -z $1 || $1 == -* || $1 == *[,$'\n\r\t']* ]] && echo "name is empty, starts with a dash or holds a comma or control character"
}

refusal() {
  local r
  r=$(badname "$1")
  if [ -n "$r" ]; then
    echo "$r"
  elif grep -qixE "$NEVER" <<<"$1"; then
    echo "on the never-apply list"
  elif grep -qiE "$ATTRIB" <<<"$1"$'\n'"$2"; then
    echo "name or description refers to AI, an agent, Claude or a model"
  fi
}

lookup() {
  jq -c --arg n "$1" 'first(.families[] as $f |
    ((($f.labels // [])[] | select(.name == $n)),
     ($f.pattern // empty | (.name | split("<n>")) as [$a, $b] |
      select(($n | startswith($a)) and ($n | endswith($b // "")) and ($n | length) > ($a + ($b // "") | length)) |
      ($n | .[($a | length):(length - ($b // "" | length))]) as $k | select($k | test("^[1-9][0-9]*$")) |
      .name = $n | .description = (.description | gsub("<n>"; $k)))
    ) + {family: $f.name, mode: $f.mode}) // empty' "$FILE" | tr -d '\r'
}

field() { jqr -r --arg k "$2" '.[$k] // ""' <<<"$1"; }

has_label() { jq -e --arg n "$2" 'any(.[]; (.name | ascii_downcase) == ($n | ascii_downcase))' <<<"$1" >/dev/null 2>&1; }

create() {
  local info=$1 color
  shift
  color=$(field "$info" color)
  [[ $color =~ ^[0-9a-fA-F]{6}$ ]] || { echo "colour is not six hex digits"; return 1; }
  ghout label create "$(field "$info" name)" --color "$color" --description "$(field "$info" description)" "$@" >/dev/null ||
    { echo "exit=$?: $(gherr)"; return 1; }
}

fails=0
refuse() {
  echo "label $1 -> refused: $2"
  fails=$((fails + 1))
}

existing=$(ghout label list --limit 1000 --json name,color,description) || notrun "gh label list -> exit=$?: $(gherr)"
jq -e 'type == "array"' <<<"$existing" >/dev/null 2>&1 || notrun "gh label list -> not a JSON array"

if [ "$CMD" = sync ]; then
  while IFS= read -r info; do
    name=$(field "$info" name)
    reason=$(refusal "$name" "$(field "$info" description)")
    if [ -n "$reason" ]; then refuse "$name" "$reason"; continue; fi
    state=$(jqr -r --argjson l "$info" 'map(select((.name | ascii_downcase) == ($l.name | ascii_downcase))) | first |
      if . == null then "missing" elif (.color // "" | tostring | ascii_downcase) == ($l.color // "" | tostring | ascii_downcase) and (.description // "") == ($l.description // "") then "unchanged" else "differs" end' <<<"$existing")
    case $state in
      unchanged) echo "label $name -> unchanged" ;;
      missing) if err=$(create "$info"); then echo "label $name -> created"; else echo "label $name -> not created: $err"; fails=$((fails + 1)); fi ;;
      differs) if err=$(create "$info" --force); then echo "label $name -> updated"; else echo "label $name -> not updated: $err"; fails=$((fails + 1)); fi ;;
    esac
  done < <(jqr -c '.families[] | .labels[]?' "$FILE")
  echo "labels sync -> refused or failed=$fails"
  [ "$fails" -eq 0 ]
  exit
fi

fields=labels
[ "$KIND" = pr ] && fields=labels,headRefOid,baseRefName
item=$(ghout "$KIND" view "$NUM" --json "$fields") || notrun "gh $KIND view $NUM -> exit=$?: $(gherr)"
jq -e '.labels | type == "array"' <<<"$item" >/dev/null 2>&1 || notrun "gh $KIND view $NUM -> no labels array"
mapfile -t CURRENT < <(jqr -r '.labels[].name' <<<"$item")
declare -A ON=()
for l in "${CURRENT[@]}"; do ON[$l]=1; done

if [ -n "$AREAS_FROM_PR" ]; then
  changed=$(ghout pr diff "$NUM" --name-only | tr -d '\r') || notrun "gh pr diff $NUM --name-only -> failed: $(gherr)"
  mapfile -t AREAS < <(jqr -r --arg c "$changed" '[.families[] | .paths // {} | to_entries[] | . as $e |
    select(any($c | split("\n")[]; startswith($e.key))) | $e.value] | unique[]' "$FILE")
  echo "area labels from gh pr diff $NUM -> ${AREAS[*]:-none}"
  ADD+=("${AREAS[@]}")
  afam=$(jqr -r 'first(.families[] | select(.paths) | .name) // ""' "$FILE")
  if [ -n "$afam" ]; then
    for l in "${CURRENT[@]}"; do
      [ "$(field "$(lookup "$l")" family)" = "$afam" ] && [[ " ${AREAS[*]} " != *" $l "* ]] && DEL+=("$l")
    done
  fi
fi

TRIG_ALL=0 TRIG_NAMES=
triggered_labels() {
  local ref=$1 list path text trig test
  ghout api "repos/{owner}/{repo}/commits/$ref" >/dev/null || { echo "commit $ref -> not found: $(gherr)"; return 1; }
  if ! list=$(ghout api "repos/{owner}/{repo}/contents/.github/workflows?ref=$ref"); then
    grep -q 'HTTP 404' "$ERR" && { echo "workflows at $ref -> none"; return 0; }
    echo "workflows at $ref -> gh api failed: $(gherr)"
    return 1
  fi
  jq -e 'type == "array"' <<<"$list" >/dev/null 2>&1 || { echo "workflows at $ref -> listing is not a JSON array"; return 1; }
  while IFS= read -r path; do
    [[ $path =~ ^\.github/workflows/[A-Za-z0-9._-]+$ ]] || { echo "workflow $path at $ref -> unexpected path"; return 1; }
    text=$(ghout api -H 'Accept: application/vnd.github.raw' "repos/{owner}/{repo}/contents/$path?ref=$ref") ||
      { echo "workflow $path at $ref -> not readable"; return 1; }
    trig=0 test=0
    grep -qE '(^|[^A-Za-z0-9_])(un)?labeled([^A-Za-z0-9_]|$)' <<<"$text" && trig=1
    [ "$KIND" = issue ] && grep -qE '(^|[^A-Za-z0-9_.])issues([^A-Za-z0-9_]|$)' <<<"$text" && trig=1
    grep -qiE "$LABEL_REF" <<<"$text" && test=1
    if [ "$trig" = 1 ] || grep -viE "$IFLINE" <<<"$text" | grep -qiE "$LABEL_REF"; then
      TRIG_ALL=1
    fi
    TRIG_NAMES+=$(grep -iE "$IFLINE" <<<"$text" | grep -oE "'[^']*'" | tr -d "'")$'\n'
    echo "workflow $path at $ref -> label trigger=$trig, label test=$test"
  done < <(jqr -r '.[] | select(.type == "file") | .path' <<<"$list")
}

triggered() { [ "$TRIG_ALL" = 1 ] || grep -qixF -- "$1" <<<"$TRIG_NAMES"; }

SCAN_OK=0
repo_json=$(ghout api 'repos/{owner}/{repo}')
DEFAULT=$(jqr -r '.default_branch // ""' <<<"$repo_json" 2>/dev/null)
HEAD_SHA=$(jqr -r '.headRefOid // ""' <<<"$item")
BASE_REF=$(jqr -r '.baseRefName // ""' <<<"$item")
ok_ref() { [[ $1 =~ ^[A-Za-z0-9._/-]+$ && $1 != *..* ]]; }
if ok_ref "$DEFAULT" && { [ "$KIND" = issue ] || { [[ $HEAD_SHA =~ ^[0-9a-f]{40}$ ]] && ok_ref "$BASE_REF"; }; }; then
  triggered_labels "$DEFAULT" &&
    { [ "$KIND" = issue ] || { triggered_labels "$HEAD_SHA" && { [ "$BASE_REF" = "$DEFAULT" ] || triggered_labels "$BASE_REF"; }; }; } &&
    SCAN_OK=1
else
  echo "workflow refs -> default branch [$DEFAULT], head [$HEAD_SHA], base [$BASE_REF]: not usable"
fi
echo "workflow scan -> $([ "$SCAN_OK" = 1 ] && echo complete || echo incomplete)"

blocked() {
  badname "$1" && return
  [ "$SCAN_OK" = 1 ] || { echo "workflow scan incomplete"; return; }
  triggered "$1" && echo "a workflow triggers on or tests this label"
}

TO_ADD=() TO_DEL=()
declare -A TAKEN=()
for l in "${ADD[@]}"; do
  info=$(lookup "$l")
  [ -n "$info" ] || { refuse "$l" "not listed in $FILE"; continue; }
  reason=$(refusal "$l" "$(field "$info" description)")
  reason=${reason:-$(blocked "$l")}
  [ -z "$reason" ] || { refuse "$l" "$reason"; continue; }
  fam=$(field "$info" family) sibs=() single=
  if [ "$(field "$info" mode)" = single ]; then
    single=1
    [ -z "${TAKEN[$fam]:-}" ] || { refuse "$l" "family $fam already takes ${TAKEN[$fam]} in this call"; continue; }
    for c in "${CURRENT[@]}"; do
      [ "$c" != "$l" ] && [ "$(field "$(lookup "$c")" family)" = "$fam" ] && sibs+=("$c")
    done
    for c in "${sibs[@]}"; do reason=${reason:-$(blocked "$c")}; done
    [ -z "$reason" ] || { refuse "$l" "removing another $fam label: $reason"; continue; }
  fi
  if [ -z "${ON[$l]:-}" ] && ! has_label "$existing" "$l"; then
    err=$(create "$info") || { refuse "$l" "missing from the repository and not created: $err"; continue; }
    echo "label $l -> created"
  fi
  [ -z "$single" ] || TAKEN[$fam]=$l
  TO_DEL+=("${sibs[@]}")
  if [ -n "${ON[$l]:-}" ]; then echo "label $l -> already present"; else TO_ADD+=("$l"); fi
done
for l in "${DEL[@]}"; do
  reason=$(badname "$l")
  [ -z "$reason" ] || { refuse "$l" "$reason"; continue; }
  [ -n "${ON[$l]:-}" ] || { echo "label $l -> not present"; continue; }
  reason=$(blocked "$l")
  [ -z "$reason" ] || { refuse "$l" "$reason"; continue; }
  TO_DEL+=("$l")
done

mapfile -t TO_DEL < <(printf '%s\n' "${TO_DEL[@]}" | awk 'NF && !seen[$0]++')
args=()
for l in "${TO_ADD[@]}"; do args+=("--add-label=$l"); done
for l in "${TO_DEL[@]}"; do args+=("--remove-label=$l"); done
if [ ${#args[@]} -gt 0 ]; then
  ghout "$KIND" edit "$NUM" "${args[@]}" >/dev/null
  code=$?
  echo "gh $KIND edit $NUM -> exit=$code"
  if [ "$code" -eq 0 ]; then
    for l in "${TO_ADD[@]}"; do echo "label $l -> added"; done
    for l in "${TO_DEL[@]}"; do echo "label $l -> removed"; done
  else
    gherr
    fails=$((fails + ${#args[@]}))
  fi
fi
echo "labels apply -> refused or failed=$fails"
[ "$fails" -eq 0 ]
