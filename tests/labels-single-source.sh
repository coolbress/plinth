#!/usr/bin/env bash
# One label list. The door creates them and the checker reports what a
# repository is missing; #78 happened because those were two lists and one of
# them was two names short. A third reader is the CI download: python-ci.yml
# fetches the checker and its data at `job.workflow_sha`, so a file the checker
# reads and the workflow does not fetch dies in every consumer's CI.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

f="$root/labels.txt"
[ -f "$f" ] && ok "labels.txt exists" || { bad "labels.txt missing"; echo "-- $pass passed, $fail failed"; exit 1; }

names="$(grep -vE '^[[:space:]]*(#|$)' "$f" | cut -d'|' -f1)"
n="$(wc -l <<<"$names" | tr -d ' ')"
[ "$n" -ge 20 ] && ok "labels.txt lists $n labels" || bad "labels.txt lists only $n"

# Three fields on every line, and a six-digit hex colour: the door passes the
# second field to `gh label create --color`, which refuses anything else.
bad_lines="$(grep -vE '^[[:space:]]*(#|$)' "$f" | grep -vcE '^[^|]+\|[0-9a-f]{6}\|[^|]+$')"
[ "$bad_lines" = 0 ] && ok "every line is name|6-hex-colour|description" || bad "$bad_lines lines are malformed"

dupes="$(sort <<<"$names" | uniq -d)"
[ -z "$dupes" ] && ok "no duplicate label" || bad "duplicates: $dupes"

# The two readers.
grep -q 'labels\.txt' "$root/scripts/new-project.sh" \
  && ok "the door reads labels.txt" || bad "the door does not read labels.txt"
grep -q 'labels\.txt' "$root/scripts/floor-check.py" \
  && ok "the checker reads labels.txt" || bad "the checker does not read labels.txt"
grep -qE 'for f in .*labels\.txt' "$root/.github/workflows/python-ci.yml" \
  && ok "python-ci.yml downloads labels.txt with the checker" \
  || bad "python-ci.yml does not download labels.txt: the checker would die in every consumer's CI"

# Labels belong to issues. `contents: read` alone makes the label read an API
# error, which the checker reports as "not verified" -- so the check would never
# run in the one place it matters, and nothing would say so.
awk '/^  floor-check:/,/steps:/' "$root/.github/workflows/python-ci.yml" | grep -q 'issues: read' \
  && ok "the floor-check job can read labels (issues: read)" \
  || bad "the floor-check job lacks issues: read; the label check would always report 'not verified' in consumer CI"
# A called workflow cannot widen what its caller grants, so the grant above is
# capped unless the caller makes it too. This repository's canary is the caller
# that proves the check runs at all.
awk '/^  canary:/,/with:/' "$root/.github/workflows/ci.yml" | grep -q 'issues: read' \
  && ok "the canary caller grants issues: read, so the job's grant is not capped" \
  || bad "the canary caller caps the grant; the label check would never run even here"

# Neither reader may carry its own copy of the names.
for n in wayfinder:prototype ready-for-agent; do
  if grep -q "$n" "$root/scripts/new-project.sh" || grep -q "$n" "$root/scripts/floor-check.py"; then
    bad "$n is hard-coded in a reader; the list is labels.txt"
  else ok "$n is not hard-coded in a reader"; fi
done

# Every wayfinder kind docs/agents/issue-tracker.md names has a line.
for kind in map research grilling prototype task; do
  grep -qx "wayfinder:$kind" <<<"$names" && ok "wayfinder:$kind is listed" || bad "wayfinder:$kind is missing"
done

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
