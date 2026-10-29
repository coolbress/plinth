#!/usr/bin/env bash
# Make one check required on the default branch. Run by a person; needs
# repository administration.
#
#   require-check.sh [--dry-run] [--repo <owner/name>] <check name>
#   require-check.sh 'ci / web-audit'            # the repository of the current directory
#
# Requiring a name that never arrives locks the repository: nothing merges,
# ever. So before writing, the name must have reported on a recent commit of
# the default branch, from a GitHub Actions job in a workflow file, and that
# job (and, for a reusable workflow, the job that calls it) must have no
# `if:`: a skipped job counts as a pass without running, and a skipped call
# reports no name at all. scripts/require-check-job.py reads the workflow.
# Anything it cannot read is a refusal. Without those limits, for a check from
# another app or one that has not run yet, scripts/upgrade-ruleset.sh.
#
# Edits only the first ruleset (the one with the pull_request rule), adds one
# entry to its required_status_checks and leaves every other field alone.
#
# Everyday tokens, an agent's included, cannot change a ruleset. Run it through
# the wrapper that asks for an admin token at the terminal:
#   scripts/with-admin-token.sh scripts/require-check.sh '<check name>'
set -euo pipefail

usage="usage: require-check.sh [--dry-run] [--repo <owner/name>] <check name>"
dry=0; repo=""
while :; do
  case "${1:-}" in
    --dry-run) dry=1; shift ;;
    --repo)    repo="${2:?$usage}"; shift 2 ;;
    -*)        echo "$usage" >&2; exit 2 ;;
    *) break ;;
  esac
done
[ $# = 1 ] && [ -n "$1" ] || { echo "$usage" >&2; exit 2; }
name="$1"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "require-check: needs a login that administers the repository; an agent's token cannot run it." >&2
echo "  run it as: scripts/with-admin-token.sh scripts/require-check.sh '<check name>'" >&2

if [ -z "$repo" ]; then
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" \
    || { echo "no repository here: run it inside the repository's checkout, or name it with --repo <owner/name>." >&2; exit 2; }
fi

stop() { echo "$1" >&2; echo "  nothing was changed." >&2; exit 1; }

# Administration first, before anything else is read. The repository's
# `permissions` says what the login's role allows; the Actions permissions
# read needs Administration on the token itself (a fine-grained token can
# lack it with an admin role behind it). A token that reads both and still
# cannot write is stopped by GitHub at the write below.
info="$(gh api "repos/$repo" --jq '[(.permissions.admin // false), .default_branch] | @tsv' 2>/dev/null)" \
  || stop "could not read $repo with this login: it does not exist, or this login cannot see it."
admin="${info%%$'\t'*}"; branch="${info#*$'\t'}"
if [ "$admin" != true ] || ! gh api "repos/$repo/actions/permissions" >/dev/null 2>&1; then
  stop "this login does not administer $repo, so it cannot change the ruleset.
  run it again with an admin token: scripts/with-admin-token.sh scripts/require-check.sh --repo $repo '$name'"
fi

# shellcheck source=scripts/lib/rulesets.sh
. "$here/lib/rulesets.sh"
id="$(wall_ruleset_id "$repo")" \
  || stop "no single branch ruleset on $repo carries the pull_request rule (none, more than one, or unreadable)."
cur="$(gh api "repos/$repo/rulesets/$id")" || stop "could not read ruleset $id on $repo."
printf '%s' "$cur" | jq -e '.rules[] | select(.type == "required_status_checks")' >/dev/null \
  || stop "ruleset $id on $repo has no required_status_checks rule to add the name to."
# Names the ruleset requires from GitHub Actions. A required entry is a name
# and an app: the same name from another app, or from any app, does not
# hold an Actions job to passing, so it counts as not required here.
from_actions='.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[]
              | select(.integration_id == 15368) | .context'
required="$(printf '%s' "$cur" | jq -r "$from_actions")"
if printf '%s\n' "$required" | grep -qxF -- "$name"; then
  echo "'$name' is already required from GitHub Actions on $repo; nothing was changed."
  exit 0
fi

# Has the name reported on the default branch? The last ten commits, newest
# first; the first run found is the one whose app and workflow are read.
seen="$(gh api "repos/$repo/commits?sha=$branch&per_page=10" --jq '.[].sha' 2>/dev/null | while read -r sha; do
  [ -n "$sha" ] || continue
  gh api "repos/$repo/commits/$sha/check-runs?per_page=100" \
    --jq '.check_runs[] | [.name, (.app.id // "" | tostring), (.check_suite.id // "" | tostring)] | @tsv' 2>/dev/null
done)" || true
[ -n "$seen" ] || stop "no check could be read on $repo's $branch branch, so '$name' cannot be verified."
hit="$(printf '%s\n' "$seen" | awk -F'\t' -v n="$name" '$1 == n { print; exit }')"
if [ -z "$hit" ]; then
  echo "'$name' has never reported on the last ten commits of $repo's $branch branch." >&2
  echo "  names that did report there:" >&2
  printf '%s\n' "$seen" | cut -f1 | sort -u | sed 's/^/     /' >&2
  echo "  a required name that never arrives means nothing merges. Copy the name from the list," >&2
  echo "  or, for a check that runs on pull requests only, make its workflow run on push to $branch too and merge that first." >&2
  stop "  refused."
fi
app="$(printf '%s' "$hit" | cut -f2)"; suite="$(printf '%s' "$hit" | cut -f3)"
[ "$app" = 15368 ] || stop "'$name' comes from app $app, not GitHub Actions (15368); this script reads Actions jobs only.
  for another app's check: scripts/upgrade-ruleset.sh $repo '$name:$app'"

path="$(gh api "repos/$repo/actions/runs?check_suite_id=$suite" --jq '.workflow_runs[0].path // ""' 2>/dev/null)" || path=""
path="${path%%@*}"
case "$path" in
  .github/workflows/*) ;;
  "") stop "could not read which workflow reported '$name'." ;;
  *)  stop "'$name' comes from $path, which GitHub runs itself (CodeQL's default setup is one), not a workflow file in $repo." ;;
esac
chain="$(python3 "$here/require-check-job.py" "$repo" "$branch" "$path" "$name")" || stop "  refused."

# A job whose needed job fails is skipped, and a skipped check counts as a
# pass: every job it needs must be required already.
deps="$(printf '%s\n' "$chain" | sed -n 's/^needs: //p')"
chain="$(printf '%s\n' "$chain" | grep -v '^needs: ')"
missing=""
while IFS= read -r d; do
  [ -n "$d" ] || continue
  printf '%s\n' "$required" | grep -qxF -- "$d" || missing="$missing     $d"$'\n'
done <<<"$deps"
if [ -n "$missing" ]; then
  echo "'$name' needs these jobs, which are not required from GitHub Actions:" >&2
  printf '%s' "$missing" >&2
  echo "  if one of them fails, '$name' is skipped, and a skipped check counts as a pass." >&2
  echo "  require them first, one name at a time with this script, then '$name'." >&2
  stop "  refused."
fi

new="$(printf '%s' "$cur" | jq --arg n "$name" '
  # Only the fields PUT accepts. Server-side fields (id, created_at, _links) are rejected if sent back.
  {name, target, enforcement, bypass_actors, conditions, rules}
  | .rules |= map(
      if .type == "required_status_checks" then
        # Add only. Existing entries and the strict policy stay as they are.
        .parameters.required_status_checks += [{context: $n, integration_id: 15368}]
      else . end)
')"

echo "-- $repo (ruleset $id, branch $branch)"
echo "   '$name' reported from $chain"
if [ "$dry" = 1 ]; then
  printf '%s' "$new" | jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[] | "   would require: \(.context)"'
  echo "   (--dry-run: nothing written)"
  exit 0
fi
if ! err="$(printf '%s' "$new" | gh api "repos/$repo/rulesets/$id" -X PUT --input - 2>&1 >/dev/null)"; then
  stop "GitHub refused the change: ${err:-no reason given}.
  this login cannot change rulesets on $repo; run it with an admin token."
fi
# The list as GitHub now holds it, read back, not as sent.
back="$(gh api "repos/$repo/rulesets/$id" 2>/dev/null)" \
  || { echo "   sent, but the ruleset could not be read back; look at Settings > Rules > Rulesets." >&2; exit 1; }
printf '%s' "$back" | jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[]
                             | "   requires: \(.context)  (app \(.integration_id // "any"))"'
printf '%s' "$back" | jq -r "$from_actions" | grep -qxF -- "$name" \
  || { echo "   sent, but '$name' from GitHub Actions is not in the list GitHub returns." >&2; exit 1; }
