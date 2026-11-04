#!/usr/bin/env python3
"""Does a pull request's description say what the person checked and which review ran? (#810)

`ci / pr-title` in python-ci.yml fetches this at its own commit and runs it on
the description closing-references.sh read; gitlab/python-ci.yml's pr-title
carries the same definitions (tests/gitlab-ci-cases.sh compares the text).
It prints one verdict line per field: `pass:` when the field is filled, and
`not yet confirmed:` when it is missing, empty or says only "done", which the
job turns into a warning. It never fails: whether either field becomes
required waits on the non-author trial (#163).

    description-fields.py PR <GitHub GraphQL answer, as closing-references.sh read it>
"""
import json
import re
import sys

COMMENT = re.compile(r"<!--.*?(?:-->|\Z)", re.S)
FENCE = re.compile(r"^\s{0,3}(```|~~~)")
HEADING = re.compile(r"^\s{0,3}#{1,6}\s")
CHECKED = re.compile(r"^\s{0,3}#{1,6}\s+what i checked myself\s*#*\s*$", re.I)
REVIEW = re.compile(r"^\s*(?:[-*]\s+)?\**review\**\s*:\**\s*(.*?)\s*$", re.I)
# Lines that end a description rather than fill a section: the closing or
# link line and the attribution's trailers.
ENDING = re.compile(
    r"^\s*(?:(?:closes|fixes|resolves|part of|related to)\s+\S*#\d+"
    r"|(?:assisted-by|co-authored-by|signed-off-by):\s)",
    re.I,
)
KINDS = ("fresh-context", "third-party", "same-session", "none")
REVIEW_FORM = "Review: fresh-context | third-party (<name>) | same-session (not independent) | none (<reason>)"


def unfenced(body):
    """The description's lines without its HTML comments, each with whether it sits in a code fence."""
    out, fenced = [], False
    for line in COMMENT.sub("", body).replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if FENCE.match(line):
            fenced = not fenced
            out.append((line, True))
            continue
        out.append((line, fenced))
    return out


def bare(text):
    """Empty, or only a word that says nothing was recorded."""
    words = re.sub(r"[\s`*_.!:()<>-]+", " ", text).strip().lower()
    return words in ("", "done", "skipped", "none", "reason", "skipped reason", "none reason")


def checked_text(lines):
    """The text under a `What I checked myself` heading, or None without one."""
    text, inside, found = [], False, False
    for line, fenced in lines:
        if not fenced and HEADING.match(line):
            inside = bool(CHECKED.match(line))
            found = found or inside
            continue
        if inside and (fenced or not (REVIEW.match(line) or ENDING.match(line))):
            text.append(line)
    return "\n".join(text).strip() if found else None


def review_values(lines):
    return [m.group(1) for line, fenced in lines if not fenced for m in [REVIEW.match(line)] if m]


def review_filled(value):
    v = value.strip().lower()
    return not bare(v) and any(v.startswith(k) for k in KINDS)


def field_lines(body, what):
    """One verdict line for each field; `what` is PR or MR."""
    lines = unfenced(body or "")
    out = []
    checked = checked_text(lines)
    if checked is not None and not bare(checked):
        out.append(f"pass: {what} description, says what the person checked themselves")
    else:
        why = ("there is no `What I checked myself` section" if checked is None
               else "its `What I checked myself` section is empty" if not checked.strip()
               else f'its `What I checked myself` section says only "{checked.strip()}", and "done" or a bare "Skipped" records nothing')
        out.append(f"not yet confirmed: {what} description, does not say what the person checked themselves: {why};"
                   " under that heading write what you ran, opened or read and what you saw (a command's output,"
                   " a page, a number), or `Skipped: <reason>`; an edited description is read again on the next run")
    values = review_values(lines)
    if any(review_filled(v) for v in values):
        out.append(f"pass: {what} description, says which review ran")
    else:
        why = ("there is no `Review:` line" if not values
               else "its `Review:` line is empty" if not values[-1].strip()
               else f'its `Review:` line says "{values[-1].strip()}", which names none of the four answers or gives no reason')
        out.append(f"not yet confirmed: {what} description, does not say which review ran: {why};"
                   f" write one line, `{REVIEW_FORM}`; an edited description is read again on the next run")
    return out


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: description-fields.py PR|MR <GitHub GraphQL answer>")
    try:
        with open(sys.argv[2], encoding="utf-8") as f:
            body = json.load(f)["data"]["repository"]["pullRequest"]["body"]
    except (OSError, ValueError, KeyError, TypeError) as e:
        print(f"not yet confirmed: {sys.argv[1]} description, its fields could not be read ({type(e).__name__});"
              " a run that reads the description confirms them")
        sys.exit(0)
    print("\n".join(field_lines(body, sys.argv[1])))
