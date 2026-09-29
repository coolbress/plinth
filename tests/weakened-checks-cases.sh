#!/usr/bin/env bash
# Verdicts of the `ci / diff-size` step that names changes to the checks the
# pull request description does not (#301). The step is not copied here; it is
# extracted from python-ci.yml and run against fixture repositories, so the
# rule tested is the rule shipped.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="$root/.github/workflows/python-ci.yml"
step="Name changes to the checks the description does not"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/weakened.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# The step's `run: |` block, dedented. A missing step is a FAIL, not a pass.
python3 - "$wf" "$step" > "$tmp/step.py" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
name = sys.argv[2]
at = next((i for i, l in enumerate(lines) if l.strip() == f"- name: {name}"), None)
if at is None:
    sys.exit(f"step not found: {name}")
i = next(j for j in range(at, len(lines)) if lines[j].strip() == "run: |")
indent = None
for l in lines[i + 1:]:
    if l.strip() and indent is None:
        indent = len(l) - len(l.lstrip())
    if l.strip() and len(l) - len(l.lstrip()) < indent:
        break
    print(l[indent:] if l.strip() else "")
PY
python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))' \
  || { echo "  FAIL  needs python3 3.11 or later (tomllib), as the runner has; got $(python3 --version 2>&1)"; exit 1; }
[ -s "$tmp/step.py" ] || { echo "  FAIL  step '$step' not found in python-ci.yml"; exit 1; }
grep -q 'shell: python' <(sed -n "/- name: $step/,/run: |/p" "$wf") \
  || { echo "  FAIL  step '$step' does not run under shell: python"; exit 1; }

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        | /'; }

# A repository with a test file, a workflow, a conftest and a pyproject with a
# [tool.ruff] table, committed as the base.
new_repo() {
  r="$tmp/r$((pass+fail))"; rm -rf "$r"; mkdir -p "$r"
  git -C "$r" init -q -b main
  git -C "$r" config user.email t@example.com; git -C "$r" config user.name t
  git -C "$r" config commit.gpgsign false
  mkdir -p "$r/tests" "$r/.github/workflows" "$r/src"
  printf 'def test_a():\n    assert 1\n' > "$r/tests/test_a.py"
  printf 'def test_b():\n    assert 1\n' > "$r/tests/test_b.py"
  printf 'x = 1\n' > "$r/tests/conftest.py"
  printf 'on: push\n' > "$r/.github/workflows/ci.yml"
  printf '[project]\nname = "p"\ndependencies = ["a"]\n\n[tool.ruff]\nline-length = 88\n' > "$r/pyproject.toml"
  printf 'x = 1\n' > "$r/src/m.py"
  git -C "$r" add -A; git -C "$r" commit -qm base
  base="$(git -C "$r" rev-parse HEAD)"
}
commit() { git -C "$r" add -A; git -C "$r" commit -qm change; }

# run <body>: runs the step on base...HEAD; sets $out and $warns (::warning lines).
run() {
  out="$(cd "$r" && BASE_SHA="$base" HEAD_SHA="$(git rev-parse HEAD)" BODY="$1" \
    GITHUB_STEP_SUMMARY="$tmp/summary" python3 "$tmp/step.py" 2>&1)"; rc=$?
  warns="$(printf '%s\n' "$out" | grep '^::warning' || true)"
}
nwarn() { [ -z "$warns" ] && echo 0 || printf '%s\n' "$warns" | wc -l | tr -d ' '; }

# expect <label> <n warnings> [<substring each warning line must contain>...]
expect() {
  label="$1"; n="$2"; shift 2
  if [ "$rc" != 0 ]; then bad "$label (exit $rc; a WARN step must exit 0)" "$out"; return; fi
  if [ "$(nwarn)" != "$n" ]; then bad "$label (expected $n warnings, got $(nwarn))" "$out"; return; fi
  for s in "$@"; do
    printf '%s\n' "$warns" | grep -qF -- "$s" || { bad "$label (no warning names '$s')" "$out"; return; }
  done
  ok "$label"
}

echo "ci / diff-size: changes to the checks the description does not name"

echo "-- the four fixtures #301 asks for"
new_repo; git -C "$r" rm -q tests/test_b.py; commit
run "Refactor the parser."
expect "a deleted test, not named: WARN" 1 "tests/test_b.py" "deleted"

new_repo; printf 'on: [push, pull_request]\n' > "$r/.github/workflows/ci.yml"; commit
run "Refactor the parser."
expect "an edited workflow, not named: WARN" 1 ".github/workflows/ci.yml"

new_repo; git -C "$r" rm -q tests/test_b.py; printf 'on: [push]\n' > "$r/.github/workflows/ci.yml"; commit
run "Drops tests/test_b.py (the feature is gone) and edits .github/workflows/ci.yml to run on push."
expect "both, both named by path: no WARN" 0
printf '%s\n' "$out" | grep -q 'named in the description' && ok "  a named change is still listed in the log" \
  || bad "  a named change is not listed in the log" "$out"

new_repo; git -C "$r" rm -q tests/test_b.py; printf 'on: [push]\n' > "$r/.github/workflows/ci.yml"; commit
run "Refactor the parser."
expect "both, neither named: two WARNs" 2 "tests/test_b.py" ".github/workflows/ci.yml"

echo "-- naming"
new_repo; git -C "$r" rm -q tests/test_b.py; commit
run "Removes test_b.py: it tested the deleted module."
expect "a file name alone counts as naming it" 0

new_repo; git -C "$r" rm -q tests/test_b.py; printf 'on: [push]\n' > "$r/.github/workflows/ci.yml"; commit
run "Removes test_b.py."
expect "one named, one not: WARN on the other only" 1 ".github/workflows/ci.yml"

new_repo; git -C "$r" rm -q tests/test_b.py; commit
run ""
expect "an empty description names nothing" 1 "tests/test_b.py"

# A name counts only where it stands whole, not inside a longer one (#326).
edit_ci() { new_repo; printf 'on: [push, pull_request]\n' > "$r/.github/workflows/ci.yml"; commit; }
edit_ci; run "Bumps the pin in python-ci.yml."
expect "a longer name that contains it (python-ci.yml) does not name ci.yml: WARN" 1 ".github/workflows/ci.yml"
edit_ci; run "Edits .github/workflows/plinth-ci.yml and old-ci.yml.bak."
expect "neither a longer path nor a longer name names it: WARN" 1 ".github/workflows/ci.yml"
edit_ci; run "Edits [the caller](https://github.com/o/r/blob/main/.github/workflows/ci.yml)."
expect "a link to the file names it" 0
edit_ci; run "Also see docs/examples/ci.yml for reference."
expect "the same name under another directory does not name it: WARN" 1 ".github/workflows/ci.yml"
edit_ci; run 'Also see docs\examples\ci.yml for reference.'
expect "the same name under a Windows-style directory does not name it: WARN" 1 ".github/workflows/ci.yml"
edit_ci; run "Restores ci.yml~ and ci.yml#2 and ~ci.yml."
expect "any other character next to it makes a longer name (ci.yml~): WARN" 1 ".github/workflows/ci.yml"
edit_ci; run "Edits ci.yml to run on pull requests."
expect "the name alone names it" 0
edit_ci; run 'Edits `ci.yml` to run on pull requests.'
expect "the name in backticks names it" 0
edit_ci; run "Runs on pull requests too (ci.yml)."
expect "the name before punctuation names it" 0
edit_ci; run "The trigger moved: ci.yml."
expect "the name ending the description with a full stop names it" 0
edit_ci; run "Edits .github/workflows/ci.yml, the caller."
expect "the full path names it" 0
# Common Markdown around a name (#334): a link's line anchor, emphasis and
# strikethrough wrapping it, a typographic apostrophe after it.
edit_ci; run "Edits [the caller](.github/workflows/ci.yml#L3)."
expect "a link to the file with a line anchor names it" 0
edit_ci; run "Edits [the caller](https://github.com/o/r/blob/main/.github/workflows/ci.yml#L3-L5 \"title\")."
expect "a link with a line range and a title names it" 0
edit_ci; run "Restores ci.yml#2, not a link."
expect "a # after the name outside a link still makes a longer name: WARN" 1 ".github/workflows/ci.yml"
edit_ci; run "Edits [x](docs/ci.yml.bak#L3)."
expect "a link to a longer name with an anchor does not name it: WARN" 1 ".github/workflows/ci.yml"
for d in '_ci.yml_' '__ci.yml__' '~~ci.yml~~' '~ci.yml~' "ci.yml’s" '“ci.yml”' "‘ci.yml’"; do
  edit_ci; run "Changed $d trigger."
  expect "  $d names it" 0
done
for d in 'my_ci.yml_' '_ci.yml_x' 'ci.yml_' '_ci.yml' 'ci.yml~~' '~~ci.yml' "python-ci.yml’s"; do
  edit_ci; run "Changed $d trigger."
  expect "  $d does not name it: WARN" 1 ".github/workflows/ci.yml"
done
for d in '[ci.yml]' '*ci.yml*' '"ci.yml"' "'ci.yml'" '<ci.yml>' '{ci.yml}' 'ci.yml!' 'ci.yml?' 'ci.yml;' 'ci.yml:'; do
  edit_ci; run "Changed $d here."
  expect "  $d names it" 0
done

new_repo; printf '[pytest]\naddopts = -q\n' > "$r/pytest.ini"; commit
run "Edits .pytest.ini only."
expect "a dot-prefixed name (.pytest.ini) does not name pytest.ini: WARN" 1 "pytest.ini"

echo "-- what counts as a change to the checks"
new_repo; printf 'x = 2\n' > "$r/src/m.py"; printf 'def test_a():\n    assert 2\n' > "$r/tests/test_a.py"; commit
run "Refactor the parser."
expect "source and a kept test edited: no WARN (a weakened assertion is not seen)" 0

new_repo; printf 'def test_c():\n    assert 1\n' > "$r/tests/test_c.py"; commit
run "Adds a test."
expect "a test added: no WARN" 0

new_repo; git -C "$r" mv tests/test_b.py tests/test_bb.py; commit
run "Rename."
expect "a test renamed inside the test pattern: no WARN" 0

new_repo; git -C "$r" mv tests/test_b.py src/b_check.py; commit
run "Rename."
expect "a test moved out of the test pattern: WARN" 1 "tests/test_b.py"

new_repo; printf 'import pytest\ncollect_ignore = ["test_a.py"]\n' > "$r/tests/conftest.py"; commit
run "Refactor."
expect "conftest.py edited: WARN" 1 "tests/conftest.py"

new_repo; printf '[pytest]\naddopts = -k "not slow"\n' > "$r/pytest.ini"; commit
run "Refactor."
expect "a check configuration file added: WARN" 1 "pytest.ini"

# pytest's other configuration files (#324): an edit to one that already exists.
for f in .pytest.ini pytest.toml .pytest.toml; do
  new_repo
  case "$f" in *.ini) printf '[pytest]\naddopts = -q\n' > "$r/$f" ;; *) printf '[pytest]\naddopts = ["-q"]\n' > "$r/$f" ;; esac
  commit; base="$(git -C "$r" rev-parse HEAD)"
  case "$f" in *.ini) printf '[pytest]\naddopts = -k "not slow"\n' > "$r/$f" ;; *) printf '[pytest]\naddopts = ["-k", "not slow"]\n' > "$r/$f" ;; esac
  commit
  run "Refactor."
  expect "$f edited: WARN" 1 "$f"
done

new_repo; printf '[allowlist]\npaths = ["src"]\n' > "$r/.gitleaks.toml"; commit
run "Refactor."
expect ".gitleaks.toml added: WARN" 1 ".gitleaks.toml"

new_repo; printf '[]\n' > "$r/ruleset.json"; commit
run "Refactor."
expect "ruleset.json added: WARN" 1 "ruleset.json"

new_repo; printf '[project]\nname = "p"\ndependencies = ["a", "b"]\n\n[tool.ruff]\nline-length = 88\n' > "$r/pyproject.toml"; commit
run "Adds b."
expect "pyproject.toml, dependencies only: no WARN" 0

new_repo; printf '[project]\nname = "p"\ndependencies = ["a"]\n\n[tool.ruff]\nline-length = 200\n' > "$r/pyproject.toml"; commit
run "Refactor."
expect "pyproject.toml, a [tool.*] table changed: WARN" 1 "pyproject.toml" "[tool.*]"

new_repo; printf '[project]\nname = "p"\ndependencies = ["a"]\n\n[tool.ruff]\nline-length = 88\n\n[tool.mypy]\nignore_errors = true\n' > "$r/pyproject.toml"; commit
run "Refactor."
expect "pyproject.toml, a [tool.*] table added: WARN" 1 "pyproject.toml"

new_repo; printf '[project]\nname = "p"\ndependencies = ["a"]\n' > "$r/pyproject.toml"; commit
run "Refactor."
expect "pyproject.toml, a [tool.*] table removed: WARN" 1 "pyproject.toml"

for spelling in "['tool'.pytest.ini_options]" '["tool".pytest.ini_options]' '[ tool . pytest . ini_options ]'; do
  new_repo; printf '[project]\nname = "p"\n\n%s\naddopts = "-q"\n' "$spelling" > "$r/pyproject.toml"; git -C "$r" add -A; git -C "$r" commit -qm quoted; base="$(git -C "$r" rev-parse HEAD)"
  printf '[project]\nname = "p"\n\n%s\naddopts = "-k not slow"\n' "$spelling" > "$r/pyproject.toml"; commit
  run "Refactor."
  expect "pyproject.toml, a change under $spelling: WARN" 1 "pyproject.toml"
done

new_repo; printf 'tool.ruff.line-length = 88\n\n[project]\nname = "p"\n' > "$r/pyproject.toml"; git -C "$r" add -A; git -C "$r" commit -qm dotted; base="$(git -C "$r" rev-parse HEAD)"
printf 'tool.ruff.line-length = 200\n\n[project]\nname = "p"\n' > "$r/pyproject.toml"; commit
run "Refactor."
expect "pyproject.toml, a dotted tool. key in the root table changed: WARN" 1 "pyproject.toml"

new_repo; git -C "$r" mv pyproject.toml pyproject.disabled; commit
run "Refactor."
expect "pyproject.toml renamed away: WARN (its [tool.*] tables are gone)" 1 "pyproject.toml"

new_repo; printf '[project]\nname = "p"\n\n[tool.mypy]\nexclude = """\n[foo]\nbuild/\n"""\n' > "$r/pyproject.toml"; git -C "$r" add -A; git -C "$r" commit -qm ml; base="$(git -C "$r" rev-parse HEAD)"
printf '[project]\nname = "p"\n\n[tool.mypy]\nexclude = """\n[foo]\nsrc/\n"""\n' > "$r/pyproject.toml"; commit
run "Refactor."
expect "pyproject.toml, a multiline [tool.*] value with a [ line changed: WARN" 1 "pyproject.toml"

new_repo; printf '[project]\nname = "p"\n' > "$r/pyproject.toml"; git -C "$r" add -A; git -C "$r" commit -qm notool; base="$(git -C "$r" rev-parse HEAD)"
printf '[project]\nname = "p"\ndependencies = ["a"\n' > "$r/pyproject.toml"; commit
run "Refactor."
expect "pyproject.toml that does not parse: WARN (a change it cannot read counts)" 1 "pyproject.toml"

new_repo; printf '[project]\nname = "p"\ndependencies = ["a", "b"]\n\n[tool.ruff]\nline-length = 88\n' > "$r/pyproject.toml"; commit
out="$(cd "$r" && BASE_SHA="$base" HEAD_SHA="$(git rev-parse HEAD)" BODY="Adds b." GITHUB_STEP_SUMMARY="$tmp/summary" \
  python3 -c 'import sys; sys.modules["tomllib"] = None; exec(compile(open(sys.argv[1]).read(), sys.argv[1], "exec"))' "$tmp/step.py" 2>&1)"; rc=$?
warns="$(printf '%s\n' "$out" | grep '^::warning' || true)"
expect "no TOML parser (Python < 3.11): any pyproject.toml edit is a WARN, never a silent pass" 1 "pyproject.toml"

echo "-- the three-dot base: what main did after the branch point is not the PR's"
new_repo; git -C "$r" checkout -q -b pr; printf 'x = 3\n' > "$r/src/m.py"; commit
git -C "$r" checkout -q main; printf 'def test_c():\n    assert 1\n' > "$r/tests/test_c.py"; commit; base="$(git -C "$r" rev-parse HEAD)"
git -C "$r" checkout -q pr
run "Refactor."
expect "a test added on the base branch after the branch point: no WARN (a two-dot diff reads it as deleted)" 0

echo "-- not a pull request"
new_repo
out="$(cd "$r" && BASE_SHA="" HEAD_SHA="" BODY="" GITHUB_STEP_SUMMARY="$tmp/summary" python3 "$tmp/step.py" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q 'Not a pull request'; then ok "no base: a pass that says why"
else bad "no base: expected exit 0 and 'Not a pull request'" "$out"; fi

echo "-- a diff that cannot be computed fails, it does not pass silently"
new_repo
out="$(cd "$r" && BASE_SHA=0000000000000000000000000000000000000000 HEAD_SHA="$(git rev-parse HEAD)" BODY="" GITHUB_STEP_SUMMARY="$tmp/summary" python3 "$tmp/step.py" 2>&1)"; rc=$?
if [ "$rc" != 0 ] && printf '%s\n' "$out" | grep -q '^::error::'; then ok "unknown base: exit $rc with ::error::"
else bad "unknown base: expected a non-zero exit and ::error::" "$out"; fi

echo "-- a path cannot forge a workflow command"
new_repo; mkdir -p "$r/.github/workflows"; printf 'on: push\n' > "$r/.github/workflows/"$'x\n::error::forged.yml'; commit
run "Refactor."
if printf '%s\n' "$out" | grep -q '^::error::forged'; then bad "a newline in a path started a new workflow command" "$out"
else ok "a newline in a path stays inside its warning"; fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
