#!/usr/bin/env bash
# The documentation and skill text, read against its sources (#1103). Seven
# tests did this one way each; their cases are the rows of the table at the
# end of this file, grouped by the test each came from, and the logic is the
# kinds below. A row is `kind ¦ description ¦ arg ¦ arg ...`; it prints one
# PASS or FAIL. `-- ¦ text` prints a heading, and `refuses ¦ description ¦
# <kind> ¦ <args...>` passes only when that kind fails (a must-not-pass case).
# In a description, each `{}` is filled, in order, with a line the kind prints
# when it passes. An argument `@<group>/<path>` names a fixture under the work
# folder, built once when a row first names its group; `TEMPLATE` names the
# checkout of plinth-template at the commit scripts/new-project.sh pins
# (tests/lib/template-checkout.sh), made once, the first time a row names it.
# No checkout is a FAIL on each row that needs one, never a pass.
# Network: the template checkout when PLINTH_TEMPLATE_DIR is unset, and the
# issue states the arsenal rows read with `gh api`.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/template-checkout.sh
. "$root/tests/lib/template-checkout.sh"
work="$(mktemp -d)" || { echo "doc-consistency: could not make a temp folder" >&2; exit 1; }; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

# ---- What the rows read ------------------------------------------------------

# at <arg>: the path an argument names: a fixture, the template checkout, or a
# path in this repository.
at() {
  case "$1" in
    TEMPLATE) printf '%s' "$template_dir" ;;
    @*) printf '%s' "$work/${1#@}" ;;
    *) printf '%s' "$root/$1" ;;
  esac
}

# flat <file>: one line, line breaks and runs of spaces as one space.
flat() { tr '\n' ' ' <"$1" | tr -s ' '; }

# text_of <name>: a named text, or a file read as one line. Returns 1 when the
# text is empty or cannot be read.
questions_md="$root/skills/new-project/questions.md"
text_of() {
  local t n name
  case "$1" in
    # /plinth:new-project's step 8, from its heading to the next, as one line.
    step8) t="$(awk '/^## 8\. Every answer in one table/ {on=1; print; next} on && /^## / {exit} on' "$questions_md" | tr '\n' ' ' | tr -s ' ')" ;;
    questions) t="$(flat "$questions_md")" ;;
    concepts) t="$(flat "$root/docs/explanation/concepts.md")" ;;
    skill+questions) t="$(cat "$root/skills/new-project/SKILL.md" "$questions_md" | tr '\n' ' ' | tr -s ' ')" ;;
    # The "change some" groups step 8 names, one per line.
    groups) t="$(text_of step8 | grep -oE '\| (Name and folder|Records language and description|License|Reviewer and code of conduct) \| rows? [0-9, and]+ \|' | sort -u)" ;;
    # row:<n>:<name>: step 8's table row whose first cells are <n> and <name>.
    row:*)
      n="${1#row:}"; name="${n#*:}"; n="${n%%:*}"
      t="$(text_of step8 | grep -oE "\| $n \| $name \|[^|]*\|[^|]*\|" | head -n 1)" ;;
    *) [ -r "$(at "$1")" ] || { echo "cannot read $1"; return 1; }; t="$(flat "$(at "$1")")" ;;
  esac
  [ -n "$t" ] || { echo "$1 is empty or missing"; return 1; }
  printf '%s\n' "$t"
}

# ---- Kinds: k_<kind> <args...> returns 0 when the check holds --------------

# refuses <kind> <args...>: the kind must fail (a must-not-pass case).
k_refuses() {
  local k="$1"; shift
  # A kind that does not exist fails for the wrong reason: never a pass here.
  declare -F "k_$k" >/dev/null || { echo "no kind \"$k\""; return 1; }
  if "k_$k" "$@"; then echo "it passed, and must not"; return 1; fi
  return 0
}

# has <text> <phrase>...: every phrase is in the text (fixed strings).
k_has() {
  local text p rc=0
  text="$(text_of "$1")" || { echo "$text"; return 1; }; shift
  for p in "$@"; do
    printf '%s\n' "$text" | grep -qF -- "$p" || { echo "does not say \"$p\""; rc=1; }
  done
  return $rc
}

# lacks <text> <phrase>: the phrase is not in the text, which must be readable.
k_lacks() {
  local text
  text="$(text_of "$1")" || { echo "$text"; return 1; }
  if printf '%s\n' "$text" | grep -qF -- "$2"; then echo "still says \"$2\""; return 1; fi
}

# nonempty <text>: the text exists.
k_nonempty() { local text; text="$(text_of "$1")" || { echo "$text"; return 1; }; }

# order <text> <first> <second>: <first> appears before <second>.
k_order() {
  local text a b
  text="$(text_of "$1")" || { echo "$text"; return 1; }
  a="$(printf '%s\n' "$text" | grep -bo -- "$2" | head -n 1 | cut -d: -f1)"
  b="$(printf '%s\n' "$text" | grep -bo -- "$3" | head -n 1 | cut -d: -f1)"
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] ||
    { echo "\"$2\" (at ${a:-none}) is not before \"$3\" (at ${b:-none})"; return 1; }
}

# match_lacks <text> <regex> <phrase>: the regex's first match exists and
# does not hold the phrase.
k_match_lacks() {
  local text m
  text="$(text_of "$1")" || { echo "$text"; return 1; }
  m="$(printf '%s\n' "$text" | grep -oE -- "$2" | head -n 1)"
  [ -n "$m" ] || { echo "nothing matches $2"; return 1; }
  case "$m" in *"$3"*) echo "it holds $3: $m"; return 1 ;; esac
}

# lines <text> <n>: the text is exactly <n> non-empty lines.
k_lines() {
  local text
  text="$(text_of "$1")" || { echo "$text"; return 1; }
  [ "$(printf '%s\n' "$text" | grep -c .)" = "$2" ] || { echo "not $2 lines:"; printf '%s\n' "$text"; return 1; }
}

# at_least <text> <phrase> <n>: the phrase occurs at least <n> times; prints
# the count.
k_at_least() {
  local text c
  text="$(text_of "$1")" || { echo "$text"; return 1; }
  c="$(printf '%s\n' "$text" | grep -oF -- "$2" | wc -l | tr -d ' ')"
  echo "$c"
  [ "$c" -ge "$3" ] || { echo "\"$2\" $c times, fewer than $3"; return 1; }
}

# install_block: the README install block and the tutorial's are the same
# bytes, and the block is the two lines the README promises. CI runs those bytes.
k_install_block() {
  local readme tutorial n
  block() { awk '/<!-- install-block:start -->/{p=1;next} /<!-- install-block:end -->/{p=0} p' "$1"; }
  readme="$(block "$root/README.md")"
  tutorial="$(block "$root/docs/tutorials/getting-started.md")"
  [ -n "$readme" ] || { echo "README.md has no install block"; return 1; }
  [ -n "$tutorial" ] || { echo "docs/tutorials/getting-started.md has no install block"; return 1; }
  if ! diff <(printf '%s\n' "$readme") <(printf '%s\n' "$tutorial"); then
    echo "README and tutorial install blocks differ"; return 1
  fi
  n="$(grep -c '^claude ' <<<"$readme")"
  [ "$n" = 2 ] || { echo "the install block has $n command lines, the README promises two"; return 1; }
  # plinth's marketplace only: every dependency lives there since #477 (#481).
  [ "$(head -1 <<<"$(grep '^claude ' <<<"$readme")")" = "claude plugin marketplace add coolbress/plinth" ] \
    || { echo "the install block does not add plinth's marketplace first"; return 1; }
  ! grep -q 'claude-plugins-official' <<<"$readme" \
    || { echo "the install block adds the official marketplace, which no dependency needs"; return 1; }
}

# ---- doc-pinned-facts: facts the docs state, read from the source (#641, #752)
# The template tag README.md and the tutorial name must be new-project.sh's
# template_ref; a per-archetype count of required checks a doc states must be
# the count floor-check.py's ruleset gives that archetype; the tools README.md's
# supported box and the tutorial's "Before you start" list (and the tutorial's
# count of them) must be the ones new-project.sh stops without; the skill
# counts the arsenal and the marketplace state must be the manifest's lists;
# the squash-merge command must read the same in the three pages that show it
# (#835); step 5 of run-a-project.md must list the three questions, and a
# line elsewhere that names them must say all three (#921). A doc that states
# no count passes; a wrong one fails with its file and line.
# facts_py <docs dir> [<section> [<item>]]: with a section, checks only it and
# prints the values its row's description takes; without one, checks all and
# prints only the FAIL lines (what a planted row reads).
facts_py() {
python3 - "$root" "$@" <<'PY'
import json, pathlib, re, subprocess, sys

root, docs = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
sel = sys.argv[3:]
matched = False
def on(sec, item=None):
    # A row whose section or item matches nothing fails below, never a silent pass.
    global matched
    if not sel:
        return True
    if sel[0] != sec:
        return False
    hit = item is None or len(sel) < 2 or sel[1] == item
    if hit and (item is not None or len(sel) < 2):
        matched = True
    return hit
fails = 0
def fail(msg):
    global fails
    fails += 1
    print(f"  FAIL  {msg}")
def ok(*vals):
    if sel:
        for v in vals:
            print(v)

words = {"eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14}
numbers = {"three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8}
src = (root / "scripts/new-project.sh").read_text(encoding="utf-8")

# 1. The template tag.
if on("tag"):
    ref = re.search(r'^template_ref="([^"]+)"$', src, re.M)
    if not ref:
        fail("scripts/new-project.sh has no template_ref line")
        ref = None
    else:
        ref = ref.group(1)
    tag = re.compile(r"plinth-template(?:@| |/releases/tag/)(v\d+\.\d+\.\d+)")
    for rel in ("README.md", "docs/tutorials/getting-started.md"):
        if not on("tag", rel):
            continue
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
            ok(seen, ref)

# 2. The per-archetype counts, from the ruleset as the door applies it.
if on("counts"):
    before = fails
    def count(archetype):
        cmd = [sys.executable, str(root / "scripts/floor-check.py"), "--print-ruleset",
               "--ruleset", str(root / "ruleset.json")] + (["--archetype", archetype] if archetype else [])
        data = json.loads(subprocess.run(cmd, check=True, capture_output=True, text=True).stdout)
        return sum(len(r["parameters"]["required_status_checks"]) for r in data["rules"]
                   if r["type"] == "required_status_checks")
    service = subprocess.run([sys.executable, str(root / "scripts/floor-check.py"), "--print-conditional-archetypes"],
                             check=True, capture_output=True, text=True).stdout.split()
    want = {None: count(None), **{a: count(a) for a in service}}

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
    if fails == before:
        ok(stated, ", ".join(f"{a or 'other'} {n}" for a, n in want.items()))

# 3. The tools the door stops without, as the two install pages list them.
def listed(rel, start, stop):
    text = (docs / rel).read_text(encoding="utf-8")
    i = text.find(start)
    if i < 0:
        fail(f"{rel} has no {start!r}: the tool list moved")
        return None, text, 0
    j = text.find(stop, i)
    span = text[i:j if j >= 0 else len(text)]
    return re.findall(r"`([a-z0-9]+)`", span), span, text.count("\n", 0, i) + 1
if on("tools") or on("toolcount"):
    tools = re.findall(r"^command -v ([a-z0-9]+)\s+>/dev/null \|\| (?:stop|miss) ", src, re.M)
    if not tools:
        fail("scripts/new-project.sh has no `command -v <tool> >/dev/null || miss` line")
    for rel, start, stop in (("README.md", "tools: `", "\n>\n"),
                             ("docs/tutorials/getting-started.md", "- Tools: ", "\n- ")):
        the_list, the_count = on("tools", rel), on("toolcount", rel)
        if not (the_list or the_count):
            continue
        names, span, line = listed(rel, start, stop)
        if names is None:
            continue
        if the_list:
            if sorted(set(names)) != sorted(tools):
                fail(f"{rel}:{line} lists the tools {sorted(set(names))}; scripts/new-project.sh checks {sorted(tools)}")
            else:
                ok(len(tools))
        m = re.search(r"checks\s+all\s+(\w+)", span)
        if m:
            got = numbers.get(m.group(1).lower(), int(m.group(1)) if m.group(1).isdigit() else -1)
            if got != len(tools):
                fail(f"{rel}:{line} says the generator checks all {m.group(1)}; it checks {len(tools)}")
            elif the_count:
                ok(m.group(1))
        elif the_count and sel:
            fail(f"{rel}:{line} says no \"checks all <n>\" for the tools")

# 4. The git floor the door stops below, which the install needs too (#771).
if on("git"):
    gf = re.search(r'^git_floor="([^"]+)"$', src, re.M)
    if not gf:
        fail("scripts/new-project.sh has no git_floor line")
    else:
        gitv = re.compile(r"\bgit`?\s+\(?(\d+\.\d+(?:\.\d+)?)\s+or\s+newer")
        for rel in ("README.md", "docs/tutorials/getting-started.md"):
            if not on("git", rel):
                continue
            text = (docs / rel).read_text(encoding="utf-8")
            found = [(text.count("\n", 0, m.start()) + 1, m.group(1)) for m in gitv.finditer(text)]
            if not found:
                fail(f"{rel} states no git floor (\"git {gf.group(1)} or newer\")")
            for n, v in found:
                if v != gf.group(1):
                    fail(f"{rel}:{n} states git {v} or newer; the door's git_floor is {gf.group(1)}")
            if found and all(v == gf.group(1) for _, v in found):
                ok(gf.group(1))

# 5. The skill counts (#835): the manifest's lists are the fact, and upstream's
# total is those two plus the skills the arsenal names as in neither.
if on("skills"):
    before = fails
    market = json.loads((docs / ".claude-plugin/marketplace.json").read_text(encoding="utf-8"))
    entries = {p["name"]: p for p in market["plugins"]}
    n_matt, n_extra = len(entries["mattpocock-skills"]["skills"]), len(entries["mattpocock-skills-extra"]["skills"])
    # The counts live beside the arsenal's SKILL.md: the listed tools and the
    # skills in neither in listed.md, the default set in installed.md.
    arsenal_rel = "skills/arsenal/listed.md"
    arsenal = (docs / arsenal_rel).read_text(encoding="utf-8")
    installed_rel = "skills/arsenal/installed.md"
    installed_md = (docs / installed_rel).read_text(encoding="utf-8")
    notice = (docs / "NOTICE").read_text(encoding="utf-8")
    counted = {**words, **numbers, "fifteen": 15}
    def num(raw):
        return int(raw) if raw.isdigit() else counted.get(raw.lower(), -1)
    neither = re.search(r"The (\w+) in neither\s+are ([^(.]+)[(.]", arsenal)
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
        (installed_rel, installed_md, r"\| `mattpocock-skills` \| (\w+) skills:", n_matt, "installed"),
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
    if fails == before:
        ok(f"{n_matt} installed, {n_extra} listed, {n_neither} in neither, {total} upstream")

# 6. The squash-merge command (#835), read with line breaks as one space.
# The template-rules rows hold plinth's CONTRIBUTING.md to the template's.
squash = 'body="$(gh pr view <n> --json body --jq .body)" && gh pr merge <n> --squash --match-head-commit <sha> --body "$body"'
for rel in ("CONTRIBUTING.md", "docs/tutorials/getting-started.md", "docs/how-to/run-a-project.md"):
    if not on("squash", rel):
        continue
    text = (docs / rel).read_text(encoding="utf-8")
    if squash in " ".join(text.split()):
        ok()
    else:
        i = text.find("gh pr merge <n>")
        fail(f"{rel}:{text.count(chr(10), 0, i) + 1 if i >= 0 else 1} does not show the squash-merge command as: {squash}")

# 7. The one-time update commands (#835): the README holds them, and
# tests/install-smoke.sh reads them there; these pages link to it.
for rel in ("docs/tutorials/getting-started.md", "docs/how-to/cut-a-release.md"):
    if not on("onetime", rel):
        continue
    text = (docs / rel).read_text(encoding="utf-8")
    if "README.md#install-in-detail" in text and "taste-skill@plinth" not in text:
        ok()
    else:
        i = text.find("taste-skill@plinth")
        fail(f"{rel}:{text.count(chr(10), 0, i) + 1 if i >= 0 else 1} must link README.md#install-in-detail and not repeat the one-time commands")

# 8. The three questions (#921): step 5 of run-a-project.md lists them under
# that name, and every other line that names them says all three.
# CHANGELOG.md is history and keeps the wording each release had.
if on("questions"):
    rap_rel = "docs/how-to/run-a-project.md"
    rap = (docs / rap_rel).read_text(encoding="utf-8")
    s5 = re.search(r"^### 5\..*?(?=^### 6\.)", rap, re.M | re.S)
    asked = []
    if s5:
        lst = re.search(r"the three questions:\n\n((?:[ \t]*\d+\. .*\n)+)", s5.group(0))
        if lst:
            asked = [m.group(1) or m.group(2) for m in re.finditer(r'\d+\. (?:"([^"]+)"|(.*))', lst.group(1))]
    s5_lines = range(rap.count("\n", 0, s5.start()) + 1, rap.count("\n", 0, s5.end()) + 1) if s5 else range(0)
    before = fails
    if len(asked) != 3:
        fail(f"{rap_rel}:{rap.count(chr(10), 0, s5.start()) + 1 if s5 else 1} step 5 lists {len(asked)} questions under \"the three questions:\", not three")
    named, before_lines = 0, fails
    for path in sorted([*(p for p in docs.glob("*.md") if p.name != "CHANGELOG.md"), *(docs / "docs").rglob("*.md"), *(docs / "skills").rglob("*.md")]):
        rel = path.relative_to(docs).as_posix()
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if "three questions" not in line.lower() or (rel == rap_rel and n in s5_lines):
                continue
            named += 1
            if len(asked) != 3:
                fail(f"{rel}:{n} names the three questions; step 5 does not list three to say")
                continue
            missing = [q for q in asked if q not in line]
            if missing:
                fail(f"{rel}:{n} names the three questions and does not say " + "; ".join(f'"{q}"' for q in missing))
    if fails == before:
        ok(named)

# 9. The first login (#1034): the tutorial's first `gh auth login -s` asks for
# the scopes new-project.sh stops without and nothing else, after a sentence
# that says the login administers the account's other repositories too; and no
# login or refresh that asks for those scopes, in a page or in the door's own
# stops, carries delete_repo, which stays an opt-in named on its own.
if on("login") or on("delete"):
    need = re.search(r"^  for s in ([a-z ]+); do has_scope ", src, re.M)
    need = need.group(1).split() if need else []
    if not need:
        fail("scripts/new-project.sh has no `for s in <scopes>; do has_scope` line: the scopes it needs cannot be read")
if on("login"):
    gs_rel = "docs/tutorials/getting-started.md"
    gs = (docs / gs_rel).read_text(encoding="utf-8")
    first = re.search(r"gh auth login -s ([a-z:_,]+)", gs)
    if not first:
        fail(f"{gs_rel} shows no `gh auth login -s` command")
    elif need:
        at = gs.count("\n", 0, first.start()) + 1
        if first.group(1).split(",") != need:
            fail(f"{gs_rel}:{at} the first login asks for {first.group(1)}; the door needs {','.join(need)}")
        elif not re.search(r"administer", gs[gs.find("## Before you start"):first.start()]):
            fail(f"{gs_rel}:{at} the first login comes before any sentence that says it can administer the account's other repositories")
        else:
            ok(first.group(1))
if on("delete"):
    login = re.compile(r"gh auth (?:login|refresh)\b[^`\"\n]*?-s ([a-z:_,]+)")
    pages = [("scripts/new-project.sh", src),
             *((p.relative_to(docs).as_posix(), p.read_text(encoding="utf-8"))
               for p in [docs / "README.md", *sorted((docs / "docs").rglob("*.md")), *sorted((docs / "skills").rglob("*.md"))]
               if p.is_file())]
    before = fails
    for rel, text in pages:
        for m in login.finditer(text):
            got = m.group(1).split(",")
            if need and all(s in got for s in need) and "delete_repo" in got:
                fail(f"{rel}:{text.count(chr(10), 0, m.start()) + 1} offers {m.group(0)}: delete_repo is an opt-in, named apart from the scopes the run needs")
    if fails == before and need:
        ok(",".join(need))

if sel and not matched:
    fail(f"nothing is checked as {' '.join(sel)}: no such section or item")
sys.exit(1 if fails else 0)
PY
}

# fact <section> [<item>]: one of the checker's facts holds in this checkout.
k_fact() { facts_py "$root" "$@"; }

# planted <file> <append|sed> <line or sed expression> <end|line:<n>|grep:<pattern>>:
# a copy of the docs with one wrong line makes the checker fail at that line,
# so it cannot pass without looking. append adds the line at the end (`end`
# is then its number); grep: reads the line number in the edited copy.
k_planted() {
  local file="$1" how="$2" arg="$3" spot="$4" where out line
  rm -rf "$work/docs"; mkdir -p "$work/docs"
  cp "$root"/README.md "$root"/GLOSSARY.md "$root"/CONTRIBUTING.md "$root"/NOTICE "$work/docs/" || return 1
  cp -R "$root/docs" "$root/skills" "$root/.claude-plugin" "$work/docs/" || return 1
  case "$how" in
    append) printf '\n%s\n' "$arg" >>"$work/docs/$file" ;;
    sed) sed -i.bak "$arg" "$work/docs/$file" ;;
    *) echo "unknown edit: $how"; return 1 ;;
  esac
  case "$spot" in
    end) where="$file:$(wc -l <"$work/docs/$file" | tr -d ' ')" ;;
    line:*) where="$file:${spot#line:}" ;;
    grep:*) where="$file:$(grep -n -m1 -- "${spot#grep:}" "$work/docs/$file" | cut -d: -f1)" ;;
    *) echo "unknown place: $spot"; return 1 ;;
  esac
  out="$(facts_py "$work/docs")"
  line="$(grep -m1 "FAIL  $where " <<<"$out")"
  if [ -n "$line" ]; then echo "${line#*FAIL  }"
  else echo "did not fail at $where: the checker does not look"; return 1; fi
}

# ---- term-table: the fixed term table (#809) ---------------------------------
# docs/reference/terms.md has one row per term a beginner meets in the first
# project, each with a plain explanation, and states the rule that the English
# term stays in brackets after a translation.
terms=(repository issue "pull request" branch commit check CI merge ruleset draft review "template update" "workflow run" "job summary" annotation)

# term_table <file>: prints each missing or empty row; prints the term count
# when none is.
k_term_table() {
  local f t row expl rc=0
  f="$(at "$1")"
  [ -r "$f" ] || { echo "unreadable: $f"; return 1; }
  for t in "${terms[@]}"; do
    row="$(grep -E "^\| \*\*$t\*\* \|" "$f" | head -1)"
    if [ -z "$row" ]; then echo "no row: $t"; rc=1; continue; fi
    expl="$(printf '%s' "$row" | awk -F'|' '{print $3}' | tr -d '[:space:]')"
    [ -n "$expl" ] || { echo "no explanation: $t"; rc=1; }
  done
  grep -q -E 'English term .*in brackets' "$f" || { echo "no bracket rule"; rc=1; }
  [ "$rc" = 0 ] && echo "${#terms[@]}"
  return $rc
}

fx_terms() { # a complete table, then one missing a term, one with an empty explanation, one without the rule
  local d="$work/terms" t good
  mkdir -p "$d"; good="$d/good.md"
  { echo "Keep the English term in brackets after any translation."
    echo "| Term | Plain explanation |"; echo "| --- | --- |"
    for t in "${terms[@]}"; do echo "| **$t** | words |"; done; } >"$good"
  grep -v -F '**ruleset**' "$good" >"$d/missing.md"
  sed 's/^| \*\*draft\*\* | words |$/| **draft** |  |/' "$good" >"$d/empty.md"
  grep -v 'in brackets' "$good" >"$d/norule.md"
}

# ---- template-rules-drift: rules plinth shares with the template (#819) -----
# plinth is not rendered from the template, so a template update never reaches
# its own rules. Each rule plinth shares with the template's AGENTS.md,
# CONTRIBUTING.md, pull-request form and issue tracker page is a named phrase
# below: the phrase must be in the template at the pinned commit, and its
# counterpart in plinth's file. Not a file comparison: most of each file is its
# own. A pin raise that rewords or drops a listed rule fails here; whoever
# raises the pin adds the rule to plinth, or writes `differs: <why>` as the
# counterpart. A rule the template adds that is not listed is not caught: list
# it when the pin raise brings it.
# name | template file | phrase in the template | plinth file | its counterpart
# (fixed strings). Template files: agents = template/AGENTS.md.jinja,
# form = template/.github/PULL_REQUEST_TEMPLATE.md,
# contributing = template/CONTRIBUTING.md.jinja,
# tracker = template/docs/agents/issue-tracker.md.jinja. Plinth files are paths.
rules=(
  "fresh-context default|agents|The default review is a fresh-context review, before the description is written|AGENTS.md|The default review is a fresh-context review, before the description is written"
  "fresh-context reads the review rules|agents|Read by the fresh-context review|AGENTS.md|Read by the fresh-context review"
  "term table|agents|add its plain explanation once, in their language, and keep the English term in brackets|AGENTS.md|add its plain explanation once, in their language, and keep the English term in brackets"
  "record ending|agents|ends in \`## Decision\` instead|docs/agents/issue-tracker.md|a record ends in \`## Decision\`"
  "checked-myself field|form|## What I checked myself|.github/PULL_REQUEST_TEMPLATE.md|## What I checked myself"
  "review field|form|Review: <!-- which review ran: fresh-context \| third-party (<name>) \| same-session (not independent) \| none (<reason>) -->|.github/PULL_REQUEST_TEMPLATE.md|Review: <!-- which review ran: fresh-context \| third-party (<name>) \| same-session (not independent) \| none (<reason>) -->"
  "another repository's reference|agents|A reference to another repository's issue or pull request is \`owner/repo#N\`; a bare \`#N\`, or \`plinth #N\`, links to this repository's own \`#N\`.|docs/agents/issue-tracker.md|A reference to another repository's issue or pull request is \`owner/repo#N\`; a bare \`#N\`, or \`plinth #N\`, links to this repository's own \`#N\`."
  "another repository's reference in the form|form|Any reference to another repository's issue or pull request, here or above: \`owner/repo#N\`.|.github/PULL_REQUEST_TEMPLATE.md|Any reference to another repository's issue or pull request, here or above: \`owner/repo#N\`."
  "public records|agents|Write them as public: no home path, account or folder name from the person's computer|AGENTS.md|Write them as public: no home path, account or folder name from the owner's computer"
  "public records in the form|form|A pasted output keeps home paths out: \`~/...\`, or the condition it shows.|.github/PULL_REQUEST_TEMPLATE.md|A pasted output keeps home paths out: \`~/...\`, or the condition it shows."
  "squash-merge command|contributing|body=\"\$(gh pr view <n> --json body --jq .body)\" && gh pr merge <n> --squash --match-head-commit <sha> --body \"\$body\"|CONTRIBUTING.md|body=\"\$(gh pr view <n> --json body --jq .body)\" && gh pr merge <n> --squash --match-head-commit <sha> --body \"\$body\""
  "a defect is a bug|tracker|A defect is a \`bug\`, whoever finds it: a person who reports it, or an agent that reproduced it and can say what the fix must do.|docs/agents/issue-tracker.md|A defect is a \`bug\`, whoever finds it: a person who reports it, or an agent that reproduced it and can say what the fix must do."
  "a ready bug's criteria|tracker|A \`bug\` made \`ready-for-agent\` gains \`## Acceptance criteria\` (and \`## Not building\` when it helps) below the form's fields, in the same issue|docs/agents/issue-tracker.md|A \`bug\` made \`ready-for-agent\` gains \`## Acceptance criteria\` (and \`## Not building\` when it helps) below the form's fields, in the same issue"
)

# has_flat <file> <phrase>: the phrase is in the file, line breaks and runs of
# spaces read as one space, so rewrapping a paragraph does not break a match.
has_flat() { [ -r "$1" ] && tr '\n' ' ' <"$1" | tr -s ' ' | grep -qF -- "$2"; }

# check_rules <template dir> <plinth dir>: one line per broken rule; returns 1 if any.
check_rules() {
  local tdir="$1" pdir="$2" entry name tfile tphrase pfile pphrase rc=0
  for entry in "${rules[@]}"; do
    entry="${entry//\\|/$'\x1f'}"
    IFS='|' read -r name tfile tphrase pfile pphrase <<<"$entry"
    tphrase="${tphrase//$'\x1f'/|}"; pphrase="${pphrase//$'\x1f'/|}"
    if ! has_flat "$tdir/$tfile" "$tphrase"; then
      echo "$name: the template no longer has \"$tphrase\"; update this entry"; rc=1; continue
    fi
    case "$pphrase" in differs:*) continue ;; esac
    has_flat "$pdir/$pfile" "$pphrase" || { echo "$name: $pfile lacks \"$pphrase\""; rc=1; }
  done
  return $rc
}

# template_rules <template dir> <plinth dir>: every listed rule holds.
k_template_rules() { check_rules "$(at "$1")" "$(at "$2")"; }

# template_rules_real TEMPLATE: the template's four files at the pinned commit
# against plinth's own; prints how the checkout is named and the rule count.
k_template_rules_real() {
  local t
  t="$(at "$1")/template"
  mkdir -p "$work/real"
  cp "$t/AGENTS.md.jinja" "$work/real/agents" 2>/dev/null; cp "$t/.github/PULL_REQUEST_TEMPLATE.md" "$work/real/form" 2>/dev/null
  cp "$t/CONTRIBUTING.md.jinja" "$work/real/contributing" 2>/dev/null
  cp "$t/docs/agents/issue-tracker.md.jinja" "$work/real/tracker" 2>/dev/null
  if ! { [ -s "$work/real/agents" ] && [ -s "$work/real/form" ] && [ -s "$work/real/contributing" ] && [ -s "$work/real/tracker" ]; }; then
    echo "$template_at has no AGENTS.md.jinja, CONTRIBUTING.md.jinja, pull-request form or docs/agents/issue-tracker.md.jinja under template/; cannot verify"; return 1
  fi
  check_rules "$work/real" "$root" || { echo "(rules shared with $template_at missing or stale)"; return 1; }
  echo "$template_at"; echo "${#rules[@]}"
}

fx_rules() { # a fixture carrying every rule, one plinth file missing one, a template missing one
  local d="$work/rules" entry tfile tphrase pfile pphrase
  mkdir -p "$d/t" "$d/p/.github" "$d/p/docs/agents"
  for entry in "${rules[@]}"; do
    entry="${entry//\\|/$'\x1f'}"
    IFS='|' read -r _ tfile tphrase pfile pphrase <<<"$entry"
    printf '%s\n' "${tphrase//$'\x1f'/|}" >>"$d/t/$tfile"
    printf '%s\n' "${pphrase//$'\x1f'/|}" >>"$d/p/$pfile"
  done
  cp -R "$d/p" "$d/p2"; grep -vF 'Read by the fresh-context review' "$d/p/AGENTS.md" >"$d/p2/AGENTS.md"
  cp -R "$d/t" "$d/t2"; grep -vF 'What I checked myself' "$d/t/form" >"$d/t2/form"
}

# ---- arsenal-freshness: the arsenal says what ships (#833) ------------------
# A row written before a release workflow existed told a real project that a
# release on a tag was "planned, not built yet", and nothing tied the claim to
# the template. These read the template at the pinned commit and the whole of
# skills/arsenal/ (SKILL.md and the installed.md and listed.md beside it) and
# fail when:
#   - a table cell says "planned", "not built yet" or "nothing yet" about
#     something the template renders or the plugin installs;
#   - a cell names an issue as the plan and that issue is closed or unreadable;
#   - a cell marks a tool "(listed", or the "Listed, not installed" table
#     (listed.md) names a plugin, that the plugin installs;
#   - the release row, the reminder row or run-a-project.md does not say what
#     the template has, archetype by archetype;
#   - plinth's own user-only skill is not on the one list of skills the person
#     types, or a page that used to repeat that list does not point at it.
# It reads the template's source tree, not a render. Other words for a plan
# ("waits for #N") are not caught, and the frontmatter of the dependencies'
# skills is not read: only plinth's own are held against the list. The issues
# are read over the network; unreadable is a FAIL.
typed_section="Skills only the person can start"
typed_anchor="skills-only-the-person-can-start"
release_row="| A merged change to put out"
reminder_row="| Between pieces of work"
plan_row="| A job bigger than one session"

# Each table cell in the catalog's files, one per line.
cells() { grep -h '^| ' "$@" | sed -e 's/^| //' -e 's/ |$//' | awk '{ gsub(/ \| /, "\n"); print }'; }

# arsenal_files <arsenal dir>: SKILL.md and the two files beside it that hold
# tables; one missing is an error, not a file with no stale claim.
arsenal_files() {
  local f
  for f in SKILL.md installed.md listed.md; do
    [ -f "$1/$f" ] || { echo "no $f in $1" >&2; return 1; }
  done
}

# The live rows also read the maintainers' page the evidence tables moved to,
# which keeps the issue numbers the catalog's files no longer carry.
evidence=""

# real_state <owner/repo> <n>: open or closed; nothing when it cannot be read.
real_state() { gh api "repos/$1/issues/$2" --jq .state 2>/dev/null; }
# The fixtures' issue states come from a stub, not the network.
stub_state() { case "$2" in 703|706) echo closed ;; 900) echo open ;; *) ;; esac; }
state_of=real_state

# installed <plinth dir>: what the plugin installs, one name per line: its own
# skills, its dependencies, and the skills their marketplace entries carry.
installed() {
  local p="$1"
  find "$p/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | while read -r f; do basename "$(dirname "$f")"; done
  jq -r '.dependencies[]? | if type == "string" then . else .name end' "$p/.claude-plugin/plugin.json" |
    while read -r dep; do
      echo "$dep"
      jq -r --arg d "$dep" '.plugins[] | select(.name == $d) | .skills[]?' "$p/.claude-plugin/marketplace.json" | sed 's#.*/##'
    done
}

# release_sources <template dir>: the template's conditional release workflows.
release_sources() { find "$1/template/.github/workflows" -type f -name '*release.yml*' 2>/dev/null; }

# stale_claims <arsenal dir> <template dir> <plinth dir>: one line per stale claim.
stale_claims() {
  local adir="$1" tdir="$2" pdir="$3" cell issue repo n state rc=0 name inst
  arsenal_files "$adir" 2>&1 || return 1
  inst="$(installed "$pdir")"
  # The guide's own cells for each step (#1086) are read with the catalog.
  local guide_steps=(); [ ! -f "$adir/../guide/steps.md" ] || guide_steps=("$adir/../guide/steps.md")
  while IFS= read -r cell; do
    if grep -qiE 'planned|not built yet|nothing yet' <<<"$cell"; then
      if grep -qiE 'release|publish' <<<"$cell" && [ -n "$(release_sources "$tdir")" ]; then
        echo "says not there, but the template renders a release workflow: $cell"; rc=1
      fi
      if grep -qi 'reminder' <<<"$cell" && [ -f "$tdir/template/.github/workflows/template-reminder.yml" ]; then
        echo "says not there, but the template renders the reminder: $cell"; rc=1
      fi
      for name in $(grep -oE '`/?[a-zA-Z0-9:_.-]+`' <<<"$cell" | tr -d '`' | sed -e 's#^/##' -e 's#^plinth:##'); do
        if grep -qxF -- "$name" <<<"$inst"; then
          echo "says not there, but the plugin installs \`$name\`: $cell"; rc=1
        fi
      done
    fi
    if grep -qiE '(^|[^a-z])plan(ned)?([^a-z]|$)' <<<"$cell"; then
      for issue in $(grep -oE '([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[0-9]+' <<<"$cell"); do
        repo="${issue%#*}"; n="${issue##*#}"
        state="$("$state_of" "${repo:-coolbress/plinth}" "$n")"
        case "$state" in
          open) ;;
          closed) echo "names $issue as the plan, and it is closed: $cell"; rc=1 ;;
          *) echo "names $issue as the plan, and its state could not be read: $cell"; rc=1 ;;
        esac
      done
    fi
    for name in $(grep -oE '`/?[a-zA-Z0-9:_.-]+` \(listed' <<<"$cell" | cut -d'`' -f2 | sed -e 's#^/##' -e 's#^plinth:##'); do
      if grep -qxF -- "$name" <<<"$inst"; then
        echo "marks \`$name\` listed, and the plugin installs it: $cell"; rc=1
      fi
    done
  done < <(cells "$adir/SKILL.md" "$adir/installed.md" "$adir/listed.md" ${evidence:+"$evidence"} ${guide_steps[@]+"${guide_steps[@]}"})
  while IFS= read -r name; do
    if grep -qxF -- "$name" <<<"$inst"; then
      echo "the \"Listed, not installed\" table names \`$name\`, and the plugin installs it"; rc=1
    fi
  done < <(grep '^| `' "$adir/listed.md" | cut -d'`' -f2)
  return $rc
}

# missing_facts <arsenal dir> <run-a-project> <template dir>: what the template
# has and the release row, the reminder row or step 9 does not say.
missing_facts() {
  local arsenal="$1/SKILL.md" howto="$2" tdir="$3" row src arch archs all_archs="" dest rc=0 step9 reminder title steps
  row="$(grep -F -- "$release_row" "$arsenal" | head -1)"
  [ -n "$row" ] || { echo "the arsenal has no row starting '$release_row'"; rc=1; }
  # The row's facts, wherever they are (#1086): the arsenal's stage row and,
  # where the plugin has it, the guide's own row for the step beside it.
  steps="$1/../guide/steps.md"
  [ ! -f "$steps" ] || row="$row $(grep -F -- "$release_row" "$steps" | head -1)"
  if [ -z "$(release_sources "$tdir")" ]; then
    echo "the template has no release workflow; the release row needs rewriting"; rc=1
  fi
  while IFS= read -r src; do
    [ -n "$src" ] || continue
    if grep -qiE 'pypi' "$src"; then dest="PyPI"
    elif grep -q 'ghcr\.io' "$src"; then dest="GHCR"
    else dest="GitHub release"; fi
    archs="$(basename "$src" | sed 's/{% endif.*//' | grep -oE "'[a-z-]+'" | tr -d "'")"
    [ -n "$archs" ] || { echo "no archetype in the workflow's file name, so the row cannot be checked: $(basename "$src")"; rc=1; }
    all_archs="$all_archs $archs"
    for arch in $archs; do
      grep -qE "\`$arch\`[^,;]*$dest" <<<"$row" || { echo "the release row does not say \`$arch\` goes to $dest: $row"; rc=1; }
    done
  done < <(release_sources "$tdir")
  # The other way round: the row names no archetype beyond those with a
  # workflow (`web` deploys, `main` is the branch).
  for arch in $(grep -oE '`[a-z-]+`' <<<"$row" | tr -d '`'); do
    case "$arch" in web|main) continue ;; esac
    case " $(echo $all_archs) " in *" $arch "*) ;; *) echo "the release row names \`$arch\`, and the template has no release workflow for it"; rc=1 ;; esac
  done
  if [ -f "$tdir/template/docs/how-to/publish-a-release.md.jinja" ]; then
    grep -qF 'docs/how-to/publish-a-release.md' <<<"$row" || { echo "the release row does not name docs/how-to/publish-a-release.md"; rc=1; }
  else
    echo "the template has no docs/how-to/publish-a-release.md.jinja; the release row names it"; rc=1
  fi
  grep -qE '`web`[^,;]*Render' <<<"$row" || { echo "the release row does not say \`web\` goes out on Render"; rc=1; }
  flat "$howto" | grep -qF 'A merged change to put out' || { echo "run-a-project.md does not point at the release row"; rc=1; }

  reminder="$tdir/template/.github/workflows/template-reminder.yml"
  if [ -f "$reminder" ]; then
    title="$(sed -n 's/.*title="\(Template update available\):.*/\1/p' "$reminder" | head -1)"
    if [ -z "$title" ] || ! grep -qF '/plinth:template-update' "$reminder"; then
      echo "the reminder workflow no longer titles its issue 'Template update available:' or names /plinth:template-update; update this test and the two places"; rc=1
    else
      step9="$(awk '/^### 9\./{on=1; next} on && /^#/{exit} on' "$howto" | tr '\n' ' ' | tr -s ' ')"
      row="$(grep -F -- "$reminder_row" "$arsenal" | head -1)"
      grep -qF "$title" <<<"$row" && grep -qF '/plinth:template-update' <<<"$row" || { echo "the 'Between pieces of work' row does not name the reminder issue and what to type"; rc=1; }
      grep -qF "$title" <<<"$step9" && grep -qF '/plinth:template-update' <<<"$step9" || { echo "run-a-project.md step 9 does not name the reminder issue and what to type"; rc=1; }
    fi
  else
    echo "the template has no template-reminder.yml; the 'Between pieces of work' row and step 9 name it"; rc=1
  fi
  return $rc
}

# typed_list <plinth dir>: the one list holds plinth's own user-only skills, the
# other pages point at it, and step 3's row asks for nothing the person must type.
typed_list() {
  local p="$1" f list rc=0 name
  list="$(awk -v h="## $typed_section" 'index($0, h) == 1 {on=1; next} on && /^## /{exit} on' "$p/skills/arsenal/SKILL.md")"
  [ -n "$list" ] || { echo "the arsenal has no section '$typed_section'"; rc=1; }
  for f in "$p"/skills/*/SKILL.md; do
    grep -q '^disable-model-invocation: true' "$f" || continue
    name="$(basename "$(dirname "$f")")"
    grep -qF "/plinth:$name" <<<"$list" || { echo "/plinth:$name is user-only and not on the list"; rc=1; }
  done
  flat "$p/skills/guide/SKILL.md" | grep -qF "$typed_section" || { echo "skills/guide/SKILL.md does not point at the list"; rc=1; }
  grep -qF "$typed_anchor" "$p/docs/how-to/run-a-project.md" || { echo "run-a-project.md does not point at the list"; rc=1; }
  grep -qF "$typed_anchor" "$p/README.md" || { echo "README.md does not point at the list"; rc=1; }
  grep -F -- '| `mattpocock-skills` |' "$p/skills/arsenal/installed.md" | grep -qF "$typed_section" || { echo "the mattpocock-skills row in installed.md does not point at the list"; rc=1; }
  if grep -F -- "$plan_row" "$p/skills/arsenal/SKILL.md" | grep -qi 'ask for it'; then
    echo "step 3's row says 'ask for it' for a skill the person must type"; rc=1
  fi
  return $rc
}

# ars_mode <stub|live>: issue states from the stub, or from the network with
# the evidence page read beside the catalog.
ars_mode() {
  if [ "$1" = stub ]; then state_of=stub_state; evidence=""
  else state_of=real_state; evidence="$root/docs/reference/arsenal-evidence.md"; fi
}

# stale_claims <stub|live> <arsenal dir> <template dir> <plinth dir>: no stale
# claim; see ars_mode. Prints how the checkout is named when it reads the
# template's.
k_stale_claims() {
  ars_mode "$1"
  stale_claims "$(at "$2")" "$(at "$3")" "$(at "$4")" || return 1
  [ "$3" != TEMPLATE ] || echo "$template_at"
}

# stale_claim_names <stub|live> <phrase> <arsenal dir> <template dir> <plinth dir>:
# a stale claim is found, and one of them says the phrase.
k_stale_claim_names() {
  local out
  ars_mode "$1"
  if out="$(stale_claims "$(at "$3")" "$(at "$4")" "$(at "$5")")"; then echo "no stale claim found"; return 1; fi
  grep -qF -- "$2" <<<"$out" || { echo "no claim says \"$2\":"; printf '%s\n' "$out"; return 1; }
}

# missing_facts <arsenal dir> <run-a-project> <template dir>: no fact missing.
k_missing_facts() {
  missing_facts "$(at "$1")" "$(at "$2")" "$(at "$3")" || return 1
  [ "$3" != TEMPLATE ] || echo "$template_at"
}

# typed_list <plinth dir>: one typed list, and the pages point at it.
k_typed_list() { typed_list "$(at "$1")"; }

# issue_state <owner/repo> <n> <state>: the live lookup reads that state.
k_issue_state() {
  local s
  s="$(real_state "$1" "$2")"
  [ "$s" = "$3" ] || { echo "could not read $1#$2's state (got \"$s\", want $3); a named plan cannot be verified"; return 1; }
}

fx_ars() { # a template and a plinth that agree, and the variants that must not pass
  local d="$work/ars" t p a h
  t="$d/t"; p="$d/p"
  mkdir -p "$t/template/.github/workflows" "$t/template/docs/how-to" "$p/skills/arsenal" "$p/skills/guide" "$p/.claude-plugin" "$p/docs/how-to"
  printf 'uses: pypa/gh-action-pypi-publish\n' >"$t/template/.github/workflows/{% if archetype in ['cli', 'library'] %}release.yml{% endif %}"
  printf 'image: ghcr.io/x\n' >"$t/template/.github/workflows/{% if archetype == 'backend' %}release.yml{% endif %}"
  printf 'gh release create\n' >"$t/template/.github/workflows/{% if archetype == 'data-ml' %}release.yml{% endif %}"
  printf 'body\n' >"$t/template/docs/how-to/publish-a-release.md.jinja"
  printf 'title="Template update available: $a to $b"\nrun /plinth:template-update\n' >"$t/template/.github/workflows/template-reminder.yml"
  printf '{"dependencies":["dep"]}\n' >"$p/.claude-plugin/plugin.json"
  printf '{"plugins":[{"name":"dep","skills":["./engineering/implement"]},{"name":"extra","skills":["./engineering/ask-matt"]}]}\n' >"$p/.claude-plugin/marketplace.json"
  cat >"$p/skills/arsenal/SKILL.md" <<'ROW'
## Where you are, and what to do next

| Where you are | Next action | Tool |
| --- | --- | --- |
| A job bigger than one session (step 3) | A plan in one issue | `/implement`, typed |
| Between pieces of work (step 9) | The template update | The monthly issue "Template update available: …": type `/plinth:template-update` |
| A merged change to put out (release and deploy) | A `web` app on Render goes out by itself; `cli` and `library` publish to PyPI, `backend` its image to GHCR, `data-ml` its model as a GitHub release | The project's `docs/how-to/publish-a-release.md` |
| Unsure | Say | `/ask-matt` (listed) |

## Skills only the person can start

- `/plinth:guide`
ROW
  printf '# Installed by default\n\n| Plugin | What |\n| --- | --- |\n| `mattpocock-skills` | See "Skills only the person can start" |\n' >"$p/skills/arsenal/installed.md"
  printf '# Listed, not installed\n\n| Plugin | What |\n| --- | --- |\n| `extra` | More |\n' >"$p/skills/arsenal/listed.md"
  printf -- '---\nname: guide\ndisable-model-invocation: true\n---\nThe arsenal, "Skills only the person can start".\n' >"$p/skills/guide/SKILL.md"
  printf '[list](x#skills-only-the-person-can-start)\n' >"$p/README.md"
  cat >"$p/docs/how-to/run-a-project.md" <<'H'
Release: the row "A merged change to put out". [list](x#skills-only-the-person-can-start)

### 9. Keep it healthy

An issue "Template update available: …": type `/plinth:template-update`.

### Next
H
  a="$p/skills/arsenal"; h="$p/docs/how-to/run-a-project.md"
  # ars_variant <name> <sed expression> [<file>]: a copy of the good catalog's
  # folder with one line of SKILL.md (or of <file>) changed.
  ars_variant() { cp -R "$a" "$d/$1"; sed -i.bak "$2" "$d/$1/${3:-SKILL.md}"; rm -f "$d/$1/"*.bak; }
  # The release row as it stood when it told a real project a release was not built (#833).
  local old_row='| A merged change to put out (release and deploy, after step 6) | A `web` app on Render goes out by itself once `main` is green; the other archetypes publish nothing yet | Render, from `${CLAUDE_PLUGIN_ROOT}/docs/how-to/choose-where-a-web-app-runs.md`; a release on a tag is planned for `library` and `cli` (#703) and `backend` (#706), not built yet |'
  cp -R "$a" "$d/old"; awk -v r="$old_row" 'index($0, "| A merged change to put out") == 1 { print r; next } { print }' "$a/SKILL.md" >"$d/old/SKILL.md"
  # The good catalog with one line changed, one folder per name.
  ars_variant a 's/| Say |/| A release is planned (#900) |/'
  ars_variant b 's/| Say |/| Planned in #703 |/'
  ars_variant c 's/| Say |/| Planned in #901 |/'
  ars_variant d 's|Say |Planned in owner/repo#703 |'
  ars_variant e 's/| Say |/| The reminder is not built yet |/'
  ars_variant f 's/| Say |/| `\/implement` is planned |/'
  ars_variant g 's|`/ask-matt` (listed)|`/implement` (listed)|'
  ars_variant h 's/^nothing$//' listed.md; printf '| `dep` | More |\n' >>"$d/h/listed.md"
  ars_variant h2 's/| More |/| `\/implement` (listed) |/' listed.md
  ars_variant h3 's/^nothing$//'; rm "$d/h3/listed.md"
  ars_variant i 's/, `data-ml` its model as a GitHub release//'
  ars_variant j 's/`backend` its image to GHCR/`backend` its image to PyPI/'
  ars_variant k 's/The monthly issue "Template update available: …"/The monthly issue/'
  sed 's/An issue "Template update available: …"/An issue/' "$h" >"$d/h9.md"
  grep -v 'A merged change' "$h" >"$d/hr.md"
  mkdir -p "$d/empty/template"
  # Each file the catalog names, gone from the template; and one workflow whose
  # name carries no archetype.
  cp -R "$t" "$d/t2"; rm "$d/t2/template/.github/workflows/template-reminder.yml"
  cp -R "$t" "$d/t3"; rm "$d/t3/template/docs/how-to/publish-a-release.md.jinja"
  cp -R "$t" "$d/t4"; rm "$d/t4/template/.github/workflows/"*release.yml*
  printf 'uses: pypa/gh-action-pypi-publish\n' >"$d/t4/template/.github/workflows/release.yml.jinja"
  cp -R "$t" "$d/t5"; rm "$d/t5/template/.github/workflows/"*backend*release.yml*
  cp -R "$p" "$d/p2"; sed -i.bak 's#/plinth:guide#/plinth:other#' "$d/p2/skills/arsenal/SKILL.md"
  cp -R "$p" "$d/p3"; printf 'no pointer\n' >"$d/p3/README.md"
  cp -R "$p" "$d/p4"; sed -i.bak 's/A plan in one issue | `\/implement`, typed/A plan | Ask for it; `\/to-spec`/' "$d/p4/skills/arsenal/SKILL.md"
}

# ---- de-jargon: public text carries no internal vocabulary ------------------
# The list is tests/de-jargon.txt, one extended regex per line. Korean
# translations (*.ko.md) are exempt. A planted word below is written in two
# pieces, so this file is scanned like any other.
jargon_list="$root/tests/de-jargon.txt"
# scan <file>...: prints hits, returns 1 if any.
scan() {
  # A pattern marked "@history " skips the released sections of a file named
  # CHANGELOG.md: it reads that file only up to its second "## [" heading.
  local hit=0 p out f unreleased="$work/unreleased"
  local -a files
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    files=("$@")
    if [ "${p#@history }" != "$p" ]; then
      p="${p#@history }"; files=()
      for f in "$@"; do
        if [ "$(basename "$f")" = CHANGELOG.md ]; then
          awk '/^## \[/{n++} n<2' "$f" >"$unreleased"
          out="$(grep -n -I -E -- "$p" "$unreleased" 2>/dev/null)" \
            && { printf '%s\n' "$p"; printf '  %s\n' "$out" | sed "s|^  |  $f:|"; hit=1; }
        else
          files+=("$f")
        fi
      done
      [ "${#files[@]}" -eq 0 ] && continue
    fi
    if out="$(grep -n -I -E -- "$p" "${files[@]}" 2>/dev/null)"; then
      printf '%s\n' "$p"; printf '  %s\n' "$out"; hit=1
    fi
  done < <(grep -v -E '^[[:space:]]*(#|$)' "$jargon_list")
  return $hit
}

# jargon <file>...: no listed word in the files.
k_jargon() {
  local -a files=(); local f
  for f in "$@"; do files+=("$(at "$f")"); done
  scan "${files[@]}"
}

fx_jargon() { printf 'see direction/0%s and gop%s\n' 4 pi >"$work/jargon/planted.txt"; }

# jargon_history: the history exemption covers released CHANGELOG.md sections
# only (#752): the deleted evidence repository's name and its term fail in a
# page and in [Unreleased], not in a released section, and GitLab and labels
# are not the term. Prints the two words, which this file never spells whole.
k_jargon_history() {
  local dir="$work/history" rc=0
  mkdir -p "$dir"
  printf 'the evidence is in plinth-l%sb\n' a >"$dir/page.md"
  printf '# Changelog\n\n## [Unreleased]\n\n## [1.0.0]\n\n- moved to plinth-l%sb\n' a >"$dir/CHANGELOG.md"
  scan "$dir/page.md" >/dev/null && { echo "the gate did not catch the repository's name in a page"; rc=1; }
  scan "$dir/CHANGELOG.md" >/dev/null || { echo "the gate caught the repository's name in a released CHANGELOG section"; rc=1; }
  printf '# Changelog\n\n## [Unreleased]\n\n- the l%sb holds it\n\n## [1.0.0]\n' a >"$dir/CHANGELOG.md"
  scan "$dir/CHANGELOG.md" >/dev/null && { echo "the gate did not catch the term in [Unreleased]"; rc=1; }
  printf 'a GitLab project, gitlab-ci and labels\n' >"$dir/page.md"
  scan "$dir/page.md" >/dev/null || { echo "the gate caught GitLab or labels as the term"; rc=1; }
  [ "$rc" = 0 ] && printf 'plinth-l%sb\nl%sb\n' a a
  return $rc
}

# jargon_repo: no listed word in any file git tracks or would add, but the
# list itself and the translations; prints the file count.
k_jargon_repo() {
  local -a files=(); local f
  cd "$root" || return 1
  while IFS= read -r f; do files+=("$f"); done \
    < <(git ls-files --cached --others --exclude-standard | grep -v -E '\.ko\.md$' | grep -v -E '^tests/de-jargon\.txt$')
  scan "${files[@]}" || { echo "-- fix the text or, if the word is legitimately public, edit tests/de-jargon.txt"; return 1; }
  echo "${#files[@]}"
}

# ---- The table runner --------------------------------------------------------

# fill <description> [<file>]: each {} takes the next line of the file; a {}
# with no line left reads "?".
fill() {
  local d="$1" out="" v i=0
  local -a vals=()
  if [ -n "${2:-}" ]; then while IFS= read -r v; do vals+=("$v"); done <"$2"; fi
  while :; do
    case "$d" in
      *'{}'*)
        v="?"; [ "$i" -lt "${#vals[@]}" ] && v="${vals[$i]}"; i=$((i+1))
        out="$out${d%%\{\}*}$v"; d="${d#*\{\}}" ;;
      *) break ;;
    esac
  done
  printf '%s' "$out$d"
}

built=" "; template_state=""
# prepare <arg>: makes what the argument names, once: a fixture group or the
# template checkout. Returns 1, with the reason in $prepare_error, when it cannot.
prepare() {
  local g
  case "$1" in
    TEMPLATE)
      case "$template_state" in ok) return 0 ;; failed) prepare_error="no checkout of the template: $template_error"; return 1 ;; esac
      if template_checkout "$work" && [ -f "$template_dir/copier.yml" ]; then template_state=ok; return 0; fi
      [ -n "$template_error" ] || template_error="$template_at has no copier.yml; cannot verify"
      template_state=failed; prepare_error="no checkout of the template: $template_error"; return 1 ;;
    @*)
      g="${1#@}"; g="${g%%/*}"
      case "$built" in *" $g "*) return 0 ;; esac
      built="$built$g "; mkdir -p "$work/$g"
      # Every step of the fixture, not only its last, must have worked.
      local rc; ( set -e; "fx_$g" ); rc=$?
      [ "$rc" = 0 ] || { prepare_error="the $g fixtures were not all built"; return 1; } ;;
  esac
}

# run_row <kind> <description> <args...>: one PASS or FAIL. The kind runs in a
# subshell, with nothing on its standard input.
run_row() {
  local kind="$1" desc="$2" a rc; shift 2
  for a in "$@"; do
    prepare "$a"; rc=$?   # not left of ||: the fixtures run under set -e
    [ "$rc" = 0 ] || { bad "$(fill "$desc")"; echo "        $prepare_error"; return; }
  done
  if ! declare -F "k_$kind" >/dev/null; then bad "$(fill "$desc")"; echo "        no kind \"$kind\""; return; fi
  ( "k_$kind" "$@" ) >"$work/row.out" 2>&1 </dev/null; rc=$?
  if [ "$rc" = 0 ]; then ok "$(fill "$desc" "$work/row.out")"
  else bad "$(fill "$desc")"; sed 's/^/        /' "$work/row.out"; fi
}

# run_table: reads the rows on its standard input, runs them in order, and
# returns 1 when any failed.
run_table() {
  local line rest kind desc sep=' ¦ '
  local -a fields
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    fields=(); rest="$line"
    while :; do
      case "$rest" in
        *"$sep"*) fields+=("${rest%%"$sep"*}"); rest="${rest#*"$sep"}" ;;
        *) fields+=("$rest"); break ;;
      esac
    done
    kind="${fields[0]}"; desc="${fields[1]:-}"
    if [ "$kind" = "--" ]; then echo "-- $desc"; continue; fi
    run_row "$kind" "$desc" ${fields[@]+"${fields[@]:2}"}
  done
  echo "-- $pass passed, $fail failed"
  [ "$fail" = 0 ]
}

run_table <<'TABLE'
# ---- From tests/doc-pinned-facts.sh: facts the docs state, read from the
# source (fact), then the checker on copies with one wrong line each (planted).
-- ¦ doc-pinned-facts: the docs in this checkout
fact ¦ README.md: {} plinth-template tag(s), all {} ¦ tag ¦ README.md
fact ¦ docs/tutorials/getting-started.md: {} plinth-template tag(s), all {} ¦ tag ¦ docs/tutorials/getting-started.md
fact ¦ README.md: lists the {} tools new-project.sh checks ¦ tools ¦ README.md
fact ¦ docs/tutorials/getting-started.md: lists the {} tools new-project.sh checks ¦ tools ¦ docs/tutorials/getting-started.md
fact ¦ docs/tutorials/getting-started.md: "checks all {}" matches ¦ toolcount ¦ docs/tutorials/getting-started.md
fact ¦ README.md: git {} or newer, as the door checks ¦ git ¦ README.md
fact ¦ docs/tutorials/getting-started.md: git {} or newer, as the door checks ¦ git ¦ docs/tutorials/getting-started.md
fact ¦ skill counts: {} ¦ skills
fact ¦ CONTRIBUTING.md: the squash-merge command ¦ squash ¦ CONTRIBUTING.md
fact ¦ docs/tutorials/getting-started.md: the squash-merge command ¦ squash ¦ docs/tutorials/getting-started.md
fact ¦ docs/how-to/run-a-project.md: the squash-merge command ¦ squash ¦ docs/how-to/run-a-project.md
fact ¦ docs/tutorials/getting-started.md: links the one-time update commands, repeats none ¦ onetime ¦ docs/tutorials/getting-started.md
fact ¦ docs/how-to/cut-a-release.md: links the one-time update commands, repeats none ¦ onetime ¦ docs/how-to/cut-a-release.md
fact ¦ the three questions: listed in step 5, said on all {} line(s) that name them ¦ questions
fact ¦ docs/tutorials/getting-started.md: the first login asks for {}, after saying what it can administer ¦ login
fact ¦ no login or refresh that asks for {} carries delete_repo ¦ delete
fact ¦ {} stated check count(s) read; expected {} ¦ counts
-- ¦ doc-pinned-facts: copies with one wrong line
planted ¦ a copy with a README template tag other than template_ref fails: {} ¦ README.md ¦ append ¦ Rendered from coolbress/plinth-template@v0.0.1. ¦ end
planted ¦ a copy with a tutorial template tag other than template_ref fails: {} ¦ docs/tutorials/getting-started.md ¦ append ¦ [old](https://github.com/coolbress/plinth-template/releases/tag/v0.0.1) ¦ end
planted ¦ a copy with a wrong count for an archetype without a service fails: {} ¦ docs/how-to/run-a-project.md ¦ append ¦ Wait for the required checks: eight on GitHub. ¦ end
planted ¦ a copy with "ten for a service", which the web archetype is not fails: {} ¦ GLOSSARY.md ¦ append ¦ The required checks: nine on GitHub (ten for a service). ¦ end
planted ¦ a copy with a wrong count for web fails: {} ¦ docs/reference/required-checks.md ¦ append ¦ The required checks: nine on GitHub (ten for `backend` or `data-ml`, eleven for `web`). ¦ end
planted ¦ a copy with a README tool list without python3 fails: {} ¦ README.md ¦ sed ¦ s/`uv`,$/`uv`./; /^> `python3`\.$/d ¦ grep:tools: `
planted ¦ a copy with a tutorial tool list without python3 fails: {} ¦ docs/tutorials/getting-started.md ¦ sed ¦ s/`uv`, `python3`\. The$/`uv`. The/ ¦ grep:^- Tools:
planted ¦ a copy with "checks all four" for five tools fails: {} ¦ docs/tutorials/getting-started.md ¦ sed ¦ s/checks all five/checks all four/ ¦ grep:^- Tools:
planted ¦ a copy with a git floor other than the door's fails: {} ¦ docs/tutorials/getting-started.md ¦ append ¦ Needs git 2.28 or newer. ¦ end
planted ¦ a copy with an arsenal count other than the manifest's fails: {} ¦ skills/arsenal/listed.md ¦ sed ¦ s/installs 15 of the 27 skills/installs 14 of the 27 skills/ ¦ grep:installs 14 of the
planted ¦ a copy with an upstream total other than the lists add to fails: {} ¦ skills/arsenal/listed.md ¦ sed ¦ s/installs 15 of the 27 skills/installs 15 of the 25 skills/ ¦ grep:installs 15 of the
planted ¦ a copy with a marketplace count other than its list fails: {} ¦ .claude-plugin/marketplace.json ¦ sed ¦ s/15 of the 27 upstream ships/14 of the 27 upstream ships/ ¦ line:1
planted ¦ a copy with a NOTICE count other than the manifest's fails: {} ¦ NOTICE ¦ sed ¦ s/15 skills installed, 6 listed/15 skills installed, 7 listed/ ¦ grep:7 listed in
planted ¦ a copy with "adds its seven" for six fails: {} ¦ skills/arsenal/listed.md ¦ sed ¦ s/adds its six$/adds its seven/ ¦ grep:adds its seven
planted ¦ a copy with a one-time command repeated outside the README fails: {} ¦ docs/how-to/cut-a-release.md ¦ append ¦ claude plugin update taste-skill@plinth ¦ end
planted ¦ a copy with a squash-merge command that differs fails: {} ¦ docs/how-to/run-a-project.md ¦ sed ¦ s/--squash --match-head-commit <sha> --body/--squash --body/ ¦ grep:gh pr merge <n> --squash
planted ¦ a copy with a step 5 that lists two of the three questions fails: {} ¦ docs/how-to/run-a-project.md ¦ sed ¦ /^  2\. "Can I see it?"$/d ¦ grep:^### 5\.
planted ¦ a copy with an arsenal cell that names the three questions and says two fails: {} ¦ docs/reference/arsenal-evidence.md ¦ sed ¦ s/"Can I see it?", "What did the reviewer say?" |/"Can I see it?" |/ ¦ grep:"Can I see it?" |
planted ¦ a copy with a line that names the three questions and says none fails: {} ¦ skills/guide/SKILL.md ¦ append ¦ Then ask the three questions. ¦ end
planted ¦ a copy with a first login that asks for delete_repo fails: {} ¦ docs/tutorials/getting-started.md ¦ sed ¦ 1,/gh auth login -s repo,workflow`/s/gh auth login -s repo,workflow`/gh auth login -s repo,workflow,delete_repo`/ ¦ grep:gh auth login -s repo,workflow,delete_repo
planted ¦ a copy with a refresh that asks for delete_repo with the needed scopes fails: {} ¦ skills/new-project/SKILL.md ¦ append ¦ fix: `! gh auth refresh -h github.com -s repo,workflow,delete_repo` ¦ end

# ---- From tests/readme-install-block.sh: the README install block.
-- ¦ readme-install-block
install_block ¦ README and tutorial install blocks are identical (2 commands, plinth's marketplace only)

# ---- From tests/term-table.sh: the fixed term table (#809), GLOSSARY.md's
# link to it and /plinth:guide's first-use rule.
-- ¦ term-table
refuses ¦ a table without a term fails ¦ term_table ¦ @terms/missing.md
refuses ¦ a row without an explanation fails ¦ term_table ¦ @terms/empty.md
refuses ¦ a table without the bracket rule fails ¦ term_table ¦ @terms/norule.md
refuses ¦ a missing file fails ¦ term_table ¦ @terms/absent.md
term_table ¦ a complete fixture passes ¦ @terms/good.md
term_table ¦ docs/reference/terms.md has all {} terms, each explained, and the bracket rule ¦ docs/reference/terms.md
has ¦ GLOSSARY.md links the table ¦ GLOSSARY.md ¦ (docs/reference/terms.md)
has ¦ /plinth:guide points at the table and states the first-use rule ¦ skills/guide/SKILL.md ¦ docs/reference/terms.md ¦ first time

# ---- From tests/template-rules-drift.sh: each rule plinth shares with the
# template, on fixtures, then at the pinned commit.
-- ¦ template-rules-drift
template_rules ¦ a fixture carrying every rule passes ¦ @rules/t ¦ @rules/p
refuses ¦ a plinth file missing a rule fails ({}) ¦ template_rules ¦ @rules/t ¦ @rules/p2
refuses ¦ a template that dropped a listed rule fails ({}) ¦ template_rules ¦ @rules/t2 ¦ @rules/p
template_rules_real ¦ plinth's CLAUDE.md, CONTRIBUTING.md, pull-request template and issue tracker page carry each rule shared with {} ({} listed) ¦ TEMPLATE

# ---- From tests/new-project-answer-table.sh: /plinth:new-project shows every
# answer in one table before it creates anything, and asks again only the rows
# the person picks (#1068). The skill is text an agent follows, so these read
# skills/new-project/questions.md, where its questions are written out (and
# the skill itself for what it no longer says): each row, the primary choice's
# form, the "change some" groups, what a change asks next, the text-mode line,
# and what a choice costs beside it (#1154). The door's own half (a
# description shortened to 350 characters is accepted) is a case in
# tests/new-project-failpath.sh.
-- ¦ new-project-answer-table
nonempty ¦ step 8 is the table, read up to the run ¦ step8
-- ¦ the table holds every answer, the name and the visibility among them
nonempty ¦ row 1 is "Repository and host" ¦ row:1:Repository and host
nonempty ¦ row 2 is "Kind" ¦ row:2:Kind
nonempty ¦ row 3 is "Visibility" ¦ row:3:Visibility
nonempty ¦ row 4 is "License" ¦ row:4:License
nonempty ¦ row 5 is "Third-party reviewer" ¦ row:5:Third-party reviewer
nonempty ¦ row 6 is "Code of conduct" ¦ row:6:Code of conduct
nonempty ¦ row 7 is "Description" ¦ row:7:Description
nonempty ¦ row 8 is "Records language" ¦ row:8:Records language
nonempty ¦ row 9 is "Local folder" ¦ row:9:Local folder
has ¦ the repository row says "`owner/name` on GitHub" ¦ row:1:Repository and host ¦ `owner/name` on GitHub
has ¦ the repository row says "GitLab.com" ¦ row:1:Repository and host ¦ GitLab.com
has ¦ the repository row says "`--host=github`" ¦ row:1:Repository and host ¦ `--host=github`
has ¦ the kind row says "`--archetype=`" ¦ row:2:Kind ¦ `--archetype=`
has ¦ the kind row says "where it runs" ¦ row:2:Kind ¦ where it runs
has ¦ the kind row says "`--hosting=`" ¦ row:2:Kind ¦ `--hosting=`
has ¦ the visibility row says "`--public`" ¦ row:3:Visibility ¦ `--public`
has ¦ the visibility row says "`--private`" ¦ row:3:Visibility ¦ `--private`
has ¦ the license row says "MIT for a public project, Proprietary for a private one" ¦ row:4:License ¦ MIT for a public project, Proprietary for a private one
has ¦ the reviewer row says "`--no-third-party-review`" ¦ row:5:Third-party reviewer ¦ `--no-third-party-review`
has ¦ the code-of-conduct row says "the owner's applies" ¦ row:6:Code of conduct ¦ the owner's applies
has ¦ the code-of-conduct row says "`--no-code-of-conduct`" ¦ row:6:Code of conduct ¦ `--no-code-of-conduct`
has ¦ the description row says "sentence of step 2" ¦ row:7:Description ¦ sentence of step 2
has ¦ the description row says "one line of at most 350 characters" ¦ row:7:Description ¦ one line of at most 350 characters
has ¦ the description row says "`--no-description`" ¦ row:7:Description ¦ `--no-description`
has ¦ the records-language row says "language the sentence of step 2 is written in" ¦ row:8:Records language ¦ language the sentence of step 2 is written in
has ¦ the records-language row says "named in English" ¦ row:8:Records language ¦ named in English
has ¦ the records-language row says "`--records-language=<language>`" ¦ row:8:Records language ¦ `--records-language=<language>`
has ¦ the folder row says "`--dir=" ¦ row:9:Local folder ¦ `--dir=
has ¦ the folder row says "absolute path" ¦ row:9:Local folder ¦ absolute path
order ¦ the owner's files are read before the table is shown ¦ step8 ¦ scripts/owner-files.sh ¦ | 1 | Repository and host |
has ¦ the step says "A `code_of_conduct: yes` line means the owner's applies" ¦ step8 ¦ A `code_of_conduct: yes` line means the owner's applies
has ¦ the step says "the script ignores `--code-of-conduct` then" ¦ step8 ¦ the script ignores `--code-of-conduct` then
has ¦ the step says "<name> --check <flags of the table>" ¦ step8 ¦ <name> --check <flags of the table>
has ¦ the step says "shorten it and check again" ¦ step8 ¦ shorten it and check again
match_lacks ¦ the table check gives the name once ¦ step8 ¦ new-project\.sh <name> --check[^`]* ¦ $ARGUMENTS
has ¦ the step says "the new name in place of the old" ¦ step8 ¦ the new name in place of the old
has ¦ the step says "The name is replaced the same way: one name, the new one." ¦ step8 ¦ The name is replaced the same way: one name, the new one.
-- ¦ the primary choice names the action, the visibility and owner/name
has ¦ the step says "header `Create`" ¦ step8 ¦ header `Create`
has ¦ the step says "| Create `VISIBILITY` repository `owner/name` (Recommended) |" ¦ step8 ¦ | Create `VISIBILITY` repository `owner/name` (Recommended) |
has ¦ the step says "`VISIBILITY` is `public` or `private`" ¦ step8 ¦ `VISIBILITY` is `public` or `private`
has ¦ the step says "No second "are you sure"" ¦ step8 ¦ No second "are you sure"
-- ¦ change some: one multi-select of at most four groups matching the rows
has ¦ the step says "| Change some |" ¦ step8 ¦ | Change some |
has ¦ the step says "header `Change`" ¦ step8 ¦ header `Change`
has ¦ the step says "multi-select" ¦ step8 ¦ multi-select
lines ¦ four groups, each naming its rows ¦ groups ¦ 4
has ¦ the groups says "| Name and folder | rows 1 and 9 |" ¦ groups ¦ | Name and folder | rows 1 and 9 |
has ¦ the groups says "| Records language and description | rows 7 and 8 |" ¦ groups ¦ | Records language and description | rows 7 and 8 |
has ¦ the groups says "| License | row 4 |" ¦ groups ¦ | License | row 4 |
has ¦ the groups says "| Reviewer and code of conduct | rows 5 and 6 |" ¦ groups ¦ | Reviewer and code of conduct | rows 5 and 6 |
has ¦ the step says "On GitLab.com leave out rows 5 and 6" ¦ step8 ¦ On GitLab.com leave out rows 5 and 6
has ¦ the step says "On GitLab.com leave out **Reviewer and code of conduct**" ¦ step8 ¦ On GitLab.com leave out **Reviewer and code of conduct**
lacks ¦ the step no longer says "the GitLab door sets no description yet" ¦ step8 ¦ the GitLab door sets no description yet
lacks ¦ the step no longer says "leave out **Description**" ¦ step8 ¦ leave out **Description**
-- ¦ the records language: asked in its group, hinted when public and not English
has ¦ the step says "header `Records`" ¦ step8 ¦ header `Records`
has ¦ the step says "`--records-language=English`" ¦ step8 ¦ `--records-language=English`
has ¦ the step says "When the visibility is public and the records language is not English" ¦ step8 ¦ When the visibility is public and the records language is not English
has ¦ the step says "on a public page" ¦ step8 ¦ on a public page
has ¦ the step says "Say nothing of it otherwise" ¦ step8 ¦ Say nothing of it otherwise
has ¦ the step says "named in English: write it as `Korean`, not `ko`" ¦ step8 ¦ named in English: write it as `Korean`, not `ko`
-- ¦ only the picked groups are asked; what a change moves is asked too
has ¦ the step says "Only the groups picked are asked" ¦ step8 ¦ Only the groups picked are asked
has ¦ the step says "A code of conduct turned on asks its report contact before the table returns" ¦ step8 ¦ A code of conduct turned on asks its report contact before the table returns
has ¦ the step says "An empty answer is asked again" ¦ step8 ¦ An empty answer is asked again
has ¦ the step says "typed into Other ("make it private")" ¦ step8 ¦ typed into Other ("make it private")
has ¦ the step says "A visibility changed this way asks the license again, with the new recommendation first" ¦ step8 ¦ A visibility changed this way asks the license again, with the new recommendation first
has ¦ the step says "each changed row marked" ¦ step8 ¦ each changed row marked
has ¦ the step says "show the table again" ¦ step8 ¦ show the table again
-- ¦ text mode
has ¦ the step says "Type 0 to create it as shown, or the numbers of the rows to change" ¦ step8 ¦ Type 0 to create it as shown, or the numbers of the rows to change
has ¦ the step says "Do not number `Create` and `Change some` as choices in text" ¦ step8 ¦ Do not number `Create` and `Change some` as choices in text
has ¦ the step says "only 0 creates. "Stop" ends it, with nothing created" ¦ step8 ¦ only 0 creates. "Stop" ends it, with nothing created
has ¦ the name step says "gives nothing to translate" ¦ questions ¦ gives nothing to translate
has ¦ the name step says "plain names for the kind" ¦ questions ¦ plain names for the kind
-- ¦ what a choice costs, beside the choice (#1154)
has ¦ the questions says "the whole history, the issues and the Actions logs are public too" ¦ questions ¦ the whole history, the issues and the Actions logs are public too
has ¦ the questions says "a fork made while it is public stays public if the repository is made private later" ¦ questions ¦ a fork made while it is public stays public if the repository is made private later
has ¦ the questions says "https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility" ¦ questions ¦ https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility
has ¦ the questions says "the month's total" ¦ questions ¦ the month's total
has ¦ the questions says "Claude Pro, US$20 a month (US$17 a month billed yearly" ¦ questions ¦ Claude Pro, US$20 a month (US$17 a month billed yearly
has ¦ the questions says "https://claude.com/pricing" ¦ questions ¦ https://claude.com/pricing
has ¦ the questions says "a US$7 web service and a US$6 Postgres" ¦ questions ¦ a US$7 web service and a US$6 Postgres
has ¦ the questions says "https://render.com/pricing" ¦ questions ¦ https://render.com/pricing
has ¦ the questions says "about US$33 a month in all" ¦ questions ¦ about US$33 a month in all
has ¦ the questions says "`cli`, `library` and `data-ml`: no host cost" ¦ questions ¦ `cli`, `library` and `data-ml`: no host cost
has ¦ the questions says "`backend`: no host cost until its image runs somewhere" ¦ questions ¦ `backend`: no host cost until its image runs somewhere
has ¦ the questions says "each run is 13 jobs (14 for `backend`, `data-ml` and `web`)" ¦ questions ¦ each run is 13 jobs (14 for `backend`, `data-ml` and `web`)
has ¦ the questions says "each billed as at least one minute" ¦ questions ¦ each billed as at least one minute
has ¦ the questions says "about 13 to 15 billed minutes for a small `cli` or `library` project and more for the other kinds" ¦ questions ¦ about 13 to 15 billed minutes for a small `cli` or `library` project and more for the other kinds
has ¦ the questions says "an edited title or description runs it again" ¦ questions ¦ an edited title or description runs it again
has ¦ the questions says "at 3 to 5 runs a pull request" ¦ questions ¦ at 3 to 5 runs a pull request
has ¦ the questions says "On GitHub, the whole history" ¦ questions ¦ On GitHub, the whole history
has ¦ the questions says "On GitHub, CI then runs on the plan's Actions minutes" ¦ questions ¦ On GitHub, CI then runs on the plan's Actions minutes
has ¦ the questions says "US$18 a month, about 3,000 Linux minutes at US$0.006" ¦ questions ¦ US$18 a month, about 3,000 Linux minutes at US$0.006
has ¦ the questions says "https://docs.github.com/en/billing/reference/actions-runner-pricing" ¦ questions ¦ https://docs.github.com/en/billing/reference/actions-runner-pricing
has ¦ the questions says "https://docs.github.com/en/billing/concepts/product-billing/github-actions" ¦ questions ¦ https://docs.github.com/en/billing/concepts/product-billing/github-actions
has ¦ the questions says "roughly 40 to 75 pull requests a month" ¦ questions ¦ roughly 40 to 75 pull requests a month
has ¦ the questions says "an estimate, not measured on a private repository" ¦ questions ¦ an estimate, not measured on a private repository
at_least ¦ the questions date their figures ({} "read 2026-11-26") ¦ questions ¦ read 2026-11-26 ¦ 4
lacks ¦ concepts.md no longer says 9 jobs ¦ docs/explanation/concepts.md ¦ 9 jobs
has ¦ concepts.md says "each CI run is 13 jobs (14 for backend, data-ml and web" ¦ concepts ¦ each CI run is 13 jobs (14 for backend, data-ml and web
-- ¦ every answer stays a flag, so the command said before the run asks nothing
has ¦ the step says "Every row becomes a flag, a default included" ¦ step8 ¦ Every row becomes a flag, a default included
has ¦ the step says "the description's, `--records-language=`, and on GitHub the reviewer's" ¦ step8 ¦ the description's, `--records-language=`, and on GitHub the reviewer's
has ¦ the step says "For `web`, add `--custom-user-model` without asking" ¦ step8 ¦ For `web`, add `--custom-user-model` without asking
has ¦ the step says "`--no-custom-user-model`" ¦ step8 ¦ `--no-custom-user-model`
has ¦ the step says "When the arguments give every row, show the table and ask nothing" ¦ step8 ¦ When the arguments give every row, show the table and ask nothing
has ¦ the step says "A row changed at the table replaces its flag among the arguments" ¦ step8 ¦ A row changed at the table replaces its flag among the arguments
has ¦ the step says "never both" ¦ step8 ¦ never both
lacks ¦ the skill no longer says "header `Defaults`" ¦ skill+questions ¦ header `Defaults`
lacks ¦ the skill no longer says "Use the recommended defaults?" ¦ skill+questions ¦ Use the recommended defaults?
lacks ¦ the skill no longer says "| Customize |" ¦ skill+questions ¦ | Customize |
lacks ¦ the skill no longer says "It never names the host or the visibility." ¦ skill+questions ¦ It never names the host or the visibility.

# ---- From tests/arsenal-freshness.sh: the arsenal says what ships (#833).
# Fixtures first, issue states from the stub; then the network and the
# template at the pinned commit.
-- ¦ arsenal-freshness
stale_claims ¦ a catalog that matches the template has no stale claim ¦ stub ¦ @ars/p/skills/arsenal ¦ @ars/t ¦ @ars/p
missing_facts ¦ a catalog that matches the template misses no fact ¦ @ars/p/skills/arsenal ¦ @ars/p/docs/how-to/run-a-project.md ¦ @ars/t
typed_list ¦ one typed list, with the pointers, passes ¦ @ars/p
refuses ¦ the old release row is a stale claim ¦ stale_claims ¦ stub ¦ @ars/old ¦ @ars/t ¦ @ars/p
stale_claim_names ¦ the old release row names a closed issue as the plan ¦ stub ¦ names #703 as the plan, and it is closed ¦ @ars/old ¦ @ars/t ¦ @ars/p
refuses ¦ the old release row misses what each archetype does ¦ missing_facts ¦ @ars/old ¦ @ars/p/docs/how-to/run-a-project.md ¦ @ars/t
refuses ¦ a cell planning an open-issue feature the template renders fails ¦ stale_claims ¦ stub ¦ @ars/a ¦ @ars/t ¦ @ars/p
refuses ¦ a cell naming a closed issue as the plan fails ¦ stale_claims ¦ stub ¦ @ars/b ¦ @ars/t ¦ @ars/p
refuses ¦ a cell naming an issue whose state cannot be read fails ¦ stale_claims ¦ stub ¦ @ars/c ¦ @ars/t ¦ @ars/p
refuses ¦ a cell naming another repository's closed issue as the plan fails ¦ stale_claims ¦ stub ¦ @ars/d ¦ @ars/t ¦ @ars/p
refuses ¦ the reminder called not built yet fails ¦ stale_claims ¦ stub ¦ @ars/e ¦ @ars/t ¦ @ars/p
refuses ¦ an installed skill called planned fails ¦ stale_claims ¦ stub ¦ @ars/f ¦ @ars/t ¦ @ars/p
refuses ¦ an installed skill marked listed fails ¦ stale_claims ¦ stub ¦ @ars/g ¦ @ars/t ¦ @ars/p
refuses ¦ an installed plugin in the Listed table fails ¦ stale_claims ¦ stub ¦ @ars/h ¦ @ars/t ¦ @ars/p
refuses ¦ an installed skill marked listed in listed.md fails ¦ stale_claims ¦ stub ¦ @ars/h2 ¦ @ars/t ¦ @ars/p
refuses ¦ a catalog folder with no listed.md fails ¦ stale_claims ¦ stub ¦ @ars/h3 ¦ @ars/t ¦ @ars/p
refuses ¦ a release row without one archetype fails ¦ missing_facts ¦ @ars/i ¦ @ars/p/docs/how-to/run-a-project.md ¦ @ars/t
refuses ¦ a release row with an archetype's wrong destination fails ¦ missing_facts ¦ @ars/j ¦ @ars/p/docs/how-to/run-a-project.md ¦ @ars/t
refuses ¦ a reminder row without the issue's title fails ¦ missing_facts ¦ @ars/k ¦ @ars/p/docs/how-to/run-a-project.md ¦ @ars/t
refuses ¦ a step 9 without the issue's title fails ¦ missing_facts ¦ @ars/p/skills/arsenal ¦ @ars/h9.md ¦ @ars/t
refuses ¦ a run-a-project.md without the release pointer fails ¦ missing_facts ¦ @ars/p/skills/arsenal ¦ @ars/hr.md ¦ @ars/t
refuses ¦ a template with no release workflow fails ¦ missing_facts ¦ @ars/p/skills/arsenal ¦ @ars/p/docs/how-to/run-a-project.md ¦ @ars/empty
refuses ¦ a template that dropped the reminder fails ¦ missing_facts ¦ @ars/p/skills/arsenal ¦ @ars/p/docs/how-to/run-a-project.md ¦ @ars/t2
refuses ¦ a template that dropped the release how-to fails ¦ missing_facts ¦ @ars/p/skills/arsenal ¦ @ars/p/docs/how-to/run-a-project.md ¦ @ars/t3
refuses ¦ a release workflow whose name carries no archetype fails ¦ missing_facts ¦ @ars/p/skills/arsenal ¦ @ars/p/docs/how-to/run-a-project.md ¦ @ars/t4
refuses ¦ a template that dropped one archetype's release workflow fails ¦ missing_facts ¦ @ars/p/skills/arsenal ¦ @ars/p/docs/how-to/run-a-project.md ¦ @ars/t5
refuses ¦ a user-only skill missing from the list fails ¦ typed_list ¦ @ars/p2
refuses ¦ a README without the pointer fails ¦ typed_list ¦ @ars/p3
refuses ¦ step 3's row saying ask for it fails ¦ typed_list ¦ @ars/p4
nonempty ¦ the evidence page is read with the catalog ¦ docs/reference/arsenal-evidence.md
issue_state ¦ issue state reads over the network (#703 closed) ¦ coolbress/plinth ¦ 703 ¦ closed
stale_claims ¦ no arsenal cell contradicts {} or what the plugin installs ¦ live ¦ skills/arsenal ¦ TEMPLATE ¦ .
missing_facts ¦ the release and reminder facts match {} ¦ skills/arsenal ¦ docs/how-to/run-a-project.md ¦ TEMPLATE
typed_list ¦ the person-typed skills are one list, and the other pages point at it ¦ .

# ---- From tests/de-jargon.sh: no internal vocabulary in public text.
-- ¦ de-jargon
refuses ¦ the gate catches a planted word ¦ jargon ¦ @jargon/planted.txt
jargon_history ¦ {} and the {} term fail in a page and in [Unreleased], not in a released CHANGELOG section
jargon_repo ¦ no internal vocabulary in {} files
TABLE
