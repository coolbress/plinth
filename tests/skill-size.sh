#!/usr/bin/env bash
# Every shipped skill stays within the size Claude Code's skill guidance
# recommends and carries no issue numbers, which mean nothing on a user's
# machine:
#
#   - each skills/*/SKILL.md is at most 500 lines and 20,000 bytes;
#   - it has no issue number (`#` and digits not after a letter or a slash);
#   - a reference file beside it (skills/*/*.md other than SKILL.md) over 100
#     lines opens with a `## Contents` list within its first 10 lines.
#
# A skill whose trim is another ticket's is a listed exception below, naming
# that ticket; the ticket carries a criterion that removes its line here.
# Optional first argument: another plugin root to read (the test's own cases).
set -uo pipefail
root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
max_lines=500
max_bytes=20000
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

# skill<TAB>ticket that trims it and removes this line
exceptions='arsenal	coolbress/plinth#1086
floor-check	coolbress/plinth#1105'

found=0
for f in "$root"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  found=$((found+1))
  name="$(basename "$(dirname "$f")")"
  rel="skills/$name/SKILL.md"
  lines="$(wc -l < "$f" | tr -d ' ')"
  bytes="$(wc -c < "$f" | tr -d ' ')"
  numbers="$(grep -cE '(^|[^/A-Za-z])#[0-9]+' "$f")"
  ticket="$(printf '%s\n' "$exceptions" | awk -F '\t' -v n="$name" '$1 == n { print $2 }')"
  if [ -n "$ticket" ]; then
    ok "$rel: an exception until $ticket ($lines lines, $bytes bytes, $numbers issue numbers)"
    continue
  fi
  if [ "$lines" -le "$max_lines" ] && [ "$bytes" -le "$max_bytes" ]
  then ok "$rel: $lines lines, $bytes bytes"
  else bad "$rel: $lines lines and $bytes bytes; the limits are $max_lines lines and $max_bytes bytes: move reference one level down, beside it"; fi
  if [ "$numbers" = 0 ]
  then ok "$rel: no issue numbers"
  else bad "$rel: $numbers lines carry an issue number; a source goes under docs/reference/, not into the skill:"
       grep -nE '(^|[^/A-Za-z])#[0-9]+' "$f" | cut -c1-120 | sed 's/^/        /'; fi
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
