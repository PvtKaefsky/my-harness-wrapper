#!/bin/bash
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0

for f in scripts/deslop-run.sh scripts/docker-lib.sh config/deslop-please.pins config/deslop-please.Dockerfile; do
  echo "test -f $SRC/$f -> $([ -f "$SRC/$f" ] && echo yes || echo no)"
  [ -f "$SRC/$f" ] || { echo "fail -> not run"; exit 1; }
done

WORK=$(mktemp -d) || { echo "mktemp -d -> exit=$?, not run"; exit 1; }
trap 'rm -rf -- "$WORK"' EXIT
BIN="$WORK/bin"
mkdir -p "$BIN" "$WORK/tree/src" "$WORK/host" "$WORK/harness/scripts" "$WORK/harness/config" "$WORK/nodocker"
cp "$SRC/scripts/deslop-run.sh" "$SRC/scripts/docker-lib.sh" "$WORK/harness/scripts/"
cp "$SRC/config/deslop-please.pins" "$SRC/config/deslop-please.Dockerfile" "$WORK/harness/config/"
RUNNER="$WORK/harness/scripts/deslop-run.sh"
REV=$(sed -n -E 's/^rev=([0-9a-f]+).*/\1/p' "$SRC/config/deslop-please.pins")
printf 'x = 1\n' > "$WORK/tree/src/m.py"
printf 'secret\n' > "$WORK/host/secret"

cat > "$BIN/docker" <<'EOF'
#!/bin/bash
here=${0%/*}
mode=$(cat "$here/mode" 2>/dev/null)
printf '%s\n' "$@" > "$here/args-$1"
env > "$here/env-$1"
case $1 in
  info) [ "$mode" = infofail ] && exit 1; echo 0.0.0-fake ;;
  build) [ "$mode" = buildfail ] && { echo "build step failed" >&2; exit 1; }; echo sha256:fake ;;
  rm) ;;
  run)
    prev=""
    for a in "$@"; do
      if [ "$prev" = -v ] && [ "${a%:/deslop/out}" != "$a" ]; then
        out=${a%:/deslop/out}
        if [ "$mode" = symlink ]; then
          MSYS=winsymlinks:nativestrict ln -s "$(cat "$here/secret-path")" "$out/allow"
        else
          printf 'new\n' > "$out/allow"
        fi
      fi
      prev=$a
    done
    case $mode in exit1) exit 1 ;; exit2) exit 2 ;; exit125) exit 125 ;; esac ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$BIN/docker"
printf '%s\n' "$WORK/host/secret" > "$BIN/secret-path"

export DESLOP_RUN_CANARY=host-value
STUB_PATH="$BIN:$PATH"
NO_DOCKER_PATH="$WORK/nodocker:$(printf '%s' "$PATH" | tr ':' '\n' | while IFS= read -r d; do
  [ -x "$d/docker" ] || [ -x "$d/docker.exe" ] || printf '%s:' "$d"; done)"
PATH=$NO_DOCKER_PATH command -v dirname >/dev/null 2>&1 || ln -s "$(command -v dirname)" "$WORK/nodocker/dirname"

check() {
  local name=$1 verdict=FAIL
  shift
  if "$@"; then verdict=ok; fi
  [ "$verdict" = ok ] || fails=$((fails + 1))
  echo "check $name -> $verdict"
}

run() {
  local mode=$1
  shift
  rm -f "$BIN"/args-* "$BIN"/env-*
  printf '%s\n' "$mode" > "$BIN/mode"
  PATH=$STUB_PATH "$BASH" "$RUNNER" "$@" > "$WORK/out" 2> "$WORK/err"
  code=$?
}

host() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
exits2() { [ "$code" -eq 2 ] && grep -qxF -- "$1" "$WORK/err"; }
has() { grep -qxF -- "$1" "$2"; }
hasre() { grep -qE -- "$1" "$2"; }
no() { [ -f "$2" ] && ! grep -qE -- "$1" "$2"; }
out_dir() { sed -n 's#:/deslop/out$##p' "$BIN/args-run"; }
out_gone() { local d; d=$(out_dir); [ -n "$d" ] && [ ! -e "$d" ]; }
rm_named() {
  local name
  name=$(grep -A1 -xF -- --name "$BIN/args-run" | tail -n 1)
  [ -n "$name" ] && has rm "$BIN/args-rm" && has -f "$BIN/args-rm" && has "$name" "$BIN/args-rm"
}
next_is() { grep -A1 -xF -- "$1" "$BIN/args-run" | tail -n 1 | grep -qxF -- "$2"; }
reset_allow() { printf 'old\n' > "$WORK/host/allow.txt"; }

run '' "$WORK/tree" --language python
check 'the tool exit 0 passes through' [ "$code" -eq 0 ]
check 'the tree is mounted read-only at /src' has "$(host "$WORK/tree"):/src:ro" "$BIN/args-run"
check 'no --privileged' no '^--privileged' "$BIN/args-run"
check 'all capabilities are dropped' next_is --cap-drop ALL
check 'no-new-privileges is set' next_is --security-opt no-new-privileges
check 'a pids limit is set' next_is --pids-limit 4096
check 'no Docker socket mount' no 'docker\.sock' "$BIN/args-run"
check 'no host network' no '^(--network|--net)(=host)?$|^host$' "$BIN/args-run"
check 'no -e, --env or --env-file' no '^(-e|--env|--env-file)(=.*)?$' "$BIN/args-run"
check 'no host variable reaches docker run' no '^DESLOP_RUN_CANARY=' "$BIN/env-run"
check 'the tool arguments pass through' has python "$BIN/args-run"
check 'the image is tagged with the pinned commit' has "deslop-please:$REV" "$BIN/args-run"
check 'the container is removed on exit' rm_named

run exit1 "$WORK/tree"
check 'the tool exit 1 passes through' [ "$code" -eq 1 ]
run exit2 "$WORK/tree"
check 'the tool exit 2 passes through' [ "$code" -eq 2 ]
run exit125 "$WORK/tree"
check 'a docker run failure exits 2 with the runner line' exits2 "docker run deslop-please:$REV -> exit=125, deslop pass not run"

reset_allow
for form in pair equals; do
  if [ "$form" = pair ]; then run '' "$WORK/tree" --allow "$WORK/host/allow.txt"; else run '' "$WORK/tree" "--allow=$WORK/host/allow.txt"; fi
  check "--allow ($form) mounts that file read-only at /deslop/allow" has "$(host "$WORK/host/allow.txt"):/deslop/allow:ro" "$BIN/args-run"
  check "--allow ($form) passes /deslop/allow" has /deslop/allow "$BIN/args-run"
done

for form in pair equals; do
  reset_allow
  if [ "$form" = pair ]; then run '' "$WORK/tree" --update-allow "$WORK/host/allow.txt"; else run '' "$WORK/tree" "--update-allow=$WORK/host/allow.txt"; fi
  check "--update-allow ($form) maps to a writable output directory" hasre ':/deslop/out$' "$BIN/args-run"
  check "--update-allow ($form) passes /deslop/out/allow" has /deslop/out/allow "$BIN/args-run"
  check "--update-allow ($form) copies the written allowlist back" has new "$WORK/host/allow.txt"
  check "the output directory is removed on exit ($form)" out_gone
done

if MSYS=winsymlinks:nativestrict ln -s "$WORK/host/secret" "$WORK/link" 2>/dev/null && [ -L "$WORK/link" ]; then
  reset_allow
  run symlink "$WORK/tree" --update-allow "$WORK/host/allow.txt"
  check 'a symlinked written allowlist exits 2 with the runner line' exits2 'written allowlist -> not a regular file, deslop pass not run'
  check 'a symlinked written allowlist leaves the destination unchanged' has old "$WORK/host/allow.txt"
else
  echo "check a symlinked written allowlist -> not run, ln -s makes no symbolic link here"
fi

run '' "$WORK/tree" --update-allow "$WORK/host/none/allow.txt"
check 'a failed allowlist copy exits 2 with the runner line' exits2 "cp allowlist to $WORK/host/none/allow.txt -> failed, deslop pass not run"

run '' "$WORK/tree" --allow "$WORK/host/missing.txt"
check 'a missing --allow file exits 2 with the runner line' exits2 "--allow $WORK/host/missing.txt -> not a file, deslop pass not run"

printf 'infofail\n' > "$BIN/mode"
PATH=$NO_DOCKER_PATH "$BASH" "$RUNNER" "$WORK/tree" > "$WORK/out" 2> "$WORK/err"
code=$?
check 'a missing docker exits 2 with the runner line' exits2 'command -v docker -> none, deslop pass not run'

run infofail "$WORK/tree"
check 'a failing docker exits 2 with the runner line' exits2 'docker info -> exit=1, deslop pass not run'

run buildfail "$WORK/tree"
check 'a failed build exits 2 with the runner line' exits2 'docker build config/deslop-please.Dockerfile -> failed, deslop pass not run'

run '' "$WORK/missing"
check 'a bad tree exits 2 with the runner line' exits2 "tree $WORK/missing -> not a directory, deslop pass not run"

printf 'rev=not-a-commit\n' >> "$WORK/harness/config/deslop-please.pins"
run '' "$WORK/tree"
check 'malformed pins exit 2 with the runner line' exits2 "pins in $WORK/harness/scripts/../config/deslop-please.pins -> malformed, deslop pass not run"

echo "fail -> $fails"
[ "$fails" -eq 0 ]
