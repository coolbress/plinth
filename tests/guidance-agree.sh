#!/usr/bin/env bash
# The agent and the person are told the same next step in each situation
# (#1146). For each situation, the command or page its next step is (not the
# words around it) must be named by every surface that speaks to it:
#
#   - agents: the template's AGENTS.md at the pin scripts/new-project.sh
#     holds (tests/lib/template-checkout.sh), the agent's every session;
#   - arsenal: skills/arsenal/SKILL.md's stage-table row;
#   - run-a-project: docs/how-to/run-a-project.md's section;
#   - guide: what scripts/guide-state.sh prints (command, before, note) on a
#     fixture of that state, with tests/guide-cases.sh's stand-in for gh.
#
# tests/lib/guidance_surfaces.py reads the first three and says which part of
# each it reads. A disagreement known today is listed below with the ticket
# that removes it; that ticket deletes its line. The list only shrinks: a
# listed entry that agrees now fails until its line goes, and an unlisted
# disagreement fails. Last, once /plinth:records-check is retired (#1108, its
# skill folder gone), no shipped surface may tell the person to type it.
set -uo pipefail
root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
work="$(mktemp -d)" && work="$(cd "$work" && pwd -P)" || { echo "guidance-agree: could not make a temp folder" >&2; exit 1; }
trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

# situation<TAB>surface<TAB>the ticket that removes it
known='coming-back	agents	coolbress/plinth-template#372
look-back	agents	coolbress/plinth-template#372
coming-back	arsenal	#1259'

# shellcheck source=tests/lib/template-checkout.sh
. "$root/tests/lib/template-checkout.sh"
if ! template_checkout "$work"; then
  bad "the template at the pin was not read: $template_error"; echo "-- $pass passed, $fail failed"; exit 1
fi
agents="$template_dir/template/AGENTS.md.jinja"
[ -f "$agents" ] || { bad "no template/AGENTS.md.jinja in the template at $template_at"; echo "-- $pass passed, $fail failed"; exit 1; }

found="$(python3 "$root/tests/lib/guidance_surfaces.py" "$root" "$agents" 2>&1)" ||
  { bad "the surfaces were not read: $(tail -1 <<<"$found")"; echo "-- $pass passed, $fail failed"; exit 1; }

# The guide, on a fixture of each state it routes: the stand-in gh is
# tests/guide-cases.sh's own, taken from that file so the two never differ.
mkdir -p "$work/bin" "$work/api"
sed -n "/^cat > \"\$work\/bin\/gh\" <<'MOCK'\$/,/^MOCK\$/p" "$root/tests/guide-cases.sh" | sed '1d;$d' > "$work/bin/gh"
if [ ! -s "$work/bin/gh" ]; then
  bad "tests/guide-cases.sh's stand-in gh was not found: the guide was not read"
else
  chmod +x "$work/bin/gh"
  export PATH="$work/bin:$PATH" FLOOR_CHECK_API_DIR="$work/api" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  # state <name> <archetype>: a checkout plinth made, its records empty.
  state() {
    local d="$work/$1"; mkdir -p "$d"; git -C "$d" init -q
    printf '_commit: v1.28.0\n_src_path: gh:coolbress/plinth-template\narchetype: %s\n' "$2" > "$d/.copier-answers.yml"
    for f in open merged issues all; do printf '[]' > "$d/$f.json"; done
    echo "$d"
  }
  # prs <file> <number:title:person|bot:checks:hours ago>...: pull requests in gh's shape.
  prs() {
    local f="$1"; shift
    python3 - "$f" "$@" <<'PY'
import json, sys, time
out = []
for spec in sys.argv[2:]:
    n, rest = spec.split(":", 1)
    title, who, checks, hours = rest.rsplit(":", 3)
    at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - float(hours) * 3600))
    roll = [] if checks == "-" else [{"status": "COMPLETED", "conclusion": checks}]
    out.append({"number": int(n), "title": title, "isDraft": False,
                "author": {"login": "app/dependabot" if who == "bot" else "someone", "is_bot": who == "bot"},
                "headRefOid": "%040d" % int(n), "statusCheckRollup": roll, "mergedAt": at, "createdAt": at,
                "commits": [{"oid": "%040d" % int(n), "committedDate": at}]})
json.dump(out, open(sys.argv[1], "w"))
PY
  }
  guide() { # <situation> <dir> <token>...: each token in the guide's command, before or note lines
    local situation="$1" d="$2" out lines lacking="" t; shift 2
    out="$(MOCK_DIR="$d" bash "$root/scripts/guide-state.sh" "$d" 2>&1)"
    lines="$(grep -E '^(command|before|note): ' <<<"$out")"
    # A token ends where a word does, as the surfaces' are read.
    for t in "$@"; do grep -qiE -- "$(sed 's/[][\.*^$/]/\\&/g' <<<"$t")([^[:alnum:]_-]|\$)" <<<"$lines" || lacking="${lacking:+$lacking, }$t"; done
    if [ -z "$lines" ]; then printf '%s\tguide\tmissing: the part (no command line; %s)\n' "$situation" "$(head -1 <<<"$out")"
    elif [ -n "$lacking" ]; then printf '%s\tguide\tmissing: %s\n' "$situation" "$lacking"
    else printf '%s\tguide\tok\n' "$situation"; fi
  }
  # A merge broke main: the newest merge, #9, and main's latest run on it failed.
  d="$(state main-broke cli)"
  prs "$d/merged.json" "2:docs: first:person:SUCCESS:48" "9:feat: totals:person:SUCCESS:2"
  printf '{"total_count":1,"workflow_runs":[{"id":31,"conclusion":"failure","created_at":"2026-10-28T10:00:00Z","head_commit":{"message":"feat: totals (#9)"}}]}' > "$d/runs.json"
  found="$found"$'\n'"$(guide main-broke "$d" undo-a-merged-change.md)"
  # A check failed on an open pull request, main green.
  d="$(state diagnose cli)"
  prs "$d/merged.json" "2:docs: first:person:SUCCESS:48" "3:feat: a:person:SUCCESS:24"
  prs "$d/open.json" "12:feat: export:person:FAILURE:1"
  found="$found"$'\n'"$(guide diagnose "$d" "diagnose this")"
  # A ticket ready.
  d="$(state implement cli)"
  prs "$d/merged.json" "2:docs: first:person:SUCCESS:48" "3:feat: a:person:SUCCESS:24"
  printf '[{"number":5,"title":"Show totals","labels":[{"name":"ready-for-agent"}],"body":"## What to build\\n\\nx"}]' > "$d/issues.json"
  found="$found"$'\n'"$(guide implement "$d" /clear /implement)"
  # A look back due: twelve feat: merges since the last one, two days ago; a
  # web project, so no release is due beside it.
  d="$(state look-back web)"
  specs=(); for i in $(seq 1 12); do specs+=("$i:feat: change $i:person:SUCCESS:1"); done
  prs "$d/merged.json" "${specs[@]}"
  python3 - "$d/history.json" <<'PY'
import json, sys, time
two = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 2 * 86400))
json.dump({"data": {"lookBack": {"nodes": [{"number": 40, "title": "Look back " + two[:10], "createdAt": two}]},
  "repository": {"createdAt": "2026-10-01T00:00:00Z", "pushedAt": two, "mergedPulls": {"totalCount": 12},
  "closedIssues": {"totalCount": 0}, "records": {"nodes": []}, "releases": {"totalCount": 0, "nodes": []},
  "tags": {"totalCount": 0, "nodes": []}, "firstMerges": {"nodes": []}}}}, open(sys.argv[1], "w"))
PY
  found="$found"$'\n'"$(guide look-back "$d" /plinth:floor-check "look back")"
fi

# Each finding against the known list.
while IFS=$'\t' read -r situation surface said; do
  [ -n "$situation" ] || continue
  ticket="$(awk -F '\t' -v s="$situation" -v f="$surface" '$1 == s && $2 == f { print $3; exit }' <<<"$known")"
  if [ "$said" = ok ] && [ -z "$ticket" ]; then ok "$situation: $surface names its next step"
  elif [ "$said" = ok ]; then bad "$situation: $surface agrees now: remove its known entry ($ticket)"
  elif [ -n "$ticket" ]; then ok "$situation: $surface, known until $ticket ($said)"
  else bad "$situation: $surface disagrees ($said): fix it, or list it with the ticket that will"; fi
done <<<"$found"
# Each known entry is still a surface the test reads.
while IFS=$'\t' read -r situation surface ticket; do
  [ -n "$situation" ] || continue
  awk -F '\t' -v s="$situation" -v f="$surface" '$1 == s && $2 == f { found = 1 } END { exit !found }' <<<"$found" ||
    bad "the known entry $situation $surface ($ticket) names nothing the test reads: remove it"
done <<<"$known"

# /plinth:records-check retired (#1108): no shipped surface names it.
if [ -d "$root/skills/records-check" ]; then
  ok "/plinth:records-check still ships (until #1108), so naming it is not checked"
else
  # Named as a command, with or without the plugin's prefix (README's skill
  # table writes `records-check [owner/name]`), on the pages and in what the
  # guide prints.
  pat='(^|[^[:alnum:]_-])(/plinth:)?records-check([^[:alnum:]_-]|$)'
  left="$({ grep -rlE "$pat" "$root/skills" "$root/docs/how-to" "$root/docs/tutorials" "$root/README.md" "$root/scripts/guide-state.sh" 2>/dev/null; grep -lE "$pat" "$agents"; } | sed "s|^$root/||")"
  if [ -z "$left" ]; then ok "/plinth:records-check is retired and no shipped surface names it"
  else bad "/plinth:records-check is retired, but these still name it: $(paste -sd ' ' - <<<"$left")"; fi
fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
