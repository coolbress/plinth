#!/usr/bin/env python3
"""CHANGELOG.md fragments: one file per pull request in changelog.d/ (#1136).

A fragment is `changelog.d/<name>.md`: one or more `### <Section>` headings of
Keep a Changelog (Added, Changed, Deprecated, Removed, Fixed, Security), each
with its entries under it, and nothing before the first heading. Several pull
requests open from the same main each add their own file, so none conflicts
in CHANGELOG.md, which every change used to edit under `## [Unreleased]`.

    changelog-fragments.py check [<root>]
        Every fragment reads, and `## [Unreleased]` in CHANGELOG.md has no
        line under it: a line there is a fragment that was not written.
        A step of `ci / docs` (.github/workflows/plinth-ci.yml).
    changelog-fragments.py assemble [<root>]
        Prints the new version's sections: each section once, in the order
        above, its entries in the fragments' name order. Run 1 of
        scripts/make-release.sh writes them under the new version's heading
        and deletes every changelog.d/*.md in the same commit.

Either stops (exit 1, the reason on stderr) on a fragment that is empty,
names no known section, has text before its first `###` heading, a section
with nothing under it, or a heading of another level; on a file in
changelog.d/ that is not a fragment (dot files aside); and on a line under
`## [Unreleased]`. tests/changelog-fragments-cases.sh runs it.
"""
import pathlib
import re
import sys

SECTIONS = ["Added", "Changed", "Deprecated", "Removed", "Fixed", "Security"]
DIR = "changelog.d"
HEADING = re.compile(r"^ {0,3}(#{1,6})(?:[ \t]+(.*?))?[ \t]*#*[ \t]*$")


def read(path, rel):
    """{section: [entry text, ...]} of one fragment; a list of problems instead."""
    text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
    if not text.strip():
        return f"{rel} is empty: write its section and its line, or delete it"
    out, cur, body, problems = {}, None, [], []

    def close():
        if cur is not None:
            block = "\n".join(body).strip("\n")
            if not block.strip():
                problems.append(f"{rel}: '### {cur}' has nothing under it")
            else:
                out.setdefault(cur, []).append(block)

    fence = None
    for n, line in enumerate(text.split("\n"), 1):
        m = re.match(r"^ {0,3}(`{3,}|~{3,})", line)
        if m:
            fence = None if fence and m[1].startswith(fence) else (fence or m[1])
        h = None if fence else HEADING.match(line)
        if h:
            if h[1] != "###":
                problems.append(f"{rel}:{n}: '{line.strip()}' is not a '### <Section>' heading; a fragment holds only those")
                continue
            close()
            cur, body = (h[2] or "").strip(), []
            if cur not in SECTIONS:
                problems.append(f"{rel}:{n}: '### {cur}' names no known section ({', '.join(SECTIONS)})")
            continue
        if cur is None:
            if line.strip():
                problems.append(f"{rel}:{n}: text before the first '### <Section>' heading")
            continue
        body.append(line)
    close()
    if not out and not problems:
        problems.append(f"{rel} names no section: start it with '### <Section>' ({', '.join(SECTIONS)})")
    return problems or out


def fragments(root):
    """[(relative name, {section: [entries]})] in name order; stops on any problem."""
    d = root / DIR
    found, problems = [], []
    if d.is_dir():
        for p in sorted(d.iterdir(), key=lambda p: p.name):
            rel = f"{DIR}/{p.name}"
            if p.name.startswith("."):
                continue
            if not p.is_file() or p.suffix != ".md":
                problems.append(f"{rel} is not a fragment (a .md file); fragments are all changelog.d/ holds")
                continue
            got = read(p, rel)
            if isinstance(got, dict):
                found.append((rel, got))
            else:
                problems.extend([got] if isinstance(got, str) else got)
    unreleased = re.search(r"^## \[Unreleased\][^\n]*\n(.*?)(?=^## \[|^\[Unreleased\]: |\Z)",
                           (root / "CHANGELOG.md").read_text(encoding="utf-8"), re.M | re.S)
    if unreleased is None:
        problems.append("CHANGELOG.md has no '## [Unreleased]' heading")
    elif unreleased[1].strip():
        first = next(l for l in unreleased[1].split("\n") if l.strip())
        problems.append(f"CHANGELOG.md has lines under '## [Unreleased]' (first: '{first.strip()}'); "
                        f"a change's line goes in its own fragment, {DIR}/<branch-slug>.md (CONTRIBUTING.md, Land a change)")
    if problems:
        print("changelog fragments:", *problems, sep="\n  ", file=sys.stderr)
        sys.exit(1)
    return found


def main():
    if len(sys.argv) not in (2, 3) or sys.argv[1] not in ("check", "assemble"):
        print("usage: changelog-fragments.py check|assemble [<root>]", file=sys.stderr)
        return 2
    root = pathlib.Path(sys.argv[2] if len(sys.argv) == 3 else ".")
    found = fragments(root)
    if sys.argv[1] == "check":
        print(f"  PASS  {len(found)} fragment(s) in {DIR}/ read, and nothing under [Unreleased] in CHANGELOG.md")
        return 0
    blocks = []
    for s in SECTIONS:
        entries = [e for _, f in found for e in f.get(s, [])]
        if entries:
            blocks.append(f"### {s}\n\n" + "\n\n".join(entries))
    print("\n\n".join(blocks))
    return 0


if __name__ == "__main__":
    sys.exit(main())
