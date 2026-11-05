#!/usr/bin/env bash
# Apply the template update /plinth:floor-check reports as a draft pull
# request (#232, #219 stage 2). Three steps, each started by a person:
#
#   template-update.sh
#       The plan. Fetches and verifies origin/<default> against GitHub, then
#       prints the tags, the command and where it will run. Writes nothing.
#       Stops first, here and in --apply, when the installed plinth targets an
#       older template tag than the latest release's or the CI pin's (#843).
#   template-update.sh --apply <base-sha> [--plinth-pin live|tested] [--assisted-by <agent>:<model>]
#       Branches a worktree beside the repository from <base-sha> (it must
#       still be origin/<default>), requires it clean, runs the command and,
#       when copier leaves no conflict, commits, pushes the branch and opens
#       a draft pull request. A conflict stops here (exit 3), left as copier
#       left it for a person to resolve.
#   template-update.sh --finish <worktree> [--resolved <path> <how>]... [--assisted-by <agent>:<model>]
#       After a person resolved the conflicts: checks nothing is left, then
#       commits, pushes and opens the draft pull request. Also finishes an
#       update whose push or pull request failed, without a second commit.
#       Each --resolved says how one conflicted file was resolved (which
#       side, on whose word) for the description; it is a record, not a
#       check, and names only a file copier left in conflict (#556).
#       Before it pushes, it counts the reviewable diff as ci / diff-size
#       does, with the ci job's own max-diff-lines and diff-size-exclude
#       (#795). Over the limit it pushes nothing (exit 4) and proposes the
#       split: the paths of a first pull request that fits, then this one.
#       --over-limit opens it as it is, red ci / diff-size and all.
#
# The command is the checker's own line (floor-check.py
# --print-update-command), run word for word: never a second construction of
# it. It carries the plinth pin the workflows call today (#219), unless the
# person chose --plinth-pin tested: then the line with the pin the target tag
# was tested with, which the checker gives only when that one is newer
# (#511). The plan prints both when there are two, and recommends the tested
# one with the checker's one-sentence reason; only the person's confirmation
# applies it (#519). The draft is opened as soon as the tree is clean; nothing waits for the
# branch's checks. Nothing is pushed to the default branch, and nothing
# here resolves a conflict by choosing a side (#88): a person, or the agent
# on a person's word for that file (#556), resolves it in the worktree.
#
# Exit: 0 done (a plan printed, or a draft opened), 1 stopped or nothing to
# update, 2 usage, 3 a conflict is waiting for a person, 4 over the diff
# limit, nothing pushed, a split proposed.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
checker="$here/floor-check.py"
state_name="plinth-template-update"

# A path as a shell word, for a line the user or the skill runs as printed.
q() { printf '%q' "$1"; }
die()  { printf 'template-update: %s\n' "$*" >&2; exit 1; }
usage() { printf 'usage: %s [--apply <base-sha> [--plinth-pin live|tested] | --finish <worktree> [--resolved <path> <how>]... [--over-limit]] [--assisted-by <agent>:<model>]\n' "$0" >&2; exit 2; }

mode=plan; base_arg=""; wt_arg=""; assisted=""; pin=""; resolutions=(); over_limit=no
while [ $# -gt 0 ]; do
  case "$1" in
    --apply)       [ $# -ge 2 ] || usage; mode=apply; base_arg="$2"; shift 2 ;;
    --finish)      [ $# -ge 2 ] || usage; mode=finish; wt_arg="$2"; shift 2 ;;
    --assisted-by) [ $# -ge 2 ] || usage; assisted="$2"; shift 2 ;;
    --resolved)    [ $# -ge 3 ] && [ -n "$2" ] && [ -n "$3" ] || usage
                   case "$2$3" in *$'\n'* | *$'\t'*) usage ;; esac
                   resolutions+=("$2" "$3"); shift 3 ;;
    --over-limit)  over_limit=yes; shift ;;
    --plinth-pin)  [ $# -ge 2 ] || usage; pin="$2"; shift 2
                   case "$pin" in live|tested) ;; *) usage ;; esac ;;
    *) usage ;;
  esac
done
# The pin is chosen on --apply, where copier runs; anywhere else it would be
# a choice that does nothing.
[ -z "$pin" ] || [ "$mode" = apply ] || usage
[ ${#resolutions[@]} = 0 ] || [ "$mode" = finish ] || usage
# Opening over the limit is a choice made after reading the measurement.
[ "$over_limit" = no ] || [ "$mode" = finish ] || usage
pin="${pin:-live}"

for tool in git gh python3 uvx; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done

# What copier left that a person has to resolve: unmerged paths, `.rej`
# files (untracked, or staged by a `git add -A`), and conflict markers (a marked file `git add`ed is no longer
# unmerged, but it is not resolved either). The `.rej` and marker checks read
# only what differs from <base>: a `.rej` fixture or a document quoting a
# marker that the base already held is not the update's (#274). One path per
# line.
conflicts_in() { # <worktree> <base>
  local p
  {
    git -C "$1" -c core.quotePath=false diff --name-only --diff-filter=U
    # Ignored ones too: a .rej copier wrote is one whatever .gitignore says.
    # The clean check before copier does not see ignored files, so an ignored
    # .rej something else put in the fresh worktree (a checkout hook) counts
    # as well; deleting it and running again recovers (#276 review).
    git -C "$1" -c core.quotePath=false ls-files --others -- '*.rej'
    git -C "$1" -c core.quotePath=false diff --name-only --diff-filter=d "$2" -- '*.rej'
    while IFS= read -r p; do
      [ -f "$1/$p" ] && [ ! -L "$1/$p" ] && LC_ALL=C grep -qE '^(<<<<<<<|>>>>>>>) ' -- "$1/$p" && printf '%s\n' "$p"
    done < <(changed_since "$1" "$2")
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

# Over ci / diff-size's limit (#795): what a first pull request that fits
# would carry, file by file (issue forms first, as the update that raised
# this was mostly forms; then by path), and the update after it, which
# always keeps .copier-answers.yml: it records the tag, so it lands last.
# Excluded paths (docs, lockfiles) are not counted and stay with the rest.
# It prints; it runs nothing.
split_proposal() { # <wt> <merge-base> <total> <max> <exclude> <branch> <repo> <default> <to> <pathspec...>
  local wt="$1" mb="$2" total="$3" max="$4" exclude="$5" branch="$6" repo="$7" default="$8" to="$9"; shift 9
  local n path first=() firstn=0 rest=() restn=0
  while IFS=$'\t' read -r n path; do
    [ -n "$path" ] || continue
    if [ "$path" != .copier-answers.yml ] && [ $((firstn + n)) -le "$max" ]; then
      first+=("$path"); firstn=$((firstn + n))
    else
      rest+=("$path ($n)"); restn=$((restn + n))
    fi
  done < <(git -C "$wt" -c core.quotePath=false diff --no-renames --numstat "$mb" HEAD -- "$@" \
             | awk -F '\t' '$1 != "-" { k = ($3 ~ /^\.github\/ISSUE_TEMPLATE\//) ? 0 : ($3 == ".copier-answers.yml") ? 2 : 1
                                       print k "\t" $3 "\t" ($1 + $2) }' \
             | LC_ALL=C sort -t "$(printf '\t')" -k1,1n -k2,2 | cut -f2,3 | awk -F '\t' '{ print $2 "\t" $1 }')
  echo "Over the limit: $total reviewable lines, against the limit of $max that ci / diff-size would apply"
  echo "(excluded from the count: $exclude). The update is committed in $wt; nothing was pushed."
  echo
  if [ ${#first[@]} = 0 ]; then
    echo "No file fits under the limit on its own, so no split by file is proposed."
  else
    echo "Proposed split: first a pull request with these paths ($firstn lines), then this update ($restn lines):"
    local f
    for f in "${first[@]}"; do echo "  $f"; done
    echo "This update keeps the rest:"
    for f in ${rest+"${rest[@]}"}; do echo "  $f"; done
    [ "$restn" -le "$max" ] || echo "  (still over the limit: after the first is merged, --finish proposes the next split)"
    echo
    # The first number whose branch (local or on origin, as last fetched)
    # and worktree are free: an update split three ways makes a second part
    # after the first is merged, while the first's branch is still there.
    local k=1
    while git -C "$wt" rev-parse -q --verify "refs/heads/$branch-part-$k" >/dev/null \
          || git -C "$wt" rev-parse -q --verify "refs/remotes/origin/$branch-part-$k" >/dev/null \
          || [ -e "$wt-part-$k" ]; do k=$((k + 1)); done
    local p1="$wt-part-$k" b1="$branch-part-$k" words=()
    for f in "${first[@]}"; do words+=("$(q "$f")"); done
    echo "To make the first (the update's own changes to those paths, nothing else):"
    echo "  git -C $(q "$wt") worktree add --no-track -b $(q "$b1") $(q "$p1") $mb"
    echo "  git -C $(q "$wt") diff --binary $mb HEAD -- ${words[*]} | git -C $(q "$p1") apply --index"
    echo "  git -C $(q "$p1") commit -m $(q "chore(template): part of the plinth-template $to update")"
    echo "  git -C $(q "$p1") push origin HEAD:refs/heads/$(q "$b1")"
    echo "then open a draft pull request from $b1 into $default of $repo, in this repository's pull-request shape."
    echo "Once it is merged, this update follows it:"
    echo "  git -C $(q "$wt") fetch origin $(q "$default") && git -C $(q "$wt") merge --no-edit origin/$(q "$default")"
    echo "  $(q "$0") --finish $(q "$wt")"
  fi
  echo
  echo "Or open this update as it is, knowing ci / diff-size fails on it until it is split:"
  echo "  $(q "$0") --finish $(q "$wt") --over-limit"
}

# ── finish: commit, push the branch, open the draft ─────────────────────
finish() { # <worktree>
  local wt="$1" sf repo default base from to cmd branch left pr
  sf="$(state_file "$wt" 2>/dev/null)" && [ -f "$sf" ] \
    || die "$wt is not a worktree this script made (no $state_name record in its git directory)"
  repo="$(state_get "$sf" repo)"; default="$(state_get "$sf" default)"; base="$(state_get "$sf" base)"
  from="$(state_get "$sf" from)"; to="$(state_get "$sf" to)"; cmd="$(state_get "$sf" command)"
  pr="$(state_get "$sf" pr)"
  local chosen pin_note; chosen="$(state_get "$sf" pin)"; pin_note="$(state_get "$sf" pin_note)"
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

  # How each conflict was resolved: only a file copier left in conflict;
  # anything else is a usage error, before anything is committed.
  local i
  for ((i = 0; i < ${#resolutions[@]}; i += 2)); do
    grep -qxF "conflict=${resolutions[i]}" "$sf" || {
      printf 'template-update: --resolved %s: not a file copier left in conflict here; the conflicts were:\n' "${resolutions[i]}" >&2
      sed -n 's/^conflict=/  /p' "$sf" >&2
      exit 2
    }
  done

  left="$(conflicts_in "$wt" "$base")"
  if [ -n "$left" ]; then
    echo "Not resolved yet, in $wt:"
    indent <<<"$left"
    echo "Resolve each (remove every conflict marker, delete each .rej once applied), git add it, then run:"
    echo "  $(q "$0") --finish $(q "$wt")"
    [ ${#resolutions[@]} = 0 ] || echo "(--resolved was not kept: state it again on that run.)"
    exit 3
  fi
  # Kept only once nothing is left: a statement made while a file was still
  # in conflict may not be the side it ends on (Codex review on #558). A
  # --finish run again after a failed push keeps what this one said.
  for ((i = 0; i < ${#resolutions[@]}; i += 2)); do
    printf 'resolved=%s\t%s\n' "${resolutions[i]}" "${resolutions[i+1]}" >> "$sf"
  done

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

  # The reviewable diff, counted as ci / diff-size counts it (#795): the
  # pathspecs and numstat of its step, with the ci job's own inputs read by
  # the checker, from the merge base with origin/<default>, which a merge
  # of the default branch moves (the second half of a split). The tree is
  # the one about to be pushed: the index, or the commit already made.
  local mb size_line="" cfg max exclude droot split=no
  mb="$(git -C "$wt" merge-base HEAD "refs/remotes/origin/$default" 2>/dev/null)" || mb="$base"
  local tree=(--cached "$mb"); [ "$committed" = yes ] && tree=("$mb" HEAD)
  if cfg="$(python3 "$checker" --root "$wt" --print-diff-size 2>&1)"; then
    max="$(sed -n 's/^max=//p' <<<"$cfg")"; exclude="$(sed -n 's/^exclude=//p' <<<"$cfg")"; droot="$(sed -n 's/^root=//p' <<<"$cfg")"
    local prefix="" spec=(".") pats=() p
    droot="${droot%/}"
    if [ -n "$droot" ] && [ "$droot" != . ]; then prefix="$droot/"; spec=("$droot"); fi
    [ -z "$exclude" ] || read -r -a pats <<<"$exclude"
    for p in ${pats+"${pats[@]}"}; do spec+=(":(exclude)$prefix$p"); done
    local numstat total=0 a d
    numstat="$(git -C "$wt" diff --numstat "${tree[@]}" -- "${spec[@]}")" || die "the diff could not be counted in $wt"
    while read -r a d _; do
      [ -n "$a" ] && [ "$a" != - ] || continue
      total=$((total + a + d))
    done <<<"$numstat"
    if [ "$max" -le 0 ]; then
      size_line="\`ci / diff-size\`, counted here before pushing: $total reviewable lines; max-diff-lines is $max, so it is measured, not enforced."
    elif [ "$total" -le "$max" ]; then
      size_line="\`ci / diff-size\`, counted here before pushing: $total reviewable lines, within the limit of $max (excluded: \`$exclude\`)."
    elif [ "$over_limit" = yes ]; then
      size_line="\`ci / diff-size\`, counted here before pushing: $total reviewable lines, over the limit of $max (excluded: \`$exclude\`). Opened as it is on \`--over-limit\`: the check fails until the update is split."
    else
      split=yes
      size_line="\`ci / diff-size\`, counted here before pushing: $total reviewable lines, over the limit of $max (excluded: \`$exclude\`); nothing was pushed, and a split was proposed."
    fi
  else
    size_line="\`ci / diff-size\` was not counted here before pushing ($cfg); its own run counts it."
  fi

  # What went in, by who: copier's clean merges (unchanged since copier left
  # them), the files it left in conflict, and anything else a person changed.
  local clean="" resolved="" edited="" path h
  # Each conflicted file with how it was resolved, the last statement for it
  # winning; none stated claims no side.
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    # ENVIRON, not -v: -v would read a backslash in the path as an escape.
    h="$(P="$path" awk -F '\t' 'sub(/^resolved=/, "") && $1 == ENVIRON["P"] { sub(/^[^\t]*\t/, ""); how = $0 } END { print how }' "$sf")"
    if [ -n "$h" ]; then resolved="$resolved$path: $h"$'\n'
    else resolved="$resolved$path (how it was resolved was not stated)"$'\n'; fi
  done < <(sed -n 's/^conflict=//p' "$sf")
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    grep -qxF "conflict=$path" "$sf" && continue
    # A renamed glossary is the script's only while its content is the one it
    # moved; a later edit is a person's, listed with theirs (Codex review on #740).
    sed -n 's/^renamed=//p' "$sf" | cut -f1 | grep -qxF -- "$path" && continue
    sed -n 's/^renamed=//p' "$sf" | awk -F '\t' -v p="$path" -v h="$(blob "$wt" "$path")" '$2 == p && $3 == h { f = 1 } END { exit !f }' && continue
    h="$(awk -v p="$path" 'sub(/^clean=/, "") { h = $1; sub(/^[^ ]* /, ""); if ($0 == p) print h }' "$sf")"
    if [ -n "$h" ] && [ "$h" = "$(blob "$wt" "$path")" ]; then clean="$clean$path"$'\n'
    else edited="$edited$path"$'\n'; fi
  done < <(git -C "$wt" -c core.quotePath=false diff --cached --name-only "$mb")

  local title="chore(template): update plinth-template $from to $to"
  # At the target tag the checker gives a line only for a recorded owner
  # answer that no longer holds (#770): a re-render, not a move.
  [ "$from" != "$to" ] || title="chore(template): re-render plinth-template $to for the owner's templates"
  local msg body; msg="$(mktemp)"; body="$(mktemp)"
  list() { if [ -n "$1" ]; then printf '%s\n' "$1" | sed '/^$/d; s/^/- /'; else echo "- none"; fi; }
  {
    echo "## What and why"
    echo
    if [ "$from" = "$to" ]; then
      echo "Re-renders this repository at plinth-template $to, the tag it already records,"
      echo "because the owner's \`.github\` no longer publishes a pull-request template or"
      echo "issue forms it recorded as shared (\`.copier-answers.yml\` in the diff shows the"
      echo "answer that turned false), by running the command the checker gives for it:"
    else
      echo "Updates this repository from plinth-template $from to $to, the tag plinth is"
      echo "tested with, by running the command \`/plinth:floor-check\` prints for it:"
    fi
    echo
    echo '```text'
    echo "$cmd"
    echo '```'
    echo
    if [ "$chosen" = tested ]; then
      echo "The plinth pin: moved to the one $to was tested with (\`--plinth-pin tested\`, recommended, on a person's word)."
    elif [ "$chosen" = same ]; then
      echo "The plinth pin: unchanged; the workflows already called the one $to was tested with."
    else
      echo "The plinth pin: kept at the one the workflows called before the update (\`--plinth-pin live\`)."
    fi
    [ -z "$pin_note" ] || { echo; echo "Before the update: ${pin_note#plinth pin: }"; }
    if grep -q '^moves=' "$sf"; then
      echo
      echo "Before the update the workflows called plinth at two commits; each file below called an"
      echo "ancestor of the ci job's commit, and the update moved it to the pin above:"
      echo
      sed -n 's/^moves=/- /p' "$sf"
    fi
    echo
    echo "Merged cleanly (copier's merge, unchanged since):"
    echo
    list "$clean"
    echo
    echo "Left in conflict by copier, each with how it was resolved as stated to \`--finish\`:"
    echo
    list "$resolved"
    echo
    echo "Edited by a person after the update, outside a conflict:"
    echo
    list "$edited"
    echo
    if grep -qE '^(not_)?renamed=' "$sf"; then
      echo "Renamed by this script to the glossary name the template now uses; the move changes no content:"
      echo
      list "$(sed -n 's/^renamed=//p' "$sf" | while IFS=$'\t' read -r o n h; do
        if [ "$h" = "$(blob "$wt" "$n")" ]; then echo "$o -> $n"
        else echo "$o -> $n (edited after the move: listed with the person's edits above)"; fi
      done)"
      echo
      if grep -q '^not_renamed=' "$sf"; then
        echo "Not renamed:"
        echo
        list "$(sed -n 's/^not_renamed=//p' "$sf")"
        echo
      fi
    fi
    echo "## How it was verified"
    echo
    echo "Opened as a draft once no conflict was left: no unmerged path, and no"
    echo "\`.rej\` file or conflict marker in a file the update changed (files unchanged"
    echo "since $(printf '%.12s' "$base") were not read). This repository's own checks had not run"
    echo "when it was opened; they run on it now. This script resolved no conflict;"
    echo "how each was resolved is what \`--resolved\` stated, which the script does"
    echo "not check, and \"not stated\" where nothing was."
    echo "copier's questions were answered with \`--defaults\`: each takes this"
    echo "repository's recorded answer, and a question it never answered takes the"
    echo "template's default (\`.copier-answers.yml\` in the diff shows any)."
    echo
    echo "$size_line"
    if [ -n "$assisted" ]; then echo; echo "Assisted-by: $assisted"; fi
  } > "$body"
  { echo "$title"; echo; cat "$body"; } > "$msg"

  if [ "$committed" = no ]; then
    git -C "$wt" commit -q -F "$msg" || { rm -f "$msg" "$body"; die "git commit failed in $wt"; }
  fi
  rm -f "$msg"
  # Over the limit: the update stays a local commit, which a merge of the
  # default branch can follow once the first part is merged (#795).
  if [ "$split" = yes ]; then
    rm -f "$body"
    split_proposal "$wt" "$mb" "$total" "$max" "$exclude" "$branch" "$repo" "$default" "$to" "${spec[@]}"
    exit 4
  fi
  # The one push this script makes, to the update branch by name. The
  # default branch is refused above and never named here.
  git -C "$wt" push -q origin "HEAD:refs/heads/$branch" \
    || { rm -f "$body"; die "pushing $branch failed; the commit is in $wt, no pull request opened. Run again: $(q "$0") --finish $(q "$wt")"; }
  # A pull request GitHub created although gh reported a failure (the reply
  # lost on the way back) is this one: adopt it rather than fail on the
  # duplicate every time (Codex review on #273). `--head` matches the branch
  # name only, so a fork's pull request from a branch of the same name
  # answers too: adopt only one whose head is this repository at the commit
  # just pushed (#274).
  local pushed own; pushed="$(git -C "$wt" rev-parse HEAD)"
  own="$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')"
  pr="$(gh pr list --repo "$repo" --head "$branch" --base "$default" --state open \
    --json url,headRepositoryOwner,headRepository,headRefOid \
    --jq "[.[] | select((.headRepositoryOwner.login + \"/\" + .headRepository.name | ascii_downcase) == \"$own\" and .headRefOid == \"$pushed\")][0].url // empty" \
    2>/dev/null)" || pr=""
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
to_sha="$(sed -nE 's/^template_sha="([0-9a-f]{40})"$/\1/p' "$here/new-project.sh")"
wt="$(dirname "$top")/$(basename "$top")-template-$to"
branch="chore/template-$to"
# A re-render at the recorded tag (#770) gets its own names: the update that
# brought the repository to $to may have left chore/template-$to behind.
if [ "$from" = "$to" ]; then wt="$wt-owner-templates"; branch="$branch-owner-templates"; fi

# The command, from the checker, on exactly the files it reads at the base:
# the answers file, the workflows and the repository's own issue and
# pull-request templates (#726). With `tested`, the line with the tested
# pin, the comparison on stderr whether or not there is one. `--repo` names
# whose `.github` the checker reads for the two answers the update carries,
# as the door's render did; a read that fails gives no line (#726).
cmd_at() { # <dir> [live|tested]
  python3 "$checker" --root "$1" --repo "$repo" --print-update-command --plinth-pin "${2:-live}"
}
at_base() { # sets $tmp: the files the checker reads, as they are at the base
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  paths=()
  for p in .copier-answers.yml .github/workflows .github/ISSUE_TEMPLATE \
           PULL_REQUEST_TEMPLATE.md .github/PULL_REQUEST_TEMPLATE.md docs/PULL_REQUEST_TEMPLATE.md; do
    git -C "$top" cat-file -e "$base:$p" 2>/dev/null && paths+=("$p")
  done
  [ ${#paths[@]} -gt 0 ] && git -C "$top" archive "$base" -- "${paths[@]}" | tar -x -C "$tmp"
}
# The installed plinth may target an older tag than the project could move to
# (#843). Older is a stop before anything is written; the person types the
# commands, since a running session does not load a new version. A comparison
# that could not be made is said, and the update goes on with this target.
plugin_gate() {
  local says rc=0
  says="$(python3 "$checker" --root "$tmp" --print-plugin-skew)" || rc=$?
  case "$rc" in
    0) ;;
    3) printf '%s\n' "$says"
       echo "Nothing has been written (the fetch moved only origin/$default)."
       exit 1 ;;
    *) echo "the installed plinth was not compared with the latest release (the check exited $rc); going on with the template tag this plinth targets, $to" >&2 ;;
  esac
}
if [ "$mode" = plan ]; then
  at_base
  plugin_gate
  # Its stderr as before, but for the `moves:` lines (#793), which the plan
  # prints under the command.
  cmd="$(cmd_at "$tmp" 2>"$tmp/live-note")" || { cat "$tmp/live-note" >&2; exit 1; }
  grep -v '^moves: ' "$tmp/live-note" >&2
  tested_cmd="$(cmd_at "$tmp" tested 2>"$tmp/pin-note")" || tested_cmd=""
  [ "$tested_cmd" != "$cmd" ] || tested_cmd=""
  echo "Repository: $repo, base origin/$default at $base (verified against GitHub)"
  if [ "$from" = "$to" ]; then echo "Template:   $to, re-rendered for the owner answers named above"
  else echo "Template:   $from -> $to"; fi
  echo "Worktree:   $wt (branch $branch)"
  echo "Command:    $cmd"
  echo "            (--defaults: each question takes the recorded answer; one never answered takes the template's default)"
  sed -n 's/^moves: /Moves:      /p' "$tmp/live-note"
  if [ -n "$tested_cmd" ] && grep -q '^moves: ' "$tmp/live-note"; then
    echo "            (with the tested pin, each moves to that pin instead, and so does ci.yml)"
  fi
  sed -n 's/^plinth pin: /Plinth pin: /p' "$tmp/pin-note"
  if [ -n "$tested_cmd" ]; then
    echo "With the tested pin: $tested_cmd"
    sed -n 's/^recommended: /Recommended: /p' "$tmp/pin-note"
  fi
  echo
  echo "Nothing has been written (the fetch moved only origin/$default). To apply it, on the user's word:"
  if [ -n "$tested_cmd" ]; then
    echo "  moving it to the one $to was tested with (recommended):"
    echo "  $(q "$0") --apply $base --plinth-pin tested"
    echo "  or keeping the plinth pin the workflows call today:"
    echo "  $(q "$0") --apply $base --plinth-pin live"
  else
    echo "  $(q "$0") --apply $base"
  fi
  exit 0
fi

# ── apply ───────────────────────────────────────────────────────────────
[ "$base_arg" = "$base" ] \
  || die "base moved: origin/$default is ${base:0:12} now, not the ${base_arg:0:12} the plan named; run the plan again"
at_base
plugin_gate

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

# The comparison is read whichever pin was chosen, for the description; only
# --plinth-pin tested takes its line, and stops when there is none.
note_file="$(mktemp)"
tested_cmd="$(cmd_at "$wt" tested 2>"$note_file")"; tested_rc=$?
pin_note="$(sed -n '/^plinth pin: /{p;q;}' "$note_file")"
why_none="${pin_note:-$(head -n 1 "$note_file")}"; rm -f "$note_file"
# The live line, read once: the command itself with --plinth-pin live, and
# with either pin the files it moves forward to the ci job's commit (#793),
# its `moves:` lines. A read that fails while the pins disagree is a stop,
# never an empty list that would skip the check after copier.
live_note="$(mktemp)"
live_cmd="$(cmd_at "$wt" 2>"$live_note")"; live_rc=$?
moves="$(sed -n 's/^moves: //p' "$live_note")"
if [ "$live_rc" != 0 ] && grep -q "workflow pins disagree" "$live_note"; then
  cat "$live_note" >&2; rm -f "$live_note"
  die "the workflows call plinth at more than one commit and the update cannot carry one (above); $wt left for inspection"
fi
if [ "$pin" = tested ]; then
  rm -f "$live_note"
  [ "$tested_rc" = 0 ] && cmd="$tested_cmd" \
    || die "no update command with the tested pin (${why_none:-no reason given}); $wt left for inspection. Run the plan again, or --apply with --plinth-pin live"
  # The live pin is already the tested one: nothing moved, and the
  # description must not say it did.
  [ "$cmd" != "$live_cmd" ] || pin=same
else
  [ "$live_rc" = 0 ] && cmd="$live_cmd" \
    || { grep -v '^moves: ' "$live_note" >&2; rm -f "$live_note"; die "no update command at the base (above); $wt left for inspection"; }
  grep -v '^moves: ' "$live_note" >&2; rm -f "$live_note"
fi
case "$cmd" in *" --vcs-ref ${to_sha:-?} "*) ;; *) die "the command does not update to $to ($to_sha): $cmd" ;; esac
read -ra words <<<"$cmd"
echo "Running in $wt:"
echo "  $cmd"
# As the door runs copier: without the token in its environment.
( cd "$wt" && env -u GH_TOKEN -u GITHUB_TOKEN "${words[@]}" < /dev/null ) \
  || die "copier update failed (above); nothing committed or pushed, $wt left as copier left it. To discard it: git worktree remove --force $(q "$wt") && git branch -D $branch"

# When the pins disagreed at the base (#793), every plinth uses: that copier
# did not leave in conflict must now name the pin the command carried: copier
# applies a diff, and a hand-edited line is not what it rendered. Read by the
# checker, as the pin items read them (a `run: |` block's text is not a
# uses:); a uses: it cannot read counts as not named. Fails closed.
if [ -n "$moves" ]; then
  want_pin="$(sed -nE 's/.* --data plinth_sha=([0-9a-fA-F]{40})( .*)?$/\1/p' <<<"$cmd" | tr 'A-F' 'a-f')"
  left="$(conflicts_in "$wt" "$base")"; stale=""
  found="$(python3 "$checker" --root "$wt" --print-plinth-pins)" || found="? the workflows could not be read"
  while IFS=' ' read -r file ref; do
    [ -n "$file" ] || continue
    grep -qxF -- ".github/workflows/$file" <<<"$left" && continue
    case "$ref" in
      "unread line "*) stale="$stale  .github/workflows/$file has a uses: at ${ref#unread } that cannot be read"$'\n' ;;
      *) [ "$(tr 'A-F' 'a-f' <<<"$ref")" = "$want_pin" ] || stale="$stale  .github/workflows/$file calls $ref, not $want_pin"$'\n' ;;
    esac
  done <<<"$found"
  if [ -n "$stale" ]; then
    printf 'template-update: after copier, a plinth uses: line does not name the pin the command carried:\n%s' "$stale" >&2
    die "nothing committed or pushed, $wt left as copier left it. To discard it: git worktree remove --force $(q "$wt") && git branch -D $branch"
  fi
fi

# The glossary's name follows the template (#714). copier never touches the
# repository's own glossary, a file /domain-modeling wrote, so when the
# updated docs/agents/domain.md names GLOSSARY.md and the root still holds
# CONTEXT.md, it is moved here, content unchanged; CONTEXT-MAP.md likewise.
# Only a tracked file whose new name is free; the description names what
# was moved and what was not.
renamed=""; not_renamed=""
if grep -qF '`GLOSSARY.md`' "$wt/docs/agents/domain.md" 2>/dev/null; then
  for pair in "CONTEXT.md GLOSSARY.md" "CONTEXT-MAP.md GLOSSARY-MAP.md"; do
    read -r old new <<<"$pair"
    git -C "$wt" ls-files --error-unmatch -- "$old" >/dev/null 2>&1 || continue
    if [ -e "$wt/$new" ]; then not_renamed="$not_renamed$old: $new already exists"$'\n'; continue; fi
    # git mv, not mv: the index entry moves, so the file stays tracked where
    # the repository's .gitignore matches the new name (Codex review on #740).
    git -C "$wt" mv -- "$old" "$new" || die "moving $old to $new failed in $wt; nothing committed or pushed"
    renamed="$renamed$old"$'\t'"$new"$'\t'"$(blob "$wt" "$new")"$'\n'
  done
  # A context's own CONTEXT.md, which a map points to, keeps its name: the
  # map's links would have to change with it.
  while IFS= read -r p; do
    [ -n "$p" ] && not_renamed="$not_renamed$p: a context's glossary under a map, left for a person"$'\n'
  done < <(git -C "$wt" -c core.quotePath=false ls-files -- '*/CONTEXT.md')
fi

sf="$(state_file "$wt")"
{
  printf 'repo=%s\ndefault=%s\nbase=%s\nbranch=%s\nfrom=%s\nto=%s\ncommand=%s\npin=%s\npin_note=%s\n' \
    "$repo" "$default" "$base" "$branch" "$from" "$to" "$cmd" "$pin" "$pin_note"
  while IFS= read -r p; do [ -n "$p" ] && printf 'renamed=%s\n' "$p"; done <<<"$renamed"
  while IFS= read -r p; do [ -n "$p" ] && printf 'moves=%s\n' "$p"; done <<<"$moves"
  while IFS= read -r p; do [ -n "$p" ] && printf 'not_renamed=%s\n' "$p"; done <<<"$not_renamed"
  conflicts="$(conflicts_in "$wt" "$base")"
  while IFS= read -r p; do [ -n "$p" ] && printf 'conflict=%s\n' "$p"; done <<<"$conflicts"
  # Each file copier merged cleanly, with its content hash, so --finish can
  # tell copier's merge from a person's later edit. Nothing is staged: the
  # index stays as copier left it, conflicts unmerged.
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    grep -qxF "$p" <<<"$conflicts" && continue
    printf '%s\n' "$renamed" | cut -f1,2 | tr '\t' '\n' | grep -qxF -- "$p" && continue
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
