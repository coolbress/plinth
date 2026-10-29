#!/usr/bin/env python3
"""Find the job a check name comes from, and refuse one with `if:`.

    require-check-job.py <owner/name> <ref> <workflow path> <check name>

Called by scripts/require-check.sh (#707) with the workflow file of the run
that reported the name on the default branch, read at the default branch's
head. A job with `if:` at its own level may be skipped: a skipped job
counts as a pass without running, and a skipped call to a reusable workflow
reports no name at all, so nothing merges.
A check name from a reusable workflow is `<caller job> / <called job>`, so
both jobs are read, the called file through the same API (a local
`./.github/workflows/x.yml` at the same ref, a remote one at its pin).

Lines, not a YAML parser (standard library only), the same approach as
floor-check.py: block scalars (`run: |`) and comments are skipped, and a form
these lines do not read (a flow mapping, an anchor, a job name set by an
expression or a matrix) is a refusal, never a pass. Exit 0 with the chain of
jobs on stdout; exit 1 with the reason on stderr.
"""

from __future__ import annotations

import re
import subprocess
import sys
from dataclasses import dataclass

# A key whose value is a block scalar indicator: the lines under it are shell.
BLOCK = re.compile(r"""^\s*(?:-\s+)*[^\s#][^#]*?:\s*[|>][-+0-9]*\s*(?:#.*)?$""")
KEY = re.compile(r"""^(\s*)(['"]?)([A-Za-z_][A-Za-z0-9_-]*)\2\s*:(?:\s+(.*?))?\s*$""")
MAX_DEPTH = 4  # GitHub nests reusable workflows at most four levels deep


class Unreadable(Exception):
    """A form the line reader does not read: refuse, do not guess."""


@dataclass
class Job:
    id: str
    line: int
    name: str | None = None
    if_line: int | None = None
    uses: str | None = None

    @property
    def display(self) -> str:
        return self.name if self.name is not None else self.id


def scalar(value: str) -> str:
    """A plain or quoted one-line value, its trailing comment dropped."""
    value = value.strip()
    if value[:1] in {"'", '"'}:
        q = value[0]
        end = value.find(q, 1)
        if end < 0:
            raise Unreadable(f"a quoted value that does not close on its line: {value}")
        return value[1:end]
    return re.split(r"\s+#", value, maxsplit=1)[0].strip()


def lines(text: str):
    """(line number, indent, line) for each line that is syntax."""
    block = None
    for n, line in enumerate(text.splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        if block is not None:
            if indent > block:
                continue
            block = None
        if BLOCK.match(line):
            block = len(re.match(r"\s*(?:-\s+)*", line).group(0))  # type: ignore[union-attr]
        yield n, indent, line


def parse_jobs(text: str) -> list[Job]:
    rows = list(lines(text))
    start = next((i for i, (_, ind, ln) in enumerate(rows) if ind == 0 and re.match(r"""['"]?jobs['"]?\s*:""", ln)), None)
    if start is None:
        raise Unreadable("no `jobs:` key at the top of the file")
    rest = rows[start][2].split(":", 1)[1].strip()
    if rest and not rest.startswith("#"):
        raise Unreadable("`jobs:` is written on one line (a flow mapping)")
    jobs: list[Job] = []
    job_indent = key_indent = None
    for n, ind, ln in rows[start + 1:]:
        if ind == 0:
            break
        if job_indent is None:
            job_indent = ind
        if ind < job_indent:
            raise Unreadable(f"line {n} is indented less than the jobs above it")
        if ind == job_indent:
            m = KEY.match(ln)
            if not m or (m.group(4) and not m.group(4).startswith("#")):
                raise Unreadable(f"line {n} does not read as a job id: {ln.strip()}")
            jobs.append(Job(id=m.group(3), line=n))
            key_indent = None
            continue
        job = jobs[-1]
        if key_indent is None:
            key_indent = ind
        if ind != key_indent:
            continue  # deeper: steps, with, strategy and their contents
        m = KEY.match(ln)
        if not m:
            raise Unreadable(f"line {n} in job `{job.id}` does not read as a key: {ln.strip()}")
        key, value = m.group(3), m.group(4) or ""
        # A merge key can carry an `if:` in from elsewhere; the three keys read here must be plain.
        if key == "<<" or (key in {"if", "name", "uses"} and value.startswith(("&", "*", "{", "[", "|", ">"))):
            raise Unreadable(f"line {n} in job `{job.id}` uses a merge key, an anchor, an alias or a multi-line value")
        if key == "if":
            job.if_line = n
        elif key == "name":
            job.name = scalar(value)
        elif key == "uses":
            job.uses = scalar(value)
    return jobs


def fetch(repo: str, ref: str, path: str) -> str:
    out = subprocess.run(
        ["gh", "api", "-H", "Accept: application/vnd.github.raw+json", f"repos/{repo}/contents/{path}?ref={ref}"],
        capture_output=True, text=True, check=False)
    if out.returncode != 0:
        raise Unreadable(f"could not read {path} in {repo} at {ref}: {out.stderr.strip() or 'gh failed'}")
    return out.stdout


def called(repo: str, ref: str, uses: str) -> tuple[str, str, str]:
    """The (repo, ref, path) a job's `uses:` calls."""
    if uses.startswith("./"):
        return repo, ref, uses[2:]
    m = re.fullmatch(r"([^/\s]+/[^/\s]+)/(\.github/workflows/[^@\s]+)@(\S+)", uses)
    if not m:
        raise Unreadable(f"`uses: {uses}` is not a workflow this script can read")
    return m.group(1), m.group(3), m.group(2)


def resolve(name: str, repo: str, ref: str, path: str, depth: int = 1) -> list[list[tuple[str, Job]]]:
    """Every chain of jobs whose check name is `name`, outermost first."""
    if depth > MAX_DEPTH:
        raise Unreadable(f"reusable workflows nested deeper than {MAX_DEPTH} levels")
    jobs = parse_jobs(fetch(repo, ref, path))
    chains: list[list[tuple[str, Job]]] = []
    for job in jobs:
        if job.uses is None and job.display == name:
            chains.append([(path, job)])
        elif job.uses is not None and name.startswith(job.display + " / "):
            r, f, p = called(repo, ref, job.uses)
            for sub in resolve(name[len(job.display) + 3:], r, f, p, depth + 1):
                chains.append([(path, job), *sub])
    # A name set by an expression may be the one asked for: with no plain match, that is not a "no".
    guessed = [j.id for j in jobs if j.name is not None and "${{" in j.name]
    if not chains and guessed:
        raise Unreadable(f"job `{guessed[0]}` in {path} sets its name with an expression, which this script does not read")
    return chains


def main(argv: list[str]) -> int:
    if len(argv) != 5:
        print("usage: require-check-job.py <owner/name> <ref> <workflow path> <check name>", file=sys.stderr)
        return 2
    repo, ref, path, name = argv[1:]
    try:
        chains = resolve(name, repo, ref, path)
    except Unreadable as e:
        print(f"cannot tell which job reports '{name}': {e}.", file=sys.stderr)
        return 1
    if not chains:
        print(f"no job in {path} at {ref} reports '{name}' (a matrix job, whose name carries its matrix values, is not read).",
              file=sys.stderr)
        return 1
    gated = [(p, j) for chain in chains for p, j in chain if j.if_line is not None]
    if gated:
        for p, j in gated:
            print(f"job `{j.id}` in {p} has `if:` (line {j.if_line}): on a run where it is false the job is skipped.",
                  file=sys.stderr)
        print("  A skipped job counts as a pass without running, and a skipped call to a reusable workflow", file=sys.stderr)
        print("  reports no name at all, which holds every pull request.", file=sys.stderr)
        print("  Move the condition into the job's steps, so the job always runs and reports, then try again.",
              file=sys.stderr)
        return 1
    for chain in chains:
        print(" -> ".join(f"{p}: job `{j.id}`" for p, j in chain))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
