#!/usr/bin/env bash
# Merge a pull request the way CONTRIBUTING.md step 5 says, only once nothing
# is left to read. Run by the person who merges, or by an agent on that
# person's word for this one pull request.
#
#   scripts/merge-when-green.sh <pr> [--repo owner/name] [--no-reviewer]
#
# It stops, and merges nothing, when:
#   - a check on the head is not SUCCESS once they have all finished;
#   - the head has no `third-party / review` and --no-reviewer was not given:
#     whether to merge without a reviewer is the person's call, not a default.
#     Where it is there, its green is the reviewer's verdict: the check binds
#     each signal to this head and to the head's push in the activity log
#     (scripts/pr-review/attest.py), which this script does not redo. It also
#     passes, by the repository's policy, on its Dependabot and release
#     exceptions, with no review;
#   - any top-level inline comment, on any commit, has no reply: every finding
#     ends as fixed, answered or moved to an issue, and the reply says which.
# Then it squash-merges with the description as the body and
# --match-head-commit, so a commit pushed while it waited stops the merge.
# A merged pull request is not undone by anything here; a stop changes nothing.
set -uo pipefail

usage="usage: scripts/merge-when-green.sh <pr> [--repo owner/name] [--no-reviewer]"
stop() { printf 'STOP: %s\n' "$@" >&2; exit 1; }

pr=""; repo=""; reviewer=required
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="${2:?$usage}"; shift 2 ;;
    --no-reviewer) reviewer=none; shift ;;
    -h|--help) echo "$usage"; exit 0 ;;
    *) [ -z "$pr" ] && [[ "$1" =~ ^[0-9]+$ ]] || { echo "$usage" >&2; exit 2; }; pr="$1"; shift ;;
  esac
done
[ -n "$pr" ] || { echo "$usage" >&2; exit 2; }
[ -n "$repo" ] || repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)" || stop "cannot tell the repository; pass --repo owner/name"

poll="${MERGE_POLL:-20}"

state="$(gh pr view "$pr" -R "$repo" --json state --jq .state)" || stop "cannot read pull request $pr in $repo"
[ "$state" = OPEN ] || stop "pull request $pr is $state"
# The head this run reads and merges. Everything below is about this commit.
head="$(gh pr view "$pr" -R "$repo" --json headRefOid --jq .headRefOid)" || stop "cannot read the head of $pr"
echo "pull request $repo#$pr, head $head"

# -- checks ----------------------------------------------------------------
gh pr checks "$pr" -R "$repo" --watch --interval "$poll" >/dev/null 2>&1
# One line per check name. A name can carry several runs on the head: a
# review that lands after the review check gave up starts a new run that
# passes beside the failed one (#369, #363). The run started last speaks for
# the name (not the one finished last: overlapping runs can finish out of
# order), and an unfinished one, if any, holds it.
checks="$(gh pr checks "$pr" -R "$repo" --json name,state,startedAt,completedAt --jq '
  def pending: .state | IN("PENDING", "QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED", "EXPECTED");
  group_by(.name)
  | map(if any(.[]; pending) then (map(select(pending)) | .[0]) else max_by(.startedAt // .completedAt // "") end)
  | .[] | "\(.state)\t\(.name)"')" || stop "cannot read the checks"
[ -n "$checks" ] || stop "no checks reported on $head"
bad="$(awk -F'\t' '$1!="SUCCESS"' <<<"$checks")"
[ -z "$bad" ] || stop "checks not green:" "$bad"
echo "checks: $(wc -l <<<"$checks" | tr -d ' ') green"

# -- the reviewer ----------------------------------------------------------
if grep -qxF "SUCCESS	third-party / review" <<<"$checks"; then
  echo "reviewer: third-party / review is green on this head"
elif [ "$reviewer" = none ]; then
  echo "reviewer: none on this repository (--no-reviewer)"
else
  stop "no third-party / review check on $head; pass --no-reviewer to merge without one"
fi

# -- every inline comment answered -------------------------------------------
comments="$(gh api --paginate "repos/$repo/pulls/$pr/comments" --jq '.[]|"\(.id)\t\(.in_reply_to_id // "")\t\(.path):\(.line // .original_line)\t\(.body|split("\n")[0])"')" \
  || stop "cannot read the inline comments"
open="$(awk -F'\t' '$2!=""{answered[$2]=1; next} {top[NR]=$0; id[NR]=$1} END{for (i in top) if (!(id[i] in answered)) print top[i]}' <<<"$comments")"
[ -z "$open" ] || stop "inline comments with no reply (fix, answer or move each, and reply):" "$open"

# -- merge -------------------------------------------------------------------
body="$(gh pr view "$pr" -R "$repo" --json body --jq .body)" || stop "cannot read the description"
[ -n "$body" ] || stop "the description is empty; it becomes the squash commit"
gh pr merge "$pr" -R "$repo" --squash --match-head-commit "$head" --body "$body" || stop "gh pr merge refused"
gh pr view "$pr" -R "$repo" --json state,mergeCommit --jq '"\(.state) \(.mergeCommit.oid)"'
