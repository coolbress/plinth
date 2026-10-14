#!/usr/bin/env bash
# The door for GitLab.com (#353 slice 2): run as
#   new-project.sh [<namespace>/]<name> --host gitlab [--license=<spdx>]
#                  [--archetype=<a>] [--dir=<path>] [--private|--public]
#
# It checks, renders and prints the plan (#531), creates the project and
# pushes main (#532), raises the wall (#533), then opens the first merge
# request and reports main's first pipeline (#534). A failure after the
# create, until the wall is up and read back, rolls the project back: deleted
# for good where the login can delete it, named where it cannot. After that
# the project is right, so a label or the merge request that fails is named
# and left.
#
# Every API read names gitlab.com (`glab api --hostname`): without it glab may
# answer for the GitLab host of the repository it is run from.
#
# Preflight, in order; the first miss stops with the one line that fixes it:
#   1 tools       claude, git >= 2.28, uv, python3, curl, glab >= the tested
#                 version, logged in to gitlab.com
#   2 login       the username glab is logged in as
#   3 namespace   a bare name goes under that username; <group>/<name> needs
#                 the Maintainer role or above in the group. Rollback needs
#                 Owner there: below it, rollback is off
#   4 project     GitLab's path rules and not a reserved name; no project and no
#                 subgroup on the path yet; no more public than its group.
#                 Private by default: GitLab.com Free protects a private
#                 project's branch (measured on #353)
# Then the license and the archetype against the template's own choices, and
# the render, with host=gitlab, into ~/<name> or --dir.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# stop, warn, below and choices_of, shared with the GitHub door.
# shellcheck source=scripts/lib/door.sh
. "$here/lib/door.sh"

# The pins come from new-project.sh, their one source: run through it.
template_repo="${PLINTH_DOOR_TEMPLATE_REPO:?run it as new-project.sh <name> --host gitlab}"
template_ref="${PLINTH_DOOR_TEMPLATE_REF:?run it as new-project.sh <name> --host gitlab}"
copier_version="${PLINTH_DOOR_COPIER_VERSION:?run it as new-project.sh <name> --host gitlab}"
copier_newer="${PLINTH_DOOR_COPIER_NEWER:?run it as new-project.sh <name> --host gitlab}"
claude_floor="${PLINTH_DOOR_CLAUDE_FLOOR:?run it as new-project.sh <name> --host gitlab}"
# The glab this door was run with on GitLab.com (#353): `glab api` with -X and
# -f, `glab auth status --hostname`, and `glab auth git-credential`.
glab_floor="1.122.0"
gitlab="gitlab.com"

usage="usage: new-project.sh [<namespace>/]<name> --host gitlab [--license=<spdx>] [--archetype=<a>] [--dir=<path>] [--private|--public]"
target=""; lic=mit; arch=cli; dir=""; visibility=private
for a in "$@"; do case "$a" in
  --private)     visibility=private ;;
  --public)      visibility=public ;;
  --license=*)   lic="${a#*=}" ;;
  --archetype=*) arch="${a#*=}" ;;
  --dir=*)       dir="${a#*=}" ;;
  -*)            echo "unknown option for --host gitlab: $a"$'\n'"$usage" >&2; exit 2 ;;
  *)             [ -z "$target" ] || { echo "one name only: $target, $a"$'\n'"$usage" >&2; exit 2; }; target="$a" ;;
esac; done
[ -n "$target" ] || { echo "$usage" >&2; exit 2; }

json() { # <python expression on d> < json: the value, or nothing when the input is not JSON
  python3 -c 'import json,sys
try: d = json.load(sys.stdin)
except ValueError: sys.exit(1)
v = eval(sys.argv[1], {"d": d})
print("" if v is None else v)' "$1" 2>/dev/null
}

# How long main's first pipeline is waited for, as on the GitHub path; and the
# Assisted-by line the first merge request ends with when an agent runs this
# (the skill sets it to its own <agent>:<model>, as CONTRIBUTING.md asks).
first_pr_wait="${PLINTH_FIRST_PR_WAIT:-300}"
case "$first_pr_wait" in ''|*[!0-9]*) stop "PLINTH_FIRST_PR_WAIT must be a whole number of seconds (got: $first_pr_wait)" "  fix: unset PLINTH_FIRST_PR_WAIT" ;; esac
assisted_by="${PLINTH_ASSISTED_BY:-}"
[ -z "$assisted_by" ] || [[ "$assisted_by" =~ ^[A-Za-z0-9._-]+:[A-Za-z0-9._-]+$ ]] \
  || stop "PLINTH_ASSISTED_BY must be <agent>:<model>, e.g. Claude:claude-opus-5-5 (got: $assisted_by)" "  fix: unset it, or set it in that form"

# ── 1 tools ──────────────────────────────────────────────────────────────
command -v git >/dev/null || stop "git is not installed" "  fix: macOS: xcode-select --install; Debian/Ubuntu: sudo apt install git"
git_v="$(git --version | awk '{print $3}')"
below 2.28 "$git_v" && stop "git $git_v is too old (2.28 or newer: init -b, switch)" "  fix: upgrade git"
command -v uv >/dev/null || stop "uv is not installed (it renders the template)" "  fix: curl -LsSf https://astral.sh/uv/install.sh | sh"
command -v python3 >/dev/null || stop "python3 is not installed (it reads GitLab's answers)" "  fix: macOS: xcode-select --install; Debian/Ubuntu: sudo apt install python3"
command -v curl >/dev/null || stop "curl is not installed (it reads the template's choices)" "  fix: install curl"
command -v claude >/dev/null || stop "claude (Claude Code) is not installed" "  fix: curl -fsSL https://claude.ai/install.sh | bash"
claude_v="$(claude --version 2>/dev/null | awk '{print $1}')" || claude_v=""
below "$claude_floor" "${claude_v:-0}" && stop "claude ${claude_v:-?} is below the supported floor $claude_floor" "  fix: claude update"
command -v glab >/dev/null || stop "glab (GitLab CLI) is not installed" "  fix: https://gitlab.com/gitlab-org/cli (macOS: brew install glab), then glab auth login --hostname $gitlab"
# The first field that reads as a version: `glab 1.122.0 (…)` now, `glab
# version 1.36.0 (…)` in older releases. None is a stop, never a pass.
glab_v="$(glab --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)" || glab_v=""
[ -n "$glab_v" ] || stop "could not read glab's version from \`glab --version\`" "  fix: brew upgrade glab (or your package manager's update), to $glab_floor or newer"
below "$glab_floor" "$glab_v" && stop "glab ${glab_v:-?} is below $glab_floor, the version this door was run with" "  fix: brew upgrade glab (or your package manager's update)"
glab auth status --hostname "$gitlab" >/dev/null 2>&1 \
  || stop "glab is not logged in to $gitlab" "  fix: glab auth login --hostname $gitlab --web --git-protocol https   (browser login; the token stays in the keyring)"

# ── 2 login ──────────────────────────────────────────────────────────────
user_json="$(glab api --hostname "$gitlab" user 2>/dev/null)" || stop "cannot read $gitlab/api/v4/user with glab's login" "  fix: glab auth status --hostname $gitlab"
login="$(json 'd["username"]' <<<"$user_json")" || login=""
user_id="$(json 'd["id"]' <<<"$user_json")" || user_id=""
[ -n "$login" ] && [ -n "$user_id" ] || stop "$gitlab/api/v4/user did not name the login" "  fix: glab auth status --hostname $gitlab"
# What the token may do. A personal access token names its scopes, and the
# door needs `api` to create, configure and delete a project. A browser
# login's OAuth token is not readable this way (measured on #531): glab's web
# login asks for `api`, but that is not read here, so the rollback is best
# effort, as the GitHub door says for a token whose reach it cannot read.
# A failed read is told apart by GitLab's answer (#535 review round 4): a
# browser login's token gets "requires token type to be a personal access
# token" (400, measured), a personal access token without the scope to read
# itself gets insufficient_scope (403); anything else is not an answer.
token_note=""; scopes_read=yes
token_fix="  fix: glab auth login --hostname $gitlab --web --git-protocol https   (or a personal access token with the api scope)"
if pat="$(glab api --hostname "$gitlab" personal_access_tokens/self 2>/dev/null)"; then
  scopes="$(json '" ".join(d["scopes"])' <<<"$pat")" || stop "could not read glab's token scopes from $gitlab" "$token_fix"
  grep -qw api <<<"$scopes" || stop "glab's token lacks the api scope (it has: ${scopes:-none}); creating and configuring a project needs it" "$token_fix"
else
  why="$(json 'd.get("error") or d.get("message", "")' <<<"$pat")" || why=""
  case "$why" in
    *"requires token type to be a personal access token"*)
      scopes_read=no
      token_note="token scopes: not readable (a browser login's token); glab's web login asks for api" ;;
    insufficient_scope*)
      stop "glab's token lacks the api scope (GitLab: insufficient_scope); creating and configuring a project needs it" "$token_fix" ;;
    *)
      stop "could not read glab's token scopes from $gitlab (GitLab answered: ${why:-nothing readable})" "$token_fix" ;;
  esac
fi

# ── 3 namespace ──────────────────────────────────────────────────────────
case "$target" in
  */*) ns="${target%/*}"; name="${target##*/}" ;;
  *)   ns="$login"; name="$target" ;;
esac
# GitLab paths are case-insensitive: the login's own namespace in any case is
# that namespace, written as GitLab writes it.
lower() { tr '[:upper:]' '[:lower:]' <<<"$1"; }
[ "$(lower "$ns")" = "$(lower "$login")" ] && ns="$login"
[[ "$ns" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*(/[A-Za-z0-9_][A-Za-z0-9_.-]*)*$ && "$name" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] \
  || stop "'$target' is not <name> or <namespace>/<name> (letters, digits, . _ -; a bare name goes under $login)"
project="$ns/$name"
url="https://$gitlab/$project"
dir="${dir:-$HOME/$name}"
enc() { python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"; }

# A personal namespace is the login's own: its owner creates and deletes there.
# A group needs Maintainer to create a project, and Owner to delete one, which
# the rollback (from #532) needs (GitLab's permissions table).
role=owner; rollback=on; group_vis=""
if [ "$ns" = "$login" ]; then
  ns_id="$(glab api --hostname "$gitlab" "namespaces/$(enc "$ns")" 2>/dev/null | json 'd["id"]')" || ns_id=""
  [ -n "$ns_id" ] || stop "could not read the namespace id of $ns on $gitlab" "  fix: glab auth status --hostname $gitlab"
else
  group_json="$(glab api --hostname "$gitlab" "groups/$(enc "$ns")" 2>/dev/null)" || group_json=""
  group_id="$(json 'd["id"]' <<<"$group_json")" || group_id=""
  [ -n "$group_id" ] || stop "group '$ns' does not exist on GitLab.com, or $login cannot see it" \
    "  fix: create it under $login ($login/$name), or ask a group Owner for access"
  ns_id="$group_id"
  group_vis="$(json 'd.get("visibility")' <<<"$group_json")" || group_vis=""
  level="$(glab api --hostname "$gitlab" "groups/$group_id/members/all/$user_id" 2>/dev/null | json 'd["access_level"]')" || level=""
  case "$level" in
    50) role=owner ;;
    40) role=maintainer; rollback="off (a Maintainer cannot delete a project in $ns; on failure it stays, for an Owner of $ns to delete)" ;;
    *)  stop "creating a project in '$ns' needs the Maintainer role or above; $login has ${level:+access level $level}${level:-no membership}" \
          "  fix: ask a group Owner for Maintainer, or create it under $login ($login/$name)" ;;
  esac
  # The group's own setting for who may create projects in it.
  creation="$(json 'd.get("project_creation_level")' <<<"$group_json")" || creation=""
  case "$creation" in
    noone) stop "the group '$ns' lets no one create projects (its project creation setting)" "  fix: a group Owner changes it, or create it under $login ($login/$name)" ;;
    owner) [ "$role" = owner ] || stop "the group '$ns' lets only Owners create projects, and $login is $role there" "  fix: ask a group Owner, or create it under $login ($login/$name)" ;;
  esac
fi
# A project is no more visible than its group (GitLab's group visibility
# rules; #535 review round 3): private < internal < public.
rank() { case "$1" in private) echo 0 ;; internal) echo 1 ;; public) echo 2 ;; *) echo 9 ;; esac; }
if [ "$ns" != "$login" ] && [ "$visibility" != private ] && [ -z "$group_vis" ]; then
  stop "could not read the visibility of the group '$ns', and a $visibility project must be no more visible than its group" \
    "  fix: run it again, or --private"
fi
if [ -n "$group_vis" ] && [ "$(rank "$visibility")" -gt "$(rank "$group_vis")" ]; then
  stop "a $visibility project cannot sit in the group '$ns', which is $group_vis: GitLab keeps a project no more visible than its group" \
    "  fix: --private, or a group Owner raises the group's visibility"
fi
if [ "$scopes_read" = no ]; then
  case "$rollback" in on) rollback="best effort (the token's scopes are not readable; it needs api to delete what it creates)" ;; esac
fi

# ── 4 project ────────────────────────────────────────────────────────────
# GitLab's path rules (its "Reserved project and group names" page): letters,
# digits, `_`, `-` and `.`; a letter or digit at each end; no two special
# characters in a row; not ending in `.git` or `.atom`. Checked before the
# render, so a name GitLab would refuse is never planned.
if ! [[ "$name" =~ ^[A-Za-z0-9]([A-Za-z0-9_.-]*[A-Za-z0-9])?$ ]] || [[ "$name" =~ [_.-][_.-] ]] \
   || [[ "$(lower "$name")" =~ \.(git|atom)$ ]]; then
  stop "'$name' is not a GitLab project path: letters, digits, _ - and ., a letter or digit at each end, no two of _ - . in a row, not ending in .git or .atom" \
    "  fix: choose another project name"
fi
# GitLab's reserved project names (the same page, one path segment each).
case "$(lower "$name")" in
  badges|blame|blob|builds|commits|create|create_dir|edit|files|find_file|new|preview|raw|refs|tree|update|wikis)
    stop "'$name' is a name GitLab reserves for its own routes; it refuses a project by that name" "  fix: choose another project name" ;;
esac
# The template derives the package name from the project name and refuses one
# that is not a Python identifier (its copier.yml validator). Checked here, so
# the refusal comes before the render and before anything exists.
pkg="$(lower "$name" | sed 's/[-. ]/_/g')"
python3 -c 'import keyword, re, sys; p = sys.argv[1]; sys.exit(0 if re.fullmatch(r"[a-z_][a-z0-9_]*", p) and not keyword.iskeyword(p) else 1)' "$pkg" \
  || stop "No Python package name can be made from '$name': '$pkg' is not an identifier or is a Python keyword" "  fix: choose another project name"
# Only a 404 is "not there": a network error, a 401 or a 5xx is not an answer.
# The status is read from the answer's JSON `message` ("404 Project Not
# Found"), never from glab's error text, which can carry the request path.
if exists_out="$(glab api --hostname "$gitlab" "projects/$(enc "$project")" 2>/dev/null)"; then
  stop "$url already exists; the door creates new projects only"
fi
exists_msg="$(json 'd.get("message", "") if isinstance(d, dict) else ""' <<<"$exists_out")" || exists_msg=""
case "$exists_msg" in
  "404 "*) ;;
  *) stop "could not tell whether $url exists; GitLab answered: $(head -c 200 <<<"${exists_msg:-$exists_out}" | tr '\n' ' ')" "  fix: run it again" ;;
esac
# A subgroup on the same path blocks the project too (#535 review round 4).
if [ "$ns" != "$login" ]; then
  if sub_out="$(glab api --hostname "$gitlab" "groups/$(enc "$project")" 2>/dev/null)"; then
    stop "$url is taken: a subgroup already holds that path, and GitLab does not put a project and a subgroup on one path" "  fix: choose another project name"
  fi
  sub_msg="$(json 'd.get("message", "") if isinstance(d, dict) else ""' <<<"$sub_out")" || sub_msg=""
  case "$sub_msg" in "404 "*) ;; *) stop "could not tell whether a subgroup holds $url; GitLab answered: ${sub_msg:-nothing readable}" "  fix: run it again" ;; esac
fi
[ ! -e "$dir" ] || { entries="$(ls -A "$dir" 2>/dev/null)" && [ -z "$entries" ]; } \
  || stop "$dir already exists and is not an empty directory" "  fix: --dir=<another path>   (the door creates ~/<name> itself; an empty directory is fine)"
if git -C "$(dirname "$dir")" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  stop "$dir would be a repository inside the repository $(git -C "$(dirname "$dir")" rev-parse --show-toplevel)" "  fix: --dir=<a path outside it>"
fi

# The license and the archetype against the template's own choices, read from
# its copier.yml at the pinned tag (public, over GitHub's raw files): copier
# refuses anything else, and that would come after the project exists.
copier_yml="$(curl -fsSL --retry 2 "https://raw.githubusercontent.com/$template_repo/$template_ref/copier.yml" 2>/dev/null)" || copier_yml=""
arch_choices="$(choices_of archetype)"; lic_choices="$(choices_of license)"
[ -n "$arch_choices" ] && [ -n "$lic_choices" ] \
  || stop "could not read the template's archetype and license choices ($template_repo@$template_ref copier.yml)" "  fix: run it again; it needs raw.githubusercontent.com"
grep -qxF "$arch" <<<"$arch_choices" || stop "unknown archetype: $arch" "  the template accepts: $(tr '\n' ' ' <<<"$arch_choices")"
spdx="$(grep -ixF "$lic" <<<"$lic_choices" | head -1)" || spdx=""
[ -n "$spdx" ] || stop "the template does not carry the license $lic" "  it accepts: $(tr '\n' ' ' <<<"$lic_choices")"

# Render, as the GitHub door does: copier at its pinned version and date,
# into a plain directory whose .git is removed, then initialised (#118).
# Without a token in its environment: gh's two names, and the three glab reads
# (GITLAB_TOKEN, GITLAB_ACCESS_TOKEN, OAUTH_TOKEN; its configuration reference).
env -u GH_TOKEN -u GITHUB_TOKEN -u GITLAB_TOKEN -u GITLAB_ACCESS_TOKEN -u OAUTH_TOKEN uvx --quiet --from "copier==$copier_version" --exclude-newer "$copier_newer" \
  copier copy --defaults --quiet \
  --data "project_name=$name" --data "owner=$ns" --data "license=$spdx" --data "archetype=$arch" \
  --data "host=gitlab" \
  --vcs-ref "$template_ref" "gh:$template_repo" "$dir" < /dev/null
rm -rf "$dir/.git"
git init -q -b main "$dir"
git -C "$dir" remote add origin "$url.git"
git -C "$dir" add -A
git -C "$dir" commit -q -m "chore: render $template_repo@$template_ref ($arch, $spdx, host gitlab)"

echo "create $gitlab/$project ($visibility, $spdx, $arch, as $role) from $template_repo@$template_ref in $dir; wall: protected main (no push, Maintainers merge, no force push), Pipelines must succeed, squash, fast-forward; then the first merge request. rollback: $rollback"
[ -z "$token_note" ] || echo "$token_note"

# ── create ───────────────────────────────────────────────────────────────
# Through the API, not `glab repo create`, which prompts and hangs inside a
# git repository (measured on #353). A failed create leaves nothing to roll
# back; its answer is named.
# The answer is read from stdout only: glab writes notices (an update
# available) to stderr even when the call succeeds.
create_err="$(mktemp)"
if ! create_out="$(glab api --hostname "$gitlab" -X POST projects -f "name=$name" -f "path=$name" \
      -F "namespace_id=$ns_id" -f "visibility=$visibility" -f default_branch=main 2>"$create_err")"; then
  printf '%s\n' "the create call failed, so there is nothing to roll back: $(head -c 300 <<<"$create_out $(cat "$create_err")" | tr '\n' ' ')" \
    "  if GitLab created it anyway, it is at $url" >&2
  rm -f "$create_err"; exit 1
fi
rm -f "$create_err"
project_id="$(json 'd["id"]' <<<"$create_out")" || project_id=""
[ -n "$project_id" ] || { printf '%s\n' "the create call answered without a project id; check $url and delete it by hand if it exists" >&2; exit 1; }
created=1; finished=0

# The rollback, for a failure after the create: GitLab.com schedules a
# deletion and renames the path, so the project is deleted, its new path read,
# and then removed for good with that path (permanently_remove, full_path).
rollback() {
  case "$rollback" in off*)
    # Rollback is off for a group Maintainer because only an Owner (or an
    # administrator) can delete a project: the fix names who can.
    printf '%s\n' "rollback is off: $url stays, with part of its wall or none, and only an Owner of $ns can delete it: ask one to delete $url (Settings > General > Advanced)" >&2; return ;;
  esac
  if ! glab api --hostname "$gitlab" -X DELETE "projects/$project_id" >/dev/null 2>&1; then
    printf '%s\n' "ROLLBACK FAILED: $url exists with part of its wall or none; delete it at $url/edit" >&2; return
  fi
  # After the first DELETE the path has changed, so the project is named by
  # its id from here on (GitLab redirects /projects/<id> to wherever it is).
  by_id="https://$gitlab/projects/$project_id"
  if read_out="$(glab api --hostname "$gitlab" "projects/$project_id" 2>/dev/null)"; then
    renamed="$(json 'd["path_with_namespace"]' <<<"$read_out")" || renamed=""
  else
    read_msg="$(json 'd.get("message", "") if isinstance(d, dict) else ""' <<<"$read_out")" || read_msg=""
    case "$read_msg" in "404 "*)
      printf '%s\n' "rolled back: deleted $url (GitLab removed it at once)" >&2; return ;;
    esac
    renamed=""
  fi
  if [ -n "$renamed" ] && glab api --hostname "$gitlab" -X DELETE "projects/$project_id?permanently_remove=true&full_path=$(enc "$renamed")" >/dev/null 2>&1; then
    printf '%s\n' "rolled back: deleted $url for good" >&2
  else
    printf '%s\n' "ROLLBACK PARTLY DONE: $url is scheduled for deletion (as ${renamed:-an unread path}), not removed for good; remove it at $by_id (Settings > General > Advanced)" >&2
  fi
}
cleanup() {
  local rc=$?
  trap - EXIT
  if [ "${created:-0}" = 1 ] && [ "${finished:-0}" != 1 ]; then
    rollback
    [ "$rc" -ne 0 ] || rc=1
  fi
  exit "$rc"
}
trap cleanup EXIT

# ── push main ────────────────────────────────────────────────────────────
# Over HTTPS, with glab as the credential helper for gitlab.com in this
# repository's own config only, as the #353 probe pushed.
git -C "$dir" config --local --replace-all credential.https://gitlab.com.helper ''
git -C "$dir" config --local --add credential.https://gitlab.com.helper '!glab auth git-credential'
git -C "$dir" push -u origin main
echo "created $url ($visibility) and pushed main"

# ── the wall ─────────────────────────────────────────────────────────────
# What #353 measured on GitLab.com Free. GitLab protects the default branch
# on the first push with its own levels, so that protection is replaced:
# no one pushes, Maintainers merge, no force push. Then the merge checks
# (the pipeline must succeed, a skipped one not counted), squash required and
# fast-forward merges, so main gains one commit per merge request. Each part
# is read back; a call or a read-back that fails rolls the project back.
# A call that fails prints GitLab's answer after the caller's message.
wall() {
  local out
  out="$(glab api --hostname "$gitlab" "$@" 2>&1)" && return 0
  printf ' GitLab answered: %s' "$(head -c 300 <<<"$out" | tr '\n' ' ')"
  return 1
}
unprotect_out="$(glab api --hostname "$gitlab" -X DELETE "projects/$project_id/protected_branches/main" 2>/dev/null)" || {
  unprotect_msg="$(json 'd.get("message", "") if isinstance(d, dict) else ""' <<<"$unprotect_out")" || unprotect_msg="$unprotect_out"
  case "$unprotect_msg" in
    "404 "*) ;;   # not protected yet: nothing to replace
    *) printf '%s\n' "could not remove GitLab's default protection of main: $(head -c 300 <<<"$unprotect_msg" | tr '\n' ' ')" >&2; exit 1 ;;
  esac; }
protect() { wall -X POST "projects/$project_id/protected_branches" -f name=main -F push_access_level=0 -F merge_access_level=40 -F allow_force_push=false; }
if ! why="$(protect)"; then
  # GitLab protects the default branch in a job after the push, which can
  # land between the DELETE and the POST: delete that protection, post once more.
  case "$why" in
    *"already exists"*) why="$(wall -X DELETE "projects/$project_id/protected_branches/main")" && why="$(protect)" ;;
    *) false ;;
  esac || { printf '%s\n' "could not protect main:$why" >&2; exit 1; }
fi
if ! why="$(wall -X PUT "projects/$project_id" -F only_allow_merge_if_pipeline_succeeds=true -F allow_merge_on_skipped_pipeline=false)"; then
  printf '%s\n' "could not set the merge checks:$why" >&2; exit 1
fi
if ! why="$(wall -X PUT "projects/$project_id" -f squash_option=always -f merge_method=ff)"; then
  printf '%s\n' "could not require squash and fast-forward merges:$why" >&2; exit 1
fi
glab api --hostname "$gitlab" "projects/$project_id/protected_branches/main" 2>/dev/null | python3 -c 'import json, sys
d = json.load(sys.stdin)
ok = (d.get("allow_force_push") is False
      and [a.get("access_level") for a in d.get("push_access_levels", [])] == [0]
      and [a.get("access_level") for a in d.get("merge_access_levels", [])] == [40])
sys.exit(0 if ok else 1)' 2>/dev/null || { printf '%s\n' "main's protection did not read back as set (no push, Maintainers merge, no force push)" >&2; exit 1; }
glab api --hostname "$gitlab" "projects/$project_id" 2>/dev/null | python3 -c 'import json, sys
d = json.load(sys.stdin)
ok = (d.get("only_allow_merge_if_pipeline_succeeds") is True and d.get("allow_merge_on_skipped_pipeline") is False
      and d.get("squash_option") == "always" and d.get("merge_method") == "ff")
sys.exit(0 if ok else 1)' 2>/dev/null || { printf '%s\n' "the merge settings did not read back as set (pipeline must succeed, skipped not counted, squash, fast-forward)" >&2; exit 1; }
finished=1

# Labels. The list is labels.txt, shared with the GitHub door and
# scripts/floor-check.py (#84). GitLab wants the colour with its #. A label
# that fails is named and left: a convenience, not a wall stone.
grep -vE '^[[:space:]]*(#|$)' "$here/../labels.txt" | while IFS='|' read -r lbl color desc; do
  why="$(wall -X POST "projects/$project_id/labels" -f "name=$lbl" -f "color=#$color" -f "description=$desc")" ||
    warn "could not create the label $lbl:$why; create it in $url/-/labels"
done

# ── the first merge request ──────────────────────────────────────────────
# As on the GitHub path: a First day section in README.md, on a branch, in a
# merge request whose description has the rendered template's shape
# (.gitlab/merge_request_templates/Default.md). The wall stands already, so
# a failure here is named with the command that finishes it, not rolled back.
if [ "$ns" = "$login" ]; then quota_url="https://$gitlab/-/profile/usage_quotas"
else quota_url="https://$gitlab/groups/$ns/-/usage_quotas"; fi
first_day="- A merge request merges only when its pipeline succeeds. GitLab Free has no required checks by name: a merge request that removes a job from \`.gitlab-ci.yml\` still merges when what is left passes, so read the job list of one that changes that file.
- Each pipeline uses the namespace's GitLab.com compute minutes, about 4 to 5 for this project's pipeline. The quota: $quota_url
- Merge with the command in CONTRIBUTING.md: squash, with the description as the commit body."
printf '\n## First day\n\n%s\n\nMade with [plinth](https://github.com/coolbress/plinth).\n' "$first_day" >> "$dir/README.md"
branch="docs/first-mr"
mr_title="docs: first merge request through the wall"
git -C "$dir" switch -q -c "$branch"
git -C "$dir" commit -q -am "$mr_title"
mr_body="## What and why

Opened by /plinth:new-project to prove the wall. A merge request merges only when its pipeline succeeds, so merging this one shows the wall stands and can be passed. It adds a First day section to README.md and changes nothing else.

## How it was verified

Nothing yet: when this was written the pipeline had not run, and running it is what this merge request is for. A failed job: open it and read the last lines of its log.

## First day

$first_day${assisted_by:+

Assisted-by: $assisted_by}"
if ! push_err="$(git -C "$dir" push -u origin "$branch" 2>&1 >/dev/null)"; then
  mr_line="not opened (the push of $branch failed: $(tail -1 <<<"$push_err")); push and open it: cd $dir && git push -u origin $branch && glab mr create --source-branch $branch --target-branch main --fill"
else
  mr_err="$(mktemp)"
  if mr_out="$(glab api --hostname "$gitlab" -X POST "projects/$project_id/merge_requests" -f "source_branch=$branch" -f target_branch=main \
        -f "title=$mr_title" -F remove_source_branch=true -f "description=$mr_body" 2>"$mr_err")" \
     && mr_url="$(json 'd["web_url"]' <<<"$mr_out")" && [ -n "$mr_url" ]; then
    mr_line="$mr_url"
  else
    mr_line="not opened (GitLab answered: $(head -c 300 <<<"$mr_out" | tr '\n' ' ' | sed 's/ *$//')); open it: cd $dir && glab mr create --source-branch $branch --target-branch main --fill"
  fi
  rm -f "$mr_err"
fi

# ── main's first pipeline ────────────────────────────────────────────────
# The push of main started it before the wall stood. Read until it completes
# or the wait ends, every 10 s; its ending is reported, and a red one is named
# with its failed jobs and not re-run: re-running blindly hides a real failure.
polls=$(( first_pr_wait / 10 + 1 )); poll=0; b_line=""; b_status=""; b_url=""; b_err=""
while [ -z "$b_line" ]; do
  poll=$((poll + 1))
  if b_out="$(glab api --hostname "$gitlab" "projects/$project_id/pipelines?ref=main" 2>/dev/null)"; then
    b_err=""
    # The list is newest first; main's first pipeline is the oldest.
    read -r b_id b_status b_url < <(json '" ".join(str(d[-1].get(k, "")) for k in ("id", "status", "web_url")) if d else ""' <<<"$b_out") || true
    case "${b_status:-}" in
      success) b_line="success: $b_url" ;;
      failed)
        jobs="$(glab api --hostname "$gitlab" "projects/$project_id/pipelines/$b_id/jobs?scope[]=failed" 2>/dev/null \
          | json '", ".join(j["name"] for j in d)')" || jobs=""
        b_line="failed (failed jobs: ${jobs:-could not be read}), not re-run: $b_url" ;;
      canceled|skipped) b_line="ended $b_status, so not confirmed: $b_url" ;;
    esac
  else
    b_err="$(json 'd.get("message", "") if isinstance(d, dict) else ""' <<<"$b_out")" || b_err=""
    b_err="${b_err:-no answer}"; b_status=""
  fi
  [ -n "$b_line" ] && break
  if [ "$poll" -ge "$polls" ]; then
    if [ -n "$b_err" ]; then b_line="not confirmed: could not be read ($b_err)"
    elif [ -z "${b_status:-}" ]; then b_line="not confirmed: not listed within $first_pr_wait s"
    else b_line="not confirmed: still $b_status after $first_pr_wait s: $b_url"; fi
    break
  fi
  sleep 10
done

cat <<EOF
done: $url ($visibility, $spdx, $arch, $template_repo@$template_ref)
  local: $dir
  first merge request: $mr_line
    wait for its pipeline to pass, then merge it with the command in CONTRIBUTING.md (squash, the description as the commit body)
  first pipeline on main: $b_line
  wall: main protected (no push, Maintainers merge, no force push); merges only when the pipeline succeeds, a skipped one not counted; squash, fast-forward
  GitLab Free has no required checks by name: a merge request that drops a job from .gitlab-ci.yml still merges when what is left passes (docs/reference/gitlab-ci.md)
  compute minutes: each pipeline uses the namespace's GitLab.com compute minutes, about 4 to 5 for this one (measured on #353); the quota is at $quota_url
  next: cd $dir && claude
EOF
