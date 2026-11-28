"""The next step each written surface names, for tests/guidance-agree.sh.

Usage: guidance_surfaces.py <plugin root> <template's AGENTS.md.jinja>

For each situation and each surface that speaks to it, prints one line,
tab-separated: <situation> <surface> <ok | missing: <token>, ...>, where a
token is the command or page the situation's next step is (#1146). The
words around it are not compared, only that the part of the surface about
that situation names each token.

The surfaces, and the part of each that is read:

- agents: the template's AGENTS.md, rendered for GitHub (each host test,
  `{% if gl %}a{% else %}b{% endif %}` or the older `host == 'gitlab'`, read
  as b, `{{ pr }}` as "pull request"), the bullet under "## Where you are"
  whose lead, before its first colon, matches the situation's;
- arsenal: skills/arsenal/SKILL.md, the stage table's row for the situation;
- run-a-project: docs/how-to/run-a-project.md, the section for it.

A part that cannot be found is printed as `missing: the part (<what was
looked for>)`, so a renamed heading fails rather than passes.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# situation: tokens, and where each surface speaks to it (None: it does not).
SITUATIONS = {
    "which-tool": (
        ["/plinth:guide"],
        {
            "agents": r"which tool|choosing a tool",
            "arsenal": "Unsure which skill now",
            "run-a-project": "#intro",
        },
    ),
    "main-broke": (
        ["undo-a-merged-change.md"],
        {
            "agents": "Something is broken",
            "arsenal": "Something broke",
            "run-a-project": "### 7.",
        },
    ),
    "diagnose": (
        ["diagnose this"],
        {
            "agents": "Something is broken",
            "arsenal": "Something broke",
            "run-a-project": "### 7.",
        },
    ),
    "implement": (
        ["/clear", "/implement"],
        {
            "agents": r"implementing a ticket|adding to what exists",
            "arsenal": "A ticket ready",
            "run-a-project": "### 4.",
        },
    ),
    "coming-back": (
        ["/plinth:guide"],
        {
            "agents": "Coming back",
            "arsenal": "Stopping, or coming back",
            "run-a-project": "### 8.",
        },
    ),
    "look-back": (
        ["/plinth:floor-check", "look back"],
        {
            "agents": r"look back",
            "arsenal": "Between pieces of work",
            "run-a-project": "### 9.",
        },
    ),
}


# The host test, as the template has written it: `{% if gl %}` (with `gl` set
# from host) and, before, `{% if host == 'gitlab' %}`.
GITLAB = r"\{%\s*if (?:gl|host == ['\"]gitlab['\"])\s*%\}"


def render_github(text: str) -> str:
    """The template's GitHub render, near enough to read its words."""
    text = re.sub(
        GITLAB + r"(.*?)\{%\s*else\s*%\}(.*?)\{%\s*endif\s*%\}",
        r"\2",
        text,
        flags=re.DOTALL,
    )
    text = re.sub(GITLAB + r".*?\{%\s*endif\s*%\}", "", text, flags=re.DOTALL)
    text = re.sub(r"\{\{\s*pr\s*\}\}", "pull request", text)
    return re.sub(r"\{%.*?%\}", "", text)


def agents_part(text: str, lead: str) -> str | None:
    """The bullet under ## Where you are whose lead (the words before its first
    colon) matches `lead`, wrapped lines and all: its words have changed with
    the template ("choosing a tool", then "which tool now")."""
    m = re.search(r"^## Where you are\n(.*?)(?=^## )", text, re.DOTALL | re.MULTILINE)
    if not m:
        return None
    bullets = re.split(r"\n(?=- )", m.group(1).strip())
    return next(
        (b for b in bullets if re.search(lead, b.split(":", 1)[0], re.IGNORECASE)), None
    )


def arsenal_part(text: str, lead: str) -> str | None:
    return next(
        (line for line in text.splitlines() if line.startswith("| " + lead)), None
    )


def guide_part(text: str, heading: str) -> str | None:
    if heading == "#intro":
        m = re.search(r"\A(.*?)(?=^## )", text, re.DOTALL | re.MULTILINE)
        return m.group(1) if m else None
    m = re.search(
        rf"^{re.escape(heading)}.*?(?=^#{{2,3}} )",
        text + "\n## end",
        re.DOTALL | re.MULTILINE,
    )
    return m.group(0) if m else None


def main() -> None:
    root, agents = Path(sys.argv[1]), Path(sys.argv[2])
    texts = {
        "agents": render_github(agents.read_text(encoding="utf-8")),
        "arsenal": (root / "skills/arsenal/SKILL.md").read_text(encoding="utf-8"),
        "run-a-project": (root / "docs/how-to/run-a-project.md").read_text(
            encoding="utf-8"
        ),
    }
    find = {"agents": agents_part, "arsenal": arsenal_part, "run-a-project": guide_part}
    for situation, (tokens, where) in SITUATIONS.items():
        for surface, lead in where.items():
            part = find[surface](texts[surface], lead)
            if part is None:
                print(f"{situation}\t{surface}\tmissing: the part ({lead})")
                continue
            lacking = [t for t in tokens if t.lower() not in part.lower()]
            print(
                f"{situation}\t{surface}\t"
                + ("ok" if not lacking else "missing: " + ", ".join(lacking))
            )


if __name__ == "__main__":
    main()
