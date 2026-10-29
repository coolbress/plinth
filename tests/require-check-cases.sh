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
  setup:
    if: github.event_name == 'push'
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
  audit:
    needs: setup
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
  prep:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
  built:
    needs: [prep]
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
  chained:
    needs:
      - built
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
YML
# Triggers: one workflow per way a pull request can go without the check.
trig() { # <file> <job> <on: block>
  printf '%s\njobs:\n  %s:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ok\n' "$3" "$2" \
    > "$work/files/r/r/.github/workflows/$1"
}
trig push-only.yml pushonly $'on:\n  push:\n    branches: [main]'
trig paths.yml pathy $'on:\n  pull_request:\n    paths:\n      - src/**'
trig other-branch.yml rel $'on:\n  pull_request:\n    branches: [release]'
trig types.yml typed $'on:\n  pull_request:\n    types: [opened]'
trig block.yml blocky $'on:\n  push:\n    branches: [main]\n  pull_request:\n    branches:\n      - main\n    types: [opened, synchronize, reopened]'
trig list.yml listy $'on:\n  - push\n  - pull_request'
# A `!` pattern under branches: drops a branch an earlier pattern matched (#736), in every way a list is written.
trig neg-flow.yml negflow $'on:\n  pull_request:\n    branches: [\'**\', \'!main\']'
trig neg-dq.yml negdq $'on:\n  pull_request:\n    branches: ["**", "!main"]'
trig neg-block.yml negblock $'on:\n  pull_request:\n    branches:\n      - \'**\'\n      - \'!main\'  # not main'
trig neg-plain.yml negplain $'on:\n  pull_request:\n    branches:\n      - "**"\n      - !main'
trig neg-target.yml negtarget $'on:\n  pull_request_target:\n    branches: [\'**\', \'!main\']'
trig neg-wrapped.yml negwrapped $'on:\n  pull_request:\n    branches: [\'**\',\n      \'!main\']'
trig neg-escape.yml negescape $'on:\n  pull_request:\n    branches: ["**", "\\x21main"]'
trig neg-alias.yml negalias $'x: &neg \'!main\'\non:\n  pull_request:\n    branches:\n      - \'**\'\n      - *neg'
trig flow-main.yml flowmain $'on:\n  pull_request:\n    branches: [main]'
trig all.yml allbranches $'on:\n  pull_request:\n    branches: [\'**\']'

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
on: [push, pull_request]
jobs:
  dyn:
    name: ${{ matrix.x }} check
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
YML

# The ruleset as GitHub holds it; a PUT replaces it, so a read-back sees the write.
echo '{"id":1,"name":"r","target":"branch","enforcement":"active","bypass_actors":[],"conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"rules":[{"type":"deletion"},{"type":"pull_request"},{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"base","integration_id":15368},{"context":"prep","integration_id":15368}]}}],"_links":{}}' > "$work/ruleset.orig"

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
      40) p=.github/workflows/dyn.yml ;; 51) p=.github/workflows/push-only.yml ;;
      52) p=.github/workflows/paths.yml ;; 53) p=.github/workflows/other-branch.yml ;;
      54) p=.github/workflows/types.yml ;; 55) p=.github/workflows/block.yml ;;
      56) p=.github/workflows/list.yml ;; 57) p=.github/workflows/neg-flow.yml ;;
      58) p=.github/workflows/neg-dq.yml ;; 59) p=.github/workflows/neg-block.yml ;;
      60) p=.github/workflows/neg-plain.yml ;; 61) p=.github/workflows/neg-target.yml ;;
      62) p=.github/workflows/neg-wrapped.yml ;; 63) p=.github/workflows/neg-escape.yml ;;
      64) p=.github/workflows/neg-alias.yml ;; 65) p=.github/workflows/flow-main.yml ;;
      66) p=.github/workflows/all.yml ;; *) p="" ;;
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
      {name: "audit", app: {id: 15368}, check_suite: {id: 10}},
      {name: "prep", app: {id: 15368}, check_suite: {id: 10}},
      {name: "built", app: {id: 15368}, check_suite: {id: 10}},
      {name: "chained", app: {id: 15368}, check_suite: {id: 10}},
      {name: "pushonly", app: {id: 15368}, check_suite: {id: 51}},
      {name: "pathy", app: {id: 15368}, check_suite: {id: 52}},
      {name: "rel", app: {id: 15368}, check_suite: {id: 53}},
      {name: "typed", app: {id: 15368}, check_suite: {id: 54}},
      {name: "blocky", app: {id: 15368}, check_suite: {id: 55}},
      {name: "listy", app: {id: 15368}, check_suite: {id: 56}},
      {name: "negflow", app: {id: 15368}, check_suite: {id: 57}},
      {name: "negdq", app: {id: 15368}, check_suite: {id: 58}},
      {name: "negblock", app: {id: 15368}, check_suite: {id: 59}},
      {name: "negplain", app: {id: 15368}, check_suite: {id: 60}},
      {name: "negtarget", app: {id: 15368}, check_suite: {id: 61}},
      {name: "negwrapped", app: {id: 15368}, check_suite: {id: 62}},
      {name: "negescape", app: {id: 15368}, check_suite: {id: 63}},
      {name: "negalias", app: {id: 15368}, check_suite: {id: 64}},
      {name: "flowmain", app: {id: 15368}, check_suite: {id: 65}},
      {name: "allbranches", app: {id: 15368}, check_suite: {id: 66}},
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

run 1 "a job that needs a job with if: is refused" --repo r/r 'audit'
said "the refusal names the needed job" 'job `setup` in .github/workflows/ci.yml has `if:`'
unwritten "needs if:"
run 1 "a job that needs a job nobody requires is refused" --repo r/r 'chained'
said "the refusal names the needed job that is not required" "     built"
unwritten "needs unrequired"
run 0 "a job whose needed jobs are all required is added" --repo r/r 'built'
# The same name required from another app, or from any app, does not hold the Actions job.
jq '.rules[2].parameters.required_status_checks[1].integration_id = 8329' "$work/ruleset.orig" > "$work/ruleset.other"
mv "$work/ruleset.orig" "$work/ruleset.keep"; cp "$work/ruleset.other" "$work/ruleset.orig"
run 1 "a needed job required only from another app is refused" --repo r/r 'built'
said "the refusal names it" "     prep"
unwritten "needed from another app"
run 0 "a name required only from another app is still added from Actions" --repo r/r 'prep'
if [ -e "$work/put.json" ] && jq -e '[.rules[2].parameters.required_status_checks[] | select(.context == "prep") | .integration_id] == [8329, 15368]' "$work/put.json" >/dev/null
then ok "the other app's entry stays and the Actions one is added beside it"
else bad "the write does not hold both prep entries"; fi
jq 'del(.rules[2].parameters.required_status_checks[1].integration_id)' "$work/ruleset.keep" > "$work/ruleset.orig"
run 1 "a needed job required from any app is refused" --repo r/r 'built'
mv "$work/ruleset.keep" "$work/ruleset.orig"

run 1 "a workflow that runs on push only is refused" --repo r/r 'pushonly'
said "the refusal says there is no pull_request event" "has no pull_request event"
unwritten "push only"
run 1 "a pull_request path filter is refused" --repo r/r 'pathy'
said "the refusal names the filter" 'has `paths:`'
unwritten "paths"
run 1 "a pull_request for another branch only is refused" --repo r/r 'rel'
said "the refusal names the branch" "runs only for pull requests to release"
unwritten "other branch"
run 1 "pull_request types without synchronize are refused" --repo r/r 'typed'
said "the refusal names the missing type" "leave out synchronize"
unwritten "types"
run 0 "a block on: with the default branch and the three types is accepted" --repo r/r 'blocky'
run 0 "an on: written as a list is accepted" --repo r/r 'listy'

run 1 "branches: ['**', '!main'] is refused" --repo r/r 'negflow'
said "the refusal names the workflow" ".github/workflows/neg-flow.yml does not run 'negflow'"
said "the refusal names the pattern and its line" "branches list has \`'!main'\` (line 3)"
said "the refusal says why in plain words" 'a pattern starting with `!` leaves branches out'
unwritten "negative pattern"
run 1 "a double-quoted ! pattern is refused" --repo r/r 'negdq'
said "it names the line" "(line 3)"
unwritten "double-quoted"
run 1 "a ! pattern as a block list item, with a comment, is refused" --repo r/r 'negblock'
said "it names the item's own line" "(line 5)"
unwritten "block item"
run 1 "an unquoted ! item is refused" --repo r/r 'negplain'
said "it names the item's own line" "\`!main\` (line 5)"
unwritten "unquoted"
run 1 "a ! pattern under pull_request_target is refused" --repo r/r 'negtarget'
said "it names the event" 'its `pull_request_target:` branches list'
unwritten "pull_request_target"
run 1 "a branches list that goes on past its line is refused, not read in part" --repo r/r 'negwrapped'
said "it names the workflow and the line" "line 3 of .github/workflows/neg-wrapped.yml"
unwritten "wrapped list"
run 1 "an escape that may spell ! is refused" --repo r/r 'negescape'
said "it names the line" "line 3 of .github/workflows/neg-escape.yml"
unwritten "escape"
run 1 "an alias in a branches list is refused" --repo r/r 'negalias'
said "it says why" "an anchor or alias"
unwritten "alias"
run 0 "branches: [main] is accepted" --repo r/r 'flowmain'
run 0 "branches: ['**'] is accepted" --repo r/r 'allbranches'

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
     and (.rules[2].parameters.required_status_checks == [{"context":"base","integration_id":15368},{"context":"prep","integration_id":15368},{"context":"slow check","integration_id":15368}])
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
