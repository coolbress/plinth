#!/usr/bin/env bash
# /plinth:guide (#710), offline. scripts/guide-state.sh is run on fixture
# checkouts with a mock `gh` that applies the script's own --jq filter to
# JSON in GitHub's shape, as gh does; each case asserts the row it lands on
# and the command it prints. Then tests/lib/guide-names.sh: the skill names
# no slash command outside the arsenal's table, and a text that does, or
# that names a tool #711 left out, fails (the must-not-pass cases first).
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/guide-state.sh"
names="$root/tests/lib/guide-names.sh"
arsenal="$root/skills/arsenal/SKILL.md"
work="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'MOCK'
#!/usr/bin/env bash
# MOCK_DIR holds open.json, merged.json, issues.json and all.json, and comments.json
# when a case reads a pull request's comments; MOCK_GH_FAIL makes every call
# fail as an unauthenticated gh does. A list is cut at --limit.
set -u
[ -n "${MOCK_GH_FAIL:-}" ] && { echo "To get started with GitHub CLI, please run:  gh auth login" >&2; exit 4; }
jqf="."; limit=30; fields=""; prev=""
for a in "$@"; do [ "$prev" = --jq ] && jqf="$a"; [ "$prev" = --limit ] && limit="$a"; [ "$prev" = --json ] && fields="$a"; prev="$a"; done
[ -n "${MOCK_FAIL_ON:-}" ] && [ "$1 $2 ${4:-}" = "$MOCK_FAIL_ON" ] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
# GET repos/<o>/<r>/commits/<sha>: the commit by that oid in open.json's
# pull requests, in the REST shape. MOCK_API_FAIL fails it.
if [ "$1" = api ] && [[ "$2" == repos/*/commits/* ]]; then
  [ -n "${MOCK_API_FAIL:-}" ] && { echo "HTTP 404: Not Found" >&2; exit 1; }
  set -o pipefail
  jq --arg s "${2##*/}" '[.[].commits[]? | select(.oid == $s)] | first | {commit: {committer: {date: .committedDate}}}' "$MOCK_DIR/open.json" | jq -r "$jqf"
  exit
fi
# As GitHub does (#906): a list asking for each pull request's commits asks
# for more nodes than GraphQL allows, so the whole read fails.
case ",$fields," in *,commits,*) [ "$1" = pr ] && { echo "GraphQL: By the time this query traverses to the authors connection, it is requesting up to 1,000,000 possible nodes which exceeds the maximum limit of 500,000." >&2; exit 1; } ;; esac
case "$1 $2 ${4:-}" in
  "repo view"*)        echo o/r; exit 0 ;;
  "pr list open")      f=open.json ;;
  "pr list merged")    f=merged.json ;;
  "issue list open")   f=issues.json ;;
  # The search for issues naming a spec under ## Parent (#909): every issue
  # in all.json, the search words not applied, so the script's filter is
  # what picks. MOCK_ALL_FAIL fails it; MOCK_ALL_LOG counts the calls.
  "issue list all")    [ -z "${MOCK_ALL_LOG:-}" ] || echo search >> "$MOCK_ALL_LOG"
                       [ -n "${MOCK_ALL_FAIL:-}" ] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }; f=all.json ;;
  "api repos/o/r/issues/"*"/comments "*) f=comments.json ;;
  *) echo "mock gh: unexpected $*" >&2; exit 1 ;;
esac
# As gh does: the --limit highest numbers (30 unless said), then the filter.
# They stay in the fixture's order, so the script's own sorting is what sorts.
set -o pipefail
# Only the --json fields asked for, as gh gives.
jq --argjson n "$limit" --arg f "$fields" '(map(.number) | sort | reverse | .[:$n]) as $keep | map(select(.number as $x | $keep | index($x)))
  | if $f == "" then . else map(with_entries(select(.key as $k | $f | split(",") | index($k)))) end' "$MOCK_DIR/$f" | jq -r "$jqf"
MOCK
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"
# floor-check's reads (#904) come from fixtures here, never the network: an
# empty folder is a 404 for each, which it says as not read.
export FLOOR_CHECK_API_DIR="$work/api"; mkdir -p "$FLOOR_CHECK_API_DIR"

# repo <name> [answers]: a git checkout, with .copier-answers.yml unless "none".
repo() {
  local d="$work/$1"; mkdir -p "$d"; git -C "$d" init -q
  [ "${2:-}" = none ] || printf '_commit: v1.28.0\n_src_path: %s\n%s\n' "${SRC:-gh:coolbress/plinth-template}" "${2:-archetype: cli}" > "$d/.copier-answers.yml"
  printf '[]' > "$d/open.json"; printf '[]' > "$d/merged.json"; printf '[]' > "$d/issues.json"; printf '[]' > "$d/all.json"
  echo "$d"
}
# ago <seconds>: that long before now, in GitHub's form.
ago() { jq -nr --argjson s "$1" 'now - $s | floor | todate'; }
pr() { # <number> <title> <bot:true|false> <check conclusion or "-" for none, "run" for in progress>
       # [<head commit's age in seconds, default a day>] [<pull request's age, default a day>]
  local checks='[]'
  case "$4" in
    -) ;; run) checks='[{"status":"IN_PROGRESS","conclusion":""}]' ;;
    *) checks="[{\"status\":\"COMPLETED\",\"conclusion\":\"$4\"},{\"state\":\"SUCCESS\"}]" ;;
  esac
  printf '{"number":%s,"title":"%s","isDraft":false,"author":{"login":"%s","is_bot":%s},"headRefOid":"%040d","statusCheckRollup":%s,"mergedAt":"2026-10-2%sT00:00:00Z","createdAt":"%s","commits":[{"oid":"%040d","committedDate":"2026-01-01T00:00:00Z"},{"oid":"%040d","committedDate":"%s"}]}' \
    "$1" "$2" "$([ "$3" = true ] && echo app/dependabot || echo someone)" "$3" "$1" "$checks" "$(( $1 % 10 ))" \
    "$(ago "${6:-86400}")" 0 "$1" "$(ago "${5:-86400}")"
}
put() { local f="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$f"; }
issue() { local l=""; [ -z "$3" ] || l="{\"name\":\"$3\"}"; printf '{"number":%s,"title":"%s","labels":[%s]}' "$1" "$2" "$l"; }

# expect <case> <dir> <where starts with> <command line> [<other expected line>]
expect() {
  local out; out="$(MOCK_DIR="$2" "$script" "$2" 2>&1)"; local rc=$?
  if [ "$rc" -eq 0 ] && grep -qF "where: $3" <<<"$out" && grep -qxF "command: $4" <<<"$out" &&
     { [ -z "${5:-}" ] || grep -qF -- "$5" <<<"$out"; } && grep -qx 'table:' <<<"$out"; then
    ok "$1"
  else
    bad "$1 (wanted where: $3 / command: $4${5:+ / $5}; exit $rc)"; sed 's/^/        /' <<<"$out" | head -14
  fi
}

d="$work/plain"; mkdir -p "$d"
expect "no git checkout: create one" "$d" "No repository yet (step 1)" "/plinth:new-project <owner>/<name>"

d="$(repo other none)"
expect "a checkout plinth did not make: floor-check" "$d" "A repository plinth did not make" "/plinth:floor-check"

d="$(SRC=gh:someone/other-template repo foreign)"
expect "another Copier template's answers file: not made by plinth" "$d" "A repository plinth did not make" "/plinth:floor-check" "not gh:coolbress/plinth-template"
d="$(SRC=/home/x/coolbress/plinth-template repo local-src)"
expect "a local copy of the template is not the door's form either" "$d" "A repository plinth did not make" "/plinth:floor-check"

d="$(repo created)"
put "$d/open.json" "$(pr 1 'chore(deps): bump actions/checkout' true SUCCESS)" "$(pr 2 'docs: first pull request through the wall' false run)"
expect "just created, Dependabot's pull request first: the door's is the one to merge" "$d" \
  "Repository made, its first pull request open (step 1)" \
  "body=\"\$(gh pr view 2 --json body --jq .body)\" && gh pr merge 2 --squash --match-head-commit $(printf '%040d' 2) --body \"\$body\"" \
  "checks pending"

d="$(repo first-merged)"
put "$d/merged.json" "$(pr 2 'docs: first pull request through the wall' false SUCCESS)"
put "$d/open.json" "$(pr 3 'chore(deps): bump x' true SUCCESS)"
expect "first pull request merged, no issue: the token, the account, four things; then step 2" "$d" \
  "First pull request merged (step 1)" "none: three pages to follow, in order (the tool cell)" "then: An idea in your own words (step 2)"

d="$(repo issue-open "archetype: web
hosting: render")"
put "$d/merged.json" "$(pr 2 'docs: first pull request through the wall' false SUCCESS)"
put "$d/issues.json" "$(issue 4 'Ask the user for their name' '')" "$(issue 5 'Show monthly totals' ready-for-agent)"
expect "an issue open: the ready-for-agent one, not the lowest number" "$d" "A ticket ready (step 4)" "/implement #5" "before: /clear"
grep -q "hosting: render" <<<"$(MOCK_DIR="$d" "$script" "$d")" && ok "a web project says where it runs" || bad "web: no hosting line"
# What it started with off (#763), through scripts/off-by-default.sh.
out="$(MOCK_DIR="$d" "$script" "$d")"
if grep -qx 'off by default:' <<<"$out" && grep -q '^  off: The third-party reviewer' <<<"$out" && grep -q '^  started off .*: HSTS preload' <<<"$out"
then ok "a web project names the reviewer and HSTS as off"; else bad "web: off-by-default lines"; sed 's/^/        /' <<<"$out" | head -14; fi
d2="$(repo cli-off)"
out="$(MOCK_DIR="$d2" "$script" "$d2")"
if grep -q '^  off: The third-party reviewer' <<<"$out" && ! grep -q 'HSTS' <<<"$out"
then ok "a cli project names the reviewer, not the web item"; else bad "cli: off-by-default lines"; fi
# The told rows (#772): a sign the project has drops its row; one with no
# sign is said to have started off, since whether it is on is not read.
: > "$d2/SUPPORT.md"; out="$(MOCK_DIR="$d2" "$script" "$d2")"; rm "$d2/SUPPORT.md"
if ! grep -q 'A support file' <<<"$out" && grep -q '^  off: Sponsorship' <<<"$out" && grep -q '^  started off (whether it is on now is not read): Topics' <<<"$out"
then ok "a cli project with SUPPORT.md: that row is gone, sponsorship is off, topics started off"
else bad "the told rows in the guide"; grep -iE 'support|sponsor|topics' <<<"$out" | sed 's/^/        /'; fi
mkdir -p "$d2/.github/workflows"; : > "$d2/.github/workflows/third-party.yml"
out="$(MOCK_DIR="$d2" "$script" "$d2")"
# The reviewer itself is not listed; the steps a project with its caller still
# has (#765) are, as started off, since none of them can be read from files.
if ! grep -qF 'The third-party reviewer (' <<<"$out" && [ "$(grep -cE 'started off \(whether it is on now is not read\): (The summons token|Requiring the third-party reviewer)' <<<"$out")" = 2 ] \
   && grep -qF 'to do, if not done yet (whether it is done is not read): Turn on Codex code review for this repository' <<<"$out" \
   && grep -qF 'Requiring the third-party reviewer' <<<"$out"
then ok "a cli project with the reviewer's caller: the reviewer is not listed; turning it on for the repository is a step to do, the other two started off"
else bad "cli with the caller: off-by-default lines"; grep -i off <<<"$out" | sed 's/^/        /'; fi

d="$(repo pr-open)"
put "$d/merged.json" "$(pr 2 'docs: first pull request through the wall' false SUCCESS)"
put "$d/open.json" "$(pr 6 'feat: monthly totals' false run)"
put "$d/issues.json" "$(issue 5 'Show monthly totals' ready-for-agent)"
expect "a pull request open comes before the issue it closes" "$d" "A pull request with checks running (step 5)" "/run" "note: pull request #6, checks pending"
put "$d/open.json" "$(pr 6 'feat: monthly totals' false FAILURE)"
expect "a pull request with a failing check: something broke, not wait" "$d" "Something broke (step 7)" \
  "diagnose this: pull request #6 has a failing check" "#6 ready, checks fail"
# An empty rollup (#906): just pushed is checks starting, not a broken wall;
# an hour on, no check ran. Neither is "Something broke".
put "$d/open.json" "$(pr 6 'feat: monthly totals' false - 60)"
expect "an empty rollup a minute after the push: checks not started yet" "$d" "A pull request with checks running (step 5)" "/run" \
  "#6 ready, checks not started yet (last change 1 min ago): feat: monthly totals"
grep -qF "note: pull request #6, checks not started yet (last change 1 min ago); look again in a minute" <<<"$(MOCK_DIR="$d" "$script" "$d")" &&
  ok "the note says to look again in a minute" || bad "no look-again note for checks not started yet"
put "$d/open.json" "$(pr 6 'feat: monthly totals' false - 3600)"
expect "an empty rollup an hour after the push: no checks ran" "$d" "A pull request with checks running (step 5)" "/run" \
  "#6 ready, no checks ran: feat: monthly totals"
grep -qF "note: pull request #6: no checks ran on it; find out why before /run" <<<"$(MOCK_DIR="$d" "$script" "$d")" &&
  ok "the note says to look into why no check ran" || bad "no look-into-it note for no checks ran"
put "$d/open.json" "$(pr 6 'feat: monthly totals' false - 3600 120)"
expect "an hour-old commit in a pull request opened two minutes ago: not started yet" "$d" "A pull request with checks running (step 5)" "/run" \
  "#6 ready, checks not started yet (last change 2 min ago)"
put "$d/open.json" "$(pr 6 'feat: monthly totals' false - 3600)" "$(pr 7 'feat: other' false - 60)"
grep -qF "#7 ready, checks not started yet (last change 1 min ago)" <<<"$(MOCK_DIR="$d" "$script" "$d")" &&
  ok "each pull request reads its own head" || bad "two pull requests: the second one's head not read"
put "$d/open.json" "$(pr 6 'feat: monthly totals' false - 3600)"
out="$(MOCK_API_FAIL=1 MOCK_DIR="$d" "$script" "$d" 2>&1)"
grep -qF "#6 ready, no checks yet; when its head was pushed was not read" <<<"$out" && grep -qF "where: A pull request with checks running (step 5)" <<<"$out" &&
  ok "the head's time not read: said so, not guessed, and not Something broke" || { bad "the head's time not read"; sed 's/^/        /' <<<"$out" | head -14; }
put "$d/open.json" "$(pr 6 'feat: monthly totals' false - -1200)"
expect "a head commit dated ahead of the clock: not started yet, never a negative age" "$d" "A pull request with checks running (step 5)" "/run" \
  "#6 ready, checks not started yet (last change 0 min ago)"

# Which check failed, and whose it is (#903). A job of a workflow the project
# calls from coolbress/plinth is plinth's: the fault may be in the version it
# calls, so the note does not send the agent to fix the code. The project's
# own keeps the note above.
run() { # <name> <conclusion> [<job id>]: a check run as gh's statusCheckRollup has it
  printf '{"__typename":"CheckRun","name":"%s","status":"COMPLETED","conclusion":"%s","detailsUrl":"%s"}' "$1" "$2" \
    "${3:+https://github.com/o/r/actions/runs/900/job/$3}"
}
prc() { # <number> <title> <check>...: a person's open pull request with those checks
  local n="$1" t="$2"; shift 2; local IFS=,
  printf '{"number":%s,"title":"%s","isDraft":false,"author":{"login":"someone","is_bot":false},"headRefOid":"%040d","statusCheckRollup":[%s]}' "$n" "$t" "$n" "$*"
}
comment() { printf '{"id":%s,"user":{"login":"%s","type":"%s"},"body":"x"}' "$1" "$2" "$3"; }
# state <case> <dir> <line>...: every line is in the output, whole; a line
# starting with "!" must be in no line of it.
state() {
  local name="$1" out miss="" l; out="$(MOCK_DIR="$2" "$script" "$2" 2>&1)"; shift 2
  for l in "$@"; do
    case "$l" in
      '!'*) grep -qF -- "${l#!}" <<<"$out" && miss="$miss
        has: ${l#!}" ;;
      *) grep -qxF -- "$l" <<<"$out" || miss="$miss
        no line: $l" ;;
    esac
  done
  if [ -z "$miss" ]; then ok "$name"; else bad "$name:$miss"; sed 's/^/        /' <<<"$out" | head -24; fi
}
mkdir -p "$d/.github/workflows"
printf 'name: CI\non:\n  pull_request:\njobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%040d # v2.28.0\n    with:\n      archetype: cli\n' 7 > "$d/.github/workflows/ci.yml"
printf 'name: Label\non:\n  pull_request_target:\njobs:\n  label:\n    uses: "coolbress/plinth/.github/workflows/pr-label.yml@%040d"\n' 8 > "$d/.github/workflows/label.yml"
printf 'name: Own\non: pull_request\njobs:\n  smoke:\n    runs-on: ubuntu-latest\n    steps:\n      - run: "true"\n  local:\n    name: ci-local\n    uses: ./.github/workflows/reused.yml\n' > "$d/.github/workflows/own.yml"
put "$d/comments.json" "$(comment 1 someone User)" "$(comment 2 'github-actions[bot]' Bot)" "$(comment 3 another User)"
put "$d/open.json" "$(prc 6 'feat: monthly totals' "$(run 'ci / build' FAILURE 456)" "$(run 'ci / test' SUCCESS 457)")"
state "only ci / build failing: named, a plinth job, and the note does not say to fix the code" "$d" \
  "where: Something broke (step 7)" \
  "failing checks on pull request #6:" \
  "  ci / build: a plinth job (the project calls coolbress/plinth's python-ci.yml at v2.28.0)" \
  "    log: gh run view --job 456 --log-failed" \
  "comments by people on pull request #6: 2" \
  "command: diagnose this: pull request #6 has a failing check in a job plinth runs; read its log and the comments before changing any code" \
  "!fixes the code" "!ci / test"
out="$(MOCK_DIR="$d" "$script" "$d" 2>&1)"
grep -E '^note: ' <<<"$out" | grep -qF 'the fault may be in the plinth version the project calls' && grep -E '^note: ' <<<"$out" | grep -qF "/plinth:floor-check compares the project's plinth pin with the latest release" && ! grep -qE '#[0-9]+|/issues/[0-9]' <<<"$(grep -E '^note: ' <<<"$out" | sed 's/pull request #6//g')" &&
  ok "the plinth job's note: maybe the plinth version the project calls, floor-check compares the pin, and no issue number of plinth's" || bad "the plinth job's note: $(grep -E '^note: ' <<<"$out")"
put "$d/open.json" "$(prc 6 'feat: monthly totals' "$(run 'label / label' FAILURE 458)")"
state "label / label failing, its pin with no version comment: a plinth job, at the commit" "$d" \
  "  label / label: a plinth job (the project calls coolbress/plinth's pr-label.yml at $(printf '%040d' 8))" "!fixes the code"
put "$d/open.json" "$(prc 6 'feat: monthly totals' "$(run 'smoke' FAILURE 459)")"
state "a failing check of the project's own: the fix-the-code note stays" "$d" \
  "  smoke: the project's own" "    log: gh run view --job 459 --log-failed" \
  "command: diagnose this: pull request #6 has a failing check" \
  "note: pull request #6 has a failing check; the agent reads its log, reproduces it and fixes the code, not the check"
put "$d/open.json" "$(prc 6 'feat: monthly totals' "$(run 'ci-local / test' FAILURE 460)")"
state "a job of a workflow the project calls from itself: the project's own" "$d" \
  "  ci-local / test: the project's own" \
  "note: pull request #6 has a failing check; the agent reads its log, reproduces it and fixes the code, not the check"
mv "$d/.github/workflows/ci.yml" "$d/ci.yml.away"
printf 'name: CI\non: pull_request\njobs:\n  ci:\n    uses: ./.github/workflows/reused.yml\n' > "$d/.github/workflows/ci.yml"
put "$d/open.json" "$(prc 6 'feat: monthly totals' "$(run 'ci / test' FAILURE 461)")"
state "ci / test from a local workflow: the name alone does not make it plinth's" "$d" \
  "  ci / test: the project's own" \
  "note: pull request #6 has a failing check; the agent reads its log, reproduces it and fixes the code, not the check"
mv "$d/ci.yml.away" "$d/.github/workflows/ci.yml"
printf 'name: M\non: pull_request\njobs:\n    mx:\n        strategy:\n            matrix:\n                kind: [cli]\n        uses: Coolbress/Plinth/.github/workflows/python-ci.yml@v2.30.0\n' > "$d/.github/workflows/matrix.yml"
put "$d/open.json" "$(prc 6 'feat: monthly totals' "$(run 'mx (cli) / build' FAILURE 462)")"
state "a matrix on the caller job, four-space indent, the repository in another case: a plinth job" "$d" \
  "  mx (cli) / build: a plinth job (the project calls coolbress/plinth's python-ci.yml at v2.30.0)" "!fixes the code"
rm "$d/.github/workflows/matrix.yml"
put "$d/open.json" "$(prc 6 'feat: monthly totals' "$(run 'ci / build' FAILURE 456)" "$(run 'smoke' TIMED_OUT 459)" '{"__typename":"StatusContext","context":"deploy/preview","state":"FAILURE","targetUrl":"https://example.com/x"}')"
state "a plinth job and two of the project's own failing: each named, the note says both" "$d" \
  "  ci / build: a plinth job (the project calls coolbress/plinth's python-ci.yml at v2.28.0)" \
  "  smoke: the project's own" "  deploy/preview: the project's own" \
  "command: diagnose this: pull request #6 has a failing check in a job plinth runs; read its log and the comments before changing any code"
out="$(MOCK_DIR="$d" "$script" "$d" 2>&1)"
grep -E '^note: ' <<<"$out" | grep -qF 'smoke, deploy/preview: the project'"'"'s own, where the agent fixes the code, not the check' && [ "$(grep -c '^    log: ' <<<"$out")" = 2 ] &&
  ok "the mixed note keeps fix-the-code for the project's own; a commit status has no log line" || bad "the mixed note: $(grep -E '^note: |log:' <<<"$out")"
put "$d/open.json" "$(prc 6 'feat: monthly totals' "$(run 'ci / build' FAILURE 456)")"
out="$(MOCK_FAIL_ON="api repos/o/r/issues/6/comments --jq" MOCK_DIR="$d" "$script" "$d" 2>&1)"
grep -qxF 'comments by people on pull request #6: not read (HTTP 502: Bad Gateway)' <<<"$out" && grep -qxF 'where: Something broke (step 7)' <<<"$out" &&
  ok "the comments not read: said so with gh's error, the step still named" || bad "comments not read: $(grep -F comments <<<"$out")"
printf '[]' > "$d/comments.json"
state "no comment by a person: 0" "$d" "comments by people on pull request #6: 0"
put "$d/open.json" "$(pr 6 'feat: monthly totals' false run)"
state "no failing check: no failing-checks lines, no comments read" "$d" "where: A pull request with checks running (step 5)" "!failing checks on" "!comments by people"
if grep -qF 'gh run view' "$root/skills/guide/SKILL.md" && grep -qiF 'newest comment' "$root/skills/guide/SKILL.md" &&
   grep -qF 'before you name a cause' "$root/skills/guide/SKILL.md" && grep -qF 'not known yet' "$root/skills/guide/SKILL.md"
then ok "the skill says to read the comment and the failed log before naming a cause, and 'not known yet' when neither names one"
else bad "the skill does not say to read the comment and the failed log before naming a cause"; fi

# Behind (#904): the template tag against the one this plinth targets, the
# plinth pin against plinth's latest release, read by floor-check.py
# --print-behind. A plinth job failing on a pin behind takes the newer plinth
# first: Dependabot's green pull request is merged on the person's word, or
# the project's how-to says how the pin is raised.
target="$(sed -nE 's/^template_ref="([^"]+)"$/\1/p' "$root/scripts/new-project.sh")"
pin="$(printf 'a%039d' 28)"
api="$FLOOR_CHECK_API_DIR/repos/coolbress/plinth"; mkdir -p "$api/compare"
release() { printf '{"tag_name":"%s"}' "$1" > "$api/releases/latest.json"; }
mkdir -p "$api/releases"; release v2.31.0
printf '{"status":"ahead","ahead_by":28,"behind_by":0}' > "$api/compare/$pin...v2.31.0?per_page=1&page=2.json"
d="$(repo behind)"
mkdir -p "$d/.github/workflows" "$d/docs/how-to"
printf 'name: CI\non: pull_request\njobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s # v2.28.0\n' "$pin" > "$d/.github/workflows/ci.yml"
printf 'name: Label\non: pull_request_target\njobs:\n  label:\n    uses: coolbress/plinth/.github/workflows/pr-label.yml@%s # v2.28.0\n' "$pin" > "$d/.github/workflows/label.yml"
put "$d/merged.json" "$(pr 2 'docs: first' false SUCCESS)" "$(pr 7 'feat: x' false SUCCESS)"
put "$d/issues.json" "$(issue 5 'Show monthly totals' ready-for-agent)"
state "the template tag behind: the gap and the tag it is behind; step 9 names the update, the step stays" "$d" \
  "template: v1.28.0, behind $target, the tag this plinth targets" \
  "step 9: template v1.28.0 is behind $target, the tag this plinth targets: /plinth:template-update, typed" \
  "where: A ticket ready (step 4)" "command: /implement #5"
state "the plinth pin behind: the gap and the release it is behind" "$d" \
  "plinth pin: $pin, behind v2.31.0, the latest plinth release, 28 commit(s) behind"
printf '_commit: %s\n_src_path: gh:coolbress/plinth-template\narchetype: cli\n' "$target" > "$d/.copier-answers.yml"
state "the template at the tag this plinth targets: said, no step 9 line" "$d" \
  "template: $target, the tag this plinth targets" "!step 9:"
put "$d/issues.json" "$(issue 11 "Template update available: v1.28.0 to $target" '')"
printf '_commit: v1.28.0\n_src_path: gh:coolbress/plinth-template\narchetype: cli\n' > "$d/.copier-answers.yml"
state "the reminder's own step is the update already: no second step 9 line" "$d" \
  "command: /plinth:template-update" "!step 9:"
put "$d/issues.json" "$(issue 5 'Show monthly totals' ready-for-agent)"

dependabot() { # <number> <title> <conclusion> [<body>]: Dependabot's open pull request
  printf '{"number":%s,"title":"%s","body":"%s","isDraft":false,"author":{"login":"app/dependabot","is_bot":true},"headRefOid":"%040d","statusCheckRollup":[%s]}' \
    "$1" "$2" "${4:-}" "$1" "$(run 'ci / build' "$3")"
}
build_fails="$(prc 6 'feat: monthly totals' "$(run 'ci / build' FAILURE 456)")"
printf '[]' > "$d/comments.json"
put "$d/open.json" "$build_fails" "$(dependabot 9 'chore(deps): bump coolbress/plinth from 2.28.0 to 2.31.0' SUCCESS)"
state "pin behind, Dependabot's green pull request raising it, a plinth job failing: merge #9, then #6's checks again" "$d" \
  "where: Green, and seen working (step 6)" "command: merge #9" "!command: diagnose" "!fixes the code"
out="$(MOCK_DIR="$d" "$script" "$d" 2>&1)"
grep -E '^note: ' <<<"$out" | grep -qF "Dependabot's pull request #9 raises the pin and its checks are green" &&
  grep -E '^note: ' <<<"$out" | grep -qF "after it merges, pull request #6's checks are run again on the newer plinth" &&
  ok "the merge note: #9 raises the pin, green; #6's checks are run again after it" || bad "the merge note: $(grep -E '^note: ' <<<"$out")"
put "$d/open.json" "$build_fails" "$(dependabot 9 'chore(deps): bump the actions group with 2 updates' SUCCESS 'Bumps coolbress/plinth from 2.28.0 to 2.31.0.')"
state "a grouped Dependabot pull request naming the pin in its body: the same merge" "$d" "command: merge #9"
put "$d/open.json" "$build_fails" "$(dependabot 9 'chore(deps): bump actions/checkout' SUCCESS)"
state "Dependabot's pull request raising something else: not the one to merge" "$d" "!command: merge"
put "$d/open.json" "$build_fails" "$(dependabot 9 'chore(deps): bump coolbress/plinth-template-action' SUCCESS 'Bumps coolbress/plinth-template-action.')"
state "a name that only starts with coolbress/plinth: not the pin" "$d" "!command: merge"
cat > "$d/docs/how-to/keep-this-project-current.md" <<'HOWTO'
# Keep this project current

## 2. Update the template

```text
/plinth:template-update
```

## 3. Merge the plinth pin pull request

**What to run:** in a terminal in this repository:

```bash
gh pr list --author app/dependabot --search coolbress/plinth
```

**Done when:** that command lists nothing. That does not prove the pin is the
newest: Dependabot looks once a week and waits three days after a release.
HOWTO
put "$d/open.json" "$build_fails"
state "pin behind, no Dependabot pull request: the command and note are the how-to's" "$d" \
  "where: Between pieces of work (step 9)" "command: gh pr list --author app/dependabot --search coolbress/plinth" "!command: diagnose"
out="$(MOCK_DIR="$d" "$script" "$d" 2>&1)"
grep -E '^note: ' <<<"$out" | grep -qF 'no Dependabot pull request raising the pin is open; from docs/how-to/keep-this-project-current.md, "3. Merge the plinth pin pull request": Done when: that command lists nothing. That does not prove the pin is the newest: Dependabot looks once a week and waits three days after a release.' &&
  grep -E '^note: ' <<<"$out" | grep -qF "pull request #6's checks are run again" &&
  ok "the how-to's note: none open, its Done when, then #6's checks again" || bad "the how-to's note: $(grep -E '^note: ' <<<"$out")"
put "$d/open.json" "$build_fails" "$(dependabot 9 'chore(deps): bump coolbress/plinth from 2.28.0 to 2.31.0' FAILURE)"
state "Dependabot's pull request raising the pin, its checks failing: not merged; the how-to, and #9 named" "$d" \
  "command: gh pr list --author app/dependabot --search coolbress/plinth" "!command: merge"
grep -qF "Dependabot's pull request #9 raises the pin, its checks fail: it is merged once they are green" <<<"$(MOCK_DIR="$d" "$script" "$d" 2>&1)" &&
  ok "the failing Dependabot pull request is named in the note" || bad "the failing Dependabot pull request is not named"
rm "$d/docs/how-to/keep-this-project-current.md"
put "$d/open.json" "$build_fails"
state "pin behind, none open, no how-to in the project: floor-check, and why" "$d" \
  "command: /plinth:floor-check" "!command: diagnose"
put "$d/open.json" "$(prc 6 'feat: monthly totals' "$(run 'smoke' FAILURE 459)")"
state "pin behind, only the project's own check failing: the fix-the-code note stays" "$d" \
  "command: diagnose this: pull request #6 has a failing check" \
  "note: pull request #6 has a failing check; the agent reads its log, reproduces it and fixes the code, not the check"
put "$d/open.json" "$build_fails" "$(dependabot 9 'chore(deps): bump coolbress/plinth from 2.28.0 to 2.31.0' SUCCESS)"
# Not read: never a guess, and never "behind".
out="$(MOCK_GH_FAIL=1 MOCK_DIR="$d" "$script" "$d" 2>&1)"
grep -qxF "plinth pin: $pin, not read against the latest release (no network read)" <<<"$out" && grep -qxF 'where: not read' <<<"$out" &&
  ! grep -qE '^command: |, behind v2' <<<"$out" &&
  ok "unauthenticated gh: plinth pin not read, where not read" || bad "unauthenticated: $(grep -E '^(plinth pin|where|template): ' <<<"$out")"
printf 'not json' > "$api/releases/latest.json"
state "the release read fails: not read, and the plinth job note of #903" "$d" \
  "plinth pin: $pin, not read against the latest release (the release: offline or API error)" \
  "command: diagnose this: pull request #6 has a failing check in a job plinth runs; read its log and the comments before changing any code"
release v2.32.0
state "the compare not there: not read against that release" "$d" \
  "plinth pin: $pin, not read against v2.32.0, the latest plinth release (the compare was not found)" "!command: merge"
release v2.31.0
printf '{"status":"identical","ahead_by":0,"behind_by":0}' > "$api/compare/$pin...v2.31.0?per_page=1&page=2.json"
state "the pin at the latest release: said, and a plinth job failing is diagnosed" "$d" \
  "plinth pin: $pin, at v2.31.0, the latest plinth release" "command: diagnose this: pull request #6 has a failing check in a job plinth runs; read its log and the comments before changing any code"
printf '{"status":"ahead","ahead_by":28,"behind_by":0}' > "$api/compare/$pin...v2.31.0?per_page=1&page=2.json"
printf 'name: Label\non: pull_request_target\njobs:\n  label:\n    uses: coolbress/plinth/.github/workflows/pr-label.yml@%040d\n' 8 > "$d/.github/workflows/label.yml"
state "two pins that disagree: not read, with floor-check's reason" "$d" "!plinth pin: $pin, behind" "!command: merge"
grep -q '^plinth pin: not read (workflow pins disagree' <<<"$(MOCK_DIR="$d" "$script" "$d" 2>&1)" && ok "two pins: floor-check's reason" || bad "two pins: no reason"

d="$(repo triage)"
put "$d/merged.json" "$(pr 2 'docs: first' false SUCCESS)" "$(pr 7 'feat: x' false SUCCESS)"
put "$d/issues.json" "$(issue 8 'It crashes on an empty file' needs-triage)"
expect "only an issue someone else opened: triage" "$d" "Something broke (step 7)" "/triage" "note: issue #8"

d="$(repo unlabelled)"
put "$d/merged.json" "$(pr 2 'docs: first' false SUCCESS)"
put "$d/issues.json" "$(issue 9 'Export to CSV' '')"
expect "an unlabelled issue: build it" "$d" "A ticket ready (step 4)" "/implement #9"

# What is not a ticket (#834): the template's monthly reminder goes to its own
# command; a person's task or a wayfinder issue is never an /implement target.
# Each is told as what it is, and the row after it is still named.
marked() { printf '{"number":%s,"title":"%s","labels":[],"body":"<!-- plinth:template-reminder -->\\nThis repository was made from template tag v1.38.0."}' "$1" "$2"; }
two_labels() { printf '{"number":%s,"title":"%s","labels":[{"name":"%s"},{"name":"%s"}]}' "$1" "$2" "$3" "$4"; }
reminder='Template update available: v1.38.0 to v1.39.0'

d="$(repo reminder)"
put "$d/merged.json" "$(pr 2 'docs: first' false SUCCESS)" "$(pr 7 'feat: x' false SUCCESS)"
put "$d/issues.json" "$(issue 11 "$reminder" '')"
expect "the reminder alone, by its title: the template update, not /implement" "$d" "Between pieces of work (step 9)" "/plinth:template-update" "note: issue #11 is the monthly template reminder"
put "$d/issues.json" "$(marked 11 'Retitled by hand')"
expect "the reminder alone, retitled: its marker still says what it is" "$d" "Between pieces of work (step 9)" "/plinth:template-update" "note: issue #11 is the monthly template reminder"
put "$d/issues.json" "$(issue 11 "$reminder" '')" "$(issue 12 'Export to CSV' '')"
expect "the reminder next to an unlabelled issue: the issue is the ticket" "$d" "A ticket ready (step 4)" "/implement #12"
put "$d/issues.json" "$(issue 11 "$reminder" '')" "$(issue 12 'It crashes' needs-triage)"
expect "the reminder next to an issue to triage: triage first" "$d" "Something broke (step 7)" "/triage" "note: issue #12"
put "$d/issues.json" "$(issue 11 "$reminder" '')" "$(issue 12 'Export to CSV' ready-for-agent)"
expect "the reminder next to a ready-for-agent ticket: the ticket wins" "$d" "A ticket ready (step 4)" "/implement #12" "#11 the monthly template reminder"
put "$d/open.json" "$(pr 13 'feat: export' false run)"
expect "the reminder next to an open pull request: the pull request first" "$d" "A pull request with checks running (step 5)" "/run"
printf '[]' > "$d/open.json"
put "$d/issues.json" "$(issue 11 "$reminder" '')"
put "$d/merged.json" "$(pr 2 'docs: first' false SUCCESS)"
expect "the reminder, one merge so far: the template update, before the first merge's pages" "$d" "Between pieces of work (step 9)" "/plinth:template-update" "note: issue #11"

d="$(repo person-task)"
put "$d/merged.json" "$(pr 2 'docs: first' false SUCCESS)" "$(pr 7 'feat: x' false SUCCESS)"
put "$d/issues.json" "$(issue 14 'Renew the domain' ready-for-human)"
expect "a ready-for-human issue alone: said to be a person's, on to the next row" "$d" "An idea in your own words (step 2)" "/grilling" "#14 [ready-for-human] a person's task: a person does it"
put "$d/issues.json" "$(issue 14 'Renew the domain' ready-for-human)" "$(issue 15 'Export to CSV' ready-for-agent)"
expect "a ready-for-human issue next to a ready-for-agent ticket: the ticket wins" "$d" "A ticket ready (step 4)" "/implement #15" "#14 [ready-for-human] a person's task: a person does it"
put "$d/issues.json" "$(two_labels 14 'Renew the domain' ready-for-agent ready-for-human)"
expect "ready-for-human and ready-for-agent on one issue: never /implement" "$d" "An idea in your own words (step 2)" "/grilling" "#14 [ready-for-agent,ready-for-human] a person's task"
put "$d/issues.json" "$(issue 14 'Renew the domain' ready-for-human)"
put "$d/merged.json" "$(pr 2 'docs: first' false SUCCESS)"
expect "a ready-for-human issue, one merge so far: the row after the first merge" "$d" "First pull request merged (step 1)" "none: three pages to follow, in order (the tool cell)" "#14 [ready-for-human]"

d="$(repo record)"
put "$d/merged.json" "$(pr 2 'docs: first' false SUCCESS)" "$(pr 7 'feat: x' false SUCCESS)"
put "$d/issues.json" "$(issue 16 'Which queue?' wayfinder:grilling)"
expect "a wayfinder record alone: said to be one, on to the next row" "$d" "An idea in your own words (step 2)" "/grilling" "#16 [wayfinder:grilling] a wayfinder record: a person does it"
put "$d/issues.json" "$(issue 16 'Which queue?' wayfinder:grilling)" "$(issue 17 'Export to CSV' ready-for-agent)"
expect "a wayfinder record next to a ready-for-agent ticket: the ticket wins" "$d" "A ticket ready (step 4)" "/implement #17" "#16 [wayfinder:grilling] a wayfinder record"
put "$d/issues.json" "$(two_labels 16 'Which queue?' wayfinder:research ready-for-agent)"
expect "a wayfinder record with the triage label: still never /implement" "$d" "An idea in your own words (step 2)" "/grilling" "#16 [wayfinder:research,ready-for-agent]"
put "$d/issues.json" "$(issue 16 'The whole move' wayfinder:map)"
expect "a wayfinder map alone: a record too" "$d" "An idea in your own words (step 2)" "/grilling" "#16 [wayfinder:map] a wayfinder record"
# docs/agents/issue-tracker.md: a task child "is a task like any other".
put "$d/issues.json" "$(issue 18 'Move the queue' wayfinder:task)"
expect "a wayfinder:task alone: a ticket, not a record" "$d" "A ticket ready (step 4)" "/implement #18" "before: /clear"
put "$d/issues.json" "$(issue 16 'Which queue?' wayfinder:grilling)" "$(issue 18 'Move the queue' wayfinder:task)"
expect "a wayfinder:task next to a record: the task" "$d" "A ticket ready (step 4)" "/implement #18" "#16 [wayfinder:grilling] a wayfinder record"
put "$d/issues.json" "$(two_labels 18 'Move the queue' wayfinder:task ready-for-human)"
expect "a wayfinder:task labelled ready-for-human: a person's" "$d" "An idea in your own words (step 2)" "/grilling" "#18 [wayfinder:task,ready-for-human] a person's task"

# docs/agents/issue-tracker.md lists a spec with the records.
d="$(repo spec-record)"
put "$d/merged.json" "$(pr 2 'docs: first' false SUCCESS)" "$(pr 7 'feat: x' false SUCCESS)"
# A spec no ticket was cut from (#909) is step 3: /to-tickets #N. Cut means
# a sub-issue of it, open or closed (subIssuesSummary.total), or an issue
# whose body names it under ## Parent.
subbed() { printf '{"number":%s,"title":"%s","labels":[{"name":"spec"}],"subIssuesSummary":{"total":%s,"completed":%s}}' "$1" "$2" "$3" "$4"; }
bodied() { jq -nc --argjson n "$1" --arg b "$2" '{number: $n, title: "t", labels: [], body: $b}'; }
put "$d/issues.json" "$(issue 19 'The queue spec' spec)"
expect "a spec alone, nothing cut from it: step 3, /to-tickets on it" "$d" "A job bigger than one session (step 3)" "/to-tickets #19" "#19 [spec] a spec, a record: a person does it; tickets cut from it: none"
grep -q '^note: issue #19 is a spec no ticket was cut from yet; /to-tickets cuts it into tickets that /implement can take one at a time$' <<<"$(MOCK_DIR="$d" "$script" "$d")" &&
  ok "the uncut spec's note says what /to-tickets makes" || bad "no note for the uncut spec"
put "$d/issues.json" "$(subbed 19 'The queue spec' 1 0)"
expect "a spec with one open sub-issue: not cut again" "$d" "An idea in your own words (step 2)" "/grilling" "tickets cut from it: 1 sub-issue"
put "$d/issues.json" "$(subbed 19 'The queue spec' 2 2)"
expect "a spec whose sub-issues are all closed: still cut" "$d" "An idea in your own words (step 2)" "/grilling" "tickets cut from it: 2 sub-issues"
put "$d/issues.json" "$(issue 19 'The queue spec' spec)"
put "$d/all.json" "$(bodied 19 '## Parent

#3')" "$(bodied 21 '## What to build

Part of #19.

## Parent

#19, T1.2 The queue spec')"
expect "a spec an issue names under ## Parent: not cut again" "$d" "An idea in your own words (step 2)" "/grilling" "tickets cut from it: #21 names it under ## Parent"
# Not under ## Parent, another repository's #19, a longer number, its own body: not cut from it.
put "$d/all.json" "$(bodied 22 '## What to build

Like #19.

## Parent

#3')" "$(bodied 23 '## Parent

other/repo#19')" "$(bodied 24 '## Parent

#190')" "$(bodied 19 '## Parent

#19')"
expect "#19 named outside ## Parent, as other/repo#19, as #190, or by itself: still uncut" "$d" "A job bigger than one session (step 3)" "/to-tickets #19" "tickets cut from it: none"
printf '[]' > "$d/all.json"
out="$(MOCK_ALL_FAIL=1 MOCK_DIR="$d" "$script" "$d" 2>&1)"
if grep -qx 'command: /grilling' <<<"$out" && grep -qF '#19 [spec] a spec, a record: a person does it; tickets cut from it: not read (HTTP 502: Bad Gateway)' <<<"$out"
then ok "the ## Parent search failing: not read, and never /to-tickets on a guess"
else bad "a failed ## Parent search"; sed 's/^/        /' <<<"$out" | head -20; fi
put "$d/issues.json" "$(issue 19 'The queue spec' spec)" "$(issue 20 'Export to CSV' ready-for-agent)"
expect "an uncut spec next to a ready-for-agent ticket: the ticket wins" "$d" "A ticket ready (step 4)" "/implement #20" "#19 [spec] a spec, a record"
put "$d/issues.json" "$(issue 19 'The queue spec' spec)" "$(issue 20 'Export to CSV' '')"
expect "an uncut spec next to an unlabelled issue: the spec is cut first" "$d" "A job bigger than one session (step 3)" "/to-tickets #19"
put "$d/issues.json" "$(issue 19 'The queue spec' spec)" "$(issue 11 "$reminder" '')"
expect "an uncut spec next to the template reminder: the spec first" "$d" "A job bigger than one session (step 3)" "/to-tickets #19" "#11 the monthly template reminder"
put "$d/issues.json" "$(subbed 19 'The queue spec' 1 0)" "$(issue 25 'Another spec' spec)"
expect "two specs, the lower one cut: the uncut one" "$d" "A job bigger than one session (step 3)" "/to-tickets #25"
# The search runs only on specs with no sub-issue, in number order, and
# stops at the first uncut one: calls = searched specs up to it.
searches() { # <case> <wanted calls> <wanted command> [<other line>]
  local log="$work/searches.log" out n; : > "$log"
  out="$(MOCK_ALL_LOG="$log" MOCK_DIR="$d" "$script" "$d" 2>&1)"; n="$(grep -c . "$log")"
  if [ "$n" -eq "$2" ] && grep -qxF "command: $3" <<<"$out" && { [ -z "${4:-}" ] || grep -qF -- "$4" <<<"$out"; }
  then ok "$1"; else bad "$1 ($n searches, wanted $2; wanted command: $3${4:+ / $4})"; sed 's/^/        /' <<<"$out" | grep -E 'spec|command' ; fi
}
put "$d/issues.json" "$(subbed 19 'The queue spec' 1 0)" "$(issue 25 'Another spec' spec)" "$(issue 26 'A third spec' spec)"
searches "three specs, the first with a sub-issue: one search, none past the uncut one" 1 "/to-tickets #25" "#26 [spec] a spec, a record: a person does it; tickets cut from it: not searched (spec #25, with none, comes first)"
put "$d/all.json" "$(bodied 21 '## Parent

#25')"
searches "the second spec named under ## Parent: searched on to the third" 2 "/to-tickets #26" "#25 [spec] a spec, a record: a person does it; tickets cut from it: #21 names it under ## Parent"
put "$d/issues.json" "$(subbed 19 'The queue spec' 1 0)" "$(subbed 25 'Another spec' 2 1)"
searches "every spec with sub-issues: no search" 0 "/grilling"
printf '[]' > "$d/all.json"
# Routing reads the state, not the words said: a spec whose search failed or
# was not run is never routed to, whatever its line says.
put "$d/issues.json" "$(issue 19 'The queue spec' spec)" "$(issue 25 'Another spec' spec)"
out="$(MOCK_ALL_FAIL=1 MOCK_DIR="$d" "$script" "$d" 2>&1)"
grep -qx 'command: /grilling' <<<"$out" && [ "$(grep -c 'tickets cut from it: not read' <<<"$out")" -eq 2 ] &&
  ok "both searches failing: each not read, no /to-tickets" || bad "two failed searches"
put "$d/open.json" "$(pr 13 'feat: export' false run)"
expect "an uncut spec next to an open pull request: the pull request first" "$d" "A pull request with checks running (step 5)" "/run"
printf '[]' > "$d/open.json"
put "$d/issues.json" "$(two_labels 19 'The queue spec' spec ready-for-agent)"
expect "a spec with the triage label: cut, never /implement" "$d" "A job bigger than one session (step 3)" "/to-tickets #19" "#19 [spec,ready-for-agent]"
# A record opens with needs-triage: evaluating it is still /triage's.
put "$d/issues.json" "$(two_labels 19 'The queue spec' spec needs-triage)"
expect "a spec to triage: /triage, not the next row" "$d" "Something broke (step 7)" "/triage" "note: issue #19"
put "$d/issues.json" "$(two_labels 16 'Which queue?' wayfinder:research needs-triage)"
expect "a wayfinder record to triage: /triage" "$d" "Something broke (step 7)" "/triage" "note: issue #16"
put "$d/issues.json" "$(two_labels 14 'Renew the domain' ready-for-human needs-triage)"
expect "a person's task to triage: /triage" "$d" "Something broke (step 7)" "/triage" "note: issue #14"

d="$(repo bots-only)"
put "$d/merged.json" "$(pr 2 'docs: first' false SUCCESS)" "$(pr 7 'feat: x' false SUCCESS)"
put "$d/open.json" "$(pr 10 'chore(deps): bump y' true SUCCESS)"
expect "only Dependabot open, past the first merge: step 9" "$d" "Between pieces of work (step 9)" \
  "/plinth:floor-check (then the Dependabot pull requests, one at a time, on green)"

d="$(repo idle)"
put "$d/merged.json" "$(pr 2 'docs: first' false SUCCESS)" "$(pr 7 'feat: x' false SUCCESS)"
expect "nothing open, past the first merge: shape the next idea" "$d" "An idea in your own words (step 2)" "/grilling" \
  "last merge: #7"

# More merged pull requests than the 100 read (#905). A read that came back
# full says it counts the last 100 only, and the step does not fall back to
# the first pull request when those 100 are all Dependabot's.
# many <count> <people's are #1..#n>: merged pull requests, the rest a bot's.
many() {
  jq -n --argjson c "$1" --argjson p "$2" '[range(1; $c + 1) | {number: ., title: "feat: change \(.)",
    author: (if . <= $p then {login: "someone", is_bot: false} else {login: "app/dependabot", is_bot: true} end),
    mergedAt: (1700000000 + . * 3600 | todate)}]'
}
d="$(repo many-merged)"
many 203 83 > "$d/merged.json"
expect "203 merged, the newest 120 a bot's: of the last 100, and past the first merge" "$d" \
  "An idea in your own words (step 2)" "/grilling" "first pull request merged: yes (0 merged by people of the last 100 read; older ones not read)"
# With a failing check there (#903), that project is at "Something broke" and
# its failing checks are named, though none of the 100 read is a person's.
put "$d/open.json" "$(prc 300 'feat: totals' "$(run 'smoke' FAILURE 470)")"
state "203 merged, none of the last 100 a person's, a failing check: named, something broke" "$d" \
  "where: Something broke (step 7)" "failing checks on pull request #300:" "  smoke: the project's own" \
  "command: diagnose this: pull request #300 has a failing check"
d="$(repo many-merged-all)"
many 150 150 > "$d/merged.json"
expect "150 merged, all by people: 100 of the last 100, not a total" "$d" \
  "An idea in your own words (step 2)" "/grilling" "first pull request merged: yes (100 merged by people of the last 100 read; older ones not read)"
d="$(repo many-merged-one)"
many 203 1 > "$d/merged.json"
expect "203 merged, the one by a person unread: not taken for the first merge" "$d" \
  "An idea in your own words (step 2)" "/grilling" "of the last 100 read"
d="$(repo at-the-read)"
many 100 100 > "$d/merged.json"
expect "exactly 100 merged: read as cut, since a 101st cannot be told apart" "$d" \
  "An idea in your own words (step 2)" "/grilling" "(100 merged by people of the last 100 read; older ones not read)"
d="$(repo at-the-read-one)"
many 100 1 > "$d/merged.json"
expect "100 merged, one by a person among them: not taken for the only one" "$d" \
  "An idea in your own words (step 2)" "/grilling" "(1 merged by people of the last 100 read; older ones not read)"
# Under 100 the read is everything: the count is the total and exact.
d="$(repo under-the-read)"
many 99 1 > "$d/merged.json"
expect "99 merged, one by a person 98 merges ago: the total, and still the one" "$d" \
  "First pull request merged (step 1)" "none: three pages to follow, in order (the tool cell)" "first pull request merged: yes (1 merged by people)"
d="$(repo under-the-read-bots)"
many 99 0 > "$d/merged.json"; put "$d/open.json" "$(pr 2 'docs: first pull request through the wall' false SUCCESS)"
expect "99 merged, all a bot's, the first pull request open: still the first merge" "$d" \
  "Repository made, its first pull request open (step 1)" \
  "body=\"\$(gh pr view 2 --json body --jq .body)\" && gh pr merge 2 --squash --match-head-commit $(printf '%040d' 2) --body \"\$body\"" \
  "first pull request merged: no (0 merged by people)"

d="$(repo no-login)"
out="$(MOCK_GH_FAIL=1 MOCK_DIR="$d" "$script" "$d" 2>&1)"
if grep -qx 'where: not read' <<<"$out" && grep -q 'gh auth login' <<<"$out" && ! grep -q '^command:' <<<"$out"; then
  ok "gh not logged in: not read, with gh's own line, and no step"
else bad "gh not logged in"; sed 's/^/        /' <<<"$out"; fi

# One read failing after the repository answered: its own error, named.
d="$(repo one-read-fails)"
out="$(MOCK_FAIL_ON="pr list merged" MOCK_DIR="$d" "$script" "$d" 2>&1)"
if grep -qx 'where: not read' <<<"$out" && grep -qF 'not read (merged pull requests: HTTP 502: Bad Gateway)' <<<"$out" &&
   ! grep -q 'unbound' <<<"$out"; then ok "one read failing: that read and gh's error, no step"
else bad "one read failing"; sed 's/^/        /' <<<"$out"; fi

d="$(repo gitlab "archetype: cli
host: gitlab")"
out="$(MOCK_DIR="$d" "$script" "$d" 2>&1)"
grep -qx 'where: not read' <<<"$out" && ! grep -q '^command:' <<<"$out" &&
  ok "a GitLab checkout: not read, no step" || bad "a GitLab checkout"

# A table that lost a row the guide looks for stops with exit 1, never guesses.
mkdir -p "$work/plugin/skills/arsenal" "$work/plugin/scripts"
cp "$script" "$root/scripts/new-project.sh" "$work/plugin/scripts/"
grep -v '^| An idea in your own words' "$arsenal" > "$work/plugin/skills/arsenal/SKILL.md"
d="$work/idle"
out="$(MOCK_DIR="$d" "$work/plugin/scripts/guide-state.sh" "$d" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && grep -q "no row starting 'An idea in your own words'" <<<"$out" &&
  ok "a row missing from the arsenal's table: exit 1, named" || bad "missing row: exit $rc: $out"

# The reasons (#834): copied from the table and the list, never the script's.
# The moments' are on every path, a repository being read or not.
d="$work/plain"
out="$("$script" "$d" 2>&1)"
missing=""
for line in \
  'why: A merged change to put out (release and deploy, after step 6): plinth does not deploy a `web` app that runs anywhere else' \
  "why: The project in use (operate): an uptime monitor and an error tracker with a free plan each. Neither is installed: the person sets them up in the service's own account" \
  'why: Looking back on a piece of work (retrospective): it reads the session and suggests rules and checks, most serious first, and changes nothing' \
  'why: Ending the project, or handing it over (end): the table gives no reason'; do
  grep -qxF -- "$line" <<<"$out" || missing="$missing
$line"
done
if [ -z "$missing" ]; then ok "a why: line for each moment, each the table's words"
else bad "why: lines missing:$missing"; fi
d="$work/idle"
out="$(MOCK_DIR="$d" "$script" "$d" 2>&1)"
grep -qF "why: The project in use (operate): an uptime monitor" <<<"$out" && ok "the moments' why: lines on a repository that is read too" || bad "no moments' why: line on a read repository"
# Off by default: the sorting rule, flattened, its links reduced to their words.
rule="$(grep -E '^  why: ' <<<"$out")"
if grep -qF 'A choice they cannot judge yet starts off and is told, in the list below, with when it is worth turning on and how (progressive disclosure).' <<<"$rule" &&
   grep -qF 'because it needs an account outside the repository' <<<"$rule" && ! grep -q 'https://' <<<"$rule" && [ "$(grep -c . <<<"$rule")" = 1 ]
then ok "one why: line under off by default, the list's sorting rule in its words"
else bad "off-by-default why: got: $rule"; fi
printf '# x\n\n## The list\n\n| Feature | Archetypes | Turn it on when | Steps | On when the project has | Listed only when the project has |\n| --- | --- | --- | --- | --- | --- |\n| A | all | b | `docs/how-to/turn-on-what-starts-off.md` | - | - |\n' > "$work/no-rule.md"
out="$(PLINTH_OFF_BY_DEFAULT="$work/no-rule.md" MOCK_DIR="$d" "$script" "$d" 2>&1)"
grep -qF '  why: not read (off-by-default: no text under ' <<<"$out" && ok "a list without its sorting rule: why: not read, no guess" || bad "no rule in the list: $(grep -F 'why:' <<<"$out" | head -3)"
for r in "plinth does not deploy" "an uptime monitor" "it reads the session"; do
  { sed '/^## Where you are, and what to do next/,/^A tool marked listed/ s/'"$r"'/something else/' "$arsenal"; } > "$work/plugin/skills/arsenal/SKILL.md"
  out="$("$work/plugin/scripts/guide-state.sh" "$work/plain" 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] && grep -qF "no longer says '$r'" <<<"$out" && ! grep -q '^why:' <<<"$out" &&
    ok "a table that lost the words of a reason ($r): exit 1, named" || bad "lost reason '$r': exit $rc: $(head -2 <<<"$out")"
done
if grep -qF '`why:`' "$root/skills/guide/SKILL.md" && grep -qF 'no other reason' "$root/skills/guide/SKILL.md"
then ok "the skill says to give the why: line's reason and no other"; else bad "the skill does not say to give the why: line's reason and no other"; fi

if grep -qF 'look again in a minute' "$root/skills/guide/SKILL.md" && grep -qF '`no checks ran`: no' "$root/skills/guide/SKILL.md"
then ok "the skill says checks not started yet and no checks ran in plain words"; else bad "the skill does not say what an empty rollup means"; fi

# ── names ────────────────────────────────────────────────────────────────
printf 'Next, type `/speckit.specify` to write the spec.\n' > "$work/n1"
printf 'Install superpowers for a better plan.\n' > "$work/n2"
printf '다음은 /compact 를 치세요.\n' > "$work/n3"
for n in n1 n2 n3; do
  "$names" "$arsenal" "$work/$n" >/dev/null && bad "names: $(cat "$work/$n") passed" || ok "names: fails on: $(cat "$work/$n")"
done
printf '다음 명령: `/clear`, 그다음 `/implement #5`. 파일은 docs/how-to/x.md, ${CLAUDE_PLUGIN_ROOT}/scripts/y.sh, `/home/runner/plinth/docs/a.md`.\n' > "$work/y1"
"$names" "$arsenal" "$work/y1" >/dev/null && ok "names: table commands and paths pass" || bad "names: a text using only table commands failed"
if out="$("$names" "$arsenal" "$root/skills/guide/SKILL.md")"; then
  ok "skills/guide/SKILL.md names only the table's commands"
else bad "skills/guide/SKILL.md:"; echo "$out"; fi
out="$("$script" "$work/plain" 2>&1)"
grep -q 'CLAUDE_PLUGIN_ROOT' <<<"$out" && bad "the printed table still carries \${CLAUDE_PLUGIN_ROOT}" ||
  ok "the printed table names the plugin's own path, not the variable"
printf '%s\n' "$out" > "$work/printed"
"$names" "$arsenal" "$work/printed" >/dev/null && ok "what the script prints names only the table's commands" || bad "the script's output names something outside the table"

echo "-- $pass passed, $fail failed"
[ "$fail" -eq 0 ]
