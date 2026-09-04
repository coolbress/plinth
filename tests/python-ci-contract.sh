#!/usr/bin/env bash
# The consumer contract of python-ci.yml: job names, inputs, secrets. Extracted
# from the workflow and diffed against the committed snapshot, and the
# ruleset's `ci / *` contexts must be exactly the jobs. Changing the snapshot
# is a MAJOR release: every consumer ruleset requires the old names forever.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$root" <<'PY'
import json, pathlib, re, sys

root = pathlib.Path(sys.argv[1])
text = (root / ".github/workflows/python-ci.yml").read_text(encoding="utf-8")
head, body = text.split("\njobs:\n", 1)
jobs = re.findall(r"^  ([a-z][a-z0-9-]*):\s*$", body, re.M)
call = head.split("workflow_call:", 1)[1]
inputs = re.findall(r"^      ([a-z][a-z0-9-]*):\s*$", call.split("\n    secrets:", 1)[0], re.M) if "inputs:" in call else []
secrets = re.findall(r"^      ([a-z][a-z0-9-]*):\s*$", call.split("\n    secrets:", 1)[1], re.M) if "\n    secrets:" in call else []
actual = f"jobs: {' '.join(jobs)}\ninputs: {' '.join(inputs)}\nsecrets: {' '.join(secrets) or '(none)'}\n"
expected = (root / "tests/python-ci-contract.txt").read_text(encoding="utf-8")
fails = 0
if actual == expected:
    print("  PASS  python-ci.yml matches tests/python-ci-contract.txt")
else:
    fails += 1
    print("  FAIL  python-ci.yml contract changed (a MAJOR change if intended):")
    print("        expected: " + expected.replace("\n", "\n                  ").rstrip())
    print("        actual:   " + actual.replace("\n", "\n                  ").rstrip())

ruleset = json.loads((root / "ruleset.json").read_text(encoding="utf-8"))
contexts = [c["context"] for r in ruleset["rules"] if r["type"] == "required_status_checks"
            for c in r["parameters"]["required_status_checks"]]
want = [f"ci / {j}" for j in jobs] + ["CodeQL"]
if sorted(contexts) == sorted(want):
    print(f"  PASS  ruleset.json requires exactly the {len(jobs)} jobs plus CodeQL")
else:
    fails += 1
    print(f"  FAIL  ruleset.json contexts {sorted(contexts)} != jobs {sorted(want)}")
print(f"-- {fails} failed")
sys.exit(1 if fails else 0)
PY
