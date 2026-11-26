#!/usr/bin/env bash
# A failed `mktemp -d` stops a script before it does anything, and its cleanup
# never removes a folder it did not make (#1123). `cd ""` succeeds and stays in
# the current folder, so a work folder set by a `cd` into mktemp's output,
# with a failing mktemp, was the current folder, and the EXIT trap removed it.
#
# 1. Static, over tests/, scripts/ and their lib/: no `cd` into a mktemp's
#    output on one line, and every assignment from `$(mktemp -d ...)` is
#    followed by its own `||` (only `&& x="$(...)"` or `&& [ ... ]` between),
#    on its line or the next. Must-not-pass fixtures first.
# 2. The scripts that had the pattern, run from a copy of tests/ and scripts/
#    with a `mktemp` on PATH that always fails: each exits non-zero and the
#    folder it was started in is unchanged.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)" || { echo "mktemp-failure-cases: could not make a temp folder" >&2; exit 1; }
scratch="$(cd "$scratch" && pwd -P)" || { echo "mktemp-failure-cases: could not read the temp folder" >&2; exit 1; }
trap 'rm -rf "$scratch"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

# check <dir>...: one line per offending line; returns 1 if any. The pattern
# is built in pieces so this file does not match itself.
cd_mktemp='cd "$('"mktemp -d"
check() {
  local rc=0 hits
  hits="$(grep -rnF --include='*.sh' -- "$cd_mktemp" "$@" 2>/dev/null)"
  [ -z "$hits" ] || { printf 'cd into a mktemp: %s\n' "$hits"; rc=1; }
  hits="$(python3 -I - "$@" 2>&1 <<'PY'
import pathlib, re, sys
assign = re.compile(r'^\s*[A-Za-z_][A-Za-z0-9_]*="\$\((?:[A-Za-z_][A-Za-z0-9_]*="\$\()?mktemp -d')
name_open = re.compile(r'\s*[A-Za-z_][A-Za-z0-9_]*="(?=\$\()')
test_cmd = re.compile(r'\s*\[ [^;&|\]]* \]')

def close(s, i):
    """s[i:] starts with "$(": the index after its matching ")", or -1."""
    depth, j = 0, i + 1
    while j < len(s):
        c = s[j]
        if c == "\\":
            j += 1
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1
    return -1

def guarded(line, nxt):
    """The `||` follows this assignment itself: only `&& name="$(...)"` or
    `&& [ ... ]` may come between, on this line or a `\\`-continued next one."""
    m = name_open.match(line)
    j = close(line, m.end())
    if j < 0 or line[j:j + 1] != '"':
        return False
    rest = line[j + 1:].rstrip()
    if rest.endswith("\\"):
        rest = rest[:-1] + " " + nxt
    while True:
        rest = rest.lstrip()
        if rest.startswith("||"):
            return True
        if not rest.startswith("&&"):
            return False
        rest = rest[2:]
        m = name_open.match(rest)
        if m:
            j = close(rest, m.end())
            if j < 0 or rest[j:j + 1] != '"':
                return False
            rest = rest[j + 1:]
            continue
        m = test_cmd.match(rest)
        if not m:
            return False
        rest = rest[m.end():]

for top in sys.argv[1:]:
    for f in sorted(pathlib.Path(top).rglob("*.sh")):
        lines = f.read_text(encoding="utf-8").splitlines()
        for i, line in enumerate(lines):
            if not assign.match(line):
                continue
            nxt = lines[i + 1].lstrip() if i + 1 < len(lines) else ""
            if not guarded(line, nxt):
                print(f"{f}:{i + 1}: {line.strip()}")
PY
)" || { printf 'the scan did not finish: %s\n' "$hits"; return 1; }
  [ -z "$hits" ] || { printf 'unguarded mktemp -d: %s\n' "$hits"; rc=1; }
  return $rc
}

mkdir -p "$scratch/fx/a" "$scratch/fx/b" "$scratch/fx/c"
printf 'work="$(%s)" && pwd -P)"\n' "$cd_mktemp" >"$scratch/fx/a/t.sh"
printf 'work="$(mktemp -d)"; trap '"'"'rm -rf "$work"'"'"' EXIT\nw2="$(mktemp -d)"; true || true\n' >"$scratch/fx/b/t.sh"
printf 'work="$(mktemp -d)" || exit 1\nd="$(mktemp -d)" \\\n  || exit 1\n' >"$scratch/fx/c/t.sh"
printf 'w="$(mktemp -d)" \x26\x26 w="$(cd "$w" \x26\x26 pwd -P)" || exit 1\nv="$(mktemp -d)" \x26\x26 v="$(cd "$v" \x26\x26 pwd -P)" \x26\x26 [ -n "$v" ] \\\n  || exit 1\nt="$(p="$(mktemp -d)" \x26\x26 dirname "$p")" || exit 1\n' >>"$scratch/fx/c/t.sh"
mkdir -p "$scratch/fx/e"
printf 'work="$(mktemp -d)"; other="$(true)" || true\nw2="$(mktemp -d)" \x26\x26 rm -rf "$w2" || true\nw3="$(mktemp -d)" \\\n  ; other="$(true)" || true\n' >"$scratch/fx/e/t.sh"
if out="$(check "$scratch/fx/a")"; then bad "a cd into a mktemp passes"; else ok "a cd into a mktemp fails ($out)"; fi
if out="$(check "$scratch/fx/b")"; then bad "an unguarded mktemp -d passes"
elif [ "$(grep -c 't.sh:[12]:' <<<"$out")" = 2 ]; then ok "an unguarded mktemp -d fails, one with a later || too ($out)"
else bad "an unguarded mktemp -d is not named on both lines: $out"; fi
mkdir -p "$scratch/fx/d"; printf 'x\n' >"$scratch/fx/d/ok.sh"; printf '\377\376 work="$(mktemp -d)" || exit 1\n' >"$scratch/fx/d/z.sh"
if out="$(check "$scratch/fx/d")"; then bad "a scan that could not read a file passes"; else ok "a scan that could not read a file fails"; fi
if out="$(check "$scratch/fx/e")"; then bad "a guard on a later command passes"
elif [ "$(grep -c 't.sh:[1-3]:' <<<"$out")" = 3 ]; then ok "a guard on a later command, not the mktemp assignment, fails ($out)"
else bad "a guard on a later command is not named on all three lines: $out"; fi
if out="$(check "$scratch/fx/c")"; then ok "a guarded mktemp -d passes, on its line or the next"; else bad "a guarded mktemp -d fails: $out"; fi

if out="$(check "$root/tests" "$root/scripts")"; then ok "tests/ and scripts/: no cd into a mktemp, every mktemp -d guarded"
else bad "tests/ and scripts/:"; sed 's/^/        /' <<<"$out"; fi

# The scripts run with mktemp failing, each from its own copy and folder.
mkdir -p "$scratch/bin"
printf '#!/bin/sh\necho "mktemp: refused (test stub)" >&2\nexit 1\n' >"$scratch/bin/mktemp"
chmod +x "$scratch/bin/mktemp"
for t in guide-cases off-by-default-cases e2e-upgrade-driver template-update-cases; do
  copy="$scratch/copy-$t"; here="$scratch/here-$t"
  mkdir -p "$copy" "$here"
  cp -R "$root/tests" "$root/scripts" "$copy/"
  echo keep >"$here/sentinel"
  before="$(ls -A "$here")"
  ( cd "$here" && PATH="$scratch/bin:$PATH" bash "$copy/tests/$t.sh" ) >"$scratch/out-$t" 2>&1; rc=$?
  after="$(ls -A "$here" 2>/dev/null)"
  if [ "$rc" != 0 ] && [ -d "$here" ] && [ "$after" = "$before" ] && [ -s "$here/sentinel" ] \
     && grep -q 'could not make a temp folder' "$scratch/out-$t"; then
    ok "$t: stops at mktemp (exit $rc), the folder it ran in unchanged"
  else
    bad "$t: exit $rc, folder $([ -d "$here" ] && echo "now holds: ${after:-nothing}" || echo removed)"
    tail -3 "$scratch/out-$t" | sed 's/^/        /'
  fi
done

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
