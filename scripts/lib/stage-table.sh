# shellcheck shell=bash
# stage_table <arsenal SKILL.md> <guide steps.md>: the "Where you are" table
# as /plinth:guide reads it (#1086), one row per stage in the arsenal's order
# with six cells: where (the arsenal's Trigger), next action, tool, how to use
# it, it leaves, then. The arsenal gives Trigger, Tool, plinth piece, Also and
# Then; the guide's steps.md gives the rest, joined by the first cell. The tool
# cell is the arsenal's Tool, then its plinth piece, then "also: " and its
# Also, then "class: " and its Class, each after "; ", a `-` left out. An arsenal row without six cells is
# printed as it is, for the reader to refuse; a stage steps.md has no row for
# is an error (exit 1).
stage_table() {
  local a="$1" s="$2"
  awk -F ' \\| ' '
    function cells(line, arr,   n, i) { n = split(line, arr, / \| /); sub(/^\| /, "", arr[1]); sub(/ \|$/, "", arr[n]); return n }
    function section(line) { return line ~ /^## / }
    FNR == 1 { file++; on = 0 }
    file == 1 && /^## Where you are, and what to do next/ { on = 1; next }
    file == 2 && /^## Steps/ { on = 1; next }
    on && section($0) { on = 0 }
    !on || !/^\| / { next }
    { n = cells($0, c); if (c[1] == "Trigger" || c[1] == "Where you are" || c[1] ~ /^---/) next }
    file == 1 { order[++rows] = c[1]; raw[c[1]] = $0; nf[c[1]] = n; for (i = 1; i <= n; i++) A[c[1], i] = c[i]; next }
    file == 2 { if (n == 4) { G[c[1]] = 1; for (i = 2; i <= 4; i++) S[c[1], i] = c[i] } else bad4[c[1]] = n }
    END {
      print "| Where you are | Next action | Tool | How to use it | It leaves | Then |"
      print "| --- | --- | --- | --- | --- | --- |"
      for (r = 1; r <= rows; r++) {
        w = order[r]
        if (nf[w] != 6) { print raw[w]; continue }
        if (!(w in G)) {
          if (w in bad4) printf "guide-state: the guide'"'"'s row \x27%s\x27 does not have four cells\n", w > "/dev/stderr"
          else printf "guide-state: the guide'"'"'s steps have no row for \x27%s\x27\n", w > "/dev/stderr"
          exit 1
        }
        tool = A[w, 2]
        if (A[w, 4] != "-") tool = (tool == "-" ? "" : tool "; ") A[w, 4]
        if (A[w, 5] != "-") tool = tool "; also: " A[w, 5]
        if (A[w, 3] != "-") tool = tool "; class: " A[w, 3]
        printf "| %s | %s | %s | %s | %s | %s |\n", w, S[w, 2], tool, S[w, 3], S[w, 4], A[w, 6]
      }
    }' "$a" "$s"
}
