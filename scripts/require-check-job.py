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
jobs on stdout, then one `needs: <check name>` line per job it needs; exit 1
with the reason on stderr. The workflow's `on:` is read too: a workflow that
does not run on every new commit of a pull request to the default branch (no
pull_request event, a path filter, another branch, a `!` branch pattern, types without
`synchronize`) leaves the name pending there, and is a refusal.
"""

from __future__ import annotations

import re
import subprocess
import sys
from dataclasses import dataclass, field

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
    needs: list[str] = field(default_factory=list)

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
        rest = value[end + 1:].strip()
        # An escape (`"\x21main"`, `'it''s'`) changes the value; these lines do not undo it.
        if (q == '"' and "\\" in value[1:end]) or (rest and not rest.startswith("#")):
            raise Unreadable(f"a quoted value with an escape or more text after it: {value}")
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
    in_needs = False
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
            in_needs = False
            continue
        job = jobs[-1]
        if key_indent is None:
            key_indent = ind
        if ind != key_indent:
            if in_needs:  # `needs:` as a block list, one id per line
                item = re.match(r"\s*-\s+(.+)$", ln)
                if not item:
                    raise Unreadable(f"line {n} in job `{job.id}`'s needs does not read as a list item")
                job.needs.append(scalar(item.group(1)))
            continue  # deeper: steps, with, strategy and their contents
        in_needs = False
        m = KEY.match(ln)
        if not m:
            raise Unreadable(f"line {n} in job `{job.id}` does not read as a key: {ln.strip()}")
        key, value = m.group(3), m.group(4) or ""
        # A merge key can carry an `if:` in from elsewhere; the three keys read here must be plain.
        if key == "<<" or (key in {"if", "name", "uses", "needs"} and value.startswith(("&", "*", "{", "|", ">"))) \
                or (key in {"if", "name", "uses"} and value.startswith("[")):
            raise Unreadable(f"line {n} in job `{job.id}` uses a merge key, an anchor, an alias or a multi-line value")
        if key == "if":
            job.if_line = n
        elif key == "name":
            job.name = scalar(value)
        elif key == "uses":
            job.uses = scalar(value)
        elif key == "needs":
            if not value or value.startswith("#"):
                in_needs = True
            else:
                job.needs = flow_list(value)
    return jobs


def flow_raw(value: str) -> list[str]:
    """The items of `a`, or of `[a, b]` on one line, as written."""
    value = value.strip()
    if value.startswith("["):
        end = value.find("]")
        if end < 0:
            raise Unreadable(f"a list that does not close on its line: {value}")
        return [v.strip() for v in value[1:end].split(",") if v.strip()]
    return [value]


def flow_list(value: str) -> list[str]:
    """`a`, or `[a, b]` on one line."""
    return [scalar(v) for v in flow_raw(value)]


def top_key(rows: list[tuple[int, int, str]], names: set[str]) -> int | None:
    for i, (_, ind, ln) in enumerate(rows):
        m = KEY.match(ln) if ind == 0 else None
        if m and m.group(3) in names:
            return i
    return None


def children(rows: list[tuple[int, int, str]], i: int) -> list[tuple[int, int, str]]:
    """The lines under rows[i], deeper than it, up to the next line at its indent or less."""
    out = []
    for row in rows[i + 1:]:
        if row[1] <= rows[i][1]:
            break
        out.append(row)
    return out


def raw_items(value: str, n: int, under: list[tuple[int, int, str]]) -> list[tuple[int, str]]:
    """(line number, item as written) of a list on line n or as `- item` lines under it."""
    if value and not value.startswith("#"):
        return [(n, v) for v in flow_raw(value)]
    out = []
    for ln_no, _, ln in under:
        m = re.match(r"\s*-\s+(.+)$", ln)
        if not m:
            raise Unreadable(f"line {ln_no} does not read as a list item")
        out.append((ln_no, m.group(1).strip()))
    return out


def items(value: str, under: list[tuple[int, int, str]]) -> list[str]:
    """A list written on the key's line or as `- item` lines under it."""
    return [scalar(v) for _, v in raw_items(value, 0, under)]


PR_EVENTS = {"pull_request", "pull_request_target"}


def pull_request_trigger(text: str, branch: str, path: str = "the workflow") -> str | None:
    """None when the workflow runs on every new commit of a pull request to
    `branch`; otherwise why not. A form not read here is a reason too."""
    rows = list(lines(text))
    i = top_key(rows, {"on", "true"})
    if i is None:
        return "it has no `on:` key at the top of the file this script can read"
    value = KEY.match(rows[i][2]).group(4) or ""  # type: ignore[union-attr]
    under = children(rows, i)
    if value.startswith("{"):
        return "its `on:` is written on one line as a mapping, which this script does not read"
    if (value and not value.startswith("#")) or (under and re.match(r"\s*-\s", under[0][2])):
        return None if PR_EVENTS & set(items(value, under)) else "its `on:` has no pull_request event"
    reasons = []
    ev_indent = under[0][1] if under else None
    for j, (n, ind, ln) in enumerate(under):
        if ind != ev_indent:
            continue
        m = KEY.match(ln)
        if not m:
            return f"line {n} of its `on:` does not read as an event"
        if m.group(3) not in PR_EVENTS:
            continue
        ev_value = m.group(4) or ""
        if ev_value and not ev_value.startswith("#") and ev_value not in {"null", "{}", "~"}:
            reasons.append(f"its `{m.group(3)}:` is written on one line, which this script does not read")
            continue
        k = rows.index((n, ind, ln))
        filters = children(rows, k)
        f_indent = filters[0][1] if filters else None
        why = None
        for fi, (fn, find, fln) in enumerate(filters):
            if find != f_indent:
                continue
            fm = KEY.match(fln)
            if not fm:
                why = f"line {fn} under `{m.group(3)}:` does not read as a key"
                break
            fkey, fval = fm.group(3), fm.group(4) or ""
            fsub = children(rows, rows.index((fn, find, fln)))
            if fkey in {"paths", "paths-ignore"}:
                why = (f"its `{m.group(3)}:` has `{fkey}:` (line {fn}): a pull request that touches no such path"
                       " never runs it, and a required name that never reports holds that pull request")
            elif fkey == "branches-ignore":
                why = f"its `{m.group(3)}:` has `branches-ignore:` (line {fn}), which this script does not read"
            elif fkey == "branches":
                try:
                    written = raw_items(fval, fn, fsub)
                except Unreadable as e:
                    raise Unreadable(f"line {fn} of {path}, `{m.group(3)}:` branches: {e}") from None
                names = []
                for ln_no, v in written:
                    try:
                        names.append(scalar(v))
                    except Unreadable as e:
                        raise Unreadable(f"line {ln_no} of {path}, `{m.group(3)}:` branches: {e}") from None
                # GitHub reads the list in order and a `!` pattern drops a branch an earlier one matched;
                # an anchor or alias may carry one in. Neither is read here.
                odd = next(((ln_no, v, p) for (ln_no, v), p in zip(written, names)
                            if p.startswith("!") or (v.startswith(("&", "*")) and v not in {"*", "**"})), None)
                if odd:
                    ln_no, v, p = odd
                    why = (f"its `{m.group(3)}:` branches list has `{v}` (line {ln_no}): "
                           + ("a pattern starting with `!` leaves branches out, maybe "
                              f"{branch}, and this script does not read those. List the branches to run on instead"
                              if p.startswith("!") else "an anchor or alias, which this script does not read"))
                elif branch not in names and not {"*", "**"} & set(names):
                    why = (f"its `{m.group(3)}:` runs only for pull requests to {', '.join(names) or 'no branch'}"
                           f" (line {fn}), not to {branch}")
            elif fkey == "types":
                types = set(items(fval, fsub))
                missing = {"opened", "synchronize"} - types
                if missing:
                    why = (f"its `{m.group(3)}:` types (line {fn}) leave out {', '.join(sorted(missing))}:"
                           " a new commit on the pull request would not run it")
            if why:
                break
        if why is None:
            return None
        reasons.append(why)
    return reasons[0] if reasons else "its `on:` has no pull_request event"


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


def needed(job: Job, jobs: list[Job], path: str) -> list[Job]:
    """Every job `job` needs, directly or through another one."""
    by_id = {j.id: j for j in jobs}
    found: list[Job] = []
    todo = list(job.needs)
    while todo:
        i = todo.pop(0)
        if i not in by_id:
            raise Unreadable(f"job `{job.id}` in {path} needs `{i}`, which is not a job there")
        if by_id[i] not in found:
            found.append(by_id[i])
            todo.extend(by_id[i].needs)
    return found


# A chain is the jobs whose `if:` decides whether the name reports, outermost
# first: the job, the jobs that call its workflow, and every job any of them
# needs. Beside it, the check names of the needed jobs.
Chain = tuple[list[tuple[str, Job]], list[str]]


def resolve(name: str, repo: str, ref: str, path: str, depth: int = 1, prefix: str = "") -> list[Chain]:
    """Every chain of jobs whose check name is `name`."""
    if depth > MAX_DEPTH:
        raise Unreadable(f"reusable workflows nested deeper than {MAX_DEPTH} levels")
    jobs = parse_jobs(fetch(repo, ref, path))
    chains: list[Chain] = []
    for job in jobs:
        if job.uses is None and job.display == name:
            found: list[Chain] = [([(path, job)], [])]
        elif job.uses is not None and name.startswith(job.display + " / "):
            r, f, p = called(repo, ref, job.uses)
            found = [([(path, job), *sub], names)
                     for sub, names in resolve(name[len(job.display) + 3:], r, f, p, depth + 1,
                                               prefix + job.display + " / ")]
        else:
            continue
        deps = needed(job, jobs, path)
        for dep in deps:
            if dep.uses is not None:
                raise Unreadable(f"job `{job.id}` in {path} needs `{dep.id}`, which calls a reusable workflow")
        for links, names in found:
            chains.append(([*links, *[(path, d) for d in deps]], [*names, *[prefix + d.display for d in deps]]))
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
        why = pull_request_trigger(fetch(repo, ref, path), ref, path)
        if why:
            print(f"{path} does not run '{name}' on every pull request to {ref}: {why}.", file=sys.stderr)
            print("  a required name that does not report on a pull request holds it. Fix the workflow's `on:`,"
                  " merge that, then try again.", file=sys.stderr)
            return 1
        chains = resolve(name, repo, ref, path)
    except Unreadable as e:
        print(f"cannot tell which job reports '{name}': {e}.", file=sys.stderr)
        return 1
    if not chains:
        print(f"no job in {path} at {ref} reports '{name}' (a matrix job, whose name carries its matrix values, is not read).",
              file=sys.stderr)
        return 1
    gated = [(p, j) for links, _ in chains for p, j in links if j.if_line is not None]
    if gated:
        for p, j in gated:
            print(f"job `{j.id}` in {p} has `if:` (line {j.if_line}): on a run where it is false the job is skipped,",
                  file=sys.stderr)
        print("  and so is every job that needs it.", file=sys.stderr)
        print("  A skipped job counts as a pass without running, and a skipped call to a reusable workflow", file=sys.stderr)
        print("  reports no name at all, which holds every pull request.", file=sys.stderr)
        print("  Move the condition into the job's steps, so the job always runs and reports, then try again.",
              file=sys.stderr)
        return 1
    for links, names in chains:
        print(" -> ".join(f"{p}: job `{j.id}`" for p, j in links))
        for n in names:
            print(f"needs: {n}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
