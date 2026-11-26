#!/usr/bin/env bash
# A step of `ci / docs` in .github/workflows/plinth-ci.yml (#293), and of
# `ci / pr-title` in python-ci.yml, which fetches it at its own commit (#781):
# fail a pull request whose description would close an issue outside its
# closing line.
# It asks GitHub which issues the merge will close, with the description read
# in the same call, and closing-references.py compares the two.
# tests/closing-references-cases.sh runs it against a fake gh, and
# tests/pr-title-description-cases.sh runs it through python-ci.yml's step.
#
# Environment: REPO (owner/name), EVENT (github.event_name), PR (the pull
# request's number, empty on any other event). GH_TOKEN is the job's token; it
# needs `pull-requests: read` and `issues: read`. ANSWER_COPY, when set, is a
# path that gets GitHub's answer once read, for description-fields.py (#810).
# MESSAGE_FILE, when set, gets the failure as "<what><TAB><next step>" and
# no annotation is printed: ci / pr-title's step prints the one annotation
# for it (#1100). ci / docs leaves it unset and keeps the annotation.
#
# Anything that cannot be read fails: a pass here means GitHub's list was read
# and compared, as it stood when this ran. An issue linked in the sidebar
# afterwards starts no new run, and the title is not read.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# At the plinth commit the workflow fetched this from (job.workflow_sha); main run by hand.
at="${PLINTH_SHA:-main}"
HOW="https://github.com/coolbress/plinth/blob/${at:0:12}/CONTRIBUTING.md#land-a-change"

if [ "${EVENT:-}" != pull_request ]; then
  echo "not a pull request (${EVENT:-no event}): no description to read."
  exit 0
fi
case "${PR:-}" in
  ''|*[!0-9]*) if [ -n "${MESSAGE_FILE:-}" ]; then printf "%s\t%s\n" "a pull_request event, but the pull request number reads '${PR:-}'" "re-run this job from the pull request" > "$MESSAGE_FILE"
              else echo "::error::a pull_request event, but the pull request number reads '${PR:-}'. Re-run this job from the pull request: $HOW"; fi; exit 1 ;;
esac

answer="$(mktemp)"; trap 'rm -f "$answer"' EXIT
# shellcheck disable=SC2016  # $owner, $name and $number are GraphQL's variables
if ! gh api graphql -f owner="${REPO%%/*}" -f name="${REPO#*/}" -F number="$PR" -f query='
  query($owner: String!, $name: String!, $number: Int!) {
    repository(owner: $owner, name: $name) {
      pullRequest(number: $number) {
        body
        closingIssuesReferences(first: 100) {
          nodes { number repository { nameWithOwner } }
          pageInfo { hasNextPage }
        }
      }
    }
  }' >"$answer"; then
  if [ -n "${MESSAGE_FILE:-}" ]; then printf '%s\t%s\n' "#$PR's description and closing list could not be read from GitHub" "re-run this job; its token needs pull-requests: read and issues: read" > "$MESSAGE_FILE"
  else echo "::error::could not read #$PR's description and closing list from GitHub. Re-run this job; its token needs pull-requests: read and issues: read: $HOW"; fi
  exit 1
fi
[ -z "${ANSWER_COPY:-}" ] || cp "$answer" "$ANSWER_COPY"

rc=0
report="$(python3 "$here/closing-references.py" "$REPO" "$answer")" || rc=$?
printf '%s\n' "$report"
{
  echo "### What merging this pull request closes"
  echo
  echo '```text'
  printf '%s\n' "$report"
  echo '```'
} >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
if [ "$rc" != 0 ]; then
  # The first FAIL names the issue, or what could not be read; the rest are in the log.
  first="$(grep -m 1 '^  FAIL  ' <<<"$report" || true)"; first="${first#  FAIL  }"; first="${first:-it could not be read}"
  case "$first" in
    *"closes it when"*) next="Reword the sentence so the keyword does not stand before the number, or put it on the closing line" ;;
    *"more than 100"*) next="Reword the description so it closes fewer issues" ;;
    *) next="Re-run this job" ;;
  esac
  if [ -n "${MESSAGE_FILE:-}" ]; then printf '%s\t%s\n' "#$PR's description: ${first//$'\t'/ }" "$(printf '%s' "${next:0:1}" | tr '[:upper:]' '[:lower:]')${next:1}" > "$MESSAGE_FILE"; exit 1; fi
  # At most 300 characters: what is cut is the first FAIL, never the action and link.
  lead="#$PR's description: "; tail=". $next: $HOW"; room=$((300 - ${#lead} - ${#tail}))
  [ "${#first}" -le "$room" ] || first="${first:0:$((room - 3))}..."
  echo "::error::$lead$first$tail"
  exit 1
fi
