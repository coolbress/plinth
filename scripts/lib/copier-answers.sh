# shellcheck shell=bash
# Reads a project's .copier-answers.yml. Sourced by scripts/guide-state.sh and
# by scripts/new-project.sh --where, so both say "made by plinth" by the same
# test (#1121).

# copier_answer <answers file> <key>: the value on the key's line, quotes
# taken off; nothing when the file or the key is missing.
copier_answer() {
  sed -nE "s/^$2: *['\"]?([^'\"]*)['\"]? *\$/\\1/p" "$1" 2>/dev/null | head -1
}

# made_by_plinth <answers file> <template repo>: rendered from plinth's
# template in the form the door writes (`_src_path: gh:<template repo>`), as
# floor-check's template item reads it. Another Copier template leaves an
# answers file too, with its own _src_path.
made_by_plinth() {
  [ -f "$1" ] && [ "$(copier_answer "$1" _src_path)" = "gh:$2" ]
}
