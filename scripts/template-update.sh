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
#       update whose push or pull request failed, without a second commit,
#       and one whose branch a person pushed after a refusal, without
#       pushing it again.
#       Each --resolved says how one conflicted file was resolved (which
#       side, on whose word) for the description; it is a record, not a
#       check, and names only a file copier left in conflict (#556).
#       Before it pushes, it counts the reviewable diff as ci / diff-size
#       does, with the ci job's own max-diff-lines and diff-size-exclude
#       (#795). Over the limit it pushes nothing (exit 4) and proposes the
#       split: the paths of a first pull request that fits, then this one.
#       --over-limit opens it as it is, red ci / diff-size and all. A move's
#       release.yml is left out of that count as the plinth the workflows
#       call leaves it out (#1044); with one that counts it, a release.yml
#       over the limit by itself stops the plan and --apply.
#   template-update.sh --archetype <a>
#   template-update.sh --apply <base-sha> --archetype <a> [--keep <path> | --drop <path>]... [--assisted-by <agent>:<model>]
#       An archetype move (#1004), at the tag the repository records: the
#       checker's line with `--data archetype=<a>`. The plan runs it on a copy
#       of the base outside the repository and prints what it deletes, adds
#       and changes, where it conflicts, the CI jobs that stop, and for a
#       required check that stops, the admin command a person runs before the
#       move's pull request merges. --apply and --finish are as above; a
#       conflict also shows this repository's side, which may hold its own code.
#       copier deletes a file of the old archetype the project changed as
#       readily as one it left alone, reporting no conflict (measured, copier
#       9.18.2, #1016). Both the plan and --apply compare each deleted file
#       with copier's own render of the recorded answers at the recorded tag;
#       one that differs is listed apart, and --apply stops before writing
#       anything until each is named once: --keep restores it after copier, as
#       the project's own file; --drop lets the move delete it.
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
# limit, nothing pushed, a split proposed, 5 origin refused the push for the
# workflow permission: a person pushes the branch, then --finish (#925).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
checker="$here/floor-check.py"
state_name="plinth-template-update"

# A path as a shell word, for a line the user or the skill runs as printed:
# sq, the doors' own quoting, which shows Hangul as typed (#1065).
# shellcheck source=scripts/lib/shell-word.sh
. "$here/lib/shell-word.sh" || { printf 'template-update: no %s\n' "$here/lib/shell-word.sh" >&2; exit 1; }
q() { sq "$1"; }
die()  { printf 'template-update: %s\n' "$*" >&2; exit 1; }
usage() { printf 'usage: %s [--apply <base-sha> [--plinth-pin live|tested | --archetype <a> [--keep <path> | --drop <path>]...] | --archetype <a> | --finish <worktree> [--resolved <path> <how>]... [--over-limit]] [--assisted-by <agent>:<model>]\n' "$0" >&2; exit 2; }

mode=plan; base_arg=""; wt_arg=""; assisted=""; pin=""; resolutions=(); over_limit=no; move=""; chosen_files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --apply)       [ $# -ge 2 ] || usage; mode=apply; base_arg="$2"; shift 2 ;;
    --finish)      [ $# -ge 2 ] || usage; mode=finish; wt_arg="$2"; shift 2 ;;
    --assisted-by) [ $# -ge 2 ] || usage; assisted="$2"; shift 2 ;;
    --resolved)    [ $# -ge 3 ] && [ -n "$2" ] && [ -n "$3" ] || usage
                   case "$2$3" in *$'\n'* | *$'\t'*) usage ;; esac
                   resolutions+=("$2" "$3"); shift 3 ;;
    --over-limit)  over_limit=yes; shift ;;
    --keep | --drop)
                   [ $# -ge 2 ] && [ -n "$2" ] || usage
                   case "$2" in *$'\n'* | *$'\t'*) usage ;; esac
                   chosen_files+=("${1#--}"$'\t'"$2"); shift 2 ;;
    --archetype)   [ $# -ge 2 ] && [ -n "$2" ] || usage; move="$2"; shift 2 ;;
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
# A move carries the live pin, and --finish reads the move from its record.
[ -z "$move" ] || { [ -z "$pin" ] && [ "$mode" != finish ]; } || usage
# What becomes of a changed file the move deletes is said where copier runs.
[ ${#chosen_files[@]} = 0 ] || { [ "$mode" = apply ] && [ -n "$move" ]; } || usage
pin="${pin:-live}"

# GitHub or GitLab (#1012; #924 stopped on GitLab). Told by origin's URL as
# configured (gitlab.com, *.gitlab.com, or a gitlab.* host) or by `host:
# gitlab` in the answers file, for a GitLab under another name. copier runs
# the same way on both; only what reads and writes the host differs: gh and
# a pull request on GitHub, `glab api` and a merge request on GitLab, asked
# of the host and project origin's URL names. --finish reads the host from
# the record --apply wrote.
origin_parts() { # <top>: "<host> <path>" from origin's URL as configured, or exit 1
  local url h p
  url="$(git -C "$1" config --get remote.origin.url 2>/dev/null)" || return 1
  case "$url" in
    *://*) h="${url#*://}"; p="${h#*/}"; h="${h%%/*}"; h="${h##*@}"; h="${h%%:*}"
           [ "$p" != "${url#*://}" ] || p="" ;;
    [!/]*:*) h="${url%%:*}"; case "$h" in */*) return 1 ;; esac; h="${h##*@}"; p="${url#*:}" ;;
    *) return 1 ;;
  esac
  p="${p%/}"; p="${p%.git}"; p="${p#/}"
  printf '%s %s\n' "$(printf '%s' "$h" | tr '[:upper:]' '[:lower:]')" "$p"
}
on_gitlab() {
  local top h _
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  sed -nE "s/^host: *['\"]?([^'\" ]*).*/\1/p" "$top/.copier-answers.yml" 2>/dev/null | grep -qx gitlab && return 0
  read -r h _ < <(origin_parts "$top") || return 1
  case "$h" in gitlab.com | *.gitlab.com | gitlab.*) return 0 ;; esac
  return 1
}
host=github; gl_host=""; gl_path=""
if [ "$mode" = finish ]; then
  rec="$(git -C "$wt_arg" rev-parse --absolute-git-dir 2>/dev/null)/$state_name"
  [ "$(sed -n 's/^host=//p' "$rec" 2>/dev/null | head -n 1)" = gitlab ] && host=gitlab
elif on_gitlab; then
  host=gitlab
  read -r gl_host gl_path < <(origin_parts "$(git rev-parse --show-toplevel)") || gl_path=""
  case "$gl_path" in
    */*) ;;
    *) die "this repository is on GitLab, but origin's URL names no GitLab project (<host>/<group>/<name>), which glab is asked about: nothing was changed. Set origin to the project's GitLab URL, then run this again." ;;
  esac
fi
# The words for what is opened, by host.
if [ "$host" = gitlab ]; then noun="merge request"; hostname=GitLab; cli=glab
else noun="pull request"; hostname=GitHub; cli=gh; fi

for tool in git "$cli" python3 uvx; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done
# A path segment for GitLab's API: the project's path or a branch, encoded whole.
enc() { python3 -I -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"; }
# GET (or another method) on GitLab's API through glab, as the person's own login.
gl_api() { glab api --hostname "$gl_host" "$@"; }
# A field of a JSON object on stdin, by a path of keys (a.b); nothing when absent.
json_get() { python3 -I -c '
import json, sys
try:
    d = json.load(sys.stdin)
    for k in sys.argv[1].split("."):
        d = d[k]
except (ValueError, KeyError, TypeError):
    sys.exit(1)
print(str(d).lower() if isinstance(d, bool) else d)' "$1"; }

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
# The version of the plinth this script is from, which reads a check an
# archetype move adds as not required yet (#1017).
# The checks a move starts that the default branch does not require yet,
# from a record (check_add=, required_read=, required=): every one when the
# required checks were not read. One already required (a project's own
# `image` job) passes any plinth's floor check (Codex review on #1029).
unrequired_adds() { # <record file>
  local c
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    grep -qx 'required_read=yes' "$1" && grep -qxF "required=$c" "$1" && continue
    printf '%s\n' "$c"
  done < <(sed -n 's/^check_add=//p' "$1")
}
plinth_version() { sed -nE 's/^[[:space:]]*"version":[[:space:]]*"([^"]+)".*/\1/p' "$here/../.claude-plugin/plugin.json" | head -n 1; }
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
  # An archetype move's release.yml over the limit by itself, counted because
  # the plinth the workflows call does not leave it out (#1044).
  local rel_alone=""
  [ -z "$(state_get "$sf" archetype)" ] || [ "$(state_get "$sf" size_move | cut -d ' ' -f 1)" = held ] || rel_alone="$(printf '%s\n' ${rest+"${rest[@]}"} \
    | awk -v f="$rel_wf" -v m="$max" 'index($0, f " (") == 1 { n = substr($0, length(f) + 3); sub(/\)$/, "", n); if (n + 0 > m + 0) print n }')"
  if [ ${#first[@]} = 0 ]; then
    echo "No file fits under the limit on its own, so no split by file is proposed."
  else
    echo "Proposed split: first a pull request with these paths ($firstn lines), then this update ($restn lines):"
    local f
    for f in "${first[@]}"; do echo "  $f"; done
    echo "This update keeps the rest:"
    for f in ${rest+"${rest[@]}"}; do echo "  $f"; done
    [ -z "${rel_n:-}" ] || echo "  $rel_wf ($rel_n, not counted: an archetype move, #1044)"
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
  if [ -n "$rel_alone" ]; then
    echo
    echo "$rel_wf alone is $rel_alone lines, and no split by file cuts one file. plinth v$(plinth_version) and later leave it out of"
    echo "ci / diff-size's count in the pull request that changes archetype: (#1044)."
    local sm; sm="$(state_get "$sf" size_move)"
    if [ "${sm%% *}" = fails ]; then
      echo "The plinth the workflows call ($(cut -d ' ' -f 2 <<<"$sm" | cut -c 1-12)) counts it: raise the plinth pin to that version or later first."
    else
      echo "Whether the plinth the workflows call does was not read when the move was applied${sm:+ (${sm#* * })}, and --finish does not read it again."
      echo "If it does, its ci / diff-size leaves the file out: once the rest is split off, open this part with --over-limit (below)"
      echo "and that check decides; if it is older, raise the plinth pin to that version or later first."
    fi
  fi
  echo
  echo "Or open this update as it is, knowing ci / diff-size fails on it until it is split:"
  echo "  $(q "$0") --finish $(q "$wt") --over-limit"
}

# ── an archetype move (#1004) ───────────────────────────────────────────
# A command a person runs with an admin token (#1045). In a description it is
# written inline (under `scripts/`, which is public). In the plan, where the
# command names this script's folder and the allowlist's runs past 300
# characters, a line pasted from a chat into a terminal breaks: it goes into
# a file in <dir>, and the plan prints `bash <that file>`, its own line, with
# where to run it. with-admin-token.sh prompts for the token at a terminal,
# so not through `!`, where it has none.
admin_cmd() { # <dir or empty> <file name> <command>
  if [ -z "$1" ]; then printf '`%s`' "$3"; return; fi
  printf '#!/usr/bin/env bash\n# Written by template-update.sh (plinth): run it in a terminal of your own,\n# not through `!`; with-admin-token.sh asks there for an admin token.\n%s\n' "$3" > "$1/$2.sh"
  printf 'the file below, which holds the command, in a separate terminal, not through `!` (with-admin-token.sh asks for the token at a terminal, which `!` does not give it):\n    bash %s' "$1/$2.sh"
}
# A check name as part of a file name, cut to 24 characters: the `bash` line
# stays under 120 even in mktemp's fallback under macOS's $TMPDIR.
slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '-' | tr -s '-' | sed 's/^-//; s/-$//' | cut -c 1-24; }
# What a person does about the required checks the move stops or starts,
# from the record: drop one that stops before the move merges (a required
# name that never reports blocks every merge), require one that starts once
# it has run on the default branch. Commands under <prefix> (this script's
# folder in the terminal, `scripts/` in a description, which is public).
# A check the move starts cannot be required before the move merges, so the
# move's own `ci / floor-check` passes only with a plinth that reads it as
# not required yet (#1017): add_floor says whether the one the workflows
# call does.
move_steps() { # <state file> <prefix> [<dir>: write each admin command there, as admin_cmd does]
  local sf="$1" pre="$2" dir="${3:-}" repo default c rd af pin ver k=0
  repo="$(state_get "$sf" repo)"; default="$(state_get "$sf" default)"; rd="$(state_get "$sf" required_read)"
  af="$(state_get "$sf" add_floor)"; pin="$(cut -d ' ' -f 2 <<<"$af")"; ver="$(plinth_version)"
  local admin="${pre}with-admin-token.sh ${pre}require-check.sh"
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    if [ "$rd" != yes ]; then
      k=$((k + 1)); echo "$c stops running; whether $default requires $c was not read. If it does, before the move's pull request merges, a person runs, with an admin token (never the agent's): $(admin_cmd "$dir" "$k-drop-$(slug "$c")" "$admin --drop --repo $repo '$c'")"
    elif grep -qxF "required=$c" "$sf"; then
      k=$((k + 1)); echo "Required check that stops running: $c, required on $default now. Before the move's pull request merges, a person runs, with an admin token (never the agent's): $(admin_cmd "$dir" "$k-drop-$(slug "$c")" "$admin --drop --repo $repo '$c'")"
    else
      echo "$c stops running, and no ruleset requires it on $default: nothing to drop. Classic branch protection is not read; if it requires $c, a person removes it there."
    fi
  done < <(sed -n 's/^check_drop=//p' "$sf")
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    if [ "$rd" = yes ] && grep -qxF "required=$c" "$sf"; then
      echo "$c starts running, and $default already requires it: nothing to add, and the move's ci / floor-check finds it required."
      continue
    fi
    case "${af%% *}" in
      held) k=$((k + 1)); echo "$c starts running. The move's pull request passes ci / floor-check before $c is required: the plinth its workflows call (${pin:0:12}) reads a check the move adds as not required yet; until $c is required, ci / floor-check fails on $default and on every pull request brought up to date with it. Once the move is merged and $c has run on $default, a person requires it, with an admin token (never the agent's): $(admin_cmd "$dir" "$k-require-$(slug "$c")" "$admin --repo $repo '$c'")" ;;
      fails) echo "$c starts running, and the plinth the workflows call (${pin:0:12}) fails the move's ci / floor-check until $c is required, which require-check.sh refuses before $c has run on $default. Raise the plinth pin first: merge a pull request that moves every coolbress/plinth uses: line to plinth v$ver or later (Dependabot's, or one by hand), then plan the move again." ;;
      *) k=$((k + 1)); echo "$c starts running; whether the plinth the workflows call passes the move's ci / floor-check before $c is required was not read${af:+ (${af#* * })}. This plinth (v$ver) does, and one from before it may fail it; then the plinth pin is raised first. Once the move is merged and $c has run on $default, to require it, a person runs, with an admin token (never the agent's): $(admin_cmd "$dir" "$k-require-$(slug "$c")" "$admin --repo $repo '$c'")" ;;
    esac
  done < <(sed -n 's/^check_add=//p' "$sf")
  # The Actions allowlist (#1018): the door set it for the old archetype,
  # and the move changes files, not the setting.
  local refused allow n s
  refused="$(sed -n 's/^action_refused=//p' "$sf" | sed -E 's/^(.*) ([^ ]+)$/\2 (\1)/' | awk 'NR > 1 { printf ", " } { printf "%s", $0 }')"
  allow="$(state_get "$sf" action_allow)"
  if [ -n "$refused" ]; then
    local then=""; case "$allow" in *"/actions/permissions "*) then=", then plans the move again for the allowlist itself" ;; esac
    echo "The Actions allowlist refuses $refused, which the workflows use after the move: a run that uses one ends in startup_failure, with no job and no message saying why. Before the move's pull request merges, a person runs, with an admin token (never the agent's)$then: $(admin_cmd "$dir" allow-actions "${pre}with-admin-token.sh $allow")"
  fi
  while IFS= read -r s; do
    [ -n "$s" ] && echo "The Actions allowlist, not judged for the workflows after the move: $s."
  done < <(sed -n 's/^action_skip=//p' "$sf")
  n="$(state_get "$sf" actions_allowed)"
  [ -z "$n" ] || echo "The Actions allowlist lets every action the workflows use after the move start ($n uses): nothing to allow."
  if grep -q '^actions_unread=' "$sf"; then
    echo "Whether the Actions allowlist lets every action the workflows use after the move start was not read ($(state_get "$sf" actions_unread)). One it refuses ends its run in startup_failure, with no job; \`/plinth:floor-check\`, run with a login that administers the repository, names each and the command that allows it."
  fi
}
# ── on GitLab (#1012) ───────────────────────────────────────────────────
# GitLab requires no check by name. What holds a merge request back is the
# project's "Pipelines must succeed" with skipped pipelines not counted, and
# the protected default branch, as /plinth:floor-check reads them on GitLab:
# a job the move stops leaves the pipeline, and one it starts is held to it
# from the move's own merge request. The record's lines for them, read from
# the project ($project_json) and its protected branches; nothing is changed.
gl_settings() {
  local gate rules
  gate="$(python3 -I -c '
import json, sys
try:
    p = json.loads(sys.argv[1])
except ValueError:
    print("unread the project could not be read"); sys.exit()
want = {"only_allow_merge_if_pipeline_succeeds": True, "allow_merge_on_skipped_pipeline": False}
absent = [k for k in want if k not in p]
off = [f"{k}={str(p[k]).lower()}" for k in want if k in p and p[k] != want[k]]
if off:
    print("off " + ", ".join(off))
elif absent:
    print("unread GitLab did not return " + ", ".join(absent) + " to this login (a project member reads them)")
else:
    print("on")' "${project_json:-}")"
  printf 'gl_gate=%s\n' "$gate"
  if rules="$(gl_api "projects/$gl_enc/protected_branches?per_page=100" --paginate 2>/dev/null)"; then
    # Every rule whose name or wildcard pattern matches the branch applies, as
    # floor-check.py matches them; how strong each is, it judges.
    python3 -I -c '
import json, re, sys
try:
    rules = json.loads(sys.argv[1])
except ValueError:
    print("gl_protect=unread an unexpected response"); sys.exit()
if not isinstance(rules, list):
    print("gl_protect=unread an unexpected response"); sys.exit()
names = [r["name"] for r in rules if isinstance(r, dict) and isinstance(r.get("name"), str)
         and re.fullmatch(".*".join(map(re.escape, r["name"].split("*"))), sys.argv[2])]
print("gl_protect=" + ("yes " + ", ".join(names) if names else "no"))' "$rules" "$default"
  else
    echo "gl_protect=unread protected branches are not readable with this login (it needs the Maintainer role), or an API error"
  fi
}
# What a person does on the project's settings for the move, from a record.
gl_move_steps() { # <state file>
  local sf="$1" repo default gh_ gate prot cmd
  repo="$(state_get "$sf" repo)"; default="$(state_get "$sf" default)"; gh_="$(state_get "$sf" gl_host)"
  local e; e="$(state_get "$sf" gl_enc)"
  gate="$(state_get "$sf" gl_gate)"; prot="$(state_get "$sf" gl_protect)"
  local jobs=""
  while IFS= read -r c; do [ -n "$c" ] && jobs="$jobs${jobs:+, }$c stops"; done < <(sed -n 's/^job_drop=//p' "$sf")
  while IFS= read -r c; do [ -n "$c" ] && jobs="$jobs${jobs:+, }$c starts"; done < <(sed -n 's/^job_add=//p' "$sf")
  jobs="${jobs:-no job starts or stops}"
  case "$gate" in
    on) echo "GitLab requires no check by name: $repo merges a merge request only on a green pipeline (\"Pipelines must succeed\" on, skipped pipelines not counted), and the move's jobs ($jobs) go with that pipeline: nothing to change in the project's settings for them." ;;
    off*) cmd="glab api --hostname $gh_ -X PUT projects/$e -F only_allow_merge_if_pipeline_succeeds=true -F allow_merge_on_skipped_pipeline=false"
          echo "GitLab requires no check by name: what holds a merge request back is \"Pipelines must succeed\", and on $repo it is not set as the door sets it (${gate#off }), so no job, the move's ($jobs) or any other, holds a merge back. Before the move's merge request merges, a Maintainer runs, with their own login (never the agent's): $cmd" ;;
    *) echo "GitLab requires no check by name; whether \"Pipelines must succeed\" is on was not read (${gate#unread }), and it is what holds the move's jobs ($jobs) to the pipeline. \`/plinth:floor-check\`, run with a login that reads the project's settings, names it and the command a Maintainer runs." ;;
  esac
  case "$prot" in
    yes*) echo "$default is protected on $repo (rules that apply: ${prot#yes }); the move changes no rule. \`/plinth:floor-check\` judges how strong they are." ;;
    no) echo "$default is not a protected branch on $repo: anyone with Developer can push to it. A Maintainer runs, with their own login (never the agent's): glab api --hostname $gh_ -X POST projects/$e/protected_branches -f name=$default -F push_access_level=0 -F merge_access_level=40 -F allow_force_push=false" ;;
    *) echo "whether $default is protected was not read (${prot#unread }); \`/plinth:floor-check\` reads it with a Maintainer's login." ;;
  esac
}
# The record's job_drop=/job_add= lines: the jobs of .gitlab-ci.yml at
# HEAD that <dir> no longer has, and the ones it gained.
gl_job_lines() { # <dir>
  local was now
  was="$(git -C "$1" show HEAD:.gitlab-ci.yml 2>/dev/null | gl_jobs_of | sort -u)"
  now="$( { [ -f "$1/.gitlab-ci.yml" ] && gl_jobs_of < "$1/.gitlab-ci.yml"; } | sort -u)"
  comm -23 <(printf '%s\n' "$was" | sed '/^$/d') <(printf '%s\n' "$now" | sed '/^$/d') | sed 's/^/job_drop=/'
  comm -13 <(printf '%s\n' "$was" | sed '/^$/d') <(printf '%s\n' "$now" | sed '/^$/d') | sed 's/^/job_add=/'
}
# The jobs of a .gitlab-ci.yml: its top-level keys, but GitLab's own
# keywords and hidden (`.`) jobs, one per line.
gl_jobs_of() { awk '/^[A-Za-z0-9_][A-Za-z0-9_ -]*:/ { k = $0; sub(/:.*/, "", k)
  if (k !~ /^(default|include|stages|variables|workflow|image|services|cache|before_script|after_script|spec)$/) print k }'; }
# The record's lines for the Actions allowlist against the workflows in <dir>
# (the rehearsal of the move): what floor-check.py --print-refused-actions
# says, or that it was not read.
actions_of() { # <dir>
  local said why rc=0
  why="$(mktemp)"
  said="$(python3 "$checker" --root "$1" --repo "$repo" --print-refused-actions 2>"$why")" || rc=$?
  if [ "$rc" != 0 ]; then printf 'actions_unread=%s\n' "$(head -n 1 "$why")"; rm -f "$why"; return 0; fi
  rm -f "$why"
  sed -n 's/^refused: /action_refused=/p; s/^allow: /action_allow=/p; s/^skip: /action_skip=/p; s/^allowed: /actions_allowed=/p' <<<"$said"
}
# This repository's side of each conflict copier left, which may hold code of
# its own: the measured hand-deleted case conflicts where a file both
# archetypes ship was changed (pyproject.toml, __main__.py, uv.lock).
ours_of() { # <worktree> <path>
  case "$2" in
    *.rej) return ;;
    uv.lock | */uv.lock) echo "$2: generated; after pyproject.toml is resolved, uv lock in the worktree makes it again"; return ;;
  esac
  echo "This repository's side of $2 (read it for code of its own before taking the template's):"
  awk '/^<<<<<<< before updating$/ { s = 1; next } /^=======$/ && s { s = 0; print "----"; next } s' "$1/$2" | sed 's/^/    /'
}
# release.yml in a move (#1044): the template renders it whole for each
# archetype, and between one that publishes to PyPI and one that publishes an
# image, either half of a split inside it is 442 lines or more. ci /
# diff-size from a plinth with the rule leaves it out of the count when
# .copier-answers.yml changes archetype: and keeps _commit:, and this script
# counts as the plinth the workflows call does.
rel_wf=".github/workflows/release.yml"
# A one-word value of .copier-answers.yml at <rev> (empty: the index), read as
# ci / diff-size reads it; nothing when absent.
answer_at() { # <worktree> <rev> <key>
  { git -C "$1" show "$2:.copier-answers.yml" 2>/dev/null || true; } \
    | sed -nE "s/^$3:[[:space:]]*['\"]?([A-Za-z0-9._-]+)['\"]?[[:space:]]*(#.*)?$/\1/p" | head -n 1
}
# "<lines> <max>" when the rehearsed move changes release.yml by more than
# the moved ci job's max-diff-lines, counted with its diff-size-exclude (a
# project that excludes the file already has nothing over: Codex review on
# #1052), the count reading the whole repository; nothing otherwise, or when
# those inputs are not read.
release_over() { # <rehearsal: copier's changes uncommitted on HEAD>
  local cfg max droot exclude n pats=() p spec=("$rel_wf")
  cfg="$(python3 "$checker" --root "$1" --print-diff-size 2>/dev/null)" || return 0
  max="$(sed -n 's/^max=//p' <<<"$cfg")"; droot="$(sed -n 's/^root=//p' <<<"$cfg")"; droot="${droot%/}"
  exclude="$(sed -n 's/^exclude=//p' <<<"$cfg")"
  { [ -z "$droot" ] || [ "$droot" = . ]; } && [ "$max" -gt 0 ] || return 0
  [ -z "$exclude" ] || read -r -a pats <<<"$exclude"
  for p in ${pats+"${pats[@]}"}; do spec+=(":(exclude)$p"); done
  if git -C "$1" cat-file -e "HEAD:$rel_wf" 2>/dev/null; then
    n="$(git -C "$1" diff --numstat HEAD -- "${spec[@]}" | awk '$1 != "-" { s += $1 + $2 } END { print s + 0 }')"
  elif [ -n "$(git -C "$1" ls-files --others -- "${spec[@]}")" ]; then n="$(wc -l < "$1/$rel_wf" | tr -d ' ')"
  else n=0; fi
  [ "$n" -le "$max" ] || echo "$n $max"
}
# What the plan says of it: <size_move record> <lines> <max>. Exit 1 when the
# plinth the workflows call counts it, so the move waits for a pin raise.
release_says() {
  local sm="$1" pin; pin="$(cut -d ' ' -f 2 <<<"$sm")"
  local head="$rel_wf changes $2 lines, over ci / diff-size's limit of $3 by itself, and a split by file cannot cut one file"
  case "${sm%% *}" in
    held) echo "$head. The plinth the workflows call (${pin:0:12}) leaves it out of the count in the pull request that changes archetype: (#1044), and --finish counts the same way, so the rest splits by file." ;;
    fails) echo "$head. The plinth the workflows call (${pin:0:12}) counts it, so the move's last pull request would fail ci / diff-size however it is split. Raise the plinth pin first: merge a pull request that moves every coolbress/plinth uses: line to plinth v$(plinth_version) or later (Dependabot's, or one by hand), then plan the move again."
           return 1 ;;
    *) echo "$head. Whether the plinth the workflows call leaves it out of the count in the move's pull request was not read${sm:+ (${sm#* * })}. This plinth (v$(plinth_version)) does; with one from before it, the move's last pull request fails ci / diff-size, and the plinth pin is raised first." ;;
  esac
}
# The top-level jobs of a workflow file, one per line.
jobs_of() { awk '/^jobs:/ { j = 1; next } /^[^ #]/ { j = 0 } j && /^  [A-Za-z0-9_-]+:/ { sub(/^  /, ""); sub(/:.*/, ""); print }'; }
# The required checks on the default branch, one per line; exit 1 unread.
required_on() { # <repo> <default>
  gh api "repos/$1/rules/branches/$2" \
    --jq '.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context' 2>/dev/null
}

# ── finish: commit, push the branch, open the draft ─────────────────────
finish() { # <worktree>
  local wt="$1" sf repo default base from to cmd branch left pr
  sf="$(state_file "$wt" 2>/dev/null)" && [ -f "$sf" ] \
    || die "$wt is not a worktree this script made (no $state_name record in its git directory)"
  repo="$(state_get "$sf" repo)"; default="$(state_get "$sf" default)"; base="$(state_get "$sf" base)"
  from="$(state_get "$sf" from)"; to="$(state_get "$sf" to)"; cmd="$(state_get "$sf" command)"
  pr="$(state_get "$sf" pr)"
  gl_host="$(state_get "$sf" gl_host)"; local gl_enc gl_id; gl_enc="$(state_get "$sf" gl_enc)"; gl_id="$(state_get "$sf" gl_id)"
  local chosen pin_note; chosen="$(state_get "$sf" pin)"; pin_note="$(state_get "$sf" pin_note)"
  if [ -n "$pr" ]; then
    echo "The draft $noun is already open: $pr"
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
    [ "$committed" = yes ] || die "nothing changed in $wt; no commit, no $noun"
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
  if [ "$host" = gitlab ]; then
    # The GitLab pipeline's diff-size job takes its inputs from the include's
    # `inputs:` in .gitlab-ci.yml, which the checker does not read (#1012).
    size_line="\`diff-size\` was not counted here before pushing: on GitLab the include's inputs are not read here, so no split is proposed; the pipeline's own diff-size job counts it."
  elif cfg="$(python3 "$checker" --root "$wt" --print-diff-size 2>&1)"; then
    max="$(sed -n 's/^max=//p' <<<"$cfg")"; exclude="$(sed -n 's/^exclude=//p' <<<"$cfg")"; droot="$(sed -n 's/^root=//p' <<<"$cfg")"
    local prefix="" spec=(".") pats=() p
    droot="${droot%/}"
    if [ -n "$droot" ] && [ "$droot" != . ]; then prefix="$droot/"; spec=("$droot"); fi
    [ -z "$exclude" ] || read -r -a pats <<<"$exclude"
    for p in ${pats+"${pats[@]}"}; do spec+=(":(exclude)$prefix$p"); done
    # release.yml in a move (#1044), left out as ci / diff-size at the
    # plinth the workflows call leaves it out: that plinth has the rule, the
    # count reads the whole repository, and .copier-answers.yml changes
    # archetype: and keeps _commit: against the merge base, so in the part
    # that carries the answers file, which a split keeps for the last.
    local rel_n="" at=""; [ "$committed" = yes ] && at=HEAD   # "" reads the index
    local a_was a_now c_was c_now
    a_was="$(answer_at "$wt" "$mb" archetype)"; a_now="$(answer_at "$wt" "$at" archetype)"
    c_was="$(answer_at "$wt" "$mb" _commit)"; c_now="$(answer_at "$wt" "$at" _commit)"
    if [ -z "$prefix" ] && [ "$(state_get "$sf" size_move | cut -d ' ' -f 1)" = held ] \
       && [ -n "$a_was" ] && [ -n "$a_now" ] && [ "$a_was" != "$a_now" ] && [ -n "$c_was" ] && [ "$c_was" = "$c_now" ]; then
      rel_n="$(git -C "$wt" diff --numstat "${tree[@]}" -- "$rel_wf" "${spec[@]:1}" | awk '$1 != "-" { s += $1 + $2 } END { print s + 0 }')"
      if [ "${rel_n:-0}" -gt 0 ]; then spec+=(":(exclude)$rel_wf"); else rel_n=""; fi
    fi
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
    if [ -n "$rel_n" ]; then
      size_line="$size_line \`$rel_wf\` ($rel_n lines) is not in that count: an archetype move, which \`ci / diff-size\` at the plinth the workflows call leaves out of it, and lists the \`archetype:\` change under changes to the checks (#1044)."
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
  local new old; new="$(state_get "$sf" archetype)"; old="$(state_get "$sf" old_archetype)"
  [ -z "$new" ] || title="chore(template): move from the $old archetype to $new"
  local msg body; msg="$(mktemp)"; body="$(mktemp)"
  list() { if [ -n "$1" ]; then printf '%s\n' "$1" | sed '/^$/d; s/^/- /'; else echo "- none"; fi; }
  {
    echo "## What and why"
    echo
    if [ -n "$new" ]; then
      echo "Re-renders this repository under the \`$new\` archetype instead of \`$old\`, at plinth-template"
      echo "$to, the tag it already records, by running the command the checker gives for the move"
      echo "(\`/plinth:template-update --archetype $new\`). copier deletes the files of the old archetype that the"
      echo "new one does not render, and keeps the files that are this repository's own;"
      # Said only as compared: a move applied by a plinth before #1016 left
      # no record of a comparison, and its description must not claim one.
      if grep -qE '^(keep|drop)=' "$sf"; then
        echo "and an old archetype file this repository changed, it deletes only as the person chose (below);"
      elif grep -qx 'compared=yes' "$sf"; then
        echo "none of the files it deletes had been changed by this repository (each was compared with the old archetype's render at $to);"
      else
        echo "whether this repository had changed any of the files it deletes was not compared (the move was applied by a plinth before #1016);"
      fi
      echo "\`.copier-answers.yml\` records the new one:"
    elif [ "$from" = "$to" ]; then
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
    if [ -n "$new" ]; then
      local names; names="$(git -C "$wt" -c core.quotePath=false diff --name-status --no-renames "${tree[@]}")"
      echo
      echo "Deleted by the move:"
      echo
      list "$(awk -F '\t' '$1 == "D" { print $2 }' <<<"$names")"
      if grep -qE '^(keep|drop)=' "$sf"; then
        echo
        echo "Changed by this repository, and the move would delete them; each as the person chose:"
        echo
        sed -n 's/^keep=\(.*\)/- \1: kept (`--keep`), restored after copier as this repository'"'"'s own file/p
                s/^drop=\(.*\)/- \1: deleted (`--drop`), on the person'"'"'s word/p' "$sf"
      fi
      echo
      echo "Added by the move:"
      echo
      list "$(awk -F '\t' '$1 == "A" { print $2 }' <<<"$names")"
      echo
      if [ "$host" = gitlab ]; then
        echo "By hand, by a person, on the project's settings (GitLab requires no check by name):"
        echo
        gl_move_steps "$sf" | sed 's/^/- /'
      else
        echo "By hand, by a person (each command is run from plinth's folder):"
        echo
        move_steps "$sf" "scripts/" | sed 's/^/- /'
      fi
      echo "- Nothing else: no label changes with the archetype, and \`/plinth:floor-check\` reads the new archetype from \`.copier-answers.yml\`."
    fi
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
    # The fields of the form plinth-template renders, in its order (#856):
    # each says only what is true as this opens, and a script is not a person.
    echo "## What I checked myself"
    echo
    echo "Not a person's check: this is only what \`/plinth:template-update\`'s script"
    echo "checked as it opened the $noun."
    echo
    echo "- Opened as a draft once no conflict was left: no unmerged path, and no \`.rej\` file or conflict marker in a file the update changed (files unchanged since $(printf '%.12s' "$base") were not read)."
    echo "- $size_line"
    if [ -n "$pin_note" ]; then echo "- The plan's plinth pin line: ${pin_note#plinth pin: }"
    else echo "- The plan's plinth pin line: the plan printed none."; fi
    echo
    echo "## How it was verified"
    echo
    echo "This script resolved no conflict; how each was resolved is what \`--resolved\`"
    echo "stated, which the script does not check, and \"not stated\" where nothing was."
    echo "copier's questions were answered with \`--defaults\`: each takes this"
    echo "repository's recorded answer, and a question it never answered takes the"
    echo "template's default (\`.copier-answers.yml\` in the diff shows any)."
    [ -z "$new" ] || echo "The one answer given is \`archetype\`, as \`--data archetype=$new\`."
    # The template's own line, in the words its CONTRIBUTING.md step 5 gives
    # (#1020): what was not checked is said once, here.
    echo
    echo "Not verified: that this repository still works after the update, which is what its own checks are for; they had not run when this $noun opened, and the script waits for none of them."
    echo
    echo "Review: none (no review had run when this $noun opened)"
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
  # The --finish line a stop below prints carries what this run was given
  # that the record does not keep (#925): --over-limit, without which the
  # run stops at the split again, and --assisted-by, the description's last
  # line. --resolved is kept in the record above.
  local again; again="$(q "$0") --finish $(q "$wt")"
  [ "$over_limit" = no ] || again="$again --over-limit"
  [ -z "$assisted" ] || again="$again --assisted-by $(q "$assisted")"
  # The one push this script makes, to the update branch by name. The
  # default branch is refused above and never named here. A branch already
  # on origin at this commit is a person's push after a refusal (#925): it
  # is not pushed again. A probe that fails is not that; the push runs.
  local remote_at; remote_at="$(git -C "$wt" ls-remote origin "refs/heads/$branch" 2>/dev/null | cut -f1)" || remote_at=""
  if [ -n "$remote_at" ] && [ "$remote_at" = "$(git -C "$wt" rev-parse HEAD)" ]; then
    echo "$branch is already on origin at this commit; not pushed again."
  else
    local push_err; push_err="$(mktemp)"
    if ! git -C "$wt" push -q origin "HEAD:refs/heads/$branch" 2>"$push_err"; then
      cat "$push_err" >&2
      rm -f "$body"
      # GitHub refuses a change under .github/workflows/ from a credential
      # without the `workflow` scope (classic token, OAuth app) or the
      # `workflows` permission (fine-grained token, GitHub App); a template
      # update usually carries one. Run again here, it is refused the same
      # way: the push is a person's (docs/how-to/give-the-agent-a-token.md).
      if grep -q "refusing to allow .* to create or update workflow" "$push_err"; then
        rm -f "$push_err"
        {
          echo "template-update: origin refused $branch because it changes .github/workflows/ and the credential here may not (GitHub's reason is above)."
          echo "Running --finish again here is refused the same way: this push is a person's, not a retry."
          echo "The commit is ready in $wt, on $branch; no pull request is opened yet."
          echo "From a separate terminal, with a credential that has the workflow permission, push it:"
          echo "  git -C $(q "$wt") push origin HEAD:refs/heads/$(q "$branch")"
          echo "Then run this once more; it finds the pushed branch and opens the draft pull request without pushing again:"
          echo "  $again"
        } >&2
        exit 5
      fi
      rm -f "$push_err"
      die "pushing $branch failed; the commit is in $wt, no $noun opened. Run again: $again"
    fi
    rm -f "$push_err"
  fi
  local pushed; pushed="$(git -C "$wt" rev-parse HEAD)"
  if [ "$host" = gitlab ]; then
    # GitLab (#1012): the same adoption, by the API's own fields: an open
    # merge request from this branch into the default one, from this project
    # (source_project_id, not a fork's) at the commit just pushed. A draft is
    # a title that starts with "Draft:".
    pr="$(gl_api "projects/$gl_enc/merge_requests?state=opened&source_branch=$(enc "$branch")&target_branch=$(enc "$default")" 2>/dev/null \
      | python3 -I -c '
import json, sys
try:
    rows = json.load(sys.stdin)
except ValueError:
    sys.exit()
for m in rows if isinstance(rows, list) else []:
    if isinstance(m, dict) and str(m.get("source_project_id")) == sys.argv[1] and m.get("sha") == sys.argv[2] and m.get("web_url"):
        print(m["web_url"]); break' "$gl_id" "$pushed")" || pr=""
    if [ -z "$pr" ]; then
      local input; input="$(mktemp)"
      python3 -I -c '
import json, sys
src, dst, title, body = sys.argv[1:5]
json.dump({"source_branch": src, "target_branch": dst, "title": "Draft: " + title,
           "description": open(body, encoding="utf-8").read()}, sys.stdout)' "$branch" "$default" "$title" "$body" > "$input"
      pr="$(gl_api -X POST "projects/$gl_enc/merge_requests" -H "Content-Type: application/json" --input "$input" 2>/dev/null | json_get web_url)" || pr=""
      rm -f "$input"
      [ -n "$pr" ] || { rm -f "$body"; die "$branch is pushed, but opening the merge request failed (glab api projects/$gl_enc/merge_requests). Run again: $again"; }
    fi
  else
  # A pull request GitHub created although gh reported a failure (the reply
  # lost on the way back) is this one: adopt it rather than fail on the
  # duplicate every time (Codex review on #273). `--head` matches the branch
  # name only, so a fork's pull request from a branch of the same name
  # answers too: adopt only one whose head is this repository at the commit
  # just pushed (#274).
  local own
  own="$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')"
  pr="$(gh pr list --repo "$repo" --head "$branch" --base "$default" --state open \
    --json url,headRepositoryOwner,headRepository,headRefOid \
    --jq "[.[] | select((.headRepositoryOwner.login + \"/\" + .headRepository.name | ascii_downcase) == \"$own\" and .headRefOid == \"$pushed\")][0].url // empty" \
    2>/dev/null)" || pr=""
  [ -n "$pr" ] || pr="$(gh pr create --repo "$repo" --draft --base "$default" --head "$branch" --title "$title" --body-file "$body")" \
    || { rm -f "$body"; die "$branch is pushed, but opening the pull request failed (above). Run again: $again"; }
  fi
  rm -f "$body"
  printf 'pr=%s\n' "$pr" >> "$sf"
  if [ "$host" = gitlab ]; then
    echo "Draft merge request: $pr"
    echo "Its pipeline starts now; nothing here waited for it. The worktree stays at $wt."
  else
    echo "Draft pull request: $pr"
    echo "Its checks start now; nothing here waited for them. The worktree stays at $wt."
  fi
  exit 0
}

[ "$mode" = finish ] && { [ -d "$wt_arg" ] || die "no such worktree: $wt_arg"; finish "$(cd "$wt_arg" && pwd)"; }

# ── plan and apply: a verified base ─────────────────────────────────────
top="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
if [ "$host" = gitlab ]; then
  # The project as GitLab names it, with its id: a merge request adopted on
  # a rerun is one from this project, not a fork's.
  gl_enc="$(enc "$gl_path")"
  project_json="$(gl_api "projects/$gl_enc" 2>/dev/null)" || project_json=""
  repo="$(json_get path_with_namespace <<<"$project_json")" || repo=""
  default="$(json_get default_branch <<<"$project_json")" || default=""
  gl_id="$(json_get id <<<"$project_json")" || gl_id=""
  [ -n "$repo" ] && [ -n "$default" ] && [ -n "$gl_id" ] \
    || die "glab cannot name the GitLab project $gl_host/$gl_path or its default branch (glab api projects/$gl_enc; glab auth login --hostname $gl_host)"
else
  read -r repo default < <(gh repo view --json nameWithOwner,defaultBranchRef \
    --jq '.nameWithOwner + " " + .defaultBranchRef.name' 2>/dev/null) || true
  [ -n "${repo:-}" ] && [ -n "${default:-}" ] || die "gh cannot name this repository or its default branch (gh repo view)"
fi
git -C "$top" fetch -q origin "+refs/heads/$default:refs/remotes/origin/$default" \
  || die "git fetch origin $default failed"
base="$(git -C "$top" rev-parse -q --verify "refs/remotes/origin/$default^{commit}")" || die "no origin/$default after fetch"
if [ "$host" = gitlab ]; then
  remote="$(gl_api "projects/$gl_enc/repository/branches/$(enc "$default")" 2>/dev/null | json_get commit.id)" || remote=""
else
  remote="$(gh api "repos/$repo/branches/$default" --jq .commit.sha 2>/dev/null)" || remote=""
fi
[ "$base" = "$remote" ] \
  || die "origin/$default is not verified: it is ${base:0:12}, $hostname's $repo $default is ${remote:-unreadable}"
# The checker reads the host from the answers file; said here as well, for
# a GitLab told by origin's URL alone.
host_arg=(); [ "$host" = gitlab ] && host_arg=(--host gitlab)

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
old_arch="$(git -C "$top" show "$base:.copier-answers.yml" 2>/dev/null | sed -nE "s/^archetype: *['\"]?([^'\" ]*).*/\1/p")"
if [ -n "$move" ]; then wt="$(dirname "$top")/$(basename "$top")-archetype-$move"; branch="chore/archetype-$move"; fi

# The command, from the checker, on exactly the files it reads at the base:
# the answers file, the workflows and the repository's own issue and
# pull-request templates (#726). With `tested`, the line with the tested
# pin, the comparison on stderr whether or not there is one. `--repo` names
# whose `.github` the checker reads for the two answers the update carries,
# as the door's render did; a read that fails gives no line (#726).
cmd_at() { # <dir> [live|tested]
  python3 "$checker" --root "$1" --repo "$repo" ${host_arg+"${host_arg[@]}"} --print-update-command --plinth-pin "${2:-live}"
}
move_at() { # <dir>: the move's line; check-drop:/check-add:/moves: on stderr
  python3 "$checker" --root "$1" --repo "$repo" ${host_arg+"${host_arg[@]}"} --print-update-command --move-archetype "$move"
}
at_base() { # sets $tmp: the files the checker reads, as they are at the base
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  paths=()
  # .gitlab-ci.yml: on GitLab the pin and its checksum are its include's (#1012).
  for p in .copier-answers.yml .github/workflows .github/ISSUE_TEMPLATE .gitlab-ci.yml \
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
  says="$(python3 "$checker" --root "$tmp" ${host_arg+"${host_arg[@]}"} --print-plugin-skew)" || rc=$?
  case "$rc" in
    0) ;;
    3) printf '%s\n' "$says"
       echo "Nothing has been written (the fetch moved only origin/$default)."
       exit 1 ;;
    *) echo "the installed plinth was not compared with the latest release (the check exited $rc); going on with the template tag this plinth targets, $to" >&2 ;;
  esac
}
# The rehearsal of the move <cmd> (in $tmp, after at_base): a clone of the
# base outside this repository, checked out as --apply's worktree is (`git
# archive` would leave out an export-ignore path), where copier runs as
# --apply would run it. Nothing of it is kept; the clone borrows this
# repository's objects and writes none into it. Sets $r, $conflicts,
# $deleted and $owned: the deleted files whose content at the base is not
# the old archetype's render (#1016).
rehearse() { # <cmd>
  local words prefix ref p
  read -ra words <<<"$1"
  r="$tmp/rehearsal"
  { git clone -q --shared --no-checkout "$top" "$r" && git -C "$r" checkout -q --detach "$base"; } \
    || die "could not make the rehearsal clone of origin/$default; nothing was written"
  ( cd "$r" && env -u GH_TOKEN -u GITHUB_TOKEN "${words[@]}" < /dev/null ) > "$tmp/rehearsal.log" 2>&1 || {
    tail -n 1 "$tmp/rehearsal.log" >&2
    die "copier refused the move in the rehearsal (its last line above); nothing was written"
  }
  conflicts="$(conflicts_in "$r" HEAD)"
  deleted="$(git -C "$r" -c core.quotePath=false ls-files --deleted | sort -u)"
  owned=""
  [ -n "$deleted" ] || return 0
  # The old archetype's render: copier's own, of the answers recorded at the
  # base, at the tag they record (a move runs only at the target tag, the
  # one the line fetches), into a folder holding nothing else. The same
  # copier as the line; `recopy` renders without merging, so the folder is
  # exactly what the template gave this repository (measured, 9.18.2).
  prefix="${1%% copier update *}"; ref="$(sed -nE 's/.* --vcs-ref ([^ ]+).*/\1/p' <<<"$1")"
  [ "$prefix" != "$1" ] && [ -n "$ref" ] || die "the move's line is not the copier update this script reads: $1"
  read -ra words <<<"$prefix"
  mkdir "$tmp/old-render" && git -C "$r" show HEAD:.copier-answers.yml > "$tmp/old-render/.copier-answers.yml" \
    || die "could not read .copier-answers.yml at the base; nothing was written"
  ( cd "$tmp/old-render" && env -u GH_TOKEN -u GITHUB_TOKEN "${words[@]}" copier recopy --defaults --overwrite --quiet \
      --vcs-ref "$ref" . < /dev/null ) > "$tmp/old-render.log" 2>&1 || {
    tail -n 1 "$tmp/old-render.log" >&2
    die "copier could not make the old archetype's render to compare the deleted files with (its last line above); nothing was written"
  }
  # A path the render does not hold, or holds otherwise, is this
  # repository's change: listed, never deleted unasked.
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ -L "$tmp/old-render/$p" ]; then
      [ "$(readlink "$tmp/old-render/$p")" = "$(git -C "$r" show "HEAD:$p")" ] && continue
    elif [ -f "$tmp/old-render/$p" ]; then
      git -C "$r" show "HEAD:$p" | cmp -s - "$tmp/old-render/$p" && continue
    fi
    owned="$owned$p"$'\n'
  done <<<"$deleted"
}
if [ "$mode" = plan ] && [ -n "$move" ]; then
  at_base
  plugin_gate
  cmd="$(move_at "$tmp" 2>"$tmp/move-note")" || { cat "$tmp/move-note" >&2; exit 1; }
  grep -vE '^(moves|check-drop|check-add|check-add-floor|diff-size-move): ' "$tmp/move-note" >&2
  rehearse "$cmd"
  added="$(git -C "$r" -c core.quotePath=false ls-files --others --exclude-standard | sort -u)"
  changed="$(git -C "$r" -c core.quotePath=false diff --name-only HEAD | sort -u | grep -vxF -f <(printf '%s\n%s\n' "$deleted" "$conflicts" | sed '/^$/d') || true)"
  stops=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    gone="$(comm -23 <(git -C "$r" show "HEAD:$f" | jobs_of | sort) <( { [ -f "$r/$f" ] && jobs_of < "$r/$f"; } | sort))"
    while IFS= read -r j; do [ -n "$j" ] && stops="$stops$f: $j"$'\n'; done <<<"$gone"
  done < <(git -C "$r" -c core.quotePath=false ls-tree -r --name-only HEAD -- .github/workflows)
  listed() { if [ -n "$1" ]; then printf '%s\n' "$1" | sed '/^$/d' | indent; else echo "  none"; fi; }
  echo "Repository: $repo, base origin/$default at $base (verified against $hostname)"
  echo "Archetype:  $old_arch -> $move, at $to (the tag it records)"
  echo "Worktree:   $wt (branch $branch)"
  echo "Command:    $cmd"
  echo "            (--defaults: each other question takes the recorded answer)"
  sed -n 's/^moves: /Moves:      /p' "$tmp/move-note"
  echo
  echo "Rehearsed on a copy of origin/$default outside this repository; nothing of it is kept."
  echo "Deletes:"; listed "$(grep -vxF -f <(printf '%s\n' "$owned" | sed '/^$/d') <<<"$deleted" || true)"
  if [ -n "$owned" ]; then
    echo "Changed by this repository, and the move deletes them (copier reports no conflict for these):"
    listed "$owned"
  fi
  echo "Adds:"; listed "$added"
  echo "Changes:"; listed "$changed"
  if [ -n "$conflicts" ]; then
    echo "Conflicts (a file both archetypes ship that this repository changed; each is shown and resolved on the person's word after --apply):"
    listed "$conflicts"
  else
    echo "Conflicts:  none"
  fi
  if [ "$host" = gitlab ]; then
    # GitLab's pipeline is .gitlab-ci.yml, its jobs the top-level keys (#1012).
    { printf 'repo=%s\ndefault=%s\ngl_host=%s\ngl_enc=%s\n' "$repo" "$default" "$gl_host" "$gl_enc"
      gl_job_lines "$r"; gl_settings; } > "$tmp/checks"
    echo "CI jobs that stop:"; listed "$(sed -n 's/^job_drop=/.gitlab-ci.yml: /p' "$tmp/checks")"
    echo "CI jobs that start:"; listed "$(sed -n 's/^job_add=/.gitlab-ci.yml: /p' "$tmp/checks")"
    gl_move_steps "$tmp/checks" | sed 's/`//g'
    echo
    echo "Nothing has been written (the fetch moved only origin/$default). To apply it, on the user's word:"
    echo "  $(q "$0") --apply $base --archetype $move"
    if [ -n "$owned" ]; then
      echo "  with each changed file above named once, as the person chooses: --keep <path> restores it after"
      echo "  copier, as this repository's own file; --drop <path> lets the move delete it. Without, --apply stops."
    fi
    exit 0
  fi
  echo "CI jobs that stop:"; listed "$stops"
  # The checks, as move_steps words them for the record --apply writes.
  { printf 'repo=%s\ndefault=%s\n' "$repo" "$default"
    sed -n 's/^check-drop: /check_drop=/p; s/^check-add: /check_add=/p; s/^check-add-floor: /add_floor=/p; s/^diff-size-move: /size_move=/p' "$tmp/move-note"
    if req="$(required_on "$repo" "$default")"; then
      echo "required_read=yes"; while IFS= read -r c; do [ -n "$c" ] && printf 'required=%s\n' "$c"; done <<<"$req"
    fi
    actions_of "$r"; } > "$tmp/checks"
  # Each admin command in a file of its own, outside the repository, under a
  # short path: the line naming it stays under 120 characters (#1045). The
  # tests set TEMPLATE_UPDATE_ADMIN_TMP to a folder of their own.
  admin_dir="$(mktemp -d "${TEMPLATE_UPDATE_ADMIN_TMP:-/tmp}/plinth-admin.XXXXXX" 2>/dev/null || mktemp -d)" \
    || die "could not make a folder for the admin commands"
  move_steps "$tmp/checks" "$(q "$here")/" "$admin_dir" | sed 's/`//g'
  rmdir "$admin_dir" 2>/dev/null && admin_dir=""
  size_wait=no; over="$(release_over "$r")"
  # shellcheck disable=SC2086 # "<lines> <max>", two words
  [ -z "$over" ] || release_says "$(state_get "$tmp/checks" size_move)" $over || size_wait=yes
  wrote="Nothing has been written (the fetch moved only origin/$default)."
  [ -z "$admin_dir" ] || wrote="Nothing has been written in the repository (the fetch moved only origin/$default; the admin commands above are files in $admin_dir)."
  echo
  if grep -q '^add_floor=fails ' "$tmp/checks" && [ -n "$(unrequired_adds "$tmp/checks")" ]; then
    echo "$wrote Raise the plinth pin first (above);"
    echo "--apply refuses this move until the workflows call a plinth that passes its ci / floor-check."
    exit 0
  fi
  if [ "$size_wait" = yes ]; then
    echo "$wrote Raise the plinth pin first (above);"
    echo "--apply refuses this move until the workflows call a plinth whose ci / diff-size leaves $rel_wf out of the move's count."
    exit 0
  fi
  echo "$wrote To apply it, on the user's word:"
  echo "  $(q "$0") --apply $base --archetype $move"
  if [ -n "$owned" ]; then
    echo "  with each changed file above named once, as the person chooses: --keep <path> restores it after"
    echo "  copier, as this repository's own file; --drop <path> lets the move delete it. Without, --apply stops."
  fi
  exit 0
fi
if [ "$mode" = plan ]; then
  at_base
  plugin_gate
  # Its stderr as before, but for the `moves:` lines (#793), which the plan
  # prints under the command.
  cmd="$(cmd_at "$tmp" 2>"$tmp/live-note")" || { cat "$tmp/live-note" >&2; exit 1; }
  grep -v '^moves: ' "$tmp/live-note" >&2
  tested_cmd="$(cmd_at "$tmp" tested 2>"$tmp/pin-note")" || tested_cmd=""
  [ "$tested_cmd" != "$cmd" ] || tested_cmd=""
  echo "Repository: $repo, base origin/$default at $base (verified against $hostname)"
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
  # A pin raised in the workflows (by Dependabot or by hand) and not in the
  # answers file (#1015): copier's old render names the recorded plinth_sha,
  # so a workflow whose plinth pin is neither that one nor the one a line
  # carries meets three pins, and its plinth uses: line is left in conflict
  # (measured, copier 9.18.2). Said here, for each line on offer, before
  # anything is written; the person still resolves it after --apply. Files
  # copier does not render (a workflow the project added) have nothing to
  # conflict with, which the line says; a `Moves:` file at an older pin
  # conflicts too, since copier runs on it as it stands.
  recorded="$(tr -d '\r' < "$tmp/.copier-answers.yml" 2>/dev/null \
    | sed -nE "s/^plinth_sha:[[:space:]]*['\"]?([0-9a-fA-F]{40})['\"]?([[:space:]#].*)?$/\1/p" | head -n 1 | tr 'A-F' 'a-f')"
  carried() { sed -nE 's/.* --data plinth_sha=([0-9a-fA-F]{40})( .*)?$/\1/p' <<<"$1" | tr 'A-F' 'a-f'; }
  live_pin="$(carried "$cmd")"; tested_pin="$(carried "${tested_cmd:-}")"
  pins_now="$( [ -z "$recorded" ] || python3 "$checker" --root "$tmp" --print-plinth-pins | awk '$2 !~ /^unread$/ { print $1, tolower($2) }')"
  called="$(awk '!s[$2]++ { printf "%s%s", (n++ ? " and " : ""), $2 }' <<<"$pins_now")"
  # A trailing comment (`# v2.41.0`, as Dependabot writes it, #1045) is a
  # change to the line as well: the template renders none. Once the line
  # carries another pin than the recorded one, copier's merge meets two
  # changed sides there too and leaves it in conflict, even where both sides
  # name the same pin (seen on a project's live run, copier 9.18.2).
  commented="$( [ -z "$recorded" ] || python3 "$checker" --root "$tmp" --print-plinth-comments | awk '{ print $1, tolower($2) }')"
  in_conflict() { # <carried pin>: the files whose line names neither pin, or the recorded one with a comment
    awk -v r="$recorded" -v c="$1" 'NR == FNR { if (c != r && $2 == r) k[$1] = 1; next }
      ($2 != r && $2 != c || k[$1]) && !s[$1]++ { printf "%s%s", (n++ ? ", " : ""), $1 }' \
      <(printf '%s\n' "$commented") <(printf '%s\n' "$pins_now")
  }
  only_comment() { # <carried pin>: the files whose line names it, with a comment the render does not carry
    [ "$1" != "$recorded" ] || return 0
    awk -v c="$1" '$2 == c && !s[$1]++ { printf "%s%s", (n++ ? ", " : ""), $1 }' <<<"$commented"
  }
  pin_says() { # <what the line is> <carried pin>
    local files only; files="$(in_conflict "$2")"; only="$(only_comment "$2")"
    if [ "$2" = "$recorded" ]; then
      echo "            $1 carries the recorded pin itself: copier keeps the pin each workflow calls, so that line moves no pin."
      return
    fi
    if [ -n "$files" ]; then
      echo "            $1 leaves the plinth uses: line in conflict in $files (those of them the template renders);"
      echo "            keep the side naming $2, the pin that line carries (copier's \`after updating\` side)."
    fi
    if [ -n "$only" ]; then
      echo "            $1 leaves the plinth uses: line in conflict in $only (those of them the template renders),"
      echo "            though both sides name $2: they differ only by the trailing comment, which the template does not"
      echo "            render. Either side runs the same plinth; this repository's (\`before updating\`) keeps the comment."
    fi
    [ -n "$files$only" ] || echo "            $1 carries the pin the workflows call: no conflict on that line is expected."
  }
  offered_conflicts() { # whether a line on offer leaves a plinth uses: line in conflict
    local c
    for c in "$live_pin" ${tested_pin:+"$tested_pin"}; do
      [ -n "$(in_conflict "$c")$(only_comment "$c")" ] && return 0
    done
    return 1
  }
  if [ -n "$recorded" ] && [ -n "$live_pin" ] && { [ -n "$(in_conflict "$recorded")" ] || offered_conflicts; }; then
    echo "Pin conflict: .copier-answers.yml records plinth_sha $recorded; the workflows call $called."
    if [ -n "$tested_pin" ]; then
      pin_says "with --plinth-pin tested, the update" "$tested_pin"
      pin_says "with --plinth-pin live, the update" "$live_pin"
    else
      pin_says "The update" "$live_pin"
    fi
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
# A move the checker refuses stops before a worktree or branch exists.
if [ -n "$move" ]; then
  rehearsed="$(move_at "$tmp" 2>"$tmp/move-check")" || { cat "$tmp/move-check" >&2; die "nothing was created"; }
  # A move whose pull request its own ci / floor-check would fail (#1017).
  floor="$(sed -n 's/^check-add-floor: fails //p' "$tmp/move-check")"
  if [ -n "$floor" ]; then
    { sed -n 's/^check-add: /check_add=/p' "$tmp/move-check"
      if req="$(required_on "$repo" "$default")"; then
        echo "required_read=yes"; while IFS= read -r c; do [ -n "$c" ] && printf 'required=%s\n' "$c"; done <<<"$req"
      fi; } > "$tmp/adds"
    unreq="$(unrequired_adds "$tmp/adds" | paste -sd, -)"
  fi
  if [ -n "$floor" ] && [ -n "$unreq" ]; then
    die "the plinth the workflows call (${floor:0:12}) fails this move's ci / floor-check until $unreq is required, which cannot happen before the move merges; raise the plinth pin to v$(plinth_version) or later first, then plan the move again. Nothing was created"
  fi
  # The changed files the move deletes (#1016), from the rehearsal the plan
  # ran: each named once, with --keep or --drop, and nothing else named.
  rehearse "$rehearsed"
  # A release.yml over the limit by itself, which the plinth the workflows
  # call counts (#1044): its last pull request could not pass ci / diff-size.
  over="$(release_over "$r")"
  if [ -n "$over" ] && grep -q '^diff-size-move: fails ' "$tmp/move-check"; then
    die "$rel_wf changes ${over% *} lines, over ci / diff-size's limit of ${over#* } by itself, and the plinth the workflows call ($(sed -n 's/^diff-size-move: fails //p' "$tmp/move-check" | cut -c 1-12)) counts it in the move's pull request; raise the plinth pin to v$(plinth_version) or later first, then plan the move again. Nothing was created"
  fi
  # The allowlist against the moved workflows, for the description (#1018);
  # on GitLab, the jobs the move starts and stops and the merge gate (#1012).
  if [ "$host" = gitlab ]; then
    actions_rec="$(gl_job_lines "$r"; gl_settings)"
  else
    actions_rec="$(actions_of "$r")"
  fi
  keeps=""; drops=""; unnamed=""; refused=""
  for c in ${chosen_files+"${chosen_files[@]}"}; do
    f="${c#*$'\t'}"
    if ! grep -qxF -- "$f" <<<"$owned"; then refused="$refused  $f: not a file this repository changed that the move deletes"$'\n'
    elif grep -qxF -- "$f" <<<"$keeps$drops"; then refused="$refused  $f: named more than once"$'\n'
    elif [ "${c%%$'\t'*}" = keep ]; then keeps="$keeps$f"$'\n'
    else drops="$drops$f"$'\n'; fi
  done
  while IFS= read -r f; do
    [ -n "$f" ] && ! grep -qxF -- "$f" <<<"$keeps$drops" && unnamed="$unnamed  $f"$'\n'
  done <<<"$owned"
  if [ -n "$refused$unnamed" ]; then
    [ -z "$refused" ] || printf 'template-update: refused:\n%s' "$refused" >&2
    [ -z "$unnamed" ] || printf 'template-update: changed by this repository, and the move deletes them; copier reports no conflict for these:\n%s' "$unnamed" >&2
    die "name each changed file once, as the person chooses: --keep <path> restores it after copier, as this repository's own file; --drop <path> lets the move delete it. Nothing was created"
  fi
fi
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

if [ -n "$move" ]; then
  # The move's line, read at the base as the plan read it; the check lines go
  # to the record, for the description.
  move_note="$(mktemp)"
  cmd="$(move_at "$wt" 2>"$move_note")" \
    || { cat "$move_note" >&2; rm -f "$move_note"; die "no move command at the base (above); $wt left for inspection"; }
  grep -vE '^(moves|check-drop|check-add|check-add-floor|diff-size-move): ' "$move_note" >&2
  moves="$(sed -n 's/^moves: //p' "$move_note")"
  checks="$(sed -n 's/^check-drop: /check_drop=/p; s/^check-add: /check_add=/p; s/^check-add-floor: /add_floor=/p; s/^diff-size-move: /size_move=/p' "$move_note")"; rm -f "$move_note"
  if [ "$host" = github ] && req="$(required_on "$repo" "$default")"; then
    checks="$checks"$'\n'"required_read=yes"
    while IFS= read -r c; do [ -n "$c" ] && checks="$checks"$'\n'"required=$c"; done <<<"$req"
  fi
  case "$cmd" in *" --data archetype=$move") ;; *) die "the command does not move to $move: $cmd" ;; esac
  [ "$cmd" = "$rehearsed" ] || die "the move's line in the worktree is not the one rehearsed ($rehearsed); $wt left for inspection"
  pin_note=""
else
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

# The changed files the person chose to keep (#1016), as they are at the
# base. Each was rehearsed as deleted; one copier did not delete here is a
# run that differs from the rehearsal, and a stop.
if [ -n "$move" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    { [ ! -e "$wt/$f" ] && [ ! -L "$wt/$f" ]; } \
      || die "copier did not delete $f here, as the rehearsal did; nothing committed or pushed, $wt left as copier left it"
  done <<<"$keeps$drops"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    git -C "$wt" checkout -q "$base" -- "$f" || die "restoring $f failed in $wt; nothing committed or pushed"
  done <<<"$keeps"
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
  printf 'repo=%s\ndefault=%s\nbase=%s\nbranch=%s\nfrom=%s\nto=%s\ncommand=%s\npin=%s\npin_note=%s\nhost=%s\n' \
    "$repo" "$default" "$base" "$branch" "$from" "$to" "$cmd" "$pin" "$pin_note" "$host"
  [ "$host" = github ] || printf 'gl_host=%s\ngl_enc=%s\ngl_id=%s\n' "$gl_host" "$gl_enc" "$gl_id"
  if [ -n "$move" ]; then
    printf 'archetype=%s\nold_archetype=%s\ncompared=yes\n' "$move" "$old_arch"
    while IFS= read -r p; do [ -n "$p" ] && printf 'keep=%s\n' "$p"; done <<<"$keeps"
    while IFS= read -r p; do [ -n "$p" ] && printf 'drop=%s\n' "$p"; done <<<"$drops"
    printf '%s\n' "$checks" | sed '/^$/d'
    printf '%s\n' "$actions_rec" | sed '/^$/d'
  fi
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
  if [ -n "$move" ]; then
    echo
    while IFS= read -r p; do [ -n "$p" ] && ours_of "$wt" "$p"; done <<<"$conflicts"
    echo
  fi
  echo "In $wt, resolve each (remove every conflict marker, delete each .rej once applied), git add it, then run:"
  echo "  $(q "$0") --finish $(q "$wt")"
  exit 3
fi
finish "$wt"
