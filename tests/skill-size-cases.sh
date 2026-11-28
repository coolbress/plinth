#!/usr/bin/env bash
# tests/skill-size.sh against fixture plugin roots: AGENTS.md over either of
# its caps fails, at both caps passes, and a root with no AGENTS.md or a caps
# file missing a cap fails rather than checking nothing. The caps are read
# from the fixture's own tests/size_caps.py, a copy of this repository's.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/skill-size.XXXXXX")" || { echo "  FAIL  mktemp"; exit 1; }
trap 'rm -rf "$tmp"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        | /'; }

# A root with one small skill, the real caps, and an AGENTS.md of $1 lines
# padded to $2 bytes ("" for no AGENTS.md).
fixture() {
  local d="$tmp/$3"
  mkdir -p "$d/tests"
  # one small skill (skill-size.sh lists no exception today; one it listed
  # would have to exist here too)
  mkdir -p "$d/skills/one"
  printf -- '---\nname: one\ndescription: x\n---\nbody\n' > "$d/skills/one/SKILL.md"
  cp "$root/tests/size_caps.py" "$d/tests/size_caps.py"
  printf 'READS_ONE_MAX_BYTES = 30000\nDESCRIPTION_ONE_MAX_BYTES = 100\n' >> "$d/tests/size_caps.py"
  if [ -n "$1" ]; then
    python3 - "$d/AGENTS.md" "$1" "$2" <<'PY'
import sys
path, lines, size = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
body = "x\n" * (lines - 1)
last = "y" * (size - len(body) - 1) + "\n"
open(path, "w").write(body + last)
PY
  fi
  printf '%s\n' "$d"
}

# expect <pass|fail> <name> <root> [text the output must carry]
expect() {
  local out s
  out="$("$root/tests/skill-size.sh" "$3" 2>&1)"; s=$?
  if [ "$1" = pass ] && [ "$s" != 0 ]; then bad "$2: expected a pass, exit $s" "$out"; return; fi
  if [ "$1" = fail ] && [ "$s" = 0 ]; then bad "$2: expected a failure, exit 0" "$out"; return; fi
  if [ -n "${4:-}" ] && ! grep -qF -- "$4" <<<"$out"; then bad "$2: output lacks '$4'" "$out"; return; fi
  ok "$2"
}

expect pass "AGENTS.md at both caps (110 lines, 7,500 bytes)" "$(fixture 110 7500 at-caps)" "AGENTS.md: 110 lines, 7500 bytes"
expect fail "AGENTS.md one line over (111)" "$(fixture 111 7000 lines-over)" "AGENTS.md: 111 lines and 7000 bytes"
expect fail "AGENTS.md one byte over (7,501)" "$(fixture 100 7501 bytes-over)" "AGENTS.md: 100 lines and 7501 bytes"
expect fail "no AGENTS.md: nothing to hold" "$(fixture "" "" no-agents)" "no AGENTS.md"

d="$(fixture 50 2000 cap-missing)"
grep -v '^AGENTS_MAX_BYTES' "$d/tests/size_caps.py" > "$d/caps" && mv "$d/caps" "$d/tests/size_caps.py"
expect fail "a cap missing from tests/size_caps.py: not read as no limit" "$d" "AGENTS_MAX_BYTES"

# A raise by an added line loses no line, so ci / diff-size would not list it.
d="$(fixture 120 2000 cap-twice)"
{ echo 'AGENTS_MAX_LINES = 140'; cat "$root/tests/size_caps.py"; } > "$d/tests/size_caps.py"
expect fail "a cap set twice (a raise by an added line): not read" "$d" "AGENTS_MAX_LINES"

d="$(fixture 50 2000 skill-over)"
python3 -c 'import sys; open(sys.argv[1], "w").write("---\nname: one\n---\n" + "x\n" * 501)' "$d/skills/one/SKILL.md"
expect fail "a skill over 500 lines still fails (the skill caps as they were)" "$d" "the limits are 500 lines and 20000 bytes"

# The arsenal's own caps (#1086): 12,000 bytes passes, one byte more fails,
# and so does a 251st line; another skill of that size still passes.
arsenal_of() { # <dir> <lines> <bytes>: skills/arsenal/SKILL.md of that size
  mkdir -p "$1/skills/arsenal"
  python3 -c 'import sys
path, lines, size = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
body = "---\nname: arsenal\ndescription: x\n---\n" + "x\n" * (lines - 5)
open(path, "w").write(body + "y" * (size - len(body) - 1) + "\n")' "$1/skills/arsenal/SKILL.md" "$2" "$3"
}
d="$(fixture 50 2000 arsenal-at)"; arsenal_of "$d" 250 12000
expect pass "the arsenal at its caps (250 lines, 12,000 bytes)" "$d" "skills/arsenal/SKILL.md: 250 lines, 12000 bytes"
d="$(fixture 50 2000 arsenal-bytes)"; arsenal_of "$d" 100 12001
expect fail "the arsenal one byte over (12,001)" "$d" "the limits are 250 lines and 12000 bytes"
d="$(fixture 50 2000 arsenal-lines)"; arsenal_of "$d" 251 9000
expect fail "the arsenal one line over (251)" "$d" "the limits are 250 lines and 12000 bytes"
d="$(fixture 50 2000 other-size)"
python3 -c 'import sys; open(sys.argv[1], "w").write("---\nname: one\ndescription: x\n---\n" + "x\n" * 299 + "y" * 15000 + "\n")' "$d/skills/one/SKILL.md"
expect pass "another skill of 300 lines and 15,000 bytes: the arsenal's caps are its own" "$d" "skills/one/SKILL.md: 304 lines"

# What one invocation reads (#1181): SKILL.md and the files its body says to
# read before acting, against READS_ONE_MAX_BYTES (30,000 here).
pad() { python3 -c 'import sys; open(sys.argv[1], "w").write("y" * int(sys.argv[2]) + "\n")' "$1" "$2"; }
d="$(fixture 50 2000 reads-over)"
printf -- '---\nname: one\ndescription: x\n---\nThe steps are in `${CLAUDE_PLUGIN_ROOT}/skills/one/steps.md`: read it before the first step.\n' > "$d/skills/one/SKILL.md"
pad "$d/skills/one/steps.md" 30000
expect fail "a file read before acting counts: SKILL.md and steps.md over the cap" "$d" "one reads"
pad "$d/skills/one/steps.md" 20000
expect pass "  and under it, named in the line" "$d" "(SKILL.md + steps.md), the cap 30000"
d="$(fixture 50 2000 reads-optional)"
printf -- '---\nname: one\ndescription: x\n---\nWhy each item says what it says is in [reference.md](reference.md); read it only when asked.\n\nThe [notes](notes.md) are for maintainers.\n' > "$d/skills/one/SKILL.md"
pad "$d/skills/one/reference.md" 40000; pad "$d/skills/one/notes.md" 40000
expect pass "a file to read only when asked, or only named, is not counted" "$d" "named, not read before acting: skills/one/reference.md skills/one/notes.md"
d="$(fixture 50 2000 reads-numbers)"
printf -- '---\nname: one\ndescription: x\n---\nThe steps are in [steps.md](steps.md): read it before the first step.\n' > "$d/skills/one/SKILL.md"
printf '1. [The host](#1-the-host)\n\n## 1. The host\n\nAs #812 decided.\n' > "$d/skills/one/steps.md"
expect fail "a file read before acting carries no issue number" "$d" "skills/one/steps.md, read with one: 1 lines carry an issue number"
printf '1. [The host](#1-the-host)\n\n## 1. The host\n' > "$d/skills/one/steps.md"
expect pass "  and a link to a heading that starts with a digit is not one" "$d" "skills/one/steps.md, read with one: no issue numbers"
d="$(fixture 50 2000 desc-over)"
printf -- '---\nname: one\ndescription: %s\n---\nbody\n' "$(printf 'w%.0s' $(seq 1 101))" > "$d/skills/one/SKILL.md"
expect fail "a description over its cap (101 bytes, the cap 100)" "$d" "one: description 101 bytes; the cap is 100"
# The review of #1181: other words for reading first, a list under "only
# when", a description as a block scalar, and none.
d="$(fixture 50 2000 reads-words)"
printf -- '---\nname: one\ndescription: x\n---\nRead `${CLAUDE_PLUGIN_ROOT}/skills/one/steps.md` before the first step.\n\nThe rules are in [rules.md](rules.md). Read it first.\n' > "$d/skills/one/SKILL.md"
pad "$d/skills/one/steps.md" 100; pad "$d/skills/one/rules.md" 100
expect pass "\"Read <file> before\" and \"Read it first\" count too" "$d" "(SKILL.md + steps.md + rules.md)"
d="$(fixture 50 2000 reads-lead-in)"
printf -- '---\nname: one\ndescription: x\n---\nEach file below answers one question; read it only when asked.\n\n- [extra.md](extra.md): read it before suggesting a command.\n' > "$d/skills/one/SKILL.md"
pad "$d/skills/one/extra.md" 40000
printf -- '---\nname: one\ndescription: x\n---\nThe person can read [extra.md](extra.md) first.\n' > "$d/skills/one/SKILL.md"
expect pass "\"the person can read <file> first\" is the person's, not counted" "$d" "named, not read before acting: skills/one/extra.md"
printf -- '---\nname: one\ndescription: x\n---\nEach file below answers one question; read it only when asked.\n\n- [extra.md](extra.md): read it before suggesting a command.\n' > "$d/skills/one/SKILL.md"
expect pass "a list item under a lead-in that says only when is not counted" "$d" "named, not read before acting: skills/one/extra.md"
d="$(fixture 50 2000 desc-block)"
printf -- '---\nname: one\ndescription: >-\n  %s\n  %s\n---\nbody\n' "$(printf 'w%.0s' $(seq 1 60))" "$(printf 'w%.0s' $(seq 1 60))" > "$d/skills/one/SKILL.md"
expect fail "a description as a block scalar is its text (121 bytes over 100)" "$d" "one: description 121 bytes; the cap is 100"
# The review of this change: a blank line between the block's paragraphs.
d="$(fixture 50 2000 desc-block-blank)"
printf -- '---\nname: one\ndescription: >-\n  Short paragraph.\n\n  %s\n---\nbody\n' "$(printf 'w%.0s' $(seq 1 200))" > "$d/skills/one/SKILL.md"
expect fail "a block description with a blank line between paragraphs counts both (217 bytes over 100)" "$d" "one: description 217 bytes; the cap is 100"
d="$(fixture 50 2000 desc-none)"
printf -- '---\nname: one\n---\nbody\n' > "$d/skills/one/SKILL.md"
expect fail "no description: not passed as 0 bytes" "$d" "one: no description in its frontmatter"
d="$(fixture 50 2000 reads-cap-missing)"
grep -v '^READS_ONE_MAX_BYTES' "$d/tests/size_caps.py" > "$d/caps" && mv "$d/caps" "$d/tests/size_caps.py"
expect fail "a skill with no reads cap: not read as no limit" "$d" "READS_ONE_MAX_BYTES"

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
