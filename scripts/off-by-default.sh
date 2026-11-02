#!/usr/bin/env bash
# What a project made by plinth starts with off (#763), read from the one
# list, docs/reference/off-by-default.md, for new-project.sh's last lines and
# for /plinth:guide. Read-only.
#
#   off-by-default.sh <archetype>          # every item for that archetype, "off: ..."
#   off-by-default.sh <archetype> <dir>    # minus what <dir> already has; an item
#                                          # with no sign there "started off"
#   off-by-default.sh --new <archetype> <dir>  # a project rendered just now: minus
#                                          # what <dir> has, the rest "off:", or
#                                          # "now:" for a step to take right away
#   off-by-default.sh --check              # every docs/ Steps page, and its #anchor, exists (exit 1 if not)
#   off-by-default.sh --project-phrases    # "<project file>\t<phrase>" per project-file item
#
# A list with no rows, or a row this script cannot read, is an error (exit 1),
# never an empty answer. A row whose last cell names a path is told only for
# a project directory that has that path (#765).
set -uo pipefail
plugin="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
list="${PLINTH_OFF_BY_DEFAULT:-$plugin/docs/reference/off-by-default.md}"
docs_url="https://github.com/coolbress/plinth/blob/main"
usage="usage: off-by-default.sh <archetype> [<project dir>] | --new <archetype> <project dir> | --check | --project-phrases"
[ $# -ge 1 ] || { echo "$usage" >&2; exit 2; }

# The table's rows under "## The list", header and separator dropped; six
# cells each, tab-separated.
rows="$(awk '/^## The list/{on=1; next} on && /^## /{exit} on && /^\| /' "$list" 2>/dev/null | tail -n +3 |
  awk -F ' \\| ' 'NF == 6 { sub(/^\| /, "", $1); sub(/ \|$/, "", $6); print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6; next }
                  { print "BAD\t" $0 }')"
[ -n "$rows" ] || { echo "off-by-default: no rows under '## The list' in $list" >&2; exit 1; }
if grep -q '^BAD' <<<"$rows"; then
  echo "off-by-default: a row of $list does not have six cells:" >&2; grep '^BAD' <<<"$rows" | cut -f2- >&2; exit 1
fi

# steps <cell>: "page <path>[#<anchor>]", "file <path>\t<phrase>", or "bad".
steps() {
  local c="$1"
  if [[ "$c" =~ ^\`(docs/[^\`#]+\.md(#[a-z0-9-]+)?)\`$ ]]; then echo "page ${BASH_REMATCH[1]}"
  elif [[ "$c" =~ ^\`([^\`]+)\`\ \"([^\"]+)\"$ ]]; then printf 'file %s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  else echo bad; fi
}

case "$1" in
  --check)
    failed=0
    while IFS=$'\t' read -r feature _ _ cell _ _; do
      s="$(steps "$cell")"
      case "$s" in
        "page "*)
          page="${s#page }"; anchor=""; [[ "$page" == *"#"* ]] && { anchor="${page#*#}"; page="${page%%#*}"; }
          if [ ! -f "$plugin/$page" ]; then echo "off-by-default: '$feature' points to $page, which does not exist" >&2; failed=1
          elif [ -n "$anchor" ] && ! grep -E '^#+ ' "$plugin/$page" | sed -E 's/^#+ //' | tr '[:upper:]' '[:lower:]' |
                 sed -E 's/[^a-z0-9 -]//g; s/ /-/g' | grep -qxF -- "$anchor"; then
            echo "off-by-default: '$feature' points to $page#$anchor, a heading that page does not have" >&2; failed=1
          fi ;;
        "file "*) ;;
        *) echo "off-by-default: '$feature' has Steps '$cell', neither \`docs/….md\` nor \`<file>\` \"<phrase>\"" >&2; failed=1 ;;
      esac
    done <<<"$rows"
    exit "$failed" ;;
  --project-phrases)
    while IFS=$'\t' read -r _ _ _ cell _ _; do
      s="$(steps "$cell")"; [ "${s%% *}" = file ] && echo "${s#file }"
    done <<<"$rows"
    exit 0 ;;
  --new) [ $# -eq 3 ] || { echo "$usage" >&2; exit 2; }; new=1; shift ;;
  -*) echo "$usage" >&2; exit 2 ;;
esac

archetype="$1"; dir="${2:-}"; new="${new:-0}"
while IFS=$'\t' read -r feature archetypes when cell sign needs; do
  [ "$archetypes" = all ] || [[ ",${archetypes// /}," == *",$archetype,"* ]] || continue
  needs="${needs//\`/}"
  if [ "$needs" != - ]; then [ -n "$dir" ] && [ -e "$dir/$needs" ] || continue; fi
  s="$(steps "$cell")"
  case "$s" in
    "page "*) where="$docs_url/${s#page }" ;;
    "file "*) f="${s#file }"; where="the steps are in ${f%%$'\t'*} under \"${f#*$'\t'}\"" ;;
    *) echo "off-by-default: '$feature' has Steps '$cell' in neither form (run --check)" >&2; exit 1 ;;
  esac
  prefix="off:"; now=0
  case "$when" in "now: "*) now=1; prefix="now:"; when="${when#now: }" ;; esac
  if [ -n "$dir" ]; then
    sign="${sign//\`/}"
    if [ "$sign" = - ]; then
      if [ "$new" != 1 ]; then
        if [ "$now" = 1 ]; then prefix="to do, if not done yet (whether it is done is not read):"
        else prefix="started off (whether it is on now is not read):"; fi
      fi
    elif [ -e "$dir/$sign" ]; then continue; fi
  fi
  # A step to take now says the step, then what happens until it is done.
  if [ "$now" = 1 ]; then
    echo "$prefix $feature. $(tr '[:lower:]' '[:upper:]' <<<"${when:0:1}")${when:1}. The steps: $where"
  else
    echo "$prefix $feature. Turn it on when $when: $where"
  fi
done <<<"$rows"
