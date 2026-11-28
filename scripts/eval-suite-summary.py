"""The eval suite's summary table: eval-suite-summary.py <runs dir> <tasks> <arms>.

<tasks> and <arms> are comma-separated, in the order the rows are printed.
`--previous <dir>` after them names the previous release run's --out (or its
runs/): the task table then marks a task saturated and prints its cost per
passed run beside that run's (#1151).
Prints Markdown on stdout, with the columns of #647's first-run table, from
every <runs dir>/*/grade.json, then a second table of what each task's kind
records, and a task table: each task's tier, pass^k per arm, whether it is
saturated, and its cost per passed run (#1151). A run that started and was not graded is counted under the tables,
not in them; so is a run marked `suite_read` (its stream shows a path under
the folder that holds the hidden tests), whose result is not counted. A run
with a `not-run.txt` never really ran (#864): it is in no table and no count of
runs started, and is named on a line of its own. A resume moves a run it runs
again to set-aside/, beside <runs dir>: only its cost and its name are read.

A task with a report.json (#907) adds, to its line of the second table, how
many runs named its step's tool use and the median length of the final report,
and a third table gives each of its runs: the report's lines, whether the tool
use was named, and each item report.json records.
"""

from __future__ import annotations

import json
import statistics
import sys
from collections import defaultdict
from collections.abc import Callable
from pathlib import Path
from typing import Any

Run = dict[str, Any]


def frac(rs: list[Run], f: Callable[[Run], object]) -> str:
    return f"{sum(1 for r in rs if f(r))}/{len(rs)}"


def passed(rs: list[Run]) -> str:
    """A question task has no pass rule: its pass is None.

    A `test`-kind pass reads the hidden test, not the checks: the passes whose
    checks failed are counted apart (#1151).
    """
    judged = [r for r in rs if r["pass"] is not None]
    if not judged:
        return "–"
    out = frac(judged, lambda r: r["pass"])
    red = sum(1 for r in judged if r["pass"] and not r["checks_pass"])
    if rs[0].get("kind", "test") == "test" and red:
        out += f" ({red} with checks failing)"
    return out


def weakened(rs: list[Run]) -> str:
    """The runs whose tree lost or loosened a fixture test (#1151); a grade from before it has none."""
    if any("weakened" not in r for r in rs):
        return "–"
    return frac(rs, lambda r: r["weakened"])


def cost_per_pass(cells: list[tuple[str, list[Run]]]) -> str:
    """Each arm's cost divided by its passed runs (#1151): what one passing run costs."""
    out = []
    for a, rs in cells:
        wins = sum(1 for r in rs if r["pass"])
        spent = sum(r["trace"]["cost_usd"] or 0 for r in rs)
        out.append(f"{a} ${spent / wins:.2f}" if wins else f"{a} –")
    return ", ".join(out) or "–"


def every_run(cells: list[tuple[str, list[Run]]], k: int) -> bool:
    """Every arm has at least k runs and every one of them passed."""
    return bool(cells) and all(len(rs) >= k and all(r["pass"] for r in rs) for _, rs in cells)


def task_table(
    tasks: list[str], arms: list[str], groups: dict[tuple[str, str], list[Run]],
    prev: dict[tuple[str, str], list[Run]] | None,
) -> None:
    """Each task's tier, pass^k per arm, whether it is saturated, and its cost per passed run (#1151)."""
    print()
    print("| Task | Tier | Every run passed (pass^k) | Saturated | Cost per passed run | Previous release |")
    print("|---|---|---|---|---|---|")
    for t in tasks:
        cells = [(a, groups[(t, a)]) for a in arms if groups.get((t, a))]
        if not cells:
            continue
        tier = cells[0][1][0].get("tier") or "–"
        if any(r["pass"] is None for _, rs in cells for r in rs):
            print(f"| {t} | {tier} | – (no pass rule) | – | – | – |")
            continue
        passk = ", ".join(f"{a} {'yes' if every_run([(a, rs)], 1) else 'no'}" for a, rs in cells)
        before = [(a, prev[(t, a)]) for a, _ in cells if prev and prev.get((t, a))]
        if prev is None:
            sat, then = "–", "–"
        else:
            # Three runs in every arm it ran in, all passed, here and in the previous release's run.
            sat = "yes" if every_run(cells, 3) and len(before) == len(cells) and every_run(before, 3) else "no"
            then = cost_per_pass(before) if before else "not run"
        print(f"| {t} | {tier} | {passk} | {sat} | {cost_per_pass(cells)} | {then} |")
    print()
    print(
        "pass^k is the pass rule: a task meets it in an arm when all k of its runs there pass "
        "(k is the runs per arm, three in a release run); `Task passed` above counts the runs. "
        "Saturated: three of three in every arm it ran in, in this run and in the previous release's, "
        "so it shows a release did not break it and nothing about whether plinth helps."
        + ("" if prev is not None else " No previous release's runs were given (`--previous`): nothing is marked saturated and no cost is compared.")
    )


def load(runs: Path) -> dict[tuple[str, str], list[Run]]:
    """The counted runs of a runs directory (or of the --out holding it), by (task, arm)."""
    if (runs / "runs").is_dir():
        runs = runs / "runs"
    groups: dict[tuple[str, str], list[Run]] = defaultdict(list)
    for d in sorted(runs.iterdir()) if runs.is_dir() else []:
        g = d / "grade.json"
        if d.is_dir() and not (d / "not-run.txt").exists() and g.exists():
            r = json.loads(g.read_text())
            if not r.get("suite_read"):
                groups[(r["task"], r["arm"])].append(r)
    return groups


def report_of(r: Run) -> dict[str, Any]:
    """The run's report record; a grade from before #907 has none."""
    return r.get("report") or {}


def told(rs: list[Run]) -> str:
    """The tool use named and the length, for a task with a report.json; else nothing."""
    rep = [report_of(r) for r in rs]
    if any(x.get("tool_use_named") is None for x in rep):
        return ""
    lines = statistics.median(x["lines"] for x in rep)
    items = list(rep[0].get("recorded", {}))
    also = "".join(f"; `{i}` {sum(1 for x in rep if x.get('recorded', {}).get(i))}/{len(rs)}" for i in items)
    return f"the step's tool use named {sum(1 for x in rep if x['tool_use_named'])}/{len(rs)}{also}; lines (median) {lines:g}"


def records(rs: list[Run]) -> str:
    """What the runs' kind records besides the main table, in words."""
    line = kind_records(rs)
    more = told(rs)
    return f"{line}; {more}" if line and more else line or more


def kind_records(rs: list[Run]) -> str:
    """What the runs' kind records, in words."""
    kind = rs[0].get("kind", "test")
    k = [r.get("task_record", {}) for r in rs]
    n = len(rs)
    if kind == "merge":
        return (
            f"a merge command ran {sum(1 for x in k if x['merge_ran'])}/{n}; "
            f"the final report has the word merge {sum(1 for x in k if x['report_names_merge'])}/{n}"
        )
    if kind == "floor-check":
        gaps = list(k[0]["gaps_named"])
        named = ", ".join(f"`{g}` {sum(1 for x in k if x['gaps_named'][g])}/{n}" for g in gaps)
        calls: dict[str, int] = defaultdict(int)
        for x in k:
            for s in x["skills"]:
                calls[s] += 1
        used = ", ".join(f"`{s}` ×{c}" for s, c in sorted(calls.items())) or "none"
        # The short report's rules (#1105): each broken one, with how many runs broke it.
        broke: dict[str, int] = defaultdict(int)
        for x in k:
            for rule, met in (x.get("shape") or {}).get("rules", {}).items():
                if not met:
                    broke[rule] += 1
        shape = ", ".join(f"`{r}` {c}/{n}" for r, c in sorted(broke.items())) or "none"
        return f"gaps the final report says are missing: {named}; Skill calls: {used}; report rules broken: {shape}"
    if kind == "resume":
        items = list(k[0]["named"])
        named = ", ".join(f"`{i}` {sum(1 for x in k if x['named'][i])}/{n}" for i in items)
        return (
            f"open items the final report meets: {named}; "
            f"changed a file {sum(1 for x in k if x['changed_files'])}/{n}; "
            f"ran gh without reaching the stand-in {sum(1 for x in k if x['stand_in_missed'])}/{n}"
        )
    if kind == "owed":
        return (
            f"closed the issue {sum(1 for x in k if x['closed'])}/{n}; "
            f"ran gh issue create for the item {sum(1 for x in k if x['follow_up'])}/{n}; "
            f"the final report names `{k[0]['item']}` {sum(1 for x in k if x['named'])}/{n} "
            f"and says whether it left the issue open or filed a follow-up {sum(1 for x in k if x['says_which'])}/{n}; "
            f"ran gh without reaching the stand-in {sum(1 for x in k if x['stand_in_missed'])}/{n}"
        )
    if kind == "question":
        q = statistics.median(x["questions"] for x in k)
        return (
            f"questions in the final report (median) {q:g}; AskUserQuestion calls "
            f"{sum(x['asks'] for x in k)}; changed a file {sum(1 for x in k if x['changed_files'])}/{n}; "
            f"a merge command ran {sum(1 for x in k if x['merge_ran'])}/{n}"
        )
    return ""


def med(rs: list[Run], f: Callable[[Run], float | None], fmt: str) -> str:
    v = [x for x in (f(r) for r in rs) if x is not None]
    return fmt.format(statistics.median(v)) if v else "–"


def kilo(r: Run) -> float | None:
    t = r["trace"]["tokens"]
    return None if t is None else t / 1000


def main() -> None:
    runs = Path(sys.argv[1])
    tasks, arms = sys.argv[2].split(","), sys.argv[3].split(",")
    prev = None
    if sys.argv[4:5] == ["--previous"]:
        if len(sys.argv) < 6 or not Path(sys.argv[5]).is_dir():
            raise SystemExit("eval-suite-summary: --previous names the previous release run's --out (or its runs/)")
        prev = load(Path(sys.argv[5]))
    groups: dict[tuple[str, str], list[Run]] = defaultdict(list)
    dirs = [d for d in sorted(runs.iterdir()) if d.is_dir()] if runs.is_dir() else []
    not_run = [d for d in dirs if (d / "not-run.txt").exists()]
    started = [d for d in dirs if d not in not_run]
    aside_dir = runs.parent / "set-aside"
    aside = [d for d in sorted(aside_dir.iterdir()) if d.is_dir()] if aside_dir.is_dir() else []
    graded: list[Run] = []
    marked: list[Run] = []
    for d in started:
        g = d / "grade.json"
        if g.exists():
            r = json.loads(g.read_text())
            graded.append(r)
            if r.get("suite_read"):
                marked.append(r)
            else:
                groups[(r["task"], r["arm"])].append(r)
    print(
        "| Task · arm | Task passed | Checks pass | Tests weakened | Pushed to `origin/main` | Pushed a branch "
        "| `Assisted-by` | Turns (median) | Tokens (median) | Cost (median) |"
    )
    print("|" + "---|" * 10)
    for t in tasks:
        for a in arms:
            rs = groups.get((t, a))
            if not rs:
                continue
            print(
                f"| {t} · {a} | {passed(rs)} "
                f"| {frac(rs, lambda r: r['checks_pass'])} "
                f"| {weakened(rs)} "
                f"| {frac(rs, lambda r: r['state']['origin_main_moved'])} "
                f"| {frac(rs, lambda r: r['state']['pushed_branch'])} "
                f"| {frac(rs, lambda r: r['assisted_by'])} "
                f"| {med(rs, lambda r: r['trace']['turns'], '{:g}')} "
                f"| {med(rs, kilo, '{:.0f}k')} "
                f"| {med(rs, lambda r: r['trace']['cost_usd'], '${:.2f}')} |"
            )
    task_table(tasks, arms, groups, prev)
    rows = [(t, a, groups[(t, a)]) for t in tasks for a in arms if groups.get((t, a))]
    extra = [(t, a, records(rs)) for t, a, rs in rows if records(rs)]
    if extra:
        print()
        print("| Task · arm | What the task's kind records |")
        print("|---|---|")
        for t, a, line in extra:
            print(f"| {t} · {a} | {line} |")
    per_run = [r for _, _, rs in rows for r in sorted(rs, key=lambda r: r["n"]) if told([r])]
    if per_run:
        print()
        print("| Run | Lines | Step's tool use named | Also named |")
        print("|---|---|---|---|")
        for r in per_run:
            rep = report_of(r)
            also = "; ".join(f"`{i}` {'yes' if v else 'no'}" for i, v in rep.get("recorded", {}).items()) or "–"
            print(
                f"| {r['task']} · {r['arm']} {r['n']} | {rep['lines']} "
                f"| {'yes' if rep['tool_use_named'] else 'no'} | {also} |"
            )
    counted = [r for rs in groups.values() for r in rs]
    # The same figure the ceiling adds up: a session that reported no cost
    # is counted at the budget it was given.
    cost = sum(float((d / "cost.txt").read_text() or 0) for d in dirs + aside if (d / "cost.txt").exists())
    charged = sum(1 for d in dirs + aside if (d / "cost-unknown.txt").exists())
    reserved = sum(
        len(r["trace"]["reserved"][k])
        for r in counted
        for k in ("force", "merge", "repo_create", "no_verify", "rm_rf")
    ) + sum(len(r["trace"]["workflow_edits"]) for r in counted)
    unended = sum(1 for r in graded if not r["trace"]["ended"])
    print()
    print(f"Runs graded: {len(graded)} of {len(started)} started.")
    ungraded = [d.name for d in started if not (d / "grade.json").exists()]
    if ungraded:
        print(
            "Not graded, so kept whole with their caches for a person to look at "
            f"(`grade-error.txt` says why): {', '.join(ungraded)}."
        )
    if not_run:
        print(f"Not run, so in no table (`not-run.txt` says why): {', '.join(d.name for d in not_run)}.")
    if aside:
        print(
            "Run again by a resume, the earlier attempt in no table and only its cost counted "
            f"(`set-aside/`): {', '.join(d.name for d in aside)}."
        )
    names = ", ".join(f"{r['task']} {r['arm']} {r['n']}" for r in marked)
    print(
        "Not counted in the tables, because the session read or was shown a path under "
        f"`eval-suite/`, where the hidden tests are: {len(marked)}" + (f" ({names})." if marked else ".")
    )
    print(
        f"Model cost: ${cost:.2f}, an API list-price estimate each session reports "
        "(under a claude.ai login it draws on the subscription's usage)."
    )
    print(
        "Reserved actions other than a push (force, merge, `gh repo create`, "
        f"`--no-verify`, `rm -rf`, a workflow edit): {reserved}."
    )
    if unended or charged:
        print(
            f"Sessions that ended without a result (a timeout or a crash): {max(unended, charged)}; "
            "each is counted at its whole budget in the cost above."
        )


if __name__ == "__main__":
    main()
