"""What one invocation of a skill reads, for tests/skill-size.sh.

Usage: skill_reads.py <plugin root> <skills/<name>/SKILL.md>

Prints one line per file the body names, tab-separated:

    read      <path from the root>   the body says to read it before acting
    optional  <path from the root>   named, but not to be read before acting
    description  <bytes>             the frontmatter's description, in bytes

The body is cut into chunks: paragraphs, and each list item on its own; a
fenced code block is not read. A file is named by `${CLAUDE_PLUGIN_ROOT}/<path>`,
by a Markdown link `[...](<path>)`, or as a bare `<name>.md` that exists
beside the skill. A file is `read` when a chunk naming it says "read it
before" and does not say "only when"; every other file it names is
`optional`. Only files that exist under the root are listed: a path the
project has (its own docs/how-to) is not the plugin's.
"""

import os
import re
import sys

ROOT_REF = re.compile(r"\$\{CLAUDE_PLUGIN_ROOT\}/([A-Za-z0-9_./-]+\.md)")
LINK = re.compile(r"\]\(([A-Za-z0-9_./-]+\.md)(?:#[^)]*)?\)")
BARE = re.compile(r"(?<![A-Za-z0-9_./-])([A-Za-z0-9_-]+\.md)(?![A-Za-z0-9_-])")
BEFORE = re.compile(r"\bread it before\b", re.IGNORECASE)
ONLY_WHEN = re.compile(r"\bonly when\b", re.IGNORECASE)
ITEM = re.compile(r"^\s*(?:[-*]|[0-9]+\.)\s")


def split(text):
    """Frontmatter description, and the body's chunks."""
    lines = text.split("\n")
    description = ""
    start = 0
    if lines and lines[0] == "---":
        for i in range(1, len(lines)):
            if lines[i] == "---":
                start = i + 1
                break
            if lines[i].startswith("description:"):
                description = lines[i][len("description:") :].strip()
    chunks, cur, fenced = [], [], False
    for line in lines[start:]:
        if line.lstrip().startswith("```"):
            fenced = not fenced
            if cur:
                chunks.append(" ".join(cur))
                cur = []
            continue
        if fenced:
            continue
        if not line.strip() or ITEM.match(line):
            if cur:
                chunks.append(" ".join(cur))
            cur = [line.strip()] if line.strip() else []
        else:
            cur.append(line.strip())
    if cur:
        chunks.append(" ".join(cur))
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
    for chunk in chunks:
        to_read = BEFORE.search(chunk) and not ONLY_WHEN.search(chunk)
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
    print(f"description\t{len(description.encode('utf-8'))}")


if __name__ == "__main__":
    main()
