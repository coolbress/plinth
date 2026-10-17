#!/usr/bin/env bash
# Create the merge ruleset (ruleset-merge.json) on an existing repository.
# Run by a person; needs repository administration.
#
#   create-merge-ruleset.sh [--dry-run] <owner/name> ...
#
# Why: the first ruleset has no bypass actor, so it holds the admin to the
# same checks as everyone else, and anyone with write access who can open a
# pull request can also merge it once the checks pass. This second ruleset
# restricts updates to the default branch and exempts the repository's admin
# role from that, so the admin's merges, `gh pr merge` and auto-merge
# included, go on as before. While the agent works under the person's own
# account it changes nothing; an agent with an account of its own (a
# collaborator with write access) can no longer merge, nor can auto-merge it
# enabled (measured on #568 and #517). The admin's merges past it leave no
# bypass audit entry, as GitHub documents for `exempt`.
#
# The door (new-project.sh) applies it to every new repository. This adds it
# to one the door made before. A separate ruleset and not a rule added to the
# first: a bypass actor reaches every rule of its ruleset, so on the first one
# it would let the admin around the checks too. `upgrade-ruleset.sh` and
# `add-ruleset-rule.sh` edit the first ruleset and leave this one alone.
#
# Everyday tokens get a 403 here. Run it through the wrapper:
#   scripts/with-admin-token.sh scripts/create-merge-ruleset.sh <owner/name>
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/rulesets.sh
. "$here/lib/rulesets.sh"
file="$here/../ruleset-merge.json"
dry=0
[ "${1:-}" = "--dry-run" ] && { dry=1; shift; }
[ $# -gt 0 ] || { echo "usage: create-merge-ruleset.sh [--dry-run] <owner/name> ..." >&2; exit 2; }

name="$(jq -r .name "$file")"
want="$(jq -cS "$ruleset_shape" "$file")"

fail=0
for repo in "$@"; do
  # Never twice: two rulesets with one name and nobody knows which one holds.
  # Every page: GitHub lists 30 rulesets a page unless asked for more.
  if ! ids="$(gh api --paginate "repos/$repo/rulesets?per_page=100" --jq ".[] | select(.name == $(jq .name "$file")) | .id")"; then
    echo "-- $repo: could not list its rulesets; not applied" >&2; fail=1; continue
  fi
  # One already there is applied only if it reads as the file: a write that
  # did not take, or another ruleset under this name, is said, never skipped
  # as done. Fixing it is a person's call (delete it, then run this again).
  if [ -n "$ids" ]; then
    if [ "$(grep -c . <<<"$ids")" = 1 ] && got="$(ruleset_reads_as "$repo" "$ids" "$file")"; then
      echo "-- $repo: '$name' already applied (ruleset $ids); skipped"
    else
      echo "-- $repo: a ruleset named '$name' exists but does not read as ruleset-merge.json: $(tr '\n' ' ' <<<"$ids")${got:+($got)}; not applied" >&2
      echo "   expected $want; delete it in the repository's Settings → Rules, then run this again" >&2
      fail=1
    fi
    continue
  fi

  if [ "$dry" = 1 ]; then
    echo "-- $repo: would create '$name' (update, the admin role exempt)  (--dry-run: nothing written)"
    continue
  fi

  if ! id="$(gh api "repos/$repo/rulesets" -X POST --input "$file" --jq .id)"; then
    echo "-- $repo: GitHub refused the ruleset; not applied" >&2; fail=1; continue
  fi

  # Written, then read back. A 200 is not proof that it took (measured).
  if got="$(ruleset_reads_as "$repo" "$id" "$file")"; then
    echo "-- $repo: '$name' applied (ruleset $id)"
  else
    echo "-- $repo: ruleset $id reads back as ${got:-nothing}, expected $want: not applied as written" >&2
    fail=1
  fi
done

[ "$fail" = 0 ] || { echo "at least one repository did not take the ruleset." >&2; exit 1; }
