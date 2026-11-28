#!/usr/bin/env python3
"""The Retired entries table of docs/reference/dependency-entries.md (#1229),
one row a line, tab-separated: name, kind (`removed` or `dropped`), the
release it left in, what replaced it (`-` for none), and the command an
installed user runs.

    scripts/retired-entries.py [<root>]

Read by tests/marketplace-manifest.sh, scripts/make-release.sh and
tests/install-smoke.sh. Exits 1, naming the line, on a row it cannot read:
a table that does not read is never an empty one."""
from __future__ import annotations

import re
import sys
from pathlib import Path

KINDS = {"entry removed": "removed", "dependency dropped": "dropped"}
CODE = re.compile(r"^`([^`]+)`$")


def rows(text: str) -> list[dict[str, str]]:
    """The rows under `## Retired entries`; ValueError on one that does not read."""
    m = re.search(r"^## Retired entries\n(.*?)(?=^## |\Z)", text, re.MULTILINE | re.DOTALL)
    if not m:
        raise ValueError("no '## Retired entries' section")
    out: list[dict[str, str]] = []
    header = False
    for line in m.group(1).splitlines():
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if cells[0] == "Name":
            header = True
            continue
        if set("".join(cells)) <= set("- "):
            continue
        if not header or len(cells) != 6:
            raise ValueError(f"a row that does not read: {line}")
        name, kind, left, replaced, _issue, command = cells
        n, c = CODE.match(name), CODE.match(command)
        if not n or kind not in KINDS or not c or not re.fullmatch(r"v\d+\.\d+\.\d+", left):
            raise ValueError(f"a row that does not read: {line}")
        r = CODE.match(replaced)
        out.append({"name": n.group(1), "kind": KINDS[kind], "left": left,
                    "replaced": r.group(1) if r else "-", "command": c.group(1)})
    if not header:
        raise ValueError("no table under '## Retired entries'")
    return out


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent)
    try:
        found = rows((root / "docs/reference/dependency-entries.md").read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        print(f"retired-entries: {e}", file=sys.stderr)
        return 1
    for r in found:
        print("\t".join((r["name"], r["kind"], r["left"], r["replaced"], r["command"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
