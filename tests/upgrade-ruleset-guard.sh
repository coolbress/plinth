#!/usr/bin/env bash
# The name guard of `scripts/upgrade-ruleset.sh`. No network: `gh` is mocked.
#
# One property: a check name that was never reported is not required.
# Why it matters: a required name that never arrives means nothing merges in
# that repository, ever. Measured 2026-08-30: a repository that called its own
# CI through a job named `canary` reported `canary / deps`, and the same
# command used on its siblings would have required `ci / deps`.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

# Mock: this repository reports `canary / deps` only; `ci / deps` never came.
cat > "$work/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -u
case "$*" in
  *"/rulesets/1"*)      echo '{"name":"r","target":"branch","enforcement":"active","bypass_actors":[],"conditions":{},"rules":[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"canary / test","integration_id":15368}]}}]}' ;;
  *"/rulesets"*)        echo 1 ;;   # the value after `--jq '.[0].id'`
  *"/commits?per_page"*) echo "sha1" ;;
  *"/pulls?state"*)      echo "sha1" ;;
  *"check-runs"*)        printf 'canary / deps\ncanary / test\n' ;;
  *"/status"*)           printf 'CodeQL\n' ;;
esac
exit 0
MOCK
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"

pass=0; fail=0
check() { # <name> <expected ok|no> <actual exit code>
  if { [ "$2" = ok ] && [ "$3" = 0 ]; } || { [ "$2" = no ] && [ "$3" != 0 ]; }
  then pass=$((pass+1)); echo "  PASS  $1"
  else fail=$((fail+1)); echo "  FAIL  $1 (exit $3, expected $2)"; fi
}

run() { "$root/scripts/upgrade-ruleset.sh" "$@" >"$work/out" 2>&1; }

run --dry-run r/r 'ci / deps:15368'
check "a name that never reported is refused" no $?
if grep -q "canary / deps" "$work/out"; then
  pass=$((pass+1)); echo "  PASS  the refusal shows the names that did report"
else
  fail=$((fail+1)); echo "  FAIL  the names that did report are not shown; nobody can fix the call"
fi

run --dry-run r/r 'canary / deps:15368'
check "a name that reported passes" ok $?

run --dry-run r/r 'CodeQL:57789'
check "commit statuses (names that only show on pull requests) count too" ok $?

run --dry-run --force r/r 'ci / deps:15368'
check "--force skips the guard" ok $?

run --dry-run r/r 'canary / deps:15368' 'ci / deps:15368'
check "one wrong name among several is enough to refuse" no $?

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
