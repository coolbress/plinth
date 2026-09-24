#!/usr/bin/env bash
# Apply the template update /plinth:floor-check reports as a draft pull
# request (#232, #219 stage 2). Three steps, each started by a person:
#
#   template-update.sh
#       The plan. Fetches and verifies origin/<default> against GitHub, then
#       prints the tags, the command and where it will run. Writes nothing.
#   template-update.sh --apply <base-sha> [--assisted-by <agent>:<model>]
#       Branches a worktree beside the repository from <base-sha> (it must
#       still be origin/<default>), requires it clean, runs the command and,
#       when copier leaves no conflict, commits, pushes the branch and opens
#       a draft pull request. A conflict stops here (exit 3), left as copier
#       left it for a person to resolve.
#   template-update.sh --finish <worktree> [--assisted-by <agent>:<model>]
#       After a person resolved the conflicts: checks nothing is left, then
#       commits, pushes and opens the draft pull request. Also finishes an
#       update whose push or pull request failed, without a second commit.
#
# The command is the checker's own line (floor-check.py
# --print-update-command), run word for word: never a second construction of
# it. The draft is opened as soon as the tree is clean; nothing waits for the
# branch's checks. Nothing is pushed to the default branch, and nothing
# resolves a conflict by choosing a side (#88).
#
# Exit: 0 done (a plan printed, or a draft opened), 1 stopped or nothing to
# update, 2 usage, 3 a conflict is waiting for a person.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
checker="$here/floor-check.py"
state_name="plinth-template-update"

# A path as a shell word, for a line the user or the skill runs as printed.
q() { printf '%q' "$1"; }
die()  { printf 'template-update: %s\n' "$*" >&2; exit 1; }
usage() { printf 'usage: %s [--apply <base-sha> | --finish <worktree>] [--assisted-by <agent>:<model>]\n' "$0" >&2; exit 2; }

mode=plan; base_arg=""; wt_arg=""; assisted=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply)       [ $# -ge 2 ] || usage; mode=apply; base_arg="$2"; shift 2 ;;
    --finish)      [ $# -ge 2 ] || usage; mode=finish; wt_arg="$2"; shift 2 ;;
    --assisted-by) [ $# -ge 2 ] || usage; assisted="$2"; shift 2 ;;
    *) usage ;;
  esac
done

for tool in git gh python3 uvx; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done

# What copier left that a person has to resolve: unmerged paths, `.rej`
# files (untracked, or staged by a `git add -A`), and conflict markers (a marked file `git add`ed is no longer
# unmerged, but it is not resolved either). One path per line.
conflicts_in() { # <worktree>
  {
    git -C "$1" -c core.quotePath=false diff --name-only --diff-filter=U
    git -C "$1" -c core.quotePath=false ls-files --cached --others -- '*.rej'
    git -C "$1" -c core.quotePath=false grep -l --untracked -E '^(<<<<<<<|>>>>>>>) ' 2>/dev/null
  } | sort -u
}

indent() { sed 's/^/  /'; }
state_file() { printf '%s/%s\n' "$(git -C "$1" rev-parse --absolute-git-dir)" "$state_name"; }
state_get() { sed -n "s/^$2=//p" "$1" | head -n 1; }
# A file's content as git would store it, or `-` when it is gone.
blob() { git -C "$1" hash-object -- "$2" 2>/dev/null || echo -; }
# The files that differ from <base>: tracked changes and new files.
changed_since() { # <worktree> <base>
  { git -C "$1" -c core.quotePath=false diff --name-only "$2"
    git -C "$1" -c core.quotePath=false ls-files --others --exclude-standard; } | sort -u
}

# ── finish: commit, push the branch, open the draft ─────────────────────
finish() { # <worktree>
  local wt="$1" sf repo default base from to cmd branch left pr
  sf="$(state_file "$wt" 2>/dev/null)" && [ -f "$sf" ] \
    || die "$wt is not a worktree this script made (no $state_name record in its git directory)"
  repo="$(state_get "$sf" repo)"; default="$(state_get "$sf" default)"; base="$(state_get "$sf" base)"
  from="$(state_get "$sf" from)"; to="$(state_get "$sf" to)"; cmd="$(state_get "$sf" command)"
  pr="$(state_get "$sf" pr)"
  if [ -n "$pr" ]; then
    echo "The draft pull request is already open: $pr"
    echo "Nothing pushed and nothing changed; further commits there are a person's."
    exit 0
  fi
  # Only the branch --apply made: a worktree switched to any other branch is
  # not the update, whatever it holds (Codex review on #273).
  branch="$(state_get "$sf" branch)"
  local on; on="$(git -C "$wt" rev-parse --abbrev-ref HEAD)"
  [ -n "$branch" ] && [ "$on" = "$branch" ] && [ "$branch" != "$default" ] \
    || die "the worktree is on '$on', not the update branch '$branch'; nothing committed or pushed. Switch back: git -C $wt switch $branch"

  left="$(conflicts_in "$wt")"
  if [ -n "$left" ]; then
    echo "Not resolved yet, in $wt:"
    indent <<<"$left"
    echo "Resolve each (remove every conflict marker, delete each .rej once applied), git add it, then run:"
    echo "  $(q "$0") --finish $(q "$wt")"
    exit 3
  fi

  git -C "$wt" add -A || die "git add failed in $wt"
  # A commit already made here is an earlier --finish whose push or pull
  # request failed: it is finished, not committed again.
  local committed=no
  [ "$(git -C "$wt" rev-parse HEAD)" != "$base" ] && committed=yes
  if git -C "$wt" diff --cached --quiet; then
    [ "$committed" = yes ] || die "nothing changed in $wt; no commit, no pull request"
  elif [ "$committed" = yes ]; then
    die "$wt has a commit and further changes; commit or discard them by hand, then run --finish again"
  fi

  # What went in, by who: copier's clean merges (unchanged since copier left
  # them), the files it left in conflict, and anything else a person changed.
  local clean="" resolved="" edited="" path h
  resolved="$(sed -n 's/^conflict=//p' "$sf")"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    grep -qxF "conflict=$path" "$sf" && continue
    h="$(awk -v p="$path" 'sub(/^clean=/, "") { h = $1; sub(/^[^ ]* /, ""); if ($0 == p) print h }' "$sf")"
    if [ -n "$h" ] && [ "$h" = "$(blob "$wt" "$path")" ]; then clean="$clean$path"$'\n'
    else edited="$edited$path"$'\n'; fi
  done < <(git -C "$wt" -c core.quotePath=false diff --cached --name-only "$base")

  local title="chore(template): update plinth-template $from to $to"
  local msg body; msg="$(mktemp)"; body="$(mktemp)"
  list() { if [ -n "$1" ]; then printf '%s\n' "$1" | sed '/^$/d; s/^/- /'; else echo "- none"; fi; }
  {
    echo "## What and why"
    echo
    echo "Updates this repository from plinth-template $from to $to, the tag plinth is"
    echo "tested with, by running the command \`/plinth:floor-check\` prints for it:"
    echo
    echo '```text'
    echo "$cmd"
    echo '```'
    echo
    echo "Merged cleanly (copier's merge, unchanged since):"
    echo
    list "$clean"
    echo
    echo "Resolved by a person (copier left a conflict):"
    echo
    list "$resolved"
    echo
    echo "Edited by a person after the update, outside a conflict:"
    echo
    list "$edited"
    echo
    echo "## How it was verified"
    echo
    echo "Opened as a draft once no conflict was left: no unmerged path, no \`.rej\`"
    echo "file, no conflict marker. This repository's own checks had not run when it"
    echo "was opened; they run on it now. No conflict was resolved automatically."
    echo "copier's questions were answered with \`--defaults\`: each takes this"
    echo "repository's recorded answer, and a question it never answered takes the"
    echo "template's default (\`.copier-answers.yml\` in the diff shows any)."
    if [ -n "$assisted" ]; then echo; echo "Assisted-by: $assisted"; fi
  } > "$body"
  { echo "$title"; echo; cat "$body"; } > "$msg"

  if [ "$committed" = no ]; then
    git -C "$wt" commit -q -F "$msg" || { rm -f "$msg" "$body"; die "git commit failed in $wt"; }
  fi
  rm -f "$msg"
  # The one push this script makes, to the update branch by name. The
  # default branch is refused above and never named here.
  git -C "$wt" push -q origin "HEAD:refs/heads/$branch" \
    || { rm -f "$body"; die "pushing $branch failed; the commit is in $wt, no pull request opened. Run again: $(q "$0") --finish $(q "$wt")"; }
  # A pull request GitHub created although gh reported a failure (the reply
  # lost on the way back) is this one: adopt it rather than fail on the
  # duplicate every time (Codex review on #273).
  pr="$(gh pr list --repo "$repo" --head "$branch" --base "$default" --state open --json url --jq '.[0].url // empty' 2>/dev/null)" || pr=""
  [ -n "$pr" ] || pr="$(gh pr create --repo "$repo" --draft --base "$default" --head "$branch" --title "$title" --body-file "$body")" \
    || { rm -f "$body"; die "$branch is pushed, but opening the pull request failed (above). Run again: $(q "$0") --finish $(q "$wt")"; }
  rm -f "$body"
  printf 'pr=%s\n' "$pr" >> "$sf"
  echo "Draft pull request: $pr"
  echo "Its checks start now; nothing here waited for them. The worktree stays at $wt."
  exit 0
}

[ "$mode" = finish ] && { [ -d "$wt_arg" ] || die "no such worktree: $wt_arg"; finish "$(cd "$wt_arg" && pwd)"; }

# ── plan and apply: a verified base ─────────────────────────────────────
top="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
read -r repo default < <(gh repo view --json nameWithOwner,defaultBranchRef \
  --jq '.nameWithOwner + " " + .defaultBranchRef.name' 2>/dev/null) || true
[ -n "${repo:-}" ] && [ -n "${default:-}" ] || die "gh cannot name this repository or its default branch (gh repo view)"
git -C "$top" fetch -q origin "+refs/heads/$default:refs/remotes/origin/$default" \
  || die "git fetch origin $default failed"
base="$(git -C "$top" rev-parse -q --verify "refs/remotes/origin/$default^{commit}")" || die "no origin/$default after fetch"
remote="$(gh api "repos/$repo/branches/$default" --jq .commit.sha 2>/dev/null)" || remote=""
[ "$base" = "$remote" ] \
  || die "origin/$default is not verified: it is ${base:0:12}, GitHub's $repo $default is ${remote:-unreadable}"

# The tags, for the names: the one recorded at the base, and the one the
# checker updates to (its own source, the pin beside this script). The
# command itself comes from the checker alone.
from="$(git -C "$top" show "$base:.copier-answers.yml" 2>/dev/null | sed -n 's/^_commit: *//p')"
to="$(sed -nE 's/^template_ref="([^"]+)"$/\1/p' "$here/new-project.sh")"
wt="$(dirname "$top")/$(basename "$top")-template-$to"
branch="chore/template-$to"

# The command, from the checker, on exactly the files it reads at the base:
# the answers file and the workflows.
cmd_at() { # <dir>
  python3 "$checker" --root "$1" --print-update-command
}
if [ "$mode" = plan ]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  paths=()
  for p in .copier-answers.yml .github/workflows; do
    git -C "$top" cat-file -e "$base:$p" 2>/dev/null && paths+=("$p")
  done
  [ ${#paths[@]} -gt 0 ] && git -C "$top" archive "$base" -- "${paths[@]}" | tar -x -C "$tmp"
  cmd="$(cmd_at "$tmp")" || exit 1
  echo "Repository: $repo, base origin/$default at $base (verified against GitHub)"
  echo "Template:   $from -> $to"
  echo "Worktree:   $wt (branch $branch)"
  echo "Command:    $cmd"
  echo "            (--defaults: each question takes the recorded answer; one never answered takes the template's default)"
  echo
  echo "Nothing has been written (the fetch moved only origin/$default). To apply it, on the user's word:"
  echo "  $(q "$0") --apply $base"
  exit 0
fi

# ── apply ───────────────────────────────────────────────────────────────
[ "$base_arg" = "$base" ] \
  || die "base moved: origin/$default is ${base:0:12} now, not the ${base_arg:0:12} the plan named; run the plan again"

[ -n "$from" ] && [ -n "$to" ] || die "no _commit in .copier-answers.yml at the base, or no template_ref beside this script"
[ -e "$wt" ] && die "$wt already exists: finish it ($(q "$0") --finish $(q "$wt")) or discard it (git worktree remove --force $(q "$wt") && git branch -D $branch)"
git -C "$top" rev-parse -q --verify "refs/heads/$branch" >/dev/null \
  && die "branch $branch already exists: delete it (git branch -D $branch) or finish its worktree"
# --exit-code: 2 is "no such branch"; any other failure is not an answer,
# and is a stop, not an absent branch (Codex review on #273).
git -C "$top" ls-remote --exit-code --heads origin "$branch" >/dev/null; probe=$?
case "$probe" in
  2) ;;
  0) die "branch $branch already exists on origin: an update is under way there" ;;
  *) die "could not ask origin whether $branch exists (git ls-remote exit $probe, above); nothing created" ;;
esac

git -C "$top" worktree add -q --no-track -b "$branch" "$wt" "$base" || die "git worktree add failed"
dirty="$(git -C "$wt" status --porcelain --untracked-files=all)"
if [ -n "$dirty" ]; then
  echo "The new worktree is not clean before anything ran; copier was not run:" >&2
  printf '%s\n' "$dirty" | sed 's/^/  /' >&2
  die "left as is in $wt (git worktree remove --force $(q "$wt") && git branch -D $branch to discard)"
fi

cmd="$(cmd_at "$wt")" || die "no update command at the base (above); $wt left for inspection"
case "$cmd" in *" --vcs-ref $to "*) ;; *) die "the command does not update to $to: $cmd" ;; esac
read -ra words <<<"$cmd"
echo "Running in $wt:"
echo "  $cmd"
# As the door runs copier: without the token in its environment.
( cd "$wt" && env -u GH_TOKEN -u GITHUB_TOKEN "${words[@]}" < /dev/null ) \
  || die "copier update failed (above); nothing committed or pushed, $wt left as copier left it. To discard it: git worktree remove --force $(q "$wt") && git branch -D $branch"

sf="$(state_file "$wt")"
{
  printf 'repo=%s\ndefault=%s\nbase=%s\nbranch=%s\nfrom=%s\nto=%s\ncommand=%s\n' "$repo" "$default" "$base" "$branch" "$from" "$to" "$cmd"
  conflicts="$(conflicts_in "$wt")"
  while IFS= read -r p; do [ -n "$p" ] && printf 'conflict=%s\n' "$p"; done <<<"$conflicts"
  # Each file copier merged cleanly, with its content hash, so --finish can
  # tell copier's merge from a person's later edit. Nothing is staged: the
  # index stays as copier left it, conflicts unmerged.
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    grep -qxF "$p" <<<"$conflicts" && continue
    printf 'clean=%s %s\n' "$(blob "$wt" "$p")" "$p"
  done < <(changed_since "$wt" "$base")
} > "$sf"

if [ -n "$conflicts" ]; then
  echo
  echo "copier left conflicts; nothing is pushed and no pull request is opened until a person resolves them:"
  indent <<<"$conflicts"
  echo "In $wt, resolve each (remove every conflict marker, delete each .rej once applied), git add it, then run:"
  echo "  $(q "$0") --finish $(q "$wt")"
  exit 3
fi
finish "$wt"
