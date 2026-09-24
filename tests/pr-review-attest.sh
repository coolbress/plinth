#!/usr/bin/env bash
# What the third-party review check blocks, and what it must not block.
#
# The judgement is scripts/pr-review/attest.py, which pr-review.yml fetches
# and runs. Left to the workflow alone nobody runs it before a pull request:
# the first run is the test, and by then that pull request is already red. So
# it is run here against fixtures.
#
# The fixtures are measured, not invented (2026-09-01): the first version
# searched `pulls/*/reviews` and found nothing there, because Codex leaves a
# marker in one issue comment. The shapes below are what actually arrived.
#
# The contract is narrow: "a third party finished a review of this commit".
# The review's verdict never blocks (MSR '26: twelve of thirteen review agents
# under a 60% signal ratio). Both directions are tested; a pass-only test
# proves little.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="$root/.github/workflows/pr-review.yml"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

attest="$root/scripts/pr-review/attest.py"

HEAD=71a704cdca35f00de6e110a3d77a165d895d882a
OLD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
BOT='chatgpt-codex-connector[bot]'

# The completion comment that arrives when nothing was found; wording as
# measured. The comment names the commit itself: `**Reviewed commit:** \`db8c8772fd\``.
done_cmt() {  # author, text, [commit named], [created_at; '' = the field is absent]
  # shellcheck disable=SC2016  # single quotes are right: Python code, not shell expansion
  python3 -c 'import json,sys
who, text = sys.argv[1:3]
sha, at = sys.argv[3:5]
body = text + ("\n\n**Reviewed commit:** `" + sha + "`" if sha else "")
print(json.dumps([{"user": {"login": who}, **({"created_at": at} if at else {}),
                   "body": body}], ensure_ascii=False))' "$1" "$2" "${3:-}" "${4-2026-09-18T07:21:03Z}"
}

# One issue comment: author, marker sha, marker status.
cmt() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
who, sha, status = sys.argv[1:4]
mark = ""
if sha:
    mark = ('<!-- codex-security-review:v1 ' + json.dumps({
        "blockingSeverityThreshold": "P0", "headSha": sha, "mergeGateEnabled": False,
        "pullRequestNumber": 211, "repository": "owner/name", "status": status,
    }) + ' -->')
body = "<!-- codex-pull-request-review-summary -->\n" + mark + "\n## Codex Review Summary\n"
print(json.dumps([{"user": {"login": who}, "body": body}], ensure_ascii=False))
PY
}

fails=0
run() {  # name, issue-comments JSON, expected exit, [reviews JSON], [accepted logins]
  printf '%s' "$2" > "$tmp/i.json"
  printf '%s' "${4:-[]}" > "$tmp/r.json"
  echo '[]' > "$tmp/rc.json"
  python3 "$attest" "$HEAD" "${5:-$BOT}" \
    "$tmp/r.json" "$tmp/rc.json" "$tmp/i.json" >"$tmp/log" 2>&1
  got=$?
  if [ "$got" -ne "$3" ]; then
    echo "  FAIL  $1: expected exit $3, got $got" >&2
    sed 's/^/        /' "$tmp/log" >&2
    fails=$((fails + 1))
  else
    echo "  PASS  $1"
  fi
}

echo "-- must block"
run "no comments at all"                    '[]'                              1
run "a human comment without marker"        '[{"user":{"login":"me"},"body":"fixed"}]' 1
run "marker status running (still looking)" "$(cmt "$BOT" "$HEAD" running)"   1
run "completed, but for an old commit"      "$(cmt "$BOT" "$OLD" completed)"  1
run "another bot with the same marker"      "$(cmt 'someone-else[bot]' "$HEAD" completed)" 1
run "broken marker JSON"                    '[{"user":{"login":"chatgpt-codex-connector[bot]"},"body":"<!-- codex-security-review:v1 {broken} -->"}]' 1
run "comments payload is not an array"      '{"message":"Not Found"}'         1

echo "-- must pass"
run "completed for this commit"             "$(cmt "$BOT" "$HEAD" completed)" 0
run "login differs in case"                 "$(cmt 'ChatGPT-Codex-Connector[bot]' "$HEAD" completed)" 0

echo "-- the verdict is not delegated (must NOT block)"
# Codex leaves no review and no comment when it finds nothing, only a marker; that passes.
run "zero findings still passes"            "$(cmt "$BOT" "$HEAD" completed)" 0

echo "-- review object signal (measured: arrives even with zero findings, before the marker)"
rvw() { printf '[{"user":{"login":"%s"},"commit_id":"%s","state":"COMMENTED"}]' "$1" "$2"; }
run "marker running but a review object arrived" "$(cmt "$BOT" "$HEAD" running)" 0 "$(rvw "$BOT" "$HEAD")"
run "a review object for an old commit does not count" '[]' 1 "$(rvw "$BOT" "$OLD")"
run "someone else's review object does not count"      '[]' 1 "$(rvw "someone" "$HEAD")"

echo "-- review comment signal: GitHub rewrites commit_id"
# Measured 2026-09-01: when a new commit lands on the pull request, GitHub
# moves the `commit_id` of live review comments to the new head; only
# `original_commit_id` stays. One comment from an old review turned every later
# push green within 20 seconds, 140 seconds before the real review arrived.
rcm() {  # author, commit_id, original_commit_id
  printf '[{"user":{"login":"%s"},"commit_id":"%s","original_commit_id":"%s","body":"P2 ..."}]' "$1" "$2" "$3"
}
runrc() {  # name, review-comments JSON, expected exit
  echo '[]' > "$tmp/i.json"; echo '[]' > "$tmp/r.json"
  printf '%s' "$2" > "$tmp/rc.json"
  python3 "$attest" "$HEAD" "$BOT" "$tmp/r.json" "$tmp/rc.json" "$tmp/i.json" >"$tmp/log" 2>&1
  got=$?
  if [ "$got" -ne "$3" ]; then
    echo "  FAIL  $1: expected exit $3, got $got" >&2; sed 's/^/        /' "$tmp/log" >&2; fails=$((fails + 1))
  else
    echo "  PASS  $1"
  fi
}
runrc "a review comment made on this commit passes"        "$(rcm "$BOT" "$HEAD" "$HEAD")" 0
runrc "an old comment moved onto the head does not count"  "$(rcm "$BOT" "$HEAD" "$OLD")"  1
runrc "someone else's review comment does not count"       "$(rcm "someone" "$HEAD" "$HEAD")" 1
runrc "a comment without original_commit_id does not count" '[{"user":{"login":"chatgpt-codex-connector[bot]"},"commit_id":"'"$HEAD"'"}]' 1

echo "-- a could-not-review notice is a review object, not a review (#204)"
# Asked by a person who is out of quota, Copilot still submits a review object
# on the head, state COMMENTED, and this notice is its whole body (measured
# 2026-09-19 on ranokay/waves#317 and dineTH2003-dev/WarehousePOS#59, no
# inline comment). It is matched on how the body begins, so a real review that
# mentions the words further down still counts.
CP='copilot-pull-request-reviewer[bot]'
NOTICE='Copilot was unable to review this pull request because the user who requested the review has reached their quota limit.'
REAL=$'### 🟡 Changes recommended\n\nThe retry loop never resets its counter.'   # the opening as measured
rv() {  # author, commit, body
  python3 -c 'import json,sys; print(json.dumps({"user": {"login": sys.argv[1]}, "commit_id": sys.argv[2], "state": "COMMENTED", "body": sys.argv[3]}, ensure_ascii=False))' "$1" "$2" "$3"
}
run "the measured notice as the only review on the head: does not count" '[]' 1 "[$(rv "$CP" "$HEAD" "$NOTICE")]" "$CP"
grep -qF "review $CP (COMMENTED) <- this commit, not counted: a could-not-review notice" "$tmp/log" \
  || { echo "  FAIL  log does not name the review and the notice as the reason" >&2; sed 's/^/        /' "$tmp/log" >&2; fails=$((fails + 1)); }
run "the notice with another reason after \"because\": does not count" '[]' 1 \
  "[$(rv "$CP" "$HEAD" 'Copilot was unable to review this pull request because it is too large.')]" "$CP"
run "the notice after leading whitespace: does not count" '[]' 1 "[$(rv "$CP" "$HEAD" $'\n  '"$NOTICE")]" "$CP"
run "the notice in another letter case: does not count" '[]' 1 \
  "[$(rv "$CP" "$HEAD" 'COPILOT WAS UNABLE TO REVIEW THIS PULL REQUEST because the user who requested the review has reached their quota limit.')]" "$CP"
run "the notice next to a real review from someone not accepted: does not count" '[]' 1 \
  "[$(rv "$CP" "$HEAD" "$NOTICE"),$(rv someone "$HEAD" "$REAL")]" "$CP"
run "a Copilot review with a real body on the head passes" '[]' 0 "[$(rv "$CP" "$HEAD" "$REAL")]" "$CP"
run "a review that mentions the words after its first line passes" '[]' 0 \
  "[$(rv "$CP" "$HEAD" "$REAL"$'\n\n'"Copilot was unable to review this pull request's lockfile.")]" "$CP"
run "a review with an empty body passes (Codex and CodeRabbit leave those)" '[]' 0 "[$(rv "$BOT" "$HEAD" '')]"
run "the notice on an older commit, a real review on the head: passes" '[]' 0 \
  "[$(rv "$CP" "$OLD" "$NOTICE"),$(rv "$CP" "$HEAD" "$REAL")]" "$CP"
run "the notice, then a real review, both on the head: passes" '[]' 0 \
  "[$(rv "$CP" "$HEAD" "$NOTICE"),$(rv "$CP" "$HEAD" "$REAL")]" "$CP"

# The pushes to the head branch, newest first, as `repos/<r>/activity` returns
# them (fields as measured on this branch, 2026-09-18).
push() {  # after, timestamp, [before]
  printf '{"after":"%s","before":"%s","timestamp":"%s","activity_type":"push","actor":{"login":"someone"}}' "$1" "${3:-$OLD}" "$2"
}
runsum() {  # name, issue-comments JSON, activity JSON ('-' = the argument is not given), expected exit
  printf '%s' "$2" > "$tmp/i.json"; echo '[]' > "$tmp/r.json"; echo '[]' > "$tmp/rc.json"
  if [ "$3" = "-" ]; then
    python3 "$attest" "$HEAD" "$BOT" "$tmp/r.json" "$tmp/rc.json" "$tmp/i.json" >"$tmp/log" 2>&1
  else
    printf '%s' "$3" > "$tmp/a.json"
    python3 "$attest" "$HEAD" "$BOT" "$tmp/r.json" "$tmp/rc.json" "$tmp/i.json" "$tmp/a.json" >"$tmp/log" 2>&1
  fi
  got=$?
  if [ "$got" -ne "$4" ]; then
    echo "  FAIL  $1: expected exit $4, got $got" >&2; sed 's/^/        /' "$tmp/log" >&2; fails=$((fails + 1))
  else
    echo "  PASS  $1"
  fi
}
T_PUSH=2026-09-18T07:15:40Z; T_DONE=2026-09-18T07:21:03.356745Z   # pushed, then reviewed
PUSHED="[$(push "$HEAD" "$T_PUSH")]"

echo "-- completion comment signal (measured: zero findings create no review object)"
D1="Codex Review: Didn't find any major issues. Keep it up!"   # wording as measured
D2="Security review completed. No security issues were found in this pull request."
runsum "completion comment names this commit"          "$(done_cmt "$BOT" "$D1" "${HEAD:0:10}")" "$PUSHED" 0
runsum "security review completion counts too"         "$(done_cmt "$BOT" "$D2" "$HEAD")" "$PUSHED" 0
runsum "completion naming another commit does not count" "$(done_cmt "$BOT" "$D1" "${OLD:0:10}")" "$PUSHED" 1
runsum "completion naming no commit does not count"    "$(done_cmt "$BOT" "$D1")" "$PUSHED" 1
runsum "the same wording from someone else does not count" "$(done_cmt someone "$D1" "$HEAD")" "$PUSHED" 1
# The reviewer's P1 scenario, head moved back to an older commit: the old
# completion names another commit and does not match.

echo "-- summary table row signal (#191: a zero-finding review started by a push left only this)"
# The summary comment as measured on plinth#186, #189 and #190 (2026-09-18):
# the HTML marker on the first line, then one table row per review, the commit
# as seven characters. On #190's second head that row was all the reviewer
# left. Both rows are measured: `Completed` there, `Running` on #195
# (`🔄 **Running** since <relative-time …>`, 2026-09-18).
row() {  # status cell, short sha, [completed at]
  printf '| 📝 **Code Review** | %s <relative-time datetime="%s">%s</relative-time> | `%s` | New commits |' "$1" "${3:-$T_DONE}" "${3:-$T_DONE}" "$2"
}
sum_cmt() {  # author, first line, row...
  python3 -c 'import json,sys
who, first = sys.argv[1:3]
body = (first + "\n\n## Codex Review Summary\n\nThis comment shows the latest Codex review activity on this pull request.\n\n"
        "| Review | Status | Commit | Review trigger |\n| --- | --- | --- | --- |\n" + "\n".join(sys.argv[3:])
        + "\n\n\n\n<details> <summary>ℹ️ About Codex in GitHub</summary>\n<br/>\n\nCodex reacts with 👀 while any review is running.\n\n</details>")
print(json.dumps([{"user": {"login": who}, "body": body}], ensure_ascii=False))' "$@"
}
SUM='<!-- codex-pull-request-review-summary -->'
DONE_ST='✅ **Completed**'; RUN_ST='🔄 **Running** since'
runsum "Completed row for this head passes"              "$(sum_cmt "$BOT" "$SUM" "$(row "$DONE_ST" "${HEAD:0:7}")")" "$PUSHED" 0
runsum "Completed row for an older head does not count"  "$(sum_cmt "$BOT" "$SUM" "$(row "$DONE_ST" "${OLD:0:7}")")" "$PUSHED" 1
runsum "Running row for this head does not count"        "$(sum_cmt "$BOT" "$SUM" "$(row "$RUN_ST" "${HEAD:0:7}")")" "$PUSHED" 1
runsum "the same row from someone else does not count"   "$(sum_cmt someone "$SUM" "$(row "$DONE_ST" "${HEAD:0:7}")")" "$PUSHED" 1
runsum "a sha inside the head but not its prefix does not count" "$(sum_cmt "$BOT" "$SUM" "$(row "$DONE_ST" "${HEAD:1:7}")")" "$PUSHED" 1
runsum "a sha shorter than seven characters does not count" "$(sum_cmt "$BOT" "$SUM" "$(row "$DONE_ST" "${HEAD:0:6}")")" "$PUSHED" 1
runsum "the row in a comment that is not the summary comment does not count" "$(sum_cmt "$BOT" "Here is the table you asked for:" "$(row "$DONE_ST" "${HEAD:0:7}")")" "$PUSHED" 1
runsum "old head Completed, this head Running: does not count" "$(sum_cmt "$BOT" "$SUM" "$(row "$DONE_ST" "${OLD:0:7}")" "$(row "$RUN_ST" "${HEAD:0:7}")")" "$PUSHED" 1
runsum "old head Completed, this head Completed: passes"  "$(sum_cmt "$BOT" "$SUM" "$(row "$DONE_ST" "${OLD:0:7}")" "$(row "$DONE_ST" "${HEAD:0:7}")")" "$PUSHED" 0

# Seven characters do not name one commit: a head made to share them with an
# earlier, reviewed head would ride on that head's row (the reviewer's P1 on
# PR #192). So the row also has to be newer than the push that brought this
# head, both times written by a server (the vendor's, GitHub's), neither by
# the author of the commit. Where the push cannot be read the row does not
# count; the other signals are untouched.
ROW_HEAD="$(sum_cmt "$BOT" "$SUM" "$(row "$DONE_ST" "${HEAD:0:7}")")"
runsum "the row is older than the push of this head (an earlier head with the same seven characters): does not count" \
  "$ROW_HEAD" "[$(push "$HEAD" 2026-09-18T07:30:00Z)]" 1
runsum "this head pushed, replaced, reviewed row in between, pushed back: the newest push decides, does not count" \
  "$ROW_HEAD" "[$(push "$HEAD" 2026-09-18T07:30:00Z),$(push "$OLD" 2026-09-18T07:16:00Z),$(push "$HEAD" "$T_PUSH")]" 1
runsum "completed in the same second as the push: does not count" "$ROW_HEAD" "[$(push "$HEAD" 2026-09-18T07:21:03Z)]" 1
runsum "no push of this head in the log: does not count"  "$ROW_HEAD" "[$(push "$OLD" "$T_PUSH")]" 1
runsum "an empty push log: does not count"                "$ROW_HEAD" '[]' 1
runsum "the push log could not be read (null): does not count" "$ROW_HEAD" 'null' 1
runsum "no push log given: does not count"                "$ROW_HEAD" - 1
runsum "a push without a timestamp: does not count"       "$ROW_HEAD" "[{\"after\":\"$HEAD\"}]" 1
runsum "a row without a completion time: does not count" \
  "$(sum_cmt "$BOT" "$SUM" "| 📝 **Code Review** | $DONE_ST | \`${HEAD:0:7}\` | New commits |")" "$PUSHED" 1
runsum "a completion time that is not UTC: does not count" \
  "$(sum_cmt "$BOT" "$SUM" "$(row "$DONE_ST" "${HEAD:0:7}" 2026-09-18T09:21:03+02:00)")" "$PUSHED" 1
# The time says the row was completed after this head arrived, not which
# commit was completed (the reviewer's second P1 on PR #192): a review of an
# earlier head with the same seven characters, still running when this head is
# pushed, completes after the push. The log holds every commit the branch has
# pointed at (`before` and `after` of each push, force pushes included), so the
# row counts only when this head is the one commit among them that begins with
# the row's characters, and only when the log is whole (under a page of 100,
# as the gate reads it).
TWIN="${HEAD:0:7}bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"    # another commit, the same seven characters
NEAR="${HEAD:0:6}0bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"   # shares six
runsum "the head replaced a commit with the same seven characters whose review finished after the push: does not count" \
  "$ROW_HEAD" "[$(push "$HEAD" "$T_PUSH" "$TWIN")]" 1
grep -qF "another commit" "$tmp/log" || { echo "  FAIL  log does not name the other commit as the reason" >&2; sed 's/^/        /' "$tmp/log" >&2; fails=$((fails + 1)); }
runsum "such a commit anywhere earlier in the log: does not count" \
  "$ROW_HEAD" "[$(push "$HEAD" "$T_PUSH"),$(push "$OLD" 2026-09-18T07:10:00Z "$TWIN"),$(push "$TWIN" 2026-09-18T07:05:00Z)]" 1
runsum "a commit sharing only six characters does not get in the way: passes" \
  "$ROW_HEAD" "[$(push "$HEAD" "$T_PUSH" "$NEAR")]" 0
many() {  # how many pushes, this head first
  python3 -c 'import json,sys
n, head, old, t = int(sys.argv[1]), *sys.argv[2:5]
print(json.dumps([{"after": head, "before": old, "timestamp": t}] + [{"after": old, "before": old, "timestamp": "2026-09-18T07:00:00Z"}] * (n - 1)))' "$1" "$HEAD" "$OLD" "$T_PUSH"
}
runsum "a log of 99 pushes is whole: passes"                       "$ROW_HEAD" "$(many 99)"  0
runsum "a full page of 100 pushes may have more behind it: does not count" "$ROW_HEAD" "$(many 100)" 1
runsum "when it does not count for the push, the log says so" "$ROW_HEAD" 'null' 1
if grep -qF "the push of this head" "$tmp/log"; then
  echo "  PASS  log names the push as the reason"
else
  echo "  FAIL  log does not say the row was left out for the push" >&2; sed 's/^/        /' "$tmp/log" >&2; fails=$((fails + 1))
fi
# The other signals do not read the push log: a review object passes without it.
echo '[]' > "$tmp/i.json"
printf '[{"user":{"login":"%s"},"commit_id":"%s","state":"COMMENTED"}]' "$BOT" "$HEAD" > "$tmp/r.json"
if python3 "$attest" "$HEAD" "$BOT" "$tmp/r.json" "$tmp/rc.json" "$tmp/i.json" >"$tmp/log" 2>&1; then
  echo "  PASS  a review object passes with no push log"
else
  echo "  FAIL  a review object needs the push log" >&2; fails=$((fails + 1))
fi
if grep -q '"\$RUNNER_TEMP/icomments.json" "\$RUNNER_TEMP/activity.json"' "$wf"; then
  echo "  PASS  the step hands the push log to the judgement"
else
  echo "  FAIL  the step does not pass activity.json to attest.py; the completion comment and the summary row would never count" >&2; fails=$((fails + 1))
fi

echo "-- the completion comment is bound to the push and to the one commit, as the row is (#193)"
# The comment names ten characters and stays on the pull request, so a later
# head made to share them would pass on it before any review of that head. It
# gets the row's two conditions from the same push log: created after the
# newest push of this head (`created_at`, GitHub's), and this head the one
# commit the branch has pointed at that begins with the characters it names.
# A fork's branch is not in the base repository's log (measured on cli/cli,
# 2026-09-18): there the comment does not count, by the owner's decision.
CMT_HEAD="$(done_cmt "$BOT" "$D1" "${HEAD:0:10}")"   # created 07:21:03Z, after T_PUSH
TWIN10="${HEAD:0:10}bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"   # another commit, the same ten characters
NEAR9="${HEAD:0:9}0bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"    # shares nine
runsum "the comment is older than the newest push of this head: does not count" \
  "$CMT_HEAD" "[$(push "$HEAD" 2026-09-18T07:30:00Z)]" 1
grep -qF "completion comment ${HEAD:0:10}" "$tmp/log" && grep -qF "not after the push of this head" "$tmp/log" \
  || { echo "  FAIL  log does not name the comment's commit and the push as the reason" >&2; sed 's/^/        /' "$tmp/log" >&2; fails=$((fails + 1)); }
runsum "this head pushed again after the comment: the newest push decides, does not count" \
  "$CMT_HEAD" "[$(push "$HEAD" 2026-09-18T07:30:00Z),$(push "$OLD" 2026-09-18T07:16:00Z),$(push "$HEAD" "$T_PUSH")]" 1
runsum "created in the same second as the push: does not count" "$CMT_HEAD" "[$(push "$HEAD" 2026-09-18T07:21:03Z)]" 1
runsum "the head replaced a commit with the same ten characters, comment newer than the push: does not count" \
  "$CMT_HEAD" "[$(push "$HEAD" "$T_PUSH" "$TWIN10")]" 1
grep -qF "completion comment ${HEAD:0:10}" "$tmp/log" && grep -qF "another commit" "$tmp/log" \
  || { echo "  FAIL  log does not name the comment's commit and the other commit as the reason" >&2; sed 's/^/        /' "$tmp/log" >&2; fails=$((fails + 1)); }
runsum "such a commit as an earlier push's head: does not count" \
  "$CMT_HEAD" "[$(push "$HEAD" "$T_PUSH"),$(push "$OLD" 2026-09-18T07:10:00Z "$TWIN10"),$(push "$TWIN10" 2026-09-18T07:05:00Z)]" 1
runsum "a comment naming all forty characters, older than the push: does not count" \
  "$(done_cmt "$BOT" "$D2" "$HEAD")" "[$(push "$HEAD" 2026-09-18T07:30:00Z)]" 1
runsum "no push of this head in the log: does not count"        "$CMT_HEAD" "[$(push "$OLD" "$T_PUSH")]" 1
runsum "an empty push log: does not count"                      "$CMT_HEAD" '[]' 1
runsum "the push log could not be read (null): does not count"  "$CMT_HEAD" 'null' 1
grep -qF "completion comment ${HEAD:0:10}" "$tmp/log" && grep -qF "the push of this head could not be read" "$tmp/log" \
  || { echo "  FAIL  log does not say the comment was left out for the push" >&2; sed 's/^/        /' "$tmp/log" >&2; fails=$((fails + 1)); }
runsum "no push log given: does not count"                      "$CMT_HEAD" - 1
runsum "a push without a timestamp: does not count"             "$CMT_HEAD" "[{\"after\":\"$HEAD\"}]" 1
runsum "a full page of 100 pushes may have more behind it: does not count" "$CMT_HEAD" "$(many 100)" 1
runsum "a comment without created_at: does not count"           "$(done_cmt "$BOT" "$D1" "${HEAD:0:10}" '')" "$PUSHED" 1
runsum "a created_at that is not a UTC time: does not count"    "$(done_cmt "$BOT" "$D1" "${HEAD:0:10}" 2026-09-18T09:21:03+02:00)" "$PUSHED" 1
runsum "a comment newer than the push, no such other commit: passes" "$CMT_HEAD" "$PUSHED" 0
runsum "one second after the push: passes"                      "$CMT_HEAD" "[$(push "$HEAD" 2026-09-18T07:21:02Z)]" 0
runsum "a commit sharing only nine characters does not get in the way: passes" \
  "$CMT_HEAD" "[$(push "$HEAD" "$T_PUSH" "$NEAR9")]" 0
runsum "a log of 99 pushes is whole: passes"                    "$CMT_HEAD" "$(many 99)" 0
# A comment left out does not take the row down with it, nor the other way round.
runsum "comment older than the push, row newer: the row passes" \
  "$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1]) + json.loads(sys.argv[2])))' \
     "$(done_cmt "$BOT" "$D1" "${HEAD:0:10}" 2026-09-18T07:00:00Z)" "$ROW_HEAD")" "$PUSHED" 0
runsum "row left out for a commit sharing seven characters, comment's ten are this head's alone: the comment passes" \
  "$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1]) + json.loads(sys.argv[2])))' \
     "$ROW_HEAD" "$CMT_HEAD")" "[$(push "$HEAD" "$T_PUSH" "$TWIN")]" 0

echo "-- the newest push of the head is the latest by time, whatever order the log arrives in (#197)"
# `repos/<r>/activity` is newest first by default and with `direction=desc`,
# oldest first with `direction=asc` (measured 2026-09-18). The step asks for
# `desc`; the judgement does not lean on it: among the pushes whose `after` is
# the head, the latest timestamp is the push, and when one of them has no
# readable timestamp nothing is known about the newest, so neither signal counts.
OLDEST_FIRST="[$(push "$HEAD" "$T_PUSH"),$(push "$OLD" 2026-09-18T07:16:00Z),$(push "$HEAD" 2026-09-18T07:30:00Z)]"
runsum "oldest-first log, head pushed twice, the row between the two pushes: does not count"     "$ROW_HEAD" "$OLDEST_FIRST" 1
runsum "oldest-first log, head pushed twice, the comment between the two pushes: does not count" "$CMT_HEAD" "$OLDEST_FIRST" 1
NO_STAMP="{\"after\":\"$HEAD\"}"
runsum "a push of the head without a timestamp, listed first: the row does not count"      "$ROW_HEAD" "[$NO_STAMP,$(push "$HEAD" "$T_PUSH")]" 1
runsum "a push of the head without a timestamp, listed last: the row does not count"       "$ROW_HEAD" "[$(push "$HEAD" "$T_PUSH"),$NO_STAMP]" 1
runsum "a push of the head without a timestamp, listed first: the comment does not count"  "$CMT_HEAD" "[$NO_STAMP,$(push "$HEAD" "$T_PUSH")]" 1
runsum "a push of the head without a timestamp, listed last: the comment does not count"   "$CMT_HEAD" "[$(push "$HEAD" "$T_PUSH"),$NO_STAMP]" 1
runsum "a push of the head with a null timestamp, listed last: does not count" \
  "$CMT_HEAD" "[$(push "$HEAD" "$T_PUSH"),{\"after\":\"$HEAD\",\"timestamp\":null}]" 1
runsum "a push of the head with a time that is not UTC to the second, listed last: does not count" \
  "$ROW_HEAD" "[$(push "$HEAD" "$T_PUSH"),$(push "$HEAD" 2026-09-18T09:00:00+02:00)]" 1
runsum "oldest-first log, the row after both pushes of the head: passes" \
  "$ROW_HEAD" "[$(push "$HEAD" 2026-09-18T07:00:00Z),$(push "$OLD" 2026-09-18T07:05:00Z),$(push "$HEAD" "$T_PUSH")]" 0
runsum "another commit's push without a timestamp does not get in the way: passes" \
  "$CMT_HEAD" "[$(push "$HEAD" "$T_PUSH"),{\"after\":\"$OLD\",\"before\":\"$OLD\"}]" 0
if grep -vE '^[[:space:]]*#' "$wf" | grep -E 'gh api .*repos/\$REPO/activity' | grep -q -- '-f direction=desc'; then   # comment lines do not count
  echo "  PASS  the step asks for the log newest first"
else
  echo "  FAIL  the activity call does not pass direction=desc; the order is left to the endpoint's default" >&2; fails=$((fails + 1))
fi

echo "-- once decided, the log and the job summary list the reviewer's inline comments on this head (#176)"
# The verdict never depends on this; the count is for the person who merges.
# Inline comments: made on this head, an old one moved onto the head, someone
# else's on this head. Only the first is counted.
rcm_url() {  # author, original_commit_id, url
  printf '{"user":{"login":"%s"},"commit_id":"%s","original_commit_id":"%s","html_url":"%s","body":"P2 ..."}' "$1" "$HEAD" "$2" "$3"
}
report() {  # name, review-comments JSON, pass condition, expected log line, expected url count
  echo '[]' > "$tmp/r.json"; printf '%s' "$2" > "$tmp/rc.json"
  printf '%s' "$(cmt "$BOT" "$HEAD" completed)" > "$tmp/i.json"   # the verdict comes from the marker
  : > "$tmp/summary.md"
  GITHUB_STEP_SUMMARY="$tmp/summary.md" python3 "$attest" "$HEAD" "$BOT" \
    "$tmp/r.json" "$tmp/rc.json" "$tmp/i.json" >"$tmp/log" 2>&1
  got=$?
  urls_log="$(grep -c 'https://' "$tmp/log")"; urls_sum="$(grep -c '^- https://' "$tmp/summary.md")"
  if [ "$got" -ne 0 ] || ! grep -qF "$3" "$tmp/log" || ! grep -qF "$3" "$tmp/summary.md" \
     || [ "$urls_log" -ne "$4" ] || [ "$urls_sum" -ne "$4" ]; then
    echo "  FAIL  $1: exit $got, wanted '$3' with $4 url(s) in log and summary (log $urls_log, summary $urls_sum)" >&2
    sed 's/^/        /' "$tmp/log" "$tmp/summary.md" >&2; fails=$((fails + 1))
  else
    echo "  PASS  $1"
  fi
}
U1=https://github.com/o/r/pull/1#discussion_r1; U2=https://github.com/o/r/pull/1#discussion_r2
report "none: printed as zero, not silence"  '[]' "no inline comments on this head" 0
report "two on this head are counted"        "[$(rcm_url "$BOT" "$HEAD" "$U1"),$(rcm_url "$BOT" "$HEAD" "$U2")]" "reviewer left 2 inline comments" 2
report "one on an older head is not counted" "[$(rcm_url "$BOT" "$HEAD" "$U1"),$(rcm_url "$BOT" "$OLD" "$U2")]" "reviewer left 1 inline comment on" 1
report "someone else's is not counted"       "[$(rcm_url someone "$HEAD" "$U1")]" "no inline comments on this head" 0
if grep -qF "$U1" "$tmp/log"; then
  echo "  FAIL  someone else's comment url leaked into the log" >&2; fails=$((fails + 1))
fi
# A failed or malformed fetch of the comments is not zero comments (#188): the
# line says it could not be read, never the zero line, and the verdict (here
# from the marker) still stands. The step writes `null` when the call fails.
report "fetch failed (null): could not be read"   'null'                     "could not be read" 0
report "an API error object: could not be read"   '{"message":"Not Found"}'  "could not be read" 0
report "not JSON: could not be read"              '<html>'                   "could not be read" 0
for bad in 'null' '{"message":"Not Found"}' '<html>'; do
  printf '%s' "$bad" > "$tmp/rc.json"; echo '[]' > "$tmp/r.json"; printf '%s' "$(cmt "$BOT" "$HEAD" completed)" > "$tmp/i.json"
  if python3 "$attest" "$HEAD" "$BOT" "$tmp/r.json" "$tmp/rc.json" "$tmp/i.json" 2>&1 | grep -q "no inline comments"; then
    echo "  FAIL  unreadable comments ($bad) printed as zero" >&2; fails=$((fails + 1))
  fi
done
rm -f "$tmp/rc.json"; : > "$tmp/summary.md"
if GITHUB_STEP_SUMMARY="$tmp/summary.md" python3 "$attest" "$HEAD" "$BOT" "$tmp/r.json" "$tmp/rc.json" "$tmp/i.json" >"$tmp/log" 2>&1 \
   && grep -q "could not be read" "$tmp/log" && grep -q "could not be read" "$tmp/summary.md" && ! grep -q "no inline comments" "$tmp/summary.md"; then
  echo "  PASS  a missing comments file: could not be read, in the log and the summary; verdict stands"
else
  echo "  FAIL  a missing comments file: expected a pass saying it could not be read in the log and the summary" >&2
  sed 's/^/        /' "$tmp/log" "$tmp/summary.md" >&2; fails=$((fails + 1))
fi
if grep -q "|| echo 'null' > \"\$RUNNER_TEMP/\$2\"" "$wf"; then
  echo "  PASS  the step writes null, not [], when a call fails"
else
  echo "  FAIL  the step's fetch fallback is not null; a failed call would read as an empty list" >&2; fails=$((fails + 1))
fi

# Without a summary file (a local run) the report still prints and the verdict still stands.
echo '[]' > "$tmp/r.json"; printf '%s' "[$(rcm_url "$BOT" "$HEAD" "$U1")]" > "$tmp/rc.json"; echo '[]' > "$tmp/i.json"
if env -u GITHUB_STEP_SUMMARY python3 "$attest" "$HEAD" "$BOT" "$tmp/r.json" "$tmp/rc.json" "$tmp/i.json" >"$tmp/log" 2>&1 \
   && grep -qF "$U1" "$tmp/log"; then
  echo "  PASS  no summary file: the log alone carries the url"
else
  echo "  FAIL  no summary file: expected a pass with the url in the log" >&2; sed 's/^/        /' "$tmp/log" >&2; fails=$((fails + 1))
fi

echo "-- when nothing matches, the log carries the clues (wrong name or commit: fix it in one go)"
printf '%s' "$(cmt "$BOT" "$OLD" completed)" > "$tmp/i.json"
echo '[]' > "$tmp/r.json"; echo '[]' > "$tmp/rc.json"
python3 "$attest" "$HEAD" "$BOT" "$tmp/r.json" "$tmp/rc.json" "$tmp/i.json" >"$tmp/log" 2>&1 || true
# A summary row still running on this head is a clue too (#191).
printf '%s' "$(sum_cmt "$BOT" "$SUM" "$(row "$RUN_ST" "${HEAD:0:7}")")" > "$tmp/i2.json"
python3 "$attest" "$HEAD" "$BOT" "$tmp/r.json" "$tmp/rc.json" "$tmp/i2.json" >>"$tmp/log" 2>&1 || true
for want in "${OLD:0:8}" "codex" "summary row ${HEAD:0:7} status=Running <- this commit"; do
  if grep -qF "$want" "$tmp/log"; then
    echo "  PASS  log names: $want"
  else
    echo "  FAIL  log lacks '$want'; no clue to fix from" >&2; cat "$tmp/log" >&2; fails=$((fails+1))
  fi
done

if [ "$fails" -ne 0 ]; then
  echo "-- $fails failed" >&2
  exit 1
fi
echo "-- blocks only on 'not finished on this commit', never on the verdict"
