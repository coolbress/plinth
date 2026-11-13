#!/usr/bin/env bash
# Facts the docs state that drifted from the source (#641, #752): the template
# tag README.md and the tutorial name must be scripts/new-project.sh's
# template_ref; a per-archetype count of required checks a doc states must
# be the count floor-check.py's ruleset gives that archetype; and the tools
# README.md's supported box and the tutorial's "Before you start" list (and the
# tutorial's count of them) must be the ones new-project.sh stops without; the
# skill counts the arsenal and the marketplace state must be the manifest's
# lists; the squash-merge command must read the same in the three pages that
# show it (#835); step 5 of run-a-project.md must list the three questions,
# and a line elsewhere that names them must say all three (#921). A doc that states no count passes; a wrong one fails with its file and line. The
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

# 4. The git floor the door stops below, which the install needs too (#771).
gf = re.search(r'^git_floor="([^"]+)"$', src, re.M)
if not gf:
    fail("scripts/new-project.sh has no git_floor line")
else:
    gitv = re.compile(r"\bgit`?\s+\(?(\d+\.\d+(?:\.\d+)?)\s+or\s+newer")
    for rel in ("README.md", "docs/tutorials/getting-started.md"):
        text = (docs / rel).read_text(encoding="utf-8")
        found = [(text.count("\n", 0, m.start()) + 1, m.group(1)) for m in gitv.finditer(text)]
        if not found:
            fail(f"{rel} states no git floor (\"git {gf.group(1)} or newer\")")
        for n, v in found:
            if v != gf.group(1):
                fail(f"{rel}:{n} states git {v} or newer; the door's git_floor is {gf.group(1)}")
        if found and all(v == gf.group(1) for _, v in found):
            print(f"  PASS  {rel}: git {gf.group(1)} or newer, as the door checks")

# 5. The skill counts (#835): the manifest's lists are the fact, and upstream's
# total is those two plus the skills the arsenal names as in neither.
market = json.loads((docs / ".claude-plugin/marketplace.json").read_text(encoding="utf-8"))
entries = {p["name"]: p for p in market["plugins"]}
n_matt, n_extra = len(entries["mattpocock-skills"]["skills"]), len(entries["mattpocock-skills-extra"]["skills"])
arsenal_rel = "skills/arsenal/SKILL.md"
arsenal = (docs / arsenal_rel).read_text(encoding="utf-8")
notice = (docs / "NOTICE").read_text(encoding="utf-8")
counted = {**words, **numbers, "fifteen": 15}
def num(raw):
    return int(raw) if raw.isdigit() else counted.get(raw.lower(), -1)
neither = re.search(r"The (\w+) in neither are ([^(]+)\(", arsenal)
if not neither:
    fail(f"{arsenal_rel} has no \"The <n> in neither are ...\": the skills upstream ships cannot be counted")
    n_neither = -1
else:
    n_neither = len(re.findall(r"`[^`]+`", neither.group(2)))
    if num(neither.group(1)) != n_neither:
        fail(f"{arsenal_rel}:{arsenal.count(chr(10), 0, neither.start()) + 1} says {neither.group(1)} in neither and names {n_neither}")
total = n_matt + n_extra + n_neither
facts = [
    (arsenal_rel, arsenal, r"`mattpocock-skills` installs (\w+) of the", n_matt, "installed"),
    (arsenal_rel, arsenal, r"`mattpocock-skills` installs \w+ of the (\w+) skills", total, "shipped upstream"),
    (arsenal_rel, arsenal, r"`mattpocock-skills-extra` lists (\w+) more", n_extra, "listed"),
    (arsenal_rel, arsenal, r"\| `mattpocock-skills` \| (\w+) skills:", n_matt, "installed"),
    (arsenal_rel, arsenal, r"\| `mattpocock-skills-extra` \| The (\w+) other", n_extra, "listed"),
    (arsenal_rel, arsenal, r"adds its\s+(\w+)\s+beside the default set's", n_extra, "listed"),
    (arsenal_rel, arsenal, r"beside the default set's\s+(\w+)", n_matt, "installed"),
    ("NOTICE", notice, r"(\w+) skills installed,", n_matt, "installed"),
    ("NOTICE", notice, r"skills installed, (\w+) listed in mattpocock-skills-extra", n_extra, "listed"),
    (".claude-plugin/marketplace.json", entries["mattpocock-skills"]["description"], r"skills, (\w+) of the", n_matt, "installed"),
    (".claude-plugin/marketplace.json", entries["mattpocock-skills"]["description"], r"of the (\w+) upstream ships", total, "shipped upstream"),
    (".claude-plugin/marketplace.json", entries["mattpocock-skills-extra"]["description"], r"The (\w+) Matt Pocock skills", n_extra, "listed"),
]
for rel, text, pattern, want_n, what in facts:
    found = list(re.finditer(pattern, text))
    if not found:
        fail(f"{rel} no longer says {pattern!r}: update this check")
    for m in found:
        if num(m.group(1)) != want_n:
            fail(f"{rel}:{text.count(chr(10), 0, m.start()) + 1} states {m.group(1)} skills {what}; the lists give {want_n}")
if not fails:
    print(f"  PASS  skill counts: {n_matt} installed, {n_extra} listed, {n_neither} in neither, {total} upstream")

# 6. The squash-merge command (#835), read with line breaks as one space.
# tests/template-rules-drift.sh holds plinth's CONTRIBUTING.md to the template's.
squash = 'body="$(gh pr view <n> --json body --jq .body)" && gh pr merge <n> --squash --match-head-commit <sha> --body "$body"'
for rel in ("CONTRIBUTING.md", "docs/tutorials/getting-started.md", "docs/how-to/run-a-project.md"):
    text = (docs / rel).read_text(encoding="utf-8")
    if squash in " ".join(text.split()):
        print(f"  PASS  {rel}: the squash-merge command")
    else:
        i = text.find("gh pr merge <n>")
        fail(f"{rel}:{text.count(chr(10), 0, i) + 1 if i >= 0 else 1} does not show the squash-merge command as: {squash}")

# 7. The one-time update commands (#835): the README holds them, and
# tests/install-smoke.sh reads them there; these pages link to it.
for rel in ("docs/tutorials/getting-started.md", "docs/how-to/cut-a-release.md"):
    text = (docs / rel).read_text(encoding="utf-8")
    if "README.md#install-in-detail" in text and "taste-skill@plinth" not in text:
        print(f"  PASS  {rel}: links the one-time update commands, repeats none")
    else:
        i = text.find("taste-skill@plinth")
        fail(f"{rel}:{text.count(chr(10), 0, i) + 1 if i >= 0 else 1} must link README.md#install-in-detail and not repeat the one-time commands")

# 8. The three questions (#921): step 5 of run-a-project.md lists them under
# that name, and every other line that names them says all three.
# CHANGELOG.md is history and keeps the wording each release had.
rap_rel = "docs/how-to/run-a-project.md"
rap = (docs / rap_rel).read_text(encoding="utf-8")
s5 = re.search(r"^### 5\..*?(?=^### 6\.)", rap, re.M | re.S)
listed = []
if s5:
    lst = re.search(r"the three questions:\n\n((?:[ \t]*\d+\. .*\n)+)", s5.group(0))
    if lst:
        listed = [m.group(1) or m.group(2) for m in re.finditer(r'\d+\. (?:"([^"]+)"|(.*))', lst.group(1))]
s5_lines = range(rap.count("\n", 0, s5.start()) + 1, rap.count("\n", 0, s5.end()) + 1) if s5 else range(0)
if len(listed) != 3:
    fail(f"{rap_rel}:{rap.count(chr(10), 0, s5.start()) + 1 if s5 else 1} step 5 lists {len(listed)} questions under \"the three questions:\", not three")
named, before = 0, fails
for path in sorted([*(p for p in docs.glob("*.md") if p.name != "CHANGELOG.md"), *(docs / "docs").rglob("*.md"), *(docs / "skills").rglob("*.md")]):
    rel = path.relative_to(docs).as_posix()
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if "three questions" not in line.lower() or (rel == rap_rel and n in s5_lines):
            continue
        named += 1
        if len(listed) != 3:
            fail(f"{rel}:{n} names the three questions; step 5 does not list three to say")
            continue
        missing = [q for q in listed if q not in line]
        if missing:
            fail(f"{rel}:{n} names the three questions and does not say " + "; ".join(f'"{q}"' for q in missing))
if fails == before:
    print(f"  PASS  the three questions: listed in step 5, said on all {named} line(s) that name them")

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
  cp "$root"/README.md "$root"/GLOSSARY.md "$root"/CONTRIBUTING.md "$root"/NOTICE "$tmp/docs/"
  cp -R "$root/docs" "$root/skills" "$root/.claude-plugin" "$tmp/docs/"
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
copy; printf '\nNeeds git 2.28 or newer.\n' >>"$tmp/docs/docs/tutorials/getting-started.md"
expect_fail "a git floor other than the door's" docs/tutorials/getting-started.md
copy; sed -i.bak 's/installs 15 of the 27 skills/installs 14 of the 27 skills/' "$tmp/docs/skills/arsenal/SKILL.md"
expect_fail_at "an arsenal count other than the manifest's" "skills/arsenal/SKILL.md:$(tool_line 'installs 14 of the' skills/arsenal/SKILL.md)"
copy; sed -i.bak 's/installs 15 of the 27 skills/installs 15 of the 25 skills/' "$tmp/docs/skills/arsenal/SKILL.md"
expect_fail_at "an upstream total other than the lists add to" "skills/arsenal/SKILL.md:$(tool_line 'installs 15 of the' skills/arsenal/SKILL.md)"
copy; sed -i.bak 's/15 of the 27 upstream ships/14 of the 27 upstream ships/' "$tmp/docs/.claude-plugin/marketplace.json"
expect_fail_at "a marketplace count other than its list" ".claude-plugin/marketplace.json:1"
copy; sed -i.bak 's/15 skills installed, 6 listed/15 skills installed, 7 listed/' "$tmp/docs/NOTICE"
expect_fail_at "a NOTICE count other than the manifest's" "NOTICE:$(tool_line '7 listed in' NOTICE)"
copy; sed -i.bak "s/adds its six\$/adds its seven/" "$tmp/docs/skills/arsenal/SKILL.md"
expect_fail_at "\"adds its seven\" for six" "skills/arsenal/SKILL.md:$(tool_line 'adds its seven' skills/arsenal/SKILL.md)"
copy; printf '\nclaude plugin update taste-skill@plinth\n' >>"$tmp/docs/docs/how-to/cut-a-release.md"
expect_fail "a one-time command repeated outside the README" docs/how-to/cut-a-release.md
copy; sed -i.bak 's/--squash --match-head-commit <sha> --body/--squash --body/' "$tmp/docs/docs/how-to/run-a-project.md"
expect_fail_at "a squash-merge command that differs" "docs/how-to/run-a-project.md:$(tool_line 'gh pr merge <n> --squash' docs/how-to/run-a-project.md)"
copy; sed -i.bak '/^  2\. "Can I see it?"$/d' "$tmp/docs/docs/how-to/run-a-project.md"
expect_fail_at "a step 5 that lists two of the three questions" "docs/how-to/run-a-project.md:$(grep -n -m1 '^### 5\.' "$tmp/docs/docs/how-to/run-a-project.md" | cut -d: -f1)"
copy; sed -i.bak 's/"Can I see it?", "What did the reviewer say?" |/"Can I see it?" |/' "$tmp/docs/skills/arsenal/SKILL.md"
expect_fail_at "an arsenal cell that names the three questions and says two" "skills/arsenal/SKILL.md:$(tool_line '"Can I see it?" |' skills/arsenal/SKILL.md)"
copy; printf '\nThen ask the three questions.\n' >>"$tmp/docs/skills/guide/SKILL.md"
expect_fail "a line that names the three questions and says none" skills/guide/SKILL.md
exit "$status"
