#!/usr/bin/env bash
# Every slash command a /plinth:guide text names must be in the arsenal's
# "Where you are, and what to do next" table (#710), and none of the tools
# #711 compared and left out may be named at all. Run by tests/guide-cases.sh
# on the skill itself, and usable on a recorded guide answer:
#
#   tests/lib/guide-names.sh <arsenal SKILL.md> <file>...
#
# A slash command is `/` and a lowercase name at the start of a word (so
# `docs/how-to`, `${CLAUDE_PLUGIN_ROOT}/scripts` and `/home/x/plinth` are not), with trailing
# punctuation dropped. Prints one FAIL line per name; exit 1 if any.
set -uo pipefail
[ "$#" -ge 2 ] || { echo "usage: guide-names.sh <arsenal SKILL.md> <file>..." >&2; exit 2; }
arsenal="$1"; shift

commands() { # <file>: each slash command once
  grep -oE "(^|[[:space:](\`\"'*>])/[a-z][a-z0-9:._-]*/?" "$1" | grep -v '/$' | sed -E 's/^[^/]//; s/[.:_-]+$//' | sort -u
}
table="$(mktemp)"; trap 'rm -f "$table"' EXIT
awk '/^## Where you are, and what to do next/{on=1; next} on && /^## /{exit} on && /^\| /' "$arsenal" > "$table"
[ -s "$table" ] || { echo "  FAIL  no 'Where you are, and what to do next' table in $arsenal"; exit 1; }
known="$(commands "$table")"

# What #711 compared and decided not to add or list.
left_out='spec[ -]?kit|openspec|bmad|superpowers|taskmaster|everything-claude-code|claude-mem|context7|security-guidance|frontend-design'

fail=0
for f in "$@"; do
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    grep -qxF -- "$c" <<<"$known" || { echo "  FAIL  $f names $c, which is not in the arsenal's table"; fail=1; }
  done < <(commands "$f")
  while IFS= read -r w; do
    echo "  FAIL  $f names $w, a tool #711 left out of plinth"; fail=1
  done < <(grep -oiE "$left_out" "$f" | sort -u)
done
exit "$fail"
