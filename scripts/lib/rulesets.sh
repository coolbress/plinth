# shellcheck shell=bash
# The door's two branch rulesets, as the scripts that write or edit them find
# and read them back. Sourced by scripts/new-project.sh,
# create-merge-ruleset.sh, upgrade-ruleset.sh, add-ruleset-rule.sh and e2e.sh;
# needs gh and jq.

# A ruleset reduced to what its file sets. GitHub adds server fields (id,
# _links, timestamps) and the update rule's parameter when it reads one back,
# and the order of keys is its own.
ruleset_shape='{name, target, enforcement, conditions, rules: [.rules[] | {type}],
                bypass_actors: [.bypass_actors[] | {actor_id, actor_type, bypass_mode}]}'

# ruleset_reads_as <owner/name> <id> <file>: the live ruleset as compared, on
# stdout; true when it equals the file's. A read that fails prints nothing.
ruleset_reads_as() {
  local got
  got="$(gh api "repos/$1/rulesets/$2" 2>/dev/null | jq -cS "$ruleset_shape" 2>/dev/null)" || got=""
  printf '%s' "$got"
  [ -n "$got" ] && [ "$got" = "$(jq -cS "$ruleset_shape" "$3")" ]
}

# wall_ruleset_id <owner/name>: the first ruleset's id (ruleset.json's), found
# by what it carries, not by its name or its place in the list: the one branch
# ruleset with a pull_request rule. A tag ruleset is not a branch ruleset, and
# the merge ruleset carries `update` alone. Prints nothing and fails when no
# ruleset or more than one carries it: an edit to the wrong one weakens it in
# silence (a rule added beside the merge ruleset's exempt admin would not hold
# the admin).
wall_ruleset_id() {
  local id ids found=()
  ids="$(gh api "repos/$1/rulesets" --jq '.[] | select(.target == "branch") | .id')" || return 1
  for id in $ids; do
    if gh api "repos/$1/rulesets/$id" --jq '[.rules[].type] | index("pull_request") != null' | grep -qx true; then
      found+=("$id")
    fi
  done
  [ "${#found[@]}" = 1 ] || return 1
  echo "${found[0]}"
}
