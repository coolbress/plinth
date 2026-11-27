#!/usr/bin/env bash
# The guidance names only skills a default install carries (#714), offline.
# Read: the arsenal's "Where you are, and what to do next" table, which
# /plinth:guide prints, and every passage of the workflow how-to and the guide
# skill that speaks of looking back. A slash command there must be one of
# plinth's skills, a skill of a dependency plugin.json names (as the
# marketplace mounts it), a Claude Code built-in the table uses, or, in the
# table only, marked "(listed)". Each of the three also names `/retro`, the
# retrospective's tool. The table's columns (#1086): one tool per job in the
# Tool cell, a class for each job in Class (installed, built in, platform,
# listed), and at most one tool with its class and condition in Also. The
# built-ins #1080 and #1086 placed stay "built in" in their rows with their
# words: `/security-review` at step 5, `/resume` and `/recap` (same machine
# only) at step 8, `/insights` on the retrospective row, `/doctor` and
# `/rewind` under "Something broke", `/design` on the idea row, `/simplify`
# on the build and check rows; `/debug`, which debugs Claude Code, is in no
# row. The template's end-or-hand-over form is read against
# the installed skills by tests/install-smoke.sh, which has them.
# The arsenal's not-used.md (#1086): each entry is "- `/<name>` (<class>).
# Breaks: <rule>.", its class "built in" or "installed by plinth" (a tool that
# needs installing is not listed), true of the name, and the tool is named in
# no row of the "Where you are" table, Tool or Also.
# Must-not-pass cases run first.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$root" <<'PY'
import json, re, sys
from pathlib import Path

root = Path(sys.argv[1])
BUILT_IN = {"clear", "design", "run", "context", "security-review", "resume", "recap", "insights", "doctor", "debug", "rewind",
            "simplify", "verify"}
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


# The stage table's columns (#1086): Trigger | Tool | Class | plinth piece |
# Also | Then. Tool holds one tool per job, jobs apart by "; ", each job's
# tool before its ": " (a sequence "X, then Y" is one job); Class has one
# class per job in the same order; Also is `-` or one tool, "(class)" and a
# condition after ": ".
CLASSES = {"installed", "built in", "platform", "listed"}
ALSO = re.compile(r"^`[^`]+` \((installed|built in|platform|listed)\): \S")


def cells(row):
    return row[2:-2].split(" | ")


def tool_names(text):
    """The tools a text names: each backticked span that is a slash command or
    a skill or plugin plinth installs or lists, by its first word."""
    out = []
    for span in re.findall(r"`([^`]+)`", text):
        word = span.split()[0].lstrip("/")
        if span.startswith("/") or word in default or word in listed_skills or word in entries:
            out.append(word)
    return out


def class_for(name):
    """The class a tool has by what plinth installs or lists, or None."""
    if name in default or "plinth:" + name in default:
        return "installed"
    if name in BUILT_IN:
        return "built in"
    if name in listed_skills or name in entries:
        return "listed"
    return None


def job_problems(trig, where, text, cls):
    """One job, or the Also cell: each part of a sequence names at most one
    tool anywhere in its text, and its class is the class that tool has."""
    out = []
    parts = text.split(", then ")
    kinds = cls.split(", then ")
    if len(kinds) not in (1, len(parts)):
        out.append(f"{trig}: {len(parts)} steps in a {where} job and {len(kinds)} classes for it")
        return out
    for i, part in enumerate(parts):
        names = tool_names(part)
        if len(names) > 1 or " or `" in part:
            out.append(f"{trig}: a {where} cell names two tools for one job: {part[:70]}")
            continue
        k = kinds[i] if len(kinds) > 1 else kinds[0]
        if k not in CLASSES:
            out.append(f"{trig}: the class {k!r} is not one of {sorted(CLASSES)}")
            continue
        want = class_for(names[0]) if names else "platform"
        if want is None:
            out.append(f"{trig}: `{names[0]}` in a {where} cell is neither installed, built in nor listed")
        elif want != k:
            out.append(f"{trig}: the class of {names[0] if names else part[:40]!r} is {k!r}, and it is {want}")
    return out


def columns(rows):
    out = []
    for r in rows[2:]:
        c = cells(r)
        if len(c) != 6:
            out.append(f"a row without six cells: {r[:60]}")
            continue
        trig, tool, cls, _, also, _ = c
        jobs = [] if tool == "-" else tool.split("; ")
        classes = [] if cls == "-" else cls.split("; ")
        if len(jobs) != len(classes):
            out.append(f"{trig}: {len(jobs)} jobs in Tool and {len(classes)} classes in Class")
        else:
            for j, k in zip(jobs, classes):
                out += job_problems(trig, "Tool", j, k)
        if also != "-":
            m = ALSO.match(also)
            if not m:
                out.append(f"{trig}: the Also cell is not one tool, its class and a condition: {also[:60]}")
            elif len(tool_names(also)) > 1:
                # One alternative, so no sequence: every tool in the whole
                # cell counts, ", then" or not.
                out.append(f"{trig}: the Also cell names more than one tool: {also[:70]}")
            else:
                out += job_problems(trig, "Also", also, m.group(1))
    return out


def class_of(rows, start, name):
    """The class the row starting with start gives the tool name, in Tool or Also."""
    row = next((r for r in rows if r.startswith(start)), None)
    if row is None or len(cells(row)) != 6:
        return None
    _, tool, cls, _, also, _ = cells(row)
    for j, k in zip(tool.split("; "), cls.split("; ")):
        if f"`{name}`" in j.split(": ", 1)[0] or f"`{name} " in j.split(": ", 1)[0]:
            return k.split(", then ")[-1] if ", then " in j else k
    m = ALSO.match(also)
    if m and also.startswith(f"`{name}`"):
        return m.group(1)
    return None


# The built-ins placed in the table (#1080, #1086): the row, the tool, and the
# words its job or condition keeps.
PLACED = (("| A pull request with checks running (step 5) |", "/security-review", "before the merge"),
          ("| A pull request with checks running (step 5) |", "/simplify", "cleanup of the changed code"),
          ("| A ticket ready (step 4) |", "/simplify", "cleanup of the changed code"),
          ("| An idea in your own words (step 2) |", "/design", "v2.1.265 or later and an account where the Design template is available"),
          ("| Stopping, or coming back (step 8) |", "/resume", "same machine only"),
          ("| Stopping, or coming back (step 8) |", "/recap", "same machine only"),
          ("| Looking back on a piece of work (retrospective) |", "/insights", "not in cloud sessions"),
          ("| Something broke (step 7) |", "/doctor", "not the app"),
          ("| Something broke (step 7) |", "/rewind", "never a merge"))


def built_ins(rows):
    out = columns(rows)
    for start, name, says in PLACED:
        row = next((r for r in rows if r.startswith(start)), "")
        if class_of(rows, start, name) != "built in":
            out.append(f"the row {start!r} no longer gives `{name}` as built in")
        elif not re.search(re.escape(f"`{name}`") + r"[^;|]*" + re.escape(says), row):
            out.append(f"the row {start!r} no longer says {says!r} of `{name}`")
    for r in rows:
        # /debug debugs Claude Code, never the app (#1080): installed.md says
        # so, and no row offers it.
        if "`/debug" in r:
            out.append(f"a 'Where you are' row names `/debug`, which debugs Claude Code, not the app: {r[:60]}")
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
     problems(arsenal.replace("`/security-review`: a security pass", "a security pass"), howto, guide),
     "no longer gives `/security-review` as built in")
case("must fail: /security-review marked installed",
     problems(arsenal.replace("| platform; built in; built in |", "| platform; built in; installed |"), howto, guide),
     "no longer gives `/security-review` as built in")
case("must fail: a row offers /debug for the app",
     problems(arsenal.replace("`/doctor`: Claude Code itself", "`/debug`: the app's bug; `/doctor`: Claude Code itself"), howto, guide),
     "names `/debug`")
case("must fail: /rewind named twice in the Something broke row",
     problems(arsenal.replace(broke, broke + " type `/rewind` to undo the merge;", 1), howto, guide), "names `/rewind` 2 times")
case("must fail: /rewind loses 'never a merge'",
     problems(arsenal.replace("never a merge", "any edit"), howto, guide), "'never a merge'")
case("must fail: step 8 drops 'same machine only'",
     problems(arsenal.replace("summary of this one, same machine only", "summary of this one"), howto, guide), "of `/recap`")
case("must fail: /design loses its conditions",
     problems(arsenal.replace(", with Claude Code v2.1.265 or later and an account where the Design template is available", ""), howto, guide),
     "of `/design`")
case("must fail: /simplify leaves the build row",
     problems(arsenal.replace("| `/simplify` (built in): cleanup of the changed code | A pull request with checks running |", "| - | A pull request with checks running |"), howto, guide),
     "'| A ticket ready (step 4) |' no longer gives `/simplify`")
case("must fail: a Tool cell names two tools for one job, with 'or'",
     problems(arsenal.replace("`/to-spec`, then `/to-tickets` |", "`/to-spec` or `/wayfinder` |"), howto, guide), "two tools for one job")
case("must fail: a Tool cell names two tools for one job, side by side",
     problems(arsenal.replace("`/grilling`: an interview", "`/grilling`, `/grill-with-docs` (listed): an interview"), howto, guide),
     "two tools for one job")
case("must fail: a job with no class",
     problems(arsenal.replace("| platform; installed; installed; built in; built in |", "| platform; installed; installed; built in |"), howto, guide),
     "5 jobs in Tool and 4 classes")
case("must fail: a class outside the four",
     problems(arsenal.replace("| `/grilling`: an interview before any code | installed |", "| `/grilling`: an interview before any code | bundled |"), howto, guide),
     "the class 'bundled'")
case("must fail: a second tool after a job's colon",
     problems(arsenal.replace("what is out of place in it, read-only", "what is out of place in it, read-only, or `/ponytail-audit` (listed) instead"), howto, guide),
     "two tools for one job")
case("must fail: a second tool in an Also cell's condition",
     problems(arsenal.replace("(installed): when the code has grown hard to change", "(installed): when unsure use `/ask-matt` (listed), or when the code has grown hard to change"), howto, guide),
     "the Also cell names more than one tool")
case("must fail: an installed tool marked listed",
     problems(arsenal.replace("| `/retro`: it reads the session and suggests rules and checks, most serious first, and changes nothing | installed |",
                              "| `/retro`: it reads the session and suggests rules and checks, most serious first, and changes nothing | listed |"), howto, guide),
     "is 'listed', and it is installed")
case("must fail: an installed sequence marked built in",
     problems(arsenal.replace("| `/to-spec`, then `/to-tickets` | installed |", "| `/to-spec`, then `/to-tickets` | built in |"), howto, guide),
     "is 'built in', and it is installed")
case("must fail: a platform job marked installed",
     problems(arsenal.replace("then its logs; `/triage`: what users report, written as an issue | platform; installed |",
                              "then its logs; `/triage`: what users report, written as an issue | installed; installed |"), howto, guide),
     "and it is platform")
case("must fail: a sequence with a class for one step of two",
     problems(arsenal.replace("| built in, then installed; installed |", "| built in, then installed, then listed; installed |"), howto, guide),
     "2 steps in a Tool job and 3 classes")
case("must fail: an Also cell with a second tool after ', then'",
     problems(arsenal.replace("`/handoff` (installed): when another person or tool takes it over |",
                              "`/handoff` (installed): when another person or tool takes it over, then `/retro` |"), howto, guide),
     "the Also cell names more than one tool")
case("must fail: an Also cell with two tools",
     problems(arsenal.replace("`/wayfinder` (installed): when the way is unclear", "`/wayfinder` (installed) or `/ask-matt`: when the way is unclear"), howto, guide),
     "the Also cell is not one tool")
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
     not_used_problems(not_used, [r.replace("| `/plinth:guide`, typed by the person", "| `/ship`, typed by the person") for r in rows]),
     "/ship is on the not-used line and in the table")
case("must fail: a not-used tool named in an Also cell",
     not_used_problems(not_used, [r.replace("`/wayfinder` (installed)", "`/steward` (built in)") for r in rows]),
     "/steward is on the not-used line and in the table")
case("must fail: a not-used.md with no entries",
     not_used_problems("# Not used with plinth\n\nNothing.\n", rows), "lists no tool")
case("not-used.md: each entry has its class and its rule, and none is in the table",
     not_used_problems(not_used, rows), None)
print(f"-- {fails} failed")
sys.exit(1 if fails else 0)
PY
