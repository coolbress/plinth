#!/usr/bin/env bash
# What /plinth:guide reads (#710): the repository's state, what it started
# with off (#763), the row of the arsenal's "Where you are, and what to do
# next" table that state points to, the reasons it may give (#834), and the
# table: on `map` every row, otherwise only the rows of the step the project
# is at and the step after it (#1060), whose cells the guide explains. For a pull request with a failing check it names the checks
# that failed, whose each one is, and how many comments people left (#903).
# It says whether the template tag and the plinth pin are behind, from
# floor-check's own reads (#904). For an open spec it reads whether any
# ticket was cut from it, and routes one with none to step 3 (#909). It picks
# the ticket /implement takes by the rules below, and says why (#910). It
# picks how much of the way the guide explains (#908): `mode: full` before a
# person's pull request has merged, when asked for the map, or when the state
# was not read; `mode: focused` otherwise, which lists only what is worth
# doing now of what started off.
# Read-only: it runs git and gh reads, nothing else.
#
#   guide-state.sh [<dir>] [map]   # default: the current directory; map: the whole way, every row
#
# The rows are copied from skills/arsenal/SKILL.md as they stand, never from
# a list of its own, so the guide cannot name a step or tool the table does
# not have. A row it looks for and does not find is an error (exit 1), not a
# guess. Issue and pull request titles are printed as they are: data.
set -uo pipefail
plugin="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/admin-reach.sh
. "$plugin/scripts/lib/admin-reach.sh" 2>/dev/null || { echo "guide-state: no $plugin/scripts/lib/admin-reach.sh" >&2; exit 1; }
arsenal="$plugin/skills/arsenal/SKILL.md"
dir="."; map=""
for a in "$@"; do
  case "$a" in map) map=yes ;; *) dir="$a" ;; esac
done

# The table names files under ${CLAUDE_PLUGIN_ROOT}; the person gets the path.
table="$(awk '/^## Where you are, and what to do next/{on=1; next} on && /^## /{exit} on && /^\| /' "$arsenal" |
  awk -v r="$plugin" '{ gsub(/\$\{CLAUDE_PLUGIN_ROOT\}/, r); print }')"
[ -n "$table" ] || { echo "guide-state: no table under 'Where you are, and what to do next' in $arsenal" >&2; exit 1; }

# row <start of the "Where you are" cell>: the row's six cells, one per line:
# where, next action, tool, how to use it, what it leaves, then.
row() {
  local r
  r="$(printf '%s\n' "$table" | awk -v p="| $1" 'index($0, p) == 1' | head -1)"
  [ -n "$r" ] || { echo "guide-state: the arsenal's table has no row starting '$1'" >&2; return 1; }
  printf '%s\n' "$r" | awk -F ' \\| ' 'NF != 6 { exit 1 } { sub(/^\| /, "", $1); sub(/ \|$/, "", $6); for (i = 1; i <= 6; i++) print $i }' ||
    { echo "guide-state: the arsenal's row '$1' does not have six cells" >&2; return 1; }
}

# why_line <row start> <words>: "why:", the row's name and its tool cell from
# those words up to the next "; ", so that the reason is the table's. Words the
# table no longer has are an error, as a missing row is.
why_line() {
  local cells tool reason
  cells="$(row "$1")" || return 1
  tool="$(sed -n 3p <<<"$cells")"
  case "$tool" in *"$2"*) ;; *) echo "guide-state: the arsenal's row '$1' no longer says '$2'" >&2; return 1 ;; esac
  reason="$2${tool#*"$2"}"
  echo "why: $(sed -n 1p <<<"$cells"): ${reason%%; *}"
}
whys="$(why_line "A merged change to put out" "plinth does not deploy" &&
  why_line "The project in use" "an uptime monitor" &&
  why_line "Looking back on a piece of work" "it reads the session" &&
  cells="$(row "Ending the project")" && echo "why: $(sed -n 1p <<<"$cells"): the table gives no reason")" || exit 1

# say <row start> <command> [<then: row start>]: the verdict block. The
# command is typed as printed; $before (typed first) and $note go with it.
# `then:` is the step after this one (#908): the row the table's Then cell
# names (`-` there is none), unless the state names another.
before=""; note=""; said_cmd=""; shown=""
# show <row start>: that row goes in the table printed without map (#1060).
show() { shown="$shown$(printf '%s\n' "$table" | awk -v p="| $1" 'index($0, p) == 1' | head -1)"$'\n'; }
say() {
  local cells after
  cells="$(row "$1")" || exit 1
  show "$1"
  echo "where: $(sed -n 1p <<<"$cells")"
  echo "next: $(sed -n 2p <<<"$cells")"
  echo "tool: $(sed -n 3p <<<"$cells")"
  [ -z "$before" ] || echo "before: $before"
  echo "command: $2"
  said_cmd="$2"
  [ -z "$note" ] || echo "note: $note"
  after="${3:-$(sed -n 6p <<<"$cells")}"
  if [ "$after" != - ]; then
    after="$(row "$after")" || exit 1
    show "$(sed -n 1p <<<"$after")"
    echo "then: $(sed -n 1p <<<"$after") -> $(sed -n 3p <<<"$after")"
  fi
}

# How much of the way the guide explains (#908), by the state alone: full
# before a person's pull request has merged, on `map`, or when the state was
# not read; focused otherwise. set_mode <full|focused> <reason>; map wins.
mode=full; mode_why="no pull request by a person has merged yet"
set_mode() { if [ -n "$map" ]; then mode=full; mode_why="asked for the whole way (map)"; else mode="$1"; mode_why="$2"; fi; }
set_mode "$mode" "$mode_why"

finish() {
  echo "mode: $mode ($mode_why)"
  echo
  printf '%s\n' "$whys"
  echo
  if [ -n "$map" ]; then
    echo "table: every row"
    printf '%s\n' "$table"
  else
    # The header and its rule, then the rows said above; none when no step was.
    echo "table: this step and the next only; /plinth:guide map prints every row"
    head -2 <<<"$table"
    printf '%s' "$shown" | awk 'NF && !seen[$0]++'
    # What goes out on a version tag stays said in every answer (#908), from
    # the release row's Next action cell, though its row is the map's.
    if [ -n "$shown" ] && ! grep -qF "| A merged change to put out" <<<"$shown"; then
      cells="$(row "A merged change to put out")" || exit 1
      echo "release: $(sed -n 1p <<<"$cells"): $(sed -n 2p <<<"$cells")"
    fi
  fi
  exit 0
}

echo "plinth guide state (read-only)"

if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
  echo "repository: none here (not a git checkout)"
  set_mode full "no repository yet, so nothing has merged"
  echo
  say "No repository yet" "/plinth:new-project <owner>/<name>"
  finish
fi
top="$(git -C "$dir" rev-parse --show-toplevel)"
answers="$top/.copier-answers.yml"
answer() { sed -nE "s/^$1: *['\"]?([^'\"]*)['\"]? *\$/\\1/p" "$answers" 2>/dev/null | head -1; }

# Made by plinth means rendered from its template in the form the door
# writes, as floor-check's template item reads it; another Copier template
# leaves an answers file too.
template_repo="$(sed -nE 's/^template_repo="([^"]+)"$/\1/p' "$plugin/scripts/new-project.sh" 2>/dev/null)"
[ -n "$template_repo" ] || { echo "guide-state: no template_repo in $plugin/scripts/new-project.sh" >&2; exit 1; }
src="$(answer _src_path)"
if [ ! -f "$answers" ] || [ "$src" != "gh:$template_repo" ]; then
  if [ -f "$answers" ]; then echo "made by plinth: no (.copier-answers.yml names ${src:-no} template, not gh:$template_repo)"
  else echo "made by plinth: no (no .copier-answers.yml)"; fi
  set_mode full "the state was not read: pull requests are read only on a repository plinth made"
  echo
  say "A repository plinth did not make" "/plinth:floor-check"
  finish
fi
archetype="$(answer archetype)"; hosting="$(answer hosting)"; place="$(answer hosting_elsewhere)"
echo "made by plinth: yes, template $(answer _commit)"
echo "archetype: ${archetype:-not recorded}"
[ "$archetype" = web ] && echo "hosting: ${hosting:-render (no answer recorded)}${place:+ ($place)}"

# behind [--no-network]: the template tag against the one this plinth targets,
# the plinth pin against plinth's latest release, as floor-check reads them.
behind() {
  local out
  if out="$(python3 "$plugin/scripts/floor-check.py" --root "$top" --print-behind "$@" 2>&1)" &&
     grep -q '^template: ' <<<"$out" && grep -q '^plinth pin: ' <<<"$out"; then
    behind_lines="$(grep -E '^(template|plinth pin): ' <<<"$out")"
  else
    behind_lines="template: not read (floor-check: $(tail -1 <<<"$out"))
plinth pin: not read (floor-check: $(tail -1 <<<"$out"))"
  fi
  printf '%s\n' "$behind_lines"
}
behind_lines=""

if [ "$(answer host)" = gitlab ]; then
  behind
  echo "repository: GitLab; the guide reads GitHub only, so issues and merge requests were not read"
  echo "so far: not read (the guide reads GitHub only)"
  set_mode full "the state was not read"
  echo
  echo "where: not read"
  finish
fi

# What the project started with off and does not have yet (#763), from the
# one list new-project.sh prints at creation. On map, every item; otherwise,
# in either mode (#908), how many, and only the ones whose line says to do
# them now (#1050). The skill says each item only when asked for the map
# (#1035), so the list is printed only then.
off_said=""
if off="$("$plugin/scripts/off-by-default.sh" "${archetype:-none}" "$top" 2>&1)"; then
  if [ -n "$off" ]; then
    if rule="$("$plugin/scripts/off-by-default.sh" --why 2>&1)"; then off_why="$rule"
    else off_why="not read ($(head -1 <<<"$rule"))"; fi
  else off_said="none left off"; fi
else
  off_said="not read ($(head -1 <<<"$off"))"
fi
say_off() {
  local now
  if [ -n "$off_said" ]; then echo "off by default: $off_said"; return; fi
  if [ -n "$map" ]; then
    echo "off by default:"; sed 's/^/  /' <<<"$off"
  else
    now="$(grep '^to do, if not done yet' <<<"$off")"
    echo "off by default: $(grep -c . <<<"$off") left off; /plinth:guide map names each"
    [ -z "$now" ] || sed 's/^/  /' <<<"$now"
  fi
  echo "  why: $off_why"
}

if ! repo="$(cd "$top" && gh repo view --json nameWithOwner --jq .nameWithOwner 2>&1)"; then
  echo "repository: not read ($(head -1 <<<"$repo"))"
  behind --no-network
  set_mode full "the state was not read"; say_off
  echo
  echo "where: not read"
  finish
fi
echo "repository: $repo"
behind

# A check run has status and conclusion; a commit status has only state.
rollup='def state: (.conclusion // .state // "") as $c | (.status // "COMPLETED") as $s
  | if $s != "COMPLETED" or ($c | IN("PENDING", "EXPECTED", "QUEUED", "IN_PROGRESS", "")) then "pending"
    elif ($c | IN("SUCCESS", "NEUTRAL", "SKIPPED")) then "pass" else "fail" end;
  def checks: [.statusCheckRollup[]? | state]
  | if length == 0 then "none" elif any(. == "fail") then "fail" elif any(. == "pending") then "pending" else "pass" end;
  # The failing ones (#903): name, then the Actions job its log is read by
  # (none for a commit status); \u001f inside one, \u001e between them.
  def failing: [.statusCheckRollup[]? | select(state == "fail")
    | [((.name // .context // "unnamed") | gsub("[\t\n\u001e\u001f]"; " ")),
       ((.detailsUrl // "") | (capture("/actions/runs/[0-9]+/job/(?<j>[0-9]+)") | .j) // "")] | join("\u001f")] | join("\u001e");'
# Dependabot's pull request that raises the plinth pin (#904): its title or
# body names coolbress/plinth, as the template's how-to searches for it, and
# not coolbress/plinth-template.
raises='def raises: if ((.author.login // "") | IN("app/dependabot", "dependabot[bot]", "dependabot"))
    and (((.title // "") + " " + (.body // "")) | ascii_downcase | test("coolbress/plinth([^-_.a-z0-9]|$)")) then "plinth" else "" end;'
bot='(.author.is_bot // false) or (.author.login // "" | startswith("app/"))'
clean='gsub("[\t\n]"; " ")'
# What an issue is (#834). The reminder is the template's Template reminder
# workflow's: its body starts with that marker, its title with those words.
kind='def kind: [.labels[].name] as $l
  | if ((.body // "") | startswith("<!-- plinth:template-reminder -->")) or (.title | startswith("Template update available:")) then "reminder"
    elif ($l | index("ready-for-human")) then "person"
    elif ($l | any(startswith("wayfinder:") and . != "wayfinder:task")) then "wayfinder"
    elif ($l | index("spec")) then "spec"
    else "ticket" end;'
# Which ticket to take (#910). refs: the #N of this repository in a text, not
# owner/repo#N, not part of a longer word. An issue's blockers: each #N under
# its ## Blocked by (### Blocked by from the task form), up to the next
# heading, unless that section opens with "None", and those on a
# first line "Blocked by: #N, #N" (docs/agents/issue-tracker.md's fallback).
# GitHub's native issue dependencies are read below. A pull request is for each #N
# its body names after a closing keyword or "Part of", as GitHub reads it.
refs='def refs: [scan("(?:^|[^A-Za-z0-9_./-])#([0-9]+)") | .[0]];'
blockers='def blockers: [(.body // "") | split("\n")[] | sub("\r$"; "")] as $ls
  | [$ls | reduce .[] as $l ({on: false, lines: []};
      if ($l | test("^#{1,6}[ \t]")) then .on = ($l | test("(?i)^#{2,3}[ \t]+Blocked by[ \t]*$"))
      elif .on and ($l | test("\\S")) then .lines += [$l] else . end) | .lines] as [$sec]
  | (if ($sec | length) > 0 and ($sec[0] | test("(?i)^([-*][ \t]+)?none([^a-z]|$)")) then [] else [$sec[] | refs[]] end)
    + (if ($ls[0] // "" | test("(?i)^Blocked by:")) then ($ls[0] | refs) else [] end)
  | map(tonumber) | unique | map(tostring) | join(",");'
for_issues='def for_issues: [(.body // "") | scan("(?i)(?:^|[^a-z0-9_])(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?|part of)[ \t]*:?[ \t]+#([0-9]+)") | .[0] | tonumber]
  | unique | map(tostring) | join(",");'

# Each read on its own, so the line names the one that failed and its error.
# The open pull requests' columns: 1 number, 2 bot or person, 3 draft or
# ready, 4 checks, 5 head, 6 title, 7 opened at, 8 failing checks, 9 raises
# the plinth pin, 10 the issues it is for, 11 mergeStateStatus (#998), 12 the
# #N its Blocked by names. mergeStateStatus is a field, not a connection: it
# adds no node to the query's count (measured for #998).
# Merged pull requests are read up to $read. A read that comes back full may
# have been cut (one more cannot be told apart), so the count is of those
# only and the line says so (#905).
read=100
prs=""; merged=""; issues=""; failed=""
issue_rows="$kind$refs$blockers"' sort_by(.number) | .[] | [.number, ([.labels[].name] | join(",")), (.title | '"$clean"'), kind, blockers] | @tsv'
if ! prs="$(cd "$top" && gh pr list --state open --limit 100 \
      --json number,title,body,isDraft,author,headRefOid,statusCheckRollup,createdAt,mergeStateStatus \
      --jq "$rollup$raises$for_issues$refs$blockers"' sort_by(.number) | .[] | [.number, (if '"$bot"' then "bot" else "person" end), (if .isDraft then "draft" else "ready" end), checks, .headRefOid, (.title | '"$clean"'), .createdAt, failing, raises, for_issues, (.mergeStateStatus // ""), blockers] | @tsv' 2>&1)"; then
  failed="open pull requests: $(tail -1 <<<"$prs")"
elif ! merged="$(cd "$top" && gh pr list --state merged --limit "$read" --json number,title,mergedAt,author \
      --jq 'sort_by(.mergedAt) | reverse | .[] | [.number, (if '"$bot"' then "bot" else "person" end), (.mergedAt[0:10]), (.title | '"$clean"')] | @tsv' 2>&1)"; then
  failed="merged pull requests: $(tail -1 <<<"$merged")"
elif ! issues="$(cd "$top" && gh issue list --state open --limit 100 --json number,title,labels,body --jq "$issue_rows" 2>&1)"; then
  failed="open issues: $(tail -1 <<<"$issues")"
fi
if [ -n "$failed" ]; then
  echo "issues and pull requests: not read ($failed)"
  set_mode full "the state was not read"; say_off
  echo
  echo "where: not read"
  finish
fi

field() { cut -f"$1"; }
# What was cut from each open spec (#909), as /to-tickets cuts one: its
# sub-issues, open or closed, else the issues, open or closed, whose body
# names #N under ## Parent. The sub-issue counts are a read of their own, one
# call and only when a spec is open: gh before 2.94.0 has no subIssuesSummary
# and refuses a list that asks for it, which would leave every issue unread;
# here only the specs are. A spec missing from that read is unread too. Only the first spec with none
# is routed to, so the search runs in number order on specs with no sub-issue
# and stops at the first that comes back uncut: one search per spec up to and
# including it, none past it. The search's words only narrow it; the filter is
# what decides: #N in that section and nowhere else, not owner/repo#N, not
# #N0. It reads the first 100 matches only.
# Out: <number>\t<cut|none|unread|unsearched>\t<what is said of it>; routing
# reads the second column, the spec's line the third (as #906 keeps them).
parent_of='def parent_of($n): [(.body // "") | split("\n")[]]
  | reduce .[] as $l ({on: false, hit: false};
      if ($l | startswith("## ")) then .on = ($l | test("^## Parent[ \t]*\r?$"))
      elif .on and ($l | test("(^|[^A-Za-z0-9_./-])#" + ($n | tostring) + "([^0-9]|$)")) then .hit = true
      else . end) | .hit;'
specs=""
if open_specs="$(awk -F '\t' '$4 == "spec" { print $1 }' <<<"$issues")" && [ -n "$open_specs" ]; then
  subs_read="$(cd "$top" && gh issue list --state open --label spec --limit 100 --json number,subIssuesSummary \
    --jq '.[] | [.number, (.subIssuesSummary.total // 0)] | @tsv' 2>&1)" || subs_failed="$(tail -1 <<<"$subs_read" | tr '\t' ' ')"
  specs="$(while IFS= read -r n; do
      subs="$([ -n "${subs_failed:-}" ] || awk -F '\t' -v n="$n" '$1 == n { print $2; exit }' <<<"$subs_read")"
      printf '%s\t%s\n' "$n" "${subs:--}"
    done <<<"$open_specs" |
  { first=""; while IFS=$'\t' read -r n subs; do
    if [ "$subs" = - ]; then
      printf '%s\tunread\tnot read (sub-issues: %s)\n' "$n" "${subs_failed:-not in the read of open specs}"
    elif [ "$subs" -gt 0 ]; then
      printf '%s\tcut\t%s sub-issue%s\n' "$n" "$subs" "$([ "$subs" -eq 1 ] || echo s)"
    elif [ -n "$first" ]; then
      printf '%s\tunsearched\tnot searched (spec #%s, with none, comes first)\n' "$n" "$first"
    elif named="$(cd "$top" && gh issue list --state all --limit 100 --search "#$n in:body" --json number,body \
          --jq "$parent_of"' [.[] | select(.number != '"$n"' and parent_of('"$n"')) | .number] | sort | map("#\(.)") | join(", ")' 2>&1)"; then
      if [ -n "$named" ]; then printf '%s\tcut\t%s names it under ## Parent\n' "$n" "$named"
      else printf '%s\tnone\tnone\n' "$n"; first="$n"; fi
    else
      printf '%s\tunread\tnot read (%s)\n' "$n" "$(tail -1 <<<"$named" | tr '\t' ' ')"
    fi
  done; })"
fi
# Column 9 of the list is whether Dependabot's pull request raises the plinth
# pin (#904): never so for a person's, so their rows end at 8 and take the
# checks line below as 9.
people_prs="$(awk -F '\t' '$2 == "person"' <<<"$prs" | cut -f1-8)"
# An empty rollup (#906) is checks not created yet, seconds after a push, or
# none that will run. GitHub gives no push time: the later of the head
# commit's time and the pull request's opening stands in for it, so a commit
# made over ten minutes before it was pushed to an older pull request reads as
# no checks ran. The head's time is one call per such pull request: asking
# the list above for `commits` makes GitHub refuse the whole query (over its
# 500,000-node limit at --limit 100). Column 9 is what is said of the checks.
checks_line() {
  local row checks sha created line t
  while IFS= read -r row; do
    checks="$(cut -f4 <<<"$row")"; sha="$(cut -f5 <<<"$row")"; created="$(cut -f7 <<<"$row")"
    line="checks $checks"
    if [ "$checks" = none ]; then
      line="no checks yet; when its head was pushed was not read"
      [[ "$created" =~ ^[0-9T:Z-]+$ ]] &&
        t="$(cd "$top" && gh api "repos/$repo/commits/$sha" --jq '[.commit.committer.date, "'"$created"'"]
          | map(fromdate) | max | ([now - ., 0] | max) as $a
          | if $a < 600 then "checks not started yet (last change \($a / 60 | floor) min ago)" else "no checks ran" end' 2>/dev/null)" &&
        [ -n "$t" ] && line="$t"
    fi
    printf '%s\t%s\n' "$row" "$line"
  done
}
[ -z "$people_prs" ] || people_prs="$(checks_line <<<"$people_prs")"
bot_prs="$(awk -F '\t' '$2 == "bot"' <<<"$prs")"
people_merged="$(awk -F '\t' '$2 == "person"' <<<"$merged" | grep -c . || true)"
counted="$people_merged merged by people"
# Cut: the older ones are unread, so neither "none" nor "exactly one" is
# known. A project with that many merges is taken as past its first.
past_first=""
if [ "$(grep -c . <<<"$merged" || true)" -ge "$read" ]; then
  past_first=yes; counted="$counted of the last $read read; older ones not read"
fi

# Which ticket /implement takes (#910), from what the repository records. A
# ready-for-agent ticket is skipped while its blockers include an open issue,
# or while an open pull request is for it (that pull request is routed first).
# Of the rest: a sub-issue of an open spec first, in the spec's sub-issue
# order (specs in number order); then the one the most open tickets name as
# their blocker; then the lowest number. The sub-issue order is read, one call
# per open spec with sub-issues, only when two or more tickets are ready. The
# open issues are the newest 100: a blocker older than all of them, in a read
# that came back full, is not known to be closed, so it still blocks.
ready_n="$(awk -F '\t' '$4 == "ticket" && ("," $2 ",") ~ /,ready-for-agent,/' <<<"$issues" | grep -c . || true)"; shown_ready="$ready_n"
# GitHub's native issue dependencies, which docs/agents/issue-tracker.md and
# /to-tickets use first: one GraphQL call for the open ready-for-agent issues
# (the newest 100, as the issue read; 50 edges each way, more not read). An
# unlabelled ticket's own are not read: it is known to wait only through a
# ready ticket's blocking edge or its body. Out: <waiter>\t<blocker> for each edge whose
# blocker is open, from blockedBy, and from blocking where the waiter is an
# open issue of this repository; a blocker in another repository is written
# owner/repo#N, and blocks too. A failed read, or a GitHub or gh that does not
# know the fields, leaves the choice to the bodies and the line says so.
deps=""; deps_failed=""; deps_read=""
read_deps() {
  [ -z "$deps_read" ] && [ "$ready_n" -ge 1 ] || return 0
  deps_read=yes
  owner="${repo%%/*}"; name="${repo#*/}"
  deps="$(cd "$top" && gh api graphql -f owner="$owner" -f name="$name" -f query='
    query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) {
      issues(states: OPEN, labels: ["ready-for-agent"], first: 100, orderBy: {field: CREATED_AT, direction: DESC}) { nodes { number
        blockedBy(first: 50) { nodes { number state repository { nameWithOwner } } }
        blocking(first: 50) { nodes { number state repository { nameWithOwner } } } } } } }' \
    --jq '"'"$(tr 'A-Z' 'a-z' <<<"$repo")"'" as $me
      | def ref: if (.repository.nameWithOwner | ascii_downcase) == $me then (.number | tostring) else "\(.repository.nameWithOwner)#\(.number)" end;
      .data.repository.issues.nodes[] | .number as $n
      | ((.blockedBy.nodes[] | select(.state == "OPEN") | [($n | tostring), ref]),
         (.blocking.nodes[] | select(.state == "OPEN" and (.repository.nameWithOwner | ascii_downcase) == $me) | [(.number | tostring), ($n | tostring)]))
      | @tsv' 2>&1)" || { deps_failed="$(tail -1 <<<"$deps" | tr '\t' ' ')"; deps=""; }
}
order=""; order_failed=""; order_read=""
read_order() {
  [ -z "$order_read" ] && [ "$ready_n" -ge 2 ] || return 0
  order_read=yes
  while IFS=$'\t' read -r n _ said; do
    case "$said" in *sub-issue*) ;; *) continue ;; esac
    if got="$(cd "$top" && gh api "repos/$repo/issues/$n/sub_issues" --paginate --jq '.[] | select((.repository_url // "") | ascii_downcase | endswith("/repos/'"$(tr 'A-Z' 'a-z' <<<"$repo")"'")) | .number' 2>&1)"; then
      order="$order$(awk -v s="$n" 'NF { print $1 "\t" s "\t" (++i) }' <<<"$got")"$'\n'
    else
      order_failed="${order_failed:+$order_failed; }#$n: $(tail -1 <<<"$got" | tr '\t' ' ')"
    fi
  done <<<"$specs"
}
# The issue read is the newest 100 open (#1059): when it came back full and
# held no ready-for-agent ticket to take, the ready-for-agent issues are read
# on their own (the newest 100 of them), and those older than the first read
# join the choice with the same skips. They do not lower the lowest number
# the first read saw: a blocker older than that, missing from it, is still
# not known to be closed, unless read by number: the older tickets' blockers
# missing from both reads are, in one GraphQL call, and one read CLOSED or
# MERGED no longer blocks; one that read does not answer still blocks,
# whatever its number: newer than that lowest, it can be a missing number
# the first read skipped, an open pull request's (#1062). A
# failed read of the ready-for-agent issues leaves the next ticket not read,
# said in place of /grilling.
full="$([ "$(grep -c . <<<"$issues" || true)" -ge 100 ] && echo 1)"
older=""; older_failed=""; older_read=""; older_full=""; states=""; states_failed=""
choose() {
read_deps; read_order
choice="$(awk -F '\t' -v full="$full" '
  function said(list,   k, a, i, s) { k = split(list, a, " "); s = a[1]
    for (i = 2; i <= k; i++) s = s (i == k ? " and " : ", ") a[i]; return s }
  function better(a, b,   ra, rb) { if (b == "") return 1
    ra = (a in rank) ? rank[a] : 1e9; rb = (b in rank) ? rank[b] : 1e9
    if (ra != rb) return ra < rb
    if (nw[a] + 0 != nw[b] + 0) return nw[a] + 0 > nw[b] + 0
    return a + 0 < b + 0 }
  FNR == 1 { f++ }
  $1 == "" { next }
  f == 1 { k = split($10, a, ","); for (i = 1; i <= k; i++) if (!(a[i] in pr)) pr[a[i]] = $1; next }
  f == 2 { if (!($1 in rank)) { rank[$1] = ++nr; spec[$1] = $2 }; next }
  f == 3 { native[$1] = native[$1] "," $2; nopen[$2] = 1; next }
  f == 4 { past[$1] = 1; next }
  f == 5 { if ($2 == "OPEN") nopen[$1] = 1; else shut[$1] = 1; next }
  { open[$1] = 1; if (!($1 in past) && (min == "" || $1 + 0 < min + 0)) min = $1
    if ($4 != "ticket") next
    t[++n] = $1; ready[$1] = (("," $2 ",") ~ /,ready-for-agent,/)
    # The body'"'"'s blockers and the native ones, each once.
    k = split($5 native[$1], a, ","); b = ""; delete seen
    for (i = 1; i <= k; i++) if (a[i] != "" && !(a[i] in seen)) { seen[a[i]] = 1; b = b "," a[i] }
    blk[$1] = substr(b, 2)
    k = split(blk[$1], a, ","); for (i = 1; i <= k; i++) { nw[a[i]]++; waits[a[i]] = waits[a[i]] (waits[a[i]] == "" ? "" : " ") "#" $1 } }
  END {
    for (j = 1; j <= n; j++) {
      x = t[j]; ob = ""; closed = ""
      k = split(blk[x], a, ",")
      for (i = 1; i <= k; i++) {
        if (a[i] ~ /#/) ob = ob " " a[i]
        else if ((a[i] in open) || (a[i] in nopen)) ob = ob " #" a[i]
        else if (!(a[i] in shut) && ((x in past) || (full && a[i] + 0 < min + 0))) ob = ob " #" a[i] "~"
        else closed = closed " #" a[i]
      }
      if (ob != "") { why = said(substr(ob, 2)); gsub(/~/, " (not in the open issues read)", why) }
      if (!ready[x]) { if (ob == "" && !(x in pr) && fallback == "") fallback = x; continue }
      if (ob != "") { nb++; bl = bl "; #" x " on " why }
      else if (x in pr) { np++; tk = tk "; #" x " on pull request #" pr[x] }
      else { nc++; cl[x] = substr(closed, 2); if (better(x, pick)) pick = x }
    }
    print "pick\t" pick
    print "fallback\t" fallback
    if (nb + np + nc == 0) exit
    if (pick == "") {
      print "ticket to take: none; every ready-for-agent ticket waits: " substr(bl tk, 3)
    } else {
      r = "not blocked"
      if (cl[pick] != "") r = r " (" said(cl[pick]) (index(cl[pick], " ") ? " are" : " is") " closed)"
      if (pick in rank) r = r "; a sub-issue of spec #" spec[pick] ", next in its order"
      if (nw[pick] > 0) r = r "; " said(waits[pick]) (nw[pick] > 1 ? " wait" : " waits") " on it"
      if (nc == 1) r = r "; the only ready-for-agent ticket left"
      else if (!(pick in rank) && nw[pick] == 0) r = r "; the lowest number of the " nc " left"
      print "ticket to take: #" pick ", " r
    }
    s = nb + np " of " nb + np + nc " ready-for-agent"
    if (nb) s = s "; blocked by an open issue: " substr(bl, 3)
    if (np) s = s "; in an open pull request: " substr(tk, 3)
    print "skipped: " (nb + np ? s : "none")
  }' <(printf '%s\n' "$prs") <(printf '%s\n' "$order") <(printf '%s\n' "$deps") <(field 1 <<<"$older") <(printf '%s\n' "$states") - \
    <<<"$issues${older:+$'\n'$older}")"
pick="$(awk -F '\t' '$1 == "pick" { print $2 }' <<<"$choice")"
fallback="$(awk -F '\t' '$1 == "fallback" { print $2 }' <<<"$choice")"
}
choose
if [ -z "$pick" ] && [ -n "$full" ]; then
  older_read=yes
  if got="$(cd "$top" && gh issue list --state open --label ready-for-agent --limit 100 --json number,title,labels,body --jq "$issue_rows" 2>&1)"; then
    older="$(awk -F '\t' 'FNR == NR { seen[$1] = 1; next } $1 != "" && !($1 in seen)' <(printf '%s\n' "$issues") - <<<"$got")"
    [ "$(grep -c . <<<"$got" || true)" -lt 100 ] || older_full=yes
    if [ -n "$older" ]; then
      ready_n=$((ready_n + $(awk -F '\t' '$4 == "ticket"' <<<"$older" | grep -c . || true)))
      missing="$(awk -F '\t' '$4 == "ticket" { k = split($5, a, ","); for (i = 1; i <= k; i++) if (a[i] != "") print a[i] }' <<<"$older" |
        sort -un | grep -vxF -f <( { field 1 <<<"$issues"; field 1 <<<"$older"; } | grep . ) || true)"
      if [ -n "$missing" ]; then
        owner="${repo%%/*}"; name="${repo#*/}"
        asked="$(sed 's/.*/n&: issueOrPullRequest(number: &) { ... on Issue { state } ... on PullRequest { state } }/' <<<"$missing" | paste -sd ' ' -)"
        if got="$(cd "$top" && gh api graphql -f owner="$owner" -f name="$name" \
              -f query="query(\$owner: String!, \$name: String!) { repository(owner: \$owner, name: \$name) { $asked } }" \
              --jq '.data.repository | to_entries[] | select(.value != null) | [(.key[1:]), .value.state] | @tsv' 2>&1)"; then
          states="$got"
        else
          states_failed="$(tail -1 <<<"$got" | tr '\t' ' ')"
        fi
      fi
      choose
    fi
  else
    older_failed="$(tail -1 <<<"$got" | tr '\t' ' ')"
  fi
fi

if [ -n "$people_prs" ]; then
  echo "open pull requests:"
  # Each one with the issues it is for (#910), from its row in $prs.
  awk -F '\t' 'FNR == NR { if ($10 != "") { f = $10; gsub(/,/, ", #", f); fr[$1] = " (for #" f ")" }; next }
    { printf "  #%s%s %s, %s: %s\n", $1, fr[$1], $3, $9, $6 }' <(printf '%s\n' "$prs") - <<<"$people_prs"
else
  echo "open pull requests: none"
fi
[ -n "$bot_prs" ] && echo "open Dependabot pull requests: $(field 1 <<<"$bot_prs" | sed 's/^/#/' | paste -sd ' ' -)"
if [ -n "$issues" ]; then
  echo "open issues ($(grep -c . <<<"$issues"), $shown_ready ready-for-agent):"
  head -10 <<<"$issues" | awk -F '\t' '{ printf "  #%s [%s] %s\n", $1, ($2 == "" ? "no label" : $2), $3 }'
else
  echo "open issues: none"
fi
# Every one of them, past the ten above: none is ever an /implement target.
not_tickets="$(awk -F '\t' 'FNR == NR { cut[$1] = $3; next }
  $4 == "reminder" { printf "  #%s the monthly template reminder: a person types /plinth:template-update\n", $1 }
  $4 == "person" { printf "  #%s [%s] a person'"'"'s task: a person does it\n", $1, $2 }
  $4 == "wayfinder" { printf "  #%s [%s] a wayfinder record: a person does it\n", $1, $2 }
  $4 == "spec" { printf "  #%s [%s] a spec, a record: a person does it; tickets cut from it: %s\n", $1, $2, cut[$1] }' \
  <(printf '%s\n' "$specs") - <<<"$issues")"
if [ -n "$not_tickets" ]; then echo "open issues that are not tickets, never for /implement:"; printf '%s\n' "$not_tickets"; fi
if [ -n "$older_failed" ]; then
  echo "ticket to take: not read: none of the newest 100 open issues can be taken, and the ready-for-agent issues past them were not read ($older_failed)"
elif [ -n "$older_read" ]; then
  l="ready-for-agent issues past the newest 100 open, read on their own: $( [ -n "$older" ] && field 1 <<<"$older" | sed 's/^/#/' | paste -sd ' ' - || echo none)"
  [ -z "$older_full" ] || l="$l; that read came back full (100), so older ones were not read"
  [ -z "$states_failed" ] || l="$l; their blockers missing from both reads: not read ($states_failed), so they still block"
  echo "$l"
fi
grep -E '^(ticket to take|skipped): ' <<<"$choice" | { [ -z "$older_failed" ] && cat || grep -v '^ticket to take: '; } | while IFS= read -r l; do
  case "$l" in "ticket to take: "*) [ -z "$deps_failed" ] || l="$l; GitHub's issue dependencies: not read ($deps_failed)" ;; esac
  printf '%s\n' "$l"
done
[ -z "$order_failed" ] || echo "spec sub-issue order: not read ($order_failed)"
if [ -n "$merged" ]; then
  last="$(head -1 <<<"$merged")"
  echo "last merge: #$(field 1 <<<"$last") on $(field 3 <<<"$last") by $(field 2 <<<"$last"): $(field 4 <<<"$last")"
else
  echo "last merge: none"
fi
echo "first pull request merged: $([ "$people_merged" -gt 0 ] || [ -n "$past_first" ] && echo yes || echo no) ($counted)"

# The pull request "Something broke" names (#903): which checks failed, and
# whose each one is. A check named "<job> / <anything>" is plinth's when <job>
# is a job of the project's workflows that calls a workflow of coolbress/plinth:
# read from the checkout's files, so a job that calls the project's own
# workflow under the same name is the project's. "<job> (" is a matrix on the
# caller job. Not read: a caller name written as an expression, a quoted job
# id, a job written on one line; such a check is said to be the project's own.
plinth_jobs() { # <name of the caller job>\t<plinth workflow file>\t<the version comment, or the ref>
  local f
  for f in "$top"/.github/workflows/*.yml "$top"/.github/workflows/*.yaml; do
    [ -f "$f" ] || continue
    awk '
      function flush() { if (uses != "") print (name != "" ? name : id) "\t" uses "\t" at; id = ""; name = ""; uses = ""; at = "" }
      function value(s) { sub(/^[^:]*:[ \t]*/, "", s); sub(/[ \t]+#.*$/, "", s); gsub(/^["\047]|["\047]$/, "", s); return s }
      /^[ \t]*(#|$)/ { next }
      { match($0, /^ */); ind = RLENGTH }
      ind == 0 { flush(); jobs = ($0 ~ /^jobs:/); ji = -1; next }
      !jobs { next }
      ji < 0 { ji = ind }
      ind == ji { flush(); id = $0; sub(/^ */, "", id); sub(/:.*$/, "", id); pi = -1; next }
      id == "" { next }
      pi < 0 { pi = ind }
      ind != pi { next }
      /^ *name:/ { name = value($0) }
      /^ *uses:/ {
        u = value($0)
        if (tolower(u) ~ /^coolbress\/plinth\/\.github\/workflows\/[^@]+@/) {
          uses = u; sub(/^[^\/]+\/[^\/]+\/\.github\/workflows\//, "", uses); at = uses
          sub(/@.*$/, "", uses); sub(/^[^@]*@/, "", at)
          if (match($0, /#[ \t]*v[0-9][^ \t]*/)) { at = substr($0, RSTART, RLENGTH); sub(/^#[ \t]*/, "", at) }
        }
      }
      END { flush() }' "$f"
  done
}
broken=""; plinth_failing=""; own_failing=""
{ [ "$people_merged" -gt 0 ] || [ -n "$past_first" ]; } && broken="$(awk -F '\t' '$4 == "fail"' <<<"$people_prs" | head -1)"
if [ -n "$broken" ]; then
  n="$(field 1 <<<"$broken")"
  callers="$(plinth_jobs)"
  echo "failing checks on pull request #$n:"
  while IFS=$'\037' read -r check job; do
    [ -n "$check" ] || continue
    whose="$(awk -F '\t' -v c="$check" 'index(c, $1 " / ") == 1 || index(c, $1 " (") == 1 { print $2 " at " $3; exit }' <<<"$callers")"
    if [ -n "$whose" ]; then
      echo "  $check: a plinth job (the project calls coolbress/plinth's $whose)"
      plinth_failing="${plinth_failing:+$plinth_failing, }$check"
    else
      echo "  $check: the project's own"
      own_failing="${own_failing:+$own_failing, }$check"
    fi
    [ -z "$job" ] || echo "    log: gh run view --job $job --log-failed"
  done < <(field 8 <<<"$broken" | tr '\036' '\n')
  # By people, not bots: the REST read says which an author is.
  if said="$(cd "$top" && gh api "repos/$repo/issues/$n/comments" --paginate --jq '.[] | select(.user.type != "Bot") | .id' 2>&1)"; then
    echo "comments by people on pull request #$n: $(grep -c . <<<"$said" || true)"
  else
    echo "comments by people on pull request #$n: not read ($(tail -1 <<<"$said"))"
  fi
fi
# The next pull request to merge (#998), past the first merge with two or
# more of a person's open: by mergeStateStatus, green and up to date (CLEAN,
# or HAS_HOOKS) first; then green but behind main (BEHIND); then green and
# BLOCKED by a rule; then checks still running; each of those oldest first.
# One with no checks on it is not ranked: nothing has checked it yet. A
# draft, a failing check, a conflict (DIRTY), a non-passing status
# (UNSTABLE), or a Blocked by naming an open issue or pull request: never;
# a Blocked by number that cannot be read: not ranked.
# GitHub works mergeability out on the first read and says UNKNOWN meanwhile:
# a green one so said is read once more, one call each after a short wait,
# and said as not read if it is still UNKNOWN. What it cannot know is a line
# of its own.
merge_next=""; merge_n=""
if { [ "$people_merged" -gt 0 ] || [ -n "$past_first" ]; } && [ "$(grep -c . <<<"$people_prs")" -ge 2 ]; then
  person_rows="$(awk -F '\t' '$2 == "person"' <<<"$prs")"
  unknown="$(awk -F '\t' '$3 == "ready" && $4 == "pass" && $11 == "UNKNOWN" { print $1 }' <<<"$person_rows")"
  reread=""
  if [ -n "$unknown" ]; then
    sleep "${GUIDE_REREAD_WAIT:-3}"
    while IFS= read -r n; do
      again="$(cd "$top" && gh pr view "$n" --json mergeStateStatus --jq .mergeStateStatus 2>/dev/null)" || again=""
      reread="$reread$n"$'\t'"${again:-UNKNOWN}"$'\n'
    done <<<"$unknown"
  fi
  # A Blocked by number missing from the capped reads (the newest 100 open
  # issues and pull requests) may still be open: each is read by number, in
  # one GraphQL call. One that read does not answer leaves the pull request
  # unranked, never unblocked.
  open_nums="$( { field 1 <<<"$issues"; field 1 <<<"$prs"; } | grep . )"
  missing="$(awk -F '\t' '{ k = split($12, a, ","); for (i = 1; i <= k; i++) if (a[i] != "") print a[i] }' <<<"$person_rows" |
    sort -un | grep -vxF -f <(printf '%s\n' "$open_nums") || true)"
  looked=""; lookup_failed=""
  if [ -n "$missing" ]; then
    owner="${repo%%/*}"; name="${repo#*/}"
    asked="$(sed 's/.*/n&: issueOrPullRequest(number: &) { ... on Issue { state } ... on PullRequest { state } }/' <<<"$missing" | paste -sd ' ' -)"
    if got="$(cd "$top" && gh api graphql -f owner="$owner" -f name="$name" \
          -f query="query(\$owner: String!, \$name: String!) { repository(owner: \$owner, name: \$name) { $asked } }" \
          --jq '.data.repository | to_entries[] | select(.value != null) | [(.key[1:]), .value.state] | @tsv' 2>&1)"; then
      looked="$got"
    else
      lookup_failed="$(tail -1 <<<"$got" | tr '\t' ' ')"
    fi
  fi
  ranked="$(awk -F '\t' -v lf="$lookup_failed" '
    FNR == 1 { f++ }
    $1 == "" { next }
    f == 1 { again[$1] = $2; next }
    f == 2 { state_of[$1] = $2; next }
    f == 3 { open[$1] = 1; next }
    f == 4 { open[$1] = 1; next }
    { n = $1; draft = $3; checks = $4; st = $11
      ob = ""; un = ""; k = split($12, a, ",")
      for (i = 1; i <= k; i++) {
        if (a[i] == "") continue
        if ((a[i] in open) || ((a[i] in state_of) && state_of[a[i]] == "OPEN")) ob = ob (ob == "" ? "#" : ", #") a[i]
        else if (!(a[i] in state_of)) un = un (un == "" ? "#" : ", #") a[i]
      }
      if (st == "UNKNOWN" && (n in again)) st = again[n]
      if (draft == "draft") { r = 6; w = "never: a draft" }
      else if (checks == "fail") { r = 6; w = "never: a check fails" }
      else if (st == "DIRTY") { r = 6; w = "never: conflicts with main (DIRTY)" }
      else if (ob != "") { r = 6; w = "never: waits on " ob " (its Blocked by)" }
      else if (un != "") { r = 5; w = "not ranked: blocker " un " not read (" (lf != "" ? lf : "no issue or pull request by that number") ")" }
      else if (checks == "pending") { r = 4; w = "checks still running" }
      else if (checks == "none") { r = 5; w = "not ranked: no checks on it yet" }
      else if (st == "CLEAN" || st == "HAS_HOOKS") { r = 1; w = "green and up to date (" st ")" }
      else if (st == "BEHIND") { r = 2; w = "green, behind main (BEHIND)" }
      else if (st == "BLOCKED") { r = 3; w = "green, merging blocked by a rule such as a required review (BLOCKED)" }
      else if (st == "UNSTABLE") { r = 6; w = "never: a status not passing (UNSTABLE)" }
      else if (st == "UNKNOWN") { r = 5; w = "not read (UNKNOWN, read twice)" }
      else { r = 5; w = "not read (" (st == "" ? "no state given" : st) ")" }
      printf "%d\t%s\t%09d\t%s\t%s\n", r, $7, n, n, w }' \
    <(printf '%s\n' "$reread") <(printf '%s\n' "$looked") <(printf '%s\n' "$issues") <(printf '%s\n' "$prs") - <<<"$person_rows" | sort -t $'\t' -k1,1n -k2,2 -k3,3)"
  lead="$(head -1 <<<"$ranked")"
  if [ "$(field 1 <<<"$lead")" -le 4 ]; then
    merge_n="$(field 4 <<<"$lead")"
    merge_next="merge next: #$merge_n, $(field 5 <<<"$lead"); the person says merge #$merge_n"
    rest="$(tail -n +2 <<<"$ranked")"
  else
    merge_next="merge next: none of the $(grep -c . <<<"$ranked") open; each line below says why"
    rest="$ranked"
  fi
  [ -z "$rest" ] || merge_next="$merge_next"$'\n'"$(awk -F '\t' '{ printf "  #%s: %s\n", $4, $5 }' <<<"$rest")"
  merge_next="$merge_next"$'\n'"merge next cannot know: whether two pull requests green alone break main together; which one depends on another, unless its Blocked by says so; which session owns each; whether the person wants it merged now"
fi
[ -z "$merge_next" ] || printf '%s\n' "$merge_next"
if [ "$people_merged" -gt 0 ]; then set_mode focused "a pull request by a person has merged"
elif [ -n "$past_first" ]; then set_mode focused "past the first merge: more merged pull requests than the $read read"
else set_mode full "no pull request by a person has merged yet"; fi
say_off
echo

pin_behind="$(sed -nE 's/^plinth pin: [^,]+, behind (v[0-9.]+), .*/\1/p' <<<"$behind_lines")"
template_behind="$(sed -nE 's/^template: ([^,]+), behind (v[0-9.]+), .*/\1 is behind \2/p' <<<"$behind_lines")"
# pin_howto: the project's own how-to step that raises the plinth pin, as
# the template renders it: its heading, the first line of its command block,
# and its "Done when" in one line. Not found is exit 1 with why.
howto_file="docs/how-to/keep-this-project-current.md"
pin_howto() {
  local f="$top/$howto_file" sec head cmd done_when
  [ -f "$f" ] || { echo "no such file"; return 1; }
  sec="$(awk '/^## /{ on = ($0 ~ /^## [0-9]+\. .*plinth pin/) } on' "$f")"
  head="$(sed -n '1s/^## //p' <<<"$sec")"
  cmd="$(awk '/^```/{ if (inb) exit; inb = 1; next } inb && NF { print; exit }' <<<"$sec")"
  done_when="$(awk '/^\*\*Done when:\*\*/{ on = 1 } on && !NF { exit } on' <<<"$sec" | tr '\n' ' ' | sed -E 's/\*\*//g; s/ +$//')"
  [ -n "$head" ] && [ -n "$cmd" ] && [ -n "$done_when" ] || { echo "no step whose heading names the plinth pin, with a command and its Done when"; return 1; }
  printf '%s\n%s\n%s\n' "$head" "$cmd" "$done_when"
}
labelled() { awk -F '\t' -v l="$1" '("," $2 ",") ~ ("," l ",")' <<<"$2" | head -1 | field 1; }
if [ "$people_merged" -eq 0 ] && [ -z "$past_first" ]; then
  first="$(awk -F '\t' 'index($6, "docs: first pull request") == 1' <<<"$people_prs" | head -1)"
  [ -n "$first" ] || first="$(head -1 <<<"$people_prs")"
  if [ -n "$first" ]; then
    # Merging is the person's word for that pull request (#908), as for any
    # other: the agent squash-merges it then, at the head the checks ran on.
    n="$(field 1 <<<"$first")"; sha="$(field 5 <<<"$first")"
    note="pull request #$n is the project's first ($(field 9 <<<"$first")); once every check is green, saying merge #$n is the person's word for it: the agent squash-merges it at head ${sha:0:7}, where the checks ran, and brings main up to date in this folder"
    say "Repository made, its first pull request open" "merge #$n"
  else
    say "Repository made, its first pull request open" "none: no pull request is open; open the repository's pull requests page"
  fi
elif [ -n "$people_prs" ]; then
  # A red check does not turn green by waiting: that is something broke.
  if [ -n "$broken" ] && [ -n "$plinth_failing" ] && [ -n "$pin_behind" ]; then
    # A plinth job failing on a plinth older than the latest release (#904):
    # the newer plinth comes first, then this pull request's checks again.
    n="$(field 1 <<<"$broken")"
    raise="$(awk -F '\t' '$9 == "plinth"' <<<"$bot_prs" | head -1)"
    again="after it merges, pull request #$n's checks are run again on the newer plinth (the agent brings main into it with gh pr update-branch $n, which starts them), and only a check still failing then is diagnosed"
    [ -z "$own_failing" ] || again="$again; $own_failing: the project's own, where the agent fixes the code, not the check"
    if [ -n "$raise" ] && [ "$(field 4 <<<"$raise")" = pass ]; then
      note="pull request #$n's failing check ($plinth_failing) is a plinth job, and the project calls a plinth older than $pin_behind, the latest release; Dependabot's pull request #$(field 1 <<<"$raise") raises the pin and its checks are green; merging it is the person's word for that pull request; $again"
      say "Green, and seen working" "merge #$(field 1 <<<"$raise")" "A pull request with checks running"
    elif howto="$(pin_howto)"; then
      note="pull request #$n's failing check ($plinth_failing) is a plinth job, and the project calls a plinth older than $pin_behind, the latest release; "
      if [ -n "$raise" ]; then note="${note}Dependabot's pull request #$(field 1 <<<"$raise") raises the pin, its checks $(field 4 <<<"$raise"): it is merged once they are green; "
      else note="${note}no Dependabot pull request raising the pin is open; "; fi
      # The how-to's command runs in a terminal, not in the session (#908):
      # it goes in the note; /plinth:floor-check names the pin to raise.
      note="${note}from $howto_file, \"$(sed -n 1p <<<"$howto")\": in a terminal, $(sed -n 2p <<<"$howto"); $(sed -n 3p <<<"$howto"); $again"
      say "Between pieces of work" "/plinth:floor-check" "A pull request with checks running"
    else
      note="pull request #$n's failing check ($plinth_failing) is a plinth job, and the project calls a plinth older than $pin_behind, the latest release; $howto_file has no step that raises the pin ($howto), so /plinth:floor-check names the pin to raise; $again"
      say "Something broke" "/plinth:floor-check" "A pull request with checks running"
    fi
  elif [ -n "$broken" ] && [ -n "$plinth_failing" ]; then
    # A plinth job (#903): nothing in the pull request may need to change.
    n="$(field 1 <<<"$broken")"
    note="pull request #$n has a failing check that is a plinth job ($plinth_failing); the fault may be in the plinth version the project calls, not in this pull request, so the cause is read from the newest comment and the failed log first; /plinth:floor-check compares the project's plinth pin with the latest release"
    [ -z "$own_failing" ] || note="$note; $own_failing: the project's own, where the agent fixes the code, not the check"
    say "Something broke" "diagnose this: pull request #$n has a failing check in a job plinth runs; read its log and the comments before changing any code"
  elif [ -n "$broken" ]; then
    n="$(field 1 <<<"$broken")"
    note="pull request #$n has a failing check; the agent reads its log, reproduces it and fixes the code, not the check"
    say "Something broke" "diagnose this: pull request #$n has a failing check"
  else
    # The merge-next candidate when there is one (#998); else the first
    # that is not a draft; a draft only when every one open is.
    n="${merge_n:-$(awk -F '\t' '$3 == "ready" { print $1; exit }' <<<"$people_prs")}"
    n="${n:-$(head -1 <<<"$people_prs" | field 1)}"
    checks="$(awk -F '\t' -v n="$n" '$1 == n { print $9; exit }' <<<"$people_prs")"
    case "$checks" in
      "no checks ran") note="pull request #$n: no checks ran on it; find out why before /run" ;;
      "checks not started yet"*) note="pull request #$n, $checks; look again in a minute, then /run once they are green" ;;
      *) note="pull request #$n, $checks; /run once they are green" ;;
    esac
    say "A pull request with checks running" "/run"
  fi
elif [ -n "$pick" ]; then
  before="/clear"; say "A ticket ready" "/implement #$pick"
elif n="$(labelled needs-triage "$issues")" && [ -n "$n" ]; then
  note="issue #$n"; say "Something broke" "/triage"
elif n="$(awk -F '\t' '$2 == "none"' <<<"$specs" | head -1 | field 1)" && [ -n "$n" ]; then
  # Work not cut yet comes after work cut (a ready-for-agent ticket) and
  # before an unlabelled issue (#909).
  note="issue #$n is a spec no ticket was cut from yet; /to-tickets cuts it into tickets that /implement can take one at a time"
  say "A job bigger than one session" "/to-tickets #$n"
elif [ -n "$fallback" ]; then
  # A ticket without ready-for-agent, on the same skips, by its body and the
  # ready tickets' dependency edges: its own native blockers are not read.
  before="/clear"; say "A ticket ready" "/implement #$fallback"
elif n="$(awk -F '\t' '$4 == "reminder"' <<<"$issues" | head -1 | field 1)" && [ -n "$n" ]; then
  note="issue #$n is the monthly template reminder"; say "Between pieces of work" "/plinth:template-update"
elif [ "$people_merged" -eq 1 ] && [ -z "$past_first" ]; then
  say "First pull request merged" "none: three pages to follow, in order (the tool cell)"; pages_named=yes
elif [ -n "$bot_prs" ]; then
  note="then Dependabot's pull requests ($(field 1 <<<"$bot_prs" | sed 's/^/#/' | paste -sd ' ' -)), one at a time, each merged on green on the person's word"
  say "Between pieces of work" "/plinth:floor-check"
elif [ -n "$older_failed" ]; then
  # In place of /grilling (#1059): a ticket may be ready past the newest 100.
  note="the ready-for-agent issues past the newest 100 open were not read ($older_failed); look again, or list them with gh issue list --label ready-for-agent"
  say "A ticket ready" "none: the next ticket was not read"
else
  say "An idea in your own words" "/grilling"
fi
# The token step (#922): "First pull request merged" is the route only while
# nothing else is open, so past the first merge, whatever the route, a line
# of its own names its three pages while the credential gh uses in this
# session reaches the repository's Administration: the agent can still
# change the checks. The reach is read as new-project.sh reads it at creation,
# by scripts/lib/admin-reach.sh: not from the account's role alone, which
# stays admin for the owner after the token step. admin: not done; none: no
# line; read, or a reach that could not be read: not verified, with why.
# Before the first merge the step is still ahead, and on its own row the pages
# are already named: no read, no line.
if { [ "$people_merged" -gt 0 ] || [ -n "$past_first" ]; } && [ -z "${pages_named:-}" ]; then
  cells="$(row "First pull request merged")" || exit 1
  pages="$(sed -n 3p <<<"$cells")"; pages="${pages%%; *}"; step1="$(sed -n 1p <<<"$cells")"
  in_repo_gh() { (cd "$top" && gh "$@"); }
  reach="$(admin_reach in_repo_gh "$repo" "?" "?")"
  case "$reach" in
    none) ;;
    admin) token_open=yes; echo "token step: not done: the credential gh uses in this session reaches the Administration of $repo, so the agent can still change the checks; before going on, follow the three pages of $step1, in order: $pages" ;;
    read) echo "token step: not verified: the credential gh uses in this session reads the Administration of $repo, and whether it can also change it cannot be read; the agent's token should have Administration at No access, as the three pages of $step1 say, in order: $pages" ;;
    *) echo "token step: not verified: ${reach#unknown: }; the agent's token should have Administration at No access, as the three pages of $step1 say, in order: $pages" ;;
  esac
fi
# The template behind (#904): step 9's line names the update; the step the
# project is at stays the one above.
if [ -n "$template_behind" ] && [ "$said_cmd" != /plinth:template-update ]; then
  echo "step 9: template $template_behind, the tag this plinth targets: /plinth:template-update, typed"
fi

# The latest completed run of ci.yml on main (#1076): pass, fail, none, or
# not read with why. Pushes only: a pull request from a fork's own main
# branch also has head branch main. A failing one is a problem; the route
# stays as above.
# Its own read: failing, it leaves every other line as it is.
problems=""
[ -z "$broken" ] || problems="a check fails on pull request #$(field 1 <<<"$broken")"
[ -z "${token_open:-}" ] || problems="${problems:+$problems; }the token step is not done"
if run="$(cd "$top" && gh api "repos/$repo/actions/workflows/ci.yml/runs?branch=main&event=push&status=completed&per_page=1" \
      --jq '.workflow_runs[0] // empty | [.id, (.conclusion // ""), (.created_at // "")[0:10]] | @tsv' 2>&1)"; then
  if [ -z "$run" ]; then echo "main ci: none (no completed run of ci.yml on main)"
  else
    IFS=$'\t' read -r run_id run_end run_on <<<"$run"
    case "$run_end" in
      success|neutral|skipped) echo "main ci: pass (run $run_id, $run_on)" ;;
      *) echo "main ci: fail (run $run_id, $run_on, ${run_end:-no conclusion}): gh run view $run_id --log-failed"
         problems="${problems:+$problems; }main's latest CI run fails (run $run_id)" ;;
    esac
  fi
else
  echo "main ci: not read ($(tail -1 <<<"$run" | tr '\t' ' '))"
fi
echo "problems: ${problems:-none}"

# What happened so far (#1076), from one GraphQL call: when the repository
# was made and last pushed to (a push to any branch, a bot's too), the true
# totals, and the records below. Its own read: failing, started, so far and
# totals say not read and every other line stays as it is. The events that
# count, each a date, a reference, a kind and the record's title as recorded:
#   - the repository's creation;
#   - the first merge by a person: the earliest merged of the first 20 pull
#     requests opened that a person (not a Bot) wrote, or of the merged ones
#     read above when that read was not cut (nexusbt's first merge was
#     Dependabot's);
#   - closed records: issues labelled spec or wayfinder:* (not
#     wayfinder:task), among the 50 closed issues updated last;
#   - releases (not drafts) and tags with no release, the 10 newest of each;
#   - feat: merges by people, from the merged pull requests read above.
# Every other merge is counted only. The newest five are printed, newest
# first; with a problem open, only the totals line.
history_q='query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) {
  createdAt pushedAt
  mergedPulls: pullRequests(states: MERGED) { totalCount }
  closedIssues: issues(states: CLOSED) { totalCount }
  records: issues(states: CLOSED, first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) { nodes { number title closedAt labels(first: 20) { nodes { name } } } }
  releases(first: 10, orderBy: {field: CREATED_AT, direction: DESC}) { totalCount nodes { tagName name isDraft publishedAt createdAt } }
  tags: refs(refPrefix: "refs/tags/", first: 10, orderBy: {field: TAG_COMMIT_DATE, direction: DESC}) { totalCount
    nodes { name target { ... on Commit { committedDate } ... on Tag { tagger { date } } } } }
  firstMerges: pullRequests(states: MERGED, first: 20, orderBy: {field: CREATED_AT, direction: ASC}) { nodes { number title mergedAt author { __typename login } } }
} }'
history_jq='def clean: gsub("[\t\n\r]"; " ");
  def ago: ((now - fromdate) / 86400 | floor | if . < 0 then 0 else . end) as $d | "\(.[0:10]) (\($d) day\(if $d == 1 then "" else "s" end) ago)";
  def many($n; $w): "\($n) \($w)\(if $n == 1 then "" else "s" end)";
  .data.repository as $r
  | (["started", "started: \($r.createdAt | ago); last activity: \(($r.pushedAt // $r.createdAt) | ago)"],
     ["totals", "totals: \($r.mergedPulls.totalCount) merged, \(many($r.closedIssues.totalCount; "closed issue")), \(many($r.releases.totalCount; "release")), \(many($r.tags.totalCount; "tag"))"],
     ["event", $r.createdAt[0:10], $repo, "created", ""],
     ($r.records.nodes[] | ([.labels.nodes[].name | select(. == "spec" or (startswith("wayfinder:") and . != "wayfinder:task"))] | first) as $l
       | select($l != null and .closedAt != null) | ["event", .closedAt[0:10], "#\(.number)", "closed \($l)", (.title | clean)]),
     ($r.releases.nodes[] | select(.isDraft | not) | ["event", (.publishedAt // .createdAt)[0:10], .tagName, "release", ((.name // "") | clean)]),
     ([$r.releases.nodes[] | select(.isDraft | not) | .tagName] as $rel | $r.tags.nodes[] | select(.name as $t | $rel | index($t) | not)
       | (.target.committedDate // .target.tagger.date // "") as $at | select($at != "") | ["event", $at[0:10], .name, "tag", ""]),
     ($r.firstMerges.nodes[] | select(.author != null and .author.__typename != "Bot" and .mergedAt != null)
       | ["first", .mergedAt[0:10], "#\(.number)", (.title | clean)]))
  | @tsv'
if history="$(cd "$top" && gh api graphql -f owner="${repo%%/*}" -f name="${repo#*/}" -f query="$history_q" \
      --jq "\"$repo\" as \$repo | $history_jq" 2>&1)"; then
  awk -F '\t' '$1 == "started" { print $2 }' <<<"$history"
  if [ -n "$problems" ]; then
    echo "so far: counts only while a problem is open"
  else
    # The first merge by a person: the earliest of the GraphQL read's, and of
    # the merged ones read above unless that read was cut.
    events="$( { awk -F '\t' '$1 == "event" || $1 == "first"' <<<"$history"
        [ -n "$past_first" ] || awk -F '\t' '$2 == "person" { print "first\t" $3 "\t#" $1 "\t" $4 }' <<<"$merged"
        awk -F '\t' '$2 == "person" && $4 ~ /^feat(\([^)]*\))?!?:/ { print "event\t" $3 "\t#" $1 "\tmerged\t" $4 }' <<<"$merged"; } |
      awk -F '\t' '
        $1 == "first" { if (fd == "" || $2 < fd) { fd = $2; fr = $3; ft = $4 }; next }
        $2 != "" { n++; d[n] = $2; r[n] = $3; k[n] = $4; t[n] = $5 }
        END {
          if (fd != "") { n++; d[n] = fd; r[n] = fr; k[n] = "first merge by a person"; t[n] = ft; first = fr }
          for (i = 1; i <= n; i++) {
            # One line per pull request: its first merge, not also its feat: merge.
            if (k[i] == "merged" && r[i] == first) continue
            printf "%s\t%s\t%s\t%s\n", d[i], r[i], k[i], t[i]
          }
        }' | sort -t $'\t' -k1,1r -s)"
    total="$(grep -c . <<<"$events" || true)"
    if [ "$total" -eq 0 ]; then echo "so far: none recorded"
    else
      echo "so far: the newest $([ "$total" -lt 5 ] && echo "$total" || echo 5) of $total events, newest first:"
      head -5 <<<"$events" | awk -F '\t' '{ printf "  %s %s %s%s\n", $1, $2, $3, ($4 == "" ? "" : ": " $4) }'
    fi
  fi
  awk -F '\t' '$1 == "totals" { print $2 }' <<<"$history"
else
  why="$(tail -1 <<<"$history" | tr '\t' ' ')"
  printf 'started: not read (%s)\nso far: not read (%s)\ntotals: not read (%s)\n' "$why" "$why" "$why"
fi
finish
