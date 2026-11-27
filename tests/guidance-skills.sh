#!/usr/bin/env bash
# The guidance names only skills a default install carries (#714), offline.
# Read: the arsenal's "Where you are, and what to do next" table, which
# /plinth:guide prints, and every passage of the workflow how-to and the guide
# skill that speaks of looking back. A slash command there must be one of
# plinth's skills, a skill of a dependency plugin.json names (as the
# marketplace mounts it), a Claude Code built-in the table uses, or, in the
# table only, marked "(listed)". Each of the three also names `/retro`, the
# retrospective's tool. The built-ins #1080 placed stay marked "(built in" in
# their rows: `/security-review` at step 5, `/resume` and `/recap` (same
# machine only) at step 8, `/insights` on the retrospective row, `/doctor`
# under "Something broke"; and `/debug`, which debugs Claude Code, appears
# in the table only as that one clause, never as a tool for the app. The template's end-or-hand-over form is read against
# the installed skills by tests/install-smoke.sh, which has them.
# The arsenal's not-used.md (#1086): each entry is "- `/<name>` (<class>).
# Breaks: <rule>.", its class "built in" or "installed by plinth" (a tool that
# needs installing is not listed), true of the name, and the tool is named in
# no row of the "Where you are" table.
# No text gives the look back a cadence of its own (#1145): "every week or
# two" is gone from the arsenal's pages, the how-to and the guide, since
# /plinth:guide says when a look back is due.
# Must-not-pass cases run first.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$root" <<'PY'
import json, re, sys
from pathlib import Path

root = Path(sys.argv[1])
BUILT_IN = {"clear", "design", "run", "context", "security-review", "resume", "recap", "insights", "doctor", "debug", "rewind", "usage"}
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


# Every skill the marketplace carries that the default install does not.
listed_skills = {s.rsplit("/", 1)[1] for e in entries.values() for s in e.get("skills", [])} - default
# What plinth installs or lists, in the arsenal's own words: a name there is
# not "built in", whether or not the marketplace mounts it.
catalog = (root / "skills/arsenal/installed.md").read_text() + (root / "skills/arsenal/listed.md").read_text()
NOT_USED = re.compile(r"^- `/([a-z][a-z0-9:-]*)` \((built in|installed by plinth)\)\. Breaks: (\S.*)$")


def not_used_problems(text, rows):
    out = []
    entries_ = [l for l in text.splitlines() if l.startswith("- ")]
    if not entries_:
        out.append("not-used.md lists no tool: the line was not read")
    for l in entries_:
        m = NOT_USED.match(l)
        if not m:
            out.append(f"a not-used entry without its class (built in, or installed by plinth) and the rule it breaks: {l[:70]}")
            continue
        name, cls = m.group(1), m.group(2)
        if cls == "installed by plinth" and name not in default:
            out.append(f"not-used marks /{name} installed by plinth, and the default install does not carry it")
        if cls == "built in" and (name in default or name in listed_skills or name in entries
                                  or f"`{name}`" in catalog or f"`/{name}`" in catalog):
            out.append(f"not-used marks /{name} built in, and it is a skill plinth installs or lists")
        for r in rows:
            if f"`/{name}`" in r or f"`/{name} " in r:
                out.append(f"/{name} is on the not-used line and in the table: {r[:60]}")
    # Every tool the file names is an entry: one in another shape escapes nothing.
    named = set(re.findall(r"`/([a-z][a-z0-9:-]*)", text))
    entered = {m.group(1) for m in map(NOT_USED.match, entries_) if m}
    for name in sorted(named - entered):
        out.append(f"not-used.md names /{name} outside an entry with its class and rule")
    return out


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
    out += built_ins(rows)
    return out


# The one clause the table may say `/debug` in (#1080).
DEBUG_CLAUSE = "`/debug` (built in) is for Claude Code itself, not the app"
# The row's start, then what it must say: a built-in and its mark (#1080).
PLACED = (("| A pull request with checks running (step 5) |", "`/security-review` (built in"),
          ("| Stopping, or coming back (step 8) |", "`/resume` and `/recap` (built in, same machine only"),
          ("| Looking back on a piece of work (retrospective) |", "`/insights` (built in"),
          ("| Something broke (step 7) |", "`/doctor` (built in"),
          ("| Something broke (step 7) |", DEBUG_CLAUSE),
          ("| Something broke (step 7) |", "`/rewind` (built in) rolls back the agent's own edits in this session and never undoes a merge"))


def built_ins(rows):
    out = []
    for start, says in PLACED:
        row = next((r for r in rows if r.startswith(start)), None)
        if row is None:
            out.append(f"no row starting {start!r}")
        elif says not in row:
            out.append(f"the row {start!r} no longer says {says!r}")
    for r in rows:
        # "`/debug" with no closing backtick: `/debug <args>` counts too.
        if r.count("`/debug") != r.count(DEBUG_CLAUSE):
            out.append(f"a 'Where you are' cell names `/debug` other than as {DEBUG_CLAUSE!r}: {r[:60]}")
        # /rewind once, in the "Something broke" row only (#1079): it is the
        # session's undo, and a second mention invites it for a merge.
        n = r.count("`/rewind")
        if n and not r.startswith("| Something broke (step 7) |"):
            out.append(f"a row other than 'Something broke' names `/rewind`: {r[:60]}")
        elif r.startswith("| Something broke (step 7) |") and n != 1:
            out.append(f"the 'Something broke' row names `/rewind` {n} times, not once")
    return out


arsenal = (root / "skills/arsenal/SKILL.md").read_text()
not_used = (root / "skills/arsenal/not-used.md").read_text()
howto = (root / "docs/how-to/run-a-project.md").read_text()
guide = (root / "skills/guide/SKILL.md").read_text()
pages = {f"skills/arsenal/{f.name}": f.read_text() for f in sorted((root / "skills/arsenal").glob("*.md"))}
pages["docs/how-to/run-a-project.md"] = howto
pages["skills/guide/SKILL.md"] = guide


def cadence(texts):
    return [f"{name} gives a cadence of its own: 'every week or two'" for name, t in texts.items()
            if "every week or two" in t.lower()]
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
step5 = "| A pull request with checks running (step 5) |"
broke = "| Something broke (step 7) |"
case("must fail: /security-review leaves the step 5 row",
     problems(arsenal.replace("`/security-review` (built in", "a security pass (built in"), howto, guide),
     "no longer says '`/security-review` (built in'")
case("must fail: a cell offers /debug for the app",
     problems(arsenal.replace(broke, broke + " Type `/debug` to find the app's bug;", 1), howto, guide),
     "names `/debug` other than")
case("must fail: a cell offers /debug with arguments for the app",
     problems(arsenal.replace(broke, broke + " type `/debug the app's crash`;", 1), howto, guide),
     "names `/debug` other than")
case("must fail: the /debug clause loses 'not the app'",
     problems(arsenal.replace(DEBUG_CLAUSE, "`/debug` (built in) debugs it"), howto, guide), "names `/debug` other than")
case("must fail: /rewind named twice in the Something broke row",
     problems(arsenal.replace(broke, broke + " type `/rewind` to undo the merge;", 1), howto, guide), "names `/rewind` 2 times")
case("must fail: /rewind gone from the Something broke row",
     problems(arsenal.replace("`/rewind` (built in) rolls back", "a rewind rolls back"), howto, guide), "`/rewind` (built in) rolls back")
case("must fail: step 8 drops 'same machine only'",
     problems(arsenal.replace("(built in, same machine only", "(built in"), howto, guide), "/recap")
assert step5 in arsenal and broke in arsenal, "a row #1080 placed a built-in in moved; update this test"
case("the arsenal's table, the how-to and the guide name only default skills, and /retro",
     problems(arsenal, howto, guide), None)
rows = table(arsenal)
ship = "- `/ship` (built in). Breaks: "
assert ship in not_used, "the /ship entry moved; update this test"
ship_line = next(l for l in not_used.splitlines() if l.startswith(ship))
case("must fail: a not-used entry with no class",
     not_used_problems(not_used.replace(ship, "- `/ship`. Breaks: "), rows), "without its class")
case("must fail: a not-used entry with no rule",
     not_used_problems(not_used.replace(ship_line, "- `/ship` (built in)."), rows), "without its class")
case("must fail: a not-used entry with an empty rule",
     not_used_problems(not_used.replace(ship_line, "- `/ship` (built in). Breaks: "), rows), "without its class")
case("must fail: a not-used tool that needs installing",
     not_used_problems(not_used + "\n- `/ponytail-audit` (listed). Breaks: it is not installed.\n", rows), "without its class")
case("must fail: a listed skill called built in",
     not_used_problems(not_used + "\n- `/ask-matt` (built in). Breaks: it routes elsewhere.\n", rows), "plinth installs or lists")
case("must fail: a listed plugin with no marketplace skills called built in",
     not_used_problems(not_used + "\n- `/last30days` (built in). Breaks: x.\n", rows), "plinth installs or lists")
case("must fail: a tool named in another shape than an entry",
     not_used_problems(not_used + "\n1. `/rename`, which renames the session.\n", rows), "outside an entry")
case("must fail: a skill called installed by plinth that the default install does not carry",
     not_used_problems(not_used + "\n- `/ask-matt` (installed by plinth). Breaks: it routes elsewhere.\n", rows), "does not carry it")
case("must fail: a not-used tool named in a Tool cell",
     not_used_problems(not_used, [r.replace("| `/plinth:guide`, typed by the person |", "| `/ship`, typed by the person |") for r in rows]),
     "/ship is on the not-used line and in the table")
case("must fail: a not-used.md with no entries",
     not_used_problems("# Not used with plinth\n\nNothing.\n", rows), "lists no tool")
case("not-used.md: each entry has its class and its rule, and none is in the table",
     not_used_problems(not_used, rows), None)
case("must fail: the how-to says every week or two again",
     cadence({**pages, "docs/how-to/run-a-project.md": howto + "\nEvery week or two, look back.\n"}), "every week or two")
case("no page gives the look back a cadence of its own", cadence(pages), None)
print(f"-- {fails} failed")
sys.exit(1 if fails else 0)
PY
