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
body = "---\nname: arsenal\n---\n" + "x\n" * (lines - 4)
open(path, "w").write(body + "y" * (size - len(body) - 1) + "\n")' "$1/skills/arsenal/SKILL.md" "$2" "$3"
}
d="$(fixture 50 2000 arsenal-at)"; arsenal_of "$d" 250 12000
expect pass "the arsenal at its caps (250 lines, 12,000 bytes)" "$d" "skills/arsenal/SKILL.md: 250 lines, 12000 bytes"
d="$(fixture 50 2000 arsenal-bytes)"; arsenal_of "$d" 100 12001
expect fail "the arsenal one byte over (12,001)" "$d" "the limits are 250 lines and 12000 bytes"
d="$(fixture 50 2000 arsenal-lines)"; arsenal_of "$d" 251 9000
expect fail "the arsenal one line over (251)" "$d" "the limits are 250 lines and 12000 bytes"
d="$(fixture 50 2000 other-size)"
python3 -c 'import sys; open(sys.argv[1], "w").write("---\nname: one\n---\n" + "x\n" * 300 + "y" * 15000 + "\n")' "$d/skills/one/SKILL.md"
expect pass "another skill of 300 lines and 15,000 bytes: the arsenal's caps are its own" "$d" "skills/one/SKILL.md: 304 lines"

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
