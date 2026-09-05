#!/usr/bin/env bash
# What the third-party review check blocks, and what it must not block.
#
# The judgement is a Python snippet inside the `run:` of pr-review.yml. Left
# there alone nobody runs it: the first run is the test, and by then a pull
# request is already red. So it is extracted here and run against fixtures.
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

python3 - "$wf" "$tmp/attest.py" <<'PY'
import sys, pathlib, textwrap
lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
start = next(i for i, ln in enumerate(lines) if ln.rstrip().endswith("<<'PY'"))
end = next(i for i in range(start + 1, len(lines)) if lines[i].strip() == "PY")
body = textwrap.dedent("\n".join(lines[start + 1:end]))
assert "codex-security-review" in body and "REVIEWED" in body, "judgement snippet not found; the workflow changed shape"
pathlib.Path(sys.argv[2]).write_text(body + "\n")
PY
[ -s "$tmp/attest.py" ] || { echo "  FAIL  could not extract the judgement snippet" >&2; exit 1; }

HEAD=71a704cdca35f00de6e110a3d77a165d895d882a
OLD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
BOT='chatgpt-codex-connector[bot]'

# The completion comment that arrives when nothing was found; wording as
# measured. The comment names the commit itself: `**Reviewed commit:** \`db8c8772fd\``.
done_cmt() {  # author, text, [commit named]
  # shellcheck disable=SC2016  # single quotes are right: Python code, not shell expansion
  python3 -c 'import json,sys
who, text = sys.argv[1:3]
sha = sys.argv[3] if len(sys.argv) > 3 else ""
body = text + ("\n\n**Reviewed commit:** `" + sha + "`" if sha else "")
print(json.dumps([{"user": {"login": who}, "created_at": "2026-09-01T06:08:51Z",
                   "body": body}], ensure_ascii=False))' "$1" "$2" "${3:-}"
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
run() {  # name, issue-comments JSON, expected exit, [reviews JSON]
  printf '%s' "$2" > "$tmp/i.json"
  printf '%s' "${4:-[]}" > "$tmp/r.json"
  echo '[]' > "$tmp/rc.json"
  python3 "$tmp/attest.py" "$HEAD" "$BOT" \
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
  python3 "$tmp/attest.py" "$HEAD" "$BOT" "$tmp/r.json" "$tmp/rc.json" "$tmp/i.json" >"$tmp/log" 2>&1
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

echo "-- completion comment signal (measured: zero findings create no review object)"
D1="Codex Review: Didn't find any major issues. Keep it up!"   # wording as measured
D2="Security review completed. No security issues were found in this pull request."
run "completion comment names this commit"          "$(done_cmt "$BOT" "$D1" "${HEAD:0:10}")" 0
run "security review completion counts too"         "$(done_cmt "$BOT" "$D2" "$HEAD")" 0
run "completion naming another commit does not count" "$(done_cmt "$BOT" "$D1" "${OLD:0:10}")" 1
run "completion naming no commit does not count"    "$(done_cmt "$BOT" "$D1")" 1
run "the same wording from someone else does not count" "$(done_cmt someone "$D1" "$HEAD")" 1
# The reviewer's P1 scenario, head moved back to an older commit: bound by
# commit, there is no time heuristic at all, and the old completion simply does not match.

echo "-- when nothing matches, the log carries the clues (wrong name or commit: fix it in one go)"
printf '%s' "$(cmt "$BOT" "$OLD" completed)" > "$tmp/i.json"
echo '[]' > "$tmp/r.json"; echo '[]' > "$tmp/rc.json"
python3 "$tmp/attest.py" "$HEAD" "$BOT" "$tmp/r.json" "$tmp/rc.json" "$tmp/i.json" >"$tmp/log" 2>&1 || true
for want in "${OLD:0:8}" "codex"; do
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
