#!/usr/bin/env bash
# Facts the docs state that drifted from the source (#641, #752): the template
# tag README.md and the tutorial name must be scripts/new-project.sh's
# template_ref; a per-archetype count of required checks a doc states must
# be the count floor-check.py's ruleset gives that archetype; and the tools
# README.md's supported box and the tutorial's "Before you start" list (and the
# tutorial's count of them) must be the ones new-project.sh stops without. A doc
# that states no count passes; a wrong one fails with its file and line. The
# checker then runs on copies with one wrong line each, so it cannot pass
# without looking.
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
# 3. The tools the door stops without, as the two install pages list them.
src = (root / "scripts/new-project.sh").read_text(encoding="utf-8")
tools = re.findall(r"^command -v ([a-z0-9]+)\s+>/dev/null \|\| stop ", src, re.M)
if not tools:
    fail("scripts/new-project.sh has no `command -v <tool> >/dev/null || stop` line")
def listed(rel, start, stop):
    text = (docs / rel).read_text(encoding="utf-8")
    i = text.find(start)
    if i < 0:
        fail(f"{rel} has no {start!r}: the tool list moved")
        return None, text, 0
    j = text.find(stop, i)
    span = text[i:j if j >= 0 else len(text)]
    return re.findall(r"`([a-z0-9]+)`", span), span, text.count("\n", 0, i) + 1
numbers = {"three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8}
for rel, start, stop in (("README.md", "tools: `", "\n>\n"),
                         ("docs/tutorials/getting-started.md", "- Tools: ", "\n- ")):
    names, span, line = listed(rel, start, stop)
    if names is None:
        continue
    if sorted(set(names)) != sorted(tools):
        fail(f"{rel}:{line} lists the tools {sorted(set(names))}; scripts/new-project.sh checks {sorted(tools)}")
    else:
        print(f"  PASS  {rel}: lists the {len(tools)} tools new-project.sh checks")
    m = re.search(r"checks\s+all\s+(\w+)", span)
    if m:
        got = numbers.get(m.group(1).lower(), int(m.group(1)) if m.group(1).isdigit() else -1)
        if got != len(tools):
            fail(f"{rel}:{line} says the generator checks all {m.group(1)}; it checks {len(tools)}")
        else:
            print(f"  PASS  {rel}: \"checks all {m.group(1)}\" matches")

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

# A tool list or count edited in place: the failure names the list's line.
expect_fail_at() {
  local what="$1" where="$2" out line
  out="$(check "$tmp/docs")"
  line="$(grep -m1 "FAIL  $where " <<<"$out")"
  if [ -n "$line" ]; then
    echo "  PASS  a copy with $what fails: ${line#*FAIL  }"
  else
    echo "  FAIL  a copy with $what did not fail at $where: the checker does not look"; status=1
  fi
}
tool_line() { grep -n -m1 -- "$1" "$tmp/docs/$2" | cut -d: -f1; }
copy; sed -i.bak 's/`uv`,$/`uv`./; /^> `python3`\.$/d' "$tmp/docs/README.md"
expect_fail_at "a README tool list without python3" "README.md:$(tool_line 'tools: `' README.md)"
copy; sed -i.bak 's/`uv`, `python3`\. The$/`uv`. The/' "$tmp/docs/docs/tutorials/getting-started.md"
expect_fail_at "a tutorial tool list without python3" "docs/tutorials/getting-started.md:$(tool_line '^- Tools: ' docs/tutorials/getting-started.md)"
copy; sed -i.bak 's/checks all five/checks all four/' "$tmp/docs/docs/tutorials/getting-started.md"
expect_fail_at "\"checks all four\" for five tools" "docs/tutorials/getting-started.md:$(tool_line '^- Tools: ' docs/tutorials/getting-started.md)"
exit "$status"
