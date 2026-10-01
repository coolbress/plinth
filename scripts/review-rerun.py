#!/usr/bin/env python3
# The decision of .github/workflows/review-rerun.yml (#363), a pure function
# of files it fetched for one open pull request:
# review-rerun.py <logins> <runs> <reviews> <issue-comments> <reactions>.
# Exit 0 with `re-run <id>: <why>` when the failed run is to be asked again,
# 1 with why not. tests/pr-review-rerun.sh runs this file against fixtures.
"""Has an accepted reviewer done something on this pull request since
`third-party / review` gave up on its head?

The check waits `wait-seconds` and fails. A review with findings is a
`pull_request_review` event and starts the check again by itself; a
zero-finding verdict is often a `+1` reaction on the pull request alone
(measured on #362), and a reaction starts no workflow. So the check
stays red although the reviewer has answered. This asks it again; the
re-run decides, with attest.py's binding rules. Loose on purpose, as
started.py is: any review, issue comment (created or edited) or
reaction of an accepted login newer than the end of the failed
attempt counts, because a re-run that finds nothing only fails again.

Bounded twice. A signal counts only when it is newer than the end of
the newest attempt, so a re-run that fails again needs another new
signal: once per signal. And never past attempt MAX_ATTEMPTS, manual
re-runs included: past that, a person decides, as today.

Only the newest run of the workflow on the head is read: a newer run
that passed, or one still going, settles it. Anything unreadable (a
failed call, a time that is not GitHub's shape) reads as no re-run, so
the failure is the one a person sees today.
"""
import json
import pathlib
import re
import sys

MAX_ATTEMPTS = 3

logins_csv, runs_p, reviews_p, icomments_p, reactions_p = sys.argv[1:6]
logins = {x.strip().lower() for x in logins_csv.split(",") if x.strip()}
#: GitHub's times, UTC to the second: they compare as text.
STAMP = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")

def load(p):
    try:
        d = json.loads(pathlib.Path(p).read_text() or "[]")
    except (OSError, json.JSONDecodeError):
        return []
    return [x for x in d if isinstance(x, dict)] if isinstance(d, list) else []

def skip(why):
    print(f"no re-run: {why}")
    sys.exit(1)

runs = [r for r in load(runs_p) if isinstance(r.get("id"), int)]
if not runs:
    skip("no run of the review workflow on this head could be read")
run = max(runs, key=lambda r: r["id"])   # ids grow; the order listed is not read
rid, attempt = run["id"], run.get("run_attempt") or 1
if run.get("status") != "completed":
    skip(f"run {rid} is {run.get('status')}")
if run.get("conclusion") != "failure":
    skip(f"run {rid} ended {run.get('conclusion')}")
end = str(run.get("updated_at") or "")
if not STAMP.match(end):
    skip(f"run {rid}: its end time cannot be read ({end or 'none'})")
if attempt >= MAX_ATTEMPTS:
    skip(f"run {rid} failed on attempt {attempt} of {MAX_ATTEMPTS}: a person decides")

signals = []
for what, path, fields in (("review", reviews_p, ("submitted_at",)),
                           ("comment", icomments_p, ("created_at", "updated_at")),
                           ("reaction", reactions_p, ("created_at",))):
    for it in load(path):
        who = (it.get("user") or {}).get("login") or ""
        if who.lower() not in logins:
            continue
        times = [t for t in (str(it.get(f) or "") for f in fields) if STAMP.match(t)]
        if times and max(times) > end:
            label = f"{what} {it['content']}" if what == "reaction" and it.get("content") else what
            signals.append((max(times), f"{label} by {who} at {max(times)}"))
if not signals:
    skip(f"run {rid} attempt {attempt} ended {end}; nothing from an accepted reviewer since")
print(f"re-run {rid}: attempt {attempt} ended {end}; since then: {min(signals)[1]}")
