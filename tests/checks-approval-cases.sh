#!/usr/bin/env bash
# Verdicts of the `ci / diff-size` step that asks an admin to approve a change
# to the checks (#586), against a fake `gh` that answers from fixtures. The
# steps are extracted from python-ci.yml, so the rule tested is the rule
# shipped; the list it reads comes from the step before it, run for real in
# the last section.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="$root/.github/workflows/python-ci.yml"
ask="Ask an admin to approve a change to the checks"
names="Name changes to the checks the description does not"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/approval.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

extract() {  # <step name> <out file>: the step's `run: |` block, dedented
  python3 - "$wf" "$1" > "$2" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
at = next((i for i, l in enumerate(lines) if l.strip() == f"- name: {sys.argv[2]}"), None)
if at is None:
    sys.exit(f"step not found: {sys.argv[2]}")
i = next(j for j in range(at, len(lines)) if lines[j].strip() == "run: |")
indent = None
for l in lines[i + 1:]:
    if l.strip() and indent is None:
        indent = len(l) - len(l.lstrip())
    if l.strip() and len(l) - len(l.lstrip()) < indent:
        break
    print(l[indent:] if l.strip() else "")
PY
  [ -s "$2" ] || { echo "  FAIL  step '$1' not found in python-ci.yml"; exit 1; }
}
extract "$ask" "$tmp/ask.py"
extract "$names" "$tmp/names.py"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        | /'; }

# The fake gh: `gh api [args] <path>` answers <dir>/<path without query, / as _>.json,
# or fails with the text of .err; every call is logged with its full path.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
d = os.environ["FAKE_GH"]
args = sys.argv[1:]
path = next(a for a in reversed(args) if not a.startswith("-") and a not in (".[] | tojson", "POST"))
with open(os.path.join(d, "calls"), "a") as f:
    f.write(("POST " if "POST" in args else "GET ") + path + "\n")
key = os.path.join(d, path.split("?", 1)[0].replace("/", "_"))
if os.path.exists(key + ".err"):
    sys.stderr.write(open(key + ".err").read()); sys.exit(1)
if not os.path.exists(key + ".json"):
    sys.stderr.write("gh: Not Found (HTTP 404)\n"); sys.exit(1)
data = json.load(open(key + ".json"))
if "--jq" in args:
    for item in data:
        print(json.dumps(item))
else:
    print(json.dumps(data))
PY
chmod +x "$tmp/bin/gh"

H=1111111111111111111111111111111111111111   # the head
OLD=2222222222222222222222222222222222222222
R=o/r
api() { printf '%s\n' "$2" > "$fx/$(printf '%s' "$1" | tr / _).json"; }
apierr() { printf '%s\n' "$2" > "$fx/$(printf '%s' "$1" | tr / _).err"; }

# fresh: a new fixture set; a Write account pushed the head, nobody reviewed,
# one listed change. Each case overrides what it needs.
fresh() {
  fx="$tmp/fx$((pass+fail))"; rm -rf "$fx"; mkdir -p "$fx"
  printf '[{"path": "tests/test_b.py", "why": "a test file deleted"}]\n' > "$fx/changes.json"
  pushed_by agent 270045750
  api "repos/$R/collaborators/agent/permission" '{"permission": "write"}'
  api "repos/$R/collaborators/boss/permission" '{"permission": "admin"}'
  api "repos/$R/pulls/7/reviews" '[]'
  EVENT=pull_request; HEAD_REPO=$R; NUMBER=7
}
pushed_by() {
  api "repos/$R/activity" "[{\"after\": \"$OLD\", \"actor\": {\"login\": \"boss\", \"id\": 1}}, {\"after\": \"$H\", \"actor\": {\"login\": \"$1\", \"id\": $2}}]"
}
review() {  # <id> <login> <state> <commit>
  python3 - "$fx/repos_o_r_pulls_7_reviews.json" "$@" <<'PY'
import json, sys
f, i, login, state, commit = sys.argv[1:]
d = json.load(open(f)); d.append({"id": int(i), "user": {"login": login}, "state": state, "commit_id": commit})
json.dump(d, open(f, "w"))
PY
}

# run: the step on the fixtures; sets $out, $rc, $sum (the summary) and $calls.
run() {
  : > "$fx/calls"; : > "$fx/summary"
  out="$(PATH="$tmp/bin:$PATH" FAKE_GH="$fx" EVENT="$EVENT" REPO=$R RUN_ID=99 NUMBER="$NUMBER" \
    HEAD_SHA=$H HEAD_REF=agent/x HEAD_REPO="$HEAD_REPO" CHANGES_FILE="$fx/changes.json" \
    GITHUB_STEP_SUMMARY="$fx/summary" python3 "$tmp/ask.py" 2>&1)"; rc=$?
  sum="$(cat "$fx/summary")"; calls="$(cat "$fx/calls")"
}
# expect <label> <exit code> <regex the summary's verdict line matches, or "none">
expect() {
  if [ "$rc" != "$2" ]; then bad "$1 (exit $rc, expected $2)" "$out"; return; fi
  if [ "$3" = none ]; then
    if grep -qE '^- (pass|fail|not yet confirmed):' <<<"$sum"; then bad "$1 (a verdict line where none was expected)" "$sum"; return; fi
  elif ! grep -qE -- "$3" <<<"$sum"; then bad "$1 (no summary line matches $3)" "$sum$(printf '\n--- log\n')$out"; return; fi
  ok "$1"
}
called()    { grep -qF -- "$2" <<<"$calls" && ok "  $1" || bad "  $1" "$calls"; }
notcalled() { grep -qF -- "$2" <<<"$calls" && bad "  $1" "$calls" || ok "  $1"; }

echo "ci / diff-size: an admin's approval of a change to the checks"

echo "-- nothing to ask"
fresh; printf '[]\n' > "$fx/changes.json"; run
expect "no row of the six kinds: no line, green" 0 none
[ -z "$calls" ] && ok "  and nothing is read" || bad "  something was read" "$calls"
fresh; NUMBER=""; run
expect "not a pull request: no line, green" 0 none
fresh; rm "$fx/changes.json"; run
expect "the list is missing (its step did not finish): fail, re-running may clear it" 1 \
  "^- fail: changes to the checks, the step that lists them did not finish.*re-running the job may clear it$"

echo "-- a head a non-admin pushed"
fresh; run
expect "no approval: fail, naming the row, the way to approve and the person's way" 1 \
  "^- fail: changes to the checks, this pull request changes how strict the checks are \(tests/test_b.py: a test file deleted\) and agent pushed it and is not an admin, so it needs an admin's approval on this head \(111111111111\); it has none\. If you agree with the change, approve the pull request on GitHub: Files changed, Review changes, Approve\. The approval re-runs the latest red run; if this check does not turn green, use \"Re-run failed jobs\" on the latest red ci / diff-size\.$"
grep -q '^::error::fail: changes to the checks' <<<"$out" && ok "  and it is an error annotation" || bad "  no error annotation" "$out"
called "the pusher is read from the branch's activity, by the head's ref" "GET repos/o/r/activity?ref=refs/heads/agent/x&"
fresh; review 1 boss APPROVED $H; run
expect "an admin's approval on the head: pass, with the approver and the head" 0 \
  "^- pass: changes to the checks, approved by boss, an admin, on this head \(111111111111\)$"
notcalled "a pull_request run re-runs nothing" "actions/"
fresh; review 1 boss APPROVED $OLD; run
expect "an admin's approval on an earlier head: fail" 1 "^- fail: changes to the checks, .*it has none"
fresh; review 1 agent APPROVED $H; run
expect "a Write account's approval on the head: fail" 1 "^- fail: changes to the checks, .*it has none"
fresh; review 1 boss APPROVED $H; review 2 boss DISMISSED $H; run
expect "an admin's approval, then dismissed: fail" 1 "^- fail: changes to the checks, .*it has none"
fresh; review 1 boss APPROVED $H; review 2 boss CHANGES_REQUESTED $H; run
expect "an admin's approval, then changes requested: fail" 1 "^- fail: changes to the checks, .*it has none"
fresh; review 1 boss APPROVED $H; review 2 boss COMMENTED $H; run
expect "an admin's approval, then a comment: still a pass" 0 "^- pass: changes to the checks, approved by boss"
fresh; printf '[%s]\n' "$(for i in 1 2 3 4 5 6 7; do printf '{"path": "tests/t%s.py", "why": "a test file deleted"},' "$i"; done | sed 's/,$//')" > "$fx/changes.json"; run
expect "seven rows: five named, the rest counted" 1 "tests/t5.py: a test file deleted; and 2 more in the table above\) and agent pushed it"

echo "-- what cannot be read fails, with the way out"
fresh; apierr "repos/$R/activity" "gh: Server Error (HTTP 502)"; run
expect "the activity unreadable: fail, re-running may clear it" 1 \
  "^- fail: changes to the checks, .*could not be read \(repos/o/r/activity: gh: Server Error \(HTTP 502\)\); re-running the job may clear it$"
fresh; api "repos/$R/activity" "[{\"after\": \"$OLD\", \"actor\": {\"login\": \"boss\", \"id\": 1}}]"; run
expect "no push of the head in the activity: fail" 1 "could not be read \(no push of this head in the branch's activity\); re-running the job may clear it$"
fresh; apierr "repos/$R/collaborators/agent/permission" "gh: Server Error (HTTP 500)"; run
expect "the pusher's permission unreadable: fail" 1 "could not be read \(repos/o/r/collaborators/agent/permission: .*re-running the job may clear it$"
fresh; apierr "repos/$R/pulls/7/reviews" "gh: Resource not accessible by integration (HTTP 403)"; run
expect "the reviews unreadable: fail" 1 "could not be read \(repos/o/r/pulls/7/reviews: .*re-running the job may clear it$"
fresh; review 1 boss APPROVED $H; apierr "repos/$R/collaborators/boss/permission" "gh: Server Error (HTTP 500)"; run
expect "the approver's permission unreadable: fail" 1 "could not be read \(repos/o/r/collaborators/boss/permission: "

echo "-- a head an admin pushed (one account for both)"
fresh; pushed_by boss 1; run
expect "an admin pushed it: green, one not yet confirmed line" 0 \
  "^- not yet confirmed: changes to the checks, boss, an admin, pushed this head \(111111111111\), so no approval is asked; .*the person's decision; reading the table before merging confirms it$"
[ "$(grep -c '^- ' <<<"$sum")" = 1 ] && ok "  and only that line" || bad "  more than one line" "$sum"
grep -q '^::warning::not yet confirmed: changes to the checks' <<<"$out" && ok "  and it is a warning annotation" || bad "  no warning annotation" "$out"
notcalled "  and the reviews are not read" "pulls/7/reviews"

echo "-- Dependabot, by its account id"
fresh; pushed_by 'dependabot[bot]' 49699333; run
expect "account id 49699333 pushed it: green, a not yet confirmed line naming Dependabot" 0 \
  "^- not yet confirmed: changes to the checks, Dependabot pushed this head \(111111111111\), so no approval is asked;"
notcalled "  and no permission is read" "collaborators"
fresh; pushed_by 'dependabot[bot]' 12345; run
expect "the login dependabot[bot] with another id: not Dependabot, an approval is asked" 1 "^- fail: changes to the checks, .*dependabot\[bot\] pushed it and is not an admin"
fresh; pushed_by 'some-app[bot]' 777; run
expect "an app's bot account (no collaborator, 404): an approval is asked" 1 "^- fail: changes to the checks, .*some-app\[bot\] pushed it and is not an admin"

echo "-- a fork's pull request"
fresh; HEAD_REPO=someone/r; run
expect "from a fork, no approval: fail, saying it comes from a fork" 1 "^- fail: changes to the checks, .* and it comes from a fork, so it needs an admin's approval"
notcalled "  and no pusher is read" "activity"
fresh; HEAD_REPO=""; run
expect "a deleted fork (no head repository): fail" 1 "it comes from a fork"
fresh; HEAD_REPO=someone/r; review 1 boss APPROVED $H; run
expect "from a fork, an admin's approval on the head: pass" 0 "^- pass: changes to the checks, approved by boss"

echo "-- the approval's own run re-runs the latest red run"
runs() { api "repos/$R/actions/runs/99" '{"workflow_id": 5}'; api "repos/$R/actions/workflows/5/runs" "{\"workflow_runs\": [$1]}"; }
r_() { printf '{"id": %s, "created_at": "%s", "status": "%s", "conclusion": %s}' "$1" "$2" "$3" "$4"; }
fresh; EVENT=pull_request_review; review 1 boss APPROVED $H
runs "$(r_ 41 2026-10-18T10:00:00Z completed '"failure"'), $(r_ 43 2026-10-18T10:05:00Z completed '"failure"'), $(r_ 42 2026-10-18T10:02:00Z completed '"failure"')"
api "repos/$R/actions/runs/43/rerun-failed-jobs" '{}'
run
expect "approved: pass" 0 "^- pass: changes to the checks, approved by boss"
called "the runs read are this workflow's pull_request runs of the head" "GET repos/o/r/actions/workflows/5/runs?head_sha=$H&event=pull_request"
called "the latest red run is re-run" "POST repos/o/r/actions/runs/43/rerun-failed-jobs"
[ "$(grep -c rerun <<<"$calls")" = 1 ] && ok "  and only that one" || bad "  more than one re-run" "$calls"
grep -q 're-ran the failed jobs of the latest red run of this head (43)' <<<"$sum" && ok "  and the summary says so" || bad "  the summary does not say so" "$sum"
fresh; EVENT=pull_request_review; review 1 boss APPROVED $H
runs "$(r_ 41 2026-10-18T10:00:00Z completed '"failure"')"
apierr "repos/$R/actions/runs/41/rerun-failed-jobs" "gh: Resource not accessible by integration (HTTP 403)"
run
expect "the re-run refused (a fork's read-only token): still a pass" 0 "^- pass: changes to the checks, approved by boss"
grep -q '^::notice::The approval could not re-run the latest red run (.*HTTP 403.*). Use "Re-run failed jobs" on the latest red ci / diff-size.$' <<<"$out" \
  && grep -q 'Use "Re-run failed jobs" on the latest red ci / diff-size' <<<"$sum" && ok "  and the log and summary give the person's way" || bad "  the person's way is missing" "$out"
fresh; EVENT=pull_request_review; review 1 boss APPROVED $H; apierr "repos/$R/actions/runs/99" "gh: Server Error (HTTP 500)"; run
expect "the runs unreadable: still a pass" 0 "^- pass: changes to the checks, approved by boss"
grep -q 'Use "Re-run failed jobs"' <<<"$sum" && ok "  with the person's way" || bad "  without the person's way" "$sum"
fresh; EVENT=pull_request_review; review 1 boss APPROVED $H
runs "$(r_ 41 2026-10-18T10:00:00Z completed '"failure"'), $(r_ 44 2026-10-18T10:09:00Z completed '"success"')"; run
expect "the latest run passed: nothing re-run" 0 "^- pass: changes to the checks"
notcalled "  no re-run" "rerun"
fresh; EVENT=pull_request_review; review 1 boss APPROVED $H
runs "$(r_ 41 2026-10-18T10:00:00Z completed '"failure"'), $(r_ 45 2026-10-18T10:09:00Z in_progress null)"; run
expect "the latest run still running: nothing re-run" 0 "^- pass: changes to the checks"
notcalled "  no re-run" "rerun"
grep -q 'was still running; once it finishes, if its ci / diff-size is red). Use "Re-run failed jobs"' <<<"$sum" \
  && ok "  and the summary gives the person's way for when it finishes" || bad "  no way given while it runs" "$sum"
fresh; EVENT=pull_request_review; run
expect "a review run with no approval on the head: fail, nothing re-run" 1 "^- fail: changes to the checks"
notcalled "  no re-run" "actions/"
fresh; EVENT=pull_request_review; pushed_by boss 1; run
expect "a review run on an admin's head: the line, nothing re-run" 0 "^- not yet confirmed: changes to the checks, boss, an admin"
notcalled "  no re-run" "actions/"

echo "-- the list the step reads: the six kinds, the workflow kind left out"
lists() {  # <label> <expected JSON paths, space separated>
  r="$tmp/repo$((pass+fail))"; rm -rf "$r"; mkdir -p "$r/tests" "$r/.github/workflows"
  git -C "$r" init -q -b main; git -C "$r" config user.email t@example.com; git -C "$r" config user.name t; git -C "$r" config commit.gpgsign false
  printf 'def test_a():\n    assert 1\n' > "$r/tests/test_a.py"; printf 'def test_b():\n    assert 1\n' > "$r/tests/test_b.py"
  printf 'on: push\n' > "$r/.github/workflows/ci.yml"; printf 'x = 1\n' > "$r/m.py"
  git -C "$r" add -A; git -C "$r" commit -qm base; b="$(git -C "$r" rev-parse HEAD)"
  (cd "$r" && eval "$2"); git -C "$r" add -A; git -C "$r" commit -qm change
  (cd "$r" && BASE_SHA="$b" HEAD_SHA="$(git rev-parse HEAD)" BODY="Names tests/test_b.py and ci.yml." CHANGES_FILE="$r.json" \
    GITHUB_STEP_SUMMARY=/dev/null python3 "$tmp/names.py" >/dev/null 2>&1) || { bad "$1 (the listing step failed)"; return; }
  got="$(python3 -c 'import json,sys; print(" ".join(r["path"] for r in json.load(open(sys.argv[1]))))' "$r.json")"
  [ "$got" = "$3" ] && ok "$1" || bad "$1 (listed '$got', expected '$3')"
}
lists "a workflow edited only: an empty list" "printf 'on: [push]\n' > .github/workflows/ci.yml" ""
lists "a test deleted, named in the description: listed anyway" "git rm -q tests/test_b.py" "tests/test_b.py"
lists "a test deleted and a workflow edited: the test only" "git rm -q tests/test_b.py; printf 'on: [push]\n' > .github/workflows/ci.yml" "tests/test_b.py"
lists "a marker added: listed" "printf 'x = 1  # noqa\n' > m.py" "m.py"
lists "source edited only: an empty list" "printf 'x = 2\n' > m.py" ""

echo "-- the job asks for its permissions"
python3 - "$wf" <<'PY' && ok "diff-size declares contents: read, pull-requests: read and actions: write at job level" || bad "diff-size's job-level permissions"
import re, sys
job = open(sys.argv[1]).read().split("\n  diff-size:\n", 1)[1].split("\n    steps:", 1)[0]
perms = dict(re.findall(r"^      ([a-z-]+): (\w+)", job, re.M))
sys.exit(0 if perms == {"contents": "read", "pull-requests": "read", "actions": "write"} else 1)
PY
python3 - "$root/.github/workflows/ci.yml" <<'PY' && ok "plinth's canary grants them" || bad "plinth's canary does not grant pull-requests: read and actions: write"
import re, sys
job = open(sys.argv[1]).read().split("\n  canary:\n", 1)[1].split("\n    with:", 1)[0]
perms = dict(re.findall(r"^      ([a-z-]+): (\w+)", job, re.M))
sys.exit(0 if perms.get("pull-requests") == "read" and perms.get("actions") == "write" else 1)
PY

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
