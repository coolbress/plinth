"""The eval suite's summary table: eval-suite-summary.py <runs dir> <tasks> <arms>.

<tasks> and <arms> are comma-separated, in the order the rows are printed.
Prints Markdown on stdout, with the columns of #647's first-run table, from
every <runs dir>/*/grade.json. A run that started and was not graded is
counted under the table, not in it.
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
    for d in started:
        g = d / "grade.json"
        if g.exists():
            r = json.loads(g.read_text())
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
                f"| {t} · {a} | {frac(rs, lambda r: r['pass'])} "
                f"| {frac(rs, lambda r: r['checks_pass'])} "
                f"| {frac(rs, lambda r: r['state']['origin_main_moved'])} "
                f"| {frac(rs, lambda r: r['state']['pushed_branch'])} "
                f"| {frac(rs, lambda r: r['assisted_by'])} "
                f"| {med(rs, lambda r: r['trace']['turns'], '{:g}')} "
                f"| {med(rs, kilo, '{:.0f}k')} "
                f"| {med(rs, lambda r: r['trace']['cost_usd'], '${:.2f}')} |"
            )
    graded = [r for rs in groups.values() for r in rs]
    cost = sum(r["trace"]["cost_usd"] or 0 for r in graded)
    reserved = sum(
        len(r["trace"]["reserved"][k])
        for r in graded
        for k in ("force", "merge", "repo_create", "no_verify", "rm_rf")
    ) + sum(len(r["trace"]["workflow_edits"]) for r in graded)
    unended = sum(1 for r in graded if not r["trace"]["ended"])
    print()
    print(f"Runs graded: {len(graded)} of {len(started)} started.")
    print(
        f"Model cost: ${cost:.2f}, an API list-price estimate each session reports "
        "(under a claude.ai login it draws on the subscription's usage)."
    )
    print(
        "Reserved actions other than a push (force, merge, `gh repo create`, "
        f"`--no-verify`, `rm -rf`, a workflow edit): {reserved}."
    )
    if unended:
        print(f"Sessions that ended without a result (timeout or crash; cost unknown): {unended}.")


if __name__ == "__main__":
    main()
