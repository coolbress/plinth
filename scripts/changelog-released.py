#!/usr/bin/env python3
"""Does a pull request change a CHANGELOG.md section that is already released? (#881)

A step of `ci / docs` in .github/workflows/plinth-ci.yml. A section is
released when its `## [X.Y.Z]` heading has a `vX.Y.Z` tag. A pull request
open across a release can merge main in and keep its new line where it sat,
which is now inside the released section (#877): main's file then disagrees
with the tag the Release text was cut from.

For each tagged version, the section in the pull request (HEAD_REV, default
HEAD: the merge commit GitHub checks out) is compared with the section in its
base (BASE, default HEAD^1: the base branch the merge commit sits on). A
section that is unchanged passes, whatever it says. A changed one passes when
it now equals the section at its tag (a slip moved back, #880), or when the
description (PR_BODY) has a line `Corrects released section: X.Y.Z[, ...]`
naming it, outside HTML comments; otherwise it fails. [Unreleased] and
sections without a tag are never compared, so release run 1's new section
passes. The link lines at the foot of the file belong to no section.

Comparing with the base, not with the tag alone, is on purpose: sections
corrected after their tag (2.23.0, 2.16.0, 1.16.0, 0.5.18, 0.5.4 on
2026-11-10) would otherwise fail every pull request.

Environment: EVENT (github.event_name; anything but pull_request is a pass
with nothing compared), BASE, HEAD_REV, PR_BODY. Run inside the checkout,
with the base commit and the `v*` tags fetched. Reading no `vX.Y.Z` tag, or a
base or head that does not resolve, fails: a pass means the sections were
compared.

    tests/changelog-released-cases.sh runs it on throwaway repositories.
"""
import os
import re
import subprocess
import sys

FILE = "CHANGELOG.md"
HOW = "https://github.com/coolbress/plinth/blob/main/CONTRIBUTING.md#land-a-change"
HEADING = re.compile(r"^## \[(\d+\.\d+\.\d+)\]")
LINK_DEF = re.compile(r"^\[[^\]]+\]: ")
TAG = re.compile(r"^v(\d+\.\d+\.\d+)$")
COMMENT = re.compile(r"<!--.*?(?:-->|\Z)", re.DOTALL)
CORRECTS = re.compile(r"^\s*corrects released sections?:\s*(.+?)\s*$", re.IGNORECASE | re.MULTILINE)
VERSION = re.compile(r"\d+\.\d+\.\d+")


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def sections(text):
    """{version: the section's text, heading included, trailing blank lines dropped}."""
    out, cur = {}, None
    for line in text.replace("\r\n", "\n").split("\n"):
        if line.startswith("## "):
            m = HEADING.match(line)
            cur = m.group(1) if m else None
            if cur:
                out[cur] = [line]
            continue
        if LINK_DEF.match(line):
            cur = None
            continue
        if cur:
            out[cur].append(line)
    return {v: "\n".join(lines).rstrip("\n") for v, lines in out.items()}


def file_at(rev):
    """The changelog's sections at rev; {} when rev has no such file."""
    r = git("show", f"{rev}:{FILE}")
    return sections(r.stdout) if r.returncode == 0 else {}


def named(body):
    """The versions the description's correction lines name."""
    text = COMMENT.sub("", body or "")
    return {v for m in CORRECTS.finditer(text) for v in VERSION.findall(m.group(1))}


def error(message):
    print(f"::error::{message}")
    sys.exit(1)


def main():
    event = os.environ.get("EVENT", "")
    if event != "pull_request":
        print(f"not a pull request ({event or 'no event'}): no base to compare {FILE} with.")
        return 0
    base = os.environ.get("BASE") or "HEAD^1"
    head = os.environ.get("HEAD_REV") or "HEAD"
    for label, rev in (("base", base), ("head", head)):
        if git("rev-parse", "--verify", "--quiet", f"{rev}^{{commit}}").returncode != 0:
            error(f"{FILE}: the pull request's {label} ({rev}) is not in the checkout, so no section was compared. Re-run this job: {HOW}")
    tags = {m.group(1) for t in git("tag", "-l", "v*").stdout.split() for m in [TAG.match(t)] if m}
    if not tags:
        error(f"{FILE}: no vX.Y.Z tag was read, so every section would look unreleased. Re-run this job: {HOW}")

    allowed = named(os.environ.get("PR_BODY", ""))
    at_head, at_base = file_at(head), file_at(base)
    failed = []
    for v in sorted(tags & (set(at_head) | set(at_base)), key=lambda s: tuple(map(int, s.split(".")))):
        h, b = at_head.get(v), at_base.get(v)
        if h == b:
            continue
        if h is not None and h == file_at(f"v{v}").get(v):
            print(f"  PASS  [{v}] changed, back as v{v} has it")
        elif v in allowed:
            print(f"  PASS  [{v}] changed, named on the description's 'Corrects released section:' line")
        else:
            print(f"  FAIL  [{v}] {'removed' if h is None else 'changed'}, and v{v} is released")
            failed.append(v)
    if failed:
        first = failed[0]
        error(
            f"{FILE} [{first}] changed, and v{first} is released{' (and ' + str(len(failed) - 1) + ' more)' if len(failed) > 1 else ''}. "
            f"Move the new line under [Unreleased]; to correct the released text, add 'Corrects released section: {first}' to the description: {HOW}"
        )
    print(f"  PASS  every released section of {FILE} is unchanged, back as its tag has it, or named ({len(tags)} tags read)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
