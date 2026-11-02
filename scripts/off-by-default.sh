#!/usr/bin/env bash
# What a project made by plinth starts with off (#763), read from the one
# list, docs/reference/off-by-default.md, for new-project.sh's last lines and
# for /plinth:guide. Read-only.
#
#   off-by-default.sh <archetype>          # every item for that archetype, "off: ..."
#   off-by-default.sh <archetype> <dir>    # minus what <dir> already has; an item
#                                          # with no sign there "started off"
#   off-by-default.sh --new <archetype> <dir>  # a project rendered just now: minus
#                                          # what <dir> has, the rest "off:"
#   off-by-default.sh --check              # every docs/ Steps page exists (exit 1 if not)
#   off-by-default.sh --project-phrases    # "<project file>\t<phrase>" per project-file item
#
# A list with no rows, or a row this script cannot read, is an error (exit 1),
# never an empty answer.
set -uo pipefail
plugin="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
list="${PLINTH_OFF_BY_DEFAULT:-$plugin/docs/reference/off-by-default.md}"
docs_url="https://github.com/coolbress/plinth/blob/main"
usage="usage: off-by-default.sh <archetype> [<project dir>] | --new <archetype> <project dir> | --check | --project-phrases"
[ $# -ge 1 ] || { echo "$usage" >&2; exit 2; }

# The table's rows under "## The list", header and separator dropped; five
# cells each, tab-separated.
rows="$(awk '/^## The list/{on=1; next} on && /^## /{exit} on && /^\| /' "$list" 2>/dev/null | tail -n +3 |
  awk -F ' \\| ' 'NF == 5 { sub(/^\| /, "", $1); sub(/ \|$/, "", $5); print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5; next }
                  { print "BAD\t" $0 }')"
[ -n "$rows" ] || { echo "off-by-default: no rows under '## The list' in $list" >&2; exit 1; }
if grep -q '^BAD' <<<"$rows"; then
  echo "off-by-default: a row of $list does not have five cells:" >&2; grep '^BAD' <<<"$rows" | cut -f2- >&2; exit 1
fi

# steps <cell>: "page <path>", "file <path>\t<phrase>", or "bad".
steps() {
  local c="$1"
  if [[ "$c" =~ ^\`(docs/[^\`]+\.md)\`$ ]]; then echo "page ${BASH_REMATCH[1]}"
  elif [[ "$c" =~ ^\`([^\`]+)\`\ \"([^\"]+)\"$ ]]; then printf 'file %s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  else echo bad; fi
}

case "$1" in
  --check)
    failed=0
    while IFS=$'\t' read -r feature _ _ cell _; do
      s="$(steps "$cell")"
      case "$s" in
        "page "*) [ -f "$plugin/${s#page }" ] || { echo "off-by-default: '$feature' points to ${s#page }, which does not exist" >&2; failed=1; } ;;
        "file "*) ;;
        *) echo "off-by-default: '$feature' has Steps '$cell', neither \`docs/….md\` nor \`<file>\` \"<phrase>\"" >&2; failed=1 ;;
      esac
    done <<<"$rows"
    exit "$failed" ;;
  --project-phrases)
    while IFS=$'\t' read -r _ _ _ cell _; do
      s="$(steps "$cell")"; [ "${s%% *}" = file ] && echo "${s#file }"
    done <<<"$rows"
    exit 0 ;;
  --new) [ $# -eq 3 ] || { echo "$usage" >&2; exit 2; }; new=1; shift ;;
  -*) echo "$usage" >&2; exit 2 ;;
esac

archetype="$1"; dir="${2:-}"; new="${new:-0}"
while IFS=$'\t' read -r feature archetypes when cell sign; do
  [ "$archetypes" = all ] || [[ ",${archetypes// /}," == *",$archetype,"* ]] || continue
  s="$(steps "$cell")"
  case "$s" in
    "page "*) where="$docs_url/${s#page }" ;;
    "file "*) f="${s#file }"; where="the steps are in ${f%%$'\t'*} under \"${f#*$'\t'}\"" ;;
    *) echo "off-by-default: '$feature' has Steps '$cell' in neither form (run --check)" >&2; exit 1 ;;
  esac
  prefix="off:"
  if [ -n "$dir" ]; then
    sign="${sign//\`/}"
    if [ "$sign" = - ]; then [ "$new" = 1 ] || prefix="started off (whether it is on now is not read):"
    elif [ -e "$dir/$sign" ]; then continue; fi
  fi
  echo "$prefix $feature. Turn it on when $when: $where"
done <<<"$rows"
