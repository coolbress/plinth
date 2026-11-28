#!/usr/bin/env bash
# Every shipped skill stays within the size Claude Code's skill guidance
# recommends and carries no issue numbers, which mean nothing on a user's
# machine:
#
#   - each skills/*/SKILL.md is at most 500 lines and 20,000 bytes, and the
#     arsenal's at most 250 lines and 12,000 bytes: it loads on every call
#     an agent makes to choose a tool;
#   - AGENTS.md is at most 110 lines and 7,500 bytes, so rule text does not
#     grow back one incident at a time;
#   - it has no issue number (`#` and digits not after a letter or a slash;
#     a link's own anchor, `](#1-the-host)`, is not one);
#   - what one invocation reads, SKILL.md and every file its body says to
#     read before acting (tests/lib/skill_reads.py finds them by the words
#     "read it before", not "only when"), is at most that skill's
#     READS_<NAME>_MAX_BYTES, and those files carry no issue number either;
#   - its description is at most DESCRIPTION_<NAME>_MAX_BYTES;
#   - a reference file beside it (skills/*/*.md other than SKILL.md) over 100
#     lines opens with a `## Contents` list within its first 10 lines.
#
# A skill whose trim is another ticket's is a listed exception below, naming
# that ticket; the ticket carries a criterion that removes its line here.
# The numbers are in tests/size_caps.py, which says why they are not here.
# Optional first argument: another plugin root to read
# (tests/skill-size-cases.sh); its tests/size_caps.py is read.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="${1:-$(cd "$here/.." && pwd)}"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

# A cap that cannot be read stops the test: an empty one would hold nothing.
# So does a name set twice: a raise by an added line loses no line, and
# ci / diff-size lists only a test file that lost lines.
cap() {
  local v
  v="$(sed -n "s/^$1 = \([0-9][0-9]*\)\$/\1/p" "$root/tests/size_caps.py" 2>/dev/null)"
  [ -n "$v" ] || { echo >&2 "  FAIL  no '$1 = <number>' line in $root/tests/size_caps.py"; exit 1; }
  [ "$(printf '%s\n' "$v" | wc -l | tr -d ' ')" = 1 ] \
    || { echo >&2 "  FAIL  $1 is set more than once in $root/tests/size_caps.py: change its one line"; exit 1; }
  printf '%s\n' "$v"
}
max_lines="$(cap SKILL_MAX_LINES)" || exit 1
max_bytes="$(cap SKILL_MAX_BYTES)" || exit 1
arsenal_lines="$(cap ARSENAL_MAX_LINES)" || exit 1
arsenal_bytes="$(cap ARSENAL_MAX_BYTES)" || exit 1
agents_lines="$(cap AGENTS_MAX_LINES)" || exit 1
agents_bytes="$(cap AGENTS_MAX_BYTES)" || exit 1

# AGENTS.md: CLAUDE.md is a link to it, so one file holds both.
if [ -f "$root/AGENTS.md" ]; then
  lines="$(wc -l < "$root/AGENTS.md" | tr -d ' ')"
  bytes="$(wc -c < "$root/AGENTS.md" | tr -d ' ')"
  if [ "$lines" -le "$agents_lines" ] && [ "$bytes" -le "$agents_bytes" ]
  then ok "AGENTS.md: $lines lines, $bytes bytes"
  else bad "AGENTS.md: $lines lines and $bytes bytes; the caps are $agents_lines lines and $agents_bytes bytes: make the incident a check, not a sentence (CONTRIBUTING.md, \"After something goes wrong\")"; fi
else
  bad "no AGENTS.md under $root: its size was not checked"
fi

# issue_lines <file>: its lines that carry an issue number, numbered; a
# link's anchor to a heading that starts with a digit is not one.
issue_lines() { sed 's/](#[^)]*)/]()/g' "$1" | grep -nE '(^|[^/A-Za-z])#[0-9]+'; }

# reads_skill <name> <skills/<name>/SKILL.md>: what one invocation reads,
# against its cap; the description against its own; the files read carry no
# issue number; the files named but not read are listed.
reads_skill() {
  local key total listed got p reads_cap desc_cap desc numbers
  key="$(printf '%s' "$1" | tr 'a-z-' 'A-Z_')"
  reads_cap="$(cap "READS_${key}_MAX_BYTES")" || exit 1
  desc_cap="$(cap "DESCRIPTION_${key}_MAX_BYTES")" || exit 1
  got="$(python3 "$here/lib/skill_reads.py" "$root" "$2" 2>&1)" || { bad "$2: what it reads was not read: $(tail -1 <<<"$got")"; return; }
  total="$(wc -c < "$root/$2" | tr -d ' ')"; listed="SKILL.md"
  while IFS=$'\t' read -r kind p; do
    [ "$kind" = read ] || continue
    total=$((total + $(wc -c < "$root/$p" | tr -d ' '))); listed="$listed + ${p#skills/"$1"/}"
    numbers="$(issue_lines "$root/$p" | grep -c . || true)"
    if [ "$numbers" = 0 ]; then ok "$p, read with $1: no issue numbers"
    else bad "$p, read with $1: $numbers lines carry an issue number:"; issue_lines "$root/$p" | cut -c1-120 | sed 's/^/        /'; fi
  done <<<"$got"
  if [ "$total" -le "$reads_cap" ]; then ok "$1 reads $total bytes per invocation ($listed), the cap $reads_cap"
  else bad "$1 reads $total bytes per invocation ($listed); the cap is $reads_cap: moving text into a file it reads first lowers nothing"; fi
  not_read="$(awk -F '\t' '$1 == "optional" { print $2 }' <<<"$got" | paste -sd ' ' -)"
  ok "$1: named, not read before acting: ${not_read:-none}"
  desc="$(awk -F '\t' '$1 == "description" { print $2 }' <<<"$got")"
  if [ -n "$desc" ] && [ "$desc" -le "$desc_cap" ]; then ok "$1: description $desc bytes, the cap $desc_cap"
  else bad "$1: description ${desc:-not found} bytes; the cap is $desc_cap: it is read on every turn"; fi
}

# skill<TAB>ticket that trims it and removes this line
exceptions=''

found=0
for f in "$root"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  found=$((found+1))
  name="$(basename "$(dirname "$f")")"
  rel="skills/$name/SKILL.md"
  lines="$(wc -l < "$f" | tr -d ' ')"
  bytes="$(wc -c < "$f" | tr -d ' ')"
  numbers="$(issue_lines "$f" | grep -c . || true)"
  ticket="$(printf '%s\n' "$exceptions" | awk -F '\t' -v n="$name" '$1 == n { print $2 }')"
  if [ -n "$ticket" ]; then
    ok "$rel: an exception until $ticket ($lines lines, $bytes bytes, $numbers issue numbers)"
    continue
  fi
  limit_lines="$max_lines"; limit_bytes="$max_bytes"
  [ "$name" != arsenal ] || { limit_lines="$arsenal_lines"; limit_bytes="$arsenal_bytes"; }
  if [ "$lines" -le "$limit_lines" ] && [ "$bytes" -le "$limit_bytes" ]
  then ok "$rel: $lines lines, $bytes bytes"
  else bad "$rel: $lines lines and $bytes bytes; the limits are $limit_lines lines and $limit_bytes bytes: move reference one level down, beside it"; fi
  if [ "$numbers" = 0 ]
  then ok "$rel: no issue numbers"
  else bad "$rel: $numbers lines carry an issue number; a source goes under docs/reference/, not into the skill:"
       issue_lines "$f" | cut -c1-120 | sed 's/^/        /'; fi
  reads_skill "$name" "$rel"
done
if [ "$found" -gt 0 ]; then ok "$found skills read"
else bad "no skills/*/SKILL.md under $root: nothing was checked"; fi

# Each exception still names a skill that exists, so a renamed or trimmed
# one does not keep an exception it no longer needs unseen.
while IFS="$(printf '\t')" read -r name ticket; do
  [ -n "$name" ] || continue
  if [ -f "$root/skills/$name/SKILL.md" ]; then ok "the exception for $name names a skill that exists"
  else bad "the exception for $name ($ticket) names no skill: remove its line"; fi
done <<<"$exceptions"

for f in "$root"/skills/*/*.md; do
  [ -f "$f" ] || continue
  [ "$(basename "$f")" = SKILL.md ] && continue
  rel="${f#"$root"/}"
  lines="$(wc -l < "$f" | tr -d ' ')"
  [ "$lines" -gt 100 ] || { ok "$rel: $lines lines, no contents list needed"; continue; }
  if head -n 10 "$f" | grep -qx '## Contents'
  then ok "$rel: $lines lines, opens with a contents list"
  else bad "$rel: $lines lines and no '## Contents' in its first 10 lines"; fi
done

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
