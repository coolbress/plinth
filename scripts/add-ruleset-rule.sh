#!/usr/bin/env bash
# Add a kind of rule to an existing ruleset. Run by a person; needs repository
# administration.
#
#   add-ruleset-rule.sh [--dry-run] <owner/name> <preset> ...
#   presets: linear-history, code-scanning, signed-commits, two-people, one-person
#
# two-people and one-person change three fields of the pull_request rule and
# nothing else (docs/how-to/add-a-second-person.md): the approval count (1 or
# 0), code owners' review and conversation resolution (on or off). Every
# other field, require_extra_approval_for_unattributed_changes included,
# stays as it is, and the merge ruleset is never edited.
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
presets="linear-history, code-scanning, signed-commits, two-people, one-person"
dry=0
[ "${1:-}" = "--dry-run" ] && { dry=1; shift; }
repo="${1:?$usage}"; shift
[ $# -gt 0 ] || { echo "name at least one preset: $presets" >&2; exit 2; }

# The pull_request rule's three fields each people preset sets; the
# two presets set the same fields, so naming both is refused.
people_json() {
  case "$1" in
    two-people) echo '{"required_approving_review_count":1,"require_code_owner_review":true,"required_review_thread_resolution":true}' ;;
    one-person) echo '{"required_approving_review_count":0,"require_code_owner_review":false,"required_review_thread_resolution":false}' ;;
  esac
}
people=""
for p in "$@"; do
  case "$p" in
    two-people|one-person)
      [ -z "$people" ] || [ "$people" = "$p" ] || { echo "two-people and one-person set the same three fields: name one" >&2; exit 2; }
      people="$p" ;;
    linear-history|code-scanning|signed-commits) ;;
    *) echo "unknown preset: $p (one of: $presets)" >&2; exit 2 ;;
  esac
done

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

# The first ruleset by what it carries, not by its name or place in the list:
# a tag ruleset can have the lower id, and the merge ruleset
# (ruleset-merge.json) targets the branch too and is never edited here.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/rulesets.sh
. "$here/lib/rulesets.sh"
id="$(wall_ruleset_id "$repo")" \
  || { echo "no single branch ruleset on $repo carries the pull_request rule (none, more than one, or unreadable); nothing edited" >&2; exit 1; }
cur="$(gh api "repos/$repo/rulesets/$id")"

add="["
for p in "$@"; do
  case "$p" in two-people|one-person) continue ;; esac
  j="$(rule_json "$p")"
  [ "$add" = "[" ] || add="$add,"
  add="$add$j"
done
add="$add]"

set_to="$(if [ -n "$people" ]; then people_json "$people"; else echo null; fi)"
new="$(printf '%s' "$cur" | jq --argjson add "$add" --argjson set "$set_to" '
  # Only the fields PUT accepts. Server-side fields (id, created_at, _links) are rejected if sent back.
  {name, target, enforcement, bypass_actors, conditions, rules}
  # Add only. A kind that already exists keeps its existing rule (unique_by keeps the first).
  | .rules = ((.rules + $add) | unique_by(.type))
  # A people preset: the three fields of the pull_request rule, the rest of it as it was.
  | if $set == null then . else .rules |= map(if .type == "pull_request" then .parameters = ((.parameters // {}) + $set) else . end) end
')"

echo "-- $repo (ruleset $id)"
if [ -n "$people" ]; then
  # Before and after, the three fields only: what the preset changes.
  three='.rules[] | select(.type == "pull_request") | .parameters // {}
    | "required_approving_review_count=\(.required_approving_review_count) require_code_owner_review=\(.require_code_owner_review) required_review_thread_resolution=\(.required_review_thread_resolution)"'
  printf '%s' "$cur" | jq -r '"   before: " + ('"$three"')'
  printf '%s' "$new" | jq -r '"   after:  " + ('"$three"')'
fi
printf '%s' "$new" | jq -r '"   rules: " + ([.rules[].type] | sort | join(" "))'
printf '%s' "$new" | jq -r '"   bypass actors: \(.bypass_actors|length), enforcement: \(.enforcement)"'

if [ "$dry" = 1 ]; then echo "   (--dry-run: nothing written)"; exit 0; fi
printf '%s' "$new" | gh api "repos/$repo/rulesets/$id" -X PUT --input - >/dev/null
echo "   applied"
