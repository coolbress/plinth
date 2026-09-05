#!/usr/bin/env bash
# Add required checks to the ruleset of an existing repository. Run by a
# person; needs repository administration.
#
#   upgrade-ruleset.sh [--dry-run] [--force] <owner/name> <context:app-id> ...
#   upgrade-ruleset.sh --dry-run myorg/myapp 'third-party / review:15368'
#
# Requiring a name that never arrives locks the repository: nothing merges,
# ever. So before writing, the names are checked against what the repository
# has actually reported, and an unseen name stops the tool (fail-closed).
# Measured 2026-08-30: a repository that called its own CI through a job named
# `canary` reported `canary / deps`, not `ci / deps`; the same command as its
# siblings would have locked it. For a check that has not run yet, --force.
#
# Why a tool: `ruleset.json` applies to new repositories only. An existing one
# is edited through the API, and JSON pasted by hand drops other fields, which
# is how a wall gets weaker in silence. This script only adds.
#
# Everyday tokens get a 403 here. Run it through the wrapper that asks for an
# admin token at the terminal (never on a command line or in history):
#   scripts/with-admin-token.sh scripts/upgrade-ruleset.sh <owner/name> ...
set -euo pipefail

usage="usage: upgrade-ruleset.sh [--dry-run] [--force] <owner/name> <context:app-id> ..."
dry=0; force=0
while :; do
  case "${1:-}" in
    --dry-run) dry=1; shift ;;
    --force)   force=1; shift ;;
    *) break ;;
  esac
done
repo="${1:?$usage}"; shift
[ $# -gt 0 ] || { echo "name at least one check, e.g. 'third-party / review:15368' (15368 is the GitHub Actions app)" >&2; exit 2; }

id="$(gh api "repos/$repo/rulesets" --jq '.[0].id')"
[ -n "$id" ] || { echo "no ruleset on $repo" >&2; exit 1; }
cur="$(gh api "repos/$repo/rulesets/$id")"

# fail-closed: has every requested name actually been reported? Some checks
# report on pull requests only (CodeQL did), so recent commits and pull
# request heads are both read.
seen="$( {
  gh api "repos/$repo/commits?per_page=3" --jq '.[].sha' 2>/dev/null
  gh api "repos/$repo/pulls?state=all&per_page=5" --jq '.[].head.sha' 2>/dev/null
} | sort -u | while read -r sha; do
  [ -n "$sha" ] || continue
  gh api "repos/$repo/commits/$sha/check-runs?per_page=100" --jq '.check_runs[].name' 2>/dev/null
  gh api "repos/$repo/commits/$sha/status" --jq '.statuses[].context' 2>/dev/null
done | sort -u )"

if [ -z "$seen" ]; then
  echo "no check name could be read from $repo; the requested names cannot be verified." >&2
  echo "  requiring an unverified name can lock the repository. To proceed anyway: --force." >&2
  [ "$force" = 1 ] || exit 1
fi

unseen=""
for spec in "$@"; do
  ctx="${spec%%:*}"
  printf '%s\n' "$seen" | grep -qxF "$ctx" || unseen="$unseen$ctx"$'\n'
done

if [ -n "$unseen" ]; then
  echo "these names have never been reported on $repo:" >&2
  printf '%s' "$unseen" | sed 's/^/     /' >&2
  echo "  names that did report:" >&2
  printf '%s\n' "$seen" | sed 's/^/     /' >&2
  echo "  a required name that never arrives means nothing merges in this repository." >&2
  echo "  fix the name, or if the check simply has not run yet: --force." >&2
  [ "$force" = 1 ] || exit 1
  echo "  --force: proceeding without verification." >&2
fi

add_json="$(printf '%s\n' "$@" | jq -R 'split(":") | {context: .[0], integration_id: (.[1]|tonumber)}' | jq -s .)"

new="$(printf '%s' "$cur" | jq --argjson add "$add_json" '
  # Only the fields PUT accepts. Server-side fields (id, created_at, _links) are rejected if sent back.
  {name, target, enforcement, bypass_actors, conditions, rules}
  | .rules |= map(
      if .type == "required_status_checks" then
        # Add only. Existing entries stay as they are (unique_by drops duplicates).
        .parameters.required_status_checks =
          ((.parameters.required_status_checks + $add) | unique_by(.context))
      else . end)
')"

echo "-- $repo (ruleset $id)"
printf '%s' "$new" | jq -r '
  .rules[] | select(.type=="required_status_checks")
  | .parameters.required_status_checks[] | "   requires: \(.context)  (app \(.integration_id))"'
printf '%s' "$new" | jq -r '"   bypass actors: \(.bypass_actors|length), enforcement: \(.enforcement)"'

if [ "$dry" = 1 ]; then echo "   (--dry-run: nothing written)"; exit 0; fi
printf '%s' "$new" | gh api "repos/$repo/rulesets/$id" -X PUT --input - >/dev/null
echo "   applied"
