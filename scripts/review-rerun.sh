#!/usr/bin/env bash
# The step of .github/workflows/review-rerun.yml (#363): which pull requests to
# look at for this event, and the re-run of each failed review run that
# review-rerun.py says to ask again. tests/review-rerun-step.sh runs it against
# a fake gh.
#
# Environment: REPO, LOGINS (accepted reviewers, comma separated), EVENT
# (github.event_name); for issue_comment also PR (the issue number), IS_PR
# (the issue's pull_request URL, empty on an issue) and COMMENTER (the
# comment's author). GH_TOKEN is the job's token.
#
# A comment is any comment in the repository, so it ends here, with no call,
# unless an accepted reviewer wrote it on a pull request. The pull request's
# code is never checked out or run: the workflow runs from the default branch,
# and only the API is read.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
d="${RUNNER_TEMP:?}"

if [ "${EVENT:-}" = issue_comment ]; then
  if [ -z "${IS_PR:-}" ]; then
    echo "a comment on issue #${PR:-?}, not a pull request: nothing to do."
    exit 0
  fi
  who="$(printf '%s' "${COMMENTER:-}" | tr '[:upper:]' '[:lower:]')"
  accepted=0
  IFS=, read -ra names <<< "$LOGINS"
  for name in "${names[@]}"; do
    name="$(printf '%s' "$name" | tr -d ' ' | tr '[:upper:]' '[:lower:]')"
    [ -n "$name" ] && [ "$name" = "$who" ] && accepted=1
  done
  if [ "$accepted" = 0 ]; then
    echo "comment on #$PR by ${COMMENTER:-?}, not an accepted reviewer: nothing to do."
    exit 0
  fi
  # That pull request alone, and only while it is open.
  prs="$(gh api "repos/$REPO/pulls/$PR" --jq 'select(.state == "open") | "\(.number) \(.head.sha)"')"
  [ -n "$prs" ] || { echo "#$PR is not open: nothing to do."; exit 0; }
else
  prs="$(gh api "repos/$REPO/pulls?state=open&per_page=100" --paginate --jq '.[] | "\(.number) \(.head.sha)"')"
  [ -n "$prs" ] || { echo "no open pull requests."; exit 0; }
fi

# A failed call leaves `null`, which review-rerun.py reads as nothing: no
# re-run, so the failure stays the one a person sees today.
get() { gh api "repos/$REPO/$1" --paginate > "$d/$2" 2>/dev/null || echo 'null' > "$d/$2"; }
failed=0
while read -r n sha; do
  # One page, newest first: only the newest run is read.
  gh api "repos/$REPO/actions/workflows/third-party.yml/runs?head_sha=$sha&per_page=100" --jq '.workflow_runs' \
    > "$d/runs.json" 2>/dev/null || echo 'null' > "$d/runs.json"
  get "pulls/$n/reviews"    reviews.json
  get "pulls/$n/comments"   rcomments.json
  get "issues/$n/comments"  icomments.json
  get "issues/$n/reactions" reactions.json
  if why="$(python3 "$here/review-rerun.py" "$LOGINS" "$d/runs.json" "$d/reviews.json" "$d/rcomments.json" "$d/icomments.json" "$d/reactions.json")"; then
    id="${why#re-run }"; id="${id%%:*}"
    if gh run rerun "$id" --failed --repo "$REPO"; then
      echo "#$n ${sha:0:8}: $why"
      continue
    fi
    # The comment and the schedule can both decide on the same run; the
    # second is refused because the first already started it. Only a status
    # read back as active says so: a lookup that fails or reads anything else
    # is a re-run nobody asked for, and the job fails (#365's review).
    now="$(gh run view "$id" --repo "$REPO" --json status --jq .status 2>/dev/null)" || now="unread"
    case "$now" in
      queued|in_progress|waiting|requested|pending)
        echo "#$n ${sha:0:8}: run $id is already running again ($now); nothing to do ($why)" ;;
      *)
        echo "::error::#$n ${sha:0:8}: could not re-run $id, its status reads ${now:-empty} ($why)"
        failed=1 ;;
    esac
  else
    echo "#$n ${sha:0:8}: $why"
  fi
done <<< "$prs"
exit "$failed"
