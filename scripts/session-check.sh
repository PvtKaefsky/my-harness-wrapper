#!/bin/bash
set -uo pipefail

REPO=${HARNESS_DIR:-/opt/my-harness-wrapper}
CONFIG_DIR="${CLAUDE_CONFIG_DIR-${HOME:-}/.claude}"
if command -v cygpath >/dev/null 2>&1 && [ -n "$CONFIG_DIR" ]; then
  CONFIG_CONV=$(cygpath -u "$CONFIG_DIR" 2>/dev/null) && [ -n "$CONFIG_CONV" ] && CONFIG_DIR=$CONFIG_CONV
fi
MANIFEST="$CONFIG_DIR/.my-harness-wrapper.manifest.json"
LOCAL_CHECKOUT=$(jq -r 'if type == "object" then (.local_checkout // empty | strings) else empty end' "$MANIFEST" 2>/dev/null)
LOCAL_CHECKOUT=${LOCAL_CHECKOUT%$'\r'}
INSTALL_LOG="$CONFIG_DIR/.my-harness-wrapper.install.log"
BOOTLOG=/home/user/bootstrap.log
if [ -n "$LOCAL_CHECKOUT" ]; then LOG="$CONFIG_DIR/session-check.log"; else LOG=/home/user/session-check.log; fi
VERIFY_TIMEOUT=${SESSION_CHECK_VERIFY_TIMEOUT:-20}
VERIFY_KILL_AFTER=${SESSION_CHECK_VERIFY_KILL_AFTER:-5}
OUT_LINE_CAP=${SESSION_CHECK_OUT_LINE_CAP:-40}

emit() {
  printf '%s\n' "$1"
  printf '%s\n' "$1" >> "$LOG" 2>/dev/null || true
}

if : >> "$LOG" 2>/dev/null; then LOG_STATE=appendable; else LOG_STATE="not appendable"; fi
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null); NOW_RC=$?
emit "session-check -> exit=$NOW_RC value=${NOW:-empty}"
emit "append to $LOG -> $LOG_STATE"

if [ -n "$LOCAL_CHECKOUT" ]; then
  emit "jq -r .local_checkout $MANIFEST -> $(printf '%s' "$LOCAL_CHECKOUT" | LC_ALL=C tr '\000-\037\177' '?')"
  emit "test -f $INSTALL_LOG -> $([ -f "$INSTALL_LOG" ] && echo yes || echo no)"
  if [ -f "$INSTALL_LOG" ]; then
    emit "stat -c %y $INSTALL_LOG -> $(stat -c %y "$INSTALL_LOG" 2>/dev/null || echo unreadable)"
    INSTALL_LAST=$(tail -n 1 "$INSTALL_LOG" 2>/dev/null)
    emit "tail -n 1 $INSTALL_LOG -> $(printf '%s' "$INSTALL_LAST" | LC_ALL=C tr '\000-\037\177' '?')"
  fi
else
  BOOT_RAW=$(uptime -s 2>/dev/null); BOOT_RC=$?
  emit "uptime -s -> exit=$BOOT_RC value=${BOOT_RAW:-empty}"
  emit "test -f $BOOTLOG -> $([ -f "$BOOTLOG" ] && echo yes || echo no)"
  if [ ! -f "$BOOTLOG" ]; then
    emit "snapshot state -> undetermined, $BOOTLOG absent"
  else
    LOG_EPOCH=$(stat -c %Y "$BOOTLOG" 2>/dev/null)
    LOG_SHOW=$(stat -c %y "$BOOTLOG" 2>/dev/null)
    BOOT_EPOCH=$([ "$BOOT_RC" -eq 0 ] && [ -n "${BOOT_RAW:-}" ] && date -d "$BOOT_RAW" +%s 2>/dev/null)
    emit "stat -c %y $BOOTLOG -> ${LOG_SHOW:-unreadable}"
    LOG_OK=no
    BOOT_OK=no
    case "${LOG_EPOCH:-}" in ''|*[!0-9]*) ;; *) LOG_OK=yes ;; esac
    case "${BOOT_EPOCH:-}" in ''|*[!0-9]*) ;; *) BOOT_OK=yes ;; esac
    if [ "$LOG_OK" = yes ] && [ "$BOOT_OK" = yes ]; then
      if [ "$LOG_EPOCH" -ge "$BOOT_EPOCH" ]; then
        emit "log mtime >= boot time -> yes, this session built the snapshot"
      else
        emit "log mtime >= boot time -> no, this session restored the snapshot"
      fi
    else
      emit "snapshot state -> undetermined, log epoch [${LOG_EPOCH:-empty}] boot epoch [${BOOT_EPOCH:-empty}]"
    fi
  fi

  FOUND=0
  for d in /home/user/*/; do
    [ -d "$d" ] || continue
    FOUND=$((FOUND + 1))
    if git -C "$d" rev-parse --git-dir >/dev/null 2>&1; then
      BR=$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null); BR_RC=$?
      SHA=$(git -C "$d" rev-parse --short HEAD 2>/dev/null); SHA_RC=$?
      emit "git -C $d rev-parse --abbrev-ref HEAD, --short HEAD -> exit=$BR_RC,$SHA_RC branch=${BR:-empty} head=${SHA:-empty}"
    else
      git -C "$d" rev-parse --git-dir >/dev/null 2>&1; GD_RC=$?
      emit "git -C $d rev-parse --git-dir -> exit=$GD_RC"
    fi
  done
  [ "$FOUND" -gt 0 ] || emit "ls -d /home/user/*/ -> none"
fi

VERIFY="$REPO/scripts/verify.sh"
emit "test -f $VERIFY -> $([ -f "$VERIFY" ] && echo yes || echo no)"
if [ ! -f "$VERIFY" ]; then
  emit "verify.sh -> not run, $VERIFY absent"
else
  OUTFILE=$(mktemp 2>/dev/null)
  if [ -z "${OUTFILE:-}" ]; then
    emit "mktemp -> empty, verify.sh not run"
    exit 0
  fi
  timeout -k "$VERIFY_KILL_AFTER" "$VERIFY_TIMEOUT" bash "$VERIFY" > "$OUTFILE" 2>&1 &
  TPID=$!
  wait "$TPID"; V_RC=$?
  kill -KILL -- "-$TPID" 2>/dev/null
  OUT_TOTAL=$(grep -a -c '' "$OUTFILE" 2>/dev/null)
  case "${OUT_TOTAL:-}" in ''|*[!0-9]*) OUT_TOTAL=0 ;; esac
  if [ "$V_RC" -eq 124 ] || [ "$V_RC" -eq 137 ]; then
    emit "verify.sh -> timed out after ${VERIFY_TIMEOUT}s, process group killed (exit=$V_RC)"
  elif grep -a -qE '^(FAIL|NOTE) ' "$OUTFILE" 2>/dev/null; then
    while IFS= read -r line || [ -n "$line" ]; do
      emit "verify.sh $(printf '%s' "$line" | LC_ALL=C tr '\000-\037\177' '?')"
    done < <(grep -a -E '^(FAIL|NOTE) ' "$OUTFILE" 2>/dev/null)
  else
    TALLY=$(grep -a -E '^fail -> ' "$OUTFILE" 2>/dev/null | tail -1)
    if [ -n "$TALLY" ]; then
      emit "verify.sh -> $TALLY (exit=$V_RC)"
    else
      if [ "$OUT_TOTAL" -le "$OUT_LINE_CAP" ]; then OUT_SHOW=$OUT_TOTAL; else OUT_SHOW=$OUT_LINE_CAP; fi
      emit "verify.sh -> no 'fail ->' line (exit=$V_RC), $OUT_TOTAL output lines, $OUT_SHOW follow"
      OUT_SHOWN=0
      while IFS= read -r line || [ -n "$line" ]; do
        OUT_SHOWN=$((OUT_SHOWN + 1))
        [ "$OUT_SHOWN" -le "$OUT_LINE_CAP" ] || break
        emit "verify.sh | $(printf '%s' "$line" | LC_ALL=C tr '\000-\037\177' '?')"
      done < "$OUTFILE"
    fi
  fi
  rm -f "$OUTFILE"
fi

exit 0
