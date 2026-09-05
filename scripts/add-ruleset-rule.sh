#!/usr/bin/env bash
# Add a kind of rule to an existing ruleset. Run by a person; needs repository
# administration.
#
#   add-ruleset-rule.sh [--dry-run] <owner/name> <preset> ...
#   presets: linear-history, code-scanning, signed-commits
#
# Why a tool: `upgrade-ruleset.sh` adds required checks only. Adding a rule
# kind means editing the ruleset JSON, and JSON pasted by hand drops other
# fields, which is how a wall gets weaker in silence. This script only adds
# and leaves existing rules alone.
#
# Everyday tokens get a 403 here. Run it through the wrapper:
#   scripts/with-admin-token.sh scripts/add-ruleset-rule.sh <owner/name> <preset>
set -euo pipefail

usage="usage: add-ruleset-rule.sh [--dry-run] <owner/name> <preset> ..."
dry=0
[ "${1:-}" = "--dry-run" ] && { dry=1; shift; }
repo="${1:?$usage}"; shift
[ $# -gt 0 ] || { echo "name at least one preset: linear-history, code-scanning, signed-commits" >&2; exit 2; }

# Preset to rule JSON. Nothing else is accepted: free-form JSON would void
# the reason this tool exists.
rule_json() {
  case "$1" in
    linear-history)
      echo '{"type":"required_linear_history"}' ;;
    code-scanning)
      # "CodeQL ran" and "no alerts remain" are different sentences: a required
      # check says the first, this rule says the second.
      echo '{"type":"code_scanning","parameters":{"code_scanning_tools":[{"tool":"CodeQL","security_alerts_threshold":"high_or_higher","alerts_threshold":"errors"}]}}' ;;
    signed-commits)
      echo '{"type":"required_signatures"}' ;;
    *) echo "unknown preset: $1" >&2; return 1 ;;
  esac
}

# What is hard to undo is said first.
for p in "$@"; do
  if [ "$p" = "signed-commits" ]; then
    echo "signed-commits rejects every unsigned commit." >&2
    echo "  agents push through local git and those commits are not signed:" >&2
    echo "  the moment this is on, agents can no longer push anything to this repository." >&2
    echo "  (SLSA Source L2, which the floor cites, does not require signatures.)" >&2
    printf '  type yes to enable it anyway: ' >&2
    IFS= read -r ans < /dev/tty
    [ "$ans" = "yes" ] || { echo "  stopped." >&2; exit 1; }
  fi
done

# The branch ruleset by target, not the first ruleset: a tag ruleset can have the lower id.
id="$(gh api "repos/$repo/rulesets" --jq '[.[] | select(.target == "branch")][0].id')"
[ -n "$id" ] && [ "$id" != null ] || { echo "no branch ruleset on $repo" >&2; exit 1; }
cur="$(gh api "repos/$repo/rulesets/$id")"

add="["
for p in "$@"; do
  j="$(rule_json "$p")"
  [ "$add" = "[" ] || add="$add,"
  add="$add$j"
done
add="$add]"

new="$(printf '%s' "$cur" | jq --argjson add "$add" '
  # Only the fields PUT accepts. Server-side fields (id, created_at, _links) are rejected if sent back.
  {name, target, enforcement, bypass_actors, conditions, rules}
  # Add only. A kind that already exists keeps its existing rule (unique_by keeps the first).
  | .rules = ((.rules + $add) | unique_by(.type))
')"

echo "-- $repo (ruleset $id)"
printf '%s' "$new" | jq -r '"   rules: " + ([.rules[].type] | sort | join(" "))'
printf '%s' "$new" | jq -r '"   bypass actors: \(.bypass_actors|length), enforcement: \(.enforcement)"'

if [ "$dry" = 1 ]; then echo "   (--dry-run: nothing written)"; exit 0; fi
printf '%s' "$new" | gh api "repos/$repo/rulesets/$id" -X PUT --input - >/dev/null
echo "   applied"
