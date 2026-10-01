#!/usr/bin/env bash
# A step of `ci / docs` in .github/workflows/plinth-ci.yml (#293): fail a pull
# request whose description would close an issue outside its closing line.
# It asks GitHub which issues the merge will close, with the description read
# in the same call, and closing-references.py compares the two.
# tests/closing-references-cases.sh runs it against a fake gh.
#
# Environment: REPO (owner/name), EVENT (github.event_name), PR (the pull
# request's number, empty on any other event). GH_TOKEN is the job's token; it
# needs `pull-requests: read` and `issues: read`.
#
# Anything that cannot be read fails: a pass here means GitHub's list was read
# and compared, as it stood when this ran. An issue linked in the sidebar
# afterwards starts no new run, and the title is not read.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${EVENT:-}" != pull_request ]; then
  echo "not a pull request (${EVENT:-no event}): no description to read."
  exit 0
fi
case "${PR:-}" in
  ''|*[!0-9]*) echo "::error::a pull_request event, but the pull request number reads '${PR:-}'"; exit 1 ;;
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
  echo "::error::could not read #$PR's description and closing list from GitHub"
  exit 1
fi

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
  echo "::error::#$PR's description would close an issue outside its closing line, or could not be read: see the lines above"
  exit 1
fi
