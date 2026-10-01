#!/usr/bin/env python3
# The decision of .github/workflows/review-rerun.yml (#363), a pure function
# of files it fetched for one open pull request:
# review-rerun.py <logins> <runs> <reviews> <review-comments> <issue-comments> <reactions>.
# Exit 0 with `re-run <id>: <why>` when the failed run is to be asked again,
# 1 with why not. tests/pr-review-rerun.sh runs this file against fixtures.
"""Has an accepted reviewer done something on this pull request since
`third-party / review` gave up on its head?

The check waits `wait-seconds` and fails. A review with findings is a
`pull_request_review` event and starts the check again by itself; a
zero-finding verdict is often a `+1` reaction on the pull request alone
is an issue comment and a `+1` reaction on the pull request (measured
on #362), and neither starts a workflow. So the check stays red
although the reviewer has answered. This asks it again; the re-run
decides, with attest.py's binding rules. What asks is what the check
can count: a review, a review comment or an issue comment (created or
edited: the summary row is an edit) of an accepted login, newer than
the end of the failed attempt. Loose on purpose, as started.py is:
which comment it is, and which commit it names, the re-run reads. A
reaction is not one of them: it names no commit and attest.py does
not read it, so a re-run on a reaction alone would only fail again
and spend an attempt. Its log line says so.

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

logins_csv, runs_p, reviews_p, rcomments_p, icomments_p, reactions_p = sys.argv[1:7]
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

def since(what, path, fields):
    """(time, description) of each item of an accepted login newer than `end`."""
    found = []
    for it in load(path):
        who = (it.get("user") or {}).get("login") or ""
        times = [t for t in (str(it.get(f) or "") for f in fields) if STAMP.match(t)]
        if who.lower() in logins and times and max(times) > end:
            label = f"{what} {it['content']}" if it.get("content") else what
            found.append((max(times), f"{label} by {who} at {max(times)}"))
    return found

signals = (since("review", reviews_p, ("submitted_at",))
           + since("review comment", rcomments_p, ("created_at", "updated_at"))
           + since("comment", icomments_p, ("created_at", "updated_at")))
if not signals:
    reactions = since("reaction", reactions_p, ("created_at",))
    if reactions:
        skip(f"run {rid} attempt {attempt} ended {end}; only a reaction since ({min(reactions)[1]}),"
             " which the check does not count: it names no commit")
    skip(f"run {rid} attempt {attempt} ended {end}; nothing from an accepted reviewer since")
print(f"re-run {rid}: attempt {attempt} ended {end}; since then: {min(signals)[1]}")
