#!/usr/bin/env bash
# What /plinth:guide reads (#710): the repository's state, what it started
# with off (#763), the row of the arsenal's "Where you are, and what to do
# next" table that state points to, the reasons it may give (#834), and the
# table itself. For a pull request with a failing check it names the checks
# that failed, whose each one is, and how many comments people left (#903).
# Read-only: it runs git and gh reads, nothing else.
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
  printf '%s\n' "$whys"
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

# Made by plinth means rendered from its template in the form the door
# writes, as floor-check's template item reads it; another Copier template
# leaves an answers file too.
template_repo="$(sed -nE 's/^template_repo="([^"]+)"$/\1/p' "$plugin/scripts/new-project.sh" 2>/dev/null)"
[ -n "$template_repo" ] || { echo "guide-state: no template_repo in $plugin/scripts/new-project.sh" >&2; exit 1; }
src="$(answer _src_path)"
if [ ! -f "$answers" ] || [ "$src" != "gh:$template_repo" ]; then
  if [ -f "$answers" ]; then echo "made by plinth: no (.copier-answers.yml names ${src:-no} template, not gh:$template_repo)"
  else echo "made by plinth: no (no .copier-answers.yml)"; fi
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

# What the project started with off and does not have yet (#763), from the
# one list new-project.sh prints at creation.
if off="$("$plugin/scripts/off-by-default.sh" "${archetype:-none}" "$top" 2>&1)"; then
  if [ -n "$off" ]; then
    echo "off by default:"; sed 's/^/  /' <<<"$off"
    if rule="$("$plugin/scripts/off-by-default.sh" --why 2>&1)"; then echo "  why: $rule"
    else echo "  why: not read ($(head -1 <<<"$rule"))"; fi
  else echo "off by default: none left off"; fi
else
  echo "off by default: not read ($(head -1 <<<"$off"))"
fi

if ! repo="$(cd "$top" && gh repo view --json nameWithOwner --jq .nameWithOwner 2>&1)"; then
  echo "repository: not read ($(head -1 <<<"$repo"))"
  echo
  echo "where: not read"
  finish
fi
echo "repository: $repo"

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

# Each read on its own, so the line names the one that failed and its error.
# Merged pull requests are read up to $read. A read that comes back full may
# have been cut (one more cannot be told apart), so the count is of those
# only and the line says so (#905).
read=100
prs=""; merged=""; issues=""; failed=""
if ! prs="$(cd "$top" && gh pr list --state open --limit 100 \
      --json number,title,isDraft,author,headRefOid,statusCheckRollup,createdAt \
      --jq "$rollup"' sort_by(.number) | .[] | [.number, (if '"$bot"' then "bot" else "person" end), (if .isDraft then "draft" else "ready" end), checks, .headRefOid, (.title | '"$clean"'), .createdAt, failing] | @tsv' 2>&1)"; then
  failed="open pull requests: $(tail -1 <<<"$prs")"
elif ! merged="$(cd "$top" && gh pr list --state merged --limit "$read" --json number,title,mergedAt,author \
      --jq 'sort_by(.mergedAt) | reverse | .[] | [.number, (if '"$bot"' then "bot" else "person" end), (.mergedAt[0:10]), (.title | '"$clean"')] | @tsv' 2>&1)"; then
  failed="merged pull requests: $(tail -1 <<<"$merged")"
elif ! issues="$(cd "$top" && gh issue list --state open --limit 100 --json number,title,labels,body \
      --jq "$kind"' sort_by(.number) | .[] | [.number, ([.labels[].name] | join(",")), (.title | '"$clean"'), kind] | @tsv' 2>&1)"; then
  failed="open issues: $(tail -1 <<<"$issues")"
fi
if [ -n "$failed" ]; then
  echo "issues and pull requests: not read ($failed)"
  echo
  echo "where: not read"
  finish
fi

field() { cut -f"$1"; }
people_prs="$(awk -F '\t' '$2 == "person"' <<<"$prs")"
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

if [ -n "$people_prs" ]; then
  echo "open pull requests:"
  awk -F '\t' '{ printf "  #%s %s, %s: %s\n", $1, $3, $9, $6 }' <<<"$people_prs"
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
# Every one of them, past the ten above: none is ever an /implement target.
not_tickets="$(awk -F '\t' '$4 == "reminder" { printf "  #%s the monthly template reminder: a person types /plinth:template-update\n", $1 }
  $4 == "person" { printf "  #%s [%s] a person'"'"'s task: a person does it\n", $1, $2 }
  $4 == "wayfinder" { printf "  #%s [%s] a wayfinder record: a person does it\n", $1, $2 }
  $4 == "spec" { printf "  #%s [%s] a spec, a record: a person does it\n", $1, $2 }' <<<"$issues")"
if [ -n "$not_tickets" ]; then echo "open issues that are not tickets, never for /implement:"; printf '%s\n' "$not_tickets"; fi
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
echo

tickets="$(awk -F '\t' '$4 == "ticket"' <<<"$issues")"
labelled() { awk -F '\t' -v l="$1" '("," $2 ",") ~ ("," l ",")' <<<"$2" | head -1 | field 1; }
if [ "$people_merged" -eq 0 ] && [ -z "$past_first" ]; then
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
  if [ -n "$broken" ] && [ -n "$plinth_failing" ]; then
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
    n="$(head -1 <<<"$people_prs" | field 1)"; checks="$(head -1 <<<"$people_prs" | field 9)"
    case "$checks" in
      "no checks ran") note="pull request #$n: no checks ran on it; find out why before /run" ;;
      "checks not started yet"*) note="pull request #$n, $checks; look again in a minute, then /run once they are green" ;;
      *) note="pull request #$n, $checks; /run once they are green" ;;
    esac
    say "A pull request with checks running" "/run" "Green, and seen working"
  fi
elif n="$(labelled ready-for-agent "$tickets")" && [ -n "$n" ]; then
  before="/clear"; say "A ticket ready" "/implement #$n"
elif n="$(labelled needs-triage "$issues")" && [ -n "$n" ]; then
  note="issue #$n"; say "Something broke" "/triage"
elif [ -n "$tickets" ]; then
  before="/clear"; say "A ticket ready" "/implement #$(head -1 <<<"$tickets" | field 1)"
elif n="$(awk -F '\t' '$4 == "reminder"' <<<"$issues" | head -1 | field 1)" && [ -n "$n" ]; then
  note="issue #$n is the monthly template reminder"; say "Between pieces of work" "/plinth:template-update"
elif [ "$people_merged" -eq 1 ] && [ -z "$past_first" ]; then
  say "First pull request merged" "none: three pages to follow, in order (the tool cell)" "An idea in your own words"
elif [ -n "$bot_prs" ]; then
  say "Between pieces of work" "/plinth:floor-check (then the Dependabot pull requests, one at a time, on green)"
else
  say "An idea in your own words" "/grilling"
fi
finish
