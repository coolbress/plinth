#!/usr/bin/env bash
# Tier 2, the upgrade path (#519): a repository an earlier release of plinth
# made, updated by this one, and read for the pin the update promises.
#
#   e2e-upgrade.sh [<owner>]
#
# The `e2e` workflow's door journey only creates: v1.15.0 shipped a change to
# the workflows a repository calls, and repositories the door had already
# made kept calling the old ones while every e2e run was green. This one
# starts from such a repository:
#
#   1 the start: the newest release tag before this commit whose door pinned
#     a template tag tested with another plinth commit than this commit's
#     tag (copier.yml's plinth_sha default). Not simply the release before:
#     when it kept the template tag, or a tag with the same pin, the update
#     moves no pin and could not fail the way this exists to catch. Its
#     template_ref is rendered with its own copier pin, as its door did,
#     plinth_sha at that tag's default.
#   2 <owner>/plinth-e2e-upgrade-<run>, public, with Actions turned off (no
#     workflow of the rendered template runs on it), main pushed.
#   3 template-update.sh beside this file, the one this commit ships: the
#     plan, then --apply with --plinth-pin tested, which opens a draft pull
#     request. A conflict is a failure: nothing here resolves one.
#   4 the update branch as pushed: every coolbress/plinth `uses:` line in
#     .github/workflows (ci.yml's and label.yml's at least) and
#     .copier-answers.yml's plinth_sha must name the plinth_sha default of
#     this commit's template tag, the pin that tag was tested with, and
#     _commit that tag.
#   5 the repository is deleted.
#
# Exit 0 means the whole path happened, deletion included. A failure after
# the create deletes the repository; one that could not be deleted is named
# on stderr and in the job summary, and the exit is 1 either way. GitHub
# only: template-update.sh has no GitLab path.
#
# The token is the e2e job's (Administration, Contents, Pull requests:
# write), typed through with-admin-token.sh, as e2e.sh's is.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pin_of() { sed -nE "s/^$1=\"([^\"]+)\"$/\\1/p"; }  # <name>, new-project.sh on stdin
door="$(cat "$here/new-project.sh")"
template_repo="$(pin_of template_repo <<<"$door")"
template_ref="$(pin_of template_ref <<<"$door")"
loud() { # a repository that outlives this run is said twice: the log and the summary
  printf '!! %s\n' "$1" >&2
  [ -z "${GITHUB_STEP_SUMMARY:-}" ] || printf '%s\n' "$1" >> "$GITHUB_STEP_SUMMARY"
}
fail() { printf '%s\n' "$@" >&2; exit 1; }
say() { # a record line, in the log and the job summary
  echo "$1"
  [ -z "${GITHUB_STEP_SUMMARY:-}" ] || printf '%s\n' "$1" >> "$GITHUB_STEP_SUMMARY"
}

# ── 1 the start ──────────────────────────────────────────────────────────
# The pin each tag was tested with: the plinth_sha default in its copier.yml.
tested_pin() { # <ref>
  gh api "repos/$template_repo/contents/copier.yml?ref=$1" --jq .content | base64 -d \
    | sed -n '/^plinth_sha:/,/^[^[:space:]]/{s/^[[:space:]]\{1,\}default:[[:space:]]*["'\'']\{0,1\}\([0-9a-fA-F]\{40\}\)["'\'']\{0,1\}[[:space:]]*$/\1/p;}' \
    | tr '[:upper:]' '[:lower:]'
}
want="$(tested_pin "$template_ref")" || want=""
[ -n "$want" ] || fail "could not read the plinth_sha default of $template_repo@$template_ref"
# Release tags reachable from this commit, newest first; the workflow checks
# out the whole history for them. One read per template tag, not per release.
start=""; from_ref=""; from_pin=""; seen=" $template_ref "
while read -r tag; do
  old="$(git -C "$here" show "$tag:scripts/new-project.sh" 2>/dev/null)" || continue
  ref="$(pin_of template_ref <<<"$old")"
  case "$seen" in *" $ref "*) continue ;; esac
  seen="$seen$ref "
  [ -n "$ref" ] || continue
  pin="$(tested_pin "$ref")" || pin=""
  [ -n "$pin" ] || fail "could not read the plinth_sha default of $template_repo@$ref ($tag's template tag)"
  if [ "$pin" != "$want" ]; then
    start="$tag"; from_ref="$ref"; from_pin="$pin"
    from_copier="$(pin_of copier_version <<<"$old")"; from_newer="$(pin_of copier_newer <<<"$old")"
    break
  fi
done < <(git -C "$here" tag --merged HEAD --sort=-v:refname --list 'v*')
[ -n "$start" ] || fail "no release tag before this commit pinned a template tag tested with another plinth commit than $want ($template_ref's); nothing to start from (is the history fetched? the checkout needs fetch-depth: 0)"
[ -n "$from_copier" ] && [ -n "$from_newer" ] || fail "$start's scripts/new-project.sh has no copier_version or copier_newer"
say "upgrade: from $start's template $from_ref (plinth $from_pin) to $template_ref (tested with plinth $want)"

# ── the token's user ─────────────────────────────────────────────────────
# As e2e.sh reads it (#288): the exit kept, the answer's shape checked.
user_err="$(mktemp "${TMPDIR:-/tmp}/plinth-e2e-upgrade-user.XXXXXX")"
user="$(gh api user --jq '"\(.id) \(.login)"' 2>"$user_err")" && user_rc=0 || user_rc=$?
read -r id login _ <<<"$user" || true
why="$(grep -m1 '^gh: ' "$user_err" || true)"; rm -f "$user_err"
if [ "$user_rc" != 0 ] || [[ ! "$id" =~ ^[0-9]+$ ]] || [ -z "$login" ]; then
  echo "gh cannot read the token's user${why:+ ($why)}: the token is refused or missing; is GH_TOKEN set to a valid one, or gh logged in?" >&2
  exit 2
fi
owner="${1:-$login}"
name="plinth-e2e-upgrade-${GITHUB_RUN_ID:-$(date -u +%Y%m%d%H%M%S)}"
repo="$owner/$name"; url="https://github.com/$repo"

# ── 1 render, as the start's door did ────────────────────────────────────
work="$(mktemp -d "${TMPDIR:-/tmp}/plinth-e2e-upgrade.XXXXXX")"; dir="$work/$name"
git -C "$work" config user.email >/dev/null 2>&1 || {
  export GIT_AUTHOR_NAME="$login" GIT_AUTHOR_EMAIL="$id+$login@users.noreply.github.com"
  export GIT_COMMITTER_NAME="$login" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
}
env -u GH_TOKEN -u GITHUB_TOKEN uvx --quiet --from "copier==$from_copier" --exclude-newer "$from_newer" \
  copier copy --defaults --quiet \
  --data "project_name=$name" --data "owner=$owner" --data "license=MIT" --data "archetype=cli" \
  --vcs-ref "$from_ref" "gh:$template_repo" "$dir" < /dev/null
rm -rf "$dir/.git"
git init -q -b main "$dir"
git -C "$dir" add -A
git -C "$dir" commit -q -m "chore: render $template_repo@$from_ref, as $start's door"

# ── 2 the repository ─────────────────────────────────────────────────────
created=0
cleanup() {
  local rc=$? out
  trap - EXIT
  [ "$rc" != 0 ] || rc=1   # a signal while gh ran reads as 0 here (see e2e.sh)
  if [ "$created" = 0 ]; then
    echo "the upgrade path failed before anything was created; nothing to delete (the local copy $work stays)" >&2
    exit "$rc"
  fi
  echo "the upgrade path did not finish (exit $rc); deleting $url (the local copy $work stays)" >&2
  if out="$(gh repo delete "$repo" --yes 2>&1)"; then echo "deleted $url" >&2
  elif grep -qE 'HTTP 404|Not Found' <<<"$out"; then echo "$url is already gone" >&2
  else loud "UPGRADE REPOSITORY NOT DELETED: $url may EXIST ($out); delete it: $url/settings (or: gh repo delete $repo --yes)"; fi
  exit "$rc"
}
trap cleanup EXIT
# A name that already exists is not this run's (a rerun after a deletion
# that failed, or anyone's): never deleted from here. Any other failure is
# deleted all the same: a create whose answer was lost still created, and
# the deletion's 404 is what says nothing exists.
if out="$(gh repo create "$repo" --public 2>&1)"; then created=1
elif grep -qi 'already exists' <<<"$out"; then
  fail "$url already exists and this run did not create it; delete or rename it, then run again"
else created=1; fail "creating $url failed ($out)"; fi
gh api -X PUT "repos/$repo/actions/permissions" -F enabled=false >/dev/null \
  || fail "could not turn Actions off on $url"
git -C "$dir" remote add origin "$url.git"
git -C "$dir" push -q -u origin main

# ── 3 the update ─────────────────────────────────────────────────────────
plan="$(cd "$dir" && "$here/template-update.sh")" || fail "the template-update plan stopped:" "$plan"
printf '%s\n' "$plan"
base="$(sed -nE 's/^ *[^ ]*template-update\.sh --apply ([0-9a-f]{40})( .*)?$/\1/p' <<<"$plan" | head -n 1)"
[ -n "$base" ] || fail "the plan printed no --apply line"
rc=0; out="$(cd "$dir" && "$here/template-update.sh" --apply "$base" --plinth-pin tested 2>&1)" || rc=$?
printf '%s\n' "$out"
[ "$rc" = 0 ] || fail "template-update.sh --apply --plinth-pin tested exited $rc (3 is a conflict copier left; nothing here resolves one)"
pr="$(sed -n 's/^Draft pull request: //p' <<<"$out")"
[ -n "$pr" ] || fail "template-update.sh reported no draft pull request"

# ── 4 what landed ────────────────────────────────────────────────────────
wt="$work/$name-template-$template_ref"; branch="chore/template-$template_ref"
head="$(git -C "$wt" rev-parse HEAD)"
pushed="$(git -C "$wt" ls-remote origin "refs/heads/$branch" | cut -f1)"
[ "$pushed" = "$head" ] || fail "$branch on GitHub is ${pushed:-absent}, not the update commit $head"
bad=""
# Each plinth reference outside a comment, file by file.
pins="$(cd "$wt/.github/workflows" && grep -HE '^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*["'\'']?coolbress/plinth/' -- *.yml || true)"
for f in ci.yml label.yml; do
  grep -q "^$f:" <<<"$pins" || bad="$bad"$'\n'"  .github/workflows/$f has no coolbress/plinth uses: line"
done
while IFS= read -r line; do
  [ -n "$line" ] || continue
  sha="$(sed -E 's/.*@([^"'\''[:space:]]*).*/\1/' <<<"$line")"
  [ "$sha" = "$want" ] || bad="$bad"$'\n'"  .github/workflows/${line%%:*} calls $sha, not $want"
done <<<"$pins"
answers_pin="$(sed -n 's/^plinth_sha: *//p' "$wt/.copier-answers.yml")"
answers_tag="$(sed -n 's/^_commit: *//p' "$wt/.copier-answers.yml")"
[ "$answers_pin" = "$want" ] || bad="$bad"$'\n'"  .copier-answers.yml records plinth_sha ${answers_pin:-(none)}, not $want"
[ "$answers_tag" = "$template_ref" ] || bad="$bad"$'\n'"  .copier-answers.yml records _commit ${answers_tag:-(none)}, not $template_ref"
[ -z "$bad" ] || fail "the tested pin did not land on $pr:$bad"
say "upgrade: landed on $pr: $(grep -c . <<<"$pins") plinth uses: line(s) and .copier-answers.yml name $want; _commit $template_ref"

# ── 5 gone ───────────────────────────────────────────────────────────────
gh repo delete "$repo" --yes >/dev/null 2>&1 || fail "the upgrade path succeeded but the deletion of $url did not"
trap - EXIT
echo "deleted $url"
rm -rf "$work"
