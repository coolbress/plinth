#!/usr/bin/env bash
# Verdicts of tests/shell-lint.sh, tests/workflow-lint.sh and tests/python-lint.sh when a tool is
# missing, fails, or is not the pinned version. The tools are stubs on a PATH
# that holds nothing else, so a linter installed on this machine cannot turn a
# "missing" case into a pass. `bash -n` is the real one.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pin="$(sed -n 's/^actionlint_version="\(.*\)"$/\1/p' "$root/tests/workflow-lint.sh")"
[ -n "$pin" ] || { echo "  FAIL  actionlint_version= not found in tests/workflow-lint.sh"; exit 1; }
ruff_pin="$(sed -n 's/^ruff_version="\(.*\)"$/\1/p' "$root/tests/python-lint.sh")"
mypy_pin="$(sed -n 's/^mypy_version="\(.*\)"$/\1/p' "$root/tests/python-lint.sh")"
[ -n "$ruff_pin" ] && [ -n "$mypy_pin" ] || { echo "  FAIL  ruff_version= or mypy_version= not found in tests/python-lint.sh"; exit 1; }

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
stub pipx   pipx 'echo "ran-pipx $*"'
stub uvx    uvx  'echo "ran-uvx $*"'
stub uvx-bad uvx 'exit 1'

pass=0; fail=0
check() { # <script> <ci|local> <want exit> <want text> <stub dirs...>
  local script="$1" where="$2" want="$3" text="$4" path="$base" d out got; shift 4
  for d in "$@"; do path="$tmp/$d:$path"; done
  if [ "$where" = ci ]; then out="$(PATH="$path" GITHUB_ACTIONS=true "$base/bash" "$root/tests/$script" 2>&1)"; got=$?
  else out="$(/usr/bin/env -u GITHUB_ACTIONS PATH="$path" "$base/bash" "$root/tests/$script" 2>&1)"; got=$?; fi
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
check workflow-lint.sh local 1 "FAIL  actionlint not found" uvx
check workflow-lint.sh local 1 "PASS  zizmor" uvx
check workflow-lint.sh local 1 "FAIL  zizmor: neither pipx nor uvx" al-pin
check workflow-lint.sh local 1 "PASS  actionlint $pin" al-pin
check workflow-lint.sh local 1 "FAIL  actionlint $pin" al-bad uvx
check workflow-lint.sh local 1 "FAIL  zizmor" al-pin uvx-bad
echo "-- workflow-lint.sh: a version that is not the pin"
check workflow-lint.sh ci    0 "PASS  actionlint $pin" al-pin pipx
check workflow-lint.sh ci    1 "FAIL  actionlint 0.0.1 is not the pinned $pin" al-old pipx
check workflow-lint.sh ci    1 "PASS  zizmor" al-old pipx
check workflow-lint.sh local 0 "not the pinned pass" al-old pipx
echo "-- workflow-lint.sh: zizmor runs at the exact pin, pipx first"
check workflow-lint.sh local 0 "ran-pipx run zizmor==" al-pin pipx uvx
check workflow-lint.sh local 0 "ran-uvx zizmor==" al-pin uvx

echo "-- python-lint.sh: ruff and mypy at the exact pins, pipx first; one failing does not hide the other"
check python-lint.sh local 1 "FAIL  ruff, mypy: neither pipx nor uvx found"
check python-lint.sh local 0 "ran-pipx run ruff==$ruff_pin" pipx uvx
check python-lint.sh local 0 "ran-uvx mypy==$mypy_pin" uvx
check python-lint.sh local 1 "FAIL  ruff" uvx-bad
check python-lint.sh local 1 "FAIL  mypy" uvx-bad
# No Python file found is a FAIL, not a pass that checked nothing: the script,
# copied into a repository that has no scripts/*.py, with a tool that would pass.
empty="$tmp/empty"; mkdir -p "$empty/tests"; cp "$root/tests/python-lint.sh" "$empty/tests/"
git -C "$empty" init -q && git -C "$empty" add tests/python-lint.sh
out="$(PATH="$tmp/uvx:$base" "$base/bash" "$empty/tests/python-lint.sh" 2>&1)"; got=$?
if [ "$got" = 1 ] && printf '%s' "$out" | grep -qF "FAIL  no Python file under scripts/"; then
  pass=$((pass+1)); echo "  PASS  python-lint.sh   local exit 1, says: FAIL  no Python file under scripts/ (a repository without them)"
else fail=$((fail+1)); printf '  FAIL  python-lint.sh   wanted exit 1 and "no Python file", got exit %s:\n%s\n' "$got" "$out"; fi

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
