"""The eval suite's summary table: eval-suite-summary.py <runs dir> <tasks> <arms>.

<tasks> and <arms> are comma-separated, in the order the rows are printed.
Prints Markdown on stdout, with the columns of #647's first-run table, from
every <runs dir>/*/grade.json, then a second table of what each task's kind
records. A run that started and was not graded is counted under the tables,
not in them; so is a run marked `suite_read` (its stream shows a path under
the folder that holds the hidden tests), whose result is not counted.
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
    """A question task has no pass rule: its pass is None."""
    judged = [r for r in rs if r["pass"] is not None]
    return frac(judged, lambda r: r["pass"]) if judged else "–"


def records(rs: list[Run]) -> str:
    """What the runs' kind records besides the main table, in words."""
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
        return f"gaps the final report names: {named}; Skill calls: {used}"
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
    groups: dict[tuple[str, str], list[Run]] = defaultdict(list)
    started = [d for d in sorted(runs.iterdir()) if d.is_dir()] if runs.is_dir() else []
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
        "| Task · arm | Task passed | Checks pass | Pushed to `origin/main` | Pushed a branch "
        "| `Assisted-by` | Turns (median) | Tokens (median) | Cost (median) |"
    )
    print("|" + "---|" * 9)
    for t in tasks:
        for a in arms:
            rs = groups.get((t, a))
            if not rs:
                continue
            print(
                f"| {t} · {a} | {passed(rs)} "
                f"| {frac(rs, lambda r: r['checks_pass'])} "
                f"| {frac(rs, lambda r: r['state']['origin_main_moved'])} "
                f"| {frac(rs, lambda r: r['state']['pushed_branch'])} "
                f"| {frac(rs, lambda r: r['assisted_by'])} "
                f"| {med(rs, lambda r: r['trace']['turns'], '{:g}')} "
                f"| {med(rs, kilo, '{:.0f}k')} "
                f"| {med(rs, lambda r: r['trace']['cost_usd'], '${:.2f}')} |"
            )
    rows = [(t, a, groups[(t, a)]) for t in tasks for a in arms if groups.get((t, a))]
    extra = [(t, a, records(rs)) for t, a, rs in rows if records(rs)]
    if extra:
        print()
        print("| Task · arm | What the task's kind records |")
        print("|---|---|")
        for t, a, line in extra:
            print(f"| {t} · {a} | {line} |")
    counted = [r for rs in groups.values() for r in rs]
    # The same figure the ceiling adds up: a session that reported no cost
    # is counted at the budget it was given.
    cost = sum(float((d / "cost.txt").read_text() or 0) for d in started if (d / "cost.txt").exists())
    charged = sum(1 for d in started if (d / "cost-unknown.txt").exists())
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
