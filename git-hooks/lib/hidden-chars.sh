hidden_swap() { LC_ALL=C tr '\000\001' '\001\000'; }

hidden_scan() {
  local action first last pat part ere="" rows="" out
  if [ ! -f "$1" ] || [ ! -r "$1" ]; then return 2; fi
  while IFS=$'\t' read -r action first last pat || [ -n "$action" ]; do
    pat=${pat%$'\r'}
    case "$action" in block|warn) ;; *) return 2 ;; esac
    [[ $first =~ ^U\+[0-9A-F]+$ && $last =~ ^U\+[0-9A-F]+$ && -n $pat ]] || return 2
    printf -v part '%b' "${pat//\\x00/\\x01}"
    ere="$ere${ere:+|}$part"
    rows="$rows $action $((16#${first#U+})) $((16#${last#U+}))"
  done < "$1"
  if [ -z "$ere" ]; then return 2; fi
  out=$(LC_ALL=C grep -a -n -o -E -- "$ere" 2>/dev/null | LC_ALL=C awk -v rows="$rows" '
    BEGIN { for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i; n = split(rows, r, " ") }
    {
      i = index($0, ":")
      k = substr($0, i + 1)
      if (seen[k]++) next
      b = ord[substr(k, 1, 1)]
      if (b == 1) cp = 0
      else if (length(k) == 3) cp = (b - 224) * 4096 + (ord[substr(k, 2, 1)] - 128) * 64 + ord[substr(k, 3, 1)] - 128
      else cp = (b - 240) * 262144 + (ord[substr(k, 2, 1)] - 128) * 4096 + (ord[substr(k, 3, 1)] - 128) * 64 + ord[substr(k, 4, 1)] - 128
      for (j = 1; j <= n; j += 3) if (cp >= r[j + 1] && cp <= r[j + 2]) { printf "%s\t%s\tU+%04X\n", r[j], substr($0, 1, i - 1), cp; break }
    }'; rc=("${PIPESTATUS[@]}"); [ "${rc[0]}" -le 1 ] && [ "${rc[1]}" -eq 0 ]) || return 2
  if [ -n "$out" ]; then printf '%s\n' "$out"; fi
}
