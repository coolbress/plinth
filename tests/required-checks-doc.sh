#!/usr/bin/env bash
# docs/reference/required-checks.md names the checks the wall requires. Its
# `ruleset.json` table must list exactly that file's contexts, its service
# table exactly the check floor-check.py adds for a service archetype, and the
# page is headings and tables only: a reference page carries no prose (#231).
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$root" <<'PY'
import json, pathlib, re, sys

root = pathlib.Path(sys.argv[1])
page = root / "docs/reference/required-checks.md"
fails = 0
def fail(msg):
    global fails
    fails += 1
    print(f"  FAIL  {msg}")

if not page.is_file():
    fail(f"{page.relative_to(root)} is missing")
    print(f"-- {fails} failed"); sys.exit(1)
lines = page.read_text(encoding="utf-8").splitlines()

sections, current = {}, None
for n, line in enumerate(lines, 1):
    if line.startswith("#"):
        current = line.lstrip("#").strip()
        sections.setdefault(current, [])
    elif line.startswith("|"):
        if current is not None:
            sections[current].append(line)
    elif line.strip():
        fail(f"line {n} is neither a heading nor a table row: {line[:60]!r}")

def names(title):
    rows = sections.get(title)
    if rows is None:
        fail(f"no section headed {title!r}")
        return []
    body = rows[2:]   # after the header and delimiter rows
    out = []
    for r in body:
        cells = [c.strip() for c in r.strip().strip("|").split("|")]
        m = re.fullmatch(r"`([^`]+)`", cells[0])
        if not m:
            fail(f"{title}: first cell is not a check name in code font: {cells[0]!r}")
            continue
        if any(not c for c in cells):
            fail(f"{title}: {m.group(1)} has an empty cell")
        out.append(m.group(1))
    return out

ruleset = json.loads((root / "ruleset.json").read_text(encoding="utf-8"))
contexts = [c["context"] for r in ruleset["rules"] if r["type"] == "required_status_checks"
            for c in r["parameters"]["required_status_checks"]]
listed = names("Required by `ruleset.json`")
if listed == contexts:
    print(f"  PASS  the page lists ruleset.json's {len(contexts)} contexts, in its order")
else:
    fail(f"the page lists {listed}, ruleset.json requires {contexts}")

image = re.search(r'^IMAGE_CHECK = "([^"]+)"$', (root / "scripts/floor-check.py").read_text(encoding="utf-8"), re.M)
listed = names("Required for a service archetype")
if image and listed == [image.group(1)]:
    print(f"  PASS  the service table lists {image.group(1)!r}, the check floor-check.py adds")
else:
    fail(f"the service table lists {listed}, floor-check.py adds {image.group(1) if image else '(unreadable)'!r}")

if not fails:
    print("  PASS  the page is headings and tables only")
print(f"-- {fails} failed")
sys.exit(1 if fails else 0)
PY
