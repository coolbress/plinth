#!/usr/bin/env bash
# Verdicts of scripts/merge-when-green.sh against a fake `gh`. The fake answers
# with JSON fixtures and runs the script's own --jq filters through jq, so the
# filters are tested, not copied. Each case says whether a merge must happen;
# the fake records the `gh pr merge` call, so "no merge" is checked, not assumed.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/merge-when-green.sh"
command -v jq >/dev/null || { echo "  FAIL  jq is needed to run the fake gh's filters"; exit 1; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Fake gh: fixtures in $FX. `--jq F` is applied with jq to the fixture's JSON.
fx="$FX"; jqf=""; args=("$@")
printf '%s\n' "$*" >>"$fx/calls"
for ((i=0; i<${#args[@]}; i++)); do [ "${args[$i]}" = --jq ] && jqf="${args[$((i+1))]}"; done
out() { if [ -n "$jqf" ]; then jq -r "$jqf" "$1"; else cat "$1"; fi; }
case "$1 $2" in
  "repo view") echo "o/r" ;;
  "pr view")
    case "$*" in
      *"state,mergeCommit"*) out "$fx/after.json" ;;
      *) out "$fx/pr.json" ;;
    esac ;;
  "pr checks") case "$*" in *--watch*) exit 0 ;; *) out "$fx/checks.json" ;; esac ;;
  "pr merge")
    rc="$(cat "$fx/merge_rc" 2>/dev/null || echo 0)"
    [ "$rc" = 0 ] && printf '%s\n' "$*" >"$fx/merged"
    [ ! -f "$fx/merge_err" ] || cat "$fx/merge_err" >&2
    exit "$rc" ;;
  api*)
    case "$*" in
      *"/actions/workflows/e2e.yml/runs"*) [ -f "$fx/e2e.json" ] || { echo "HTTP 502" >&2; exit 1; }; out "$fx/e2e.json" ;;
      *"/actions/runs/"*"/jobs"*)
        [[ "$*" =~ runs/([0-9]+)/jobs ]]; f="$fx/jobs-${BASH_REMATCH[1]}.json"
        [ -f "$f" ] || f="$fx/no-jobs.json"; out "$f" ;;
      *"/actions/runs -f head_sha="*)
        [[ "$*" =~ head_sha=([0-9a-z]+) ]]; f="$fx/runs-${BASH_REMATCH[1]}.json"
        [ -f "$f" ] || { echo "HTTP 502" >&2; exit 1; }; out "$f" ;;
      "api repos/o/r/pulls/7 --jq"*) out "$fx/pull.json" ;;
      *"/pulls/"*"/comments"*) out "$fx/comments.json" ;;
      *"/pulls/"*"/reviews"*) [ -f "$fx/reviews.json" ] || exit 1; out "$fx/reviews.json" ;;
      *"/issues/"*"/comments"*) [ -f "$fx/icomments.json" ] || exit 1; out "$fx/icomments.json" ;;
      *"/activity"*) [ -f "$fx/activity.json" ] || exit 1; out "$fx/activity.json" ;;
      *"/issues/"[0-9]*)
        [[ "$*" =~ issues/([0-9]+) ]]; f="$fx/issue-${BASH_REMATCH[1]}.json"
        [ -f "$f" ] || exit 1; out "$f" ;;
      "api repos/o/r/rules/branches/main --jq"*) [ -f "$fx/rules.json" ] || exit 1; out "$fx/rules.json" ;;
      "api repos/o/r/rulesets/"*) [ -f "$fx/ruleset.json" ] || exit 1; out "$fx/ruleset.json" ;;
      "api repos/o/r --jq .permissions.admin") [ -f "$fx/repo.json" ] || exit 1; out "$fx/repo.json" ;;
      *) echo "fake gh: unexpected api $*" >&2; exit 1 ;;
    esac ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$work/bin/gh"

H=1111111111111111111111111111111111111111
green='[{"name":"ci / install","state":"SUCCESS"},{"name":"third-party / review","state":"SUCCESS"}]'

# setup <case-dir>: a pull request that should merge; each case then breaks one thing.
setup() {
  FX="$work/$1"; export FX; mkdir -p "$FX"
  printf '{"state":"OPEN","headRefOid":"%s","headRefName":"b","baseRefName":"main","body":"## What and why\\n\\nx"}' "$H" >"$FX/pr.json"
  printf '{"state":"MERGED","mergeCommit":{"oid":"abc"}}' >"$FX/after.json"
  printf '%s' "$green" >"$FX/checks.json"
  printf '[]' >"$FX/comments.json"
  printf '[]' >"$FX/reviews.json"; printf '[]' >"$FX/icomments.json"; printf '[]' >"$FX/activity.json"
  printf '{"user":{"login":"someone","type":"User"}}' >"$FX/pull.json"
  printf '{"jobs":[]}' >"$FX/no-jobs.json"
}

pass=0; fail=0
run() { # <merge|stop> <label> [script args...]
  local want="$1" label="$2"; shift 2
  local got rc
  PATH="$work/bin:$PATH" MERGE_POLL=0 MERGE_ANALYZE_WAIT=0 bash "$script" 7 --repo o/r "$@" >"$FX/out" 2>&1; rc=$?
  if [ -f "$FX/merged" ]; then got=merge; else got=stop; fi
  # A merge exits 0; a stop exits non-zero and leaves no merge call behind.
  local ok=no
  if [ "$want" = merge ]; then [ "$got" = merge ] && [ "$rc" = 0 ] && ok=yes
  else [ "$got" = stop ] && [ "$rc" != 0 ] && ok=yes; fi
  if [ "$ok" = yes ]; then
    pass=$((pass+1)); printf '  PASS  %-5s %s\n' "$want" "$label"
  else
    fail=$((fail+1)); printf '  FAIL  %-5s %s  (got %s, exit %s)\n' "$want" "$label" "$got" "$rc"; sed 's/^/        /' "$FX/out"
  fi
}

echo "-- merges"
setup ok; run merge "every check green, third-party / review among them, no comments"
if grep -q -- "--match-head-commit $H" "$FX/merged" && grep -q -- "--squash" "$FX/merged"; then
  pass=$((pass+1)); echo "  PASS  merge  pins the head and squashes"
else
  fail=$((fail+1)); echo "  FAIL  merge  pins the head and squashes: $(cat "$FX/merged")"
fi
setup answered
printf '[{"id":1,"in_reply_to_id":null,"path":"a","line":3,"body":"P2 x"},{"id":2,"in_reply_to_id":1,"path":"a","line":3,"body":"Fixed"}]' >"$FX/comments.json"
run merge "an inline comment with a reply"
setup norev; printf '[{"name":"ci / install","state":"SUCCESS"}]' >"$FX/checks.json"
run merge "no reviewer check, --no-reviewer given" --no-reviewer

echo "-- stops"
setup red; printf '[{"name":"ci / install","state":"FAILURE"},{"name":"third-party / review","state":"SUCCESS"}]' >"$FX/checks.json"
run stop "a failed check"
setup pending; printf '[{"name":"ci / install","state":"PENDING"},{"name":"third-party / review","state":"SUCCESS"}]' >"$FX/checks.json"
run stop "a check still pending"
setup none; printf '[]' >"$FX/checks.json"
run stop "no checks at all"
setup open
printf '[{"id":1,"in_reply_to_id":null,"path":"a","line":3,"body":"P1 x"}]' >"$FX/comments.json"
run stop "an inline comment with no reply"
setup oldopen
printf '[{"id":1,"in_reply_to_id":null,"path":"a","line":3,"body":"P1 old"},{"id":2,"in_reply_to_id":1,"path":"a","line":3,"body":"Fixed"},{"id":3,"in_reply_to_id":null,"path":"b","line":null,"original_line":9,"body":"P2 older, unanswered"}]' >"$FX/comments.json"
run stop "one answered and one unanswered comment"
echo "-- several runs under one name (#363): the newest finished one speaks"
setup latepass; printf '[{"name":"ci / install","state":"SUCCESS","startedAt":"2026-10-01T10:00:00Z","completedAt":"2026-10-01T10:00:00Z"},{"name":"third-party / review","state":"FAILURE","startedAt":"2026-10-01T10:55:21Z","completedAt":"2026-10-01T10:56:21Z"},{"name":"third-party / review","state":"SUCCESS","startedAt":"2026-10-01T10:57:41Z","completedAt":"2026-10-01T10:58:41Z"}]' >"$FX/checks.json"
run merge "a review check that failed, then passed on the reviewer's review"
setup latefail; printf '[{"name":"ci / install","state":"SUCCESS","startedAt":"2026-10-01T10:00:00Z","completedAt":"2026-10-01T10:00:00Z"},{"name":"third-party / review","state":"SUCCESS","startedAt":"2026-10-01T10:57:41Z","completedAt":"2026-10-01T10:58:41Z"},{"name":"third-party / review","state":"FAILURE","startedAt":"2026-10-01T11:09:00Z","completedAt":"2026-10-01T11:10:00Z"}]' >"$FX/checks.json"
run stop "a review check that passed, then failed on a later run"
setup lateqd; printf '[{"name":"ci / install","state":"SUCCESS","startedAt":"2026-10-01T10:00:00Z","completedAt":"2026-10-01T10:00:00Z"},{"name":"third-party / review","state":"SUCCESS","startedAt":"2026-10-01T10:57:41Z","completedAt":"2026-10-01T10:58:41Z"},{"name":"third-party / review","state":"IN_PROGRESS"}]' >"$FX/checks.json"
run stop "a passed run beside one still running under the same name"
setup lateci; printf '[{"name":"ci / install","state":"FAILURE","startedAt":"2026-10-01T10:00:00Z","completedAt":"2026-10-01T10:00:00Z"},{"name":"ci / install","state":"SUCCESS","startedAt":"2026-10-01T10:29:00Z","completedAt":"2026-10-01T10:30:00Z"},{"name":"third-party / review","state":"SUCCESS","startedAt":"2026-10-01T10:57:41Z","completedAt":"2026-10-01T10:58:41Z"}]' >"$FX/checks.json"
run merge "any check re-run to green: the newer run counts"
setup overlap; printf '[{"name":"ci / install","state":"SUCCESS","startedAt":"2026-10-01T09:59:00Z","completedAt":"2026-10-01T10:00:00Z"},{"name":"third-party / review","state":"SUCCESS","startedAt":"2026-10-01T10:30:00Z","completedAt":"2026-10-01T11:05:00Z"},{"name":"third-party / review","state":"FAILURE","startedAt":"2026-10-01T10:40:00Z","completedAt":"2026-10-01T10:50:00Z"}]' >"$FX/checks.json"
run stop "overlapping runs: the one started later failed first, the older passed after"
setup revred; printf '[{"name":"ci / install","state":"SUCCESS"},{"name":"third-party / review","state":"FAILURE"}]' >"$FX/checks.json"
run stop "third-party / review red"
run stop "third-party / review red, even with --no-reviewer" --no-reviewer
setup noflag; printf '[{"name":"ci / install","state":"SUCCESS"}]' >"$FX/checks.json"
run stop "no reviewer check and no --no-reviewer"
setup closed; printf '{"state":"MERGED","headRefOid":"%s","body":"x"}' "$H" >"$FX/pr.json"
run stop "a pull request that is not open"
setup nobody; printf '{"state":"OPEN","headRefOid":"%s","body":""}' "$H" >"$FX/pr.json"
run stop "an empty description"
setup refused; echo 1 >"$FX/merge_rc"
if PATH="$work/bin:$PATH" MERGE_POLL=0 bash "$script" 7 --repo o/r >"$FX/out" 2>&1; then
  fail=$((fail+1)); echo "  FAIL  stop  gh pr merge refusing (for example a newer head) exits non-zero"
else
  pass=$((pass+1)); echo "  PASS  stop  gh pr merge refusing (for example a newer head) exits non-zero"
fi

echo "-- refused under the merge ruleset (#569): the person merges, no retry"
# What gh printed when the base branch policy blocked a green pull request (#568's merge paths record).
blocked='X Pull request o/r#7 is not mergeable: the base branch policy prohibits the merge.'
refusal() { # <label> <admin: true|false|unread> <stderr> <say: yes|no> [ruleset: never|exempt|none]
  setup "ref-$2-$RANDOM"; echo 1 >"$FX/merge_rc"; printf '%s\n' "$3" >"$FX/merge_err"
  [ "$2" = unread ] || printf '{"permissions":{"admin":%s}}' "$2" >"$FX/repo.json"
  case "${5:-never}" in
    none) printf '[{"type":"pull_request","ruleset_source_type":"Repository","ruleset_id":1}]' >"$FX/rules.json" ;;
    *) printf '[{"type":"pull_request","ruleset_source_type":"Repository","ruleset_id":1},{"type":"update","ruleset_source_type":"Repository","ruleset_id":2}]' >"$FX/rules.json"
       printf '{"id":2,"current_user_can_bypass":"%s"}' "${5:-never}" >"$FX/ruleset.json" ;;
  esac
  PATH="$work/bin:$PATH" MERGE_POLL=0 bash "$script" 7 --repo o/r >"$FX/out" 2>&1; rc=$?
  if [ "$rc" != 0 ] && grep -qF "$3" "$FX/out" && { grep -q 'Do not retry. The person merges' "$FX/out"; [ "$?" = "$([ "$4" = yes ] && echo 0 || echo 1)" ]; } \
     && { [ "$4" = no ] || grep -q "Whether the person's merge goes through was not read with this login" "$FX/out"; }; then
    pass=$((pass+1)); echo "  PASS  stop  $1"
  else fail=$((fail+1)); echo "  FAIL  stop  $1 (exit $rc)"; sed 's/^/        /' "$FX/out"; fi
}
refusal "a non-admin login blocked by the base branch policy: the person merges" false "$blocked" yes
refusal "a non-admin login refused by the rule (the API's words): the person merges" false "GraphQL: Repository rule violations found Cannot update this protected ref. (mergePullRequest)" yes
refusal "an admin login blocked: no person-merges line (something else blocks it)" true "$blocked" no
refusal "a role that cannot be read: no person-merges line" unread "$blocked" no
refusal "a non-admin login refused for another reason: no person-merges line" false "X Head branch was modified. Review and try the merge again." no
refusal "a non-admin login blocked with no update rule on the base (another policy): no person-merges line" false "$blocked" no none
refusal "a non-admin login GitHub says can bypass the update rule: no person-merges line" false "$blocked" no exempt

echo "-- the review round (#485): the line third-party / review writes, never a stop"
# Recorded from coolbress/plinth#484 at its last head, trimmed to the fields
# attest.py and this script read; every inline thread there has a reply.
rec="$root/tests/fixtures/pr-484-round"
H484=aa3c0b9a85d9c00b030e691b5f5fc6d2d5d02c2d
check() { # <label> <status>: one assertion
  if [ "$2" = 0 ]; then pass=$((pass+1)); echo "  PASS  round $1"; else fail=$((fail+1)); echo "  FAIL  round $1"; sed 's/^/        /' "$FX/out"; fi
}
recorded() { # <case-dir>: the #484 fixtures as this case's answers
  setup "$1"
  printf '{"state":"OPEN","headRefOid":"%s","headRefName":"docs/arsenal-concern-index","body":"## What and why\\n\\nx"}' "$H484" >"$FX/pr.json"
  cp "$rec/reviews.json" "$rec/icomments.json" "$rec/activity.json" "$FX/"; cp "$rec/rcomments.json" "$FX/comments.json"
}
want="$(python3 "$root/scripts/pr-review/attest.py" --round "$H484" "chatgpt-codex-connector[bot]" \
  "$rec/reviews.json" "$rec/rcomments.json" "$rec/icomments.json" "$rec/activity.json")"
# What third-party / review logged for that head (run 38063970448).
logged="review round 7 on this pull request: 6 earlier commit(s) reviewed by an accepted reviewer, as read by this run. The review budget is spent (the first review and two rounds of fixes): fix only what is irreversible or reaches other people, answer the rest or move it to an issue. https://github.com/coolbress/plinth/blob/main/docs/how-to/configure-the-third-party-reviewer.md#when-to-stop"
[ "$want" = "$logged" ] && s=0 || s=1; check "the fixture reads as the check logged it on #484" $s
recorded r484
run merge "a round-7 pull request, green, every thread answered"
grep -qxF -- "$want" "$FX/out"; check "the printed line equals attest.py --round on the same files" $?
grep -qx "A wording fix is answered on its thread, not pushed: a push starts another round." "$FX/out"; check "from round 3, a wording fix is answered" $?
[ "$(grep -n -m1 '^review round' "$FX/out" | cut -d: -f1)" -lt "$(grep -n -m1 '^checks:' "$FX/out" | cut -d: -f1)" ] && s=0 || s=1; check "printed before the checks" $s
grep -q 'activity.*ref=refs/heads/docs/arsenal-concern-index' "$FX/calls"; check "the activity log is read for the head branch" $?

recorded before
PATH="$work/bin:$PATH" MERGE_POLL=0 bash "$script" 7 --repo o/r --round >"$FX/out" 2>&1; rc=$?
[ "$rc" = 1 ] && [ ! -f "$FX/merged" ] && grep -qxF -- "$want" "$FX/out" && grep -q -- '--row <irreversible|issue|answer|unclassified> "<why>"' "$FX/out"
check "round 7, --round with no row: prints the line, asks for the row, exits 1, merges nothing" $?
grep -qF -- 'merge-when-green.sh 7 --repo o/r --round --row' "$FX/out"; check "the suggested retry keeps --repo" $?
PATH="$work/bin:$PATH" MERGE_POLL=0 bash "$script" 7 --repo o/r --round --reviewer-logins 'chatgpt-codex-connector[bot],other' >"$FX/out" 2>&1
grep -qF -- '--repo o/r --reviewer-logins chatgpt-codex-connector\[bot\]\,other --round --row' "$FX/out"; check "the suggested retry keeps --reviewer-logins" $?
! grep -qE '^pr (merge|checks|comment|edit|review|ready)|--method (POST|PATCH|PUT|DELETE)|(^| )-X ' "$FX/calls"; check "--round makes only read calls" $?
! grep -q '^checks:' "$FX/out"; check "--round does not wait for the checks" $?

# rnd <label> <want-exit> [args...]: --round on the recorded round-7 pull request
rnd() {
  local label="$1" want_rc="$2" rc; shift 2
  recorded "rnd-$want_rc-$RANDOM"
  PATH="$work/bin:$PATH" MERGE_POLL=0 bash "$script" 7 --repo o/r "$@" >"$FX/out" 2>&1; rc=$?
  [ "$rc" = "$want_rc" ] && [ ! -f "$FX/merged" ]; check "$label (exit $rc)" $?
}
rnd "round 7, --row answer with a reason: exit 0" 0 --round --row answer "a how-to line that could say more exposes nothing"
grep -qx "For the description's review section: row answer: a how-to line that could say more exposes nothing" "$FX/out" \
  && grep -q "do not push a fix" "$FX/out"; check "the row line is printed for the description, and no push for answer" $?
rnd "round 7, --row irreversible: exit 0, says push" 0 --round --row irreversible "a check name consumers require"
grep -q "Fix it and push" "$FX/out"; check "irreversible says fix and push" $?
rnd "round 7, --row with an empty reason: exit 1" 1 --round --row issue "  "
rnd "an unknown row: usage, exit 2" 2 --round --row wording "x"
rnd "--row without --round: usage, exit 2" 2 --row answer "x"
setup r1; PATH="$work/bin:$PATH" MERGE_POLL=0 bash "$script" 7 --repo o/r --round >"$FX/out" 2>&1
check "round 1, --round with no row: exit 0" $?
setup r0; mkdir -p "$FX/bin"; printf '#!/bin/sh\nexit 1\n' >"$FX/bin/python3"; chmod +x "$FX/bin/python3"
PATH="$FX/bin:$work/bin:$PATH" MERGE_POLL=0 bash "$script" 7 --repo o/r --round >"$FX/out" 2>&1
rc=$?; [ "$rc" = 1 ] && grep -q "could not be read" "$FX/out"; check "a round that cannot be read asks for the row too" $?
setup lower; rm "$FX/reviews.json"; PATH="$work/bin:$PATH" MERGE_POLL=0 bash "$script" 7 --repo o/r --round >"$FX/out" 2>&1
rc=$?; [ "$rc" = 1 ] && grep -q '^review round at least 1' "$FX/out"; check "a lower-bound count asks for the row too" $?
recorded logins; PATH="$work/bin:$PATH" MERGE_POLL=0 bash "$script" 7 --repo o/r --round --reviewer-logins someone-else >"$FX/out" 2>&1
grep -q '^review round 1 on this pull request' "$FX/out"; check "--reviewer-logins counts only those accounts" $?

setup first
run merge "round 1"
grep -q '^review round 1 on this pull request' "$FX/out" && ! grep -q 'wording fix' "$FX/out"; check "round 1: the count, no budget sentence" $?
setup unread; rm "$FX/reviews.json"
run merge "a failed fetch of the reviews still merges"
grep -q '^review round at least 1 .*reviews.json could not be read' "$FX/out"; check "a failed fetch reads as a lower bound" $?
setup nopython; mkdir -p "$FX/bin"; printf '#!/bin/sh\nexit 1\n' >"$FX/bin/python3"; chmod +x "$FX/bin/python3"
PATH="$FX/bin:$work/bin:$PATH" MERGE_POLL=0 bash "$script" 7 --repo o/r >"$FX/out" 2>&1
[ -f "$FX/merged" ] && grep -q '^review round: not read' "$FX/out"; s=$?; check "attest.py failing says so and still merges" $s

echo "-- after the merge, the named issues (#490): printed, never a stop"
# issue <case-dir> <n> <body>: an issue fixture with that body
issue() { jq -n --arg b "$3" '{body: $b}' >"$FX/issue-$2.json"; }
named_pr() { # <case-dir> <closing numbers, space-separated> <description>
  setup "$1"
  jq -n --arg h "$H" --arg b "$3" --arg c "$2" '{state: "OPEN", headRefOid: $h, headRefName: "b", body: $b,
    closingIssuesReferences: [$c | split(" ")[] | select(. != "") | {number: tonumber, repository: {name: "r", owner: {login: "o"}}}]}' >"$FX/pr.json"
}
open_ac=$'## What to build\n\nx\n\n## Acceptance criteria\n\n- [x] one done\n- [ ] two left\r\n- [ ] three left\n\n## Not building\n\n- [ ] not a criterion'
done_ac=$'## Acceptance criteria\n\n- [x] one\n- [x] two\n\n## Outcome\n\nCompleted.'
named_pr partof "" $'## What and why\n\nx\n\nPart of #12\n\nAssisted-by: a:b'; issue partof 12 "$open_ac"
run merge "a merge naming an open issue with Part of"
grep -qx 'o/r#12, part of this change:' "$FX/out" && grep -qx '    - \[ \] two left' "$FX/out" && grep -qx '    - \[ \] three left' "$FX/out"
check "Part of #12: its two unticked criteria are printed" $?
! grep -q 'not a criterion\|one done\|no ## Outcome' "$FX/out"; check "only unticked lines under Acceptance criteria; no ending asked of an open issue" $?
grep -q '^Whoever merged ticks the criteria' "$FX/out"; check "it ends with the line for whoever merged" $?
[ "$(grep -n -m1 '^MERGED' "$FX/out" | cut -d: -f1)" -lt "$(grep -n -m1 '^o/r#12' "$FX/out" | cut -d: -f1)" ] && s=0 || s=1; check "printed after the merge" $s
# Every call after the merge (the log has the --body's lines too, skipped here):
# a pull request view, or a plain `gh api` read of the issue.
sed -n "$(grep -n -m1 '^pr merge' "$FX/calls" | cut -d: -f1),\$p" "$FX/calls" | sed 1d | grep -E '^(pr|api|issue|repo) ' \
  | grep -vE '^pr view 7 -R o/r --json (state,mergeCommit|closingIssuesReferences) --jq |^api repos/o/r/issues/12 --jq [^-]*$' >"$FX/odd"
[ ! -s "$FX/odd" ] && [ "$(grep -c '^api repos/o/r/issues/12 ' "$FX/calls")" = 1 ] && s=0 || s=1
check "the issue reads are GET only" $s
head -n "$(grep -n -m1 '^pr merge' "$FX/calls" | cut -d: -f1)" "$FX/calls" | grep -q 'issues/12\|closingIssuesReferences' && s=1 || s=0
check "nothing is read for the issues before the merge" $s

named_pr closes "12" $'## What and why\n\nx\n\nCloses #12'; issue closes 12 $'## Acceptance criteria\n\n- [x] one\n\n## Not building\n\nx'
run merge "a merge closing an issue with no ending"
grep -qx 'o/r#12, closed by this merge:' "$FX/out" && grep -qx '  no ## Outcome (or ## Decision for a record) in the body' "$FX/out" && ! grep -q unticked "$FX/out"
check "Closes #12 without Outcome: the missing ending is printed" $?

named_pr settled "12 13" $'Closes #12\nCloses #13\nPart of #12'; issue settled 12 "$done_ac"
issue settled 13 $'## Acceptance criteria\n\n- [x] one\n\n## Decision\n\nDecided.'
run merge "a merge closing two settled issues"
! grep -q '^o/r#\|Whoever merged' "$FX/out"; check "every criterion ticked and an ending: nothing printed (must not print)" $?
[ "$(grep -c 'issues/12 ' "$FX/calls")" = 1 ] && s=0 || s=1; check "an issue both closed and Part of is read once" $s

named_pr nobody "" $'## What and why\n\nKept apart of #9 on purpose; #489 merged with Part of #485 in prose.\nPart of #485 is quoted here as an example, not a link.'
run merge "a merge naming no issue"
! grep -q 'Whoever merged\|not read' "$FX/out"; check "no issue named (prose quoting Part of #485 is not a link line): nothing printed" $?
! grep -qE 'issues/[0-9]+ ' "$FX/calls"; check "and no issue is read" $?

named_pr unread "12" $'Closes #12\nPart of o/other#5'; issue unread 12 "$done_ac"
run merge "an issue that cannot be read still exits 0"
grep -qx 'o/other#5: not read' "$FX/out" && grep -q '^Whoever merged' "$FX/out"; check "a failed issue read prints not read" $?
named_pr norefs "" $'Part of #12'; issue norefs 12 "$open_ac"
jq '.closingIssuesReferences = "x"' "$FX/pr.json" >"$FX/p" && mv "$FX/p" "$FX/pr.json"
run merge "the closing references cannot be read: still exits 0"
grep -qx 'issues this merge closed: not read' "$FX/out" && grep -qx 'o/r#12, part of this change:' "$FX/out"; check "unreadable closing references say so; Part of is still read" $?

named_pr two "" $'x\n\nPart of #12, #13.'; issue two 12 "$open_ac"; issue two 13 "$open_ac"
run merge "a Part of line naming two issues"
grep -qx 'o/r#12, part of this change:' "$FX/out" && grep -qx 'o/r#13, part of this change:' "$FX/out"; check "both issues on the line are read" $?

named_pr queued "12" $'Closes #12'; issue queued 12 $'## Acceptance criteria\n\n- [ ] left'
printf '{"state":"OPEN","mergeCommit":null}' >"$FX/after.json"
run merge "a merge queue takes it: gh pr merge succeeds, the state is still OPEN"
grep -q '^Not merged yet (OPEN null)' "$FX/out" && ! grep -q 'issues/12' "$FX/calls" && ! grep -q '^o/r#12' "$FX/out"
check "not merged yet: says so and reads no issue" $?

echo "-- a release pull request of coolbress/plinth waits for its e2e (#855)"
# release_pr <case> [title]: everything green; only the e2e runs differ.
release_pr() {
  setup "$1"
  jq --arg t "${2:-chore(release): v9.9.9}" '.title = $t | .headRefName = "release/v9.9.9"' "$FX/pr.json" >"$FX/p" && mv "$FX/p" "$FX/pr.json"
}
e2e_runs() { # one `<conclusion|-:status> <head_sha> [head_branch]` per argument, oldest first; GitHub's own order is not relied on. The branch defaults to the release's; `null` is none
  local a c s b i=0
  { for a in "$@"; do read -r c s b <<<"$a"; b="${b:-release/v9.9.9}"; i=$((i+1)); t="2026-11-07T10:00:0${i}Z"
      if [ "${c#-:}" = "$c" ]; then jq -n --arg c "$c" --arg s "$s" --arg t "$t" --arg b "$b" '{status:"completed",conclusion:$c,head_sha:$s,head_branch:(if $b == "null" then null else $b end),run_started_at:$t,html_url:"https://example.test/runs/\($c)"}'
      else jq -n --arg st "${c#-:}" --arg s "$s" --arg t "$t" --arg b "$b" '{status:$st,conclusion:null,head_sha:$s,head_branch:(if $b == "null" then null else $b end),run_started_at:$t,html_url:"https://example.test/runs/\($st)"}'; fi
    done; } | jq -s '{workflow_runs:.}' >"$FX/e2e.json"
}
P="--repo coolbress/plinth"
says_cmd() { grep -qF 'gh workflow run e2e.yml --ref release/v9.9.9' "$FX/out"; }

release_pr e2e-none; e2e_runs
run stop "no e2e run on the head" $P
says_cmd; check "and it prints the dispatch command for the release branch" $?
grep -q 'head_sha='"$H" "$FX/calls"; check "and the runs were asked by head_sha" $?
! grep -q 'pr checks' "$FX/calls"; check "and it stops before waiting on the checks" $?
release_pr e2e-red; e2e_runs "failure $H"
run stop "a red e2e run on the head" $P
says_cmd; check "and it prints the dispatch command" $?
grep -qF 'failure https://example.test/runs/failure' "$FX/out"; check "and it names the red run" $?
release_pr e2e-running; e2e_runs "-:in_progress $H"
run stop "an e2e run still going on the head" $P
grep -qF 'in_progress https://example.test/runs/in_progress' "$FX/out"; check "and it names the run going" $?
for verdict in cancelled skipped; do
  release_pr "e2e-$verdict"; e2e_runs "$verdict $H"
  run stop "a $verdict e2e run on the head" $P
done
release_pr e2e-other; e2e_runs "success 2222222222222222222222222222222222222222"
run stop "a green e2e run answered for another commit" $P
release_pr e2e-unread
run stop "the e2e runs cannot be read" $P
grep -q 'cannot read the e2e runs' "$FX/out"; check "and it says so, not 'no run'" $?
release_pr e2e-green; e2e_runs "success $H"
run merge "a green e2e run on the head" $P
grep -qF 'https://example.test/runs/success' "$FX/out"; check "and it names the green run" $?
release_pr e2e-again; e2e_runs "failure $H" "success $H"
run merge "a red run, then a green one dispatched again on the same head" $P
release_pr e2e-later-red; e2e_runs "success $H" "failure $H"
run stop "a green run, then a red one on the same head: the run started last speaks" $P
release_pr e2e-later-running; e2e_runs "success $H" "-:in_progress $H"
run stop "a green run, then one still going on the same head" $P
release_pr e2e-case; e2e_runs
run stop "the repository's name in another case is the same repository" --repo CoolBress/Plinth
release_pr e2e-still-red; e2e_runs "success $H"
printf '[{"name":"ci / install","state":"FAILURE"},{"name":"third-party / review","state":"SUCCESS"}]' >"$FX/checks.json"
run stop "a green e2e run does not excuse a red check" $P

echo "-- only a run on a release/v* branch counts: elsewhere it never moved the calls to its own commit (#862)"
for b in main fix/e2e release/notes release-v9.9.9 my/release/v9.9.9 null; do
  release_pr "e2e-on-$(tr '/' '-' <<<"$b")"; e2e_runs "success $H $b"
  run stop "a green run at the head on $b" $P
  says_cmd; check "  and it prints the dispatch command for the release branch" $?
  grep -qF '(no run on a release/v* branch at that commit)' "$FX/out"; check "  and it says none counts, not that the commit has no run" $?
done
release_pr e2e-probe; e2e_runs "success $H release/v0.0.0-probe"
run merge "a green run at the head on another release/v* branch" $P
release_pr e2e-main-then-release; e2e_runs "success $H main" "success $H"
run merge "a green run on main, then a green one on the release branch" $P
release_pr e2e-release-then-main; e2e_runs "success $H" "failure $H main"
run merge "a green release run is not spoken over by a later run elsewhere" $P
release_pr e2e-red-then-main; e2e_runs "failure $H" "success $H main"
run stop "a red release run is not excused by a later green run elsewhere" $P
grep -qF 'failure https://example.test/runs/failure' "$FX/out"; check "  and it names the red run" $?
release_pr e2e-going-then-main; e2e_runs "-:in_progress $H" "success $H main"
run stop "a release run still going is not excused by a green run elsewhere" $P

echo "-- everything else is unchanged"
release_pr e2e-round; e2e_runs
PATH="$work/bin:$PATH" MERGE_POLL=0 bash "$script" 7 $P --round >"$FX/out" 2>&1; check "--round only reads, and does not stop on the e2e runs" $?
! grep -q 'e2e.yml' "$FX/calls"; check "  and does not ask for them" $?
for title in 'fix(release): run e2e before the merge' 'chore(release): prepare the notes' 'chore(release): v9.9.9 and more'; do
  release_pr e2e-title "$title"; e2e_runs; rm -f "$FX/merged" "$FX/calls"
  run merge "the title '$title' is not a release's" $P
  ! grep -q 'e2e.yml' "$FX/calls"; check "  and no e2e run is asked for" $?
done
release_pr e2e-elsewhere; rm -f "$FX/merged" "$FX/calls"
run merge "the same title on another repository, which has no e2e.yml to ask"
! grep -q 'e2e.yml' "$FX/calls"; check "  and no e2e run is asked for" $?

echo "-- a neutral CodeQL on a Dependabot pull request (#872)"
# What plinth-template#220 showed: every check green, CodeQL neutral, no
# code-scanning run on the head (default setup starts none for Dependabot).
neutral='[{"name":"ci / install","state":"SUCCESS"},{"name":"third-party / review","state":"SUCCESS"},{"name":"CodeQL","state":"NEUTRAL"}]'
runs() { # <sha> <run lines "id path status conclusion name"...>: the Actions runs at that commit
  local sha="$1" a id p st co nm; shift
  { for a in "$@"; do read -r id p st co nm <<<"$a"
      jq -n --arg id "$id" --arg p "$p" --arg st "$st" --arg co "$co" --arg n "${nm:-run}" --arg s "$sha" \
        '{id:($id|tonumber),path:$p,status:$st,conclusion:(if $co == "null" then null else $co end),name:$n,head_sha:$s,html_url:"https://example.test/runs/\($id)"}'
    done; } | jq -s '{workflow_runs:.}' >"$FX/runs-$sha.json"
}
run_jobs() { # <run id> <job lines "status conclusion name...">
  local id="$1" a st co nm; shift
  { for a in "$@"; do read -r st co nm <<<"$a"
      jq -n --arg st "$st" --arg co "$co" --arg n "$nm" --arg id "$id" \
        '{status:$st,conclusion:(if $co == "null" then null else $co end),name:$n,html_url:"https://example.test/runs/\($id)/job"}'
    done; } | jq -s '{jobs:.}' >"$FX/jobs-$id.json"
}
CS=dynamic/github-code-scanning/codeql
dependabot() { # <case>: neutral CodeQL, author Dependabot, CI runs on the head and none of them code scanning
  setup "$1"; printf '%s' "$neutral" >"$FX/checks.json"
  printf '{"user":{"login":"dependabot[bot]","type":"Bot"}}' >"$FX/pull.json"
  runs "$H" "11 .github/workflows/ci.yml completed success CI"
  run_jobs 11 "completed success build"
  runs abc "21 $CS completed success Push" "22 .github/workflows/ci.yml completed success CI"
  run_jobs 21 "completed success Analyze (actions)" "completed success Analyze (python)"
}
dependabot dep-ok
run merge "Dependabot, CodeQL neutral, no Analyze run on the head"
grep -q "default setup does not analyse Dependabot's pull requests" "$FX/out"; check "  and it says why it passed the neutral CodeQL" $?
says_neutral() { grep -q "A neutral CodeQL is not a pass" "$FX/out" && grep -qF -- "$1" "$FX/out"; }
dependabot dep-analyzed; runs "$H" "11 .github/workflows/ci.yml completed success CI" "12 $CS completed success PR"
run_jobs 12 "completed success Analyze (python)"
run stop "Dependabot, CodeQL neutral, an Analyze run on the head"
says_neutral "an analysis exists on this head"; check "  and it says what neutral means and why the exception does not apply" $?
grep -qF "Analyze (python)" "$FX/out"; check "  and it names the analysis" $?
dependabot dep-queued; runs "$H" "12 $CS queued null PR"
run stop "Dependabot, CodeQL neutral, a code-scanning run on the head that lists no job yet"
dependabot dep-advanced; run_jobs 11 "completed success Analyze (javascript)"
run stop "Dependabot, CodeQL neutral, an Analyze job in a workflow of the repository's own"
dependabot dep-person; printf '{"user":{"login":"someone","type":"User"}}' >"$FX/pull.json"
run stop "a person's pull request with CodeQL neutral and no Analyze run"
says_neutral "the author is someone, not dependabot[bot]"; check "  and it says what neutral means and who the author is" $?
dependabot dep-lookalike; printf '{"user":{"login":"dependabot","type":"User"}}' >"$FX/pull.json"
run stop "an author named dependabot without [bot]"
dependabot dep-red
printf '[{"name":"ci / install","state":"FAILURE"},{"name":"third-party / review","state":"SUCCESS"},{"name":"CodeQL","state":"NEUTRAL"}]' >"$FX/checks.json"
run stop "Dependabot, CodeQL neutral and another check red"
says_neutral "other checks are not green"; check "  and it lists both" $?
dependabot dep-unread; rm "$FX/runs-$H.json"
run stop "Dependabot, CodeQL neutral, the head's runs cannot be read"
grep -q "cannot read the Actions runs on $H" "$FX/out"; check "  and it says so" $?
dependabot dep-other-name; printf '[{"name":"ci / install","state":"NEUTRAL"},{"name":"third-party / review","state":"SUCCESS"}]' >"$FX/checks.json"
run stop "Dependabot, another check neutral"
setup plain; run merge "a pull request with every check green"
! grep -qE 'pulls/7 --jq|actions/runs' "$FX/calls"; check "  reads neither the author nor the runs" $?
echo "-- after that merge, the base branch's analysis (#872)"
after_case() { # <case> <want-exit> <label>
  local rc; PATH="$work/bin:$PATH" MERGE_POLL=0 MERGE_ANALYZE_WAIT=0 bash "$script" 7 --repo o/r >"$FX/out" 2>&1; rc=$?
  [ -f "$FX/merged" ] && [ "$rc" = "$2" ]; check "$3 (exit $rc)" $?
}
dependabot main-pass; after_case main-pass 0 "both Analyze jobs pass on the merge commit: merged, exit 0"
grep -q '^code scanning on main at abc: passed' "$FX/out" && grep -qF 'Analyze (python)' "$FX/out"; check "  and it reports the pass, job by job" $?
[ "$(grep -n -m1 '^MERGED' "$FX/out" | cut -d: -f1)" -lt "$(grep -n -m1 '^code scanning on main' "$FX/out" | cut -d: -f1)" ] && s=0 || s=1; check "  after the merge" $s
dependabot main-fail; run_jobs 21 "completed success Analyze (actions)" "completed failure Analyze (python)"
after_case main-fail 1 "an Analyze job fails on the merge commit: merged, exit 1"
grep -q '^FAIL: code scanning failed on main at abc' "$FX/out" && grep -qF 'failure	Analyze (python)' "$FX/out" \
  && grep -q 'new pull request' "$FX/out" && grep -q 'gh run rerun' "$FX/out"; check "  and it says it failed on main, which job, and what to do next" $?
dependabot main-none; runs abc "22 .github/workflows/ci.yml completed success CI"
after_case main-none 0 "no Analyze run on the merge commit: merged, exit 0"
grep -q '^code scanning on main at abc: not started' "$FX/out" && grep -q 'not confirmed' "$FX/out" && ! grep -q passed "$FX/out"; check "  and it says not started, not confirmed" $?
dependabot main-running; run_jobs 21 "completed success Analyze (actions)" "in_progress null Analyze (python)"
after_case main-running 0 "an Analyze job still running when the wait ends: merged, exit 0"
grep -q '^code scanning on main at abc: not finished' "$FX/out" && grep -q 'not confirmed' "$FX/out"; check "  and it says not finished, not confirmed" $?
dependabot main-waits; run_jobs 21 "in_progress null Analyze (python)"
PATH="$work/bin:$PATH" MERGE_POLL=1 MERGE_ANALYZE_WAIT=2 bash "$script" 7 --repo o/r >"$FX/out" 2>&1
[ "$(grep -c 'runs -f head_sha=abc' "$FX/calls")" -ge 2 ] && grep -q '^code scanning on main at abc: not finished' "$FX/out"
check "  with a wait, it reads again until the wait ends" $?
dependabot main-unread; rm "$FX/runs-abc.json"
after_case main-unread 0 "the merge commit's runs cannot be read: merged, exit 0"
grep -q '^code scanning on main at abc: not read' "$FX/out"; check "  and it says not read" $?
setup main-plain; run merge "a merge with every check green"
! grep -q 'runs -f head_sha=abc' "$FX/calls" && ! grep -q '^code scanning' "$FX/out"; check "  waits for no analysis on the base branch" $?

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
