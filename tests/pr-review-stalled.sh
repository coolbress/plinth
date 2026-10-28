#!/usr/bin/env bash
# A reviewer that acknowledged the request and never finished (#719).
#
# On #712 and #717 (2026-10-28) and plinth-template#136 (2026-10-27) the
# reviewer put its eyes on the summons within seconds and its summary comment
# went to "Running", and no review came in the full wait. The check failed
# with the words for a reviewer that never came. Now the red says which of
# the two it is: "acknowledged, not finished" with the times read and the
# next steps in order, or today's words when nothing acknowledged the request.
# Neither passes: the check stays red without an accepted review.
#
# The whole second step of pr-review.yml runs here on a clock that only
# `sleep` moves, with `gh` answering from tests/fixtures/pr-review-stalled/:
# the comments, the summary comment's edit history, the reactions, reviews,
# review comments and pushes of those pull requests, as they stood at each
# second. Each run starts when the failed run started and waits 1200 s,
# looking every 300 s and at the two ask points.
# There is no summons-token here: the summonses in the timelines are the ones
# the real runs posted, at the times they posted them.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="$root/.github/workflows/pr-review.yml"
howto="$root/docs/how-to/configure-the-third-party-reviewer.md"
fx="$root/tests/fixtures/pr-review-stalled"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fails=0

python3 - "$wf" "$tmp" <<'PY'
import sys, pathlib, textwrap
lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
start = next(i for i, ln in enumerate(lines) if "name: A third-party review is attached to this commit" in ln)
start = next(i for i in range(start, len(lines)) if lines[i].strip() == "run: |") + 1
end = next((i for i in range(start, len(lines)) if lines[i].strip() and len(lines[i]) - len(lines[i].lstrip()) < 10), len(lines))
pathlib.Path(sys.argv[2], "step.sh").write_text(textwrap.dedent("\n".join(lines[start:end])) + "\n")
PY
[ -s "$tmp/step.sh" ] || { echo "  FAIL  could not extract the step" >&2; exit 1; }
mkdir -p "$tmp/rt/plinth/scripts" && ln -s "$root/scripts/pr-review" "$tmp/rt/plinth/scripts/pr-review"

# gh: the timeline as it stood at the clock's second.
mkdir -p "$tmp/bin"
cat > "$tmp/gh.py" <<'PY'
import json, os, pathlib, subprocess, sys
from datetime import datetime, timezone
m = pathlib.Path(os.environ["MOCK"]); a = sys.argv[1:]
d = json.loads((m / "timeline.json").read_text())
now = datetime.fromtimestamp(int((m / "clock").read_text()), timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
drop = set(os.environ.get("DROP", "").split(",")) - {""}   # logins whose every trace is left out
who = lambda it: (it.get("user") or it.get("actor") or {}).get("login") not in drop
path = next(x for x in a[1:] if not x.startswith("-") and "/" in x)
if path.endswith("/reactions") and os.environ.get("NO_REACTIONS"):
    sys.exit(1)                                                # the reactions call fails
if path.endswith("/activity"):
    out = [p for p in d["pushes"] if p["timestamp"] <= now]
elif "/issues/comments/" in path:
    cid = int(path.split("/")[-2])
    out = [r for r in d["reactions"] if r["on"] == cid and r["created_at"] <= now and who(r)]
elif path.endswith("/reactions"):
    out = [r for r in d["reactions"] if r["on"] == "pr" and r["created_at"] <= now and who(r)]
elif "/issues/" in path and path.endswith("/comments"):
    out = []
    for c in d["comments"]:
        seen = [v for v in c["versions"] if v["at"] <= now]
        if c["created_at"] <= now and seen and who(c):
            out.append({"id": c["id"], "user": c["user"], "created_at": c["created_at"],
                        "updated_at": seen[-1]["at"], "body": seen[-1]["body"]})
elif path.endswith("/reviews"):
    out = [r for r in d["reviews"] if r["submitted_at"] <= now and who(r)]
elif "/pulls/" in path and path.endswith("/comments"):
    out = [r for r in d["rcomments"] if r["created_at"] <= now and who(r)]
else:
    out = []
for r in out:
    r.pop("on", None)
if "--jq" in a:
    sys.stdout.write(subprocess.run(["jq", "-c", a[a.index("--jq") + 1]], input=json.dumps(out),
                                    capture_output=True, text=True, check=True).stdout)
else:
    print(json.dumps(out))
PY
printf '#!/bin/sh\nexec python3 "$MOCK/../gh.py" "$@"\n' > "$tmp/bin/gh"
printf '#!/bin/sh\necho $(( $(cat "$MOCK/clock") + $1 )) > "$MOCK/clock"\n' > "$tmp/bin/sleep"
cat > "$tmp/bin/date" <<'SH'
#!/bin/sh
c="$(cat "$MOCK/clock")"; for f; do :; done
if [ "$f" = "+%s" ]; then echo "$c"; else /bin/date -u -r "$c" "$f" 2>/dev/null || /bin/date -u -d "@$c" "$f"; fi
SH
chmod +x "$tmp/bin/"*
epoch() { python3 -c 'import sys; from datetime import datetime; print(int(datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00")).timestamp()))' "$1"; }

BOT='chatgpt-codex-connector[bot]'
replay() {  # name, fixture, head, run start (UTC), expected exit; DROP: logins left out
  rm -rf "$tmp/m"; mkdir -p "$tmp/m"
  cp "$fx/$2" "$tmp/m/timeline.json"; epoch "$4" > "$tmp/m/clock"
  PATH="$tmp/bin:$PATH" MOCK="$tmp/m" NO_REACTIONS="${NO_REACTIONS:-}" DROP="${DROP:-}" RUNNER_TEMP="$tmp/rt" REPO=o/r NUMBER=7 HEAD_SHA="$3" HEAD_REF=b \
    AUTHOR_LOGIN=coolbress TITLE=t LOGINS="$BOT" ASK="@codex review" SUMMONS_TOKEN="" OWNER=coolbress \
    WAIT=1200 POLL=300 bash "$tmp/step.sh" >"$tmp/out" 2>&1
  got=$?
  if [ "$got" -ne "$5" ]; then
    echo "  FAIL  $1: exit $got, wanted $5" >&2
    grep -v '^\(   \.\.\.\|not yet\|   summary row\|  authors\)' "$tmp/out" | sed 's/^/        /' >&2
    fails=$((fails + 1)); return 1
  fi
  echo "  PASS  $1: exit $got"
}
has() {  # what, text
  if grep -qF -- "$2" "$tmp/out"; then echo "  PASS  $1"; else
    echo "  FAIL  $1: the log lacks '$2'" >&2; tail -12 "$tmp/out" | sed 's/^/        /' >&2; fails=$((fails + 1)); fi
}
lacks() {  # what, text
  if ! grep -qF -- "$2" "$tmp/out"; then echo "  PASS  $1"; else
    echo "  FAIL  $1: the log has '$2'" >&2; fails=$((fails + 1)); fi
}
TODAY="::error::no third-party review is attached to this commit"
ACK="::error::acknowledged, not finished: the reviewer took the request for this commit"

H712=02183290ca748c35d3d5eacc1900e39479f6e726
H717=a47af6c25bc3821de8e369b3eabf725bd85b24c2
H136=6a1d9db21099c94b44440b495c3c5475a00ea98d
H717B=46c042e0aa2b22014581b8c6da4192cc65047bf2

echo "-- acknowledged, not finished: fails, names the state, the times and the steps"
replay "#712, run of 08:55:58" plinth-712.json "$H712" 2026-10-28T08:55:58Z 1 && {
  has "#712: the state" "$ACK ($H712)"
  has "#712: requested, acknowledged, how long" "requested 2026-10-28T09:02:48Z (the summons); acknowledged 2026-10-28T09:03:03Z (eyes reaction on the request); 12 min 55 s ago, read at 2026-10-28T09:15:58Z."
  has "#712: the summary's running state" "also: summary says running for this commit at 2026-10-28T09:03:06Z."
  lacks "#712: not today's words" "$TODAY"
}
cp "$tmp/out" "$tmp/out712"
replay "#717, run of 09:24:33" plinth-717.json "$H717" 2026-10-28T09:24:33Z 1 && {
  has "#717: the state and times" "requested 2026-10-28T09:31:27Z (the summons); acknowledged 2026-10-28T09:31:41Z (eyes reaction on the request)"
  has "#717: the summary's running state" "also: summary says running for this commit at 2026-10-28T09:31:44Z."
}
replay "plinth-template#136, run of 16:19:05" plinth-template-136.json "$H136" 2026-10-27T16:19:05Z 1 && {
  has "#136: the state and times" "requested 2026-10-27T16:25:56Z (the summons); acknowledged 2026-10-27T16:26:12Z (eyes reaction on the request)"
  has "#136: the summary's running state" "also: summary says running for this commit at 2026-10-27T16:26:13Z."
}
# The re-run of 16:40:04 on the same commit: its own summons at 16:53:41 is the
# one reported, not the first run's.
replay "plinth-template#136, re-run of 16:40:04" plinth-template-136.json "$H136" 2026-10-27T16:40:04Z 1 && {
  has "#136 re-run: the newer request" "requested 2026-10-27T16:53:41Z (the summons); acknowledged 2026-10-27T16:53:55Z (eyes reaction on the request)"
}
# Only the summary can tell when the reactions cannot be read.
NO_REACTIONS=1 replay "#712, the reactions calls fail: the summary alone" plinth-712.json "$H712" 2026-10-28T08:55:58Z 1 && {
  has "#712: acknowledged by the summary" "requested 2026-10-28T09:02:48Z (the summons); acknowledged 2026-10-28T09:03:06Z (summary says running for this commit)"
}

echo "-- nothing acknowledged the request: today's words, unchanged"
DROP="$BOT" replay "#712 with every trace of the reviewer left out" plinth-712.json "$H712" 2026-10-28T08:55:58Z 1 && {
  has "today's error" "$TODAY ($H712)."
  has "today's first hint" "is the reviewer's automatic review on for this repository?"
  has "today's summons hint" "comment '@codex review' on the pull request yourself and re-run this job"
  lacks "not the acknowledged state" "acknowledged, not finished"
}

echo "-- the review lands inside the wait: passes"
replay "#717 head 46c042e, run of 10:28:53" plinth-717.json "$H717B" 2026-10-28T10:28:53Z 0 && {
  has "the review is the signal" "third party looked at this commit: review (COMMENTED)"
  lacks "no red" "::error::"
}

echo "-- what counts as an acknowledgement: attest.py --stalled on its own"
H=71a704cdca35f00de6e110a3d77a165d895d882a
O=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
printf '[{"after":"%s","before":"%s","timestamp":"2026-09-18T10:20:00Z"}]' "$H" "$O" > "$tmp/act.json"
printf '[]' > "$tmp/empty.json"
REQ="{\"id\":11,\"user\":{\"login\":\"coolbress\"},\"created_at\":\"2026-09-18T10:27:00Z\",\"body\":\"@codex review\\n\\n<!-- third-party-review: $H -->\"}"
summary() {  # commit, status
  printf '{"id":12,"user":{"login":"%s"},"created_at":"2026-09-18T10:27:05Z","updated_at":"2026-09-18T10:27:09Z","body":"<!-- codex-pull-request-review-summary -->\\n<!-- codex-review-state:v1 {\\"code_review\\":{\\"commit_sha\\":\\"%s\\",\\"status\\":\\"%s\\"}} -->"}' "$BOT" "$1" "$2"
}
eyes() {  # login, on (a comment id or null), created_at
  printf '{"user":{"login":"%s"},"content":"eyes","created_at":"%s","comment_id":%s}' "$1" "$3" "$2"
}
stalled() {  # name, issue comments, reactions, expected exit, expected text ('' = none)
  printf '%s' "$2" > "$tmp/ic.json"; printf '%s' "$3" > "$tmp/re.json"
  ASK="@codex review" python3 "$root/scripts/pr-review/attest.py" --stalled "$H" "$BOT" "$tmp/empty.json" "$tmp/empty.json" \
    "$tmp/ic.json" "$tmp/act.json" "$tmp/re.json" 2026-09-18T10:40:00Z > "$tmp/out" 2>&1
  got=$?
  if [ "$got" -ne "$4" ] || { [ -n "$5" ] && ! grep -qF -- "$5" "$tmp/out"; }; then
    echo "  FAIL  $1: exit $got (wanted $4), log lacks '$5'" >&2; sed 's/^/        /' "$tmp/out" >&2; fails=$((fails + 1))
  else
    echo "  PASS  $1"
  fi
}
stalled "eyes on the request"                       "[$REQ]" "[$(eyes "$BOT" 11 2026-09-18T10:27:03Z)]" 0 "requested 2026-09-18T10:27:00Z (the summons); acknowledged 2026-09-18T10:27:03Z (eyes reaction on the request); 12 min 57 s ago"
stalled "eyes on the pull request after the push"   "[]" "[$(eyes "$BOT" null 2026-09-18T10:21:00Z)]" 0 "requested 2026-09-18T10:20:00Z (the push, the reviewer's own trigger); acknowledged 2026-09-18T10:21:00Z (eyes reaction on the pull request)"
stalled "the summary running on this commit"        "[$REQ,$(summary "$H" running)]" "null" 0 "acknowledged 2026-09-18T10:27:09Z (summary says running for this commit)"
stalled "eyes from another account"                 "[$REQ]" "[$(eyes coolbress 11 2026-09-18T10:27:03Z)]" 1 ""
stalled "eyes on the pull request before the push"  "[]" "[$(eyes "$BOT" null 2026-09-18T10:19:00Z)]" 1 ""
stalled "eyes on a comment that is no request"      "[]" "[$(eyes "$BOT" 99 2026-09-18T10:27:03Z)]" 1 ""
stalled "the summary running on another commit"     "[$REQ,$(summary "$O" running)]" "[]" 1 ""
stalled "the summary completed on this commit"      "[$REQ,$(summary "$H" completed)]" "[]" 1 ""
stalled "nothing read at all"                       "null" "null" 1 ""
LIMIT="{\"user\":{\"login\":\"$BOT\"},\"created_at\":\"2026-09-18T10:27:30Z\",\"body\":\"You have reached your Codex usage limits for code reviews.\"}"
stalled "eyes, then a usage-limit notice: the known cause stands" "[$REQ,$LIMIT]" "[$(eyes "$BOT" 11 2026-09-18T10:27:03Z)]" 1 ""

echo "-- the how-to says the same steps in the same words as the log"
# The log of the #712 replay above: the phrase, and each numbered step after
# "Next, in this order:". The how-to must carry each, word for word.
python3 - "$howto" "$tmp/out712" <<'PY' || fails=$((fails + 1))
import pathlib, re, sys
flat = lambda t: " ".join(t.split()).replace("`", "")
howto = flat(pathlib.Path(sys.argv[1]).read_text())
log = pathlib.Path(sys.argv[2]).read_text().splitlines()
at = next((i for i, ln in enumerate(log) if "Next, in this order:" in ln), len(log))
steps = [ln.strip() for ln in log[at:] if re.match(r"\s+\d\. ", ln)]
bad = [] if "acknowledged, not finished" in howto else ["the phrase 'acknowledged, not finished'"]
bad += [repr(s) for s in steps if flat(s) not in howto]
if len(steps) < 3:
    bad.append(f"the log has {len(steps)} numbered steps, wanted 3")
if bad:
    print("  FAIL  the how-to does not carry the log's words: " + "; ".join(bad), file=sys.stderr)
    sys.exit(1)
print(f"  PASS  the how-to carries the phrase and all {len(steps)} steps of the log, word for word")
PY

if [ "$fails" -ne 0 ]; then
  echo "-- $fails failed" >&2
  exit 1
fi
