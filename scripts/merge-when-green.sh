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
# not pushed. The line never stops anything. With --round it stops there,
# before the checks and the merge: it prints the head and that line (and,
# with --row or from round 3, what is below), with GET calls only, for the
# moment before a fix for a review finding is pushed. --reviewer-logins is the caller's
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
#   - on coolbress/plinth, the pull request is titled `chore(release): vX.Y.Z`
#     and the `e2e` run started last on the head, of those on a `release/v*`
#     branch, is not green, or there is none (#855, #862): the merge is what reaches an
#     installation with auto-update on, and it cannot be taken back. A
#     dispatched run does not show in `gh pr checks`, so the checks below do not
#     hold on it. The ruleset's `ci / release-gate` (#863) holds it too; that
#     check ran before the dispatch, so on coolbress/plinth a red one is
#     re-run once the e2e run on the head is green, and the checks wait for it;
#   - a check on the head is not SUCCESS once they have all finished, with one
#     exception (#872): a NEUTRAL `CodeQL` on a pull request whose author is
#     dependabot[bot] and whose head has no `Analyze (...)` job in any Actions
#     run. Code scanning's default setup starts no analysis for an event
#     Dependabot causes, so that check is neutral on every such pull request;
#     the push to the base branch runs the analysis, and after the merge this
#     script waits for it and reports passed, failed (exit 1: a failure on the
#     base branch now), or not started, not finished or not read (not
#     confirmed). A neutral `CodeQL` anywhere else stops, saying what it means;
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
# After the merge it prints, for each issue the pull request closes or names
# on a `Part of #N` line, the acceptance criteria still unticked and, for one it
# closed, a missing `## Outcome`, for whoever merged to settle (#490).
# A merged pull request is not undone by anything here; a stop changes nothing.
set -uo pipefail

usage="usage: scripts/merge-when-green.sh <pr> [--repo owner/name] [--no-reviewer] [--reviewer-logins a,b] [--round [--row <irreversible|issue|answer|unclassified> \"<why>\"]]"
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

# Code scanning's analyses at a commit, read from its Actions runs (the token
# that runs this can read those; the check-runs API needs Checks access it may
# lack): one line per `Analyze (...)` job of any run there, and one for a
# default-setup run that lists no such job yet, each
# "<status>\t<conclusion>\t<name>\t<url>". Returns 1 when a read fails.
analyses() {
  local sha="$1" runs id path st co url name jobs
  runs="$(gh api --paginate -X GET "repos/$repo/actions/runs" -f "head_sha=$sha" -F per_page=100 \
    --jq ".workflow_runs[] | select(.head_sha == \"$sha\") | [.id, .path, .status, (.conclusion // \"-\"), .html_url, .name] | @tsv")" || return 1
  while IFS=$'\t' read -r id path st co url name; do
    [ -n "$id" ] || continue
    jobs="$(gh api --paginate "repos/$repo/actions/runs/$id/jobs" \
      --jq '.jobs[] | select(.name | startswith("Analyze (")) | [.status, (.conclusion // "-"), .name, .html_url] | @tsv')" || return 1
    if [ -n "$jobs" ]; then printf '%s\n' "$jobs"
    elif [ "$path" = dynamic/github-code-scanning/codeql ]; then printf '%s\t%s\t%s\t%s\n' "$st" "$co" "$name (no Analyze job listed yet)" "$url"; fi
  done <<<"$runs"
}

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
    # The same target as this run, so the retry reads the same round.
    again="scripts/merge-when-green.sh $pr --repo $(printf '%q' "$repo")"
    [ "$logins" = "chatgpt-codex-connector[bot]" ] || again+=" --reviewer-logins $(printf '%q' "$logins")"
    echo "  $again --round --row <irreversible|issue|answer|unclassified> \"<why>\"" >&2
    echo "  irreversible: irreversible, or reaches other people; judge by what the diff does, not the reviewer's label" >&2
    exit 1
  fi
  exit 0
fi

# -- a release's e2e (#855) ----------------------------------------------------
# By this repository's name, not by whether it has an e2e.yml: another repository
# may use the title with no such workflow, and a 404 read as "nothing to wait
# for" would turn this off the day the file were renamed here. Any read that
# fails stops. The select repeats the head, as make-release.sh's does. Before the
# checks, so a missing run is said without waiting for them. Only a run on a
# release/v* branch counts, whichever way it ended: on any other ref scripts/e2e.sh
# keeps the template's pin, so a green run there never called this commit's
# workflows from another repository (#862). A run's head_branch is also the name
# of a tag it ran on; nothing here tells a tag named release/v* from a branch.
# Newest first. The run started last speaks, as it does for a check name
# below: a green run does not excuse a later red one, or one still going.
e2e_runs_on_head() {
  gh api -X GET "repos/$repo/actions/workflows/e2e.yml/runs" -f "head_sha=$head" -F per_page=100 \
    --jq ".workflow_runs | map(select(.head_sha == \"$head\" and ((.head_branch // \"\") | startswith(\"release/v\")))) | sort_by(.run_started_at // .created_at) | reverse | .[] | \"\(.conclusion // .status) \(.html_url)\"" 2>&1
}
plinth=no; [ "$(tr '[:upper:]' '[:lower:]' <<<"$repo")" = coolbress/plinth ] && plinth=yes
if [ "$plinth" = yes ]; then
  title="$(gh pr view "$pr" -R "$repo" --json title --jq .title)" || stop "cannot read the title of $pr"
  if [[ "$title" =~ ^chore\(release\):\ v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    runs="$(e2e_runs_on_head)" || stop "cannot read the e2e runs on $head: $runs"
    newest="${runs%%$'\n'*}"
    case "$newest" in
      "success "*) ;;
      *)
        branch="$(gh pr view "$pr" -R "$repo" --json headRefName --jq .headRefName)" || stop "cannot read the branch of $pr"
        stop "the e2e run started last on $head on a release/v* branch is not green; a release merges only after a green one, because the merge reaches every installation with auto-update on:" \
             "${runs:-(no run on a release/v* branch at that commit)}" \
             "run it, unless the newest run above is still going, then wait for it: gh workflow run e2e.yml --ref $branch --repo $repo   (on HTTP 403, through scripts/with-admin-token.sh: docs/how-to/cut-a-release.md, step 5)" \
             "then, once it is green, run this again" ;;
    esac
    echo "e2e: green on this head, on a release/v* branch: ${newest#success }"
  fi
fi

# -- ci / release-gate (#863) ------------------------------------------------
# On coolbress/plinth the ruleset requires `ci / release-gate`, which fails a
# release (a release/v* branch, a chore(release): title, a changed manifest
# version: wider than the title above) until its head has a green e2e run. It
# ran when the head was pushed, before a dispatched e2e run existed, and a
# dispatched run starts no check of the pull request, so nothing re-runs it
# but this: when it is red and the e2e run started last on the head, from a
# release/v* branch, is green, once, by its job; then the checks below wait
# for the new attempt. Red with no green e2e run: the checks below stop on it,
# and its log says what to run. The name's run started last speaks, as below.
if [ "$plinth" = yes ]; then
  gate_jq='def pending: .state | IN("PENDING", "QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED", "EXPECTED");
    [.[] | select(.name == "ci / release-gate")]
    | if length == 0 then empty elif any(.[]; pending) then (map(select(pending)) | .[0]) else max_by(.startedAt // .completedAt // "") end
    | "\(.state)\t\(.link // "")"'
  gate="$(gh pr checks "$pr" -R "$repo" --json name,state,link,startedAt,completedAt --jq "$gate_jq")" \
    || stop "cannot read the checks, so whether ci / release-gate needs a re-run is unknown"
  case "${gate%%$'\t'*}" in
    FAILURE|CANCELLED|TIMED_OUT)
      runs="$(e2e_runs_on_head)" || stop "cannot read the e2e runs on $head, so whether ci / release-gate can pass now is unknown: $runs"
      case "${runs%%$'\n'*}" in
        "success "*)
          link="${gate#*$'\t'}"
          [[ "$link" =~ /job/([0-9]+) ]] || stop "ci / release-gate is red and its job cannot be read from its link '$link'; re-run it from the pull request's Checks tab, then run this again"
          out="$(gh api -X POST "repos/$repo/actions/jobs/${BASH_REMATCH[1]}/rerun" 2>&1)" \
            || stop "cannot re-run ci / release-gate (job ${BASH_REMATCH[1]}): $out" \
                    "re-run it from the pull request's Checks tab with a login that can write to the repository's Actions, then run this again"
          echo "re-ran ci / release-gate (job ${BASH_REMATCH[1]}), red from before the e2e run: $link"
          # Until the new attempt shows, the old red one is the newest.
          for _ in 1 2 3 4 5 6 7 8 9 10; do
            gate="$(gh pr checks "$pr" -R "$repo" --json name,state,link,startedAt,completedAt --jq "$gate_jq")" || gate=""
            case "${gate%%$'\t'*}" in FAILURE|CANCELLED|TIMED_OUT) sleep "$poll" ;; *) break ;; esac
          done ;;
      esac ;;
  esac
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
# A neutral `CodeQL` (#872): code scanning could not compare this pull
# request's alerts with the base branch's, usually because no analysis ran
# for this head. Default setup starts none for an event Dependabot causes, so
# every Dependabot pull request carries one; there alone, and only while no
# analysis exists on the head, it passes, and the push to the base branch runs
# the analysis this script then waits for. Anywhere else it stops.
neutral_codeql=no
if grep -qxF "NEUTRAL	CodeQL" <<<"$bad"; then
  rest="$(grep -vxF "NEUTRAL	CodeQL" <<<"$bad")"
  why_not=""
  if [ -n "$rest" ]; then
    why_not="other checks are not green either"
  elif ! author="$(gh api "repos/$repo/pulls/$pr" --jq .user.login)"; then
    stop "cannot read the author of $pr, so the neutral CodeQL cannot be judged"
  elif [ "$author" != "dependabot[bot]" ]; then
    why_not="the author is $author, not dependabot[bot]"
  elif ! found="$(analyses "$head")"; then
    stop "cannot read the Actions runs on $head, so whether an analysis ran there is unknown"
  elif [ -n "$found" ]; then
    why_not="an analysis exists on this head, so its result speaks, not the exception:"$'\n'"$found"
  else
    neutral_codeql=dependabot
    bad=""
  fi
  [ "$neutral_codeql" = dependabot ] || stop "checks not green:" "$bad" \
    "A neutral CodeQL is not a pass: code scanning could not tell which alerts this pull request adds (open the check for why; often no analysis ran for this head). It passes only on a Dependabot pull request with no analysis on its head; here $why_not"
fi
[ -z "$bad" ] || stop "checks not green:" "$bad"
if [ "$neutral_codeql" = dependabot ]; then
  echo "checks: $(($(wc -l <<<"$checks") - 1)) green, and CodeQL neutral on a Dependabot pull request with no analysis on its head: default setup does not analyse Dependabot's pull requests, and the push to the base branch runs the analysis, which this script waits for after the merge"
else
  echo "checks: $(wc -l <<<"$checks" | tr -d ' ') green"
fi

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
# An `update` rule on the pull request's base branch whose ruleset this login
# can never bypass. Any read that fails says no.
reserved_to_admin() {
  local base id
  base="$(gh pr view "$pr" -R "$repo" --json baseRefName --jq .baseRefName 2>/dev/null)" && [ -n "$base" ] || return 1
  for id in $(gh api "repos/$repo/rules/branches/$base" --jq '.[] | select(.type == "update" and .ruleset_source_type == "Repository") | .ruleset_id' 2>/dev/null); do
    [ "$(gh api "repos/$repo/rulesets/$id" --jq .current_user_can_bypass 2>/dev/null)" = never ] && return 0
  done
  return 1
}
if ! refused="$(gh pr merge "$pr" -R "$repo" --squash --match-head-commit "$head" --body "$body" 2>&1)"; then
  printf '%s\n' "$refused" >&2
  # Under the ruleset that reserves the merge to the admin (#568), a login
  # without the admin role is refused however often it retries: gh's own
  # check reads the pull request as blocked, the API answers with the rule
  # violation (#569). gh says the same for any block (a missing approval, an
  # unresolved thread), so the line needs the role read as not admin and an
  # `update` rule on the base branch from a ruleset GitHub says this login
  # can never bypass.
  if grep -qiE 'base branch policy prohibits the merge|repository rule violations|cannot update this protected ref' <<<"$refused" \
     && [ "$(gh api "repos/$repo" --jq '.permissions.admin' 2>/dev/null)" = false ] \
     && reserved_to_admin; then
    # Only this login's answer is read: whether the admin is still exempt is
    # in bypass actors a non-admin cannot read, so that is said, not assumed.
    stop "GitHub refused the merge: this login is not the repository's admin, and GitHub says it can never bypass the ruleset that restricts updates to the base branch." \
         "Do not retry. The person merges: the merge button on the pull request's page, or their own login outside this session." \
         "Whether the person's merge goes through was not read with this login; if it is refused too, /plinth:floor-check with the person's login reads that ruleset."
  fi
  stop "gh pr merge refused"
fi
[ -z "$refused" ] || printf '%s\n' "$refused"
after="$(gh pr view "$pr" -R "$repo" --json state,mergeCommit --jq '"\(.state) \(.mergeCommit.oid)"')"
after_rc=$?
echo "$after"

# -- the named issues (#490) ---------------------------------------------------
# After the merge, with GET calls only: the issues GitHub closes through this
# pull request and those its description names on a `Part of #N` line. For each,
# the acceptance criteria still unticked and, for one the merge closed, a
# body with no `## Outcome` (or `## Decision`). Which criterion the change met
# is the merger's call, so nothing is ticked here, and a failed read prints
# "not read" and leaves the exit status as it was without this section.
named() {
  local refs parts said=0 kind r n ib todo end
  refs="$(gh pr view "$pr" -R "$repo" --json closingIssuesReferences \
    --jq '(.closingIssuesReferences // [])[] | "closes\t\(.repository.owner.login)/\(.repository.name)\t\(.number)"' 2>/dev/null)" \
    || { echo "issues this merge closed: not read"; said=1; refs=""; }
  # A `Part of` link line, in the grammar `ci / docs` reads (closing-references.py).
  parts="$(python3 "$(dirname "${BASH_SOURCE[0]}")/closing-references.py" --part-of "$repo" <<<"$body" 2>/dev/null)" \
    || { echo "Part of lines: not read"; said=1; parts=""; }
  parts="$(awk -F'\t' 'NF == 2 {printf "part\t%s\t%s\n", $1, $2}' <<<"$parts")"
  while IFS=$'\t' read -r kind r n; do
    [ -n "$n" ] || continue
    if ! ib="$(gh api "repos/$r/issues/$n" --jq '.body // ""' 2>/dev/null)"; then
      echo "$r#$n: not read"; said=1; continue
    fi
    ib="${ib//$'\r'/}"
    todo="$(awk '/^## /{in_ac = ($0 ~ /^## Acceptance criteria[[:space:]]*$/); next}
                 in_ac && /^[[:space:]]*[-*] \[ \]/' <<<"$ib")"
    end=yes
    [ "$kind" = part ] || grep -qE '^## (Outcome|Decision)([^[:alnum:]]|$)' <<<"$ib" || end=no
    [ -n "$todo" ] || [ "$end" = no ] || continue
    if [ "$kind" = closes ]; then echo "$r#$n, closed by this merge:"; else echo "$r#$n, part of this change:"; fi
    [ -z "$todo" ] || { echo "  unticked acceptance criteria:"; sed 's/^[[:space:]]*/    /' <<<"$todo"; }
    [ "$end" = yes ] || echo "  no ## Outcome (or ## Decision for a record) in the body"
    said=1
  done < <(printf '%s\n%s\n' "$refs" "$parts" | awk -F'\t' 'NF == 3 && !seen[tolower($2) "#" $3]++')
  [ "$said" = 0 ] || echo "Whoever merged ticks the criteria this change met and writes the ending of an issue it closed (AGENTS.md)."
}
# A merge queue takes the pull request without merging it yet: the issues are
# read only once it reads as merged.
case "$after" in
  MERGED*) named ;;
  *) echo "Not merged yet (${after:-state not read}): read its issues' criteria once it has." ;;
esac

# -- the base branch's analysis, after a neutral CodeQL passed (#872) ----------
# The analysis the pull request never had runs on the push to the base branch.
# Wait for its `Analyze (...)` jobs on the merge commit (MERGE_ANALYZE_WAIT
# seconds, 20 minutes by default) and say how they ended. A failure is the base
# branch's now, and exits 1; not started, not finished or not read is said as
# not confirmed, and leaves the exit status as it was.
base_analysis() {
  local sha="$1" base wait="${MERGE_ANALYZE_WAIT:-1200}" t0=$SECONDS lines where
  base="$(gh pr view "$pr" -R "$repo" --json baseRefName --jq .baseRefName 2>/dev/null)" && [ -n "$base" ] || base="the base branch"
  where="code scanning on $base at $sha"
  while :; do
    if ! lines="$(analyses "$sha")"; then
      echo "$where: not read (the Actions runs could not be read), so this merge's analysis is not confirmed: https://github.com/$repo/security/code-scanning"
      return 0
    fi
    [ -n "$lines" ] && ! awk -F'\t' '$1 != "completed" {f = 1} END {exit !f}' <<<"$lines" && break
    [ $((SECONDS - t0)) -lt "$wait" ] || break
    sleep "$poll"
  done
  if [ -z "$lines" ]; then
    echo "$where: not started within $((wait / 60)) minute(s), so this merge's analysis is not confirmed. Look for a run named 'Push on $base' in https://github.com/$repo/actions, and at the tool status under https://github.com/$repo/security/code-scanning"
  elif awk -F'\t' '$1 != "completed" {f = 1} END {exit !f}' <<<"$lines"; then
    echo "$where: not finished within $((wait / 60)) minute(s), so this merge's analysis is not confirmed; read it there once it ends:"
    printf '%s\n' "$lines"
  elif awk -F'\t' '$2 != "success" {f = 1} END {exit !f}' <<<"$lines"; then
    echo "FAIL: code scanning failed on $base at $sha, after this merge. The pull request is merged, so the failure is on $base now:"
    printf '%s\n' "$lines"
    echo "Read the failed job's log. If it reports alerts (https://github.com/$repo/security/code-scanning?query=is%3Aopen+ref%3Arefs%2Fheads%2F$base), fix them, or revert this merge, in a new pull request. If the job itself broke, run it again: gh run rerun <run id from the URL> --failed --repo $repo"
    return 1
  else
    echo "$where: passed"
    printf '%s\n' "$lines"
  fi
}
if [ "$neutral_codeql" = dependabot ]; then
  case "$after" in
    MERGED*) base_analysis "${after#MERGED }" || after_rc=1 ;;
    *) echo "Not merged yet: once it has, read the analysis on the base branch's merge commit, since this pull request had none." ;;
  esac
fi
exit "$after_rc"
