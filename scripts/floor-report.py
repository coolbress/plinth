#!/usr/bin/env python3
"""The short report /plinth:floor-check gives, made from one run of
scripts/floor-check.py --format json (read on stdin or from a file).

    floor-check.py ... --format json | floor-report.py --root .
    floor-report.py --root . [--all | --area <area>] [--no-note] [run.json]

It prints, in English for the skill to say in the person's language:
  - one verdict line;
  - at most five action rows, those that cannot be undone or reach others
    first, each one of three kinds: do it yourself, one pull request, later;
  - "N more" naming every other finding;
  - since the last run, when there is one: fixed, still missing, new, by id;
  - one line for what could not be read, saying they are not failures and
    what would read them;
  - one line for what was not checked, saying it is not a problem;
  - whether the merge is guidance or a boundary for the agent's login;
  - the passes as one line;
  - where to go next, `/plinth:guide`;
  - one question, last.
No check id appears in it. --all prints every result the run reported, the
PASS lines included; --area one area's results the same way.

The last run is kept in one note on this machine,
$XDG_CACHE_HOME/plinth/<host>-<owner>-<repo>/floor.json (~/.cache without
it), and written only from a run on the repository's default branch with a
clean working tree; nothing is written in the repository. --no-note neither
reads nor writes it. Standard library only.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROWS = 5
# A check's hand-off, as the row's kind: what the person reads in the row.
KINDS = {"agent": "pr", "person": "you", "admin": "you", "ci": "later"}
KIND_TEXT = {"pr": "I can do it in one pull request",
             "you": "Do it yourself",
             "later": "Later, after the next `ci / floor-check` run on the default branch"}
# Results the report leaves to the JSON and --all: facts, not findings (#1105).
JSON_ONLY = {("FC-G10", "github"), ("FC-G10", "gitlab"), ("FC-G10", "askpass"),
             ("FC-E06", "expect"), ("FC-E30", "good"), ("FC-G02", "current"), ("FC-G02", "other"),
             ("FC-C03", "none"), ("FC-C26", "good"), ("FC-E07", "where"),
             # The checker does not read whether the owner's shared set has a
             # form the local set lacks, the one case #1105 shows it in.
             ("FC-A11", "info")}
JSON_ONLY_IDS = {"FC-G06", "FC-G07", "FC-G08", "FC-G09", "FC-G11"}   # the clean-credential INFOs


def json_only(r: dict) -> bool:
    if (r["id"], r["key"]) in JSON_ONLY:
        return True
    return r["id"] in JSON_ONLY_IDS and r["state"] in ("info", "pass")


def first_line(r: dict) -> str:
    return r["message"].split("\n", 1)[0].strip()


def findings(results: list[dict]) -> list[dict]:
    """Each failed or warned check once, in the run's order, with the
    indented lines under it (its fix lines) and the parts that failed."""
    out: dict[str, dict] = {}
    last = None
    for r in results:
        indented = r["message"].startswith("  ")
        if r["state"] in ("fail", "warn") and not json_only(r):
            f = out.setdefault(r["id"], {"id": r["id"], "name": r["name"], "state": r["state"],
                                         "handoff": r["handoff"], "keepable": r["keepable"],
                                         "ci_visible": r["ci_visible"], "area": r["area"],
                                         "fix": r["fix"], "parts": [], "lines": []})
            if r["state"] == "fail":
                f["state"] = "fail"
            f["parts"].append(first_line(r))
            last = f
        elif indented and last is not None and r["id"] == last["id"]:
            last["lines"].append(r["message"].strip())
        else:
            last = None
    return list(out.values())


def rank(f: dict) -> tuple:
    # Irreversible or reaching others first, then failures, then what CI
    # does not show (the reads only this run makes), then the run's order.
    return (f["keepable"], f["state"] != "fail", f["ci_visible"])


def rows(fs: list[dict]) -> list[dict]:
    """The action rows: every pull-request finding is one row; each other
    finding is its own."""
    out: list[dict] = []
    pr: dict | None = None
    for f in sorted(fs, key=rank):
        kind = KINDS[f["handoff"]]
        # One that cannot be kept (a tracked secret, say) keeps its own row
        # and its lines: what the pull request cannot undo is in them.
        if kind == "pr" and f["keepable"]:
            if pr is None:
                pr = {"kind": "pr", "members": []}
                out.append(pr)
            pr["members"].append(f)
        else:
            out.append({"kind": kind, "members": [f]})
    return out


def row_text(row: dict, branch: str | None = None) -> list[str]:
    if row["kind"] == "pr" and (len(row["members"]) > 1 or row["members"][0]["keepable"]):
        parts = "; ".join("; ".join(f["parts"]) for f in row["members"])
        return [f"{KIND_TEXT['pr']}: {parts}."]
    f = row["members"][0]
    on = f" (the wall is read on {branch})" if branch and f["area"] == "wall" else ""
    text = [f"{KIND_TEXT[row['kind']]}: {'; '.join(f['parts'])}{on}."]
    text += [f"   {line}" for line in f["lines"][:3]]
    return text


# What stands in, in the repository's own checks, for a read no change here clears.
STANDS_IN = {"FC-E09": "`ci / secrets` stands in for push protection",
             "FC-E21": "`ci / lint`'s security rules stand in for CodeQL",
             "FC-E23": "`ci / lint`'s security rules stand in for CodeQL"}


def reasons(unknowns: list[dict]) -> str:
    out = []
    for r in unknowns:
        if r["state"] == "review":
            why = f"a run of {r['reader']}"
        elif r["cannot_be_read_here"]:
            why = STANDS_IN.get(r["id"], "nothing on this machine or in this repository can read it")
        else:
            why = r["reason"]
        if why not in out:
            out.append(why)
    return "; ".join(out)


def cache_dir() -> Path:
    base = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    return Path(base) / "plinth"


def note_path(doc: dict) -> Path | None:
    if not doc.get("repo"):
        return None
    return cache_dir() / f"{doc['host']}-{doc['repo'].replace('/', '-')}" / "floor.json"


def git(root: str, *args: str) -> str | None:
    p = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True, check=False)
    return p.stdout.strip() if p.returncode == 0 else None


def default_branch(doc: dict, root: str) -> str | None:
    """The branch the wall was read on (from GitHub), else origin's HEAD."""
    for r in doc["results"]:
        if r["id"] == "FC-E07" and r["key"] == "where":
            return r["message"].split("the wall is checked on ", 1)[-1].split(",", 1)[0].strip()
    head = git(root, "symbolic-ref", "--short", "refs/remotes/origin/HEAD")
    return head.split("/", 1)[1] if head and "/" in head else None


def may_write_note(doc: dict, root: str) -> str | None:
    """None when this run may be the note; otherwise why not."""
    if doc.get("crashed"):
        return "the run stopped early"
    status = git(root, "status", "--porcelain")
    if status is None:
        return "not a git checkout"
    if status:
        return "the working tree has changes"
    branch, want = git(root, "rev-parse", "--abbrev-ref", "HEAD"), default_branch(doc, root)
    if not want:
        return "the default branch could not be read"
    if branch != want:
        return f"not on the default branch ({want})"
    return None


def unread_ids(doc: dict) -> set[str]:
    """Checks this run did not read: those it could not read, and those it
    did not evaluate at all (offline, the wall is one SKIP and its checks
    report nothing). A finding of the last run among them is neither fixed
    nor forgotten."""
    return ({r["id"] for r in doc["results"] if r["state"] in ("unknown", "review")}
            | {n["id"] for n in doc.get("not_evaluated", [])})


def note_of(doc: dict, root: str, prev: dict | None) -> dict:
    fs = findings([r for r in doc["results"] if r["area"] != "machine"])
    kept = {i: n for i, n in (prev or {}).get("findings", {}).items() if i in unread_ids(doc)}
    return {"schema": "floor-note/1", "when": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "commit": git(root, "rev-parse", "HEAD"), "findings": {**kept, **{f["id"]: f["name"] for f in fs}}}


def since(prev: dict, now: dict, doc: dict) -> str:
    a, b, unread = set(prev["findings"]), set(now["findings"]), unread_ids(doc)
    fixed, still, new = a - b - unread, a & b - unread, b - a
    gone = a & unread - {f["id"] for f in findings(doc["results"])}
    return (f"Since the last run ({prev['when'][:10]}): {len(fixed)} fixed, {len(still)} still missing, "
            f"{len(new)} new" + (f"; {len(gone)} not read this time, so not counted" if gone else "") + ".")


def full(results: list[dict]) -> list[str]:
    return [f"  {r['shown']:5} {r['message']}" for r in results]


def report(doc: dict, prev: dict | None, now: dict | None) -> list[str]:
    res = doc["results"]
    machine = [r for r in res if r["area"] == "machine"]
    fs = findings(res)
    rs = rows(fs)
    fails = sum(f["state"] == "fail" for f in fs)
    warns = len(fs) - fails
    out = []
    if doc.get("crashed"):
        out.append(f"The check stopped early ({doc['crashed']['error']}): this is what it read before. Nothing was changed.")
    elif fails:
        out.append(f"{fails} thing{'s' if fails != 1 else ''} to fix"
                   + (f" and {warns} to look at" if warns else "") + ". Nothing was changed.")
    elif warns:
        out.append(f"No check failed in what was read; {warns} thing{'s' if warns != 1 else ''} to look at. Nothing was changed.")
    else:
        out.append("No check failed in what was read, and nothing needs a look. Nothing was changed.")
    branch = next((r["message"].split("the wall is checked on ", 1)[-1].split(",", 1)[0].strip()
                   for r in res if r["id"] == "FC-E07" and r["key"] == "where"), None)
    for i, row in enumerate(rs[:ROWS], 1):
        text = row_text(row, branch)
        out.append(f"{i}. {text[0]}")
        out += text[1:]
    if len(rs) > ROWS:
        rest = [f["name"] for row in rs[ROWS:] for f in row["members"]]
        out.append(f"{len(rest)} more: {'; '.join(rest)}.")
    if prev and now and not doc.get("crashed"):
        out.append(since(prev, now, doc))
    # Whether "merge on your word" is guidance or a boundary for the login
    # the agent inherits: a fact the person needs, not a finding.
    merge = next((r for r in res if r["id"] == "FC-E26" and r["state"] in ("pass", "info")), None)
    if merge:
        out.append(first_line(merge)[0].upper() + first_line(merge)[1:])
    # What .plinth-adoption.yml holds off (#1112): said on any machine, not counted.
    later = next((r for r in res if r["id"] == "FC-E12" and r["key"] == "later"), None)
    if later:
        out.append(first_line(later)[0].upper() + first_line(later)[1:] + ".")
    kept = [r for r in res if r.get("kept")]
    if kept:
        out.append("Kept by you in .plinth-adoption.yml, not counted: "
                   + "; ".join(f"{r['name']} ({r['kept']['reason']})" for r in kept) + ".")
    unknowns = [r for r in res if r["state"] in ("unknown", "review") and r["area"] != "machine" and not json_only(r)]
    if unknowns:
        names = []
        for r in unknowns:
            if r["name"] not in names:
                names.append(r["name"])
        out.append(f"Could not be read, and these are not failures: {'; '.join(names)}. What would read them: {reasons(unknowns)}.")
    skipped = ["checks for another host, archetype or flag"] if doc["not_evaluated"] else []
    if any(r["state"] == "not_applicable" for r in res):
        skipped.append("the Python items, which do not apply: plinth has no checks for this repository's language")
    if any(r["id"] == "FC-G01" for r in machine):
        skipped.append("this machine's sandbox (`floor-check machine` says what it closes and breaks)")
    if any(r["state"] == "unknown" and r["area"] == "machine" and r["id"] != "FC-G01" for r in machine):
        skipped.append("what this machine's settings do not say (SSH keys among them)")
    if skipped:
        out.append(f"Not checked, and not a problem: {'; '.join(skipped)}.")
    passed = sum(r["state"] == "pass" for r in res)
    if passed:
        out.append(f"Passed: {passed} check{'s' if passed != 1 else ''} (say \"show everything\" to see each).")
    out.append("Next: type `/plinth:guide`; it names in plain words the one command to type next.")
    if any(row["kind"] == "pr" for row in rs):
        out.append("Shall I prepare the file items as one pull request for you to approve?")
    elif rs:
        out.append("Which of these do you want to start with?")
    else:
        out.append("Do you want to see everything the check read?")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run", nargs="?", help="the --format json document; stdin when left out")
    ap.add_argument("--root", default=".", help="the checkout the run read, for the note's git state")
    ap.add_argument("--all", action="store_true", help="every result, the PASS lines included")
    ap.add_argument("--area", help="one area's results, every line")
    ap.add_argument("--no-note", action="store_true", help="neither read nor write the last-run note")
    a = ap.parse_args()
    text = Path(a.run).read_text(encoding="utf-8") if a.run else sys.stdin.read()
    try:
        doc = json.loads(text)
    except ValueError:
        print("The check printed no report this can read (it may have stopped on a usage error). Nothing was changed.")
        return 2
    if a.all or a.area:
        res = [r for r in doc["results"] if not a.area or r["area"] == a.area]
        if a.area and not res:
            areas = sorted({r["area"] for r in doc["results"]})
            print(f"No result in the area \"{a.area}\"; this run's areas: {', '.join(areas)}.")
            return 2
        print("\n".join(full(res)))
        n = doc["summary"]
        print(f"-- {n['fail']} failed, {n['unknown']} not verified")
        return 0
    prev = now = None
    path = None if a.no_note else note_path(doc)
    if path:
        try:
            prev = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            prev = None
        now = note_of(doc, a.root, prev)
    print("\n".join(report(doc, prev, now)))
    if path and now and may_write_note(doc, a.root) is None:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(now, indent=2) + "\n", encoding="utf-8")
        tmp.replace(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
