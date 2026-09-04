#!/usr/bin/env bash
# Verdicts of `ci / pr-title`. The rule is not copied here; it is extracted from
# the workflow. Two copies of a rule drift, and that drift is what let invented
# commit types through once.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="$root/.github/workflows/python-ci.yml"

types="$(sed -nE "s/^[[:space:]]*types='([^']+)'.*/\1/p" "$wf" | head -1)"
[ -n "$types" ] || { echo "  FAIL  types= not found in python-ci.yml"; exit 1; }
# The whole pattern, not just the type list: grep -qE "<pattern>" in the workflow.
shape="$(sed -nE 's/^.*grep -qE "([^"]+)".*$/\1/p' "$wf" | head -1)"
[ -n "$shape" ] || { echo "  FAIL  the grep pattern was not found in python-ci.yml"; exit 1; }
re="${shape//\$types/$types}"

pass=0; fail=0
check() { # <ok|no> <title>
  if printf '%s' "$2" | grep -qE "$re"; then got=ok; else got=no; fi
  if [ "$got" = "$1" ]; then pass=$((pass+1)); printf '  PASS  %-3s %s\n' "$1" "$2"
  else fail=$((fail+1)); printf '  FAIL  %-3s %s  (got %s)\n' "$1" "$2" "$got"; fi
}

echo "ci / pr-title verdicts (rule extracted from python-ci.yml; types: $types)"
echo "-- must pass"
check ok "feat: add a thing"
check ok "fix(cli): exit code"
check ok "docs(research): add a corpus note"
check ok "docs(decision): record a decision"
check ok "refactor(layout): move files"
check ok "build(deps): bump a dependency"
check ok "fix(security): close a hole"
check ok "feat!: callers must change"
check ok "feat(api)!: breaking"
echo "-- must fail: invented types"
check no "research: add a corpus note"
check no "decide: record a decision"
check no "decision: record a decision"
check no "record: note it"
check no "anchor: add an anchor"
check no "audit: audit it"
check no "move: move files"
echo "-- must fail: shape"
check no "just a title"
check no "feat:"
check no "feat add a thing"
check no "Feat: capitalised"
check no "feat(scope) missing colon"
echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
