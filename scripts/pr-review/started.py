#!/usr/bin/env python3
# The ask test of .github/workflows/pr-review.yml (#206, #215):
# started.py <head> <logins> <issue-comments> <activity> [<first ask point>].
# Exit 0 when not to ask (this head replaced, or an accepted reviewer active
# since then), 1 when to ask; it prints why. tests/pr-review-summon.sh runs
# this file.
"""Has this head been replaced by a newer push, or has an accepted
reviewer shown life on this pull request since the newest push of the
head, and since `since` when it is given?

Loose on purpose: a request that lands while a review of the head is
running is folded into it (measured on #207, #205), so asking once
too often costs nothing seen, and not asking fails a pull request
nobody reviewed. So any issue comment of an accepted login created or
updated after that time counts, whatever it says: Codex's summary
comment and CodeRabbit's are created when a review starts. Reviews
and review comments on the head are not read here: they pass the
check before it asks. Where the push cannot be read, nothing counts
as started at the first ask point.
"""
import json
import pathlib
import re
import sys

head, logins_csv, icomments_p, activity_p = sys.argv[1:5]
since = sys.argv[5] if len(sys.argv) > 5 else ""   # the first ask point, at the second
logins = {x.strip().lower() for x in logins_csv.split(",") if x.strip()}
#: GitHub's times and the step's, UTC to the second: they compare as text.
STAMP = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")

def load(p):
    try:
        d = json.loads(pathlib.Path(p).read_text() or "[]")
    except (OSError, json.JSONDecodeError):
        return []
    return d if isinstance(d, list) else []

# Replaced (#215): the reviewer reviews the pull request's current head,
# so a request from this run would serve the newer commit and be
# counted as this one's. Only a log that confirms it: short of a full
# page, this head's push in it, every entry stamped, and every push
# at the latest second naming a commit, none of them this head. The
# order is not read (#197). A tie with this head, or anything
# unreadable, confirms nothing.
log = load(activity_p)
if (0 < len(log) < 100 and any(isinstance(p, dict) and p.get("after") == head for p in log)
        and all(isinstance(p, dict) and STAMP.match(str(p.get("timestamp") or "")) for p in log)):
    latest = max(p["timestamp"] for p in log)
    newest = sorted({str(p.get("after") or "") for p in log if p["timestamp"] == latest})
    if head not in newest and all(newest):
        print(f"this head is no longer the branch's newest push ({', '.join(newest)})")
        sys.exit(0)

# The newest push of the head, read as attest.py reads it (#197).
pushes = [p for p in log if isinstance(p, dict)]
if len(pushes) >= 100:   # a full page: older pushes may be missing
    pushes = []
stamps = [str(p.get("timestamp") or "") for p in pushes if p.get("after") == head]
pushed = max(stamps) if stamps and all(STAMP.match(t) for t in stamps) else ""
# The first ask point is the step's own clock, so the second ask can
# be tested without the push: a review the first ask started, whose
# comments the check cannot count without the push, is then not
# asked for a second time (a whole second review, #205).
if not pushed and not since:
    print("the push of this head could not be read, or the log is a full page: nothing counts as started")
    sys.exit(1)
after, what = (since, f"the first ask point ({since})") if since > pushed else (pushed, f"the push ({pushed})")

for it in load(icomments_p):
    if not isinstance(it, dict):
        continue
    who = (it.get("user") or {}).get("login") or ""
    times = [str(it.get(k) or "") for k in ("created_at", "updated_at")]
    times = [t for t in times if STAMP.match(t)]
    if who.lower() in logins and times and max(times) > after:
        print(f"reviewer active since {what}: {who}, comment updated {max(times)}")
        sys.exit(0)
print(f"nothing from an accepted reviewer since {what}")
sys.exit(1)
