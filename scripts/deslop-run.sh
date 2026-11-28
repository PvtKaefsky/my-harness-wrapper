#!/bin/bash
set -uo pipefail

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SELF_DIR/docker-lib.sh"
PINS="$SELF_DIR/../config/deslop-please.pins"
DOCKERFILE="$SELF_DIR/../config/deslop-please.Dockerfile"

notrun() {
  echo "$1, deslop pass not run" >&2
  exit 2
}

abspath() { printf '%s/%s\n' "$(cd "$(dirname "$1")" && pwd)" "$(basename "$1")"; }

[ $# -ge 1 ] || notrun "usage: deslop-run.sh <tree> [deslop-please arguments]"
[ -d "$1" ] || notrun "tree $1 -> not a directory"
TREE=$(cd "$1" && pwd) || notrun "tree $1 -> not readable"
shift

URL="" REV="" IMAGE="" INDEXERS=()
[ -f "$PINS" ] || notrun "test -f $PINS -> no"
while IFS='=' read -r key value || [ -n "${key:-}" ]; do
  value=${value%$'\r'}
  case "$key" in
    url) URL=$value ;;
    rev) REV=$value ;;
    image) IMAGE=$value ;;
    indexer) INDEXERS+=("$value") ;;
  esac
done < "$PINS"
valid=yes
[[ "$URL" =~ ^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || valid=no
[[ "$REV" =~ ^[0-9a-f]{40}$ ]] || valid=no
[[ "$IMAGE" =~ ^[a-z0-9][a-z0-9._/-]*:[A-Za-z0-9._-]+(@sha256:[0-9a-f]{64})?$ ]] || valid=no
[ "${#INDEXERS[@]}" -gt 0 ] || valid=no
for pkg in "${INDEXERS[@]}"; do [[ "$pkg" =~ ^@[a-z0-9._-]+/[a-z0-9._-]+@[0-9]+\.[0-9]+\.[0-9]+$ ]] || valid=no; done
[ "$valid" = yes ] || notrun "pins in $PINS -> malformed"

command -v docker >/dev/null 2>&1 || notrun "command -v docker -> none"
dk info >/dev/null 2>&1 || notrun "docker info -> exit=$?"

SCRATCH=$(mktemp -d) || notrun "mktemp -d -> exit=$?"
NAME="deslop-run-$$-$RANDOM"
TAG="deslop-please:$REV"
cleanup() {
  dk rm -f "$NAME" >/dev/null 2>&1
  rm -rf -- "$SCRATCH"
}
trap cleanup EXIT

MOUNTS=(-v "$(hostpath "$TREE"):/src:ro")
ARGS=() UPDATE=""
while [ $# -gt 0 ]; do
  case $1 in
    --allow | --update-allow)
      [ $# -ge 2 ] || notrun "$1 -> no path"
      flag=$1 path=$2
      shift 2 ;;
    --allow=* | --update-allow=*)
      flag=${1%%=*} path=${1#*=}
      shift ;;
    *)
      ARGS+=("$1")
      shift
      continue ;;
  esac
  if [ "$flag" = --allow ]; then
    [ -f "$path" ] || notrun "--allow $path -> not a file"
    MOUNTS+=(-v "$(hostpath "$(abspath "$path")"):/deslop/allow:ro")
    ARGS+=(--allow /deslop/allow)
  else
    mkdir -p "$SCRATCH/out" && chmod 0777 "$SCRATCH/out" || notrun "mkdir output directory -> failed"
    MOUNTS+=(-v "$(hostpath "$SCRATCH/out"):/deslop/out")
    ARGS+=(--update-allow /deslop/out/allow)
    UPDATE=$path
  fi
done

if ! dkenv docker build -q -t "$TAG" --build-arg "IMAGE=$IMAGE" --build-arg "URL=$URL" \
  --build-arg "REV=$REV" --build-arg "INDEXERS=${INDEXERS[*]}" - < "$DOCKERFILE" > "$SCRATCH/build.log" 2>&1; then
  tail -n 20 "$SCRATCH/build.log" >&2
  notrun "docker build config/deslop-please.Dockerfile -> failed"
fi

COPY='(cd /src && find . -path "*[[:cntrl:]]*" -prune -o -name .git -prune -o -type d -name target \
  -exec test -f "{}/CACHEDIR.TAG" \; -prune -print) > /tmp/skip &&
  tar -C /src --exclude=.git --anchored --no-wildcards -X /tmp/skip -cf - . | tar -C /work -xf - ||
  { echo "copy of the tree -> failed" >&2; exit 2; }
exec deslop-please "$@"'
dkenv docker run --rm --name "$NAME" --pids-limit 4096 --cap-drop ALL --security-opt no-new-privileges \
  "${MOUNTS[@]}" "$TAG" bash -o pipefail -c "$COPY" deslop-run ${ARGS[@]+"${ARGS[@]}"}
code=$?
case $code in 0 | 1 | 2) ;; *) notrun "docker run $TAG -> exit=$code" ;; esac
if [ -n "$UPDATE" ] && { [ -e "$SCRATCH/out/allow" ] || [ -L "$SCRATCH/out/allow" ]; }; then
  [ -f "$SCRATCH/out/allow" ] && [ ! -L "$SCRATCH/out/allow" ] || notrun "written allowlist -> not a regular file"
  cp -- "$SCRATCH/out/allow" "$UPDATE" || notrun "cp allowlist to $UPDATE -> failed"
fi
exit "$code"
