#!/usr/bin/env python3
"""Records check: what is out of place in a repository's issue and
pull-request records, counted read-only (#977). It changes nothing: it only
reads files in --root and sends GET requests and GraphQL queries.

    records-check.py --root . --repo owner/name [--host gitlab]

Every line is PASS, WARN, INFO or SKIP; it never prints FAIL. It exits 0
whenever it ran, whatever it found, and non-zero (2) only when it could not
run: no repository named or found, or the issue or pull-request list could not
be read. An item it could not read is a SKIP, counted on the last line as
not verified.

Two layers:

- Facts, judged whatever the repository's conventions say: a `#N` or
  `owner/repo#N` in a body (outside code) that resolves to nothing (410, or a
  404 above the highest number the repository has used); a home path in a
  body, reported by line and form, never repeating what matched; a body at
  90% or more of GitHub's 65,536 limit, counted in characters and in UTF-8
  bytes, since the unit is not documented.
- Convention items, judged only against what the repository's own files say:
  the issue and pull-request templates that apply (local, else the owner's
  `.github`), CONTRIBUTING.md, docs/agents/issue-tracker.md and AGENTS.md.
  Each line names the file the convention came from; with none read the line
  is `not checked: convention not read`. Items: a completed `task` or `bug`
  with no ending section (an issue carrying a Decision heading, a record's
  ending, is excepted); a merged pull request with no AI trailer in its body
  or its merge commit, an INFO (a person or a bot may have written it).

Unticked acceptance criteria on a completed issue are a heuristic, since the
ending may explain them: they are counted and listed "for a person to read",
with URLs and line numbers, never judged.

A GitLab checkout (--host gitlab, or `host: gitlab` in .copier-answers.yml)
prints `GitLab: not read` and judges nothing.

Standard library only. RECORDS_CHECK_API_DIR serves fixtures: a REST path
`<path>.json` (a body of {"__status": N} answers that status; no file is a
404), and a GraphQL query as `graphql/<name>.json`, its name given below.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

LIMIT = 65536
NEAR = int(LIMIT * 0.9)
PAGE = 20
REF_CHUNK = 50
LABELS_PAGE = 20
KIND_LABELS = ("task", "bug")
RECORD_HEADING = "decision"

ISSUE_TEMPLATE_SUFFIXES = (".yml", ".yaml", ".md")
PR_TEMPLATE_PATHS = (".github/PULL_REQUEST_TEMPLATE.md", ".github/pull_request_template.md",
                     "PULL_REQUEST_TEMPLATE.md", "pull_request_template.md",
                     "docs/PULL_REQUEST_TEMPLATE.md", "docs/pull_request_template.md")
DOC_PATHS = ("CONTRIBUTING.md", ".github/CONTRIBUTING.md", "docs/CONTRIBUTING.md",
             "docs/agents/issue-tracker.md", "AGENTS.md")

counts: dict[str, int] = {}
skips = 0
unchecked = 0


class CannotRun(Exception):
    pass


def line(kind: str, msg: str, rule: str | None = None) -> None:
    global skips, unchecked
    print(f"  {kind:4}  {msg}")
    # A rule with no convention read is not a record left unread.
    if kind == "SKIP" and "not checked: convention not read" in msg:
        unchecked += 1
    elif kind == "SKIP":
        skips += 1
    if rule and kind in ("WARN", "INFO"):
        counts[rule] = counts.get(rule, 0) + 1


# ── reading ──────────────────────────────────────────────────────────────


def fixture_dir() -> Path | None:
    d = os.environ.get("RECORDS_CHECK_API_DIR")
    return Path(d) if d else None


def rest(path: str) -> tuple[int, Any]:
    """GET api.github.com/<path>: (status, JSON). Status 0 means no answer."""
    d = fixture_dir()
    if d:
        f = d / (path + ".json")
        if not f.is_file():
            return 404, None
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except ValueError:
            return 0, None
        if isinstance(data, dict) and "__status" in data:
            return int(data["__status"]), None
        return 200, data
    try:
        r = subprocess.run(["gh", "api", "-i", path], capture_output=True, text=True, timeout=60, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return rest_plain(path)
    m = re.match(r"HTTP/\S+ (\d{3})", r.stdout)
    if not m:
        return rest_plain(path) if r.returncode != 0 else (0, None)
    status = int(m.group(1))
    _, _, body = r.stdout.partition("\r\n\r\n") if "\r\n\r\n" in r.stdout else r.stdout.partition("\n\n")
    try:
        return status, json.loads(body) if body.strip() else None
    except ValueError:
        return status, None


def rest_plain(path: str) -> tuple[int, Any]:
    req = urllib.request.Request(f"https://api.github.com/{path}")
    req.add_header("Accept", "application/vnd.github+json")
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, None
    except (urllib.error.URLError, TimeoutError, ValueError):
        return 0, None


def graphql(name: str, query: str, variables: dict[str, Any]) -> dict | None:
    """The whole answer ({data, errors}), or None when there was none. An
    answer may carry both data and errors; the caller reads each part."""
    d = fixture_dir()
    if d:
        f = d / "graphql" / (name + ".json")
        try:
            out = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
        return out if isinstance(out, dict) else None
    cmd = ["gh", "api", "graphql", "-f", f"query={query}"]
    for k, v in variables.items():
        if v is not None:
            cmd += ["-F" if isinstance(v, int) else "-f", f"{k}={v}"]
    # A large page is sometimes cut by the network (a reset stream, measured
    # on this repository's issues): three tries before it counts as no answer.
    for _ in range(3):
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=120, check=False)
        except (OSError, subprocess.TimeoutExpired):
            continue
        # gh exits 1 on an answer with errors and still prints it: read the body.
        try:
            out = json.loads(r.stdout)
        except ValueError:
            continue
        return out if isinstance(out, dict) else None
    return None


ISSUES_Q = """query($owner:String!,$name:String!,$cursor:String){repository(owner:$owner,name:$name){
issues(first:PAGE,after:$cursor,orderBy:{field:CREATED_AT,direction:ASC}){pageInfo{hasNextPage endCursor}
nodes{number url state stateReason body labels(first:LABELS){totalCount nodes{name}}}}}}"""
ISSUES_Q = ISSUES_Q.replace("first:PAGE", f"first:{PAGE}").replace("first:LABELS", f"first:{LABELS_PAGE}")
PULLS_Q = """query($owner:String!,$name:String!,$cursor:String){repository(owner:$owner,name:$name){
pullRequests(first:PAGE,after:$cursor,orderBy:{field:CREATED_AT,direction:ASC}){pageInfo{hasNextPage endCursor}
nodes{number url state merged body mergeCommit{message}}}}}""".replace("first:PAGE", f"first:{PAGE}")


def read_all(kind: str, field: str, query: str, owner: str, name: str) -> list[dict]:
    """Every node of one paginated list; CannotRun when a page is not read.
    Fixture pages are graphql/<kind>-1.json, -2.json, ..."""
    nodes: list[dict] = []
    cursor = None
    page = 1
    while True:
        ans = graphql(f"{kind}-{page}", query, {"owner": owner, "name": name, "cursor": cursor})
        conn = (((ans or {}).get("data") or {}).get("repository") or {}).get(field)
        if not isinstance(conn, dict):
            why = "; ".join(e.get("message", "") for e in (ans or {}).get("errors") or []) or "no answer"
            raise CannotRun(f"the {kind} of {owner}/{name} could not be read (page {page}: {why})")
        nodes += [n for n in conn.get("nodes") or [] if isinstance(n, dict)]
        info = conn.get("pageInfo") or {}
        if not info.get("hasNextPage"):
            return nodes
        cursor = info.get("endCursor")
        page += 1


# ── text ─────────────────────────────────────────────────────────────────

FENCE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")
HEADING = re.compile(r"^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$")


def outside_fences(body: str) -> list[tuple[int, str]]:
    """(line number, text) of each line outside fenced code; fence lines dropped."""
    out: list[tuple[int, str]] = []
    fence: str | None = None
    for i, ln in enumerate(body.splitlines(), 1):
        m = FENCE.match(ln)
        if m:
            mark = m.group(1)
            if fence is None:
                fence = mark[0] * len(mark)
                continue
            if mark[0] == fence[0] and len(mark) >= len(fence):
                fence = None
                continue
        if fence is None:
            out.append((i, ln))
    return out


def norm(h: str) -> str:
    return re.sub(r"\s+", " ", h.replace("*", "").replace("__", "").strip().strip(":").strip()).casefold()


def named(heading: str, names: set[str]) -> bool:
    """The heading is one of the names, or one followed by more words:
    `## Outcome: completed`, `## Outcome (cancelled)`."""
    return any(heading == n or re.match(re.escape(n) + r"\W", heading) for n in names)


def headings(body: str) -> list[tuple[int, int, str]]:
    """(line, level, normalised text) of each heading outside code."""
    out: list[tuple[int, int, str]] = []
    for i, ln in outside_fences(body):
        m = HEADING.match(ln)
        if m:
            level = len(ln.strip()) - len(ln.strip().lstrip("#"))
            out.append((i, level, norm(m.group(1))))
    return out


INLINE_CODE = re.compile(r"(`+)(.+?)\1")
# An owner is letters, digits and hyphens: `v1.2/x#4` is not a reference.
REF = re.compile(r"(?<![\w&/#.\-])(?:([A-Za-z0-9][A-Za-z0-9\-]*/[\w.\-]+))?#(\d+)\b")


def refs(body: str) -> set[tuple[str | None, int]]:
    found: set[tuple[str | None, int]] = set()
    for _, ln in outside_fences(body):
        ln = INLINE_CODE.sub(" ", ln)
        # A link is not a reference, its text included: GitHub does not turn
        # `[discussion #121836](url)` into a link to this repository's #121836.
        ln = re.sub(r"\[[^\]]*\]\([^)]*\)", " ", ln)
        ln = re.sub(r"https?://\S+", " ", ln)
        for m in REF.finditer(ln):
            found.add((m.group(1), int(m.group(2))))
    return found


HOME = re.compile(r"(?<![\w.\-])(/Users/|/home/|[A-Za-z]:\\Users\\)([^\s/\\`'\"<>()\[\]]+)")
NOT_A_PERSON = {"runner", "ubuntu", "linuxbrew", "public", "default", "user", "username", "you", "your-name", "name", "me", "shared", "$user", "${user}",
                "...", "…", "<you>", "<user>", "<name>"}


def home_paths(body: str) -> list[tuple[int, str]]:
    """(line, form) of each home path; the form is the prefix and a
    placeholder, never the name that followed it."""
    out: list[tuple[int, str]] = []
    for i, ln in enumerate(body.splitlines(), 1):
        for m in HOME.finditer(ln):
            name = m.group(2).rstrip(".,;:")
            if name.casefold() in NOT_A_PERSON or name.startswith(("<", "$", "{", "*", "…", "...")):
                continue
            form = m.group(1) + "<name>"
            out.append((i, form))
    return out


def size(body: str) -> tuple[int, int]:
    return len(body), len(body.encode("utf-8"))


# ── conventions ──────────────────────────────────────────────────────────


def read_conventions(root: Path, owner: str) -> dict[str, str]:
    """{shown path: text} of each convention file that applies."""
    out: dict[str, str] = {}
    forms = root / ".github" / "ISSUE_TEMPLATE"
    local = sorted(p for p in forms.iterdir() if p.is_file()) if forms.is_dir() else []
    if local:
        for f in local:
            if f.suffix in ISSUE_TEMPLATE_SUFFIXES:
                out[str(f.relative_to(root))] = f.read_text(encoding="utf-8", errors="replace")
    else:
        status, listing = rest(f"repos/{owner}/.github/contents/.github/ISSUE_TEMPLATE")
        if status == 200 and isinstance(listing, list):
            for e in listing:
                n = e.get("name", "") if isinstance(e, dict) else ""
                if Path(n).suffix in ISSUE_TEMPLATE_SUFFIXES:
                    text = owner_file(owner, f".github/ISSUE_TEMPLATE/{n}")
                    if text is not None:
                        out[f"{owner}/.github: .github/ISSUE_TEMPLATE/{n}"] = text
        elif status not in (404,):
            line("SKIP", f"the owner's shared issue templates ({owner}/.github) not read: status {status or 'no answer'}")
    pr = [p for p in PR_TEMPLATE_PATHS if (root / p).is_file()]
    # On a case-insensitive file system two spellings are one file: read it once.
    seen: set[tuple[int, int]] = set()
    once = []
    for p in pr:
        if ino(root / p) not in seen:
            seen.add(ino(root / p))
            once.append(p)
    pr = once
    prdir = root / ".github" / "PULL_REQUEST_TEMPLATE"
    pr += [str(f.relative_to(root)) for f in sorted(prdir.glob("*.md"))] if prdir.is_dir() else []
    if pr:
        for p in pr:
            out[p] = (root / p).read_text(encoding="utf-8", errors="replace")
    else:
        for p in PR_TEMPLATE_PATHS:
            text = owner_file(owner, p)
            if text is not None:
                out[f"{owner}/.github: {p}"] = text
                break
    for p in DOC_PATHS:
        if (root / p).is_file():
            out[p] = (root / p).read_text(encoding="utf-8", errors="replace")
    return out


def ino(p: Path) -> tuple[int, int]:
    st = p.stat()
    return st.st_dev, st.st_ino


def owner_file(owner: str, path: str) -> str | None:
    import base64
    status, data = rest(f"repos/{owner}/.github/contents/{path}")
    if status != 200 or not isinstance(data, dict):
        return None
    return base64.b64decode(data.get("content", "")).decode("utf-8", errors="replace")


def sentences(text: str) -> list[str]:
    """Prose units: a table row, list item or paragraph, cut at sentence ends."""
    units: list[str] = []
    cur: list[str] = []
    for ln in text.splitlines():
        s = ln.strip()
        if not s:
            if cur:
                units.append(" ".join(cur))
            cur = []
            continue
        if re.match(r"^(\||[-*+] |\d+\. |#)", s) and cur:
            units.append(" ".join(cur))
            cur = []
        cur.append(s)
    if cur:
        units.append(" ".join(cur))
    out: list[str] = []
    for u in units:
        out += re.split(r"(?<=[.;!?])\s+(?=[A-Z`(])", u)
    return out


# The heading a sentence names as the ending: right after "ending" or "ends
# in" ("the ending under `## Outcome`", "ends in `## Decision`"), or before
# "is its ending". A heading elsewhere in the sentence (`## Decisions`, dated,
# while open) is not one.
ENDING = (re.compile(r"\b(?:ending|ends in|ends with)\b[^`]{0,40}`#{1,6} ([^`]+)`", re.IGNORECASE),
          re.compile(r"`#{1,6} ([^`]+)` is (?:its|the) ending", re.IGNORECASE))
BACKTICK_HEADING = re.compile(r"`#{1,6} ([^`]+)`")


def ending_convention(conv: dict[str, str]) -> tuple[set[str], list[str]]:
    names: set[str] = set()
    where: list[str] = []
    for path, text in conv.items():
        found = {norm(h) for s in sentences(text) for rx in ENDING for h in rx.findall(s)}
        if found:
            names |= found
            where.append(path)
    return names, where


CRITERIA = re.compile(r"acceptance criteri", re.IGNORECASE)


def criteria_convention(conv: dict[str, str]) -> tuple[set[str], list[str]]:
    """The criteria heading as the conventions spell it: a backticked heading,
    a template heading, or an issue form's label."""
    names: set[str] = set()
    where: list[str] = []
    for path, text in conv.items():
        found = {norm(h) for h in BACKTICK_HEADING.findall(text) if CRITERIA.search(h)}
        if path.endswith(".md"):
            found |= {norm(m.group(1)) for m in re.finditer(r"^\s{0,3}#{1,6}\s+(.+?)\s*$", text, re.MULTILINE)
                      if CRITERIA.search(m.group(1))}
        found |= {norm(m.group(1).strip("'\"")) for m in re.finditer(r"^\s*label:\s*(.+?)\s*$", text, re.MULTILINE)
                  if CRITERIA.search(m.group(1))}
        if found:
            names |= found
            where.append(path)
    return names, where


TRAILER_FORM = re.compile(r"\b([A-Z][A-Za-z]*(?:-[A-Za-z]+)+):\s*<")


def trailer_convention(conv: dict[str, str]) -> tuple[set[str], list[str]]:
    """A trailer key the conventions give with a placeholder (`Key: <agent>...`)
    in a sentence that names AI."""
    keys: set[str] = set()
    where: list[str] = []
    for path, text in conv.items():
        found = {k.casefold() for s in sentences(text) if re.search(r"\bAI\b", s) for k in TRAILER_FORM.findall(s)}
        if found:
            keys |= found
            where.append(path)
    return keys, where


def has_trailer(text: str | None, keys: set[str]) -> bool:
    if not text:
        return False
    return any(re.match(r"^\s*([A-Za-z][\w-]*):\s*\S", ln) and ln.split(":", 1)[0].strip().casefold() in keys
               for ln in text.splitlines())


def unticked_criteria(body: str, names: set[str]) -> list[int]:
    """Line numbers of `- [ ]` items under a criteria heading, to the next
    heading of the same or a higher level."""
    lines = dict(outside_fences(body))
    hs = headings(body)
    out: list[int] = []
    for idx, (ln, level, text) in enumerate(hs):
        if not named(text, names):
            continue
        end = next((h[0] for h in hs[idx + 1:] if h[1] <= level), max(lines, default=0) + 1)
        out += [i for i in range(ln + 1, end) if i in lines and re.match(r"^\s*[-*+]\s+\[ \]", lines[i])]
    return out


# ── the check ────────────────────────────────────────────────────────────


def host_of(root: Path, given: str | None) -> str:
    if given:
        return given
    p = root / ".copier-answers.yml"
    if p.is_file():
        for ln in p.read_text(encoding="utf-8", errors="replace").splitlines():
            m = re.match(r"^host:\s*['\"]?(\w+)", ln)
            if m:
                return m.group(1)
    return "github"


def resolve(own: str, refs_by_repo: dict[str, dict[int, list[str]]], known: set[int]) -> None:
    """A reference that resolves to nothing: 410, or 404 above the highest
    number the repository has used (issues, pull requests, discussions)."""
    bad = 0
    for repo in sorted(refs_by_repo):
        nums = sorted(n for n in refs_by_repo[repo] if not (repo == own and n in known))
        if not nums:
            continue
        o, n = repo.split("/", 1)
        for c in range(0, len(nums), REF_CHUNK):
            chunk = nums[c:c + REF_CHUNK]
            fields = " ".join(f"n{x}:issueOrPullRequest(number:{x}){{__typename}} d{x}:discussion(number:{x}){{number}}"
                              for x in chunk)
            q = ("query($owner:String!,$name:String!){repository(owner:$owner,name:$name){"
                 "i:issues(first:1,orderBy:{field:CREATED_AT,direction:DESC}){nodes{number}} "
                 "p:pullRequests(first:1,orderBy:{field:CREATED_AT,direction:DESC}){nodes{number}} "
                 "dd:discussions(first:1,orderBy:{field:CREATED_AT,direction:DESC}){nodes{number}} "
                 + fields + "}}")
            ans = graphql(f"refs-{o}-{n}-{c // REF_CHUNK + 1}", q, {"owner": o, "name": n}) or {}
            data = (ans.get("data") or {}).get("repository")
            errors = ans.get("errors") or []
            if not isinstance(data, dict):
                for x in chunk:
                    line("SKIP", f"{repo}#{x} not verified: {repo} could not be read "
                                 f"({'; '.join(e.get('type') or e.get('message', '') for e in errors) or 'no answer'})")
                continue
            # A NOT_FOUND error on one field is that field's answer, not the query's.
            other = {tuple(e.get("path") or []) for e in errors if e.get("type") != "NOT_FOUND"}
            highest = max([x.get("number", 0) for k in ("i", "p", "dd") for x in (data.get(k) or {}).get("nodes") or []]
                          or [0])
            for x in chunk:
                if data.get(f"n{x}") or data.get(f"d{x}"):
                    continue
                if any(p[:2] in (("repository", f"n{x}"), ("repository", f"d{x}")) for p in other):
                    line("SKIP", f"{repo}#{x} not verified: GitHub answered an error for it")
                    continue
                status, _ = rest(f"repos/{repo}/issues/{x}")
                where = ", ".join(refs_by_repo[repo][x][:3]) + (" and more" if len(refs_by_repo[repo][x]) > 3 else "")
                shown = f"#{x}" if repo == own else f"{repo}#{x}"
                if status == 410:
                    line("WARN", f"ref: {shown} was deleted (410), referenced in {where}", "ref")
                    bad += 1
                elif status == 404 and x > highest:
                    line("WARN", f"ref: {shown} resolves to nothing (404, above {repo}'s highest number, {highest}), "
                                 f"referenced in {where}", "ref")
                    bad += 1
                elif status in (200, 301):
                    continue
                else:
                    line("SKIP", f"{shown} not verified: status {status or 'no answer'} at or below the highest "
                                 f"number, {highest}")
    if not bad:
        line("PASS", "ref: every #N and owner/repo#N read resolves, or is not verified above")


def check(root: Path, repo: str) -> None:
    owner, name = repo.split("/", 1)
    issues = read_all("issues", "issues", ISSUES_Q, owner, name)
    pulls = read_all("pulls", "pullRequests", PULLS_Q, owner, name)
    line("INFO", f"{repo}: {len(issues)} issues and {len(pulls)} pull requests read")
    items = [(i, "issue") for i in issues] + [(p, "pull request") for p in pulls]
    known = {x["number"] for x, _ in items if isinstance(x.get("number"), int)}

    # Facts.
    refs_by_repo: dict[str, dict[int, list[str]]] = {}
    hp = big = 0
    for x, _ in items:
        body = x.get("body") or ""
        url = x.get("url", "")
        for r, n in refs(body):
            refs_by_repo.setdefault((r or repo).casefold(), {}).setdefault(n, []).append(url)
        for ln, form in home_paths(body):
            line("WARN", f"home-path: {url} line {ln}: a home path ({form})", "home-path")
            hp += 1
        chars, octets = size(body)
        if max(chars, octets) >= NEAR:
            line("WARN", f"body-size: {url}: {chars} characters, {octets} UTF-8 bytes of GitHub's {LIMIT}", "body-size")
            big += 1
    if not hp:
        line("PASS", "home-path: no home path in a body")
    if not big:
        line("PASS", f"body-size: every body under 90% of {LIMIT}, in characters and in UTF-8 bytes")
    resolve(repo.casefold(), refs_by_repo, known)

    # Conventions.
    conv = read_conventions(root, owner)
    completed = [i for i in issues if i.get("state") == "CLOSED" and i.get("stateReason") == "COMPLETED"]

    ending, ending_from = ending_convention(conv)
    if not ending:
        line("SKIP", "ending: not checked: convention not read (no file says which heading ends an issue; "
                     "plinth's default is `## Outcome`, `## Decision` for a record, written in "
                     "docs/agents/issue-tracker.md)")
    else:
        miss = 0
        shown = ", ".join(f"`{h}`" for h in sorted(ending))
        for i in completed:
            labels = i.get("labels") or {}
            got = [lb.get("name", "") for lb in labels.get("nodes") or []]
            if (labels.get("totalCount") or 0) > len(got) and not set(got) & set(KIND_LABELS):
                line("SKIP", f"ending: {i.get('url')} not verified: its labels were cut at {LABELS_PAGE}")
                continue
            if not set(got) & set(KIND_LABELS):
                continue
            hs = [h for _, _, h in headings(i.get("body") or "")]
            if any(named(h, ending | {RECORD_HEADING}) for h in hs):
                continue
            line("WARN", f"ending: {i.get('url')} closed completed with no ending section ({shown}, "
                         f"from {', '.join(ending_from)})", "ending")
            miss += 1
        if not miss:
            line("PASS", f"ending: every completed task or bug has an ending section ({shown}, from {', '.join(ending_from)})")

    keys, trailer_from = trailer_convention(conv)
    if not keys:
        line("SKIP", "trailer: not checked: convention not read (no file names an AI trailer; plinth's default is "
                     "`Assisted-by: <agent>:<model>`, written in CONTRIBUTING.md)")
    else:
        none = 0
        for p in pulls:
            if not p.get("merged"):
                continue
            if has_trailer(p.get("body"), keys) or has_trailer((p.get("mergeCommit") or {}).get("message"), keys):
                continue
            line("INFO", f"trailer: {p.get('url')}: no trailer", "trailer")
            none += 1
        if not none:
            line("PASS", f"trailer: every merged pull request carries one ({', '.join(sorted(keys))}, "
                         f"from {', '.join(trailer_from)})")

    names, crit_from = criteria_convention(conv)
    if not names:
        line("SKIP", "criteria: not checked: convention not read (no file names an acceptance-criteria heading; "
                     "plinth's default is `## Acceptance criteria`, in the task form)")
    else:
        found = [(i.get("url"), unticked_criteria(i.get("body") or "", names)) for i in completed]
        found = [(u, lns) for u, lns in found if lns]
        counts["criteria"] = len(found)
        line("INFO", f"for a person to read: {len(found)} completed issues leave acceptance criteria unticked "
                     f"(heading from {', '.join(crit_from)}); whether each ending says why is not judged")
        for u, lns in found:
            line("INFO", f"  {u} line {', '.join(map(str, lns))}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=(__doc__ or "").split("\n\n")[0])
    ap.add_argument("--root", default=".")
    ap.add_argument("--repo")
    ap.add_argument("--host", choices=("github", "gitlab"))
    a = ap.parse_args(argv)
    root = Path(a.root)
    if host_of(root, a.host) == "gitlab":
        print("  INFO  GitLab: not read")
        return 0
    if not a.repo or not re.fullmatch(r"[\w.-]+/[\w.-]+", a.repo):
        print("records-check: could not run: no --repo owner/name", file=sys.stderr)
        return 2
    try:
        check(root, a.repo)
    except CannotRun as e:
        print(f"records-check: could not run: {e}", file=sys.stderr)
        return 2
    rules = ("ref", "home-path", "body-size", "ending", "trailer")
    per = ", ".join(f"{r} {counts.get(r, 0)}" for r in rules)
    print(f"-- {per}; for a person to read: criteria {counts.get('criteria', 0)}; "
          f"{unchecked} rules not checked; {skips} not verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
