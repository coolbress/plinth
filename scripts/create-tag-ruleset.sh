#!/usr/bin/env bash
# Create a tag ruleset on a repository. Run by a person; needs repository
# administration.
#
#   create-tag-ruleset.sh [--dry-run] <owner/name> ...
#
# Why tags: a tag is what a pin comment claims. Consumers call
# `uses: coolbress/plinth/...@<sha> # v1.2.0`; the run uses the SHA, so moving
# the tag changes no code. What changes is whether the comment is true: once
# `v1.2.0` points elsewhere, release notes, pin comments and the release tool
# all lie. And a deleted tag is a release that vanished.
#
# Two things are blocked: deletion and moving (non-fast-forward). Creation is
# not, or no release could be cut.
#
# `upgrade-ruleset.sh` and `add-ruleset-rule.sh` edit the existing branch
# ruleset; this creates a new one, because a ruleset has one target.
#
# Everyday tokens get a 403 here. Run it through the wrapper:
#   scripts/with-admin-token.sh scripts/create-tag-ruleset.sh <owner/name>
set -euo pipefail

dry=0
[ "${1:-}" = "--dry-run" ] && { dry=1; shift; }
[ $# -gt 0 ] || { echo "usage: create-tag-ruleset.sh [--dry-run] <owner/name> ..." >&2; exit 2; }

NAME="tags: no deletion, no force-push"

body() {
  jq -n --arg name "$NAME" '{
    name: $name,
    target: "tag",
    enforcement: "active",
    bypass_actors: [],                      # zero: owners included, like the branch ruleset
    conditions: { ref_name: { include: ["~ALL"], exclude: [] } },
    rules: [ { type: "deletion" }, { type: "non_fast_forward" } ]
  }'
}

fail=0
for repo in "$@"; do
  # Never twice: two rulesets with one name and nobody knows which one holds.
  if gh api "repos/$repo/rulesets" --jq '.[] | select(.target == "tag") | .id' | grep -q .; then
    echo "-- $repo: a tag ruleset already exists; skipped"
    continue
  fi

  if [ "$dry" = 1 ]; then
    echo "-- $repo: would create the tag ruleset (deletion, non_fast_forward, 0 bypass actors)  (--dry-run: nothing written)"
    continue
  fi

  body | gh api "repos/$repo/rulesets" -X POST --input - >/dev/null

  # Written, then read back. A 200 is not proof that it took (measured).
  got="$(gh api "repos/$repo/rulesets" --jq '[.[] | select(.target == "tag")] | length')"
  if [ "$got" = "1" ]; then
    echo "-- $repo: tag ruleset applied"
  else
    echo "-- $repo: $got tag rulesets after the write, expected 1: not applied" >&2
    fail=1
  fi
done

[ "$fail" = 0 ] || { echo "at least one repository did not take the ruleset." >&2; exit 1; }
