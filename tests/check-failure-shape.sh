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
# Every required check has the shape (#1100 brought the last of them):
# `ci / pr-title`, `ci / diff-size` and `ci / floor-check`, which have no
# Verdict step, by running the steps that fail, and wanting exit 1. A row
# with no case fails here.
# `ci / test` also: pytest's FAILED and ERROR lines become at most nine
# annotations at file and line plus one "showing 9 of N" line, read from
# committed pytest output (tests/fixtures/pytest/); pytest's exit code, 124
# and 137 included, survives the `tee` that keeps its output.
# `ci / lint` and `ci / typecheck` (#1099): ruff's and mypy's findings
# become the same nine annotations and "showing 9 of N", read from committed
# output (tests/fixtures/ruff/, tests/fixtures/mypy/), and the tool's own
# error (exit 2) fails as "could not run", not as findings.
# A not yet confirmed line says one fact per sentence (#1156): "not yet
# confirmed: <what>. Why: <reason>. What confirms it: <run>.", pinned on
# every such line ci / test, ci / lint and ci / typecheck print here and on
# the changed-lines step's own lines.
# PLINTH_WF reads another copy of python-ci.yml (an older commit's, say).
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="${PLINTH_WF:-$root/.github/workflows/python-ci.yml}"
doc="$root/docs/reference/required-checks.md"
fx="$root/tests/fixtures/pytest"; fxr="$root/tests/fixtures/ruff"; fxm="$root/tests/fixtures/mypy"
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
# The web archetype's two (#614) are not in ruleset.json; a web project's
# ruleset requires them, and their pages have a heading here.
checks += ["ci / migrations", "ci / deploy-check"]
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

# shape <label> <file with the step's output> <exit> [<the exit wanted>]: the
# block's rules. A Verdict step exits 0; a check with no Verdict step
# (pr-title, diff-size, floor-check) fails in the step that prints it, 1.
shape() {
  local label="$1" out="$2" rc="$3" want="${4:-0}" why=() titled msg more anchor
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
  [ "$rc" = "$want" ] || why+=("exit $rc, want $want")
  if [ "${#why[@]}" = 0 ]; then ok "$label: one titled ::error, the block last, a link that exists, exit $want"
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
  printf 'not yet confirmed: changed lines ran under the tests. Why: it did not run because an earlier step failed. What confirms it: a run that gets past that step.\n' > "$d/changed.verdict"
  case "$1" in
    pytest) cp "$fx/${2:-one}.txt" "$d/pytest.log" ;;
    extra) { echo "── python 3.13"; cat "$fx/${2:-one}.txt"; } > "$d/extra.log" ;;
    limit) echo 10 > "$d/pytest.time-limit" ;;
  esac
}

step lint Verdict "$work/lint-verdict.sh"
step typecheck Verdict "$work/typecheck-verdict.sh"
# job_verdict <job> [VAR=value...]: that job's Verdict with every step
# passed, then the given outcomes; jpre leaves what the failed step left.
# The run's directory is the workspace, as on the runner: a GITHUB_WORKSPACE
# from the shell running this test (CI's own) would be another tree.
job_verdict() {
  local job="$1"; shift
  rt="$work/rt-$((++n))"; mkdir -p "$rt"; : > "$rt/summary"
  (cd "$rt" && env RUNNER_TEMP="$rt" GITHUB_WORKSPACE="$rt" GITHUB_STEP_SUMMARY="$rt/summary" PLINTH_SHA="$SHA" \
     SYNC=success CHECK=success FORMAT=success ZIZMOR=success MYPY=success "$@" bash -e "$work/$job-verdict.sh") > "$rt/out" 2>&1
  rc=$?
}
# jpre <rc file> <code> [<fixture> <as>]: the step's exit code and its kept output.
jpre() {
  local d="$work/rt-$((n + 1))"; mkdir -p "$d"; : > "$d/zizmor.kva"
  [ -z "${1:-}" ] || echo "$2" > "$d/$1"
  [ -z "${3:-}" ] || sed "s#@ROOT@#$(cd "$d" && pwd -P)#g" "$3" > "$d/$4"
}

fxg="$root/tests/fixtures/gitleaks"
for j in build secrets deps migrations deploy-check; do step "$j" Verdict "$work/$j-verdict.sh"; done
# jv <job> [VAR=value...]: that job's Verdict with every step passed (a web
# project for migrations and deploy-check, a pull request for deps), then the
# given values. The run's directory is the workspace, as on the runner.
jv() {
  local job="$1"; shift
  rt="$work/rt-$((++n))"; mkdir -p "$rt"; : > "$rt/summary"
  (cd "$rt" && env RUNNER_TEMP="$rt" GITHUB_WORKSPACE="$rt" GITHUB_STEP_SUMMARY="$rt/summary" PLINTH_SHA="$SHA" \
     SYNC=success BUILD=success SMOKE=success GITLEAKS=success WD=. WEB=true PG=success MISSING=success EMPTY=success ROWS=success DEPLOY=success \
     EVENT=pull_request SERVED=run REVIEW=success OSV=skipped SEVERITY=high ACTOR=someone VULNERABLE="" \
     "$@" bash -e "$work/$job-verdict.sh") > "$rt/out" 2>&1
  rc=$?
}
vuln_one='[{"change_type":"added","manifest":"uv.lock","ecosystem":"pip","name":"jinja2","version":"2.10","package_url":"pkg:pypi/jinja2@2.10","license":null,"source_repository_url":null,"vulnerabilities":[{"severity":"high","advisory_ghsa_id":"GHSA-462w-v97r-4m45","advisory_summary":"Jinja2 sandbox escape","advisory_url":"https://github.com/advisories/GHSA-462w-v97r-4m45"}]}]'

# The checks with no Verdict step: their steps, run as the runner would.
step pr-title "Check the title" "$work/title.sh"
step pr-title "The description closes no issue outside its closing line" "$work/description.sh"
step diff-size "Measure the reviewable diff" "$work/measure.sh"
step diff-size "No line the pull request adds is a merge conflict marker" "$work/markers.sh"
step diff-size "Name changes to the checks the description does not" "$work/names.py"
step diff-size "Ask an admin to approve a change to the checks" "$work/ask.py"
step floor-check "Floor check" "$work/floor.sh"
newrt() { rt="$work/rt-$((++n))"; mkdir -p "$rt"; : > "$rt/summary"; }
run_title() { newrt; (cd "$rt" && env GITHUB_STEP_SUMMARY="$rt/summary" PLINTH_SHA="$SHA" TITLE="$1" bash -e "$work/title.sh") > "$rt/out" 2>&1; rc=$?; }
gr="$work/gitrepo"; mkdir -p "$gr/src"; git -C "$gr" init -q -b main; git -C "$gr" config user.email t@example.com; git -C "$gr" config user.name t
git -C "$gr" config commit.gpgsign false; printf 'x = 1\n' > "$gr/src/m.py"; git -C "$gr" add -A; git -C "$gr" commit -qm base; gbase="$(git -C "$gr" rev-parse HEAD)"
seq 1 500 > "$gr/src/big.txt"; git -C "$gr" add -A; git -C "$gr" commit -qm big; ghead="$(git -C "$gr" rev-parse HEAD)"
# measure <max lines> <base> <head>: the measure step, in rt.
measure() { newrt; (cd "$gr" && env RUNNER_TEMP="$rt" GITHUB_STEP_SUMMARY="$rt/summary" PLINTH_SHA="$SHA" MAX_LINES="$1" EXCLUDE="" WORKDIR=. BASE_SHA="$2" HEAD_SHA="$3" bash -e "$work/measure.sh") > "$rt/out" 2>&1; rc=$?; }
# floor <the verdict lines a fake checker writes, as a Python string>.
floor() {
  newrt; mkdir -p "$rt/plinth"
  printf 'import sys\nopen(sys.argv[sys.argv.index("--verdicts") + 1], "w").write(%s)\nprint("  FAIL  x")\nsys.exit(1)\n' "$1" > "$rt/plinth/floor-check.py"
  (cd "$rt" && env RUNNER_TEMP="$rt" GITHUB_STEP_SUMMARY="$rt/summary" PLINTH_SHA="$SHA" GH_TOKEN=x WORKDIR=. EXPECT="" GITHUB_REPOSITORY=o/r bash -e "$work/floor.sh") > "$rt/out" 2>&1; rc=$?
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
    "ci / lint" | "ci / typecheck")
      case "$var" in
        SYNC) jpre; job_verdict "$job" SYNC=failure CHECK=skipped FORMAT=skipped ZIZMOR=skipped MYPY=skipped ;;
        CHECK) jpre ruff-check.rc 1 "$fxr/one.json" ruff-check.json; job_verdict lint CHECK=failure ;;
        FORMAT) jpre ruff-format.rc 1 "$fxr/format.log" ruff-format.log; job_verdict lint FORMAT=failure ;;
        ZIZMOR) jpre; job_verdict lint ZIZMOR=failure ;;
        MYPY) jpre mypy.rc 1 "$fxm/one.log" mypy.log; job_verdict typecheck MYPY=failure ;;
        *) bad "$check: steps.$sid.outcome ($var) has no case here: add one"; continue ;;
      esac
      shape "$check, steps.$sid failed" "$rt/out" "$rc" ;;
    "ci / build" | "ci / secrets" | "ci / deps" | "ci / migrations" | "ci / deploy-check")
      d="$work/rt-$((n + 1))"; mkdir -p "$d"
      case "$job:$var" in
        build:SYNC) jv build SYNC=failure BUILD=skipped SMOKE=skipped ;;
        build:BUILD) jv build BUILD=failure SMOKE=skipped ;;
        build:SMOKE) printf 'import\037mypkg\037dist/mypkg-1.0-py3-none-any.whl\n' > "$d/smoke.at"; jv build SMOKE=failure ;;
        secrets:GITLEAKS) echo 3 > "$d/gitleaks.rc"; cp "$fxg/one.json" "$d/gitleaks.json"; jv secrets GITLEAKS=failure ;;
        deps:REVIEW) jv deps REVIEW=failure VULNERABLE="$vuln_one" ;;
        deps:OSV) mkdir -p "$d/plinth-deps"; echo "fail: dependency review, 1 advisories at high or above on added dependency versions: jinja2 2.10 (GHSA-462w-v97r-4m45, CVSS 7.5)" > "$d/plinth-deps/deps.verdict"
                  jv deps SERVED=refused REVIEW=skipped OSV=failure ;;
        migrations:PG) jv migrations PG=failure SYNC=skipped MISSING=skipped EMPTY=skipped ROWS=skipped ;;
        migrations:SYNC) jv migrations SYNC=failure MISSING=skipped EMPTY=skipped ROWS=skipped ;;
        migrations:MISSING) jv migrations MISSING=failure EMPTY=skipped ROWS=skipped ;;
        migrations:EMPTY) jv migrations EMPTY=failure ROWS=skipped ;;
        migrations:ROWS) echo "fail: the base commit's rows survive this head's migrations: notes_note 3 -> 0" > "$d/rows.verdict"; jv migrations ROWS=failure ;;
        deploy-check:SYNC) jv deploy-check SYNC=failure DEPLOY=skipped ;;
        deploy-check:DEPLOY) printf '%s\n' "System check identified some issues:" "WARNINGS:" "?: (security.W004) You have not set a value for the SECURE_HSTS_SECONDS setting." > "$d/deploy.log"; jv deploy-check DEPLOY=failure ;;
        *) bad "$check: steps.$sid.outcome ($var) has no case here: add one"; continue ;;
      esac
      shape "$check, steps.$sid failed" "$rt/out" "$rc" ;;
    "ci / pr-title") run_title "Add a thing"; shape "$check, a title that is not Conventional Commits" "$rt/out" "$rc" 1 ;;
    "ci / diff-size") measure 400 "$gbase" "$ghead"; shape "$check, over the limit" "$rt/out" "$rc" 1 ;;
    # floor-check.py's own not yet confirmed lines (its SKIPs) keep their
    # form, `<what>; left to /plinth:floor-check`, which the say helper keys
    # on; the fake checker writes none, so the #1156 pin below does not read them.
    "ci / floor-check") floor "'fail: one thing; run /plinth:floor-check, which writes the fix\n' + 'fail: another\n'"
                        shape "$check, two FAILs" "$rt/out" "$rc" 1 ;;
    *) bad "$check has no case here: add one" ;;
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
echo "not yet confirmed: changed lines ran under the tests. Why: it did not run because an earlier step failed. What confirms it: a run that gets past that step." > "$work/rt-$((n + 1))/changed.verdict"
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

echo "-- ci / lint and ci / typecheck: the findings, named and annotated"
jpre ruff-check.rc 1 "$fxr/one.json" ruff-check.json; job_verdict lint CHECK=failure; out="$rt/out"
if [ "$(grep -c '^::error file=' "$out")" = 1 ] && grep -qx '::error file=src/one.py,line=1,col=8::F401 `os` imported but unused' "$out"; then
  ok "ruff check, one finding: one annotation at its file and line, with its code"
else bad "ruff check, one finding: want one annotation at src/one.py:1" "$(grep '^::' "$out")"; fi
grep -qx 'failed: ruff check: 1 finding, the first F401 at src/one.py:1' "$out" && grep -qx 'next: run uv run ruff check . here, fix what it names, and push' "$out" \
  && ok "ruff check: failed: names the finding, next: is the command that shows it" || bad "ruff check's block" "$(tail -3 "$out")"
jpre ruff-check.rc 1 "$fxr/many.json" ruff-check.json; job_verdict lint CHECK=failure; out="$rt/out"
if [ "$(grep -c '^::error file=src/many.py,line=[0-9]*,col=8::F401 ' "$out")" = 9 ] \
   && grep -qx "::notice::showing 9 of 12 ruff check findings; every one is in the ruff check step's log" "$out"; then ok "ruff check, twelve findings: nine annotations and one showing 9 of 12"
else bad "ruff check, twelve findings: want nine annotations and one showing line" "$(grep '^::' "$out")"; fi
shape "ruff check, twelve findings" "$out" "$rc"
jpre ruff-check.rc 2; job_verdict lint CHECK=failure; out="$rt/out"
grep -qx 'failed: ruff check could not run (exit 2): the tool'"'"'s own error, not a finding' "$out" && ! grep -q '^::error file=' "$out" \
  && grep -qx "next: run uv run ruff check . here and fix what stops it; its error is in the ruff check step's log" "$out" \
  && ok "ruff check exits 2: could not run, not findings" || bad "ruff check exits 2" "$(cat "$out")"
shape "ruff check could not run" "$out" "$rc"
for f in format format-before-0.9; do
  jpre ruff-format.rc 1 "$fxr/$f.log" ruff-format.log; job_verdict lint FORMAT=failure; out="$rt/out"
  if grep -qx 'failed: ruff format --check: 2 files not formatted: src/f1.py, src/f2.py' "$out" && grep -qx 'next: run uv run ruff format here, commit what it changes, and push' "$out" \
     && [ "$(grep -c '^::error file=src/f[12].py' "$out")" = 2 ]; then ok "ruff format --check ($f.log): the files named and annotated, next: is uv run ruff format"
  else bad "ruff format --check ($f.log)" "$(cat "$out")"; fi
done
jpre ruff-format.rc 2; job_verdict lint FORMAT=failure
grep -q '^failed: ruff format --check could not run (exit 2)' "$rt/out" && ok "ruff format --check exits 2: could not run" || bad "ruff format --check exits 2" "$(tail -3 "$rt/out")"
jpre ruff-check.rc 1 "$fxr/many.json" ruff-check.json; jpre ruff-format.rc 1 "$fxr/format.log" ruff-format.log; job_verdict lint CHECK=failure FORMAT=failure
[ "$(grep -c '^::error file=' "$rt/out")" = 9 ] && grep -qx '::notice::2 more files ruff format would change are not annotated; every one is in the ruff format --check step'"'"'s log' "$rt/out" \
  && grep -q '^failed: ruff check: 12 findings' "$rt/out" && ok "ruff check and format both fail: nine annotations in the job, the first failure in the block" \
  || bad "ruff check and format both fail" "$(grep -E '^(::|failed:)' "$rt/out")"

jpre mypy.rc 1 "$fxm/one.log" mypy.log; job_verdict typecheck MYPY=failure; out="$rt/out"
if [ "$(grep -c '^::error file=' "$out")" = 1 ] && grep -qxF '::error file=src/m1.py,line=2::Incompatible return value type (got "int", expected "str")  [return-value]' "$out"; then
  ok "mypy, one error: one annotation at its file and line, with its code"
else bad "mypy, one error: want one annotation at src/m1.py:2" "$(grep '^::' "$out")"; fi
grep -qx 'failed: mypy: 1 error, the first at src/m1.py:2 \[return-value\]' "$out" && grep -qx 'next: run uv run mypy . here, fix what it names, and push' "$out" \
  && ok "mypy: failed: names the error and its code, next: is the command that shows it" || bad "mypy's block" "$(tail -3 "$out")"
jpre mypy.rc 1 "$fxm/many.log" mypy.log; job_verdict typecheck MYPY=failure; out="$rt/out"
if [ "$(grep -c '^::error file=src/m12.py,line=[0-9]*::Incompatible' "$out")" = 9 ] \
   && grep -qx "::notice::showing 9 of 12 mypy errors; every one is in the mypy step's log" "$out"; then ok "mypy, twelve errors: nine annotations and one showing 9 of 12"
else bad "mypy, twelve errors: want nine annotations and one showing line" "$(grep '^::' "$out")"; fi
shape "mypy, twelve errors" "$out" "$rc"
jpre mypy.rc 2 /dev/stdin mypy.log <<<"mypy: can't read file 'nonexist': No such file or directory"; job_verdict typecheck MYPY=failure; out="$rt/out"
grep -q '^failed: mypy could not run (exit 2)' "$out" && ! grep -q '^::error file=' "$out" && ok "mypy exits 2: could not run, not findings" || bad "mypy exits 2" "$(cat "$out")"
shape "mypy could not run" "$out" "$rc"
jpre mypy.rc 2 "$fxm/syntax.log" mypy.log; job_verdict typecheck MYPY=failure; out="$rt/out"
grep -qx 'failed: mypy: 1 error, the first at src/bad.py:1 \[syntax\]' "$out" && grep -q '^::error file=src/bad.py,line=1::' "$out" \
  && ok "mypy exits 2 on a syntax error: an error at its file and line, not could not run" || bad "mypy's syntax error" "$(cat "$out")"
jpre ruff-check.rc 1 "$fxr/syntax.json" ruff-check.json; job_verdict lint CHECK=failure
grep -qx 'failed: ruff check: 2 findings, the first invalid-syntax at src/bad.py:1' "$rt/out" && grep -q '^::error file=src/bad.py,line=1,col=7::invalid-syntax Expected' "$rt/out" \
  && ok "a syntax error: ruff's invalid-syntax, named and annotated at its line" || bad "ruff's syntax error" "$(grep -E '^(::|failed:)' "$rt/out")"
# A comma in a file's name (#1172's third-party review): ruff's GitHub format
# writes it unescaped in file=; its JSON keeps the name whole.
jpre ruff-check.rc 1 "$fxr/comma.json" ruff-check.json; job_verdict lint CHECK=failure
grep -qx '::error file=src/a%2Cb.py,line=1,col=8::F401 `os` imported but unused' "$rt/out" && grep -qx 'failed: ruff check: 1 finding, the first F401 at src/a,b.py:1' "$rt/out" \
  && ok "a comma in the file's name: the whole name, escaped in file=" || bad "a comma in the file's name" "$(grep -E '^(::|failed:)' "$rt/out")"
printf 'not json\n' > "$work/broken.json"; jpre ruff-check.rc 1 "$work/broken.json" ruff-check.json; job_verdict lint CHECK=failure
grep -qx 'failed: ruff check' "$rt/out" && ! grep -q '^::error file=' "$rt/out" && ok "output that is not JSON: plain failed: ruff check, no annotation" \
  || bad "output that is not JSON" "$(grep -E '^(::|failed:)' "$rt/out")"
mkdir -p "$work/ws/app"; jpre mypy.rc 1 "$fxm/one.log" mypy.log; d="$work/rt-$((n + 1))"
(cd "$work/ws/app" && env RUNNER_TEMP="$d" GITHUB_WORKSPACE="$work/ws" GITHUB_STEP_SUMMARY="$d/summary" PLINTH_SHA="$SHA" SYNC=success MYPY=failure bash -e "$work/typecheck-verdict.sh") > "$d/out" 2>&1
n=$((n + 1))
grep -q '^::error file=app/src/m1.py,line=2::' "$d/out" && ok "under working-directory app, mypy's annotation file is from the repository's root" \
  || bad "mypy's annotation file ignores working-directory" "$(grep '^::' "$d/out")"
# ruff's JSON names the file by its absolute path: under
# working-directory app it is app/... from the root; with a workspace that
# does not hold it (CI's own, before #1172's fix), never the absolute path.
mkdir -p "$work/ws2/app"; d="$work/rt-$((n + 1))"; mkdir -p "$d"; : > "$d/zizmor.kva"; echo 1 > "$d/ruff-check.rc"
sed "s#@ROOT@#$(cd "$work/ws2/app" && pwd -P)#g" "$fxr/one.json" > "$d/ruff-check.json"; grep -q "\"filename\": \"/" "$d/ruff-check.json" || bad "the fixture's path is not absolute"
(cd "$work/ws2/app" && env RUNNER_TEMP="$d" GITHUB_WORKSPACE="$work/ws2" GITHUB_STEP_SUMMARY="$d/summary" PLINTH_SHA="$SHA" \
   SYNC=success CHECK=failure FORMAT=success ZIZMOR=success bash -e "$work/lint-verdict.sh") > "$d/out" 2>&1
n=$((n + 1))
grep -qx '::error file=app/src/one.py,line=1,col=8::F401 `os` imported but unused' "$d/out" && grep -qx 'failed: ruff check: 1 finding, the first F401 at app/src/one.py:1' "$d/out" \
  && ok "ruff's absolute path under working-directory app: app/src/one.py from the root, in the annotation and in failed:" || bad "ruff's absolute path under app" "$(grep -E '^(::|failed:)' "$d/out")"
d="$work/rt-$((n + 1))"; mkdir -p "$d"; : > "$d/zizmor.kva"; echo 1 > "$d/ruff-check.rc"
sed "s#@ROOT@#$(cd "$d" && pwd -P)#g" "$fxr/one.json" > "$d/ruff-check.json"
(cd "$d" && env RUNNER_TEMP="$d" GITHUB_WORKSPACE="$work/ws2" GITHUB_STEP_SUMMARY="$d/summary" PLINTH_SHA="$SHA" \
   SYNC=success CHECK=failure FORMAT=success ZIZMOR=success bash -e "$work/lint-verdict.sh") > "$d/out" 2>&1
n=$((n + 1))
if grep -q '^::error file=src/one.py,line=1' "$d/out" && ! grep -qE '^(::error file=|failed: .* at )/' "$d/out"; then ok "an absolute path outside the workspace: from the working directory, never absolute"
else bad "an absolute path outside the workspace" "$(grep -E '^(::|failed:)' "$d/out")"; fi

for j in lint typecheck; do
  jpre; job_verdict "$j"
  if [ "$rc" = 0 ] && ! grep -qE '^(::error|failed:|next:|more:)' "$rt/out"; then ok "ci / $j passing: no block, no ::error"
  else bad "ci / $j passing printed a block or an error" "$(cat "$rt/out")"; fi
done

echo "-- ci / lint and ci / typecheck: the steps keep the tool's exit code"
cat > "$work/bin/uv" <<'SH'
#!/usr/bin/env bash
case " $* " in *" --output-format=json "*) echo '[{"code": "F401", "filename": "x.py", "location": {"row": 1, "column": 1}, "message": "stub"}]'; exit 0 ;; esac
echo "x.py:1: error: from the stub  [misc]"
exit "${STUB_RC:-0}"
SH
for s in "lint check ruff-check" "lint format ruff-format" "typecheck mypy mypy"; do
  read -r j id f <<<"$s"; step "$j" "$id" "$work/$id.sh"
  for code in 0 1 2; do
    d="$work/s-$id-$code"; mkdir -p "$d"
    (cd "$d" && env PATH="$work/bin:$PATH" RUNNER_TEMP="$d" STUB_RC="$code" bash -e "$work/$id.sh") > "$d/out" 2>&1; got=$?
    gh=0; [ "$id" != check ] || { [ -s "$d/ruff-check.json" ] && gh=1; }
    if [ "$got" = "$code" ] && [ "$(cat "$d/$f.rc" 2>/dev/null)" = "$code" ] && { [ "$id" != check ] || [ "$gh" = "$([ "$code" = 1 ] && echo 1 || echo 0)" ]; } \
       && ! grep -q '^::error' "$d/out"; then ok "ci / $j, steps.$id: the tool exits $code, the step exits $code and records it, no annotation in its own log"
    else bad "ci / $j, steps.$id: the tool exits $code, the step exited $got" "$(cat "$d/out")"; fi
  done
done

echo "-- ci / secrets: each secret at its file and line, its value never printed"
# gitleaks names a file from the repository's root (measured: run in app/,
# it reports app/config.py), so the annotation uses it as it is.
d="$work/rt-$((n + 1))"; mkdir -p "$d"; echo 3 > "$d/gitleaks.rc"; sed 's#"File": "config.py"#"File": "app/config.py"#' "$fxg/one.json" > "$d/gitleaks.json"; jv secrets GITLEAKS=failure; out="$rt/out"
grep -qx '::error file=app/config.py,line=1::gitleaks rule aws-access-token matched a secret here in commit b7ba5b11f925, so revoke it where it was issued and remove it from the branch history' "$out" \
  && grep -qx 'failed: gitleaks found 1 secret in the history, the first (aws-access-token) in app/config.py at line 1 of commit b7ba5b11f925' "$out" \
  && ok "one secret: an annotation at its file and line from the root, and failed: names rule, file, line and commit" || bad "one secret" "$(grep -E '^(::|failed:|next:)' "$out")"
# Twelve findings whose report carries the secret itself, as without --redact.
d="$work/rt-$((n + 1))"; mkdir -p "$d"; echo 3 > "$d/gitleaks.rc"; canary="plinth-canary-$RANDOM-not-a-secret"
python3 -c 'import json,sys; x=json.load(open(sys.argv[1]))[0]; json.dump([dict(x, File=f"src/m{i:02}.py", StartLine=i+1, Secret=sys.argv[2], Match="key = "+sys.argv[2]) for i in range(12)], open(sys.argv[3],"w"))' "$fxg/one.json" "$canary" "$d/gitleaks.json"
jv secrets GITLEAKS=failure; out="$rt/out"
if [ "$(grep -c '^::error file=src/m[0-9]*.py,line=' "$out")" = 9 ] && grep -qx "::notice::showing 9 of 12 secrets gitleaks found; every one is in the secret detection step's log" "$out"; then ok "twelve secrets: nine annotations and one showing 9 of 12"
else bad "twelve secrets" "$(grep '^::' "$out")"; fi
! grep -qF "$canary" "$out" "$rt/summary" && ok "the secret's value is not in the log or the summary, even when the report carries it" || bad "the secret's value was printed" "$(grep -F "$canary" "$out" "$rt/summary")"
shape "twelve secrets" "$out" "$rc"
d="$work/rt-$((n + 1))"; mkdir -p "$d"; echo 1 > "$d/gitleaks.rc"; jv secrets GITLEAKS=failure; out="$rt/out"
grep -qx 'failed: gitleaks could not run (exit 1), its own error and not a finding' "$out" && ! grep -q '^::error file=' "$out" && ok "gitleaks exits 1: could not run, not a secret" || bad "gitleaks exits 1" "$(cat "$out")"
shape "gitleaks could not run" "$out" "$rc"

echo "-- ci / deps: an advisory and a review that could not run are two causes"
jv deps REVIEW=failure VULNERABLE="$vuln_one"; out="$rt/out"
grep -qx 'failed: dependency review, 1 added dependency version with an advisory at high or above: jinja2 2.10 (GHSA-462w-v97r-4m45)' "$out" && grep -q "^next: raise each named package past its advisory's fixed version" "$out" \
  && ok "the review found an advisory: failed: names the package, version and advisory; next: raises it" || bad "the review's advisory" "$(tail -3 "$out")"
jv deps REVIEW=failure VULNERABLE=""; out="$rt/out"
grep -qx "failed: dependency review could not run (its error is in the dependency review step's log)" "$out" && grep -q '^next: re-run this job' "$out" \
  && ok "the review failed with no vulnerable change: could not run, re-run" || bad "the review could not run" "$(tail -3 "$out")"
shape "the review could not run" "$out" "$rc"
jv deps SERVED=refused REVIEW=skipped OSV=failure; out="$rt/out"
grep -q '^failed: dependency review could not run, osv-scanner did not compare' "$out" && grep -q "^next: re-run this job, and if it fails again read the error in the osv-scanner step's log" "$out" \
  && ok "refused and osv-scanner left no verdict: could not run" || bad "osv-scanner could not run" "$(tail -3 "$out")"
jv deps ACTOR='dependabot[bot]'
grep -qx -- '- not yet confirmed: CodeQL on this head. Why: Dependabot pushed it, and CodeQL does not analyse a head Dependabot pushed. What confirms it: the analysis of `main` after the merge.' "$rt/summary" \
  && ok "a head Dependabot pushed: CodeQL's line, one fact per sentence" || bad "Dependabot's CodeQL line" "$(cat "$rt/summary")"

echo "-- ci / build, ci / migrations, ci / deploy-check: the cause and its own next step"
d="$work/rt-$((n + 1))"; mkdir -p "$d"; printf 'install\037\037dist/mypkg-1.0.tar.gz\n' > "$d/smoke.at"; jv build SMOKE=failure
grep -qx 'failed: install smoke, dist/mypkg-1.0.tar.gz did not install in a clean venv' "$rt/out" && ok "an install that failed: the artifact, though the module field is empty" || bad "the smoke's install" "$(tail -3 "$rt/out")"
d="$work/rt-$((n + 1))"; mkdir -p "$d"; printf 'import\037install\037dist/mypkg-1.0.tar.gz\n' > "$d/smoke.at"; jv build SMOKE=failure
grep -qx 'failed: install smoke, import install from dist/mypkg-1.0.tar.gz failed in a clean venv' "$rt/out" && ok "a module named install is an import, not the install step" || bad "a module named install" "$(tail -3 "$rt/out")"
d="$work/rt-$((n + 1))"; mkdir -p "$d"; echo "something else" > "$d/smoke.at"; jv build SMOKE=failure
grep -q "^next: read the install smoke step's log" "$rt/out" && shape "an unknown smoke label" "$rt/out" "$rc" || bad "an unknown smoke label printed no next:" "$(cat "$rt/out")"
d="$work/rt-$((n + 1))"; mkdir -p "$d"; echo noroot > "$d/smoke.at"; jv build SMOKE=failure
grep -q '^next: add a \[build-system\] table' "$rt/out" && ! grep -q '^::error::' "$rt/out" && ok "no root wheel: one cause, the Verdict's annotation, a [build-system] next step" || bad "no root wheel" "$(cat "$rt/out")"
d="$work/rt-$((n + 1))"; mkdir -p "$d"; printf 'import\037mypkg\037dist/mypkg-1.0-py3-none-any.whl\n' > "$d/smoke.at"; jv build SMOKE=failure
grep -qx 'failed: install smoke, import mypkg from dist/mypkg-1.0-py3-none-any.whl failed in a clean venv' "$rt/out" && grep -q "^next: run uv build here, then uv run --isolated --no-project --with dist/mypkg-1.0-py3-none-any.whl python -c 'import mypkg'" "$rt/out" \
  && ok "an import that failed: the module and the artifact, and the command that repeats it" || bad "the smoke's import" "$(tail -3 "$rt/out")"
d="$work/rt-$((n + 1))"; mkdir -p "$d"; echo "fail: the base commit's rows survive this head's migrations, tests/migration_rows.json holds a model migrate rewrites (its name is in this step's log)" > "$d/rows.verdict"; jv migrations ROWS=failure
grep -q '^next: take the model the rows step names out of tests/migration_rows.json' "$rt/out" && ok "rows that hold a model migrate rewrites: take it out" || bad "the rows' model" "$(tail -3 "$rt/out")"
d="$work/rt-$((n + 1))"; mkdir -p "$d"; echo "not yet confirmed: the base commit's rows survive this head's migrations. Why: the base commit has no tests/migration_rows.json. What confirms it: a base that has it." > "$d/rows.verdict"; jv migrations
[ "$rc" = 0 ] && ! grep -qE '^(failed:|::error)' "$rt/out" && ok "a base with no rows file: not yet confirmed, no block" || bad "no rows file" "$(cat "$rt/out")"
d="$work/rt-$((n + 1))"; mkdir -p "$d"; printf '%s\n' "?: (security.W004) You have not set a value for the SECURE_HSTS_SECONDS setting." "?: (security.W008) Your SECURE_SSL_REDIRECT setting is not set to True." "?: (security.W004) again" "?: (oauth2_provider.E001) a setting" > "$d/deploy.log"; jv deploy-check DEPLOY=failure
grep -qx 'failed: manage.py check --deploy: 3 issues, the first security.W004' "$rt/out" && grep -qF 'next: run DJANGO_SECRET_KEY=$(openssl rand -hex 32) DJANGO_ALLOWED_HOSTS=example.invalid uv run python manage.py check --deploy' "$rt/out" \
  && ok "deploy issues: counted once each, an app label with a digit included, the first named; next: uses a random 64-character key, as the step does (a short one is security.W009 itself)" || bad "deploy warnings" "$(tail -3 "$rt/out")"
for j in build secrets deps migrations deploy-check; do
  jv "$j"
  if [ "$rc" = 0 ] && ! grep -qE '^(::error|failed:|next:|more:)' "$rt/out"; then ok "ci / $j passing: no block, no ::error"
  else bad "ci / $j passing printed a block or an error" "$(cat "$rt/out")"; fi
done
jv migrations WEB=false; grep -qx 'pass: migrations, does not apply (the web input is false: not a web project)' "$rt/out" && [ "$rc" = 0 ] && ok "not a web project: migrations passes as not applying" || bad "migrations off the web archetype" "$(cat "$rt/out")"

echo "-- ci / pr-title, ci / diff-size, ci / floor-check: one cause, one annotation"
run_title "fix: a thing (#12)"
grep -qx 'failed: PR title ends in a number: fix: a thing (#12)' "$rt/out" && grep -qx "next: remove the trailing (#N) and name the issue on the description's closing line" "$rt/out" \
  && shape "a title ending in a number" "$rt/out" "$rc" 1 || bad "a title ending in a number" "$(cat "$rt/out")"
# The description: closing-references.sh's failure is the step's one
# annotation, not one of its own as well.
mkdir -p "$work/ghbin"; cat > "$work/ghbin/gh" <<'SH'
#!/usr/bin/env bash
[[ "$*" == *"pullRequests(first: 1"* ]] && { echo '{"data":{"repository":{"issues":{"nodes":[{"number":90}]},"pullRequests":{"nodes":[{"number":91}]}}}}'; exit 0; }
printf '%s' '{"data":{"repository":{"pullRequest":{"body":"The two fixes #65 decided.\n\n## What I checked myself\n\nRan it.\n\nReview: fresh-context","closingIssuesReferences":{"nodes":[{"number":65,"repository":{"nameWithOwner":"o/r"}}],"pageInfo":{"hasNextPage":false}}}}}}'
SH
chmod +x "$work/ghbin/gh"; newrt; mkdir -p "$rt/plinth-closing"
cp "$root/scripts/closing-references.sh" "$root/scripts/closing-references.py" "$root/scripts/description-fields.py" "$rt/plinth-closing/"
(cd "$rt" && env PATH="$work/ghbin:$PATH" RUNNER_TEMP="$rt" GITHUB_STEP_SUMMARY="$rt/summary" PLINTH_SHA="$SHA" REPO=o/r GH_TOKEN=x EVENT_NAME=pull_request PR=7 FETCH=success bash "$work/description.sh") > "$rt/out" 2>&1; rc=$?
if [ "$(grep -c '^::error' "$rt/out")" = 1 ] && grep -q "^failed: #7's description: " "$rt/out" && grep -q '^next: reword the sentence' "$rt/out"; then ok "a closing keyword in a sentence: closing-references.sh's message is the one annotation"
else bad "the description's failure: want one ::error, closing-references.sh's" "$(grep -E '^(::|failed:|next:)' "$rt/out")"; fi
shape "a closing keyword in a sentence" "$rt/out" "$rc" 1
measure 400 "$gbase" "$ghead"
if grep -q "^next: split the change into pull requests that land one after another, .*and do not shorten docs, docstrings or tests to fit$" "$rt/out" \
   && grep -qx 'Split the change; do not shorten docs, docstrings or tests to fit.' "$rt/summary"; then ok "over the limit: split the change, do not shorten docs, docstrings or tests to fit (#1144)"
else bad "over the limit: the split advice" "$(tail -3 "$rt/out"; cat "$rt/summary")"; fi
measure 0 "$gbase" "$ghead"; [ "$rc" = 0 ] && ! grep -q '^::error' "$rt/out" && ok "max-diff-lines 0: measured, no annotation" || bad "max-diff-lines 0" "$(cat "$rt/out")"
# Runs 44675262391 and 44495014302 of a project's template update: the head
# was not fetched, and one cause printed three of plinth's annotations, one
# from each step that read the diff. Now the measure step's is the only one.
measure 400 "$gbase" 4fa0da4bae525838f4702c93b4e2eba82143493e; one="$rt"; m_rc=$rc
(cd "$gr" && env RUNNER_TEMP="$one" GITHUB_STEP_SUMMARY="$one/summary" PLINTH_SHA="$SHA" FETCH=success MEASURE=failure BASE_SHA="$gbase" HEAD_SHA=4fa0da4bae525838f4702c93b4e2eba82143493e bash "$work/markers.sh") > "$one/markers" 2>&1; k_rc=$?
(cd "$gr" && env RUNNER_TEMP="$one" GITHUB_STEP_SUMMARY="$one/summary" PLINTH_SHA="$SHA" MEASURE=failure BODY="" BASE_SHA="$gbase" HEAD_SHA=4fa0da4bae525838f4702c93b4e2eba82143493e CHANGES_FILE="$one/changes.json" WEB=false python3 "$work/names.py") > "$one/names" 2>&1; c_rc=$?
(cd "$gr" && env RUNNER_TEMP="$one" GITHUB_STEP_SUMMARY="$one/summary" PLINTH_SHA="$SHA" MEASURE=failure EVENT=pull_request REPO=o/r RUN_ID=1 NUMBER=7 HEAD_SHA=4fa0da4bae525838f4702c93b4e2eba82143493e HEAD_REF=x HEAD_REPO=o/r CHANGES_FILE="$one/changes.json" python3 "$work/ask.py") > "$one/ask" 2>&1; a_rc=$?
all="$(cat "$one/out" "$one/markers" "$one/names" "$one/ask")"
if [ "$(grep -c '^::error' <<<"$all")" = 1 ] && [ "$(grep -c '^::warning' <<<"$all")" = 0 ] && [ "$m_rc/$k_rc/$c_rc/$a_rc" = 1/0/0/0 ]; then
  ok "the merge base unreadable (runs 44675262391, 44495014302): one ::error in the job, the measure step's, which alone fails"
else bad "the merge base unreadable: want one ::error and exits 1/0/0/0, got $m_rc/$k_rc/$c_rc/$a_rc" "$(grep -E '^(::|failed:)' <<<"$all")"; fi
shape "the merge base unreadable" "$one/out" "$m_rc" 1
[ "$(grep -c '^- not yet confirmed: .*Why: the diff could not be computed, as the measure step says\.' "$one/summary")" = 3 ] \
  && ok "... and the summary says the three other reads are not yet confirmed, for that reason" || bad "the summary of the unreadable diff" "$(cat "$one/summary")"
# Measure passed: a step that cannot read the diff still fails, never passes.
newrt; (cd "$gr" && env RUNNER_TEMP="$rt" GITHUB_STEP_SUMMARY="$rt/summary" PLINTH_SHA="$SHA" MEASURE=success BODY="" BASE_SHA=0000000000000000000000000000000000000000 HEAD_SHA="$ghead" CHANGES_FILE="$rt/changes.json" WEB=false python3 "$work/names.py") > "$rt/out" 2>&1; rc=$?
shape "measure passed, the name step's git failed: its own block" "$rt/out" "$rc" 1
newrt; (cd "$gr" && env RUNNER_TEMP="$rt" GITHUB_STEP_SUMMARY="$rt/summary" PLINTH_SHA="$SHA" MEASURE=success EVENT=pull_request REPO=o/r RUN_ID=1 NUMBER=7 HEAD_SHA=1111111111111111111111111111111111111111 HEAD_REF=x HEAD_REPO=o/r CHANGES_FILE="$rt/none.json" python3 "$work/ask.py") > "$rt/out" 2>&1; rc=$?
shape "measure passed, the list of changes missing: the approval step fails" "$rt/out" "$rc" 1
floor "'fail: ' + 'y' * 400 + '; run /plinth:floor-check, which writes the fix\n'"
grep -qE '^::error title=ci / floor-check::floor-check: 1 FAIL, the first: y+\.\.\. — run /plinth:floor-check here' "$rt/out" && shape "a 400-character FAIL" "$rt/out" "$rc" 1 \
  || bad "a long FAIL is not cut with the next step kept" "$(grep '^::' "$rt/out")"

echo "-- not yet confirmed: one fact per sentence (#1156)"
# More of the lines: the changed-lines step itself, run with uv and git
# failing (no pull request; pytest stopped; coverage recorded nothing), and
# lint's zizmor lines (it did not finish; an advisory).
step test "Changed lines under the tests" "$work/changed.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$work/bin/uv"; chmod +x "$work/bin/uv"
for c in "PR= COV=success PYTEST=success" "PR=7 COV=failure PYTEST=failure" "PR=7 COV=success PYTEST=success"; do
  d="$work/rt-$((++n))"; mkdir -p "$d"
  (cd "$d" && env PATH="$work/bin:$PATH" RUNNER_TEMP="$d" GIT_DIR="$d/no-git" $c bash -e "$work/changed.sh") > "$d/out" 2>&1
  cat "$d/changed.verdict" >> "$d/out" 2>/dev/null
done
jpre; rm "$work/rt-$((n + 1))/zizmor.kva"; job_verdict lint
jpre; echo "GHSA-mrrh-fwg8-r2c3 for tj-actions/changed-files@v35 (.github/workflows/ci.yml:9)" > "$work/rt-$((n + 1))/zizmor.kva"; job_verdict lint
# Every line, whether a run printed it or the step left it for the summary.
nyc="$(cat "$work"/rt-*/out "$work"/rt-*/summary 2>/dev/null | sed -n 's/^\(- \|::warning::\)\{0,1\}\(not yet confirmed: .*\)$/\2/p' | sort -u)"
bad_form="$(grep -vE '^not yet confirmed: .+\. Why: .+\. What confirms it: .+\.$' <<<"$nyc" | grep -v '^$')"
shapes="$(grep -oE '^not yet confirmed: (changed lines ran under the tests|no published advisory|GHSA|[^.]*)\. Why: [a-z]+ [a-z]+' <<<"$nyc" | sort -u | wc -l | tr -d ' ')"
if [ -z "$bad_form" ] && [ "$shapes" -ge 6 ]; then ok "every not yet confirmed line read ($(grep -c . <<<"$nyc"), $shapes kinds) is what. Why: reason. What confirms it: run."
else bad "not yet confirmed lines not in the form, or too few kinds read ($shapes)" "$bad_form"; fi
grep -q '^not yet confirmed: changed lines ran under the tests. Why: coverage recorded no line' <<<"$nyc" \
  && grep -q '^not yet confirmed: ruff check. Why: it did not run because an earlier step failed. What confirms it: a run that gets past that step.$' <<<"$nyc" \
  && grep -q '^not yet confirmed: GHSA-mrrh-fwg8-r2c3 for tj-actions/changed-files@v35 (.github/workflows/ci.yml:9). Why: ' <<<"$nyc" \
  && ok "the changed-lines step's, a stopped step's and an advisory's lines were among them" || bad "a kind of line was not read" "$nyc"

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
