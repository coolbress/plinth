#!/usr/bin/env bash
# The refusals of `scripts/require-check.sh` (#707). No network: `gh` is mocked.
#
# One property: the ruleset is written only for a name that reported on the
# default branch, from a GitHub Actions job in a workflow file, with no `if:`
# on that job or on the job that calls it, and only with a login that
# administers the repository. Every refusal leaves the ruleset unwritten.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/files/r/r/.github/workflows" "$work/files/other/lib/.github/workflows"

cat > "$work/files/r/r/.github/workflows/ci.yml" <<'YML'
name: ci
on: [push, pull_request]
jobs:
  base:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
  slow:
    name: "slow check"   # quoted, with a comment
    runs-on: ubuntu-latest
    steps:
      - if: github.event_name == 'push'
        run: |
          echo a step's if is not the job's
  gated:
    runs-on: ubuntu-latest
    if: github.event_name == 'push'
    steps:
      - run: echo ok
  wrap:
    uses: ./.github/workflows/inner.yml
  wrapif:
    if: always()
    uses: ./.github/workflows/inner.yml
  remote:
    uses: other/lib/.github/workflows/lib.yml@0123456789abcdef0123456789abcdef01234567
YML
cat > "$work/files/r/r/.github/workflows/inner.yml" <<'YML'
on:
  workflow_call:
jobs:
  inner:
    runs-on: ubuntu-latest
    steps:
      - run: |
          if: this line is shell, not the job's key
  innerif:
    if: ${{ inputs.go }}
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
YML
cat > "$work/files/other/lib/.github/workflows/lib.yml" <<'YML'
on: workflow_call
jobs:
  lib:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
YML
cat > "$work/files/r/r/.github/workflows/dyn.yml" <<'YML'
on: push
jobs:
  dyn:
    name: ${{ matrix.x }} check
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
YML

# The ruleset as GitHub holds it; a PUT replaces it, so a read-back sees the write.
echo '{"id":1,"name":"r","target":"branch","enforcement":"active","bypass_actors":[],"conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"rules":[{"type":"deletion"},{"type":"pull_request"},{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"base","integration_id":15368}]}}],"_links":{}}' > "$work/ruleset.orig"

cat > "$work/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -u
w="$MOCK_WORK"
out() { case "$*" in *" --jq "*) jq -r "${@: -1}" ;; *) cat ;; esac; }
args="$*"
case "$args" in
  "repo view"*) echo "r/r" ;;
  *"-X PUT"*)
    cat > "$w/put.json"
    [ "${PUT_FAIL:-0}" = 1 ] && { echo "HTTP 403: Resource not accessible by personal access token" >&2; exit 1; }
    jq '. + {id: 1}' "$w/put.json" > "$w/ruleset" ;;
  *"/actions/permissions"*) [ "${ACTIONS_PERM:-1}" = 1 ] || { echo "HTTP 403" >&2; exit 1; }; echo '{}' ;;
  *"/actions/runs?check_suite_id="*)
    suite="${args##*check_suite_id=}"; suite="${suite%% *}"
    case "$suite" in
      10) p=.github/workflows/ci.yml ;; 20) p=dynamic/github-code-scanning/codeql ;;
      40) p=.github/workflows/dyn.yml ;; *) p="" ;;
    esac
    jq -n --arg p "$p" '{workflow_runs: [{path: $p}]}' | out "$@" ;;
  *"/contents/"*)
    spec="${args##*repos/}"; spec="${spec%% *}"
    owner_repo="$(echo "$spec" | cut -d/ -f1-2)"; path="${spec#*/contents/}"; path="${path%%\?*}"
    cat "$w/files/$owner_repo/$path" 2>/dev/null || { echo "HTTP 404" >&2; exit 1; } ;;
  *"/rulesets/1"*) out "$@" < "$w/ruleset" ;;
  *"/rulesets?"*) echo '[{"id":7,"target":"tag"},{"id":1,"target":"branch"}]' | out "$@" ;;
  *"/commits?sha=main"*) echo '[{"sha":"sha1"}]' | out "$@" ;;
  *"/commits/sha1/check-runs"*)
    jq -n '{check_runs: [
      {name: "base", app: {id: 15368}, check_suite: {id: 10}},
      {name: "slow check", app: {id: 15368}, check_suite: {id: 10}},
      {name: "gated", app: {id: 15368}, check_suite: {id: 10}},
      {name: "wrap / inner", app: {id: 15368}, check_suite: {id: 10}},
      {name: "wrapif / inner", app: {id: 15368}, check_suite: {id: 10}},
      {name: "wrap / innerif", app: {id: 15368}, check_suite: {id: 10}},
      {name: "remote / lib", app: {id: 15368}, check_suite: {id: 10}},
      {name: "Analyze (python)", app: {id: 15368}, check_suite: {id: 20}},
      {name: "x check", app: {id: 15368}, check_suite: {id: 40}},
      {name: "Vercel", app: {id: 8329}, check_suite: {id: 30}}]}' | out "$@" ;;
  "api repos/r/r --jq"*)
    jq -n --argjson a "${ADMIN:-true}" '{permissions: {admin: $a}, default_branch: "main"}' | out "$@" ;;
  *) echo "mock gh: unexpected call: $args" >&2; exit 1 ;;
esac
MOCK
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH" MOCK_WORK="$work"

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; sed 's/^/        | /' "$work/out"; }

run() { # <expected exit> <description> [args...]
  local want="$1" what="$2" rc; shift 2
  cp "$work/ruleset.orig" "$work/ruleset"; rm -f "$work/put.json"
  "$root/scripts/require-check.sh" "$@" >"$work/out" 2>&1; rc=$?
  if [ "$rc" = "$want" ]; then ok "$what (exit $rc)"; else bad "$what: exit $rc, expected $want"; fi
}
said()    { if grep -qF -- "$2" "$work/out"; then ok "$1"; else bad "$1: output lacks '$2'"; fi; }
unwritten() { if [ ! -e "$work/put.json" ]; then ok "$1: the ruleset was not written"; else bad "$1: the ruleset was written"; fi; }

ADMIN=false run 1 "a login whose role is not admin is stopped" --repo r/r 'slow check'
said "the first line says an agent's token cannot run it" "an agent's token cannot run it"
said "the stop says it changed nothing" "nothing was changed"
unwritten "not admin"
ADMIN=true ACTIONS_PERM=0 run 1 "an admin role behind a token without Administration is stopped" --repo r/r 'slow check'
unwritten "no Administration"

run 1 "a name that never reported on the default branch is refused" --repo r/r 'never seen'
said "the refusal says the name never reported" "has never reported on the last ten commits"
said "the refusal lists the names that did report" "slow check"
unwritten "never seen"

run 1 "a job with if: is refused" --repo r/r 'gated'
said "the refusal names the job and its if:" 'job `gated` in .github/workflows/ci.yml has `if:`'
unwritten "if:"
run 1 "a call to a reusable workflow with if: is refused" --repo r/r 'wrapif / inner'
said "the refusal names the calling job" 'job `wrapif`'
unwritten "caller if:"
run 1 "a called job with if: is refused" --repo r/r 'wrap / innerif'
said "the refusal names the called job" 'job `innerif` in .github/workflows/inner.yml'
unwritten "called if:"

run 1 "a check GitHub runs itself (CodeQL default setup) is refused" --repo r/r 'Analyze (python)'
said "the refusal says GitHub runs it itself" "which GitHub runs itself"
unwritten "dynamic"
run 1 "a check from another app is refused" --repo r/r 'Vercel'
said "the refusal names upgrade-ruleset.sh for it" "upgrade-ruleset.sh r/r 'Vercel:8329'"
unwritten "other app"
run 1 "a job named by an expression is refused, not guessed" --repo r/r 'x check'
said "the refusal says why it cannot tell" "sets its name with an expression"
unwritten "expression"

run 0 "a name already required changes nothing" --repo r/r 'base'
unwritten "already required"
run 0 "--dry-run adds nothing" --dry-run --repo r/r 'slow check'
unwritten "dry run"
PUT_FAIL=1 run 1 "a write GitHub refuses is reported in plain words" --repo r/r 'slow check'
said "it says GitHub refused and nothing changed" "GitHub refused the change"

run 0 "a job with no if: is added" --repo r/r 'slow check'
if [ -e "$work/put.json" ] && jq -e '
     (.rules | map(.type)) == ["deletion","pull_request","required_status_checks"]
     and (.rules[2].parameters.required_status_checks == [{"context":"base","integration_id":15368},{"context":"slow check","integration_id":15368}])
     and .rules[2].parameters.strict_required_status_checks_policy == true
     and (has("id") | not) and (has("_links") | not)' "$work/put.json" >/dev/null
then ok "the write adds the name and keeps every other rule, entry and the strict policy"
else bad "the write is not the old ruleset plus one entry"; fi
said "the new list is printed as read back" "requires: slow check"
said "the old entry is in the printed list" "requires: base"
run 0 "a called job in a local reusable workflow is added" --repo r/r 'wrap / inner'
said "it names the chain of jobs" 'inner.yml: job `inner`'
run 0 "a called job in a pinned remote workflow is added" --repo r/r 'remote / lib'
run 0 "without --repo the current directory's repository is used" 'slow check'
run 2 "no name is a usage error" --repo r/r

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
