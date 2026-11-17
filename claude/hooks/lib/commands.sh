# Sourced by the Bash guards: split a command line into its top-level
# commands so a guard only inspects the command it cares about.

# Prints each top-level command of $1, heredoc bodies included, followed
# by \036. Quotes, $(...) and heredocs of any delimiter don't split.
bash_commands() {
  printf '%s' "$1" | awk -v sq1="'" '
    function emit() { sub(/^[[:space:]]+/, "", cur); if (cur != "") printf "%s\036", cur; cur = "" }
    function push(c) { ctx[++d] = c }
    function heredoc(   j, w, q, ch) {
      j = i + 2
      strip = 0
      if (substr(s, j, 1) == "-") { strip = 1; j++ }
      while (substr(s, j, 1) ~ /[ \t]/) j++
      w = ""
      q = substr(s, j, 1)
      if (q == sq1 || q == "\"") {
        j++
        while (j <= n && substr(s, j, 1) != q) w = w substr(s, j++, 1)
        j++
      } else {
        while (j <= n && (ch = substr(s, j, 1)) !~ /[ \t;&|()<>]/) {
          if (ch != "\\") w = w ch
          j++
        }
      }
      if (w != "") { pend[++np] = w; pstrip[np] = strip }
      cur = cur substr(s, i, j - i)
      i = j - 1
    }
    function bodies(   k, cmp) {
      for (k = 1; k <= np; k++) {
        while (ln < m) {
          cmp = L[++ln]
          cur = cur cmp "\n"
          if (pstrip[k]) sub(/^\t+/, "", cmp)
          if (cmp == pend[k]) break
        }
      }
      np = 0
    }
    { L[NR] = $0 }
    END {
      m = NR; d = 0; sq = 0; np = 0; cur = ""
      for (ln = 1; ln <= m; ln++) {
        s = L[ln]; n = length(s)
        for (i = 1; i <= n; i++) {
          c = substr(s, i, 1); nx = substr(s, i + 1, 1)
          if (sq) { cur = cur c; if (c == sq1) sq = 0; continue }
          if (c == "\\") { cur = cur c nx; i++; continue }
          if (d > 0 && ctx[d] == "D") {
            cur = cur c
            if (c == "\"") d--
            else if (c == "$" && nx == "(") { cur = cur nx; i++; push("S") }
            continue
          }
          if (c == sq1) { sq = 1; cur = cur c; continue }
          if (c == "\"") { push("D"); cur = cur c; continue }
          if (c == "$" && nx == "(") { push("S"); cur = cur c nx; i++; continue }
          if (c == "<" && nx == "<" && substr(s, i + 2, 1) != "<") { heredoc(); continue }
          if (d > 0) { cur = cur c; if (c == ")") d--; else if (c == "(") push("S"); continue }
          if (c == "#" && (cur == "" || cur ~ /[[:space:]]$/)) break
          if (c == "&" && (nx == ">" || cur ~ /[<>]$/)) { cur = cur c; continue }
          if (c ~ /[;&|()]/) { emit(); continue }
          cur = cur c
        }
        if (ln == m) break
        if (s ~ /\\$/ && !sq) { cur = cur "\n"; continue }
        if (np) { cur = cur "\n"; bodies(); if (d == 0 && !sq) emit(); continue }
        if (d == 0 && !sq) emit(); else cur = cur "\n"
      }
      emit()
    }'
}

# Strips leading VAR=value assignments and `command`/`env` from a command.
command_words() {
  local cmd=$1
  local re='^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|command|env)[[:space:]]+(.*)'
  while [[ $cmd =~ $re ]]; do cmd=${BASH_REMATCH[2]}; done
  printf '%s' "$cmd"
}

# Prints the body of the first heredoc opened on the first line of $1.
heredoc_body() {
  local first=${1%%$'\n'*}
  local re='<<-?[[:space:]]*['\''"]?([A-Za-z_][A-Za-z0-9_]*)'
  [[ $first =~ $re ]] || return 1
  awk -v d="${BASH_REMATCH[1]}" 'NR == 1 { next } { l = $0; sub(/^\t+/, "", l) } l == d { exit } { print }' <<<"$1"
}
