#!/usr/bin/env -S python3 -I
"""A read-only gh for one copy of a project, with no network (#832).

The eval suite copies this file into a run as `gh`, with the task's
issues.json beside it: the repository's issues and pull requests as they stood
when the session started. It serves `issue list`, `issue view`, `pr list`,
`pr view`, `repo view` and `auth status`, shaped as gh prints them into a pipe
(tab-separated), or as JSON with `--json`, filtered with `--jq` as gh filters it
(#836: scripts/guide-state.sh reads through it; jq does the filtering, so a
call with `--jq` needs jq on the PATH). Anything else, a write included, exits 1
and says so; nothing reaches GitHub. Every call is appended to calls.log beside
it, for the grade.

Python 3.9 and the standard library only: it runs on whatever python3 the
session finds.
"""

import contextlib
import io
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SERVED = "issue list/view, pr list/view, repo view and auth status"
CALLS = {("issue", "list"), ("issue", "view"), ("pr", "list"), ("pr", "view"), ("repo", "view"), ("auth", "status")}


def refuse(why):
    print(f"gh: {why}; this copy of the project is offline and serves {SERVED} only", file=sys.stderr)
    sys.exit(1)


def options(args):
    """The positional arguments and the options, by their long name."""
    short = {"-s": "--state", "-l": "--label", "-L": "--limit", "-c": "--comments", "-R": "--repo",
             "-q": "--jq", "-t": "--template", "-S": "--search", "-w": "--web"}
    flags = {"--comments", "--web"}
    pos, opts = [], {}
    i = 0
    while i < len(args):
        a = args[i]
        if a.startswith("-"):
            name, _, value = a.partition("=")
            name = short.get(name, name)
            if name in flags:
                opts[name] = True
            elif value or "=" in a:
                opts.setdefault(name, []).append(value)
            else:
                i += 1
                opts.setdefault(name, []).append(args[i] if i < len(args) else "")
        else:
            pos.append(a)
        i += 1
    for unserved in ("--template", "--web"):
        if unserved in opts:
            refuse(f"{unserved} is not served")
    return pos, opts


def fields(record, wanted):
    out = {}
    for f in wanted.split(","):
        v = record.get(f)
        if f == "labels":
            v = [{"name": n} for n in record.get("labels", [])]
        elif f == "comments":
            v = [{"author": {"login": c["author"]}, "body": c["body"]} for c in record.get("comments", [])]
        elif f == "author":
            v = {"login": record.get("author", "")}
        elif f == "url":
            v = f"https://github.com/{DATA['repo']}/{record['kind']}/{record['number']}"
        out[f] = v
    return out


def listing(records, opts, line):
    state = (opts.get("--state") or ["open"])[-1].upper()
    picked = [r for r in records if state == "ALL" or r["state"] == state
              or (state == "CLOSED" and r["state"] == "MERGED")]
    for label in opts.get("--label", []):
        picked = [r for r in picked if label in r.get("labels", [])]
    for term in opts.get("--search", []):
        picked = [r for r in picked if term.lower() in (r["title"] + r["body"]).lower()]
    picked = picked[: int((opts.get("--limit") or ["30"])[-1])]
    if "--json" in opts:
        print(json.dumps([fields(r, opts["--json"][-1]) for r in picked], indent=2, ensure_ascii=False))
    else:
        for r in picked:
            print(line(r))


def viewing(records, pos, opts, what):
    m = re.search(r"(\d+)$", pos[0]) if pos else None
    found = [r for r in records if m and r["number"] == int(m.group(1))]
    if not found:
        refuse(f"no {what} {pos[0] if pos else '(none named)'} in this repository")
    r = found[0]
    if "--json" in opts:
        print(json.dumps(fields(r, opts["--json"][-1]), indent=2, ensure_ascii=False))
        return
    head = [("title", r["title"]), ("state", r["state"]), ("author", r["author"]),
            ("labels", ", ".join(r.get("labels", []))), ("comments", str(len(r["comments"]))),
            ("number", str(r["number"]))]
    print("\n".join(f"{k}:\t{v}" for k, v in head))
    print("--")
    print(r["body"])
    if opts.get("--comments"):
        for c in r["comments"]:
            print(f"author:\t{c['author']}\n--\n{c['body']}\n--")


def filtered(jq, group, verb, pos, opts):
    """What `serve` prints, through jq -r: gh's --jq prints a string raw too."""
    if "--json" not in opts:
        refuse("--jq needs --json")
    shown = io.StringIO()
    with contextlib.redirect_stdout(shown):
        serve(group, verb, pos, opts)
    try:
        done = subprocess.run(["jq", "-r", jq], input=shown.getvalue(), capture_output=True, text=True)
    except FileNotFoundError:
        refuse("--jq needs jq on the PATH, and there is none")
    sys.stdout.write(done.stdout)
    sys.stderr.write(done.stderr)
    sys.exit(done.returncode)


def main(args):
    with open(HERE / "calls.log", "a") as log:
        log.write(" ".join(args).replace("\n", " ") + "\n")
    group, verb = (args + ["", ""])[:2]
    if (group, verb) not in CALLS:
        refuse(f"`gh {group} {verb}` is not served")
    pos, opts = options(args[2:])
    jq = opts.pop("--jq", None)
    if jq:
        filtered(jq[-1], group, verb, pos, opts)
    serve(group, verb, pos, opts)


def serve(group, verb, pos, opts):
    issues = [dict(r, kind="issues") for r in DATA["issues"]]
    pulls = [dict(r, kind="pull") for r in DATA["pulls"]]
    if (group, verb) == ("auth", "status"):
        print(f"github.com\n  Logged in to github.com account {DATA['repo'].split('/')[0]} (offline copy)")
    elif (group, verb) == ("repo", "view"):
        if "--json" in opts:
            print(json.dumps({"nameWithOwner": DATA["repo"], "name": DATA["repo"].split("/")[1]}))
        else:
            print(f"name:\t{DATA['repo']}")
    elif (group, verb) == ("issue", "list"):
        listing(issues, opts, lambda r: "\t".join(
            [str(r["number"]), r["state"], r["title"], ", ".join(r["labels"]), r["updatedAt"]]))
    elif (group, verb) == ("issue", "view"):
        viewing(issues, pos, opts, "issue")
    elif (group, verb) == ("pr", "list"):
        listing(pulls, opts, lambda r: "\t".join(
            [str(r["number"]), r["title"], r["headRefName"], r["state"], r["createdAt"]]))
    elif (group, verb) == ("pr", "view"):
        viewing(pulls, pos, opts, "pull request")


DATA = json.loads((HERE / "issues.json").read_text())

if __name__ == "__main__":
    main(sys.argv[1:])
