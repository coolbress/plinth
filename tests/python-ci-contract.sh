#!/usr/bin/env bash
# The consumer contract of python-ci.yml: job names, inputs, secrets. Extracted
# from the workflow and diffed against the committed snapshot, and the
# ruleset's `ci / *` contexts must be exactly the jobs every archetype runs.
# A snapshot change is a release decision, read this way:
#   MAJOR: a job, input or secret renamed or removed (every consumer ruleset
#          requires the old names forever), or a job that needs a permission
#          the template's caller job does not grant (every updated repository
#          fails at startup, as v2.0.0 did, #586).
#   MINOR: only a new job, or a new input with a default, inside that grant.
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
actual = f"jobs: {' '.join(sorted(jobs))}\ninputs: {' '.join(sorted(inputs))}\nsecrets: {' '.join(sorted(secrets)) or '(none)'}\n"
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
# The two web-only jobs are required for the web archetype alone, added by
# floor-check.py's ruleset_for the way `image` is for a service (#614).
WEB_ONLY = {"migrations", "deploy-check"}
want = [f"ci / {j}" for j in jobs if j not in WEB_ONLY]
if sorted(contexts) == sorted(want):
    print(f"  PASS  ruleset.json requires exactly the {len(want)} jobs every archetype runs, by name (CodeQL is a rule)")
else:
    fails += 1
    print(f"  FAIL  ruleset.json contexts {sorted(contexts)} != jobs {sorted(want)}")
import subprocess
web = json.loads(subprocess.run([sys.executable, str(root / "scripts/floor-check.py"), "--print-ruleset",
                                 "--ruleset", str(root / "ruleset.json"), "--archetype", "web"],
                                capture_output=True, text=True, check=True).stdout)
web_contexts = [c["context"] for r in web["rules"] if r["type"] == "required_status_checks"
                for c in r["parameters"]["required_status_checks"]]
# And `image`: the web archetype is a service, whose ci.yml carries that job
# from plinth-template v1.20.0 on (#615).
if sorted(set(web_contexts) - set(contexts)) == sorted([f"ci / {j}" for j in WEB_ONLY] + ["image"]):
    print("  PASS  the web archetype's ruleset adds exactly ci / migrations, ci / deploy-check and image")
else:
    fails += 1
    print(f"  FAIL  the web archetype's ruleset adds {sorted(set(web_contexts) - set(contexts))}")
print(f"-- {fails} failed")
sys.exit(1 if fails else 0)
PY
