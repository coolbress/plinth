#!/usr/bin/env python3
# The judgement of .github/workflows/pr-review.yml, a pure function of files
# the step fetched: attest.py <head> <logins> <reviews> <review-comments>
# <issue-comments> [<activity>]. Exit 0 with the signal found, 1 with what
# was seen. tests/pr-review-attest.sh runs this file against fixtures.
r"""Did an accepted reviewer account leave a signal on THIS commit?
Participation evidence, no verdict.

Four signals, all accepted; the first to arrive wins (1 to 3 measured
2026-09-01, 4 on 2026-09-18):

  1 review object: a code review ends as a review with state
    COMMENTED, even with zero findings. Fast, about four minutes.
    Not every review object is a review: Copilot, asked by a person
    out of quota, submits one on the head seconds later whose body is
    a notice that it could not review (#204). A body that begins
    with that notice does not count.
  2 marker: `<!-- codex-security-review:v1 {"headSha":..,"status":"completed"} -->`
    inside the summary issue comment. `completed` needs the security
    review to finish too, which has taken over 30 minutes, and has
    stayed at `running` after the review was done. Not trusted alone.
  3 completion comment: with zero findings no review object may
    appear at all, only a plain issue comment ("Codex Review: Didn't
    find any major issues", "Security review completed..."). It names
    the commit (`**Reviewed commit:** \`db8c8772fd\``), ten
    characters, and it stays on the pull request: a later head made
    to share them would pass on it before any review of that head
    (#193). So it is bound as signal 4 is, by the same predicate:
    its `created_at` must be later than the newest push of this
    head, and the head must be the one commit the branch has
    pointed at that begins with the characters it names. Two
    earlier versions bound by time in place of the commit and both
    were guesses; this is a time next to the commit. String
    matching is brittle; that is why all the signals are read.
  4 summary table row: a zero-finding review started by a push
    (`New commits`) has left none of the above (measured on
    plinth#190, head fd4bb91; #191). What it did leave is a row in
    the summary issue comment, edited in place:
    `| 📝 **Code Review** | ✅ **Completed** <time> | \`fd4bb91\` | New commits |`.
    A `**Completed**` row whose commit, seven characters as the
    vendor writes it, is a prefix of the head counts. Any other
    status does not; the trigger column is not read. Seven
    characters do not name one commit: a head made to share them
    with an earlier, reviewed head would ride on that head's row
    (the reviewer's finding on plinth#192). So the row's completion
    time must also be later than the newest push that brought this
    head to the branch, read from the repository's activity log.
    Both times are written by a server, the vendor's and GitHub's;
    a commit's own dates are its author's text and are not read.
    The newest push of the head is the latest timestamp among the
    log's entries whose `after` is the head, in whatever order they
    arrive; if one of those has no readable timestamp, the push
    counts as unread (#197).
    This is a time next to the commit, not in place of it. The
    time says the row was completed after this head arrived, not
    which commit was completed: the review of an earlier head with
    the same seven characters, still running when this head is
    pushed, completes after the push (the reviewer's second finding
    there). The log holds every commit the branch has pointed at,
    the `before` and `after` of each push, force pushes included;
    the row counts only when the head is the one commit among them
    that begins with the row's characters. Where the push cannot be
    read (the call failed, the head is not in the log, a fork's
    branch) or the log is a full page of 100, which may have more
    behind it, neither the row nor the completion comment counts
    and the log says so; signals 1 and 2 compare forty characters
    and do not read the log. A fork's pull request therefore passes
    on signal 1 or 2 only (the owner's decision on #193: the fork
    is where the person who can push a colliding head is least
    known).

Author alone cannot tell a code review from a security review; the
same bot posts both. So the sentence guaranteed is exactly "the
reviewer looked at this commit". The security review is not
available on every plan and this check stands without it; the
deterministic security checks (CodeQL, zizmor, bandit, secrets,
dependencies) already block in CI.
"""
import json
import os
import pathlib
import re
import sys

head, logins_csv = sys.argv[1:3]
reviews_p, rcomments_p, icomments_p = sys.argv[3:6]
activity_p = sys.argv[6] if len(sys.argv) > 6 else ""   # pushes to the head branch, newest first

#: The commit a completion comment names, seven to forty characters.
REVIEWED = re.compile(r"Reviewed commit:\*{0,2}\s*`([0-9a-f]{7,40})`", re.IGNORECASE)

#: Completion wording with zero findings. Vendor text: brittle by nature.
DONE = re.compile(
    # No apostrophe: the vendor writes "Didn't" and the character varies.
    r"find any major issues|Security review completed"
    r"|No security issues were found|리뷰를 마쳤",   # the same completion in Korean, measured
    re.IGNORECASE,
)
#: A review object whose body begins so says no review happened: Copilot
#: submits it on the head when the person who asked is out of quota
#: (measured 2026-09-19, #204). Vendor text, the one notice measured.
COULD_NOT_REVIEW = re.compile(r"\s*Copilot was unable to review this pull request", re.IGNORECASE)
logins = {x.strip().lower() for x in logins_csv.split(",") if x.strip()}
MARK = re.compile(r"<!--\s*codex-security-review:v1\s*(\{.*?\})\s*-->", re.DOTALL)

#: The summary comment starts with this line; a table anywhere else is not read.
SUMMARY = "<!-- codex-pull-request-review-summary -->"
#: One row of its table: status (bold, after one emoji), the rest of
#: that cell, and the commit. Vendor text.
ROW = re.compile(r"^\|[^|\n]*\|\s*(?:\S+\s+)?\*\*([^*|\n]+)\*\*([^|\n]*)\|\s*`([0-9a-f]{7,40})`\s*\|", re.MULTILINE)
#: When the row's review completed, to the second, UTC only.
WHEN = re.compile(r'datetime="(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.\d+)?Z"')
#: GitHub's push time, the same shape without a fraction.
STAMP = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")

def readable(p):
    """Is the file a JSON list? The step writes `null` when a call
    fails, so a failed fetch and an empty list are told apart (#188)."""
    try:
        return isinstance(json.loads(pathlib.Path(p).read_text() or "[]"), list)
    except (OSError, json.JSONDecodeError):
        return False

def load(p):
    try:
        d = json.loads(pathlib.Path(p).read_text() or "[]")
    except (OSError, json.JSONDecodeError):
        return []
    return d if isinstance(d, list) else []

def ours(it):
    return ((it.get("user") or {}).get("login") or "").lower() in logins

seen = set()
for path in (reviews_p, rcomments_p, icomments_p):
    for it in load(path):
        seen.add((it.get("user") or {}).get("login") or "")

def looked(how, excerpt=None):
    """The verdict is yes. Say so, then list the accepted reviewer's
    inline comments made on this commit (`original_commit_id`, the
    field that does not move) with their URLs, in the log and in the
    job summary. Zero is printed as zero. The count never changes the
    verdict; it is there so the person who merges sees what the
    summary comment does not say (#176: a P2 merged past unread while
    the summary read "Didn't find any major issues"). It is what the
    fetch that produced the signal saw: a review that finishes later
    (the security review has taken over 30 minutes) adds comments
    this line does not show, so it says so."""
    print(f"third party looked at this commit: {how}")
    if excerpt:
        print(f"   {excerpt}")
    urls = [it.get("html_url") or "(no url)" for it in load(rcomments_p)
            if ours(it) and it.get("original_commit_id") == head]
    n = len(urls)
    if not readable(rcomments_p):
        # A failed or malformed fetch is not zero comments (#188): say
        # so, never the zero line. The verdict above was not built on
        # this file, so it stands.
        line = ("inline comments: could not be read (the pulls/<n>/comments call failed"
                " or did not return a list); run the live query in the how-to")
    else:
        line = (f"reviewer left {n} inline comment{'s' if n != 1 else ''} on {head[:8]}"
                if n else f"no inline comments on this head ({head[:8]})")
        line += " as of this check run; a later review may add more"
    print(line)
    for u in urls:
        print(f"   {u}")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write(line + "\n" + "".join(f"- {u}\n" for u in urls))
    sys.exit(0)

# 1 review objects and review comments: the commit must match.
#
# Two different fields, and mixing them opens the check (measured
# 2026-09-01): the `commit_id` of a review comment (`pulls/N/comments`)
# is rewritten by GitHub to the current head whenever a new commit
# lands, as long as the line is still alive. One comment from an old
# review turned every later push green within 20 seconds, 140 seconds
# before the real review arrived. `original_commit_id` is the commit
# the comment was made on and never moves; that is the one read.
# Review objects (`pulls/N/reviews`) have no such field and their
# `commit_id` does not move. A review object that is a could-not-review
# notice is left out (#204); review comments are not read for it.
notices = []
for kind, path, field in (("review", reviews_p, "commit_id"),
                          ("review-comment", rcomments_p, "original_commit_id")):
    for it in load(path):
        if ours(it) and it.get(field) == head:
            if kind == "review" and COULD_NOT_REVIEW.match(it.get("body") or ""):
                notices.append(it)
                continue
            looked(f"{kind} ({it.get('state') or 'comment'})")

# 2 marker: `completed` only. `running` is looking, not looked.
states = []
for it in load(icomments_p):
    if not ours(it):
        continue
    for raw in MARK.findall(it.get("body") or ""):
        try:
            d = json.loads(raw)
        except json.JSONDecodeError:
            continue
        states.append((d.get("headSha") or "", d.get("status") or "?"))
        if d.get("headSha") == head and d.get("status") == "completed":
            looked("marker status=completed")

# Signals 3 and 4 name the head by a prefix (ten characters, seven), so
# both are also bound to the push of this head and to the head being
# the one such commit (#191, #193). All times are UTC to the second in
# one shape, so they compare as text.
pushes = [p for p in load(activity_p) if isinstance(p, dict)]
if len(pushes) >= 100:   # a full page: older pushes may be missing
    pushes = []
# The newest push of this head is the latest by time, not the first
# listed: the step asks for newest first, and this does not lean on
# it (#197). One of them without a readable time: nothing is known.
stamps = [str(p.get("timestamp") or "") for p in pushes if p.get("after") == head]
pushed = max(stamps)[:19] if stamps and all(STAMP.match(t) for t in stamps) else ""
tips = {str(p.get(k) or "") for p in pushes for k in ("before", "after")}

def unbound(sha, when):
    """Why a signal that names this head as `sha` and was finished at
    `when` is not tied to it; empty when it is."""
    if not pushed:
        return "the push of this head could not be read, or the log is a full page"
    if not when > pushed:
        return f"finished {when or '(no time read)'}, not after the push of this head ({pushed}Z)"
    if [t for t in tips if t.startswith(sha)] != [head]:
        return f"another commit this branch has pointed at begins with {sha}"
    return ""

# 3 completion comment: names a prefix of the head, created after the
# newest push of this head (`created_at`, GitHub's).
left_out = []
for it in load(icomments_p):
    body = it.get("body") or ""
    if not ours(it) or not DONE.search(body):
        continue
    m = REVIEWED.search(body)
    if not m:
        # A completion that names no commit belongs to an unknown commit.
        continue
    sha = m.group(1)
    if head.startswith(sha):
        when = str(it.get("created_at") or "")
        when = when[:19] if STAMP.match(when) else ""
        why = unbound(sha, when)
        if not why:
            looked(f"completion comment (Reviewed commit: {sha}, {when}Z; this head was pushed {pushed}Z)",
                   body.splitlines()[0][:90])
        left_out.append((sha, why))

# 4 summary table row: `Completed`, the commit is a prefix of the head,
# and the completion is later than the newest push of this head.
rows = []
for it in load(icomments_p):
    body = it.get("body") or ""
    if not ours(it) or not body.lstrip().startswith(SUMMARY):
        continue
    for status, cell, sha in ROW.findall(body):
        found = WHEN.search(cell)
        when = found.group(1) if found else ""
        fits = status == "Completed" and head.startswith(sha)
        why = unbound(sha, when) if fits else ""
        if fits and not why:
            looked(f"summary table row (Completed, {sha}, {when}Z; this head was pushed {pushed}Z)")
        note = "<- this commit" if head.startswith(sha) else ""
        if why:
            note += f", not counted: {why}"
        rows.append((sha, status, note))

print("not yet.")
for it in notices[-3:]:
    print(f"   review {(it.get('user') or {}).get('login')} ({it.get('state') or '?'}) <- this commit,"
          f" not counted: a could-not-review notice: {(it.get('body') or '').strip().splitlines()[0][:90]}")
for sha, status in states[-3:]:
    print(f"   marker {sha[:8]} status={status} {'<- this commit' if sha == head else ''}")
for sha, why in left_out[-3:]:
    print(f"   completion comment {sha} <- this commit, not counted: {why}")
for sha, status, note in rows[-3:]:
    print(f"   summary row {sha[:8]} status={status} {note}")
if seen:
    print("  authors seen on this pull request: " + ", ".join(sorted(x for x in seen if x)))
sys.exit(1)
