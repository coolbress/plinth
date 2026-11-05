#!/usr/bin/env python3
"""Does a pull request's description say what the person checked and which review ran? (#810)

`ci / pr-title` in python-ci.yml fetches this at its own commit and runs it on
the description closing-references.sh read; gitlab/python-ci.yml's pr-title
carries the same definitions (tests/gitlab-ci-cases.sh compares the text).
It prints one verdict line per field: `pass:` when the field is filled, and
`not yet confirmed:` when it is missing, empty or says only "done", which the
job turns into a warning. It never fails: whether either field becomes
required waits on the non-author trial (#163).

    description-fields.py PR <GitHub GraphQL answer, as closing-references.sh read it> [<the highest numbers' answer>]

With the third argument, GitHub's answer for the newest issue and pull request,
it also prints a `not yet confirmed:` line for each bare `#N` above the highest
of them (#826): a reference to another repository written without its name.
"""
import json
import re
import sys

COMMENT = re.compile(r"<!--.*?(?:-->|\Z)", re.DOTALL)
FENCE = re.compile(r"^\s{0,3}(```|~~~)")
HEADING = re.compile(r"^\s{0,3}#{1,6}\s")
CHECKED = re.compile(r"^\s{0,3}#{1,6}\s+what i checked myself\s*:?\s*#*\s*$", re.IGNORECASE)
REVIEW = re.compile(r"^\s*(?:[-*]\s+)?\**review\**\s*:\**\s*(.*?)\s*$", re.IGNORECASE)
# Lines that end a description rather than fill a section: the closing or
# link line and the attribution's trailers.
ENDING = re.compile(
    r"^\s*(?:(?:closes|fixes|resolves|part of|related to)\s+\S*#\d+"
    r"|(?:assisted-by|co-authored-by|signed-off-by):\s)",
    re.IGNORECASE,
)
# fresh-context or same-session alone; third-party and none with what goes in
# their brackets, a placeholder such as `<name>` not counting.
KINDS = re.compile(r"^(?:(?:fresh-context|same-session)\b|(?:third-party|none)\s*\(\s*[^\s<)][^)]*\))", re.IGNORECASE)
REVIEW_FORM = "Review: fresh-context | third-party (<name>) | same-session (not independent) | none (<reason>)"
# A bare `#N`, or GitLab's `!N` (#826): what stands outside code spans and
# links, with no path, name, `#`, `!` or `&` (an HTML entity) right before it.
CODE_SPAN = re.compile(r"(`+).*?\1")
LINKS = re.compile(r"!?\[[^\]]*\]\([^)]*\)|!?\[[^\]]*\]\[[^\]]*\]|^\s{0,3}\[[^\]]+\]:\s.*|<[a-z][a-z0-9+.-]*:[^>\s]*>|https?://\S+", re.IGNORECASE)
BARE = re.compile(r"(?<![\w/#!&.-])([#!])(\d+)\b")


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
    words = re.sub(r"\[[ xX]?\]|[\s`*_.!:()<>-]+", " ", text).strip().lower()
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
    v = value.strip()
    return not bare(v) and "|" not in v and bool(KINDS.match(v))


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
               else f'its `What I checked myself` section says only "{" ".join(checked.split())}", and "done" or a bare "Skipped" records nothing')
        out.append(f"not yet confirmed: {what} description, does not say what the person checked themselves: {why};"
                   " under that heading write what you ran, opened or read and what you saw (a command's output,"
                   " a page, a number), or `Skipped: <reason>`; an edited description is read again on the next run")
    values = review_values(lines)
    if any(review_filled(v) for v in values):
        out.append(f"pass: {what} description, says which review ran")
    else:
        why = ("there is no `Review:` line" if not values
               else "its `Review:` line is empty" if not values[-1].strip()
               else f'its `Review:` line says "{" ".join(values[-1].split())}", which names none of the four answers or gives no reason')
        out.append(f"not yet confirmed: {what} description, does not say which review ran: {why};"
                   f" write one line, `{REVIEW_FORM}`; an edited description is read again on the next run")
    return out


def unknown_numbers(body, highest, what):
    """One line for each bare reference above the highest number of its kind (#826).

    `highest` maps `#` (and on GitLab `!`) to that number, what it numbers, and
    how another repository's is written; a kind that could not be read is left out."""
    seen, out = set(), []
    for line, fenced in unfenced(body or ""):
        if fenced:
            continue
        for m in BARE.finditer(LINKS.sub(" ", CODE_SPAN.sub(" ", line))):
            sigil, number = m.group(1), int(m.group(2))
            if sigil not in highest or number <= highest[sigil][0] or (sigil, number) in seen:
                continue
            seen.add((sigil, number))
            top, kind, form = highest[sigil]
            out.append(f"not yet confirmed: {what} description, {sigil}{number} is above the highest {kind} number here"
                       f" ({sigil}{top}), so it links to nothing; a reference to another repository's is written `{form}`;"
                       " an edited description is read again on the next run")
    return out


def github_highest(path):
    """The highest number GitHub's answer gives: issues and pull requests share one count."""
    with open(path, encoding="utf-8") as f:
        repo = json.load(f)["data"]["repository"]
    return max([n["number"] for k in ("issues", "pullRequests") for n in repo[k]["nodes"]] + [0])


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4):
        sys.exit("usage: description-fields.py PR|MR <GitHub GraphQL answer> [<the highest numbers' answer>]")
    try:
        with open(sys.argv[2], encoding="utf-8") as f:
            body = json.load(f)["data"]["repository"]["pullRequest"]["body"]
    except (OSError, ValueError, KeyError, TypeError) as e:
        print(f"not yet confirmed: {sys.argv[1]} description, its fields could not be read ({type(e).__name__});"
              " a run that reads the description confirms them")
        sys.exit(0)
    lines = field_lines(body, sys.argv[1])
    # The bare numbers: never the fields' verdict, never a red. Unread, the
    # log says why and nothing is warned.
    if len(sys.argv) == 4:
        try:
            lines += unknown_numbers(body, {"#": (github_highest(sys.argv[3]), "issue or pull request", "owner/repo#N")}, sys.argv[1])
        except Exception as e:
            print(f"bare #N not checked: the highest issue or pull request number could not be read ({type(e).__name__})", file=sys.stderr)
    print("\n".join(lines))
