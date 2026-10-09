#!/usr/bin/env bash
# Verdicts of the `ci / diff-size` step that names changes to the checks the
# pull request description does not (#301), the verdict lines python-ci's
# jobs open their summaries with (#437), and the zizmor step's split (#450).
# The steps are not copied here; they are extracted from python-ci.yml and
# run against fixtures, so the rule tested is the rule shipped.
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
edit_ci; run "$(printf 'Edits [the caller][c].\n\n[c]: .github/workflows/ci.yml#L3')"
expect "a reference-style link definition with a line anchor names it" 0
edit_ci; run "$(printf 'Edits [the caller][c].\n\n  [c]: <.github/workflows/ci.yml#L3> "title"')"
expect "an indented, bracketed definition with a title names it" 0
edit_ci; run "See <https://github.com/o/r/blob/main/.github/workflows/ci.yml#L3>."
expect "an autolink with a line anchor names it" 0
edit_ci; run "$(printf 'Edits [x][c].\n\n[c]: docs/ci.yml.bak#L3')"
expect "a definition pointing at a longer name does not name it: WARN" 1 ".github/workflows/ci.yml"
edit_ci; run "Restores <ci.yml#2>, not a link."
expect "angle brackets with no scheme are not an autolink: WARN" 1 ".github/workflows/ci.yml"
edit_ci; run "Restores <.github/workflows/ci.yml#L3>, not a link."
expect "  nor with a path and no scheme: WARN" 1 ".github/workflows/ci.yml"
edit_ci; run "Restores <ci.yml#2 and ci.yml#3>, not links."
expect "a # inside angle brackets that are not one target still makes a longer name: WARN" 1 ".github/workflows/ci.yml"
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
new_repo; printf 'x = 2\n' > "$r/src/m.py"; commit
run "Refactor the parser."
expect "source edited only: no WARN" 0

echo "-- a kept test file that lost lines (#434)"
# coolbress/plinth-reach#8's shape: the assertion replaced by a stubbed
# lookup, one line out and lines in, the file kept.
eight() { new_repo; printf 'def test_a(monkeypatch):\n    monkeypatch.setattr("m.lookup", lambda: "1")\n    assert version() == "1"\n' > "$r/tests/test_a.py"; commit; }
eight; run "Refactor the parser."
expect "#8's shape (a kept test file, lines removed and added), not named: WARN" 1 "tests/test_a.py" "a test file lost lines"
eight; run "Rewrites tests/test_a.py to stub the lookup: the version comes from the stub."
expect "#8's shape, named: no WARN" 0
printf '%s\n' "$out" | grep -q '^named in the description: tests/test_a.py: a test file lost lines$' && ok "  and it is listed as named" \
  || bad "  a named rewrite is not listed in the log" "$out"

new_repo; printf 'def test_a():\n    assert 1\n\ndef test_a2():\n    assert 1\n' > "$r/tests/test_a.py"; commit
run "Adds a test."
expect "a kept test file that only gains lines: no WARN" 0
printf '%s\n' "$out" | grep -q '^0 change(s) to the checks' && ok "  and it is not listed" || bad "  a test file that only gained lines is listed" "$out"

new_repo; printf 'set -e\necho a\n' > "$r/tests/run.sh"; git -C "$r" add -A; git -C "$r" commit -qm sh; base="$(git -C "$r" rev-parse HEAD)"
printf 'echo b\n' > "$r/tests/run.sh"; commit
run "Refactor."
expect "a shell file under tests/ that lost lines: no WARN (.py only)" 0

new_repo; git -C "$r" mv tests/test_b.py tests/test_bb.py; printf 'def test_b():\n    pass\n' > "$r/tests/test_bb.py"; commit
run "Rename."
expect "a test renamed inside the test paths and rewritten: WARN on the new path" 1 "tests/test_b.py -> tests/test_bb.py" "a test file lost lines"

new_repo; printf 'x = 1\ny = 2\nz = 3\nw = 4\n' > "$r/src/m.py"; git -C "$r" add -A; git -C "$r" commit -qm four; base="$(git -C "$r" rev-parse HEAD)"
git -C "$r" mv src/m.py tests/test_m.py; printf 'x = 1\ny = 2\nz = 3\n' > "$r/tests/test_m.py"; commit
run "Moves it."
expect "a source file moved into the test paths and cut: no WARN (not a kept test file)" 0
new_repo; printf 'import pytest\ncollect_ignore = ["test_a.py"]\n' > "$r/tests/conftest.py"; commit
run "Refactor."
expect "conftest.py edited with a line removed: one WARN carrying both reasons" 1 "tests/conftest.py" "check configuration changed; a test file lost lines"

echo "-- a skip or a suppression added (#434)"
markers=('@pytest.mark.skip' '@pytest.mark.skipif(True, reason="x")' '@pytest.mark.xfail' 'pytest.skip("x")' 'x = 1  # noqa: E501' 'x = 1  # type: ignore[assignment]' 'x = 1  # pragma: no cover')
for m in "${markers[@]}"; do
  new_repo; printf '%s\n' "$m" >> "$r/src/m.py"; commit
  run "Refactor."
  expect "added: $m: WARN" 1 "src/m.py" "a skip or a suppression added"
done
for m in "${markers[@]}"; do
  new_repo; printf 'x = 1\n%s\n' "$m" > "$r/src/m.py"; git -C "$r" add -A; git -C "$r" commit -qm with; base="$(git -C "$r" rev-parse HEAD)"
  printf 'x = 1\n%s\ny = 2\n' "$m" > "$r/src/m.py"; commit
  run "Refactor."
  expect "  unchanged: $m: no WARN" 0
  printf 'x = 1\ny = 2\n' > "$r/src/m.py"; commit
  run "Refactor."
  expect "  removed: $m: no WARN" 0
done
new_repo; printf '@pytest.mark.skip\ndef test_c():\n    assert 1\n' > "$r/tests/test_c.py"; commit
run "Adds test_c.py."
expect "a new test file with a skip, the file named: no WARN" 0
new_repo; printf '# noqa\n' > "$r/src/notes.txt"; commit
run "Refactor."
expect "a marker in a file that is not Python: no WARN" 0
new_repo; printf 'x = 1  # NOQA\ny = 2  #type:ignore\npytest.skip ("x")\npytest . mark . xfail\n' >> "$r/src/m.py"; commit
run "Refactor."
expect "markers in other cases and spacing still count, one row per file" 1 "src/m.py" "pytest.skip (" "mark . xfail"

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

# The verdict lines each python-ci job opens its summary with (#437), run
# from the steps themselves: extracted by job and step name, run as the
# runner runs a `run:` block (bash -e), with the step's env given here.
job_step() { # <job> <step name> -- prints the step's run block, dedented
  python3 - "$wf" "$1" "$2" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
job, name = sys.argv[2], sys.argv[3]
j = next((i for i, l in enumerate(lines) if l == f"  {job}:"), None)
end = next((i for i in range(j + 1, len(lines)) if lines[i][:3].strip() and lines[i].startswith("  ") and not lines[i].startswith("   ")), len(lines)) if j is not None else 0
at = next((i for i in range(j or 0, end) if lines[i].strip() == f"- name: {name}"), None)
if j is None or at is None:
    sys.exit(f"step not found: {job} / {name}")
i = next(k for k in range(at, end) if lines[k].strip() == "run: |")
indent = None
for l in lines[i + 1:end]:
    if l.strip() and indent is None:
        indent = len(l) - len(l.lstrip())
    if l.strip() and len(l) - len(l.lstrip()) < indent:
        break
    print(l[indent:] if l.strip() else "")
PY
}
# verdict <job> <step> <env assignments...> -- sets $out (stdout+stderr), $rc, $sum (the summary)
verdict() {
  local job="$1" name="$2"; shift 2
  job_step "$job" "$name" > "$tmp/v.sh" || { bad "$job / $name: step not found"; return; }
  : > "$tmp/sum"
  out="$(cd "${dir:-$tmp}" && env GITHUB_STEP_SUMMARY="$tmp/sum" RUNNER_TEMP="$tmp/rt" "$@" bash -e "$tmp/v.sh" 2>&1)"; rc=$?
  sum="$(cat "$tmp/sum")"
}
first() { # <label> <expected first summary line, a regex>
  if [ "$(head -1 <<<"$sum")" != "" ] && grep -qE -- "$2" <<<"$(head -1 <<<"$sum")"; then ok "$1"
  else bad "$1 (first summary line does not match '$2')" "$sum"; fi
}
warned() { # <label> <n> -- each not yet confirmed line is a ::warning:: with the same text
  local n; n="$(grep -c '^::warning::not yet confirmed: ' <<<"$out")"
  if [ "$n" = "$2" ] && [ "$(grep -c '^- not yet confirmed: ' <<<"$sum")" = "$2" ] \
    && diff <(sed -n 's/^::warning:://p' <<<"$out") <(sed -n 's/^- //p' <<<"$sum" | grep '^not yet confirmed: ') >/dev/null; then ok "$1"
  else bad "$1 (expected $2 not yet confirmed lines, each also a ::warning::)" "$out"$'\n'"$sum"; fi
}
mkdir -p "$tmp/rt"

echo "-- verdict lines: ci / diff-size"
new_repo; printf 'y = 2\n' >> "$r/src/m.py"; commit; dir="$r"
verdict diff-size "Measure the reviewable diff" MAX_LINES=400 EXCLUDE="" WORKDIR=. BASE_SHA="" HEAD_SHA=""
first "not a pull request: pass, does not apply" '^- pass: diff size, does not apply \(not a pull request'
verdict diff-size "Measure the reviewable diff" MAX_LINES=0 EXCLUDE="" WORKDIR=. BASE_SHA="$base" HEAD_SHA="$(git -C "$r" rev-parse HEAD)"
first "max-diff-lines 0: pass, measured and not enforced, with the count" '^- pass: diff size, measured and not enforced \(max-diff-lines is 0\): 1 lines$'
[ "$rc" = 0 ] && ok "max-diff-lines 0: exit 0" || bad "max-diff-lines 0: exit $rc" "$out"
verdict diff-size "Measure the reviewable diff" MAX_LINES=400 EXCLUDE="" WORKDIR=. BASE_SHA="$base" HEAD_SHA="$(git -C "$r" rev-parse HEAD)"
first "within the limit: pass with the count" '^- pass: diff size, 1 lines, within the limit of 400$'
for i in 1 2 3; do printf 'z%s = 3\n' "$i" >> "$r/src/m.py"; done; commit
verdict diff-size "Measure the reviewable diff" MAX_LINES=2 EXCLUDE="" WORKDIR=. BASE_SHA="$base" HEAD_SHA="$(git -C "$r" rev-parse HEAD)"
first "over the limit: fail, first" '^- fail: diff size, 4 lines, over the limit of 2$'
[ "$rc" != 0 ] && ok "over the limit: the step still fails" || bad "over the limit: exit 0" "$out"
dir=""

echo "-- verdict lines: ci / deps"
verdict deps Verdict EVENT=push SERVED="" REVIEW=skipped SEVERITY=high ACTOR=someone
first "not a pull request: pass, does not apply" '^- pass: dependency review, does not apply \(not a pull request'
warned "not a pull request: no warning" 0
verdict deps Verdict EVENT=pull_request SERVED=refused REVIEW=skipped SEVERITY=high ACTOR=someone
first "refused on a private repository: not yet confirmed, Dependabot alerts after the merge" '^- not yet confirmed: dependency review, GitHub refuses it .*; Dependabot alerts report one after the merge$'
warned "refused: one warning, the same text" 1
verdict deps Verdict EVENT=pull_request SERVED=run REVIEW=success SEVERITY=moderate ACTOR=someone
first "reviewed: pass, at the input's severity" '^- pass: dependency review, no added dependency version with an advisory at moderate or above$'
verdict deps Verdict EVENT=pull_request SERVED=run REVIEW=failure SEVERITY=high ACTOR=someone
first "review failed: fail" '^- fail: dependency review'
verdict deps Verdict EVENT=pull_request SERVED=run REVIEW=success SEVERITY=high ACTOR='dependabot[bot]'
if grep -qE '^- not yet confirmed: CodeQL on this head, Dependabot pushed it .*`main` is analysed after the merge$' <<<"$sum"; then ok "a head Dependabot pushed: CodeQL not yet confirmed"
else bad "a head Dependabot pushed: no CodeQL line" "$sum"; fi
warned "a head Dependabot pushed: one warning" 1
verdict deps Verdict EVENT=push SERVED="" REVIEW=skipped SEVERITY=high ACTOR='dependabot[bot]'
warned "Dependabot outside a pull request: no CodeQL line" 0

echo "-- verdict lines: ci / lint"
verdict lint Verdict SYNC=success CHECK=success FORMAT=success ZIZMOR=success
first "lint opens with uv sync" '^- pass: uv sync --locked$'
warned "zizmor left no advisory list: its known-vulnerable-actions line is not yet confirmed" 1
verdict lint Verdict SYNC=failure CHECK=skipped FORMAT=skipped ZIZMOR=skipped
first "a failed sync: fail" '^- fail: uv sync --locked$'
warned "a failed sync: each step it stopped is not yet confirmed, known-vulnerable-actions too" 4
if grep -q "online audits" <<<"$sum"; then bad "the standing online-audits line is still written" "$sum"; else ok "no standing online-audits line"; fi

# The zizmor step, run against a fake uvx that prints a fixture JSON and exits
# with a given code (zizmor 1.29.0's shape: 0 none, 11-14 findings by highest
# severity, 1 an error during the audit). Then the Verdict step on its outcome.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/uvx" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$FAKE_ARGS"
[ -f "$FAKE_JSON" ] && cat "$FAKE_JSON"
exit "$FAKE_RC"
SH
chmod +x "$tmp/bin/uvx"
finding() { # <ident> <severity> <annotation> <feature> <row>
  printf '{"ident":"%s","desc":"d","url":"u","ignored":false,"fixes":[],"determinations":{"confidence":"High","severity":"%s","persona":"Regular"},"locations":[{"symbolic":{"key":{"Local":{"verbatim_path":".github/workflows/a.yml"}},"annotation":"%s","route":{"route":[]},"feature_kind":"Normal","kind":"Primary"},"concrete":{"location":{"start_point":{"row":%s,"column":8},"end_point":{"row":%s,"column":40},"offset_span":{"start":0,"end":1}},"feature":"%s","comments":[]}}]}' \
    "$1" "$2" "$3" "$5" "$5" "$4"
}
kva1="$(finding known-vulnerable-actions High GHSA-mrrh-fwg8-r2c3 'uses: tj-actions/changed-files@v35' 6)"
kva2="$(finding known-vulnerable-actions High GHSA-mcph-m25j-8j63 'uses: tj-actions/changed-files@v35' 6)"
imp="$(finding impostor-commit High 'uses a commit that does not belong to the repository' 'uses: actions/checkout@0123456789abcdef0123456789abcdef01234567' 9)"
# zz <json or -> <exit> -- runs the zizmor step, then the Verdict on its outcome
zz() {
  rm -f "$tmp/rt/"zizmor*; if [ "$1" = - ]; then rm -f "$tmp/z.json"; else printf '%s\n' "$1" > "$tmp/z.json"; fi
  job_step lint "Workflow security (zizmor, medium and above)" > "$tmp/z.sh" || { bad "lint / zizmor: step not found"; return; }
  zout="$(cd "$tmp" && env PATH="$tmp/bin:$PATH" FAKE_JSON="$tmp/z.json" FAKE_RC="$2" FAKE_ARGS="$tmp/z.args" GH_TOKEN=t RUNNER_TEMP="$tmp/rt" bash -e "$tmp/z.sh" 2>&1)"; zrc=$?
  verdict lint Verdict SYNC=success CHECK=success FORMAT=success ZIZMOR="$([ "$zrc" = 0 ] && echo success || echo failure)"
}
rest="zizmor's audits at medium and above, offline and online, except known-vulnerable-actions"
nokva="- pass: no published advisory at medium or above for an action pinned here (zizmor known-vulnerable-actions)"

zz '[]' 0
[ "$zrc" = 0 ] && ok "zizmor, no findings: the step passes" || bad "zizmor, no findings: the step exited $zrc" "$zout"
grep -q -- '--format json' "$tmp/z.args" && grep -q -- '--min-severity medium' "$tmp/z.args" && ok "zizmor runs with --format json at medium and above" || bad "zizmor's arguments" "$(cat "$tmp/z.args")"
grep -qx -- "- pass: $rest" <<<"$sum" && grep -qx -- "$nokva" <<<"$sum" && ok "zizmor, no findings: the two pass lines" || bad "zizmor, no findings: the two pass lines" "$sum"
warned "zizmor, no findings: no warning" 0

zz "[$imp]" 14
[ "$zrc" != 0 ] && ok "an impostor-commit finding: the step fails" || bad "an impostor-commit finding: the step passed" "$zout"
grep -q '^impostor-commit High .github/workflows/a.yml:10' <<<"$zout" && ok "an impostor-commit finding: printed with its ident, severity and location" || bad "the finding is not printed" "$zout"
grep -qx -- "- fail: $rest" <<<"$sum" && ok "an impostor-commit finding: fail" || bad "an impostor-commit finding: no fail line" "$sum"
grep -qx -- "$nokva" <<<"$sum" && ok "an impostor-commit finding: known-vulnerable-actions still reported" || bad "an impostor-commit finding: no known-vulnerable-actions line" "$sum"

zz "[$kva1,$kva2]" 14
[ "$zrc" = 0 ] && ok "only known-vulnerable-actions: the step passes" || bad "only known-vulnerable-actions: the step exited $zrc" "$zout"
[ "$(grep -c '^known-vulnerable-actions High ' <<<"$zout")" = 2 ] && ok "only known-vulnerable-actions: each finding in the log" || bad "the advisories are not in the log" "$zout"
grep -qx -- "- pass: $rest" <<<"$sum" && ok "only known-vulnerable-actions: pass for the rest" || bad "only known-vulnerable-actions: no pass for the rest" "$sum"
warned "only known-vulnerable-actions: one not yet confirmed line and one warning per finding" 2
grep -qE '^- not yet confirmed: GHSA-mrrh-fwg8-r2c3 .*tj-actions/changed-files@v35.*fixed version confirms it$' <<<"$sum" && ok "the line names the advisory, the action and its ref, and what confirms it" || bad "the line does not name the advisory, action and ref" "$sum"

zz "[$kva1,$imp]" 14
[ "$zrc" != 0 ] && grep -qx -- "- fail: $rest" <<<"$sum" && ok "both: fail for the rest" || bad "both: no fail" "$zout"$'\n'"$sum"
warned "both: the advisory is still a not yet confirmed line" 1

zz - 1
[ "$zrc" != 0 ] && ok "exit 1, an error during the audit: the step fails" || bad "exit 1: the step passed" "$zout"
grep -qx -- "- fail: $rest" <<<"$sum" && ok "exit 1: fail" || bad "exit 1: no fail line" "$sum"
warned "exit 1: known-vulnerable-actions not yet confirmed" 1
zz '[]' 2
[ "$zrc" != 0 ] && ok "exit 2, an argument error: the step fails" || bad "exit 2: the step passed" "$zout"
zz 'not json' 0
[ "$zrc" != 0 ] && ok "output that is not JSON: the step fails" || bad "not JSON: the step passed" "$zout"
# A JSON \n decodes to a real newline: the annotation and the feature both carry one.
f="$(finding known-vulnerable-actions High 'GHSA-x\n::error::forged' 'a/b@v1\n::error::forged' 1)"
zz "[$f]" 14
if grep -q '^::error::forged' <<<"$zout"$'\n'"$out"; then bad "a newline in a finding started a workflow command" "$zout"$'\n'"$out"; else ok "a newline in a finding stays on its line"; fi
grep -q '^- not yet confirmed: GHSA-x ::error::forged for a/b@v1 (' <<<"$sum" && ok "a multi-line feature: the action is its first line" || bad "a multi-line feature" "$sum"
zz '{}' 0
[ "$zrc" != 0 ] && ok "output that is not a list: the step fails" || bad "a JSON object: the step passed" "$zout"
zz - 0
[ "$zrc" != 0 ] && grep -q '^- not yet confirmed: no published advisory' <<<"$sum" && ok "no output at exit 0: the step fails, no advisory pass" || bad "no output at exit 0" "$zout"$'\n'"$sum"

echo "-- verdict lines: ci / test"
# A not yet confirmed line can carry an input's text (the extra versions):
# it must not end its ::warning:: and start another command.
job_step test Verdict | grep '^say()' > "$tmp/say.sh"
printf '%s\n' '. "$1"' 'say "not yet confirmed: x%"$'"'"'\n'"'"'"::error::y"$'"'"'\r'"'"'' > "$tmp/say-call.sh"
out="$(GITHUB_STEP_SUMMARY=/dev/null bash -e "$tmp/say-call.sh" "$tmp/say.sh")"
if [ "$out" = '::warning::not yet confirmed: x%25%0A::error::y%0D' ]; then ok "a not yet confirmed line escapes %, a newline and a carriage return"
else bad "say does not escape its text" "$out"; fi
verdict test Verdict SYNC=success PYTEST=success EXTRA=skipped VERSIONS=""
if grep -qx -- "- pass: pytest on extra Python versions, does not apply (the extra-python-versions input is empty)" <<<"$sum"; then ok "no extra versions: pass, does not apply, not a skipped step's not yet confirmed"
else bad "no extra versions" "$sum"; fi
warned "no extra versions: no warning" 0

echo "-- verdict lines: ci / floor-check"
mkdir -p "$tmp/rt/plinth"
cat > "$tmp/rt/plinth/floor-check.py" <<'PY'
import sys
out = sys.argv[sys.argv.index("--verdicts") + 1]
open(out, "w").write("fail: a\nnot yet confirmed: b 100%; c\n")
print("  FAIL  a")
sys.exit(1)
PY
verdict floor-check "Floor check" GH_TOKEN=x WORKDIR=. EXPECT="" GITHUB_REPOSITORY=o/r
first "the checker's verdict lines open the summary" '^- fail: a$'
[ "$rc" = 1 ] && ok "the step exits with the checker's code" || bad "the step exited $rc, not the checker's 1" "$out"
if grep -qx '::warning::not yet confirmed: b 100%25; c' <<<"$out"; then ok "each not yet confirmed is a ::warning::, % escaped"; else bad "no escaped warning" "$out"; fi
if grep -q '^  FAIL  a$' <<<"$sum"; then ok "the checker's report follows the verdict lines"; else bad "the report is not in the summary" "$sum"; fi
printf 'import sys\nprint("  PASS  partial")\nsys.exit(0)\n' > "$tmp/rt/plinth/floor-check.py"; rm -f "$tmp/rt/floor.verdicts"   # RUNNER_TEMP is fresh per job
verdict floor-check "Floor check" GH_TOKEN=x WORKDIR=. EXPECT="" GITHUB_REPOSITORY=o/r
[ "$rc" != 0 ] && ok "a checker that writes no verdict file fails the step" || bad "no verdict file, and the step passed" "$out"
first "a checker that writes no verdict file: a fail line opens the summary" '^- fail: the floor, the checker wrote no verdicts \(exit 0\)'
if grep -q '^  PASS  partial$' <<<"$sum"; then ok "a checker that writes no verdict file: its report still reaches the summary"; else bad "the partial report is lost" "$sum"; fi
# A read left to /plinth:floor-check is a setting the Actions token never
# reads, in every run: summary only, no annotation (#440, #441). A step
# annotates at most nine lines and says how many more the summary has:
# GitHub drops a step's annotations past ten with no notice.
fake_verdicts() { # <verdict lines...> -- a checker that writes them and passes
  { echo 'import sys'; echo 'out = sys.argv[sys.argv.index("--verdicts") + 1]'
    printf 'open(out, "w").write(%s)\n' "$(python3 -c 'import json, sys; print(json.dumps("".join(a + "\n" for a in sys.argv[1:])))' "$@")"
    echo 'print("  PASS  x")'; } > "$tmp/rt/plinth/floor-check.py"
  rm -f "$tmp/rt/floor.verdicts"
}
left=(); for s in "push protection" "ruleset 1: bypass actors" "CodeQL default setup languages" "squash commit settings"; do
  left+=("not yet confirmed: $s not read here; left to /plinth:floor-check"); done
fake_verdicts "pass: the floor, no FAIL in what this run read" "${left[@]}" "not yet confirmed: labels not verified; a run that can read it confirms it"
verdict floor-check "Floor check" GH_TOKEN=x WORKDIR=. EXPECT="" GITHUB_REPOSITORY=o/r
if [ "$(grep -c '^::warning::' <<<"$out")" = 1 ] && grep -qx '::warning::not yet confirmed: labels not verified; a run that can read it confirms it' <<<"$out"; then
  ok "reads left to /plinth:floor-check: no annotation; the other not yet confirmed: one"
else bad "expected exactly one ::warning::, the labels line" "$out"; fi
if [ "$(grep -c '^- not yet confirmed: ' <<<"$sum")" = 5 ] && [ "$(grep -c '; left to /plinth:floor-check$' <<<"$sum")" = 4 ]; then ok "reads left to /plinth:floor-check: still in the summary, unchanged"
else bad "the summary lost a line left to /plinth:floor-check" "$sum"; fi
[ "$rc" = 0 ] && ok "reads left to /plinth:floor-check: the step passes" || bad "the step exited $rc" "$out"
twelve=(); for i in $(seq 1 12); do twelve+=("not yet confirmed: item $i; a run that can read it confirms it"); done
fake_verdicts "pass: the floor" "${twelve[@]}"
verdict floor-check "Floor check" GH_TOKEN=x WORKDIR=. EXPECT="" GITHUB_REPOSITORY=o/r
if [ "$(grep -c '^::warning::' <<<"$out")" = 10 ] && [ "$(grep -c '^::warning::not yet confirmed: item [1-9];' <<<"$out")" = 9 ] \
  && [ "$(grep '^::warning::' <<<"$out" | tail -1)" = '::warning::3 more not yet confirmed lines are in the job summary' ]; then
  ok "twelve not yet confirmed: nine annotated, then one that says three more are in the summary"
else bad "twelve not yet confirmed: expected items 1-9 and '3 more'" "$out"; fi
if [ "$(grep -c '^- not yet confirmed: item ' <<<"$sum")" = 12 ]; then ok "twelve not yet confirmed: the summary carries all twelve"
else bad "twelve not yet confirmed: the summary does not carry all twelve" "$sum"; fi
[ "$rc" = 0 ] && ok "twelve not yet confirmed: the step passes" || bad "the step exited $rc" "$out"
# Every job's helper is the same text, so the cap and the marker hold in each.
helpers="$(grep -E '^ +(nw=0;|say\(\) )' "$wf" | sed 's/^ *//' | sort | uniq -c)"
if [ "$(wc -l <<<"$helpers" | tr -d ' ')" = 2 ] && [ "$(awk '{print $1}' <<<"$helpers" | sort -u | wc -l | tr -d ' ')" = 1 ] \
  && [ "$(awk 'NR==1{print $1}' <<<"$helpers")" = 9 ]; then
  ok "every step that writes verdicts defines the same capped say helper ($(awk 'NR==1{print $1}' <<<"$helpers") steps)"
else bad "the say helpers differ between steps, or a step lacks the cap" "$helpers"; fi
fake_verdicts "fail: a" "${twelve[@]}"; sed -i.bak 's/^print("  PASS  x")$/print("  FAIL  a"); sys.exit(1)/' "$tmp/rt/plinth/floor-check.py"
verdict floor-check "Floor check" GH_TOKEN=x WORKDIR=. EXPECT="" GITHUB_REPOSITORY=o/r
[ "$rc" = 1 ] && ok "past the cap, the step still exits with the checker's code" || bad "past the cap, the step exited $rc, not 1" "$out"
grep -qx '::warning::3 more not yet confirmed lines are in the job summary' <<<"$out" && ok "past the cap, a failing step still says how many more" || bad "a failing step lost the 'more' line" "$out"

echo "-- verdict lines: ci / pr-title"
verdict pr-title "Check the title" TITLE=""
first "not a pull request: pass, does not apply" '^- pass: PR title, does not apply \(not a pull request'
verdict pr-title "Check the title" TITLE="feat(x): a thing"
first "a conventional title: pass" '^- pass: PR title follows the convention$'
verdict pr-title "Check the title" TITLE="feat: a thing (#12)"
first "a trailing number: fail, first" '^- fail: PR title, it ends in a number$'
verdict pr-title "Check the title" TITLE="Add a thing"
first "not Conventional Commits: fail, first" '^- fail: PR title, it is not Conventional Commits$'
[ "$rc" != 0 ] && ok "not Conventional Commits: the step still fails" || bad "a bad title passed" "$out"

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
