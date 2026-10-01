#!/usr/bin/env python3
# The decision of the `ci / docs` step that reads a pull request's description
# (#293), a pure function of one GraphQL answer:
# closing-references.py <owner/repo> <answer.json>.
# Exit 0 when every issue the merge would close is named on the closing line,
# 1 with the issues and the lines when one is not, 2 when the answer cannot be
# read. tests/closing-references-cases.sh runs this through its step.
"""Would merging this pull request close an issue its closing line does not name?

GitHub closes an issue when a merged description has a closing keyword
directly before its number, in a sentence as much as on a line of its
own: "the two fixes #65 decided" closed #65 with every criterion open
(#284). Which issues a merge will close is GitHub's to say, so the list
is read from it (`closingIssuesReferences`) and never worked out here;
an issue linked by hand in the sidebar is on that list too.

What is worked out here is the closing line: a line that is only a
closing keyword and an issue (`Closes #12`, a full stop allowed; more
issues after a comma or `and`, of which GitHub closes those with a
keyword of their own), standing in the closing position. That position
is the end of the description: below it come only blank lines, other
closing lines, `Part of` and `Related to` lines that hold issues only,
and trailers (`Assisted-by: ...`); above it, in its own paragraph, only
closing and such link lines. So the last line of a wrapped sentence that happens to read
`fixes #65` is not a closing line, and neither is the same line further
up with text after it; the message says to move that one.

The keyword search is used only to quote the line to reword. It does
not decide anything, so a form of GitHub's it misses costs a less
helpful message, not a wrong verdict.

Not read here: the pull request's title, which becomes the squash
commit's subject, and a link made in the sidebar after this ran, which
starts no new run. Whether GitHub's list is already current when an
`edited` event's run asks for it is not measured.
"""
import json
import re
import sys

KEYWORD = r"(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)"
# #12, GH-12, owner/repo#12, or the issue's URL.
REF = r"(?:(?:[\w.-]+/[\w.-]+)?#\d+|\bGH-\d+|https://github\.com/[\w.-]+/[\w.-]+/issues/\d+)"
CLOSING_LINE = re.compile(
    rf"^\s*{KEYWORD}:?\s+{REF}(?:\s*(?:,\s*and|,|and)\s*(?:{KEYWORD}:?\s+)?{REF})*\s*\.?\s*$",
    re.IGNORECASE,
)
# `Part of #12`, `Related to #12, #13.`: issues only. A sentence that starts
# with the same words is prose, and would let the line below it pass as a
# closing line (#368's review).
LINK_LINE = re.compile(
    rf"^\s*(?:part of|related to)\s+{REF}(?:\s*(?:,\s*and|,|and)\s*{REF})*\s*\.?\s*$",
    re.IGNORECASE,
)
TRAILER = re.compile(r"^[A-Za-z][A-Za-z0-9-]*: \S")
KEYWORD_BEFORE_REF = re.compile(rf"\b{KEYWORD}:?\s+({REF})", re.IGNORECASE)

Issue = tuple[str, int]  # (owner/repo in lower case, number)


def refs(text: str, repo: str) -> list[Issue]:
    """Every issue the text names; a bare #N is this repository's."""
    out = []
    for ref in re.findall(REF, text, re.IGNORECASE):
        where, number = re.split(r"/issues/|#|GH-", ref, flags=re.IGNORECASE)
        where = where.replace("https://github.com/", "") or repo
        out.append((where.lower(), int(number)))
    return out


def closing_position(lines: list[str]) -> set[int]:
    """Indexes of the closing lines at the end of the description."""
    found = set()
    for i in range(len(lines) - 1, -1, -1):
        line = lines[i]
        if not line.strip():
            continue
        if CLOSING_LINE.match(line):
            if not own_paragraph(lines, i):
                break
            found.add(i)
        elif not (LINK_LINE.match(line) or TRAILER.match(line)):
            break
    return found


def own_paragraph(lines: list[str], i: int) -> bool:
    """Is every line above this one, up to the blank line, a closing or link line?"""
    for line in reversed(lines[:i]):
        if not line.strip():
            break
        if not (CLOSING_LINE.match(line) or LINK_LINE.match(line)):
            return False
    return True


def excerpt(line: str, start: int, end: int, around: int = 50) -> str:
    """The match with some of the sentence on each side; a description line can be a whole paragraph."""
    a, b = max(0, start - around), min(len(line), end + around)
    return ("... " if a > 0 else "") + line[a:b].strip() + (" ..." if b < len(line) else "")


def show(issue: Issue, repo: str) -> str:
    return f"#{issue[1]}" if issue[0] == repo.lower() else f"{issue[0]}#{issue[1]}"


def main() -> int:
    repo, path = sys.argv[1], sys.argv[2]
    try:
        with open(path, encoding="utf-8") as f:
            pr = json.load(f)["data"]["repository"]["pullRequest"]
        closing = pr["closingIssuesReferences"]
        more = closing["pageInfo"]["hasNextPage"]
        will_close = [(n["repository"]["nameWithOwner"].lower(), int(n["number"])) for n in closing["nodes"]]
        body = pr["body"] or ""
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as e:
        print(f"  FAIL  could not read the pull request's closing list from GitHub's answer ({type(e).__name__}: {e})")
        return 2
    if more:
        print("  FAIL  GitHub lists more than 100 issues this merge would close; only the first 100 were read")
        return 2
    if not will_close:
        print("  PASS  GitHub lists no issue this pull request's merge would close")
        return 0

    lines = body.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    position = closing_position(lines)
    named = {issue for i in position for issue in refs(lines[i], repo)}
    outside = [issue for issue in will_close if issue not in named]
    if not outside:
        print(f"  PASS  the merge closes {', '.join(show(i, repo) for i in will_close)}: named on the closing line")
        return 0

    misplaced = False
    for issue in outside:
        name = show(issue, repo)
        print(f"  FAIL  {name}: GitHub closes it when this pull request merges, and the closing line does not name it")
        hits = 0
        for i, line in enumerate(lines):
            if i in position:
                continue
            at = [m for m in KEYWORD_BEFORE_REF.finditer(line) if issue in refs(m.group(1), repo)]
            if not at:
                continue
            hits += 1
            if CLOSING_LINE.match(line):
                misplaced = True
                print(f"        line {i + 1} is a closing line with text below it: {line.strip()}")
            else:
                print(f"        line {i + 1}: {excerpt(line, at[0].start(), at[0].end())}")
        if not hits:
            print("        no line was found with a closing keyword before it: it may be linked by hand")
            print("        under Development in the pull request's sidebar. Unlink it there, or name it")
            print("        on the closing line.")
    example = show(outside[0], repo)
    print()
    print("  A closing keyword (close, closes, closed, fix, fixes, fixed, resolve, resolves,")
    print("  resolved) directly before an issue number closes that issue on merge, in a")
    print("  sentence as much as on a line of its own.")
    print(f'  Reword the sentence so the keyword does not stand before the number: "the two fixes that {example}')
    print(f'  decided", or the issue first: "{example} decided two fixes".')
    print("  If this pull request does complete the issue, say so in a paragraph of its own, directly above")
    print(f"  the attribution (the last line, with no attribution): Closes {example}")
    if misplaced:
        print("  A closing line further up is not read as one: move it directly above the attribution.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
