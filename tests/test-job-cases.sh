#!/usr/bin/env bash
# `ci / test`'s time limit and where it runs coverage (#941). The steps are
# extracted from python-ci.yml and run as the runner runs them, with `uv`
# stubbed: the stub logs its arguments, and a pytest it runs sleeps
# $STUB_SLEEP seconds, then exits $STUB_RC. So the rule tested is the rule
# shipped: on a push pytest runs without coverage, on a pull request under
# it; the job's limit is the test-timeout-minutes input; pytest and each
# extra version stop at what is left of it less the margin kept for the steps
# after them, and Verdict says it was the limit, not a test.
#
# Measured on GitHub before this was built (probe runs listed in #941's
# pull request): a step's own timeout-minutes kills the step's shell only, and the
# pytest it started kept running into the later steps; `+` is not an
# expression operator; 0 and 400 are accepted as timeout-minutes without a
# word. Hence coreutils `timeout` in the shell and a range check of our own.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="$root/.github/workflows/python-ci.yml"
command -v timeout >/dev/null || { echo "  FAIL  coreutils timeout is needed (brew install coreutils)"; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-job.XXXXXX")" || { echo "test-job-cases: could not make a temp folder" >&2; exit 1; }
trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        | /'; }

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
# The test job's text, from `  test:` to the next job.
job_text() {
  python3 - "$wf" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
j = lines.index("  test:")
end = next(i for i in range(j + 1, len(lines)) if re.match(r"^  [a-z]", lines[i]))
print("\n".join(lines[j:end]))
PY
}
for s in limit pytest extra Verdict; do
  name="$s"; [ "$s" = limit ] && name="Time limit"; [ "$s" = pytest ] && name="pytest on .python-version"; [ "$s" = extra ] && name="Also on the extra Python versions"
  job_step test "$name" > "$tmp/$s.sh" || { echo "  FAIL  test / $name: step not found in python-ci.yml"; exit 1; }
done
job_step test "Changed lines under the tests" > "$tmp/changed.sh" || { echo "  FAIL  the changed-lines step was not found"; exit 1; }
job_text > "$tmp/job.yml"

echo "-- the job's own limit is the input"
grep -qx '    timeout-minutes: ${{ inputs.test-timeout-minutes }}' "$tmp/job.yml" \
  && ok "the test job's timeout-minutes is the test-timeout-minutes input" \
  || bad "the test job's timeout-minutes is not \${{ inputs.test-timeout-minutes }}" "$(grep -n timeout-minutes "$tmp/job.yml")"
python3 - "$wf" <<'PY' && ok "test-timeout-minutes is a number input whose default is 10" || bad "test-timeout-minutes is not a number input defaulting to 10"
import re, sys
text = open(sys.argv[1], encoding="utf-8").read().split("\njobs:\n", 1)[0]
m = re.search(r"^      test-timeout-minutes:\n((?:        .*\n|\s*\n)+)", text, re.M)
sys.exit(not (m and re.search(r"^        type: number$", m.group(1), re.M) and re.search(r"^        default: 10$", m.group(1), re.M)))
PY
margin="$(sed -n 's/^      TEST_MARGIN_SECONDS: "\([0-9]*\)"$/\1/p' "$tmp/job.yml")"
[ -n "$margin" ] && ok "the margin kept for the steps after pytest is named: $margin s" \
  || { bad "the job names no TEST_MARGIN_SECONDS"; margin=120; }
# The first step records the start, before the checkout.
first="$(grep -m1 -E '^      - (name|id|uses):' "$tmp/job.yml")"
[ "$first" = "      - name: Time limit" ] && ok "Time limit is the job's first step" || bad "the job's first step is not Time limit" "$first"

mkdir -p "$tmp/bin"
cat > "$tmp/bin/uv" <<'SH'
#!/usr/bin/env bash
echo "uv $*" >> "$UVLOG"
case " $* " in
  *" python - "*) exit 10 ;;   # coverage's configuration names no source
  *pytest*) [ "${STUB_SLEEP:-0}" = 0 ] || exec sleep "$STUB_SLEEP"; exit "${STUB_RC:-0}" ;;
esac
exit 0
SH
chmod +x "$tmp/bin/uv"

# run <step> [VAR=value...]: runs a step as the runner does, in a fresh
# RUNNER_TEMP unless KEEP=1; sets $out, $rc and $summary.
n=0
fresh() { n=$((n+1)); rt="$tmp/rt$n"; mkdir -p "$rt"; : > "$rt/uv.log"; }
run() {
  local s="$1"; shift
  [ -n "${KEEP:-}" ] || fresh
  : > "$rt/summary"
  rc=0
  out="$(cd "$tmp" && env PATH="$tmp/bin:$PATH" RUNNER_TEMP="$rt" GITHUB_STEP_SUMMARY="$rt/summary" UVLOG="$rt/uv.log" \
    TEST_MARGIN_SECONDS="$margin" "$@" bash --noprofile --norc -eo pipefail "$tmp/$s.sh" 2>&1)" || rc=$?
  summary="$(cat "$rt/summary")"
}
started() { # <seconds ago>: the job started then
  echo $(( $(date +%s) - $1 )) > "$rt/test.started"
}

echo "-- the input's range"
for v in 1 10 20 360; do
  run limit LIMIT="$v"
  [ "$rc" = 0 ] && [ -s "$rt/test.started" ] && ok "test-timeout-minutes $v is taken and the start recorded" || bad "test-timeout-minutes $v (exit $rc)" "$out"
done
for v in 0 361 400 2.5 ""; do
  run limit LIMIT="$v"
  if [ "$rc" != 0 ] && printf '%s' "$out" | grep -q "test-timeout-minutes" && printf '%s' "$out" | grep -q "1 to 360"; then ok "test-timeout-minutes '$v' fails, naming the input and its range"
  else bad "test-timeout-minutes '$v' (exit $rc)" "$out"; fi
done

echo "-- coverage only on a pull request"
python3 - "$tmp/job.yml" <<'PY' && ok "Install coverage runs only on a pull request" || bad "Install coverage is not limited to a pull request"
import re, sys
job = open(sys.argv[1], encoding="utf-8").read()
step = job.split("- name: Install coverage", 1)[1].split("\n      - ", 1)[0]
sys.exit(not re.search(r"^        if: \$\{\{ github\.event\.pull_request \}\}$", step, re.M))
PY
fresh; started 5; KEEP=1 run pytest LIMIT=10 COV=skipped
if [ "$rc" = 0 ] && grep -qx "uv run pytest" "$rt/uv.log" && ! grep -q coverage "$rt/uv.log"; then ok "a push (coverage not installed) runs plain pytest"
else bad "a push did not run plain pytest (exit $rc)" "$out"$'\n'"$(cat "$rt/uv.log")"; fi
run changed PR= COV=skipped PYTEST=success
grep -qx "pass: changed lines ran under the tests, does not apply (not a pull request)" "$rt/changed.verdict" \
  && ok "a push: the changed-lines line still reads does not apply" || bad "a push: the changed-lines line changed" "$(cat "$rt/changed.verdict" 2>&1)"
fresh; started 5; KEEP=1 run pytest LIMIT=10 COV=success
if [ "$rc" = 0 ] && grep -q "uv run --no-sync coverage run --branch --source=. -m pytest" "$rt/uv.log"; then ok "a pull request runs pytest under coverage, as before"
else bad "a pull request did not run pytest under coverage (exit $rc)" "$out"$'\n'"$(cat "$rt/uv.log")"; fi

echo "-- the time limit"
for v in 1 2; do
  fresh; started 5; KEEP=1 run pytest LIMIT="$v" COV=skipped
  if [ "$rc" = 0 ] && grep -qx "uv run pytest" "$rt/uv.log"; then ok "a $v-minute limit still runs pytest (the margin is a fifth of it)"
  else bad "a $v-minute limit ran no pytest (exit $rc)" "$out"; fi
done
verdict() { KEEP=1 run Verdict SYNC=success PYTEST="$1" EXTRA="${2:-skipped}" VERSIONS="${3:-}" WEB=false PG=skipped LIMIT=1 LIMIT_OUTCOME=success; }
fresh
started $(( 60 - 12 - 3 ))   # a 1-minute limit keeps a fifth, 12 s
KEEP=1 run pytest LIMIT=1 COV=skipped STUB_SLEEP=60
if [ "$rc" != 0 ] && [ -s "$rt/pytest.time-limit" ] && printf '%s' "$out" | grep -q "::error::"; then ok "pytest past what is left of the limit is stopped (exit $rc) and says so"
else bad "pytest past the limit (exit $rc)" "$out"; fi
# #983: measure what takes the time before raising the limit.
case "$(printf '%s\n' "$out" | grep "::error::")" in
  *"uv run pytest --durations=20"*"raise test-timeout-minutes"*"moves between runs of the same commit"*) ok "the stop line names uv run pytest --durations=20 before raising the limit" ;;
  *) bad "the stop line does not say to measure before raising the limit" "$out" ;;
esac
verdict failure
line="$(printf '%s\n' "$summary" | grep "pytest on .python-version")"
case "$line" in
  "- fail: pytest on .python-version, stopped at the time limit"*"1-minute"*"test-timeout-minutes"*"less 12 s"*"not a failing test"*"uv run pytest --durations=20"*"raise test-timeout-minutes"*"moves between runs of the same commit"*) ok "Verdict says the time limit stopped pytest, with the minutes, the input and the measuring step" ;;
  *) bad "Verdict's pytest line" "$summary" ;;
esac

fresh
started 60
KEEP=1 run pytest LIMIT=1 COV=skipped
if [ "$rc" != 0 ] && [ -s "$rt/pytest.time-limit" ] && ! grep -q pytest "$rt/uv.log"; then ok "no time left: pytest does not start and the limit is the reason"
else bad "no time left (exit $rc)" "$out"$'\n'"$(cat "$rt/uv.log")"; fi

fresh; started 5; KEEP=1 run pytest LIMIT=10 COV=skipped STUB_RC=1
verdict failure
if [ "$rc" = 0 ] && printf '%s\n' "$summary" | grep -qx -- "- fail: pytest on .python-version"; then ok "a failing test is still a plain fail line"
else bad "a failing test's line" "$summary"; fi

fresh
started $(( 60 - 12 - 3 ))   # a 1-minute limit keeps a fifth, 12 s
KEEP=1 run extra LIMIT=1 VERSIONS="3.13 3.14" STUB_SLEEP=60
if [ "$rc" != 0 ] && [ -s "$rt/extra.time-limit" ] && [ "$(grep -c pytest "$rt/uv.log")" = 1 ]; then ok "an extra version past the limit is stopped, and the next one does not start"
else bad "extra versions past the limit (exit $rc)" "$out"$'\n'"$(cat "$rt/uv.log")"; fi
verdict success failure "3.13 3.14"
line="$(printf '%s\n' "$summary" | grep "pytest on 3.13 3.14")"
case "$line" in
  "- fail: pytest on 3.13 3.14, stopped at the time limit"*"test-timeout-minutes"*) ok "Verdict says the time limit stopped the extra versions" ;;
  *) bad "Verdict's extra-versions line" "$summary" ;;
esac

echo
echo "  $pass passed, $fail failed"
[ "$fail" = 0 ]
