#!/usr/bin/env bash
# The door for GitLab.com (#353 slice 2): run as
#   new-project.sh [<namespace>/]<name> --host gitlab [--license=<spdx>]
#                  [--archetype=<a>] [--dir=<path>] [--private|--public]
#
# This stage (#531) checks, renders and prints the plan, and creates nothing on
# GitLab. Creating the project and pushing main (#532), raising the wall
# (#533) and the first merge request (#534) come next.
#
# Every API read names gitlab.com (`glab api --hostname`): without it glab may
# answer for the GitLab host of the repository it is run from.
#
# Preflight, in order; the first miss stops with the one line that fixes it:
#   1 tools       claude, git >= 2.28, uv, python3, curl, glab >= the tested
#                 version, logged in to gitlab.com
#   2 login       the username glab is logged in as
#   3 namespace   a bare name goes under that username; <group>/<name> needs
#                 the Maintainer role or above in the group. Rollback (once
#                 the door creates) needs Owner there: below it, rollback is off
#   4 project     must not exist yet. Private by default: GitLab.com Free
#                 protects a private project's branch (measured on #353)
# Then the license and the archetype against the template's own choices, and
# the render, with host=gitlab, into ~/<name> or --dir.
set -euo pipefail

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

stop() { printf '%s\n' "$@" >&2; exit 2; }
below() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" != "$1" ]; }   # below <floor> <version>
json() { # <python expression on d> < json: the value, or nothing when the input is not JSON
  python3 -c 'import json,sys
try: d = json.load(sys.stdin)
except ValueError: sys.exit(1)
v = eval(sys.argv[1], {"d": d})
print("" if v is None else v)' "$1" 2>/dev/null
}

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
token_note=""; scopes_read=yes
if pat="$(glab api --hostname "$gitlab" personal_access_tokens/self 2>/dev/null)" && scopes="$(json '" ".join(d["scopes"])' <<<"$pat")"; then
  grep -qw api <<<"$scopes" || stop "glab's token lacks the api scope (it has: ${scopes:-none}); creating and configuring a project needs it" \
    "  fix: glab auth login --hostname $gitlab --web --git-protocol https   (or a personal access token with the api scope)"
else
  scopes_read=no
  token_note="token scopes: not readable (a browser login's token); glab's web login asks for api"
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
role=owner; rollback=on
if [ "$ns" != "$login" ]; then
  group_json="$(glab api --hostname "$gitlab" "groups/$(enc "$ns")" 2>/dev/null)" || group_json=""
  group_id="$(json 'd["id"]' <<<"$group_json")" || group_id=""
  [ -n "$group_id" ] || stop "group '$ns' does not exist on GitLab.com, or $login cannot see it" \
    "  fix: create it under $login ($login/$name), or ask a group Owner for access"
  level="$(glab api --hostname "$gitlab" "groups/$group_id/members/all/$user_id" 2>/dev/null | json 'd["access_level"]')" || level=""
  case "$level" in
    50) role=owner ;;
    40) role=maintainer; rollback="off (Maintainer cannot delete a project in $ns; on failure it stays: delete it at $url/edit)" ;;
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
[ ! -e "$dir" ] || { entries="$(ls -A "$dir" 2>/dev/null)" && [ -z "$entries" ]; } \
  || stop "$dir already exists and is not an empty directory" "  fix: --dir=<another path>   (the door creates ~/<name> itself; an empty directory is fine)"
if git -C "$(dirname "$dir")" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  stop "$dir would be a repository inside the repository $(git -C "$(dirname "$dir")" rev-parse --show-toplevel)" "  fix: --dir=<a path outside it>"
fi

# The license and the archetype against the template's own choices, read from
# its copier.yml at the pinned tag (public, over GitHub's raw files): copier
# refuses anything else, and that would come after the project exists.
copier_yml="$(curl -fsSL --retry 2 "https://raw.githubusercontent.com/$template_repo/$template_ref/copier.yml" 2>/dev/null)" || copier_yml=""
choices_of() { sed -n "/^$1:/,/^[a-z_]/p" <<<"$copier_yml" | sed -n 's/^    [^:]*: \([A-Za-z0-9][A-Za-z0-9.-]*\)$/\1/p'; }
arch_choices="$(choices_of archetype)"; lic_choices="$(choices_of license)"
[ -n "$arch_choices" ] && [ -n "$lic_choices" ] \
  || stop "could not read the template's archetype and license choices ($template_repo@$template_ref copier.yml)" "  fix: run it again; it needs raw.githubusercontent.com"
grep -qxF "$arch" <<<"$arch_choices" || stop "unknown archetype: $arch" "  the template accepts: $(tr '\n' ' ' <<<"$arch_choices")"
spdx="$(grep -ixF "$lic" <<<"$lic_choices" | head -1)" || spdx=""
[ -n "$spdx" ] || stop "the template does not carry the license $lic" "  it accepts: $(tr '\n' ' ' <<<"$lic_choices")"

# Render, as the GitHub door does: copier at its pinned version and date,
# without a token in its environment, into a plain directory whose .git is
# removed, then initialised (#118).
env -u GH_TOKEN -u GITHUB_TOKEN -u GITLAB_TOKEN uvx --quiet --from "copier==$copier_version" --exclude-newer "$copier_newer" \
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
echo "rendered into $dir; nothing is created on GitLab yet: creating the project, the wall and the first merge request are the next stages of the GitLab door (#353)"
