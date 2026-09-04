#!/usr/bin/env bash
# Inputs of the reusable workflow are actually passed by someone.
#
# Why: an input that only enables a step behind `if: inputs.x != ''` runs
# nowhere if nobody passes it, and CI stays green. Declared is not the same as
# exercised (the same disease as all-tests-are-wired). Only `if:`-gated inputs
# are enforced; inputs whose code path runs on the default are listed as INFO.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$root" <<'PY'
import re, sys, pathlib

root = pathlib.Path(sys.argv[1])
files = sorted((root / ".github" / "workflows").glob("*.yml"))


def declared(text: str) -> list[str]:
    if "workflow_call" not in text:
        return []
    block = text.split("workflow_call", 1)[1].split("\njobs:", 1)[0]
    return re.findall(r"^      ([a-z][a-z0-9-]*):\s*$", block, re.M)


def gated(text: str, name: str) -> bool:
    return any(f"inputs.{name}" in line for line in text.splitlines() if re.match(r"^\s*if:", line))


def passed_keys(text: str) -> set[str]:
    """Keys inside `with:` blocks only; counting the declaration always passes."""
    out: set[str] = set()
    indent = None
    for line in text.splitlines():
        if indent is not None:
            m = re.match(r"^(\s+)([a-z][a-z0-9-]*):", line)
            if m and len(m.group(1)) > indent:
                out.add(m.group(2))
                continue
            if line.strip() and not line.strip().startswith("#"):
                indent = None
        m = re.match(r"^(\s*)with:\s*$", line)
        if m:
            indent = len(m.group(1))
    return out


passed: set[str] = set()
for f in files:
    passed |= passed_keys(f.read_text(encoding="utf-8"))

blocking, info = [], []
for f in files:
    text = f.read_text(encoding="utf-8")
    for name in declared(text):
        if name in passed:
            continue
        (blocking if gated(text, name) else info).append(f"{f.name}: {name}")

for item in info:
    print(f"  INFO  nobody passes it (the path runs on its default): {item}")
if blocking:
    print("  FAIL  `if:`-gated inputs nobody passes; that path runs nowhere:")
    for item in blocking:
        print(f"        {item}")
    sys.exit(1)
print("  PASS  every `if:`-gated input is passed by some caller")
PY
