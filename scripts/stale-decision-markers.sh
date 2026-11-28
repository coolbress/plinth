#!/usr/bin/env bash
# The decisions page's `(decided; not built yet: <ref>)` markers whose issue
# is closed (#1221). The marker comes off in the pull request that finishes
# building the decision (docs/reference/decisions-in-force.md); this finds the
# ones left behind, so a release does not publish a page that says a decision
# is not built when its issue says it is.
#
#   scripts/stale-decision-markers.sh [<page>]    (default: the decisions page)
#
# Each <ref> is `#N` (this repository, coolbress/plinth) or `owner/repo#N`; a
# marker may name several, comma-separated. Each issue is read once with gh:
#   - closed as completed: stale. Its line is printed; the exit is 1.
#   - closed any other way (not planned, a duplicate): printed as a question
#     for a person (does the decision still hold, and what builds it?), never
#     a failure: only a person can answer it.
#   - open: the marker stands; not printed.
# An issue gh cannot read is printed and exits 2: a marker that was not read
# is not passed. Exit 0 when every marker's issue is open (or only needs a
# person), with one line saying how many were read. Reads GitHub only.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
page="${1:-$root/docs/reference/decisions-in-force.md}"
[ -f "$page" ] || { echo "stale-decision-markers: no page at $page" >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "stale-decision-markers: gh is not installed; it reads each marker's issue" >&2; exit 2; }

# line<TAB>ref, one per ref a marker names; the page's own example (`#N`) has no number and is not one.
refs="$(awk '{
  s = $0
  while (match(s, /not built yet: [^)]*\)/)) {
    inner = substr(s, RSTART + 15, RLENGTH - 16); s = substr(s, RSTART + RLENGTH)
    n = split(inner, parts, /, */)
    for (i = 1; i <= n; i++) if (parts[i] ~ /^([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)?#[0-9]+$/) print NR "\t" parts[i]
  }
}' "$page")"

stale=0; unread=0; person=0; read_n=0; seen=""
while IFS=$'\t' read -r line ref; do
  [ -n "$ref" ] || continue
  case "$ref" in
    \#*) repo="coolbress/plinth"; n="${ref#\#}" ;;
    *)   repo="${ref%#*}"; n="${ref##*#}" ;;
  esac
  key="$repo#$n"
  # One read per issue: `<key> <state>` lines, looked up as fixed text.
  state="$(awk -v k="$key" '$1 == k { print $2; exit }' <<<"$seen")"
  if [ -z "$state" ]; then
    state="$(gh issue view "$n" --repo "$repo" --json state,stateReason -q '"\(.state):\(.stateReason // "")"' 2>/dev/null)" || state=""
    [ -n "$state" ] || state="UNREAD"
    seen="$seen"$'\n'"$key $state"; read_n=$((read_n + 1))
  fi
  case "$state" in
    OPEN:*) ;;
    CLOSED:COMPLETED)
      stale=$((stale + 1))
      echo "stale: line $line: $ref is closed as completed; remove its marker, and say so in the pull request (docs/agents/issue-tracker.md#closing-an-issue)" ;;
    CLOSED:*)
      person=$((person + 1))
      echo "for a person: line $line: $ref is closed (${state#CLOSED:}), not completed: does the decision still hold, and what builds it? Not a failure." ;;
    *)
      unread=$((unread + 1))
      echo "not read: line $line: $ref (gh issue view failed); the marker is not passed" ;;
  esac
done <<<"$refs"

total="$(grep -c . <<<"$refs" || true)"
if [ "$unread" -gt 0 ]; then
  echo "stale-decision-markers: $unread of $total marker reference(s) not read in $(basename "$page")" >&2; exit 2
elif [ "$stale" -gt 0 ]; then
  echo "stale-decision-markers: $stale stale marker(s) in $(basename "$page"); remove each before the release" >&2; exit 1
fi
also=""; [ "$person" = 0 ] || also=", $person for a person (above)"
echo "stale-decision-markers: $total marker reference(s), $read_n issue(s) read: none closed as completed$also"
