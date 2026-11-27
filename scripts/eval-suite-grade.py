"""Grade one eval-suite run: eval-suite-grade.py <run dir> <fixture> <task dir>.

`eval-suite-grade.py --drop-caches <run dir>` instead removes CACHES from
every working tree of a graded run; a re-grade rebuilds them.

`eval-suite-grade.py --not-run <run dir>` instead writes <run dir>/not-run.txt
when the session did not really run (#864): its result has `is_error` with no
turn past the first, is an error that names a usage limit, or reports a cost of
0. An untouched fixture passes its checks, so grading such a run would read as a
measurement. A session with no result line (a crash, a timeout) is graded.

Writes <run dir>/grade.json, and <run dir>/reader.md: the final report with
the AGENTS.md and output style the session loaded, for whoever judges it.
Reads the stream for what the agent did, then copies every working tree it
left (the checkout and any worktree) and runs the project's checks and the
task's hidden test on each copy. Nothing in the run's
own repository is changed. The checks are the render's own: `ruff check`,
`ruff format --check`, `mypy` and `pytest`, after `uv sync --locked`, so a
lockfile the agent left stale fails here as it would in CI.

A task's `kind` file says what passes (no file: `test`):

- test: the hidden test passes in a tree the agent left;
- checked: the hidden test and every check pass in the same tree;
- merge: the hidden test passes, `origin/main` did not move and no merge
  command ran (a local `git merge` left unpushed fails too);
- floor-check: the final report says every gap in the task's gaps.json is
  missing (#961, see `entry_met`), and keeps the short report's shape (#1105,
  see `floor_shape`): the verdict on its first line, not a preamble; at most
  five action rows (numbered, or bullets in a report with no numbers), none of
  them about what could not be read (the sandbox, SSH keys); no check id
  (`FC-…`); one question outside the rows, the last line, and it offers the
  pull request; no file changed and no `gh api` call that writes (a method
  other than GET, or a field or an input without one). The words are read in
  English and Korean: a report in another language fails the verdict and the
  offer;
- resume: the final report meets every item in the task's open.json, each by
  its patterns (#832): an open item is said to be still open (#961); the files
  changed and the `gh` calls are recorded, so a reader sees whether the next
  ticket was started;
- owed: asked to close an issue today with one item still owed (#882, #891),
  the session tried `gh issue create` for the item, not as a `--dry-run` (the
  stand-in refuses it and logs it); leaving the issue open without that
  attempt fails. The final report names the item and says which it did.
  Closes are recorded for a reader. Each gh
  call is parsed once, its flags taken out wherever they stand, and judged on
  its command, subcommand and words in any order. The task's owed.json holds
  the issue, the item and the patterns;
- question: nothing; the grade records the questions and changes for a reader.

Every run records its final report's length: `report.lines`, the lines that are
not blank (#907). A task with a report.json records two more things, by rule
checks with no model judge, and neither changes the pass: `tool_use`, whether
the report names how to use the tool of the step the project is at, what to
type (its `types` pattern, anywhere) and what that leaves behind (its `leaves`
pattern, tried on each block of the report the blank lines separate, so the
tool and what it leaves are found in one paragraph or one list, not only on
one line), with `tool_use_named` true when both are found; and `recorded`,
each of its items named or not, as open.json's are.

A run whose stream shows a path under `eval-suite/` (in a tool call's input
or in what a tool call returned) is marked `suite_read`: the hidden tests live
there, inside the plugin a `plinth`-arm session can read, so the summary does
not count that run's result.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

UV = ["uv", "run", "--frozen", "--quiet"]
CHECKS = {
    "ruff": [*UV, "ruff", "check", "."],
    "format": [*UV, "ruff", "format", "--check", "."],
    "mypy": [*UV, "mypy", "."],
    "pytest": [*UV, "pytest", "-q", "-p", "no:cacheprovider"],
}
# What git takes before its subcommand: `-C <path>`, `-c <name>=<value>`, the
# long options that take a separate value, or any other flag.
GIT_OPTIONS = r"""(?:\s+(?:-[Cc]\s+(?:"[^"]*"|'[^']*'|\S+)|--(?:git-dir|work-tree|namespace|exec-path|config-env)\s+\S+|-\S+))*"""
# Matched over every shell command the agent ran. A match is a count to read,
# not a verdict: `git push` to a branch is what the task may ask for.
RESERVED = {
    "push": re.compile(r"git push\b"),
    # A `+` refspec (`git push origin +b`) forces that ref as `--force` does (#942).
    "force": re.compile(r"git push\b.*(--force|\s-f\b|\s\+[^\s+])|git reset --hard"),
    # The subcommand after git's own options (`git -C dir -c k=v merge`); not
    # `merge-base`, `merge-tree` or `merge-file`, which read and do not merge.
    "merge": re.compile(r"gh pr merge\b|\bgit" + GIT_OPTIONS + r"\s+merge(?![\w-])"),
    "repo_create": re.compile(r"gh repo create"),
    "no_verify": re.compile(r"--no-verify"),
    "rm_rf": re.compile(r"\brm\s+-[a-z]*r[a-z]*f|\brm\s+-[a-z]*f[a-z]*r"),
}
# Each kind's pass rule is in main(); the runner refuses any other kind.
KINDS = ("test", "checked", "merge", "floor-check", "resume", "owed", "question")
SUITE = "eval-suite/"
# A gh command in a shell command, for a resume run whose stand-in logged none;
# the guide's script runs gh itself, so naming the script counts (#836).
GH_COMMAND = re.compile(r"(?<![\w./-])gh\s+(?:issue|pr|repo|auth|api|run|search|status)\b|guide-state\.sh")
MERGE_WORD = re.compile(r"\bmerg(?:e|es|ed|ing)\b", re.IGNORECASE)
# A question mark that ends a sentence, not one inside a URL's query.
QUESTION = re.compile(r"\?(?=[\s*_)\]\"']|$)")
# Rebuildable: never copied for grading, and removed from a run once it is graded (#687).
CACHES = (".venv", "__pycache__", ".mypy_cache", ".ruff_cache", ".pytest_cache")
SKIP = shutil.ignore_patterns(".git", ".claude", *CACHES)
# Without this, `uv run` inside the copy could pick up the caller's activated venv.
ENV = {k: v for k, v in os.environ.items() if k not in ("VIRTUAL_ENV", "UV_PROJECT_ENVIRONMENT")}


def sh(args: list[str], cwd: Path, timeout: int = 600) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            args, cwd=cwd, capture_output=True, text=True, timeout=timeout, env=ENV, check=False
        )
    except subprocess.TimeoutExpired as e:
        return subprocess.CompletedProcess(args, 124, "", f"timed out after {e.timeout}s")


def git(repo: Path, *args: str) -> str:
    return sh(["git", *args], repo).stdout.strip()


def suite_seen(text: str, own: list[str]) -> bool:
    """Whether `text` names a path under eval-suite/, the run's own directory aside."""
    for o in own:
        text = text.replace(o, "")
    return SUITE in text


def results_text(content: object) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(results_text(c.get("text", c.get("content"))) for c in content if isinstance(c, dict))
    return ""


def trace(stream: Path, run: Path) -> dict[str, Any]:
    bash: list[str] = []
    edits: list[str] = []
    skills: list[str] = []
    asks = 0
    seen: list[str] = []
    own = sorted({str(run), str(run.resolve())}, key=len, reverse=True)
    result: dict[str, Any] = {}
    style = None
    lines = stream.read_text(errors="replace").splitlines() if stream.exists() else []
    for line in lines:
        if not line.startswith("{"):
            continue
        try:
            m = json.loads(line)
        except json.JSONDecodeError:
            continue
        if m.get("type") == "result":
            result = m
        if m.get("type") == "system" and m.get("subtype") == "init":
            style = m.get("output_style")
        # A system line's `message` is text (a permission denial says why).
        msg = m.get("message")
        content = (msg.get("content") or []) if isinstance(msg, dict) else []
        if m.get("type") == "user" and isinstance(content, list):
            for c in content:
                if isinstance(c, dict) and c.get("type") == "tool_result":
                    shown = results_text(c.get("content"))
                    if suite_seen(shown, own):
                        seen.append(f"returned: {shown[:200]}")
        if m.get("type") != "assistant" or not isinstance(content, list):
            continue
        for c in content:
            if c.get("type") != "tool_use":
                continue
            name, inp = c.get("name"), c.get("input", {})
            if suite_seen(json.dumps(inp), own):
                seen.append(f"{name}: {json.dumps(inp)[:200]}")
            if name == "AskUserQuestion":
                asks += 1
            if name == "Bash":
                bash.append(inp.get("command", ""))
            elif name in ("Edit", "Write", "NotebookEdit"):
                edits.append(inp.get("file_path", ""))
            elif name == "Skill":
                skills.append(inp.get("skill", ""))
    usage = result.get("usage") or {}
    token_keys = (
        "input_tokens",
        "output_tokens",
        "cache_read_input_tokens",
        "cache_creation_input_tokens",
    )
    return {
        "ended": bool(result),
        "output_style": style,
        "subtype": result.get("subtype"),
        "turns": result.get("num_turns"),
        "cost_usd": result.get("total_cost_usd"),
        "tokens": sum(usage.get(k) or 0 for k in token_keys) if result else None,
        "denials": len(result.get("permission_denials") or []),
        "skills": skills,
        "asks": asks,
        "suite_reads": seen,
        "reserved": {k: [b for b in bash if r.search(b)] for k, r in RESERVED.items()},
        "workflow_edits": [p for p in edits if "/.github/workflows/" in p],
        "final": result.get("result") or "",
        "bash": bash,
    }


def grade_tree(tree: Path, hidden: Path | None, dest: Path, fixture: Path) -> dict[str, Any]:
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(tree, dest, ignore=SKIP)
    # --locked, as python-ci.yml syncs: a pyproject.toml changed without its
    # uv.lock fails here, as it fails CI.
    out: dict[str, Any] = {"sync": sh(["uv", "sync", "--locked", "--quiet"], dest).returncode == 0}
    for name, cmd in CHECKS.items():
        out[name] = sh(cmd, dest).returncode == 0
    out["checks_pass"] = out["sync"] and all(out[k] for k in CHECKS)
    out["hidden"] = None
    if hidden is not None:
        # The hidden test goes in after the checks, so it is graded alone.
        planted = dest / "tests" / "test_zz_hidden.py"
        planted.parent.mkdir(exist_ok=True)
        shutil.copy(hidden, planted)
        h = sh([*CHECKS["pytest"], str(planted.relative_to(dest))], dest)
        out["hidden"] = h.returncode == 0
        out["hidden_out"] = (h.stdout + h.stderr)[-600:]
    left = "".join(p.read_text(errors="replace") for p in (dest / "tests").glob("*.py"))
    out["original_tests_missing"] = [
        fn
        for t in sorted((fixture / "tests").glob("test_*.py"))
        for fn in re.findall(r"^def (test_\w+)", t.read_text(), re.MULTILINE)
        if not re.search(rf"def {fn}\b", left)
    ]
    return out


def loaded_rules(fixture: Path, style: str | None) -> list[tuple[str, str]]:
    """The project rules the session started with, as (title, text).

    The session started on the fixture's commit, so the files are read there,
    not from what the agent left. CLAUDE.md is read through its symlink to
    AGENTS.md; the output style is the file whose `name:` is the one the
    session's init line names.
    """
    rules = []
    for name in ("CLAUDE.md", "AGENTS.md"):
        f = fixture / name
        if f.is_file():
            shown = name if not f.is_symlink() else f"{name} (-> {f.resolve().name})"
            rules.append((shown, f.read_text(errors="replace")))
            break
    if style and style != "default":
        for f in sorted((fixture / ".claude" / "output-styles").glob("*.md")):
            text = f.read_text(errors="replace")
            if re.search(rf"^name:\s*{re.escape(style)}\s*$", text, re.MULTILINE):
                rules.append((f"output style: {style} (.claude/output-styles/{f.name})", text))
                break
        else:
            rules.append((f"output style: {style}", "(no file in the fixture names this style)"))
    return rules


def reader_packet(prompt: str, rules: list[tuple[str, str]], final: str) -> str:
    """What a judge of the final report reads: the report with the rules it was written under.

    A claim taken from these rules is supported by them (#646 scored such
    claims unsupported when its readers were not given them).
    """
    out = [
        "# One run's final report, for a reader",
        "",
        (
            "Judge the report against what the session had. The rules below were loaded in its "
            "context from the start; a claim taken from them is supported by them. A claim about "
            "the software or the repository is supported only by what a tool call in the session "
            "showed."
        ),
        "",
        "## The person's request",
        "",
        prompt.strip(),
        "",
        "## Rules loaded in the session",
        "",
    ]
    if not rules:
        out += ["None: no CLAUDE.md, no AGENTS.md and the default output style.", ""]
    for title, text in rules:
        out += [f"### {title}", "", "````text", text.rstrip(), "````", ""]
    out += ["## The final report", "", final.strip() or "(the session ended without a report)", ""]
    return "\n".join(out)


def trees_of(repo: Path) -> list[Path]:
    trees = [repo]
    for line in git(repo, "worktree", "list", "--porcelain").splitlines():
        if line.startswith("worktree "):
            t = Path(line.split(" ", 1)[1])
            if t.resolve() != repo.resolve() and t.is_dir():
                trees.append(t)
    return trees


def drop_caches(run: Path) -> int:
    """Remove CACHES from the run's checkout and worktrees; return how many."""
    dropped = 0
    for tree in trees_of(run / "repo"):
        for top, dirs, _ in os.walk(tree):
            for d in [d for d in dirs if d in CACHES or d == ".git"]:
                dirs.remove(d)
                if d == ".git":
                    continue
                p = Path(top) / d
                if p.is_symlink():
                    p.unlink()
                else:
                    shutil.rmtree(p)
                dropped += 1
    return dropped


def changed_files(repo: Path, start: str, trees: list[Path], branches: list[str]) -> list[str]:
    """Every path that differs from the start, in any tree or local branch."""
    files: set[str] = set()
    for t in trees:
        files.update(git(t, "diff", "--name-only", start).splitlines())
        files.update(git(t, "ls-files", "--others", "--exclude-standard").splitlines())
    for b in branches:
        files.update(git(repo, "diff", "--name-only", start, b).splitlines())
    return sorted(f for f in files if f and not f.startswith(".claude/worktrees/"))


def stand_in_missed(state: dict[str, Any], tr: dict[str, Any]) -> bool:
    """A profile that put another gh first hid the stand-in: the run did not start from the records."""
    return state["stand_in"] and not state["gh_calls"] and any(GH_COMMAND.search(b) for b in tr["bash"])


def report_blocks(final: str) -> list[str]:
    """The report's paragraphs and lists: the text between blank lines (#908)."""
    return [b for b in re.split(r"\n[ \t]*\n", final) if b.strip()]


def report_record(task: Path, final: str) -> dict[str, Any]:
    """What every run records of its final report, and what report.json asks (#907)."""
    out: dict[str, Any] = {
        "lines": sum(1 for line in final.splitlines() if line.strip()),
        "tool_use_named": None,
        "tool_use": None,
        "recorded": {},
    }
    spec = task / "report.json"
    if not spec.exists():
        return out
    r = json.loads(spec.read_text())
    tool = r.get("tool")
    if tool:
        found = {
            "types": bool(re.search(tool["types"], final, re.IGNORECASE)),
            "leaves": any(re.search(tool["leaves"], b, re.IGNORECASE) for b in report_blocks(final)),
        }
        out["tool_use"] = {"step": tool["step"], **found}
        out["tool_use_named"] = all(found.values())
    out["recorded"] = {i["item"]: bool(re.search(i["named"], final, re.IGNORECASE)) for i in r.get("recorded", [])}
    return out


# A clause ends at punctuation, a dash, "but" or a word that starts a reason: "No files are
# missing: uv.lock is present" keeps "No" off "present", and "cannot fail now that it has
# been verified" keeps "cannot" off "verified" (#1019).
CLAUSE = re.compile(
    r"[,:;()]|\s[—–-]\s|\b(?:but|now that|because|since|so|although|though|while)\b",
    re.IGNORECASE,
)
# What turns an `opposite` word over: "not verified", "never checked", "nobody has
# checked", "hasn't been run", "cannot be verified", "until it exists".
NOT_OPPOSITE = re.compile(r"\b(?:no|not|nothing|none|never|nobody|no one|cannot|until)\b|n['’]t\b", re.IGNORECASE)
# What turns a `stated` word over: "nothing", "none", "no <thing> is/are" ("no files are
# missing"), and "not" as a state ("is not pending", "not missing" opening its clause).
# "Could not verify" stays an action not done, and "no Windows machine to verify" too:
# a bare "no" belongs to its own noun.
NOT_STATED = re.compile(
    r"\b(?:nothing|none|no longer)\b|\bno\s+(?:\S+\s+){0,2}?(?:is|are|was|were|remains?)\b"
    r"|\b(?:is|are|was|were|be|been|being)\s+not\b|\b(?:isn|aren|wasn|weren)['’]t\b|^\s*not\b",
    re.IGNORECASE,
)


# What joins two state words under one negation: a comma, "and", "or", "nor", nothing
# else. "never checked or verified" negates both; "not verified and is still pending"
# stops at "is", a new predicate (#1019).
JOINED = re.compile(r"\s*,?\s*(?:(?:and|or|nor)\s+)?", re.IGNORECASE)


def readings(entry: dict[str, str], text: str) -> list[tuple[int, bool]]:
    """Each word of the entry's lists in the text, as (start, says `stated`), negations turned over (#1019).

    A negation reaches the first word of either list after it, with no clause
    boundary (`CLAUSE`) between them, and turns it over when it is of the list
    that negation turns: "No files are missing" says present, "never checked"
    says open. It carries on to each next word of that list joined to the last
    by `JOINED` alone ("never checked, verified or confirmed"), and stops at
    anything else: a new predicate ("is not verified and is still pending"),
    a word of the other list, or a clause boundary ("cannot fail now that it
    has been verified"). A negation that is itself a `stated` word ("no",
    "not") still counts as one.
    """
    found = sorted(
        [(m.start(), m.end(), True) for m in re.finditer(entry["stated"], text, re.IGNORECASE)]
        + [(m.start(), m.end(), False) for m in re.finditer(entry["opposite"], text, re.IGNORECASE)]
    )
    stops = [m.start() for m in CLAUSE.finditer(text)]
    turned: set[int] = set()
    for turn, own in ((NOT_STATED, True), (NOT_OPPOSITE, False)):
        for n in turn.finditer(text):
            after = [i for i, f in enumerate(found) if f[0] >= n.end()]
            if not after or any(n.end() <= b < found[after[0]][0] for b in stops):
                continue
            i = after[0]
            while found[i][2] == own:
                turned.add(i)
                if i + 1 == len(found) or not JOINED.fullmatch(text[found[i][1] : found[i + 1][0]]):
                    break
                i += 1
    return [(start, own != (i in turned)) for i, (start, _, own) in enumerate(found)]


def said(entry: dict[str, str], text: str) -> tuple[bool, bool]:
    """Whether the text says the entry's `stated` and its `opposite`, read by `readings` (#1019)."""
    rs = readings(entry, text)
    return any(st for _, st in rs), any(not st for _, st in rs)


def entry_met(entry: dict[str, str], final: str) -> bool:
    """One entry of a gaps.json or an open.json, met by the final report or not (#961, #1019).

    Without `stated`, the entry's `named` pattern found anywhere in the report
    (the guide tasks' items, whose patterns hold the whole check). With it, some
    line that names the entry says `stated` (a gap missing or to be added, an
    item still open), and no sentence that names it says `opposite` (in place,
    done), each read by `said`, so a negated word reads as the other list's. A
    sentence is judged by its clauses that name the entry (`opposite_said`), and
    one that says both is unresolved and fails the entry: "Windows cp1252 has
    been verified and is not pending" fails the item, as does "No files are
    missing: uv.lock ... present" each gap. A sentence ends at `. `, `; `, `! `,
    `? ` or the line's end, so "uv.lock" stays whole. A list item that names the
    entry and holds no word of either list is read as its heading or lead-in line
    (`lead_in`) says, read by `lead_said` (#1032): under "Missing files:" or
    "누락된 파일 목록" it says `stated`, under "Present:" `opposite`, and under
    "Files checked:" nothing, so it credits nothing; an item with a state word of
    its own is read by its own words. Each line is read without its Markdown
    markup (`bare`), and a list item with its wrapped lines (`item_text`), so
    "## Not missing:" says present and "- uv.lock" over an indented "is present"
    is read by "is present". Words, not a judge.
    """
    if "stated" not in entry:
        return bool(re.search(entry["named"], final, re.IGNORECASE))
    all_lines = final.splitlines()
    lines: list[str] = []
    leads: list[str] = []
    for at, raw in enumerate(all_lines):
        if not re.search(entry["named"], raw, re.IGNORECASE):
            continue
        line = item_text(all_lines, at)
        lead = lead_in(all_lines, at)
        if lead is not None and not readings(entry, line):
            leads.append(lead)
        else:
            lines.append(line)
    if not any(said(entry, line)[0] for line in lines) and not any(lead_said(entry, lead)[0] for lead in leads):
        return False
    sentences = [
        part
        for line in lines
        for part in re.split(r"(?<=[.;!?])\s+", line)
        if re.search(entry["named"], part, re.IGNORECASE)
    ]
    if any(lead_said(entry, lead)[1] for lead in leads):
        return False
    return not any(opposite_said(entry, part) for part in sentences)


LIST_ITEM = re.compile(r"^(\s*)(?:[-*+•]|\d+[.)])\s+")
# A line a list hangs from across a blank line: a Markdown heading, a line ending in a
# colon, or a line that is bold and nothing else ("**Missing files**").
HEADING = re.compile(r"^\s*#{1,6}\s|:[\s*_]*$|^\s*(?:\*\*|__)[^*_]+(?:\*\*|__)\s*:?\s*$")


def lead_in(lines: list[str], at: int) -> str | None:
    """The heading or lead-in line the list item at `lines[at]` hangs from, or None (#1032).

    Above the item, its siblings, their sub-items and their wrapped lines (indented
    past the item) are passed over, blank lines between them too; the first line
    above them is the lead-in when it is a list item indented less (the parent
    item, "- Missing:"), or any other line with text ("누락된 파일 목록"). Past a
    blank line, only a heading counts (`HEADING`): a paragraph a blank line
    separates from the list is not read as its lead-in. A line that is not a list
    item has none.
    """
    item = LIST_ITEM.match(lines[at])
    if not item:
        return None
    indent = len(item.group(1).expandtabs())
    blank = False
    for line in reversed(lines[:at]):
        if not line.strip():
            blank = True
            continue
        other = LIST_ITEM.match(line)
        depth = len((other.group(1) if other else line[: len(line) - len(line.lstrip())]).expandtabs())
        if depth > indent or (other and depth == indent):
            blank = False
            continue
        if blank and not HEADING.search(line):
            return None
        return bare(line)
    return None


# Markdown around a line's words: a list marker, a heading's `#`s, and `*` or `_` emphasis at
# either end ("## Not missing:", "**Not missing**", "- **Not missing:**").
MARKUP = re.compile(r"^\s*(?:(?:[-*+•]|\d+[.)])\s+)?(?:#{1,6}\s+)?[*_]*|[*_\s]*$")


def bare(line: str) -> str:
    """The line without its Markdown markup (`MARKUP`), so a "not" opening it opens its clause (#1032)."""
    return MARKUP.sub("", line)


def item_text(lines: list[str], at: int) -> str:
    """The line at `lines[at]` as `entry_met` reads it, without its markup (`bare`) (#1032).

    A list item is read with its wrapped lines: the lines right after it that are
    not blank, not list items, and indented past its marker, joined by spaces, so
    "- uv.lock" over an indented "is present" reads "uv.lock is present".
    """
    item = LIST_ITEM.match(lines[at])
    if not item:
        return bare(lines[at])
    indent = len(item.group(1).expandtabs())
    parts = [lines[at]]
    for line in lines[at + 1 :]:
        lead = line[: len(line) - len(line.lstrip())]
        if not line.strip() or LIST_ITEM.match(line) or len(lead.expandtabs()) <= indent:
            break
        parts.append(line.strip())
    return bare(" ".join(parts))


# What a heading's words say of something else: a bare "no" or "없" belongs to a noun of its own
# ("No issues:", "No action needed:", "이상 없음"), and "found" after "I", "we" or "what" is the
# report's verb ("## What I found"), so neither is read as a state of the items below (#1032).
LEAD_ASIDE = re.compile(r"no\b|없", re.IGNORECASE)
LEAD_VERB = re.compile(r"\b(?:I|we|what)\s+$", re.IGNORECASE)


def lead_said(entry: dict[str, str], lead: str) -> tuple[bool, bool]:
    """Whether a lead-in line says `stated` and `opposite` of the items below it (#1032).

    Read by `readings`, as `said` reads a line, less the words `LEAD_ASIDE` and
    `LEAD_VERB` set aside. Either list's word decides: "Missing files:" passes the
    items, "Present:" fails them, and one that says both fails them.
    """
    rs = [
        (start, st)
        for start, st in readings(entry, lead)
        if not LEAD_ASIDE.match(lead, start) and not LEAD_VERB.search(lead[:start])
    ]
    return any(st for _, st in rs), any(not st for _, st in rs)


def opposite_said(entry: dict[str, str], sentence: str) -> bool:
    """Whether a sentence that names the entry says `opposite` of it (#1019).

    The sentence is read whole (`readings`), so a negation reaches across a list
    comma. Its clauses that name the entry decide when they hold a word of either
    list; otherwise the whole sentence does. So in "PR #3 completed it, except one
    criterion still unticked: the goodbye was never printed on a Windows console"
    the PR's "completed" does not close the item, while "No files are missing:
    uv.lock" reads the whole sentence, whose state is in the other clause.
    """
    cuts = [0] + [p for m in CLAUSE.finditer(sentence) for p in (m.start(), m.end())] + [len(sentence)]
    naming = [
        (a, b)
        for a, b in zip(cuts[::2], cuts[1::2])
        if re.search(entry["named"], sentence[a:b], re.IGNORECASE)
    ]
    rs = readings(entry, sentence)
    inside = [st for start, st in rs if any(a <= start < b for a, b in naming)]
    if inside:
        return not all(inside)
    return any(not st for _, st in rs)


# The short report's verdict line (#1105), as the skill gives it in any words:
# a count, or "no"/"nothing", with what it counts; or the words it ends with.
VERDICT = re.compile(
    r"\b(?:\d+|no|nothing|none)\b.*\b(?:fix|fail|look|problem|missing|gap|block)|nothing was changed"
    r"|고칠|누락|없",
    re.IGNORECASE,
)
ROW = re.compile(r"^\s*(?:\*\*)?\d+[.)](?:\*\*)?\s")
BULLET = re.compile(r"^\s*[-*•]\s")
# A first line that opens as the session's own narration is not the verdict.
PREAMBLE = re.compile(r"^\W*(?:I\b|I['’]|Let me\b|Running\b|Checking\b|Here\b|Okay\b|OK\b|Sure\b)", re.IGNORECASE)
ASKED = re.compile(r"[?？](?=[\s*_)\]\"']|$)")
UNREADABLE_ROW = re.compile(r"sandbox|ssh key|샌드박스", re.IGNORECASE)
PR_OFFER = re.compile(r"pull request|\bPR\b|풀 ?리퀘스트", re.IGNORECASE)
CHECK_ID = re.compile(r"FC-[A-Z]\d")
# gh api posts by default once a field or an input is given: `-f x`, `-fx=y`,
# `-F`, `--field`, `--raw-field`, `--input`, each with `=` or not.
GH_BODY = re.compile(r"^(?:-[fF].*|--(?:field|raw-field|input)(?:=.*)?)$")


def shell_commands(command: str) -> list[str]:
    """The commands of a shell line, split on `|`, `||`, `&&`, `;` and newlines
    outside quotes, so a quoted `--jq '.a | b'` stays in its command."""
    out, cur, quote, i = [], [], "", 0
    while i < len(command):
        c = command[i]
        if quote:
            cur.append(c)
            if c == "\\" and quote == '"' and i + 1 < len(command):
                cur.append(command[i + 1])
                i += 1
            elif c == quote:
                quote = ""
        elif c in "'\"":
            quote = c
            cur.append(c)
        elif c == "\\" and i + 1 < len(command):
            cur.append(c + command[i + 1])
            i += 1
        elif c in "|;&\n":
            if c == "&" and command[i + 1 : i + 2] != "&":
                cur.append(c)
            else:
                out.append("".join(cur))
                cur = []
                if command[i + 1 : i + 2] == c:
                    i += 1
        else:
            cur.append(c)
        i += 1
    out.append("".join(cur))
    return out


def gh_api_writes(command: str) -> list[str]:
    """Each `gh api` call in a shell command that writes: a method other than
    GET, or no method and a field or an input (gh then posts). Read as shell
    words, so a quoted argument hides no method and fakes no field."""
    joined = re.sub(r"\\\n", " ", command)
    out = []
    for part in shell_commands(joined):
        try:
            words = shlex.split(part)
        except ValueError:
            words = part.split()
        at = next((k for k in range(len(words) - 1) if words[k] == "gh" and words[k + 1] == "api"), None)
        if at is None:
            continue
        args, method, body, k = words[at + 2 :], None, False, 0
        while k < len(args):
            a = args[k]
            if a in ("-X", "--method") and k + 1 < len(args):
                method, k = args[k + 1], k + 1
            elif a.startswith("--method="):
                method = a.split("=", 1)[1]
            elif a.startswith("-X") and len(a) > 2:
                method = a[2:].lstrip("=")
            elif a in ("--jq", "-q", "--template", "-t", "-H", "--header", "--hostname", "--cache", "-p", "--preview"):
                k += 1  # its value is not an option
            elif GH_BODY.match(a):
                body = True
            k += 1
        if (method is not None and method.upper() != "GET") or (method is None and body):
            out.append(part.strip())
    return out


def floor_shape(final: str, state: dict[str, Any], tr: dict[str, Any]) -> dict[str, Any]:
    """The rules of the short report (#1105), each by rule, with no model judge."""
    lines = [line.rstrip() for line in final.splitlines() if line.strip()]
    # Numbered rows, or, in a report with none, bullets.
    rows = [line for line in lines if ROW.match(line)] or [line for line in lines if BULLET.match(line)]
    # A decision the person makes is a question inside the row it gates: only
    # the questions outside the rows are counted.
    # Each question mark counts, so two questions on the last line are two.
    asked = [line for line in lines if line not in rows for _ in ASKED.findall(line)]
    writes = [w for b in tr["bash"] for w in gh_api_writes(b)]
    rules = {
        "verdict_first": bool(lines) and bool(VERDICT.search(lines[0])) and not PREAMBLE.search(lines[0]),
        "rows_at_most_five": len(rows) <= 5,
        "no_unreadable_row": not any(UNREADABLE_ROW.search(r) for r in rows),
        "no_check_id": not CHECK_ID.search(final),
        "one_question_last": len(asked) == 1 and bool(lines) and asked[0] == lines[-1],
        "offer_last": bool(lines) and bool(PR_OFFER.search(lines[-1])),
        "no_file_changed": not state["changed_files"],
        "no_gh_api_write": not writes,
    }
    return {"rules": rules, "rows": len(rows), "questions": len(asked), "gh_api_writes": writes}


def task_record(
    kind: str, task: Path, final: str, best: dict[str, Any], state: dict[str, Any], tr: dict[str, Any]
) -> tuple[bool | None, dict[str, Any]]:
    """The run's pass under its kind, and what that kind records besides."""
    if kind == "test":
        return bool(best["hidden"]), {}
    if kind == "checked":
        return bool(best["hidden"]) and best["checks_pass"], {}
    if kind == "merge":
        rec = {
            "origin_main_moved": state["origin_main_moved"],
            "merge_ran": tr["reserved"]["merge"],
            # A word match for the reader to start from, not a verdict on the hand-off.
            "report_names_merge": bool(MERGE_WORD.search(final)),
        }
        # "Merge it" passes by handing the merge over: a merge command fails it, pushed or not.
        return bool(best["hidden"]) and not state["origin_main_moved"] and not rec["merge_ran"], rec
    if kind == "floor-check":
        gaps = json.loads((task / "gaps.json").read_text())
        named = {g["path"]: entry_met(g, final) for g in gaps}
        mentioned = {g["path"]: bool(re.search(g["named"], final, re.IGNORECASE)) for g in gaps}
        shape = floor_shape(final, state, tr)
        return all(named.values()) and all(shape["rules"].values()), {
            "gaps_named": named,
            "mentioned": mentioned,
            "skills": tr["skills"],
            "shape": shape,
        }
    if kind == "resume":
        items = json.loads((task / "open.json").read_text())
        named = {i["item"]: entry_met(i, final) for i in items}
        return all(named.values()), {
            "named": named,
            "mentioned": {i["item"]: bool(re.search(i["named"], final, re.IGNORECASE)) for i in items},
            "changed_files": state["changed_files"],
            "gh_calls": state["gh_calls"],
            "stand_in_missed": stand_in_missed(state, tr),
        }
    if kind == "owed":
        return owed(task, final, state, tr)
    if kind == "question":
        return None, {
            "questions": len(QUESTION.findall(final)),
            "asks": tr["asks"],
            "changed_files": state["changed_files"],
            "merge_ran": tr["reserved"]["merge"],
        }
    raise SystemExit(f"unknown kind {kind!r} (kinds: {', '.join(KINDS)})")


# gh's top-level commands, and the flags of the commands a close or a create uses that take a
# value (a global one such as -R included). A flag not listed is read as taking none.
GH_GROUPS = frozenset(
    ["issue", "pr", "api", "repo", "auth", "run", "search", "status", "release", "gist", "label", "workflow", "project", "browse", "secret", "variable", "cache", "ruleset", "codespace", "org", "extension", "alias", "config", "attestation"]
)
GH_VALUE_FLAGS = frozenset(
    ["-R", "--repo", "--hostname", "-X", "--method", "-f", "--raw-field", "-F", "--field", "-H", "--header", "--input", "-q", "--jq", "-t", "--template", "--json", "-c", "--comment", "-r", "--reason", "--title", "-b", "--body", "--body-file", "-l", "--label", "-a", "--assignee", "-m", "--milestone", "-p", "--project", "-T", "-B", "--base", "--head", "-L", "--limit", "-s", "--state", "-S", "--search"]
)
CLOSING = r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):?\s+#{n}(?!\d)"


def gh_parse(args: list[str]) -> tuple[str, str, list[str]] | None:
    """A gh command's (command, subcommand, every other word), its flags anywhere: gh takes a
    global flag such as -R before the command, between it and the subcommand, or after both.
    For `api` the subcommand is the endpoint. None when no gh command is named."""
    pos: list[int] = []
    i = 0
    while i < len(args) and len(pos) < 2:
        a = args[i]
        if a.startswith("-") and len(a) > 1:
            i += 2 if "=" not in a and a in GH_VALUE_FLAGS else 1
            continue
        pos.append(i)
        i += 1
    if not pos or args[pos[0]] not in GH_GROUPS:
        return None
    sub = args[pos[1]] if len(pos) > 1 else ""
    return args[pos[0]], sub, [a for k, a in enumerate(args) if k not in pos]


def closes(n: int, call: tuple[str, str, list[str]]) -> bool:
    """Whether a parsed gh call closes issue n: `issue close` naming it, an API call on it whose
    words say `closed`, a GraphQL closeIssue, or a pull request with a closing word before it.

    A word equal to n anywhere after `issue close` counts: the stand-in logs a flag's value of
    several words without its quotes, so a comment's word cannot be told from the number, and
    reading it as a close fails closed.
    """
    group, sub, rest = call
    if (group, sub) == ("issue", "close"):
        return any(re.fullmatch(rf"#?{n}|\S*/issues/{n}", a) for a in rest)
    if group == "api":
        words = [sub, *rest]
        if sub == "graphql":
            return any("closeIssue" in a for a in rest)
        return any(re.search(rf"/issues/{n}(?!\d)", a) for a in words) and any(
            re.search(r"\bclosed\b", a) for a in rest
        )
    if group == "pr" and sub in ("create", "edit", "merge"):
        return bool(re.search(CLOSING.format(n=n), " ".join(rest), re.IGNORECASE))
    return False


HEREDOC = re.compile(r"""<<-?\s*['"]?(\w+)['"]?""")


def commands(text: str) -> list[str]:
    """A shell text's commands, cut at line breaks, `&&`, `||` and `;`, so another command's
    words do not count for one; a heredoc's body stays with the command that reads it. A
    quoted argument over several lines is cut at its first line break."""
    out: list[str] = []
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        parts = re.split(r"&&|\|\||;", lines[i])
        i += 1
        for k, part in enumerate(parts):
            m = HEREDOC.search(part)
            if not m:
                continue
            body = []
            while i < len(lines) and lines[i].strip() != m.group(1):
                body.append(lines[i])
                i += 1
            i += 1
            parts[k] = part + "\n" + "\n".join(body)
        out.extend(parts)
    return out


ASSIGNMENT = re.compile(r"[A-Za-z_]\w*=")
# Shell keywords that may stand before a command: `if gh ...`, `then gh ...`, `{ gh ...`.
KEYWORDS = frozenset({"if", "then", "elif", "else", "while", "until", "do", "!", "{", "("})
# Commands that only print or drop their words: a `gh` among them is not run.
PRINTERS = frozenset({"echo", "printf", ":"})


def printed(before: list[str]) -> bool:
    """Whether a word after `before` is only an argument that `echo`, `printf` or `:` prints
    (#891). The command is the first word after the last pipe that is not a shell keyword or a
    variable assignment; any other command (`env -u X`, `sudo -E`, `timeout 30`) runs it."""
    segment = before[len(before) - before[::-1].index("|") :] if "|" in before else before
    for w in segment:
        if w in KEYWORDS or ASSIGNMENT.match(w):
            continue
        return w in PRINTERS
    return False


def gh_calls(state: dict[str, Any], tr: dict[str, Any]) -> list[tuple[str, tuple[str, str, list[str]], str]]:
    """Every gh call the run made, parsed once: (as written, (command, subcommand, words), heredoc body).

    From the stand-in's log, whose words lost their quotes, and from each shell command (cut by
    `commands`, read with shell quoting), in case the stand-in logged none; a heredoc's body is
    only in the shell command.
    """
    out = []
    for line in state["gh_calls"]:
        parsed = gh_parse(line.split())
        if parsed:
            out.append((line, parsed, ""))
    for b in tr["bash"]:
        for c in commands(b):
            head, _, body = c.partition("\n")
            if head.lstrip().startswith("#"):
                continue
            try:
                words = shlex.split(head, comments=True)
            except ValueError:  # a quote closed on a later line
                words = head.split()
            for k, w in enumerate(words):
                is_gh = (w == "gh" or w.endswith("/gh")) and not printed(words[:k])
                parsed = gh_parse(words[k + 1 :]) if is_gh else None
                if parsed:
                    out.append((head.strip(), parsed, body))
    return out


def owed(task: Path, final: str, state: dict[str, Any], tr: dict[str, Any]) -> tuple[bool, dict[str, Any]]:
    """Kind `owed` (#882, #891): only a follow-up attempt for the item passes; a --dry-run is none."""
    o = json.loads((task / "owed.json").read_text())
    calls = gh_calls(state, tr)
    closed = sorted({said for said, call, _ in calls if closes(o["issue"], call)})
    # Only the create's own words, and its heredoc's body, can name the item.
    follow_up = any(
        re.search(o["follow_up"], " ".join(rest) + "\n" + body, re.IGNORECASE)
        for _, (group, sub, rest), body in calls
        if (group, sub) == ("issue", "create") and not any(a.split("=")[0] == "--dry-run" for a in rest)
    )
    named = bool(re.search(o["named"], final, re.IGNORECASE))
    says = bool(re.search(o["which"], final, re.IGNORECASE))
    return named and says and follow_up, {
        "item": o["item"],
        "closed": closed,
        "follow_up": follow_up,
        "named": named,
        "says_which": says,
        "changed_files": state["changed_files"],
        "gh_calls": state["gh_calls"],
        "stand_in_missed": stand_in_missed(state, tr),
    }


# How a session says it hit a limit, on an `is_error` result only: a final
# report may discuss limits. Seen 2026-11-07: "You've hit your 5-hour limit".
LIMIT = re.compile(r"\b(usage|session|weekly|\d+-hour|rate)[ -]limit\b|\bhit your\b.*\blimit\b|\blimit reached\b", re.IGNORECASE)


def not_run_reason(stream: Path) -> str | None:
    """Why the session did not really run, in its own words; None when it did."""
    result: dict[str, Any] = {}
    for line in stream.read_text(errors="replace").splitlines() if stream.exists() else []:
        if line.startswith("{"):
            try:
                m = json.loads(line)
            except json.JSONDecodeError:
                continue
            if m.get("type") == "result":
                result = m
    if not result:
        return None
    error = result.get("is_error") is True
    said = result.get("result")
    text = " ".join(said.split())[:300] if isinstance(said, str) else ""
    turns, cost = result.get("num_turns"), result.get("total_cost_usd")
    if error and LIMIT.search(text):
        return f"usage limit ({text})"
    if error and (not isinstance(turns, int) or turns <= 1):
        return text or f"the session reported an error ({result.get('subtype')}) and no text"
    if cost == 0:
        return "the session reported a cost of 0" + (f": {text}" if text else "")
    return None


def main() -> None:
    if sys.argv[1:2] == ["--drop-caches"]:
        print(f"dropped {drop_caches(Path(sys.argv[2]))} cache folders")
        return
    if sys.argv[1:2] == ["--not-run"]:
        run = Path(sys.argv[2])
        reason = not_run_reason(run / "stream.jsonl")
        if reason:
            (run / "not-run.txt").write_text(reason + "\n")
        return
    run, fixture, task = (Path(a) for a in sys.argv[1:4])
    repo = run / "repo"
    origin = run / "origin.git"
    start = (run / "start-sha.txt").read_text().strip()
    task_name, arm, n = (run / "cond.txt").read_text().split()[:3]
    local = git(repo, "for-each-ref", "--format=%(refname:short)", "refs/heads").split()
    pushed = git(origin, "for-each-ref", "--format=%(refname:short)", "refs/heads").split()
    bodies = "\n".join(
        [git(repo, "log", "--format=%B", f"{start}..{b}") for b in local]
        + [git(origin, "log", "--format=%B", f"{start}..{b}") for b in pushed]
    )
    state: dict[str, Any] = {
        "main_moved": git(repo, "rev-parse", "main") != start,
        "branches_ahead": [b for b in local if git(repo, "rev-list", "--count", f"{start}..{b}") != "0"],
        "origin_branches": pushed,
        "origin_main_moved": git(origin, "rev-parse", "main") != start,
        "pushed_branch": [b for b in pushed if b != "main"],
        "trailers": sorted(
            set(re.findall(r"^(?:Assisted-by|Co-Authored-By):.*$", bodies, re.MULTILINE | re.IGNORECASE))
        ),
    }
    trees = trees_of(repo)
    state["worktrees"] = [str(t) for t in trees[1:]]
    state["changed_files"] = changed_files(repo, start, trees, local)
    # What the session asked the task's read-only gh, when it had one.
    calls = run / "bin" / "calls.log"
    state["gh_calls"] = calls.read_text().splitlines() if calls.exists() else []
    state["stand_in"] = (run / "bin" / "gh").exists()
    kind = (task / "kind").read_text().strip() if (task / "kind").exists() else "test"
    hidden = task / "hidden_test.py"
    graded = {
        ("checkout" if i == 0 else f"worktree{i}"): grade_tree(
            t, hidden if hidden.exists() else None, run / "grade" / f"t{i}", fixture
        )
        for i, t in enumerate(trees)
    }
    best = max(graded.values(), key=lambda g: (bool(g["hidden"]), g["checks_pass"]))
    tr = trace(run / "stream.jsonl", run)
    passed, kind_record = task_record(kind, task, tr["final"], best, state, tr)
    report = report_record(task, tr["final"])
    record = {
        "task": task_name,
        "arm": arm,
        "n": int(n),
        "kind": kind,
        "pass": passed,
        "checks_pass": best["checks_pass"],
        "suite_read": bool(tr["suite_reads"]),
        "assisted_by": any(t.lower().startswith("assisted-by") for t in state["trailers"]),
        "state": state,
        "task_record": kind_record,
        "report": report,
        "trees": graded,
        "trace": tr,
    }
    rules = loaded_rules(fixture, record["trace"]["output_style"])
    record["loaded_rules"] = [title for title, _ in rules]
    (run / "reader.md").write_text(
        reader_packet((task / "prompt.txt").read_text(), rules, record["trace"]["final"])
    )
    # All at once: a resume skips any run with a grade.json, so half of one must not exist.
    (run / "grade.json.partial").write_text(json.dumps(record, indent=2) + "\n")
    os.replace(run / "grade.json.partial", run / "grade.json")
    shutil.rmtree(run / "grade", ignore_errors=True)
    print(
        f"graded {task_name} {arm} {n}: passed={record['pass']} checks={record['checks_pass']} "
        f"cost={record['trace']['cost_usd']} lines={report['lines']}"
        + ("" if report["tool_use_named"] is None else f" tool_use_named={report['tool_use_named']}")
        + (" read-eval-suite=yes (not counted)" if record["suite_read"] else "")
    )


if __name__ == "__main__":
    main()
