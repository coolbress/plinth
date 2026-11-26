#!/usr/bin/env bash
# What scripts/floor-check.py's REGISTRY declares about each check (#1103),
# read without running a fixture (tests/floor-check-golden.sh runs them):
#   - each area letter has one name, and every id's letter and area is one of them;
#   - every id ever recorded in tests/fixtures/floor-check-golden/ids.txt is still
#     registered, as an id or as an alias (an id whose letter changed is a
#     new id: the old one stays, as an alias of it), and every registered id is
#     recorded there (`--write` adds the new ones); the record the latest
#     release shipped is read too (the network), as the same pull request can edit this one;
#   - every entry that .plinth-adoption.yml may not keep is listed with why (#1112);
#   - every `baseline` id is in the OSPS Baseline release OSPS_BASELINE names
#     (tests/fixtures/osps-baseline/<release>.txt);
#   - every entry whose view is not `report` is listed with why, and with
#     whether `ci / floor-check` prints it.
#
#   tests/floor-check-registry.sh           check
#   tests/floor-check-registry.sh --write   add the registered ids ids.txt lacks
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
py="$(command -v python3)" || { echo "  FAIL  no python3"; exit 1; }
"$py" -c 'import sys; sys.exit(sys.version_info < (3, 11))' \
  || { echo "  FAIL  needs python3 3.11 or later, as the runner has; got $("$py" --version 2>&1)"; exit 1; }

"$py" - "$root" "${1:-}" <<'PY'
import importlib.util, re, sys
from pathlib import Path
root, mode = Path(sys.argv[1]), sys.argv[2]
spec = importlib.util.spec_from_file_location("floor_check", root / "scripts/floor-check.py")
fc = importlib.util.module_from_spec(spec); spec.loader.exec_module(fc)
reg = fc.REGISTRY
passed = failed = 0
def ok(msg):
    global passed; passed += 1; print(f"  PASS  {msg}")
def bad(msg, detail=()):
    global failed; failed += 1; print(f"  FAIL  {msg}")
    for d in detail:
        print(f"        {d}")
def listed(head, rows):
    print(f"  {head}")
    for r in rows or ["(none)"]:
        print(f"        {r}")

# One name per letter, the ticket's table; and nothing registered outside it.
want = {"A": "files", "B": "agent", "C": "project", "D": "ci", "E": "wall", "F": "plinth", "G": "machine",
        "R": "records"}
if fc.AREAS == want:
    ok("each area letter has one name: " + ", ".join(f"{k} {v}" for k, v in fc.AREAS.items()))
else:
    bad("AREAS is not the one table of letters and names", [f"has  {fc.AREAS}", f"want {want}"])
nameless = [f"{i}: letter {i[3]}, area {e['area']}" for i, e in reg.items()
            if i[3] not in fc.AREAS or e["area"] not in fc.AREAS]
if not nameless:
    ok(f"every one of {len(reg)} ids has a letter and an area with a name")
else:
    bad("ids whose letter or area has no name", nameless)

# Ids are never renamed: the record of every id registered so far.
record = root / "tests/fixtures/floor-check-golden/ids.txt"
recorded = [ln.split()[0] for ln in record.read_text(encoding="utf-8").splitlines()
            if ln.strip() and not ln.startswith("#")] if record.is_file() else []
aliases = {a for e in reg.values() for a in e["aliases"]}
gone = [i for i in recorded if i not in reg and i not in aliases]
new = [i for i in reg if i not in recorded]
if mode == "--write" and new:
    with record.open("a", encoding="utf-8") as f:
        f.write("".join(f"{i} {reg[i]['name']}\n" for i in new))
    print(f"  wrote {len(new)} new ids to {record.relative_to(root)}")
    new = []
if not gone:
    ok(f"every one of {len(recorded)} recorded ids is still registered, as an id or an alias")
else:
    bad("recorded ids no longer registered: an id that changed letter or number keeps the old one as an alias", gone)

# The same pull request can edit ids.txt, so the record is also read as the
# latest release shipped it: an id a release carried stays, here and in
# REGISTRY. A release before the record existed has none (404); a failed
# read is a FAIL, not a pass.
import subprocess, urllib.error, urllib.request
tags = subprocess.run(["git", "-C", str(root), "ls-remote", "--tags", "--refs",
                       "https://github.com/coolbress/plinth.git", "v*"],
                      capture_output=True, text=True, timeout=60, check=False)
versions = sorted((tuple(map(int, m.groups())), m.group(0)) for line in tags.stdout.splitlines()
                  if (m := re.search(r"v(\d+)\.(\d+)\.(\d+)$", line)))
if tags.returncode != 0 or not versions:
    bad("the release tags could not be listed, so the released id record was not read",
        [tags.stderr.strip() or "(no v* tag)"])
else:
    tag = versions[-1][1]
    url = f"https://raw.githubusercontent.com/coolbress/plinth/{tag}/tests/fixtures/floor-check-golden/ids.txt"
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            shipped = [ln.split()[0] for ln in r.read().decode().splitlines() if ln.strip() and not ln.startswith("#")]
    except urllib.error.HTTPError as e:
        shipped = None if e.code == 404 else e
    except OSError as e:
        shipped = e
    if isinstance(shipped, Exception):
        bad(f"{tag}'s id record could not be read", [str(shipped)])
    elif shipped is None:
        print(f"  INFO  {tag} carries no id record yet; the next release's is held from then on")
    else:
        lost = [i for i in shipped if i not in recorded or (i not in reg and i not in aliases)]
        if not lost:
            ok(f"every one of {len(shipped)} ids {tag} shipped is still recorded and registered")
        else:
            bad(f"ids {tag} shipped that left ids.txt or REGISTRY (keep the old id as an alias)", lost)
if not new:
    ok("every registered id is in the record")
else:
    bad("registered ids not in tests/fixtures/floor-check-golden/ids.txt (rerun with --write)", new)

# Keepable: listed, with why, for whoever reads .plinth-adoption.yml's rules.
unkept = [i for i, e in reg.items() if not e["keepable"]]
no_why = [i for i in unkept if not (reg[i]["not_keepable"] or "").strip()]
if not no_why:
    ok(f"every entry declares keepable; {len(unkept)} may not be kept, each with why")
else:
    bad("entries not keepable with no reason", no_why)
listed("not keepable in .plinth-adoption.yml:", [f"{i} {reg[i]['name']}: {reg[i]['not_keepable']}" for i in unkept])

# Baseline: one release, every id in its list.
osps = root / "tests/fixtures/osps-baseline" / f"{fc.OSPS_BASELINE}.txt"
if not osps.is_file():
    bad(f"no control list for OSPS_BASELINE {fc.OSPS_BASELINE} at {osps.relative_to(root)}")
else:
    controls = {ln.strip() for ln in osps.read_text(encoding="utf-8").splitlines()
                if re.fullmatch(r"OSPS-[A-Z]{2}-\d\d\.\d\d", ln.strip())}
    unknown = [f"{i}: {c}" for i, e in reg.items() for c in e["baseline"] if c not in controls]
    mapped = sum(bool(e["baseline"]) for e in reg.values())
    if controls and not unknown:
        ok(f"every baseline id is one of OSPS Baseline {fc.OSPS_BASELINE}'s {len(controls)} controls "
           f"({mapped} entries carry one)")
    else:
        bad(f"baseline ids not in OSPS Baseline {fc.OSPS_BASELINE}", unknown or ["(the control list is empty)"])

# Views: what is not in the report, and why.
off = [i for i, e in reg.items() if e["view"] != "report"]
no_why = [i for i in off if not (reg[i]["view_why"] or "").strip()]
if not no_why:
    ok(f"every entry declares a view; {len(off)} not in the report, each with why")
else:
    bad("entries outside the report with no reason", no_why)
listed("not in the report:", [f"{i} {reg[i]['view']}, {'printed' if reg[i]['ci_visible'] else 'not printed'} "
                              f"by ci / floor-check: {reg[i]['view_why']}" for i in off])
hidden = [i for i, e in reg.items() if not e["ci_visible"]]
listed("not printed by ci / floor-check:", [f"{i} {reg[i]['name']}" for i in hidden])

print(f"-- {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
PY
