#!/usr/bin/env bash
# Create the merge ruleset (ruleset-merge.json) on an existing repository.
# Run by a person; needs repository administration.
#
#   create-merge-ruleset.sh [--dry-run] <owner/name> ...
#
# Why: the first ruleset has no bypass actor, so it holds the admin to the
# same checks as everyone else, and anyone with write access who can open a
# pull request can also merge it once the checks pass. This second ruleset
# restricts updates to the default branch and lets the repository's admin
# role bypass that through a pull request only. While the agent works under
# the person's own account it changes nothing; an agent with an account of
# its own (a collaborator with write access) can no longer merge (#568,
# measured there).
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
file="$here/../ruleset-merge.json"
dry=0
[ "${1:-}" = "--dry-run" ] && { dry=1; shift; }
[ $# -gt 0 ] || { echo "usage: create-merge-ruleset.sh [--dry-run] <owner/name> ..." >&2; exit 2; }

name="$(jq -r .name "$file")"
# What is compared after the write: the fields the file sets, in the order
# GitHub may return them, bypass actors reduced to the three that matter.
shape='{name, target, enforcement, conditions, rules: [.rules[] | {type}],
        bypass_actors: [.bypass_actors[] | {actor_id, actor_type, bypass_mode}]}'
want="$(jq -cS "$shape" "$file")"

fail=0
for repo in "$@"; do
  # Never twice: two rulesets with one name and nobody knows which one holds.
  if ! ids="$(gh api "repos/$repo/rulesets" --jq ".[] | select(.name == $(jq .name "$file")) | .id")"; then
    echo "-- $repo: could not list its rulesets; not applied" >&2; fail=1; continue
  fi
  if [ -n "$ids" ]; then
    echo "-- $repo: a ruleset named '$name' already exists; skipped"
    continue
  fi

  if [ "$dry" = 1 ]; then
    echo "-- $repo: would create '$name' (update, bypassed by the admin role in pull_request mode)  (--dry-run: nothing written)"
    continue
  fi

  if ! id="$(gh api "repos/$repo/rulesets" -X POST --input "$file" --jq .id)"; then
    echo "-- $repo: GitHub refused the ruleset; not applied" >&2; fail=1; continue
  fi

  # Written, then read back. A 200 is not proof that it took (measured).
  got="$(gh api "repos/$repo/rulesets/$id" | jq -cS "$shape" 2>/dev/null || true)"
  if [ "$got" = "$want" ]; then
    echo "-- $repo: '$name' applied (ruleset $id)"
  else
    echo "-- $repo: ruleset $id reads back as ${got:-nothing}, expected $want: not applied as written" >&2
    fail=1
  fi
done

[ "$fail" = 0 ] || { echo "at least one repository did not take the ruleset." >&2; exit 1; }
