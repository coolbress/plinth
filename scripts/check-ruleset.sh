#!/usr/bin/env bash
# Invariants of ruleset.json: is the wall a wall.
#
# This file is not configuration, it is executable: every repository the door
# creates gets its wall from here. One line silently flipped (a bypass actor,
# a check removed, a merge method added) flips the wall of every repository
# created afterwards, so a check reads it instead of a human eye. The check is
# not "is it valid JSON" (jq empty does that) but "does it still enforce".
set -euo pipefail

f="${1:-ruleset.json}"
fail=0

jq empty "$f" 2>/dev/null || { echo "FAIL  $f is not valid JSON"; exit 1; }

chk() { # description, jq expression, expected
  local got
  got="$(jq -c "$2" "$f")"
  if [ "$got" = "$3" ]; then
    printf '  PASS  %s\n' "$1"
  else
    printf '  FAIL  %s\n        expected: %s\n        actual:   %s\n' "$1" "$3" "$got"
    fail=1
  fi
}

echo "ruleset invariants: $f"

# The wall itself.
chk 'no bypass actors (neither agents nor people get around it)' '.bypass_actors' '[]'
chk 'enforced, not advisory' '.enforcement' '"active"'
chk 'targets the default branch' '.conditions.ref_name.include' '["~DEFAULT_BRANCH"]'
chk 'default branch cannot be deleted' '[.rules[].type]|index("deletion")!=null' 'true'
chk 'no force push' '[.rules[].type]|index("non_fast_forward")!=null' 'true'
chk 'nothing lands without a pull request' '[.rules[].type]|index("pull_request")!=null' 'true'

# Merge settings and the ruleset must agree, or the repository has no merge
# button at all. The door sets both.
chk 'squash is the only merge method' \
    '.rules[]|select(.type=="pull_request").parameters.allowed_merge_methods' '["squash"]'

# Machine verdicts. Check names are {caller job} / {called job}: the caller is
# named `ci`, the called jobs live in python-ci.yml. Three files must agree
# (this one, python-ci.yml, the instance's ci.yml); rename one and every
# repository locks itself out of merging.
chk 'required checks are the python-ci jobs plus CodeQL' \
    '[.rules[]|select(.type=="required_status_checks").parameters.required_status_checks[].context]' \
    '["ci / pr-title","ci / lint","ci / typecheck","ci / test","ci / build","ci / secrets","ci / deps","ci / diff-size","ci / floor-check","CodeQL"]'
# A name alone lets anyone post a green check under it; the source app pins it.
# Two sources: `ci / *` is GitHub Actions (15368), `CodeQL` is code scanning (57789).
chk 'Actions checks come from the GitHub Actions app (15368)' \
    '[.rules[]|select(.type=="required_status_checks").parameters.required_status_checks[]|select(.context|startswith("ci / ")).integration_id]|unique' \
    '[15368]'
chk 'CodeQL comes from the code scanning app (57789)' \
    '[.rules[]|select(.type=="required_status_checks").parameters.required_status_checks[]|select(.context=="CodeQL").integration_id]|unique' \
    '[57789]'
# Per-language jobs (`Analyze (python)`) are never required: languages differ
# per repository and a missing one never reports, which locks the repository.
chk 'no per-language Analyze job is required' \
    '[.rules[]|select(.type=="required_status_checks").parameters.required_status_checks[].context|select(startswith("Analyze"))]|length' \
    '0'
chk 'green on a stale main does not count (strict)' \
    '.rules[]|select(.type=="required_status_checks").parameters.strict_required_status_checks_policy' 'true'

[ "$fail" = 0 ] && { echo "RESULT PASS"; exit 0; }
echo "RESULT FAIL"; exit 1
