"""What one invocation of a skill reads, for tests/skill-size.sh.

Usage: skill_reads.py <plugin root> <skills/<name>/SKILL.md>

Prints one line per file the body names, tab-separated:

    read      <path from the root>   the body says to read it before acting
    optional  <path from the root>   named, but not to be read before acting
    description  <bytes>             the frontmatter's description, in bytes

The body is cut into chunks: paragraphs, and each list item on its own; a
fenced code block is not read. A file is named by `${CLAUDE_PLUGIN_ROOT}/<path>`,
by a Markdown link `[...](<path>)`, or as a bare `<name>.md` that exists
beside the skill; a table row is a chunk of its own. A file is `read`
when a chunk naming it has a "read" and, later in the same sentence (up to
a `.`, `;` or `:` before a space, or a table cell's `|`), "before" or "first", and does not
say "only when" (nor "can read" or "may read"); a list item whose lead-in paragraph says "only when" is not
read either. Every other file it names is `optional`. The description is
the frontmatter's one line, or a block scalar's indented lines joined;
none is printed as an empty number. Only files that exist under the root are listed: a path the
project has (its own docs/how-to) is not the plugin's.
"""

import os
import re
import sys

ROOT_REF = re.compile(r"\$\{CLAUDE_PLUGIN_ROOT\}/([A-Za-z0-9_./-]+\.md)")
LINK = re.compile(r"\]\(([A-Za-z0-9_./-]+\.md)(?:#[^)]*)?\)")
BARE = re.compile(r"(?<![A-Za-z0-9_./-])([A-Za-z0-9_-]+\.md)(?![A-Za-z0-9_-])")
# "read it before", "Read <file> before", "read it first": a "read" and,
# later in the same sentence, "before" or "first"; not "can read" or "may
# read", which is the person's choice ("the person can read ... first").
BEFORE = re.compile(
    r"(?<!can )(?<!may )\bread\b(?:(?![.;:](?:\s|$))[^|])*?\b(?:before|first)\b",
    re.IGNORECASE,
)
ONLY_WHEN = re.compile(r"\bonly when\b", re.IGNORECASE)
ITEM = re.compile(r"^\s*(?:[-*]|[0-9]+\.)\s")


def split(text):
    """Frontmatter description, and the body's chunks."""
    lines = text.split("\n")
    description = None
    start = 0
    if lines and lines[0] == "---":
        for i in range(1, len(lines)):
            if lines[i] == "---":
                start = i + 1
                break
            if lines[i].startswith("description:"):
                description = lines[i][len("description:") :].strip()
                # A block scalar (>-, |): its indented lines are the text.
                if description in ("", ">", ">-", ">+", "|", "|-", "|+"):
                    more = []
                    for line in lines[i + 1 :]:
                        if not line.startswith((" ", "\t")):
                            break
                        more.append(line.strip())
                    description = " ".join(more) or None
    chunks, cur, fenced, item = [], [], False, False
    for line in lines[start:]:
        if line.lstrip().startswith("```"):
            fenced = not fenced
            if cur:
                chunks.append((item, " ".join(cur)))
                cur = []
            continue
        if fenced:
            continue
        # A table row is a chunk of its own, as a list item is.
        if not line.strip() or ITEM.match(line) or line.lstrip().startswith("|"):
            if cur:
                chunks.append((item, " ".join(cur)))
            cur = [line.strip()] if line.strip() else []
            item = bool(ITEM.match(line))
        else:
            if not cur:
                item = False
            cur.append(line.strip())
    if cur:
        chunks.append((item, " ".join(cur)))
    return description, chunks


def names(chunk, root, here):
    found = []
    for m in ROOT_REF.finditer(chunk):
        found.append(os.path.normpath(m.group(1)))
    for m in LINK.finditer(chunk):
        found.append(os.path.normpath(os.path.join(here, m.group(1))))
    for m in BARE.finditer(chunk):
        p = os.path.normpath(os.path.join(here, m.group(1)))
        if os.path.isfile(os.path.join(root, p)):
            found.append(p)
    return [p for p in dict.fromkeys(found) if os.path.isfile(os.path.join(root, p))]


def main():
    root, skill = sys.argv[1], sys.argv[2]
    here = os.path.dirname(skill)
    with open(os.path.join(root, skill), encoding="utf-8") as f:
        description, chunks = split(f.read())
    read, optional = [], []
    # A list's items take the paragraph above them as their lead-in: "read it
    # only when asked" there holds for each item under it.
    lead_only = False
    for item, chunk in chunks:
        if not item:
            lead_only = bool(ONLY_WHEN.search(chunk))
        to_read = (
            BEFORE.search(chunk)
            and not ONLY_WHEN.search(chunk)
            and not (item and lead_only)
        )
        for p in names(chunk, root, here):
            if p == skill:
                continue
            (read if to_read else optional).append(p)
    read = list(dict.fromkeys(read))
    optional = [p for p in dict.fromkeys(optional) if p not in read]
    for p in read:
        print(f"read\t{p}")
    for p in optional:
        print(f"optional\t{p}")
    print(
        "description\t"
        + ("" if description is None else str(len(description.encode("utf-8"))))
    )


if __name__ == "__main__":
    main()
