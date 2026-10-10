#!/usr/bin/env bash
# Merge a pull request the way CONTRIBUTING.md step 5 says, only once nothing
# is left to read. Run by the person who merges, or by an agent on that
# person's word for this one pull request.
#
#   scripts/merge-when-green.sh <pr> [--repo owner/name] [--no-reviewer]
#                               [--reviewer-logins a,b]
#   scripts/merge-when-green.sh <pr> --round [--row <row> "<why>"] [...]
#
# Every run first prints the review round line that `third-party / review`
# writes for this head (scripts/pr-review/attest.py --round, the same files
# read the same way, #485), and from round 3 that a wording fix is answered,
# not pushed. The line never stops anything. With --round it prints only
# that line and exits: GET calls only, no merge, for the moment before a fix
# for a review finding is pushed. --reviewer-logins is the caller's
# `reviewer-logins`, when it is not the reusable workflow's default.
#
# From round 3, or when the round cannot be read, --round also asks for the
# finding's row of "When to stop" in writing, and exits 1 without it: --row
# irreversible (fix and push, whatever the round), issue (open one, answer
# with the link), answer (reply with the reason) or unclassified (stays open
# until another look classifies it), then the reason. It prints the line for
# the description's review section. This is the local script, not the check:
# a `git push` does not run it, and the check never stops on the round
# (#423). What is written before the push is the judgement, as with `verify`.
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

usage="usage: scripts/merge-when-green.sh <pr> [--repo owner/name] [--no-reviewer] [--reviewer-logins a,b] [--round [--row irreversible|issue|answer|unclassified \"<why>\"]]"
stop() { printf 'STOP: %s\n' "$@" >&2; exit 1; }

pr=""; repo=""; reviewer=required; only_round=0; row=""; why=""
# The default of `reviewer-logins` in .github/workflows/pr-review.yml.
logins="chatgpt-codex-connector[bot]"
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="${2:?$usage}"; shift 2 ;;
    --no-reviewer) reviewer=none; shift ;;
    --reviewer-logins) logins="${2:?$usage}"; shift 2 ;;
    --round) only_round=1; shift ;;
    --row)
      [ $# -ge 3 ] || { echo "$usage" >&2; exit 2; }
      case "$2" in irreversible|issue|answer|unclassified) ;; *) echo "$usage" >&2; exit 2 ;; esac
      row="$2"; why="$3"; shift 3 ;;
    -h|--help) echo "$usage"; exit 0 ;;
    *) [ -z "$pr" ] && [[ "$1" =~ ^[0-9]+$ ]] || { echo "$usage" >&2; exit 2; }; pr="$1"; shift ;;
  esac
done
[ -n "$pr" ] || { echo "$usage" >&2; exit 2; }
[ -z "$row" ] || [ "$only_round" = 1 ] || { echo "--row goes with --round" >&2; echo "$usage" >&2; exit 2; }
[ -n "$repo" ] || repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)" || stop "cannot tell the repository; pass --repo owner/name"

poll="${MERGE_POLL:-20}"

state="$(gh pr view "$pr" -R "$repo" --json state --jq .state)" || stop "cannot read pull request $pr in $repo"
[ "$state" = OPEN ] || stop "pull request $pr is $state"
# The head this run reads and merges. Everything below is about this commit.
head="$(gh pr view "$pr" -R "$repo" --json headRefOid --jq .headRefOid)" || stop "cannot read the head of $pr"
echo "pull request $repo#$pr, head $head"

# -- the review round ----------------------------------------------------------
# The files pr-review.yml's step fetches, fetched the same way (a failed call
# leaves `null`), judged by the same attest.py. Read-only, and never a stop.
# Sets `spent` for --round: yes from round 3, unread when it cannot tell
# (attest.py failed, or a fetch failed and the count is a lower bound).
spent=unread
round() {
  local d branch line
  d="$(mktemp -d)" || { echo "review round: not read (no temporary directory)"; return; }
  get() { gh api "repos/$repo/$1" --paginate > "$d/$2" 2>/dev/null || echo 'null' > "$d/$2"; }
  get "pulls/$pr/reviews"   reviews.json
  get "pulls/$pr/comments"  rcomments.json
  get "issues/$pr/comments" icomments.json
  if branch="$(gh pr view "$pr" -R "$repo" --json headRefName --jq .headRefName 2>/dev/null)" && [ -n "$branch" ]; then
    gh api --method GET "repos/$repo/activity" -f ref="refs/heads/$branch" -f direction=desc -F per_page=100 \
      > "$d/activity.json" 2>/dev/null || echo 'null' > "$d/activity.json"
  else
    echo 'null' > "$d/activity.json"
  fi
  if line="$(GITHUB_STEP_SUMMARY='' python3 "$(dirname "${BASH_SOURCE[0]}")/pr-review/attest.py" --round "$head" "$logins" \
      "$d/reviews.json" "$d/rcomments.json" "$d/icomments.json" "$d/activity.json")" && [ -n "$line" ]; then
    echo "$line"
    case "$line" in
      *"review budget is spent"*)
        spent=yes
        echo "A wording fix is answered on its thread, not pushed: a push starts another round." ;;
      "review round at least "*) ;;   # a lower bound may already be past it
      *) spent=no ;;
    esac
  else
    echo "review round: not read (attest.py failed)"
  fi
  rm -rf "$d"
}
round
if [ "$only_round" = 1 ]; then
  if [ -n "$row" ]; then
    [ -n "${why//[[:space:]]/}" ] || { echo "--row $row needs the reason, in words" >&2; exit 1; }
    printf 'For the description'"'"'s review section: row %s: %s\n' "$row" "$why"
    case "$row" in
      irreversible) echo "Fix it and push, whatever the round." ;;
      issue) echo "Open an issue, answer the thread with its link, and do not push a fix for it." ;;
      answer) echo "Answer the thread with the reason, and do not push a fix for it." ;;
      unclassified) echo "It stays open: no merge past it until another look classifies it." ;;
    esac
  elif [ "$spent" != no ]; then
    [ "$spent" = yes ] || echo "The round could not be read, so it may be past the budget."
    echo "Before pushing a fix, write the finding's row and why (When to stop):" >&2
    echo "  scripts/merge-when-green.sh $pr --round --row irreversible|issue|answer|unclassified \"<why>\"" >&2
    echo "  irreversible: irreversible, or reaches other people; judge by what the diff does, not the reviewer's label" >&2
    exit 1
  fi
  exit 0
fi

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
