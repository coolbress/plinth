#!/usr/bin/env bash
# `ci / install` passes only when every install-<n> job of plinth-ci.yml did
# (#1135): tests/lib/install-verdict.sh on fixture `needs` contexts and a
# stubbed `gh`, and the shipped workflow's own install job read for the
# wiring (it needs every install-<n> job, `if: always()` so a failed group
# fails it rather than skips it, and its step hands the verdict NEEDS).
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verdict="$root/tests/lib/install-verdict.sh"
shipped="$root/.github/workflows/plinth-ci.yml"
command -v jq >/dev/null || { echo "  FAIL  jq is needed"; exit 1; }
work="$(mktemp -d "${TMPDIR:-/tmp}/install-verdict.XXXXXX")" || { echo "  FAIL  mktemp"; exit 1; }
trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        | /'; }

# A two-group workflow, the shape the verdict reads.
cat >"$work/wf.yml" <<'YML'
jobs:
  install-1:
    steps:
      - name: Manifests, pins, skill frontmatter
        run: ./tests/marketplace-manifest.sh
  install-2:
    steps:
      - name: Floor checker verdicts on fixtures
        run: ./tests/floor-check-cases.sh

      - name: The eval suite stops at its ceiling
        env:
          X: "1"
        run: ./tests/eval-suite-cases.sh
  install:
    needs: [install-1, install-2]
  tools:
    steps: []
YML
mkdir -p "$work/bin"
cat >"$work/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "gh $*" >>"$GH_LOG"
[ -n "${GH_FAIL:-}" ] && { echo "HTTP 403: Resource not accessible by integration" >&2; exit 1; }
cat "$GH_JOBS"
SH
chmod +x "$work/bin/gh"
cat >"$work/jobs.json" <<'JSON'
{"jobs": [
 {"name": "ci / install-1", "conclusion": "success", "html_url": "https://x/1", "steps": [{"name": "Manifests, pins, skill frontmatter", "conclusion": "success"}]},
 {"name": "ci / install-2", "conclusion": "failure", "html_url": "https://x/2", "steps": [
   {"name": "Floor checker verdicts on fixtures", "conclusion": "success"},
   {"name": "The eval suite stops at its ceiling", "conclusion": "failure"}]}
]}
JSON

# run <needs json> [VAR=value ...]: the verdict on the fixture workflow.
run() {
  local needs="$1"; shift
  out="$(env PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" GH_JOBS="$work/jobs.json" \
    GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=7 GITHUB_RUN_ATTEMPT=2 NEEDS="$needs" "$@" \
    bash "$verdict" "${WF:-$work/wf.yml}" 2>&1)"; code=$?
}
s='{"result":"success","outputs":{}}'; f='{"result":"failure","outputs":{}}'
: >"$work/gh.log"

run "{\"install-1\":$s,\"install-2\":$s}"
[ "$code" = 0 ] && grep -qF "PASS  every install-<n> job succeeded" <<<"$out" && [ ! -s "$work/gh.log" ] \
  && ok "every group green passes, and reads no API" || bad "all green did not pass (exit $code)" "$out"

run "{\"install-1\":$s,\"install-2\":$f}"
[ "$code" = 1 ] && grep -qF '::error title=ci / install::ci / install-2: failure' <<<"$out" \
  && grep -qF 'FAIL  ci / install-2, step "The eval suite stops at its ceiling" (./tests/eval-suite-cases.sh): https://x/2' <<<"$out" \
  && ! grep -qF 'Floor checker' <<<"$out" \
  && grep -qF 'actions/runs/7/attempts/2/jobs' "$work/gh.log" \
  && ok "a failed group fails, naming its failed step and the test it runs" || bad "a failed group was not named (exit $code)" "$out"

for r in cancelled skipped; do
  run "{\"install-1\":{\"result\":\"$r\"},\"install-2\":$s}"
  [ "$code" = 1 ] && grep -qF "ci / install-1: $r" <<<"$out" \
    && ok "a $r group fails" || bad "a $r group did not fail (exit $code)" "$out"
done

run "{\"install-1\":$s}"
[ "$code" = 1 ] && grep -qF "ci / install-2 is not in the install job's needs" <<<"$out" \
  && ok "a declared group missing from needs fails" || bad "a group outside needs passed (exit $code)" "$out"

run "{\"install-1\":$s,\"install-2\":$s,\"install-9\":$s}"
[ "$code" = 1 ] && grep -qF "needs lists install-9" <<<"$out" \
  && ok "a needs entry the workflow does not declare fails" || bad "an undeclared needs entry passed (exit $code)" "$out"

for needs in '' 'not json' '{}'; do
  run "$needs"
  [ "$code" = 1 ] && grep -q '::error title=ci / install::' <<<"$out" \
    && ok "NEEDS '${needs}' fails" || bad "NEEDS '${needs}' did not fail (exit $code)" "$out"
done

printf 'jobs:\n  tools:\n    steps: []\n' >"$work/none.yml"
WF="$work/none.yml" run "{}"
[ "$code" = 1 ] && grep -qF "no install-<n> job" <<<"$out" \
  && ok "a workflow with no install-<n> job fails" || bad "no groups passed (exit $code)" "$out"

run "{\"install-1\":$s,\"install-2\":$f}" GH_FAIL=1
[ "$code" = 1 ] && grep -qF "could not read which step failed (HTTP 403" <<<"$out" && grep -qF "open the failed job's log: install-2" <<<"$out" \
  && ok "an unreadable API still fails, and says which job to open" || bad "an unreadable API did not fail as it should (exit $code)" "$out"

# The shipped workflow: every install-<n> job is in install's needs, install
# is never skipped, and its verdict step reads the whole needs context.
job="$(awk '/^  install:$/ { f = 1; next } f && /^  [a-z]/ { exit } f' "$shipped")"
declared="$(sed -nE 's/^  (install-[0-9]+):[[:space:]]*$/\1/p' "$shipped" | sort)"
needs="$(sed -nE 's/^    needs: \[(.*)\]$/\1/p' <<<"$job" | tr -d ' ' | tr ',' '\n' | sort)"
[ "$(wc -l <<<"$declared")" -ge 2 ] && [ -n "$needs" ] && [ "$declared" = "$needs" ] \
  && ok "plinth-ci.yml's install needs exactly its $(wc -l <<<"$declared" | tr -d ' ') install-<n> jobs" \
  || bad "plinth-ci.yml's install needs ($(echo $needs)) is not its install-<n> jobs ($(echo $declared)), or there are fewer than two"
grep -qE '^    if: always\(\)$' <<<"$job" \
  && ok "the install job runs whatever the groups' results (if: always())" \
  || bad "the install job has no 'if: always()': a failed group would skip it, and a skipped required check passes"
grep -qF 'NEEDS: ${{ toJSON(needs) }}' <<<"$job" && grep -qF 'tests/lib/install-verdict.sh .github/workflows/plinth-ci.yml' <<<"$job" \
  && ok "the install job hands the verdict the needs context and this workflow" \
  || bad "the install job does not run tests/lib/install-verdict.sh on NEEDS and plinth-ci.yml"
! grep -qE 'run: \./tests/[a-z0-9-]+\.sh' <<<"$job" \
  && ok "the install job runs no test of its own" || bad "the install job runs a test itself; tests belong in an install-<n> job"

echo "install-verdict-cases: $pass passed, $fail failed"
[ "$fail" = 0 ]
