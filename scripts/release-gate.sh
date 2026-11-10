#!/usr/bin/env bash
# The step of `ci / release-gate` in .github/workflows/plinth-ci.yml (#863):
# a release pull request merges only after a green `e2e` run on its head. The
# merge is what reaches every installation with auto-update on, and the
# ruleset, which requires this check, holds the merge button and a bare
# `gh pr merge` too, not only scripts/merge-when-green.sh.
#
# GitHub cannot require a check of some pull requests alone: a ruleset targets
# the base branch, and a workflow skipped by a filter leaves its check pending.
# So this job runs on every pull request and decides here.
#
# A pull request is a release when its head branch is release/v*, its title
# starts `chore(release):`, or its diff changes a "version" line of
# .claude-plugin/plugin.json or .claude-plugin/marketplace.json. The last is
# read from the checkout's merge commit against its first parent, and fails
# closed: anything that would ship a new version needs e2e. Anything else
# passes at once.
#
# A release passes when the e2e run started last on its head SHA (the pull
# request's head, not the merge ref), of those on a release/v* branch, is
# green: on any other ref scripts/e2e.sh keeps the template's pin, so a green
# run there never called this commit's workflows (#862). merge-when-green.sh
# reads the same runs the same way and re-runs this job once that run is green.
#
# Environment: EVENT (github.event_name), REPO (owner/name), HEAD_REF and
# TITLE (the pull request's head branch and title, through env: only),
# HEAD_SHA (github.event.pull_request.head.sha). GH_TOKEN is the job's token,
# with `actions: read`. Run from the checkout of the merge commit, at least two
# deep. tests/release-gate-cases.sh runs it against a fake gh.
#
# Anything it cannot read fails: the diff, the runs, the head SHA.
set -euo pipefail
HOW="https://github.com/coolbress/plinth/blob/main/docs/how-to/cut-a-release.md"
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
standard="a release pull request has a green e2e run on its head"

pass() { echo "$1"; echo "pass: $standard${2:+, $2}" >>"$summary"; exit 0; }
die()  { echo "::error::$1 $HOW"; echo "fail: $standard; $1" >>"$summary"; exit 1; }

[ "${EVENT:-}" = pull_request ] || pass "not a pull request (${EVENT:-no event}): nothing merges from here." \
  "does not apply (not a pull request)"
[ -n "${HEAD_REF:-}" ] || die "a pull_request event, but the head branch reads empty. Re-run this job from the pull request:"

why=()
[[ "$HEAD_REF" == release/v* ]] && why+=("its branch $HEAD_REF is release/v*")
[[ "${TITLE:-}" == "chore(release):"* ]] && why+=("its title starts chore(release):")
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
  # Every "version" value in the file, wherever it sits on a line, on each
  # side; a side git or jq cannot read (a file added, deleted or not JSON)
  # fails, git's failure included: pipefail holds inside $( ).
  for side in HEAD^1 HEAD; do
    v="$(git show "$side:$f" 2>&1 | jq -c '[.. | objects | .version? | select(. != null)]' 2>&1)" \
      || die "cannot read the \"version\" values of $f at $side (${v%%$'\n'*}), so whether this pull request ships a version is unknown. Re-run the job:"
    [ "$side" = HEAD ] && after="$v" || before="$v"
  done
  if [ "$before" != "$after" ]; then
    why+=("it changes the \"version\" line of $f")
  fi
done

if [ "${#why[@]}" = 0 ]; then
  pass "not a release: the branch is $HEAD_REF, the title does not start chore(release):, and neither manifest's \"version\" line changes." \
    "does not apply (not a release)"
fi
reason="${why[0]}"; for w in "${why[@]:1}"; do reason+="; $w"; done
echo "a release: $reason."

case "${HEAD_SHA:-}" in
  *[!0-9a-f]*|'') die "a release, but the head SHA reads '${HEAD_SHA:-}'. Re-run this job from the pull request:" ;;
esac
[ "${#HEAD_SHA}" = 40 ] || die "a release, but the head SHA '$HEAD_SHA' is not a full commit SHA. Re-run this job from the pull request:"

# Newest first; the select repeats the head, as merge-when-green.sh's does.
runs="$(gh api -X GET "repos/$REPO/actions/workflows/e2e.yml/runs" -f "head_sha=$HEAD_SHA" -F per_page=100 \
          --jq ".workflow_runs | map(select(.head_sha == \"$HEAD_SHA\" and ((.head_branch // \"\") | startswith(\"release/v\")))) | sort_by(.run_started_at // .created_at) | reverse | .[] | \"\(.conclusion // .status) \(.html_url)\"" 2>&1)" \
  || die "cannot read the e2e runs on $HEAD_SHA ($(tr '\n' ' ' <<<"$runs")), so the release is not known to be tested. Re-run the job:"
newest="${runs%%$'\n'*}"
case "$newest" in
  "success "*) pass "e2e: green on $HEAD_SHA, on a release/v* branch: ${newest#success }" ;;
esac

[ -n "$runs" ] && printf 'e2e runs on %s from a release/v* branch, newest first:\n%s\n' "$HEAD_SHA" "$runs"
if [[ "$HEAD_REF" == release/v* ]]; then
  next="gh workflow run e2e.yml --ref $HEAD_REF, then once it is green: scripts/merge-when-green.sh <pr> re-runs this job."
else
  next="move it to a release/v* branch (an e2e run elsewhere never calls this commit's workflows), then gh workflow run e2e.yml --ref release/vX.Y.Z."
fi
if [ -z "$runs" ]; then
  die "a release ($reason) with no e2e run on its head $HEAD_SHA from a release/v* branch. Next: $next"
fi
die "a release ($reason) whose e2e run started last on $HEAD_SHA is not green: ${newest}. Next: $next"
