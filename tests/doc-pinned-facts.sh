#!/usr/bin/env bash
# Two facts the docs state that drifted from the source (#641): the template
# tag README.md and the tutorial name must be scripts/new-project.sh's
# template_ref, and a per-archetype count of required checks a doc states must
# be the count floor-check.py's ruleset gives that archetype. A doc that states
# no count passes; a wrong one fails with its file and line. The checker then
# runs on copies with one wrong line each, so it cannot pass without looking.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

check() {
python3 - "$root" "$1" <<'PY'
import json, pathlib, re, subprocess, sys

root, docs = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
fails = 0
def fail(msg):
    global fails
    fails += 1
    print(f"  FAIL  {msg}")

# 1. The template tag.
ref = re.search(r'^template_ref="([^"]+)"$', (root / "scripts/new-project.sh").read_text(encoding="utf-8"), re.M)
if not ref:
    fail("scripts/new-project.sh has no template_ref line")
    ref = None
else:
    ref = ref.group(1)
tag = re.compile(r"plinth-template(?:@| |/releases/tag/)(v\d+\.\d+\.\d+)")
for rel in ("README.md", "docs/tutorials/getting-started.md"):
    seen, wrong = 0, 0
    for n, line in enumerate((docs / rel).read_text(encoding="utf-8").splitlines(), 1):
        for m in tag.finditer(line):
            seen += 1
            if m.group(1) != ref:
                wrong += 1
                fail(f"{rel}:{n} names plinth-template {m.group(1)}; template_ref is {ref}")
    if not seen:
        fail(f"{rel} names no plinth-template tag")
    elif ref and not wrong:
        print(f"  PASS  {rel}: {seen} plinth-template tag(s), all {ref}")

# 2. The per-archetype counts, from the ruleset as the door applies it.
def count(archetype):
    cmd = [sys.executable, str(root / "scripts/floor-check.py"), "--print-ruleset",
           "--ruleset", str(root / "ruleset.json")] + (["--archetype", archetype] if archetype else [])
    data = json.loads(subprocess.run(cmd, check=True, capture_output=True, text=True).stdout)
    return sum(len(r["parameters"]["required_status_checks"]) for r in data["rules"]
               if r["type"] == "required_status_checks")
service = subprocess.run([sys.executable, str(root / "scripts/floor-check.py"), "--print-conditional-archetypes"],
                         check=True, capture_output=True, text=True).stdout.split()
want = {None: count(None), **{a: count(a) for a in service}}

words = {"eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14}
number = re.compile(r"\b(" + "|".join(words) + r"|\d+)\b", re.I)
pages = [docs / "README.md", docs / "GLOSSARY.md", docs / "CONTRIBUTING.md",
         *sorted((docs / "docs").rglob("*.md")), *sorted((docs / "skills").rglob("*.md"))]
stated = 0
for page in pages:
    if not page.is_file():
        continue
    rel = page.relative_to(docs)
    text = page.read_text(encoding="utf-8")
    start = 0
    for block in re.split(r"\n[ \t]*\n", text):
        first = text.index(block, start) if block else start
        start = first + len(block)
        if not re.search(r"required\s+checks?", block, re.I):
            continue
        for m in number.finditer(block):
            span = re.split(r"[,;:()]|\.(?:\s|$)", block[m.end():], maxsplit=1)[0]
            span = " ".join(span.split())
            raw = m.group(1).lower()
            if raw.isdigit() and not re.match(r"(required )?checks\b", span):
                continue
            if not re.match(r"(required )?checks\b|on GitHub\b|for\b", span):
                continue
            named = re.findall(r"[a-z][a-z-]*", span)
            if "service" in named:
                archetypes = service
            else:
                archetypes = [a for a in service if a in named]
                if not archetypes:
                    if span.startswith("for"):
                        continue        # "nine for ..." that names no archetype is not a count
                    archetypes = [None]
            line = text.count("\n", 0, first + m.start()) + 1
            got = int(raw) if raw.isdigit() else words[raw]
            stated += 1
            for a in archetypes:
                if got != want[a]:
                    fail(f"{rel}:{line} states {got} required checks for "
                         f"{a or 'an archetype without a service'}; floor-check.py's ruleset has {want[a]}")
print(f"  PASS  {stated} stated check count(s) read; expected "
      + ", ".join(f"{a or 'other'} {n}" for a, n in want.items()) if not fails else
      f"-- {fails} failed")
sys.exit(1 if fails else 0)
PY
}

status=0
echo "the docs in this checkout:"
check "$root" || status=1

# The checker on copies with one wrong line each must fail.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
copy() {
  rm -rf "$tmp/docs"; mkdir -p "$tmp/docs"
  cp "$root"/README.md "$root"/GLOSSARY.md "$root"/CONTRIBUTING.md "$tmp/docs/"
  cp -R "$root/docs" "$root/skills" "$tmp/docs/"
}
expect_fail() {
  local what="$1" where out line
  # The planted line is the file's last: the failure must name it.
  where="$2:$(wc -l <"$tmp/docs/$2" | tr -d ' ')"
  out="$(check "$tmp/docs")"
  line="$(grep -m1 "FAIL  $where " <<<"$out")"
  if [ -n "$line" ]; then
    echo "  PASS  a copy with $what fails: ${line#*FAIL  }"
  else
    echo "  FAIL  a copy with $what did not fail at $where: the checker does not look"; status=1
  fi
}
echo "copies with one wrong line:"
copy; printf '\nRendered from coolbress/plinth-template@v0.0.1.\n' >>"$tmp/docs/README.md"
expect_fail "a README template tag other than template_ref" README.md
copy; printf '\n[old](https://github.com/coolbress/plinth-template/releases/tag/v0.0.1)\n' >>"$tmp/docs/docs/tutorials/getting-started.md"
expect_fail "a tutorial template tag other than template_ref" docs/tutorials/getting-started.md
copy; printf '\nWait for the required checks: eight on GitHub.\n' >>"$tmp/docs/docs/how-to/run-a-project.md"
expect_fail "a wrong count for an archetype without a service" docs/how-to/run-a-project.md
copy; printf '\nThe required checks: nine on GitHub (ten for a service).\n' >>"$tmp/docs/GLOSSARY.md"
expect_fail "\"ten for a service\", which the web archetype is not" GLOSSARY.md
copy; printf '\nThe required checks: nine on GitHub (ten for `backend` or `data-ml`, eleven for `web`).\n' >>"$tmp/docs/docs/reference/required-checks.md"
expect_fail "a wrong count for web" docs/reference/required-checks.md
exit "$status"
