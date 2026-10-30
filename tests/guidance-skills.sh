#!/usr/bin/env bash
# The guidance names only skills a default install carries (#714), offline.
# Read: the arsenal's "Where you are, and what to do next" table, which
# /plinth:guide prints, and every passage of the workflow how-to and the guide
# skill that speaks of looking back. A slash command there must be one of
# plinth's skills, a skill of a dependency plugin.json names (as the
# marketplace mounts it), a Claude Code built-in the table uses, or, in the
# table only, marked "(listed)". Each of the three also names `/retro`, the
# retrospective's tool. The template's end-or-hand-over form is read against
# the installed skills by tests/install-smoke.sh, which has them.
# Must-not-pass cases run first.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$root" <<'PY'
import json, re, sys
from pathlib import Path

root = Path(sys.argv[1])
BUILT_IN = {"clear", "design", "run", "context"}
plugin = json.loads((root / ".claude-plugin/plugin.json").read_text())
entries = {e["name"]: e for e in json.loads((root / ".claude-plugin/marketplace.json").read_text())["plugins"]}
default = {"plinth:" + d.name for d in (root / "skills").iterdir() if d.is_dir()}
for dep in plugin["dependencies"]:
    e = entries[dep if isinstance(dep, str) else dep["name"]]
    for s in e["skills"]:
        default.add(s.rsplit("/", 1)[1])
    # An entry that mounts one directory under another name says the name.
    default.update(re.findall(r"skill, ([a-z][a-z-]+):", e["description"]))

COMMAND = re.compile(r"`/([a-z][a-z0-9:-]*)[^`]*`( \(listed\))?")


def table(text):
    m = re.search(r"^## Where you are, and what to do next\n(.*?)(?=^## )", text, re.M | re.S)
    return [l for l in (m.group(1) if m else "").splitlines() if l.startswith("| ")]


def looking_back(text):
    """The passages, paragraphs or list items, that speak of looking back."""
    blocks = re.split(r"\n\s*\n|\n(?=\s*- )", text)
    return [b for b in blocks if re.search(r"retrospective|looking back", b, re.I)]


def problems(arsenal, howto, guide):
    out = []
    rows = table(arsenal)
    if not rows:
        out.append("no 'Where you are, and what to do next' table")
    for where, passages, listed_ok in (("the arsenal's table", rows, True),
                                       ("the how-to", looking_back(howto), False),
                                       ("the guide", looking_back(guide), False)):
        for p in passages:
            for name, listed in COMMAND.findall(p):
                if name in default or name in BUILT_IN or (listed and listed_ok):
                    continue
                out.append(f"{where} names /{name}, which the default install does not carry")
    for where, text in (("the arsenal", arsenal), ("the how-to", howto), ("the guide", guide)):
        if "`/retro`" not in text:
            out.append(f"{where} does not name `/retro`, the retrospective's tool")
    return out


arsenal = (root / "skills/arsenal/SKILL.md").read_text()
howto = (root / "docs/how-to/run-a-project.md").read_text()
guide = (root / "skills/guide/SKILL.md").read_text()
row = "| Looking back on a piece of work (retrospective) |"
fails = 0


def case(name, got, want):
    """want: the text one problem must carry, or None for no problem at all."""
    global fails
    hit = not got if want is None else any(want in g for g in got)
    if hit:
        print(f"  PASS  {name}" + (f": {got[0]}" if got else ""))
    else:
        fails += 1
        print(f"  FAIL  {name}: {got or 'nothing found'}")


def problems_without(skill):
    """The real texts, with one skill taken out of the default set."""
    global default
    kept = default
    default = kept - {skill}
    try:
        return problems(arsenal, howto, guide)
    finally:
        default = kept


assert row in arsenal, "the retrospective row moved; update this test"
case("must fail: the table names a skill upstream added and plinth does not install",
     problems(arsenal.replace(row, row + " `/implement-spec` |", 1), howto, guide), "/implement-spec")
case("must fail: the table names a skill upstream removed",
     problems(arsenal.replace(row, row + " `/resolving-merge-conflicts` |", 1), howto, guide),
     "/resolving-merge-conflicts")
case("must fail: a looking-back passage of the how-to names a listed skill",
     problems(arsenal, howto + "\n\nLooking back: type `/ask-matt`.\n", guide), "the how-to names /ask-matt")
case("must fail: the guide's looking-back line names an uninstalled skill",
     problems(arsenal, howto, guide + "\n- Looking back: type `/pr`.\n"), "the guide names /pr")
case("must fail: the how-to no longer names /retro",
     problems(arsenal, howto.replace("`/retro`", "it"), guide), "the how-to does not name `/retro`")
case("must fail: retro is not in the default install",
     problems_without("retro"), "names /retro, which the default install does not carry")
case("the arsenal's table, the how-to and the guide name only default skills, and /retro",
     problems(arsenal, howto, guide), None)
print(f"-- {fails} failed")
sys.exit(1 if fails else 0)
PY
