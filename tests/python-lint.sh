#!/usr/bin/env bash
# Lint and type-check the Python plinth ships into other people's CI:
# scripts/floor-check.py (python-ci.yml's floor-check job) and the pr-review
# judgement scripts (pr-review.yml). `ci / tools` runs this file; nothing else
# checks these files, since python-ci.yml's ruff and mypy run in a consumer's
# project with its configuration (#261).
#
# The rules are ruff's and mypy's defaults at the pinned versions, with no
# configuration file: these are standalone scripts, not a package, and a
# default set pinned by version changes only when the pin is raised.
# `--isolated` keeps a ruff configuration elsewhere on the machine from
# changing the set, and mypy reads no configuration file for the same reason.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ruff_version="0.16.8"
mypy_version="2.3.1"
# The Python mypy checks against, not the one that runs it, so a laptop and CI
# agree. 3.10 is the oldest mypy 2.3.1 accepts; these scripts also run on older
# python3 (a user's system one), which only compiling on it would show.
mypy_target="3.10"
cd "$root" || exit 1
fail=0

files=()
while IFS= read -r f; do files+=("$f"); done < <(git ls-files -- 'scripts/*.py')
# No file is not a pass: a moved directory would otherwise lint nothing, green.
if [ "${#files[@]}" = 0 ]; then echo "  FAIL  no Python file under scripts/ (git ls-files)"; exit 1; fi

if command -v pipx >/dev/null; then run="pipx run"
elif command -v uvx >/dev/null; then run="uvx"
else run=""; fi
if [ -z "$run" ]; then
  echo "  FAIL  ruff, mypy: neither pipx nor uvx found: install uv (https://docs.astral.sh/uv/)"; exit 1
fi

if $run "ruff==$ruff_version" check --isolated --no-cache "${files[@]}"; then
  echo "  PASS  ruff $ruff_version (${#files[@]} files, $run)"
else
  echo "  FAIL  ruff $ruff_version ($run)"; fail=1
fi

# `--cache-dir=/dev/null` writes no .mypy_cache into the checkout.
if $run "mypy==$mypy_version" --config-file '' --cache-dir=/dev/null --python-version "$mypy_target" "${files[@]}"; then
  echo "  PASS  mypy $mypy_version (${#files[@]} files, Python $mypy_target, $run)"
else
  echo "  FAIL  mypy $mypy_version ($run)"; fail=1
fi
exit "$fail"
