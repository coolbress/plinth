#!/usr/bin/env bash
# Verdicts of tests/shell-lint.sh, tests/workflow-lint.sh and tests/python-lint.sh when a tool is
# missing, fails, or is not the pinned version. The tools are stubs on a PATH
# that holds nothing else, so a linter installed on this machine cannot turn a
# "missing" case into a pass. `bash -n` is the real one. zizmor, ruff and mypy
# come from tests/lib/lint-tools.sh's hash-checked venv; here a stub directory
# stands in for it (PLINTH_LINT_TOOLS_BIN), and the pins are checked in the
# lock file itself.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pin="$(sed -n 's/^actionlint_version="\(.*\)"$/\1/p' "$root/tests/workflow-lint.sh")"
[ -n "$pin" ] || { echo "  FAIL  actionlint_version= not found in tests/workflow-lint.sh"; exit 1; }
lock_pin() { sed -n "s/^$1==\([^ ;]*\).*/\1/p" "$root/tests/lint-tools.txt"; }
zizmor_pin="$(lock_pin zizmor)"; ruff_pin="$(lock_pin ruff)"; mypy_pin="$(lock_pin mypy)"
[ -n "$zizmor_pin" ] && [ -n "$ruff_pin" ] && [ -n "$mypy_pin" ] || { echo "  FAIL  zizmor, ruff or mypy not pinned in tests/lint-tools.txt"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
base="$tmp/base"; mkdir -p "$base"
# git: python-lint.sh lists the files it checks with `git ls-files`.
for t in bash dirname sed head git; do ln -s "$(command -v "$t")" "$base/$t"; done

stub() { # <dir> <name> <body>
  mkdir -p "$tmp/$1"; printf '#!/bin/sh\n%s\n' "$3" > "$tmp/$1/$2"; chmod +x "$tmp/$1/$2"
}
stub sc-ok  shellcheck 'echo "version: 9.9.9"; exit 0'
stub sc-bad shellcheck 'case "$1" in --version) echo "version: 9.9.9";; *) exit 1;; esac'
stub al-pin actionlint "echo $pin"
stub al-old actionlint 'echo 0.0.1'
stub al-bad actionlint "case \"\$1\" in -version) echo $pin;; *) exit 1;; esac"
for tool in zizmor ruff mypy; do
  stub tools-ok  "$tool" "echo \"ran-$tool \$*\""
  stub tools-bad "$tool" 'exit 1'
done

pass=0; fail=0
check() { # <script> <ci|local> <want exit> <want text> <stub dirs...>; tools-ok/tools-bad stand in for the venv
  local script="$1" where="$2" want="$3" text="$4" path="$base" tools="" d out got; shift 4
  for d in "$@"; do case "$d" in tools-*) tools="$tmp/$d" ;; *) path="$tmp/$d:$path" ;; esac; done
  if [ "$where" = ci ]; then out="$(PATH="$path" GITHUB_ACTIONS=true PLINTH_LINT_TOOLS_BIN="$tools" "$base/bash" "$root/tests/$script" 2>&1)"; got=$?
  else out="$(/usr/bin/env -u GITHUB_ACTIONS PATH="$path" PLINTH_LINT_TOOLS_BIN="$tools" "$base/bash" "$root/tests/$script" 2>&1)"; got=$?; fi
  if [ "$got" = "$want" ] && printf '%s' "$out" | grep -qF -- "$text"; then
    pass=$((pass+1)); printf '  PASS  %-16s %-5s exit %s, says: %s\n' "$script" "$where" "$want" "$text"
  else
    fail=$((fail+1)); printf '  FAIL  %-16s %-5s wanted exit %s and "%s", got exit %s:\n%s\n' "$script" "$where" "$want" "$text" "$got" "$out"
  fi
}

echo "-- shell-lint.sh"
check shell-lint.sh local 0 "PASS  shellcheck 9.9.9" sc-ok
check shell-lint.sh local 1 "FAIL  shellcheck not found"
check shell-lint.sh local 1 "PASS  bash -n"                    # a missing shellcheck does not hide bash -n
check shell-lint.sh local 1 "FAIL  shellcheck 9.9.9" sc-bad
echo "-- workflow-lint.sh: a missing tool fails and does not hide the other"
check workflow-lint.sh local 1 "FAIL  actionlint not found" tools-ok
check workflow-lint.sh local 1 "PASS  zizmor $zizmor_pin" tools-ok
check workflow-lint.sh local 1 "FAIL  zizmor: python3 not found" al-pin
check workflow-lint.sh local 1 "PASS  actionlint $pin" al-pin
check workflow-lint.sh local 1 "FAIL  actionlint $pin" al-bad tools-ok
check workflow-lint.sh local 1 "FAIL  zizmor" al-pin tools-bad
echo "-- workflow-lint.sh: a version that is not the pin"
check workflow-lint.sh ci    1 "PASS  actionlint $pin" al-pin tools-ok
check workflow-lint.sh ci    1 "FAIL  actionlint 0.0.1 is not the pinned $pin" al-old tools-ok
check workflow-lint.sh ci    1 "FAIL  zizmor: PLINTH_LINT_TOOLS_BIN is set in CI" al-pin tools-ok
check python-lint.sh   ci    1 "FAIL  ruff, mypy: PLINTH_LINT_TOOLS_BIN is set in CI" tools-ok
check workflow-lint.sh local 0 "not the pinned pass" al-old tools-ok
check workflow-lint.sh local 0 "not hash-checked" al-pin tools-ok

echo "-- python-lint.sh: one failing tool does not hide the other"
check python-lint.sh local 1 "FAIL  ruff, mypy: python3 not found"
check python-lint.sh local 0 "PASS  ruff $ruff_pin" tools-ok
check python-lint.sh local 0 "PASS  mypy $mypy_pin" tools-ok
check python-lint.sh local 1 "FAIL  ruff" tools-bad
check python-lint.sh local 1 "FAIL  mypy" tools-bad
# No Python file found is a FAIL, not a pass that checked nothing: the script,
# copied into a repository that has no scripts/*.py, with tools that would pass.
empty="$tmp/empty"; mkdir -p "$empty/tests/lib"
cp "$root/tests/python-lint.sh" "$root/tests/lint-tools.txt" "$empty/tests/"; cp "$root/tests/lib/lint-tools.sh" "$empty/tests/lib/"
git -C "$empty" init -q && git -C "$empty" add tests
out="$(PATH="$base" PLINTH_LINT_TOOLS_BIN="$tmp/tools-ok" "$base/bash" "$empty/tests/python-lint.sh" 2>&1)"; got=$?
if [ "$got" = 1 ] && printf '%s' "$out" | grep -qF "FAIL  no Python file under scripts/"; then
  pass=$((pass+1)); echo "  PASS  python-lint.sh   local exit 1, says: FAIL  no Python file under scripts/ (a repository without them)"
else fail=$((fail+1)); printf '  FAIL  python-lint.sh   wanted exit 1 and "no Python file", got exit %s:\n%s\n' "$got" "$out"; fi

echo "-- tests/lint-tools.txt: every pin of lint-tools.in, every package hashed"
bad=""
while read -r req; do
  grep -qx "${req} \\\\" "$root/tests/lint-tools.txt" || grep -q "^${req} ;" "$root/tests/lint-tools.txt" || bad="$bad $req"
done < <(grep -E '^[a-z0-9_-]+==' "$root/tests/lint-tools.in")
if [ -z "$bad" ]; then pass=$((pass+1)); echo "  PASS  every pin in lint-tools.in is in lint-tools.txt at the same version"
else fail=$((fail+1)); echo "  FAIL  pinned in lint-tools.in but not in lint-tools.txt:$bad (regenerate it; the command is in lint-tools.in)"; fi
unhashed="$(awk '/^[a-z0-9_.-]+==/ {if (pkg && !h) print pkg; pkg=$1; h=0} /--hash=sha256:[0-9a-f]{64}/ {h=1} END {if (pkg && !h) print pkg}' "$root/tests/lint-tools.txt")"
if [ -z "$unhashed" ]; then pass=$((pass+1)); echo "  PASS  every package in lint-tools.txt carries a sha256 hash"
else fail=$((fail+1)); echo "  FAIL  no hash in lint-tools.txt for: $unhashed"; fi

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
