#!/usr/bin/env bash
# `scripts/check-ruleset.sh --own <file>` (#863) reads plinth's own `main
# protection` back as `gh api repos/coolbress/plinth/rulesets/<id>` returns
# it: the five checks it requires, from the Actions app, enforced on the
# default branch, with no bypass actor. Each fixture breaks one of those.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/check-ruleset-own.XXXXXX")"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0

cat >"$work/good.json" <<'EOF'
{"name":"main protection","target":"branch","enforcement":"active","bypass_actors":[],
 "conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},
 "rules":[{"type":"deletion"},
  {"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[
   {"context":"ci / docs","integration_id":15368},{"context":"ci / install","integration_id":15368},
   {"context":"ci / tools","integration_id":15368},{"context":"third-party / review","integration_id":15368},
   {"context":"ci / release-gate","integration_id":15368}]}}]}
EOF

case_() { # <label> <want exit> <jq edit of good.json>
  jq -r "$3" "$work/good.json" >"$work/f.json"
  (cd "$root" && ./scripts/check-ruleset.sh --own "$work/f.json") >"$work/out" 2>&1; rc=$?
  if [ "$rc" = "$2" ]; then echo "  PASS  $1"; pass=$((pass + 1))
  else echo "  FAIL  $1: exit $rc, want $2" >&2; sed 's/^/        /' "$work/out" >&2; fail=$((fail + 1)); fi
}
case_ "the five checks, enforced on the default branch, no bypass: passes" 0 '.'
case_ "without ci / release-gate: fails" 1 '(.rules[1].parameters.required_status_checks) |= map(select(.context != "ci / release-gate"))'
case_ "ci / release-gate from another app: fails" 1 '(.rules[1].parameters.required_status_checks[4].integration_id) = 1'
case_ "enforcement evaluate: fails" 1 '.enforcement = "evaluate"'
case_ "enforcement disabled: fails" 1 '.enforcement = "disabled"'
case_ "a branch other than the default: fails" 1 '.conditions.ref_name.include = ["refs/heads/nothing"]'
case_ "a bypass actor: fails" 1 '.bypass_actors = [{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}]'
case_ "not JSON: fails" 1 'tostring | .[0:5]'

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
