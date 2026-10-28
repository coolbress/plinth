#!/usr/bin/env bash
# `ci / code-growth` (#705) on fixture projects: above the conventions it warns
# at most three times, each warning naming the next step, and below them its
# summary opens with a pass line. It never fails. The steps are not copied
# here; they are extracted from python-ci.yml and run as the runner runs them,
# so the rule tested is the rule shipped. ruff is the one tests/lint-tools.txt
# pins by hash; `uv run --no-sync` is a stub that runs its command, as it does
# once `uv sync --locked` has put the project's ruff in its environment.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="$root/.github/workflows/python-ci.yml"
# shellcheck source=tests/lib/lint-tools.sh
. "$root/tests/lib/lint-tools.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/code-growth.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | tail -20 | sed 's/^/        | /'; }

bin="$(lint_tools_bin)" || { echo "$bin"; exit 1; }
[ -x "$bin/ruff" ] || { echo "  FAIL  ruff is not in $bin"; exit 1; }
mkdir -p "$tmp/bin"
cat > "$tmp/bin/uv" <<'SH'
#!/bin/sh
[ "$1 $2" = "run --no-sync" ] || { echo "uv stub: only 'uv run --no-sync' is expected, got: $*" >&2; exit 2; }
shift 2; exec "$@"
SH
chmod +x "$tmp/bin/uv"; ln -s "$bin/ruff" "$tmp/bin/ruff"

# A step's `run: |` block, dedented, by job and step id or name.
job_step() {
  python3 - "$wf" "$1" "$2" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
job, name = sys.argv[2], sys.argv[3]
j = next((i for i, l in enumerate(lines) if l == f"  {job}:"), None)
end = next((i for i in range(j + 1, len(lines)) if lines[i][:3].strip() and lines[i].startswith("  ") and not lines[i].startswith("   ")), len(lines)) if j is not None else 0
at = next((i for i in range(j or 0, end) if lines[i].strip() in (f"- name: {name}", f"- id: {name}")), None)
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
job_step code-growth "Measure the code's size" > "$tmp/measure.sh" || { echo "  FAIL  code-growth / Measure the code's size: step not found in python-ci.yml"; exit 1; }
job_step code-growth Verdict > "$tmp/verdict.sh" || { echo "  FAIL  code-growth / Verdict: step not found in python-ci.yml"; exit 1; }
grep -q 'continue-on-error: true' <(sed -n "/- name: Measure the code's size/,/run: |/p" "$wf") \
  && ok "the measuring step continues on error, so the job reports and never fails" \
  || bad "the measuring step does not continue on error"

# Fixture writers. complex <name>: complexity 12, 25 statements.
# long <name>: complexity 1, 79 statements. small <name>: a few lines.
complex() { printf 'def %s(x):\n    y = 0\n' "$1"; for i in $(seq 11); do printf '    if x == %s:\n        y = %s\n' "$i" "$i"; done; printf '    return y\n\n\n'; }
long()    { printf 'def %s():\n    y = 0\n' "$1"; for i in $(seq 78); do printf '    y += %s\n' "$i"; done; printf '    return y\n\n\n'; }
small()   { printf 'def %s():\n    return 1\n\n\n' "$1"; }
lines()   { for i in $(seq "$1"); do printf 'x%s = %s\n' "$i" "$i"; done; }

new_repo() { # [<project dir under the repository>]
  r="$tmp/r$((pass+fail))"; rm -rf "$r"; mkdir -p "$r"
  git -C "$r" init -q -b main
  git -C "$r" config user.email t@example.com; git -C "$r" config user.name t
  git -C "$r" config commit.gpgsign false
  p="$r${1:+/$1}"; mkdir -p "$p/src/pkg" "$p/tests"
  printf '[project]\nname = "p"\nversion = "0"\n\n[tool.ruff.lint]\nselect = ["E", "F"]\n' > "$p/pyproject.toml"
  small ok > "$p/src/pkg/__init__.py"
}

# run [SYNC]: both steps in $p, as the runner runs them; sets $out, $sum, $warns.
run() {
  rt="$tmp/rt"; rm -rf "$rt"; mkdir -p "$rt"; : > "$rt/summary"
  git -C "$r" add -A >/dev/null; git -C "$r" commit -qm c >/dev/null 2>&1
  out="$(cd "$p" && export PATH="$tmp/bin:$PATH" RUNNER_TEMP="$rt" GITHUB_STEP_SUMMARY="$rt/summary" SYNC="${1:-success}"
         bash -e "$tmp/measure.sh" 2>&1; echo "measure exit $?"; bash -e "$tmp/verdict.sh" 2>&1; echo "verdict exit $?")"
  sum="$(cat "$rt/summary")"
  warns="$(printf '%s\n' "$out" | grep '^::warning' || true)"
}
nwarn() { [ -z "$warns" ] && echo 0 || printf '%s\n' "$warns" | wc -l | tr -d ' '; }
# expect <label> <n warnings> <first summary line, a regex> [<text every warning carries>]
expect() {
  label="$1"; n="$2"; first="$3"; each="${4:-}"
  if ! printf '%s\n' "$out" | grep -qx 'measure exit 0' || ! printf '%s\n' "$out" | grep -qx 'verdict exit 0'; then
    bad "$label (a step exited non-zero; this job never fails)" "$out"; return 1; fi
  if [ "$(nwarn)" != "$n" ]; then bad "$label (expected $n warnings, got $(nwarn))" "$out"$'\n'"$sum"; return 1; fi
  if ! printf '%s\n' "$sum" | head -1 | grep -qE -- "$first"; then bad "$label (summary opens otherwise)" "$sum"; return 1; fi
  if [ -n "$each" ] && [ "$(printf '%s\n' "$warns" | grep -cF -- "$each")" != "$n" ]; then
    bad "$label (not every warning carries '$each')" "$warns"; return 1; fi
  ok "$label"
}
NEXT="Next: ask Claude to run /improve-codebase-architecture on"

echo "ci / code-growth: below the conventions"
new_repo; small a > "$p/src/pkg/a.py"; complex in_tests > "$p/tests/test_x.py"; run
expect "a small project gets a pass line in the summary's verdict form, no warning" 0 \
  '^- pass: code size within the conventions \(no function above complexity 10 or 50 statements, no Python file above 1000 lines\), 2 Python files measured$'
lines 1000 > "$p/src/pkg/a.py"; run
expect "a file of exactly 1000 lines is not above the convention" 0 '^- pass: code size within the conventions'

new_repo; rm -rf "$p/src" "$p/tests"; printf '# nothing\n' > "$p/README.md"; run
expect "a project with no Python file passes as does not apply" 0 \
  '^- pass: code size within the conventions, does not apply \(no Python file under \.\)$'

echo "ci / code-growth: above the conventions"
new_repo
{ complex tangled; long straight; } > "$p/src/pkg/a.py"
lines 1300 > "$p/src/pkg/big.py"
run
if expect "one complex function, one long one, one 1300-line file: three warnings, each naming the next step" 3 \
  '^- not yet confirmed: code size within the conventions, 2 functions and 1 file are above them, largest first: ' "$NEXT"; then
  printf '%s\n' "$warns" | head -1 | grep -qF '::warning file=src/pkg/a.py,line=28,title=Code growth::src/pkg/a.py:28 function `straight` has 79 statements (convention 50)' \
    && ok "the largest comes first, a statement-only function named from its def line" \
    || bad "the first warning is not the long function" "$warns"
  printf '%s\n' "$warns" | grep -qF 'file=src/pkg/big.py,line=1,title=Code growth::src/pkg/big.py:1 file has 1300 lines (convention 1000)' \
    && ok "the long file is a warning" || bad "no warning names the long file" "$warns"
  printf '%s\n' "$sum" | grep -qF 'conventions, not validated numbers' \
    && printf '%s\n' "$sum" | grep -qF '| `src/pkg/a.py:1` | function `tangled` has complexity 12 (convention 10) |' \
    && ok "the summary lists them and says the limits are conventions, not validated numbers" \
    || bad "the summary's table or its conventions line is missing" "$sum"
  printf '%s\n' "$sum" | grep -c '^- ' | grep -qx 1 && ok "the summary has the one verdict line" || bad "the summary has other verdict lines" "$sum"
fi

new_repo; for f in one two three four five; do complex "$f"; done > "$p/src/pkg/a.py"; run
expect "five complex functions: still three warnings, and the summary lists all five" 3 \
  '^- not yet confirmed: code size within the conventions, 5 functions and 0 files' "$NEXT" \
  && { [ "$(printf '%s\n' "$sum" | grep -c '^| `src/pkg/a.py')" = 5 ] && ok "all five are in the summary's table" || bad "the table does not list five" "$sum"; }

new_repo; complex tangled > "$p/src/pkg/a.py"
printf '\n[tool.ruff.lint.mccabe]\nmax-complexity = 50\n\n[tool.ruff.lint.pylint]\nmax-statements = 500\n' >> "$p/pyproject.toml"; run
expect "a project's own looser ruff limits do not change the conventions" 1 \
  '^- not yet confirmed: code size within the conventions, 1 function and 0 files' "$NEXT src/pkg/a.py"

new_repo; rm -rf "$p/src"; complex tangled > "$p/app.py"; run
expect "without src/ the whole project is measured" 1 '^- not yet confirmed: ' "file=app.py,line=1"

new_repo proj; complex tangled > "$p/src/pkg/a.py"; run
expect "in a working directory below the root, the warning names the file from the root" 1 '^- not yet confirmed: ' \
  "file=proj/src/pkg/a.py,line=1"

echo "ci / code-growth: when it could not measure"
new_repo; complex tangled > "$p/src/pkg/a.py"; run failure
expect "a failed uv sync is one not yet confirmed warning, never a pass" 1 \
  '^- not yet confirmed: code size within the conventions, it did not run because an earlier step failed' 'not yet confirmed'

new_repo; complex tangled > "$p/src/pkg/a.py"; printf '[tool.ruff\n' > "$p/pyproject.toml"; run
expect "ruff that cannot read the project's configuration is not yet confirmed, not a pass" 1 \
  '^- not yet confirmed: code size within the conventions, ruff did not finish' 'ruff did not finish'

# A ruff that prints a well-formed empty list and exits 2: its exit code is
# what says it did not finish, never the list.
mkdir -p "$tmp/broken"; printf '#!/bin/sh\necho "[]"; exit 2\n' > "$tmp/broken/ruff"; chmod +x "$tmp/broken/ruff"
new_repo; complex tangled > "$p/src/pkg/a.py"; ln -sf "$tmp/broken/ruff" "$tmp/bin/ruff"; run; ln -sf "$bin/ruff" "$tmp/bin/ruff"
expect "ruff that exits with an error is not yet confirmed, even when it printed a list" 1 \
  '^- not yet confirmed: code size within the conventions, ruff did not finish' 'ruff did not finish'

new_repo; rm -rf "$tmp/rt"; mkdir -p "$tmp/rt"; : > "$tmp/rt/summary"
out="$(cd "$p" && RUNNER_TEMP="$tmp/rt" GITHUB_STEP_SUMMARY="$tmp/rt/summary" bash -e "$tmp/verdict.sh" 2>&1; echo "verdict exit $?")"
out="measure exit 0"$'\n'"$out"; sum="$(cat "$tmp/rt/summary")"; warns="$(printf '%s\n' "$out" | grep '^::warning' || true)"
expect "a measuring step that wrote nothing is not yet confirmed" 1 \
  '^- not yet confirmed: code size within the conventions, the measuring step did not finish'

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
