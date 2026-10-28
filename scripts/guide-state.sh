#!/usr/bin/env bash
# What /plinth:guide reads (#710): the repository's state, the row of the
# arsenal's "Where you are, and what to do next" table that state points to,
# and the table itself. Read-only: it runs git and gh reads, nothing else.
#
#   guide-state.sh [<dir>]     # default: the current directory
#
# The rows are copied from skills/arsenal/SKILL.md as they stand, never from
# a list of its own, so the guide cannot name a step or tool the table does
# not have. A row it looks for and does not find is an error (exit 1), not a
# guess. Issue and pull request titles are printed as they are: data.
set -uo pipefail
plugin="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
arsenal="$plugin/skills/arsenal/SKILL.md"
dir="${1:-.}"

# The table names files under ${CLAUDE_PLUGIN_ROOT}; the person gets the path.
table="$(awk '/^## Where you are, and what to do next/{on=1; next} on && /^## /{exit} on && /^\| /' "$arsenal" |
  awk -v r="$plugin" '{ gsub(/\$\{CLAUDE_PLUGIN_ROOT\}/, r); print }')"
[ -n "$table" ] || { echo "guide-state: no table under 'Where you are, and what to do next' in $arsenal" >&2; exit 1; }

# row <start of the "Where you are" cell>: the row's three cells, one per line.
row() {
  local r
  r="$(printf '%s\n' "$table" | awk -v p="| $1" 'index($0, p) == 1' | head -1)"
  [ -n "$r" ] || { echo "guide-state: the arsenal's table has no row starting '$1'" >&2; return 1; }
  printf '%s\n' "$r" | awk -F ' \\| ' '{ sub(/^\| /, "", $1); sub(/ \|$/, "", $3); print $1; print $2; print $3 }'
}

# say <row start> <command> [<then: row start>]: the verdict block. The
# command is typed as printed; $before (typed first) and $note go with it.
before=""; note=""
say() {
  local cells after
  cells="$(row "$1")" || exit 1
  echo "where: $(sed -n 1p <<<"$cells")"
  echo "next: $(sed -n 2p <<<"$cells")"
  echo "tool: $(sed -n 3p <<<"$cells")"
  [ -z "$before" ] || echo "before: $before"
  echo "command: $2"
  [ -z "$note" ] || echo "note: $note"
  if [ -n "${3:-}" ]; then
    after="$(row "$3")" || exit 1
    echo "then: $(sed -n 1p <<<"$after") -> $(sed -n 3p <<<"$after")"
  fi
}

finish() {
  echo
  echo "table:"
  printf '%s\n' "$table"
  exit 0
}

echo "plinth guide state (read-only)"

if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
  echo "repository: none here (not a git checkout)"
  echo
  say "No repository yet" "/plinth:new-project <owner>/<name>"
  finish
fi
top="$(git -C "$dir" rev-parse --show-toplevel)"
answers="$top/.copier-answers.yml"
answer() { sed -nE "s/^$1: *['\"]?([^'\"]*)['\"]? *\$/\\1/p" "$answers" 2>/dev/null | head -1; }

if [ ! -f "$answers" ]; then
  echo "made by plinth: no (no .copier-answers.yml)"
  echo
  say "A repository plinth did not make" "/plinth:floor-check"
  finish
fi
archetype="$(answer archetype)"; hosting="$(answer hosting)"; place="$(answer hosting_elsewhere)"
echo "made by plinth: yes, template $(answer _commit)"
echo "archetype: ${archetype:-not recorded}"
[ "$archetype" = web ] && echo "hosting: ${hosting:-render (no answer recorded)}${place:+ ($place)}"

if [ "$(answer host)" = gitlab ]; then
  echo "repository: GitLab; the guide reads GitHub only, so issues and merge requests were not read"
  echo
  echo "where: not read"
  finish
fi

if ! repo="$(cd "$top" && gh repo view --json nameWithOwner --jq .nameWithOwner 2>&1)"; then
  echo "repository: not read ($(head -1 <<<"$repo"))"
  echo
  echo "where: not read"
  finish
fi
echo "repository: $repo"

# A check run has status and conclusion; a commit status has only state.
rollup='def checks: [.statusCheckRollup[]? | (.conclusion // .state // "") as $c | (.status // "COMPLETED") as $s
  | if $s != "COMPLETED" or ($c | IN("PENDING", "EXPECTED", "QUEUED", "IN_PROGRESS", "")) then "pending"
    elif ($c | IN("SUCCESS", "NEUTRAL", "SKIPPED")) then "pass" else "fail" end]
  | if length == 0 then "none" elif any(. == "fail") then "fail" elif any(. == "pending") then "pending" else "pass" end;'
bot='(.author.is_bot // false) or (.author.login // "" | startswith("app/"))'
clean='gsub("[\t\n]"; " ")'

if ! prs="$(cd "$top" && gh pr list --state open --limit 100 \
      --json number,title,isDraft,author,headRefOid,statusCheckRollup \
      --jq "$rollup"' sort_by(.number) | .[] | [.number, (if '"$bot"' then "bot" else "person" end), (if .isDraft then "draft" else "ready" end), checks, .headRefOid, (.title | '"$clean"')] | @tsv' 2>&1)" ||
   ! merged="$(cd "$top" && gh pr list --state merged --limit 100 --json number,title,mergedAt,author \
      --jq 'sort_by(.mergedAt) | reverse | .[] | [.number, (if '"$bot"' then "bot" else "person" end), (.mergedAt[0:10]), (.title | '"$clean"')] | @tsv' 2>&1)" ||
   ! issues="$(cd "$top" && gh issue list --state open --limit 100 --json number,title,labels \
      --jq 'sort_by(.number) | .[] | [.number, ([.labels[].name] | join(",")), (.title | '"$clean"')] | @tsv' 2>&1)"; then
  echo "issues and pull requests: not read ($(tail -1 <<<"$prs$merged$issues"))"
  echo
  echo "where: not read"
  finish
fi

field() { cut -f"$1"; }
people_prs="$(awk -F '\t' '$2 == "person"' <<<"$prs")"
bot_prs="$(awk -F '\t' '$2 == "bot"' <<<"$prs")"
people_merged="$(awk -F '\t' '$2 == "person"' <<<"$merged" | grep -c . || true)"

if [ -n "$people_prs" ]; then
  echo "open pull requests:"
  awk -F '\t' '{ printf "  #%s %s, checks %s: %s\n", $1, $3, $4, $6 }' <<<"$people_prs"
else
  echo "open pull requests: none"
fi
[ -n "$bot_prs" ] && echo "open Dependabot pull requests: $(field 1 <<<"$bot_prs" | sed 's/^/#/' | paste -sd ' ' -)"
if [ -n "$issues" ]; then
  echo "open issues ($(grep -c . <<<"$issues")):"
  head -10 <<<"$issues" | awk -F '\t' '{ printf "  #%s [%s] %s\n", $1, ($2 == "" ? "no label" : $2), $3 }'
else
  echo "open issues: none"
fi
if [ -n "$merged" ]; then
  last="$(head -1 <<<"$merged")"
  echo "last merge: #$(field 1 <<<"$last") on $(field 3 <<<"$last") by $(field 2 <<<"$last"): $(field 4 <<<"$last")"
else
  echo "last merge: none"
fi
echo "first pull request merged: $([ "$people_merged" -gt 0 ] && echo yes || echo no) ($people_merged merged by people)"
echo

labelled() { awk -F '\t' -v l="$1" '("," $2 ",") ~ ("," l ",")' <<<"$issues" | head -1 | field 1; }
if [ "$people_merged" -eq 0 ]; then
  first="$(awk -F '\t' 'index($6, "docs: first pull request") == 1' <<<"$people_prs" | head -1)"
  [ -n "$first" ] || first="$(head -1 <<<"$people_prs")"
  if [ -n "$first" ]; then
    n="$(field 1 <<<"$first")"; sha="$(field 5 <<<"$first")"
    say "Repository made, its first pull request open" \
      "body=\"\$(gh pr view $n --json body --jq .body)\" && gh pr merge $n --squash --match-head-commit $sha --body \"\$body\"" \
      "First pull request merged"
  else
    say "Repository made, its first pull request open" "none: no pull request is open; open the repository's pull requests page"
  fi
elif [ -n "$people_prs" ]; then
  # A red check does not turn green by waiting: that is something broke.
  pr="$(awk -F '\t' '$4 == "fail"' <<<"$people_prs" | head -1)"
  if [ -n "$pr" ]; then
    n="$(field 1 <<<"$pr")"
    note="pull request #$n has a failing check; the agent reads its log, reproduces it and fixes the code, not the check"
    say "Something broke" "diagnose this: pull request #$n has a failing check"
  else
    n="$(head -1 <<<"$people_prs" | field 1)"
    note="pull request #$n, checks $(head -1 <<<"$people_prs" | field 4); /run once they are green"
    say "A pull request with checks running" "/run" "Green, and seen working"
  fi
elif n="$(labelled ready-for-agent)" && [ -n "$n" ]; then
  before="/clear"; say "A ticket ready" "/implement #$n"
elif n="$(labelled needs-triage)" && [ -n "$n" ]; then
  note="issue #$n"; say "Something broke" "/triage"
elif [ -n "$issues" ]; then
  before="/clear"; say "A ticket ready" "/implement #$(head -1 <<<"$issues" | field 1)"
elif [ "$people_merged" -eq 1 ]; then
  say "First pull request merged" "none: three pages to follow, in order (the tool cell)" "An idea in your own words"
elif [ -n "$bot_prs" ]; then
  say "Between pieces of work" "/plinth:floor-check (then the Dependabot pull requests, one at a time, on green)"
else
  say "An idea in your own words" "/grilling"
fi
finish
