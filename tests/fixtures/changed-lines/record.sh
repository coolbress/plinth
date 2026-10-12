#!/usr/bin/env bash
# Records coverage.xml and diff-cover JSON for each changed-lines case (#503),
# from real runs of coverage 7.10.7 and diff-cover 9.7.1 against a merge
# commit's first parent, as ci / test runs them.
# Usage: record.sh <work dir> <canary dir> <fixtures dir>
set -euo pipefail
W="$1"; canary="$2"; dest="$3"
mkdir -p "$W" "$dest"
cov() { uv run --locked -q --with 'coverage[toml]==7.10.7' coverage "$@"; }

# case_ <name> <source> <pre-base command> <feature command>
case_() {
  name="$1"; src="$2"; pre="$3"; feat="$4"
  r="$W/$name"; mkdir -p "$r"; cd "$r"
  git init -q -b main; git config user.email t@e; git config user.name t; git config commit.gpgsign false
  cp -R "$canary" sub; rm -rf sub/.venv sub/.pytest_cache; "$pre"
  git add -A; git commit -qm base; git checkout -qb feat
  "$feat"
  git add -A; git commit -qm feat; git checkout -q main; echo "# x" >> sub/README.md; git commit -qam other
  git merge -q --no-ff feat -m merge
  cd sub; uv sync --locked -q
  cov run --branch --source="$src" -m pytest -q -p no:cacheprovider >/dev/null
  cov xml -q -o "$dest/$name.xml"
  # Machine-specific values made fixed; with --source=. coverage measures the
  # project's .venv too: those packages are dropped, the root's counts kept.
  python3 - "$dest/$name.xml" <<'X'
import re, sys
p = sys.argv[1]; t = open(p).read()
t = re.sub(r'timestamp="[0-9]+"', 'timestamp="0"', t)
t = re.sub(r"<source>[^<]*/sub", "<source>/home/runner/work/p/p/sub", t)
t = re.sub(r'\s*<package name="\.venv[^"]*".*?</package>', "", t, flags=re.S)
open(p, "w").write(t)
X
  uvx -q diff-cover@9.7.1 "$dest/$name.xml" --compare-branch=HEAD^1 --format "json:$dest/$name.json" >/dev/null 2>&1 || true
}

nop() { :; }
pkg=sub/src/canary
# flat layout: the package at the project root.
flatten() {
  mv sub/src/canary sub/canary; rmdir sub/src; pkg=sub/canary
  python3 - sub/pyproject.toml <<'X'
import sys
p = sys.argv[1]; t = open(p).read()
t = t.replace('src = ["src", "tests"]', 'src = [".", "tests"]').replace('files = ["src", "tests"]', 'files = ["canary", "tests"]')
open(p, "w").write(t)
X
}
untested='\n\ndef untested(x: int) -> int:\n    if x > 1:\n        return x * 2\n    return x\n'
# none ran: a new module nothing imports, and a new test file that runs.
none() {
  printf 'def extra(x: int) -> int:\n    if x > 1:\n        return x * 2\n    return x\n' > "$pkg/extra.py"
  printf 'from canary import alive\n\n\ndef test_more() -> None:\n    assert alive()\n' > sub/tests/test_more.py
}
# some ran: a function added to an imported module; its def line runs at import.
some() { printf '%b' "$untested" >> "$pkg/__init__.py"; }
# all ran: the same function and a test that calls it on both branches.
all_() {
  some
  printf 'from canary import untested\n\n\ndef test_untested() -> None:\n    assert untested(2) == 4\n    assert untested(1) == 1\n' > sub/tests/test_more.py
}
# no executable line: a comment.
noexec() { printf '# a comment\n' >> "$pkg/__init__.py"; }
# nothing collected: a test that imports nothing; the source never runs.
nothing() { some; printf 'def test_nothing() -> None:\n    assert True\n' > sub/tests/test_canary.py; }

case_ none src nop none
case_ some src nop some
case_ all src nop all_
case_ noexec src nop noexec
case_ nothing src nop nothing
case_ flat . flatten none
ls -la "$dest"
