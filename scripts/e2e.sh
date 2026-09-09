#!/usr/bin/env bash
# Tier 2: the door's journey on real GitHub, through the wall, then gone.
#
#   e2e.sh [<owner>]
#
# Creates <owner>/plinth-e2e-<run> with the door beside this file
# (new-project.sh: create, render, main, labels, CodeQL, ruleset, the first
# pull request), reads the wall back with the checker `ci / floor-check` runs
# (floor-check.py), waits for every check on that pull request to be green,
# squash-merges it, reads main back, and deletes the repository. The `e2e`
# workflow runs it nightly and on demand; make-release.sh run 2 accepts a
# green run on the commit it is about to tag, and nothing else.
#
# Exit 0 means the whole journey happened, deletion included. Before the door
# runs, the token creates and deletes <name>-probe: a token that can create
# but not delete would leave a repository behind on every run, and that is
# found out first. A sibling name, not the name itself: a deletion GitHub is
# still finishing must not collide with the door's create. Any failure after that deletes what was
# made; a repository that could not be deleted is named on stderr and in the
# job summary, and the exit is 1 either way.
#
# The token is the one the door asks for (classic: repo, workflow,
# delete_repo; fine-grained: Administration, Contents, Pull requests,
# Workflows: write on the owner's repositories), typed through
# with-admin-token.sh, which a CI step feeds from stdin:
#   printf '%s\n' "$PLINTH_E2E_TOKEN" | scripts/with-admin-token.sh scripts/e2e.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# How long the first pull request may take to turn green and mergeable: the
# template's CI plus CodeQL's first analysis. Tests shorten it.
wait_s="${PLINTH_E2E_WAIT:-1500}"
case "$wait_s" in ''|*[!0-9]*) echo "PLINTH_E2E_WAIT must be a whole number of seconds (got: $wait_s)" >&2; exit 2 ;; esac

read -r id login < <(gh api user --jq '"\(.id) \(.login)"') \
  || { echo "gh cannot read the token's user: is GH_TOKEN set, or gh logged in?" >&2; exit 2; }
owner="${1:-$login}"
name="plinth-e2e-${GITHUB_RUN_ID:-$(date -u +%Y%m%d%H%M%S)}"
repo="$owner/$name"; url="https://github.com/$repo"
loud() { # a repository that outlives this run is said twice: the log and the summary
  printf '!! %s\n' "$1" >&2
  [ -z "${GITHUB_STEP_SUMMARY:-}" ] || printf '%s\n' "$1" >> "$GITHUB_STEP_SUMMARY"
}
fail() { printf '%s\n' "$@" >&2; exit 1; }

# ── first assert: this token can create and delete a repository ──────────
probe="$repo-probe"; purl="https://github.com/$probe"
echo "first assert: create and delete $purl"
created_probe=0
if out="$(gh repo create "$probe" --public 2>&1)"; then created_probe=1
elif grep -qi 'already exists' <<<"$out"; then
  # Not this run's (a rerun with the same run id after a deletion that
  # failed, or anyone's repository of that name): never deleted from here.
  fail "$purl already exists and this run did not create it; delete or rename it, then run again"
fi
# Otherwise deleted whether or not the create answered: a create whose answer
# was lost still created, and a 404 here is the only proof that nothing exists.
if out="$(gh repo delete "$probe" --yes 2>&1)"; then
  [ "$created_probe" = 1 ] || echo "  the create's answer was lost, but $purl existed and is deleted"
  echo "  ok"
elif [ "$created_probe" = 0 ] && grep -qE 'HTTP 404|Not Found' <<<"$out"; then
  fail "the token cannot create $purl (classic: the repo scope; fine-grained: Administration: write on $owner's repositories)"
else
  loud "$purl EXISTS and the token cannot delete it ($out; classic: delete_repo; fine-grained: Administration: write); delete it: $purl/settings"; exit 1
fi

# ── the door ─────────────────────────────────────────────────────────────
work="$(mktemp -d "${TMPDIR:-/tmp}/plinth-e2e.XXXXXX")"; dir="$work/$name"
# A runner has no git identity, and the door commits. Read from a directory
# that is not a repository, which is what the door's fresh clone inherits: a
# user.email set only in this checkout's own config would pass here and be
# absent there. The noreply address attributes the commit to the token's
# user; a made-up one would not.
git -C "$work" config user.email >/dev/null 2>&1 || {
  export GIT_AUTHOR_NAME="$login" GIT_AUTHOR_EMAIL="$id+$login@users.noreply.github.com"
  export GIT_COMMITTER_NAME="$login" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
}
merged=0 # what the summary says when the deletion is what failed
cleanup() {
  local rc=$? out why
  trap - EXIT
  # The trap is cleared once the final deletion succeeded, so this runs only
  # on a failure or on a signal (a cancellation, a workflow timeout). On a
  # signal that landed while gh ran, bash gives $? as 0 and exits by the
  # signal after this returns (measured, bash 3.2): 0 here is not "done".
  [ "$rc" != 0 ] || rc=1
  # Only what this run created is deleted. The door prints `done: <url>` when
  # it finished and `the wall did not go up; deleting <url>` when it failed
  # after creating; both come after its create succeeded, and it keeps them
  # for this. A door that refused in preflight, or whose create failed because
  # the name already existed (a rerun after a deletion that failed, a
  # preflight read that missed), prints neither: not ours to delete.
  if ! grep -qE "^(done: |the wall did not go up; deleting )$url( |\$)" "$work/door.log" 2>/dev/null; then
    echo "the journey failed before anything was created; nothing to delete (the local copy $work stays)" >&2
    exit "$rc"
  fi
  # The door deletes on its own failures; whatever is still there goes now.
  # Deletion is attempted rather than existence asked first: an answer that
  # is not 404 is not "absent", and a probe that failed on a bad minute would
  # have read that way and left a public repository behind unreported.
  echo "the journey did not finish (exit $rc); deleting $url if it is still there (the local copy $dir stays)" >&2
  if out="$(gh repo delete "$repo" --yes 2>&1)"; then echo "deleted $url" >&2
  elif grep -qE 'HTTP 404|Not Found' <<<"$out"; then echo "$url is already gone" >&2
  else why="ROLLBACK FAILED"; [ "$merged" = 0 ] || why="MERGED, NOT DELETED"
    loud "$why: $url may EXIST ($out); delete it: $url/settings (or: gh repo delete $repo --yes)"; fi
  exit "$rc"
}
trap cleanup EXIT

"$here/new-project.sh" "$repo" --dir="$dir" 2>&1 | tee "$work/door.log"
pr_url="$(sed -n 's/^  first pull request: //p' "$work/door.log")"
[ -n "$pr_url" ] || fail "the door did not report a first pull request"

# The record: which generator, which template commit, which workflow pin.
template_repo="$(sed -nE 's/^template_repo="([^"]+)"$/\1/p' "$here/new-project.sh")"
template_ref="$(sed -nE 's/^template_ref="([^"]+)"$/\1/p' "$here/new-project.sh")"
template_sha="$(gh api "repos/$template_repo/commits/$template_ref" --jq .sha 2>/dev/null || echo unresolved)"
echo "generator: $(git -C "$here" rev-parse HEAD 2>/dev/null || echo unknown) ($(git -C "$here" describe --tags --always 2>/dev/null || echo untagged))"
echo "template: $template_repo@$template_ref ${template_sha:0:12}"
echo "pins: $(grep -hE '^[[:space:]]*uses:' "$dir"/.github/workflows/*.yml | sed 's/^[[:space:]]*uses: //' | tr '\n' ' ')"

# ── the wall, read back ──────────────────────────────────────────────────
# The ruleset targets ~DEFAULT_BRANCH; the checker warns when that is not
# main, and here it is a failure: main is the one branch the door promised.
default_branch="$(gh api "repos/$repo" --jq .default_branch)"
[ "$default_branch" = main ] || fail "the default branch of $url is $default_branch, not main"
python3 "$here/floor-check.py" --root "$dir" --repo "$repo" --ruleset "$here/../ruleset.json"

# ── through the wall ─────────────────────────────────────────────────────
echo "waiting for $pr_url to turn green and mergeable (up to $wait_s s)"
deadline=$((SECONDS + wait_s)); repush_at=$((SECONDS + wait_s / 5)); repushed=0; state=unknown
while :; do
  # `pr checks` exits 8 while something is pending and 1 once something is
  # red; the JSON is what is read. One red check is the answer: no wait. A
  # query that failed reads as nothing red and is asked again next poll;
  # only the merge state below opens the door, so that costs time, not truth.
  red="$(gh pr checks "$pr_url" --json bucket,name,link --jq '.[] | select(.bucket == "fail") | "  \(.name)  \(.link)"' 2>/dev/null || true)"
  [ -z "$red" ] || fail "a check on the first pull request is red:" "$red"
  state="$(gh pr view "$pr_url" --json mergeStateStatus --jq .mergeStateStatus 2>/dev/null || echo unknown)"
  # CLEAN is GitHub's word for "every rule is satisfied", CodeQL's included;
  # a merge refused after it is a race with that evaluation, so try again.
  if [ "$state" = CLEAN ] && gh pr merge "$pr_url" --squash; then break; fi
  # CodeQL default setup does not always analyse the first push after it was
  # enabled (measured 2026-09-09, #117). The door prints the recovery, an
  # empty commit pushed once more, and a runner has nobody to type it: done
  # here, once, after a fifth of the wait with no CodeQL check on the head.
  if [ "$repushed" = 0 ] && [ "$SECONDS" -ge "$repush_at" ]; then
    # Only a read of the names can say CodeQL is absent: exit 0, or 8, the
    # exit `pr checks` gives a pending check without --json (with it, gh
    # 2.79.0 exits 0 whatever the buckets: checks.go returns from the
    # exporter first). Any other exit (network, auth, the API) is not an
    # answer, and never the reason for a push: asked again next poll. The
    # exit is read apart from grep's, which pipefail would fold into one.
    rc=0; names="$(gh pr checks "$pr_url" --json name --jq '.[].name' 2>&1)" || rc=$?
    if [ "$rc" != 0 ] && [ "$rc" != 8 ]; then
      echo "could not read the checks on $pr_url (gh exited $rc: ${names//$'\n'/ }); the recovery push waits for a readable answer" >&2
    elif ! grep -qE '^(CodeQL|Analyze \()' <<<"$names"; then
      echo "CodeQL has not picked up the first pull request after $((wait_s / 5)) s; pushing the door's recovery commit once (#117)" >&2
      git -C "$dir" commit -q --allow-empty -m 'ci: trigger code scanning' && git -C "$dir" push -q
      repushed=1
    fi
  fi
  [ "$SECONDS" -lt "$deadline" ] \
    || fail "the first pull request was not merged within $wait_s s (merge state: $state):" "$(gh pr checks "$pr_url" 2>&1 || true)"
  sleep $(( wait_s < 20 ? wait_s : 20 ))
done
# Read main back rather than trust the exit code: the squash commit is the
# pull request's title, and main carrying it is what "merged" means here.
# GitHub appends the number, `title (#1)` (measured 2026-09-09; the first
# version of this line wanted the title at the end and read a merged main as
# not merged), so the title is looked for anywhere in the subject.
tip="$(gh api "repos/$repo/commits/main" --jq '"\(.sha[0:12]) \(.commit.message | split("\n")[0])"')"
case "$tip" in *"docs: first pull request through the wall"*) ;; *) fail "main does not carry the squash commit; its tip is: $tip" ;; esac
echo "merged: $tip"; merged=1

# ── gone ─────────────────────────────────────────────────────────────────
# The trap stays armed until the deletion returned: a cancellation or a
# timeout landing on it, like a deletion that failed on its own, goes to
# cleanup, which tries once more and names what is left. Not a public
# repository nobody was told about.
gh repo delete "$repo" --yes >/dev/null 2>&1 || fail "the journey succeeded but the deletion of $url did not"
trap - EXIT
echo "deleted $url"
rm -rf "$work"
