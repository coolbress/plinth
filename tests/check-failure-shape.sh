#!/usr/bin/env bash
# What a failing required check says, and where (#1098): the annotation, the
# last lines of the job's log and the top of its summary carry one cause, one
# next step and a link. The case matrix is generated: one row per required
# check in ruleset.json and, for a job with a Verdict step, one per
# `steps.<id>.outcome` that step reads. Each failing row runs the shipped
# Verdict step, extracted from python-ci.yml, and wants exactly one titled
# `::error` of at most 300 characters, the block `failed:` / `next:` / `more:`
# as the last lines the step prints, a `more:` link at the plinth commit the
# workflow runs whose anchor is a heading in docs/reference/required-checks.md
# at this commit, no "earlier step failed" warning, and exit 0.
# Only `ci / test` has the shape yet; the other rows are printed as pending
# with the ticket that brings them (#1099, #1100), and fail here once that
# job's Verdict prints a block, so the list is kept honest.
# `ci / test` also: pytest's FAILED and ERROR lines become at most nine
# annotations at file and line plus one "showing 9 of N" line, read from
# committed pytest output (tests/fixtures/pytest/); pytest's exit code, 124
# and 137 included, survives the `tee` that keeps its output.
# PLINTH_WF reads another copy of python-ci.yml (an older commit's, say).
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="${PLINTH_WF:-$root/.github/workflows/python-ci.yml}"
doc="$root/docs/reference/required-checks.md"
fx="$root/tests/fixtures/pytest"
python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))' \
  || { echo "  FAIL  needs python3 3.11 or later, as the runner has; got $(python3 --version 2>&1)"; exit 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/check-failure-shape.XXXXXX")" || { echo "check-failure-shape: could not make a temp folder" >&2; exit 1; }; trap 'rm -r "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        | /'; }
SHA=0123456789abcdef0123456789abcdef01234567

# step <job> <step name or id> <out>: the step's `run: |` block, dedented.
step() {
  python3 - "$wf" "$1" "$2" > "$3" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
start = lines.index(f"  {sys.argv[2]}:")
end = next((i for i in range(start + 1, len(lines)) if re.match(r"^  [a-z]", lines[i])), len(lines))
want = (f"- name: {sys.argv[3]}", f"- id: {sys.argv[3]}", f"id: {sys.argv[3]}")
at = next(i for i in range(start, end) if lines[i].strip() in want)
r = next(i for i in range(at, end) if lines[i].strip() == "run: |")
indent = None
for l in lines[r + 1:end]:
    if l.strip() and indent is None:
        indent = len(l) - len(l.lstrip())
    if l.strip() and len(l) - len(l.lstrip()) < indent:
        break
    print(l[indent:] if l.strip() else "")
PY
}

# The matrix: <check> <env var> <step id>, or <check> - - for a job with no
# Verdict step.
python3 - "$wf" "$root/ruleset.json" > "$work/matrix" <<'PY'
import json, re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
rules = json.load(open(sys.argv[2], encoding="utf-8"))["rules"]
checks = [c["context"] for r in rules if r["type"] == "required_status_checks"
          for c in r["parameters"]["required_status_checks"]]
for check in checks:
    job = check.removeprefix("ci / ")
    start = lines.index(f"  {job}:")
    end = next((i for i in range(start + 1, len(lines)) if re.match(r"^  [a-z]", lines[i])), len(lines))
    at = next((i for i in range(start, end) if lines[i].strip() == "- name: Verdict"), None)
    if at is None:
        print(f"{check}\t-\t-"); continue
    stop = next((i for i in range(at + 1, end) if lines[i].startswith("      - ")), end)
    rows = [m.groups() for l in lines[at:stop]
            if (m := re.match(r"^ +([A-Z_]+): \$\{\{ steps\.([a-z-]+)\.outcome \}\}", l))]
    for var, sid in rows or [("-", "-")]:
        print(f"{check}\t{var}\t{sid}")
PY
[ -s "$work/matrix" ] && ok "the matrix has $(wc -l < "$work/matrix" | tr -d ' ') rows from ruleset.json and the Verdict steps" \
  || { bad "no matrix was built"; exit 1; }

# The anchors docs/reference/required-checks.md has, as GitHub makes them.
python3 - "$doc" > "$work/anchors" <<'PY'
import re, sys
for line in open(sys.argv[1], encoding="utf-8"):
    m = re.match(r"#{1,6}\s+(.*?)\s*$", line)
    if m:
        print(re.sub(r"[^\w\- ]", "", m.group(1).lower()).replace(" ", "-"))
PY

# shape <label> <file with the step's output> <exit>: the block's rules.
shape() {
  local label="$1" out="$2" rc="$3" why=() titled msg more anchor
  titled="$(grep -E '^::error title=' "$out")"
  if [ "$(grep -c . <<<"$titled")" != 1 ] || [ -z "$titled" ]; then why+=("$(grep -c . <<<"$titled") titled ::error, want one"); fi
  msg="${titled#*::error title=*::}"
  [ "${#msg}" -le 300 ] || why+=("the titled ::error is ${#msg} characters")
  [ "$(tail -3 "$out" | cut -d' ' -f1 | tr '\n' ' ')" = "failed: next: more: " ] || why+=("the last lines are not the block")
  grep -qE '^next: .+' "$out" || why+=("no next: line")
  more="$(sed -n 's/^more: //p' "$out")"
  case "$more" in
    "https://github.com/coolbress/plinth/blob/${SHA:0:12}/docs/reference/required-checks.md#"*)
      anchor="${more#*#}"; grep -qx -- "$anchor" "$work/anchors" || why+=("no heading for #$anchor") ;;
    *) why+=("more: is not a link to required-checks.md at the workflow's commit: $more") ;;
  esac
  ! grep -qE '^::warning::.*earlier step failed' "$out" || why+=("an earlier-step-failed warning")
  [ "$rc" = 0 ] || why+=("exit $rc")
  if [ "${#why[@]}" = 0 ]; then ok "$label: one titled ::error, the block last, a link that exists, exit 0"
  else bad "$label: $(IFS=';'; echo "${why[*]}")" "$(cat "$out")"; fi
}

step test Verdict "$work/test-verdict.sh"
# test_verdict <label> [VAR=value...]: runs ci / test's Verdict with every
# step passed, then the given outcomes; a pytest step that did not pass
# leaves the changed-lines step's line, as the runner does.
test_verdict() {
  local label="$1"; shift
  rt="$work/rt-$((++n))"; mkdir -p "$rt"; : > "$rt/summary"
  (cd "$rt" && env RUNNER_TEMP="$rt" GITHUB_STEP_SUMMARY="$rt/summary" TEST_MARGIN_SECONDS=120 PLINTH_SHA="$SHA" \
     SYNC=success PYTEST=success EXTRA=skipped VERSIONS="" WEB=false PG=skipped LIMIT=10 LIMIT_OUTCOME=success \
     "$@" bash -e "$work/test-verdict.sh") > "$rt/out" 2>&1
  rc=$?
}
n=0
pre() { # what a step left in RUNNER_TEMP before Verdict runs
  mkdir -p "$work/rt-$((n + 1))"; local d="$work/rt-$((n + 1))"
  printf 'not yet confirmed: changed lines ran under the tests, it did not run because an earlier step failed; a run that gets past that step confirms it\n' > "$d/changed.verdict"
  case "$1" in
    pytest) cp "$fx/${2:-one}.txt" "$d/pytest.log" ;;
    extra) { echo "── python 3.13"; cat "$fx/${2:-one}.txt"; } > "$d/extra.log" ;;
    limit) echo 10 > "$d/pytest.time-limit" ;;
  esac
}

echo "-- the matrix: every required check, every outcome its Verdict reads"
while IFS=$'\t' read -r check var sid; do
  job="${check#ci / }"
  case "$check" in
    "ci / test")
      case "$var" in
        LIMIT_OUTCOME) pre none; test_verdict x LIMIT_OUTCOME=failure LIMIT=0 SYNC=skipped PYTEST=skipped ;;
        SYNC) pre none; test_verdict x SYNC=failure PYTEST=skipped ;;
        PG) pre none; test_verdict x WEB=true PG=failure PYTEST=skipped ;;
        PYTEST) pre pytest; test_verdict x PYTEST=failure ;;
        EXTRA) pre extra; echo "pass: changed lines ran under the tests, all 2 changed lines ran" > "$work/rt-$((n + 1))/changed.verdict"
               test_verdict x VERSIONS=3.13 EXTRA=failure ;;
        *) bad "$check: steps.$sid.outcome ($var) has no case here: add one"; continue ;;
      esac
      shape "$check, steps.$sid failed" "$rt/out" "$rc" ;;
    *)
      case "$job" in lint|typecheck) t="#1099" ;; *) t="#1100" ;; esac
      what="$check"; [ "$var" = - ] || what="$check, steps.$sid"
      if sed -n "/^  $job:/,/^  [a-z]/p" "$wf" | grep -qF "fail_check=\"$check\""; then
        bad "$check sets fail_check now: give its rows cases here instead of pending"
      else printf '  ----  %s: pending, %s brings the shape\n' "$what" "$t"; fi ;;
  esac
done < "$work/matrix"

echo "-- ci / test: the failed test, named and annotated"
pre pytest one; test_verdict x PYTEST=failure; out="$rt/out"
grep -qx 'failed: pytest on .python-version: tests/test_app.py::test_add_negative failed' "$out" \
  && ok "one failing assertion: the block's failed: line names the test" || bad "the failed: line does not name the test" "$(tail -5 "$out")"
grep -qx '::error file=tests/test_app.py,line=10::FAILED tests/test_app.py::test_add_negative - assert -2 == -3' "$out" \
  && ok "the failed test is an annotation at its file and line" || bad "no annotation at tests/test_app.py:10" "$(grep '^::' "$out")"
grep -q '^next: run uv run pytest tests/test_app.py::test_add_negative' "$out" \
  && ok "next: runs that one test" || bad "next: does not run the test" "$(tail -3 "$out")"
grep -qx -- '- fail: pytest on .python-version' "$rt/summary" && ok "the summary still opens with the plain fail line" || bad "the summary's fail line changed" "$(cat "$rt/summary")"
[ "$(grep -n '^fail: pytest on .python-version$' "$out" | cut -d: -f1)" -lt "$(grep -n '^failed: ' "$out" | cut -d: -f1)" ] 2>/dev/null \
  && ok "the summary's lines are in the log too, above the block" || bad "the log lacks the summary's lines" "$(cat "$out")"

pre pytest many; test_verdict x PYTEST=failure; out="$rt/out"
if [ "$(grep -c '^::error file=tests/test_many.py,line=[0-9]*::FAILED ' "$out")" = 9 ] \
   && grep -qx '::notice::showing 9 of 12 failed tests; every one is in the pytest step'"'"'s log' "$out"; then ok "twelve failures: nine annotations and one showing 9 of 12"
else bad "twelve failures: want nine annotations and one showing line" "$(grep '^::' "$out")"; fi
grep -qx 'failed: pytest on .python-version: tests/test_many.py::test_n00 failed, and 11 more' "$out" \
  && ok "twelve failures: failed: names the first and counts the rest" || bad "twelve failures: the failed: line" "$(tail -3 "$out")"
shape "twelve failures" "$out" "$rc"

pre pytest mixed; test_verdict x PYTEST=failure; out="$rt/out"
for want in 'file=tests/test_a.py,line=4::FAILED tests/test_a.py::test_helper' 'file=tests/test_a.py,line=18::FAILED tests/test_a.py::TestK::test_p\[a b\]' \
            'file=tests/test_a.py,line=22::ERROR tests/test_a.py::test_err'; do
  grep -q "^::error $want" "$out" && ok "a class, a parameter, a fixture's error: $want" || bad "no annotation $want" "$(grep '^::' "$out")"
done
pre pytest collect-error; test_verdict x PYTEST=failure; out="$rt/out"
grep -qx '::error file=tests/test_b.py,line=1::ERROR tests/test_b.py' "$out" && ok "a collection error is an annotation at the import" \
  || bad "no annotation for the collection error" "$(grep '^::' "$out")"
shape "a collection error" "$out" "$rc"

mkdir -p "$work/ws/app"; pre pytest one; d="$work/rt-$((n + 1))"
(cd "$work/ws/app" && env RUNNER_TEMP="$d" GITHUB_WORKSPACE="$work/ws" GITHUB_STEP_SUMMARY="$d/summary" TEST_MARGIN_SECONDS=120 PLINTH_SHA="$SHA" \
   SYNC=success PYTEST=failure EXTRA=skipped VERSIONS="" WEB=false PG=skipped LIMIT=10 LIMIT_OUTCOME=success bash -e "$work/test-verdict.sh") > "$d/out" 2>&1
n=$((n + 1))
grep -q '^::error file=app/tests/test_app.py,line=10::' "$d/out" && ok "under working-directory app, the annotation's file is from the repository's root" \
  || bad "the annotation's file ignores working-directory" "$(grep '^::' "$d/out")"

pre pytest one; printf '=== short test summary info ===\nFAILED tests/a,b:c.py::test_x - 100%% broken\n' > "$work/rt-$((n + 1))/pytest.log"; test_verdict x PYTEST=failure
grep -qx '::error file=tests/a%2Cb%3Ac.py::FAILED tests/a,b:c.py::test_x - 100%25 broken' "$rt/out" && ok "a comma, a colon and a percent sign are escaped" \
  || bad "the annotation's escaping" "$(grep '^::' "$rt/out")"
pre pytest one; printf '%s\n' '_____ test_db _____' '----- Captured stdout call -----' 'FAILED to connect to the database' \
  'tests/test_db.py:3: AssertionError' '===== short test summary info =====' 'FAILED tests/test_db.py::test_p[a - b] - assert False' > "$work/rt-$((n + 1))/pytest.log"
test_verdict x PYTEST=failure
if grep -qx 'failed: pytest on .python-version: tests/test_db.py::test_p\[a - b\] failed' "$rt/out" && [ "$(grep -c '^::error file=' "$rt/out")" = 1 ]; then
  ok "a test's own output saying FAILED is not a failed test, and an id with ' - ' in its parameters is kept whole"
else bad "captured output or a ' - ' in an id" "$(cat "$rt/out")"; fi
pre pytest one; : > "$work/rt-$((n + 1))/pytest.log"; test_verdict x PYTEST=failure
grep -qx 'failed: pytest on .python-version' "$rt/out" && grep -q "^next: read the pytest step's log" "$rt/out" && ! grep -q '^::error file=' "$rt/out" \
  && ok "no FAILED line in the log: the block names pytest and says to read its log" || bad "an empty log" "$(cat "$rt/out")"
shape "no FAILED line in the log" "$rt/out" "$rc"

pre extra one; test_verdict x VERSIONS="3.13 3.14" EXTRA=failure
grep -q '^::error file=tests/test_app.py,line=10::FAILED tests/test_app.py::test_add_negative - assert -2 == -3 (python 3.13)$' "$rt/out" \
  && grep -q '^next: run uv run --isolated --python 3.13 --with pytest pytest tests/test_app.py::test_add_negative' "$rt/out" \
  && ok "an extra version: the annotation and next: name the version" || bad "an extra version's failure" "$(cat "$rt/out")"
pre limit; test_verdict x PYTEST=failure
grep -q '^next: run uv run pytest --durations=20' "$rt/out" && grep -q '^failed: pytest on .python-version, stopped at the time limit' "$rt/out" \
  && ok "the time limit: the block says so and names the measuring step" || bad "the time limit's block" "$(tail -4 "$rt/out")"
pre none; test_verdict x
if [ "$rc" = 0 ] && ! grep -qE '^(::error|failed:|next:|more:)' "$rt/out"; then ok "a passing run: no block, no ::error"
else bad "a passing run printed a block or an error" "$(cat "$rt/out")"; fi
pre none
echo "not yet confirmed: changed lines ran under the tests, it did not run because an earlier step failed; a run that gets past that step confirms it" > "$work/rt-$((n + 1))/changed.verdict"
test_verdict x
grep -q '^::warning::not yet confirmed: changed lines' "$rt/out" && ok "with no fail line, a step that did not run is still a warning" \
  || bad "with no fail line the warning went" "$(cat "$rt/out")"

echo "-- ci / test: pytest's output is kept, its exit code too"
step test "pytest on .python-version" "$work/pytest.sh" 2>/dev/null || { bad "the pytest step has no name 'pytest on .python-version'"; : > "$work/pytest.sh"; }
mkdir -p "$work/bin"
cat > "$work/bin/uv" <<'SH'
#!/usr/bin/env bash
echo "FAILED tests/test_x.py::test_y - from the stub"
exit "${STUB_RC:-0}"
SH
chmod +x "$work/bin/uv"
for code in 1 124 137; do   # pytest's own codes; 124 is what timeout returns at the limit
  d="$work/p$code"; mkdir -p "$d"; date +%s > "$d/test.started"
  (cd "$d" && env PATH="$work/bin:$PATH" RUNNER_TEMP="$d" TEST_MARGIN_SECONDS=120 LIMIT=10 COV=skipped STUB_RC="$code" bash -e "$work/pytest.sh") > "$d/out" 2>&1
  got=$?
  if [ "$got" = "$code" ] && grep -qx 'FAILED tests/test_x.py::test_y - from the stub' "$d/out" && grep -qx 'FAILED tests/test_x.py::test_y - from the stub' "$d/pytest.log"; then
    ok "pytest exits $code: the step exits $code, and its output is in the log and in pytest.log"
  else bad "pytest exits $code: the step exited $got" "$(cat "$d/out")"; fi
  # 137 is the limit only at the deadline (pytest ignored the TERM); before it,
  # it is pytest's own code.
  if [ "$code" != 124 ]; then [ ! -e "$d/pytest.time-limit" ] && ok "exit $code before the deadline is not the time limit" || bad "exit $code was taken for the time limit"
  else [ -s "$d/pytest.time-limit" ] && grep -q '^::error::pytest stopped at the time limit' "$d/out" && ok "exit $code still fires the time-limit message" \
    || bad "exit $code: no time-limit message" "$(cat "$d/out")"; fi
done

echo "-- names, links and the page"
python3 - "$wf" <<'PY' && ok "every step of ci / test that runs pytest has a name" || bad "a step that runs pytest has no name"
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
start = lines.index("  test:")
end = next(i for i in range(start + 1, len(lines)) if re.match(r"^  [a-z]", lines[i]))
steps, cur = [], None
for l in lines[start:end]:
    if l.startswith("      - "):
        cur = [l]; steps.append(cur)
    elif cur is not None:
        cur.append(l)
nameless = [s[0].strip() for s in steps if re.search(r"\bpytest\b(?! on )", "\n".join(s)) and "run:" in "\n".join(s)
            and not any(re.match(r"^      (- )?  ?name: ", l) or l.startswith("      - name: ") for l in s)]
print("\n".join(nameless))
sys.exit(1 if nameless else 0)
PY
left="$(cd "$root" && grep -n 'blob/main' "$wf" .github/workflows/pr-review.yml scripts/closing-references.sh scripts/description-fields.py \
  scripts/conflict-markers.py scripts/floor-check.py scripts/pr-review/attest.py)"
[ -z "$left" ] && ok "no link python-ci.yml, pr-review.yml or a script they fetch prints points at blob/main" || bad "links still at blob/main" "$left"
python3 - "$doc" "$work/matrix" <<'PY' && ok "required-checks.md has When a check fails, a heading per required check" || bad "When a check fails lacks a heading"
import sys
text = open(sys.argv[1], encoding="utf-8").read().split("\n")
checks = sorted({l.split("\t")[0] for l in open(sys.argv[2], encoding="utf-8") if l.strip()})
if "## When a check fails" not in text:
    print("        | no '## When a check fails' section"); sys.exit(1)
at = text.index("## When a check fails")
end = next((i for i in range(at + 1, len(text)) if text[i].startswith("## ")), len(text))
missing = [c for c in checks if f"### {c}" not in text[at:end]]
if missing:
    print("        | " + ", ".join(missing))
sys.exit(1 if missing else 0)
PY

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
