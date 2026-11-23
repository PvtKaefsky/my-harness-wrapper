hook_name=${0##*/}
hook_lib="$HOOK_DIR/lib"

hook_sanitize() { printf '%s' "$1" | LC_ALL=C tr '\n' ' ' | LC_ALL=C tr '\000-\037\177' '?'; }

hook_refuse() {
  printf 'harness %s: %s\n' "$hook_name" "$(hook_sanitize "$1")" >&2
  exit 1
}

hook_commit_msg() {
  local pattern key val mode="" comment="#" cut=no drop=no scanned awk_rc hit grep_rc found scan_rc action n cp
  . "$hook_lib/hidden-chars.sh" 2>/dev/null || hook_refuse "$hook_lib/hidden-chars.sh could not be read, so the message was not checked; re-run the harness installer, then commit again."
  { pattern=$(< "$hook_lib/attribution.ere"); } 2>/dev/null
  pattern=${pattern%$'\r'}
  if [ -z "$pattern" ] || [ "$pattern" != "${pattern%%$'\n'*}" ]; then
    hook_refuse "$hook_lib/attribution.ere holds no single pattern line, so the message was not checked; re-run the harness installer, then commit again."
  fi
  while read -r key val; do
    case "$key" in
      commit.cleanup) mode=$val ;;
      core.commentchar|core.commentstring) comment=$val ;;
    esac
  done < <(git config --get-regexp '^(commit\.cleanup|core\.comment(char|string))$' 2>/dev/null)
  [ -n "$comment" ] || comment="#"
  case "$mode" in
    strip) cut=yes; drop=yes ;;
    whitespace|verbatim) ;;
    scissors) [ "${GIT_EDITOR-}" = ":" ] || cut=yes ;;
    *) [ "${GIT_EDITOR-}" = ":" ] || { cut=yes; drop=yes; } ;;
  esac
  { scanned=$(hidden_swap < "$1" | LC_ALL=C awk -v cut="$cut" -v drop="$drop" -v c="$comment" '
    BEGIN { scissors = " ------------------------ >8 ------------------------"; cands = "#;@!$%^&|:" }
    {
      line = $0
      sub(/\r$/, "", line)
      if (c == "auto") { cmt = substr(line, 1, 1); iscomment = (cmt != "" && index(cands, cmt) > 0) }
      else { cmt = c; iscomment = (substr(line, 1, length(c)) == c) }
      if (cut == "yes" && iscomment && line == cmt scissors) exit
      if (drop == "yes" && iscomment) next
      print line
    }'; rc=("${PIPESTATUS[@]}"); if [ "${rc[0]}" -ne 0 ] && [ "${rc[0]}" -ne 141 ]; then exit "${rc[0]}"; fi; exit "${rc[1]}"); awk_rc=$?; } 2>/dev/null
  if [ "$awk_rc" -ne 0 ]; then
    hook_refuse "awk could not read the message file $1 (exit=$awk_rc), so the message was not checked."
  fi
  hit=$(printf '%s\n' "$scanned" | grep -a -i -E -m1 -- "$pattern" 2>/dev/null); grep_rc=$?
  if [ "$grep_rc" -gt 1 ]; then
    hook_refuse "grep could not apply $hook_lib/attribution.ere (exit=$grep_rc), so the message was not checked."
  fi
  if [ "$grep_rc" -eq 0 ]; then
    printf 'harness commit-msg: matched line -> %s\n' "$(hook_sanitize "$hit")" >&2
    printf 'harness commit-msg: remove that attribution line from the commit message, then commit again.\n' >&2
    exit 1
  fi
  found=$(printf '%s\n' "$scanned" | hidden_scan "$hook_lib/hidden-chars.tsv"); scan_rc=$?
  if [ "$scan_rc" -ne 0 ]; then
    hook_refuse "$hook_lib/hidden-chars.tsv could not be applied (exit=$scan_rc), so the message was not checked; re-run the harness installer, then commit again."
  fi
  while IFS=$'\t' read -r action n cp; do
    [ "$action" = block ] || continue
    printf 'harness commit-msg: hidden character -> %s on line %s of the commit message\n' "$cp" "$n" >&2
    printf 'harness commit-msg: remove that character from the commit message, then commit again.\n' >&2
    exit 1
  done <<< "$found"
}

hook_staged_diff() {
  git -c core.quotePath=true diff --cached --no-color --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ -U0 | hidden_swap
  return "${PIPESTATUS[0]}"
}

hook_pre_commit() {
  local tsv="$hook_lib/hidden-chars.tsv" found mapped rc action cp n path blocked=no
  . "$hook_lib/hidden-chars.sh" 2>/dev/null || hook_refuse "$hook_lib/hidden-chars.sh could not be read, so the staged changes were not checked; re-run the harness installer, then commit again."
  found=$(hook_staged_diff | LC_ALL=C sed -e '/^+/!s/.*//' | hidden_scan "$tsv"; rc=("${PIPESTATUS[@]}"); if [ "${rc[2]}" -ne 0 ]; then exit 2; fi; [ "${rc[0]}" -eq 0 ] && [ "${rc[1]}" -eq 0 ]); rc=$?
  if [ "$rc" -eq 2 ]; then
    hook_refuse "$tsv could not be applied, so the staged changes were not checked; re-run the harness installer, then commit again."
  fi
  if [ "$rc" -ne 0 ]; then
    hook_refuse "git diff --cached could not be read, so the staged changes were not checked."
  fi
  [ -n "$found" ] || return 0
  mapped=$(hook_staged_diff | LC_ALL=C awk -v found="${found//$'\n'/;}" '
    function count(x, a) { return split(x, a, ",") > 1 ? a[2] + 0 : 1 }
    BEGIN { n = split(found, f, ";"); for (i = 1; i <= n; i++) { split(f[i], c, "\t"); want[c[2]] = want[c[2]] c[1] "\t" c[3] "\n"; left++ } }
    old + new > 0 {
      first = substr($0, 1, 1)
      if (first == "\\") next
      if (first == "+") {
        if (NR in want) { m = split(want[NR], w, "\n"); for (i = 1; i < m; i++) { printf "%s\t%d\t%s\n", w[i], ln, path; left-- } }
        ln++; new--
      } else if (first == "-") old--
      else { old--; new--; ln++ }
      next
    }
    /^\+\+\+ / { path = substr($0, 5); sub(/\t$/, "", path); if (substr(path, 1, 2) == "b/") path = substr(path, 3); next }
    /^@@ / { split($0, h, " "); old = count(h[2]); new = count(h[3]); split(substr(h[3], 2), s, ","); ln = s[1] + 0 }
    END { if (left != 0) exit 3 }'; rc=("${PIPESTATUS[@]}"); [ "${rc[0]}" -eq 0 ] && [ "${rc[1]}" -eq 0 ]) || hook_refuse "git diff --cached could not be mapped to files, so the staged changes were not checked."
  while IFS=$'\t' read -r action cp n path; do
    case "$action" in
      block) blocked=yes; printf 'harness pre-commit: hidden character -> %s at %s:%s\n' "$cp" "$(hook_sanitize "$path")" "$n" >&2 ;;
      warn) printf 'harness pre-commit: zero-width character %s at %s:%s, committed as staged.\n' "$cp" "$(hook_sanitize "$path")" "$n" >&2 ;;
    esac
  done <<< "$mapped"
  if [ "$blocked" = yes ]; then
    printf 'harness pre-commit: remove each character from the staged file, then commit again.\n' >&2
    exit 1
  fi
}

hook_push_to_checkout_default() {
  local base=HEAD
  git update-index -q --ignore-submodules --refresh || hook_refuse "Up-to-date check failed"
  git diff-files --quiet --ignore-submodules -- || hook_refuse "Working directory has unstaged changes"
  git rev-parse --verify -q HEAD >/dev/null || base=$(git hash-object -t tree /dev/null)
  git diff-index --quiet --cached --ignore-submodules "$base" -- || hook_refuse "Working directory has staged changes"
  git read-tree -u -m "$1" || hook_refuse "Could not update working tree to new HEAD"
  exit 0
}

hook_relative() {
  case "$2" in
    /*|[A-Za-z]:/*|[A-Za-z]:\\*) printf -v "$3" '%s' "$2" ;;
    *) printf -v "$3" '%s/%s' "$1" "$2" ;;
  esac
}

hook_is_gitdir() { [ -f "$1/HEAD" ] && [ -d "$1/objects" ] && [ -d "$1/refs" ]; }

hook_common_dir() {
  local gitdir="" line=""
  if [ -n "${GIT_COMMON_DIR-}" ]; then common=$GIT_COMMON_DIR; return 0; fi
  if [ -n "${GIT_DIR-}" ]; then
    gitdir=$GIT_DIR
  elif [ -d .git ]; then
    hook_is_gitdir .git || return 1
    gitdir="$PWD/.git"
  elif [ -f .git ]; then
    IFS= read -r line < .git || [ -n "$line" ] || return 1
    line=${line%$'\r'}
    case "$line" in "gitdir: "?*) hook_relative "$PWD" "${line#gitdir: }" gitdir ;; *) return 1 ;; esac
  elif hook_is_gitdir .; then
    gitdir=$PWD
  else
    return 1
  fi
  if [ -f "$gitdir/commondir" ]; then
    line=""
    IFS= read -r line < "$gitdir/commondir" || [ -n "$line" ] || return 1
    line=${line%"${line##*[![:space:]]}"}
    [ -n "$line" ] || return 1
    hook_relative "$gitdir" "$line" common
  else
    common=$gitdir
  fi
}

hook_configured_dir() {
  local out rc line scope value s name v_worktree="" v_local="" v_global="" v_system=""
  out=$(git config --show-scope --type=path --get-all core.hooksPath 2>/dev/null); rc=$?
  [ "$rc" -ne 1 ] || return 1
  if [ "$rc" -ne 0 ]; then
    hook_refuse "git config --show-scope --type=path --get-all core.hooksPath -> exit=$rc, so the repository's own $hook_name hook was not looked up."
  fi
  while IFS= read -r line; do
    line=${line%$'\r'}
    scope=${line%%$'\t'*}
    [ "$scope" != "$line" ] || continue
    value=${line#*$'\t'}
    case "$scope" in
      worktree|local|global|system) printf -v "v_$scope" '%s' "$value" ;;
    esac
  done <<< "$out"
  for s in worktree local global system; do
    name="v_$s"
    value=${!name}
    [ -n "$value" ] || continue
    hook_relative "$PWD" "$value" hooks
    [ -f "$hooks/lib/dispatch.sh" ] || return 0
  done
  hooks=""
  return 1
}

hook_forward() {
  local common="" rc target hooks=""
  if hook_configured_dir; then
    :
  elif ! hook_common_dir; then
    common=$(git rev-parse --git-common-dir 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$common" ]; then
      hook_refuse "the repository's git directory was not found from $PWD, and git rev-parse --git-common-dir -> exit=$rc, so the repository's own $hook_name hook was not looked up."
    fi
  fi
  [ -n "$hooks" ] || hooks="$common/hooks"
  target="$hooks/$hook_name"
  if [ -f "$target" ] && ! [ "$hooks" -ef "$HOOK_DIR" ] && ! [ "$target" -ef "$0" ]; then
    if [ -x "$target" ]; then exec "$target" "$@"; fi
    printf 'harness %s: %s was not run, it is not executable.\n' "$hook_name" "$(hook_sanitize "$target")" >&2
  fi
  case "$hook_name" in
    push-to-checkout) hook_push_to_checkout_default "$@" ;;
    proc-receive) hook_refuse "the repository has no executable proc-receive hook at $target." ;;
  esac
  exit 0
}

if [ "$hook_name" = commit-msg ]; then hook_commit_msg "$1"; fi
if [ "$hook_name" = pre-commit ]; then hook_pre_commit; fi
hook_forward "$@"
