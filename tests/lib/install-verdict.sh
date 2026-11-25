#!/usr/bin/env bash
# The verdict of `ci / install` (#1135). Its tests run in the `install-<n>`
# jobs of plinth-ci.yml, at once on separate runners; the `install` job needs
# them all, and this step passes only when every one of them succeeded.
#
#   NEEDS='${{ toJSON(needs) }}' tests/lib/install-verdict.sh <plinth-ci.yml>
#
# Fail-closed: a job the workflow declares but `needs` does not list (its
# result would never be read), a result other than success (failure,
# cancelled, skipped), no install-<n> job at all, or NEEDS that is not JSON
# each fail. For a failed job it names the failed step and the test that step
# runs, read from the run's jobs through the API (GH_TOKEN, GITHUB_REPOSITORY,
# GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT, `actions: read`); when that cannot be
# read it still fails and says to open the job.
set -uo pipefail
wf="${1:?usage: install-verdict.sh <plinth-ci.yml>}"
fail=0
err() { fail=1; printf '::error title=ci / install::%s\n' "$1"; }

declared="$(sed -nE 's/^  (install-[0-9]+):[[:space:]]*$/\1/p' "$wf" | sort)"
results="$(jq -r 'to_entries[] | "\(.key) \(.value.result)"' <<<"${NEEDS:-}" 2>/dev/null)" \
  || { err "NEEDS is not the needs context as JSON; nothing was verified"; exit 1; }
[ -n "$declared" ] || { err "no install-<n> job in $wf; nothing was verified"; exit 1; }

failed=""
for j in $declared; do
  r="$(awk -v j="$j" '$1 == j { print $2 }' <<<"$results")"
  case "$r" in
    success) printf '  PASS  ci / %s\n' "$j" ;;
    '') err "ci / $j is not in the install job's needs, so its result is never read: add it there" ;;
    *) err "ci / $j: $r"; failed="$failed $j" ;;
  esac
done
for j in $(awk '{ print $1 }' <<<"$results"); do
  grep -qx "$j" <<<"$declared" || err "needs lists $j, which $wf does not declare as an install-<n> job"
done
[ "$fail" = 0 ] && { echo "  PASS  every install-<n> job succeeded"; exit 0; }

# test_of <step name>: the ./tests/<file> the step with that name runs.
test_of() {
  awk -v n="$1" '
    { line = $0; sub(/^[[:space:]]*-?[[:space:]]*/, "", line) }
    line == "name: " n { hit = 1; next }
    hit && line ~ /^- name: |^name: / { exit }
    hit && match(line, /\.\/tests\/[A-Za-z0-9._-]+/) { print substr(line, RSTART, RLENGTH); exit }
  ' "$wf"
}
if [ -n "$failed" ]; then
  api="repos/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}/attempts/${GITHUB_RUN_ATTEMPT:-1}/jobs?per_page=100"
  if jobs="$(gh api "$api" 2>&1)"; then
    for j in $failed; do
      steps="$(jq -r --arg j "$j" '.jobs[] | select(.name == $j or (.name | endswith(" / " + $j)))
        | . as $job | .steps[]? | select(.conclusion == "failure") | "\(.name)\t\($job.html_url)"' <<<"$jobs")"
      if [ -z "$steps" ]; then
        echo "  ci / $j: no failed step in the run's record (cancelled or timed out?); open the job's log"
        continue
      fi
      while IFS=$'\t' read -r name url; do
        t="$(test_of "$name")"
        echo "  FAIL  ci / $j, step \"$name\"${t:+ ($t)}: $url"
      done <<<"$steps"
    done
  else
    echo "  ci / install could not read which step failed ($(head -n1 <<<"$jobs")); open the failed job's log:$failed"
  fi
fi
echo "failed: ci / install, because an install-<n> job did not succeed"
echo "next: open the job named above, fix what its failed step names, and push; a local run is that step's ./tests/ file"
exit 1
