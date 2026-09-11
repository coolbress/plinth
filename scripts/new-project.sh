#!/usr/bin/env bash
# The door: create a repository with the wall already up, or create nothing.
#
#   new-project.sh [<owner>/]<name> [--license=<spdx>] [--archetype=<a>] [--dir=<path>]
#                  [--force-defaults]
#
# Preflight, in order; the first miss stops with the one line that fixes it,
# before anything exists:
#   1 tools       claude >= 2.1.234, git >= 2.28, uv, gh logged in (warnings: token
#                 in the environment, sandbox off, native Windows)
#   2 token       classic: scopes repo and workflow; delete_repo is optional and
#                 without it rollback is off. Fine-grained: the admin path, because
#                 its reach over a repository that does not exist yet cannot be read.
#   3 owner       exists; your own login or an organization you belong to
#   4 visibility  public only; the repository must not exist yet
# Then: create, render the box (copier, one tested tag), push main (the baseline,
# before the wall, and the proof the token can push), confirm main is the
# default branch the ruleset will target, labels, ruleset, secret scanning,
# Dependabot, Actions allowlist, squash only, CodeQL (once GitHub has detected
# the languages, and waited for until its first analysis of main is done), and
# the first pull request, whose workflow must start.
#
# fail-closed: after the repository is created, a fatal exit before setup
# completes attempts a best-effort deletion -- the trap fires on `created=1`
# alone and does not inspect the wall, so a failure after the ruleset is applied
# deletes too. The local clone stays; a failed deletion prints the URL loudly.
# Two steps are not fatal and warn instead: a label that cannot be created, and
# a CodeQL default setup slow to configure or to pick the first pull request up
# (the door pushes one empty commit itself, which is analysed; then it warns).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The box, at the one tag this version of plinth is tested with, and the
# workflow file it ships (the first pull request's run is looked up by it).
# Then the renderer, at one version, with its dependencies as they were on
# one date: copier runs as you, with your git configuration in reach, and
# an unpinned resolution would let any package published later run there.
# Raising the tag, the version or the date is the only edit here.
template_repo="coolbress/plinth-template"
template_ref="v1.3.0"
template_ci=".github/workflows/ci.yml"
copier_version="9.18.2"
copier_newer="2026-09-09"
claude_floor="2.1.234"
tutorial="https://github.com/coolbress/plinth/blob/main/docs/tutorials/getting-started.md"

usage="usage: new-project.sh [<owner>/]<name> [--license=<spdx>] [--archetype=<a>] [--dir=<path>] [--force-defaults]"
target=""; lic=mit; arch=cli; dir=""; private=0; force_defaults=0
for a in "$@"; do case "$a" in
  --private)     private=1 ;;
  --force-defaults) force_defaults=1 ;;
  --license=*)   lic="${a#*=}" ;;
  --archetype=*) arch="${a#*=}" ;;
  --dir=*)       dir="${a#*=}" ;;
  -*)            echo "unknown option: $a"$'\n'"$usage" >&2; exit 2 ;;
  *)             [ -z "$target" ] || { echo "one name only: $target, $a"$'\n'"$usage" >&2; exit 2; }; target="$a" ;;
esac; done
[ -n "$target" ] || { echo "$usage" >&2; exit 2; }
# The wall requires CodeQL, and CodeQL on a private repository needs a GitHub
# Code Security license; a ruleset requiring a check that never reports locks
# the repository on its first PR. Refused here, before any call, so nobody
# types an admin token for a request that cannot be served.
if [ "$private" = 1 ]; then
  cat >&2 <<'EOF'
private repositories are not supported yet: the wall requires CodeQL, and private CodeQL needs a GitHub Code Security license (org on Team+).
  now:   create it public (drop --private)
  free:  GitLab Free has protected branches + pipelines-must-succeed (no CodeQL, no push protection) — see docs/explanation/what-private-repos-get
  later: a lower wall for private repos (Semgrep OSS instead of CodeQL — the original standards decision, not built) is a v1.1 candidate
EOF
  exit 2
fi

stop() { printf '%s\n' "$@" >&2; exit 2; }
warn() { printf 'warning: %s\n' "$1" >&2; }
below() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" != "$1" ]; }   # below <floor> <version>

# ── 1 tools ──────────────────────────────────────────────────────────────
command -v git >/dev/null || stop "git is not installed" "  fix: macOS: xcode-select --install; Debian/Ubuntu: sudo apt install git"
git_v="$(git --version | awk '{print $3}')"
below 2.28 "$git_v" && stop "git $git_v is too old (2.28 or newer: init -b, switch)" "  fix: upgrade git"
command -v uv  >/dev/null || stop "uv is not installed (it renders the template)" "  fix: curl -LsSf https://astral.sh/uv/install.sh | sh"
command -v gh  >/dev/null || stop "gh (GitHub CLI) is not installed" "  fix: https://cli.github.com, then gh auth login"
command -v claude >/dev/null || stop "claude (Claude Code) is not installed" "  fix: curl -fsSL https://claude.ai/install.sh | bash"
claude_v="$(claude --version 2>/dev/null | awk '{print $1}')" || claude_v=""
below "$claude_floor" "${claude_v:-0}" && stop "claude ${claude_v:-?} is below the supported floor $claude_floor" "  fix: claude update"
gh auth status >/dev/null 2>&1 || stop "gh is not logged in" "  fix: gh auth login   (browser login; the token stays in the keychain)"
# How long each wait below may take: GitHub detecting the languages, CodeQL
# default setup's first analysis of main, and the first pull request being
# picked up by CI and CodeQL (three waits, so three times this at worst). 300 s
# covers the second, a CodeQL run for Python and Actions on a fresh runner;
# the other two usually end within a minute. Tests shorten it; a typo must
# stop here, not after the repository exists.
first_pr_wait="${PLINTH_FIRST_PR_WAIT:-300}"
case "$first_pr_wait" in ''|*[!0-9]*) stop "PLINTH_FIRST_PR_WAIT must be a whole number of seconds (got: $first_pr_wait)" "  fix: unset PLINTH_FIRST_PR_WAIT" ;; esac

if [ "${PLINTH_TOKEN_SOURCE:-}" != prompt ]; then
  for v in GH_TOKEN GITHUB_TOKEN; do
    [ -n "${!v:-}" ] && warn "$v is set in the environment; the agent can read it. Prefer gh auth login (keychain)."
  done
fi
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) warn "native Windows is not tested; use WSL2" ;; esac
conf="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if command -v python3 >/dev/null && ! python3 - "$conf/settings.json" "$conf/settings.local.json" <<'PYCHK' 2>/dev/null
import json, sys
for f in sys.argv[1:]:
    try:
        if json.load(open(f)).get("sandbox", {}).get("enabled") is True: sys.exit(0)
    except Exception:
        pass
sys.exit(1)
PYCHK
then warn "sandbox is off in $conf/settings.json; run /sandbox once in Claude Code (macOS: as is; Linux/WSL2: needs bubblewrap and socat; native Windows: not supported)"; fi

# ── 2 token ──────────────────────────────────────────────────────────────
login="$(gh api user --jq .login)"
case "$target" in
  */*) owner="${target%%/*}"; name="${target#*/}" ;;
  *)   owner="$login"; name="$target" ;;
esac
[[ "$owner" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ && "$name" =~ ^[A-Za-z0-9._][A-Za-z0-9._-]*$ ]] \
  || stop "'$target' is not <name> or <owner>/<name> (letters, digits, . _ -; a bare name goes under $login)"
repo="$owner/$name"
url="https://github.com/$repo"
dir="${dir:-$HOME/$name}"

# A classic token answers with X-OAuth-Scopes; a fine-grained or app token has no such header.
headers="$(gh api -i user 2>&1 | tr -d '\r' | sed '/^$/q')" || stop "cannot read api.github.com/user as $login:" "$headers"
scopes="$(awk 'tolower($1)=="x-oauth-scopes:"{sub(/^[^:]*: ?/,""); print; exit}' <<<"$headers")"
has_scope() { grep -qE "(^|,) *$1 *(,|$)" <<<"$scopes"; }
rollback="on"
if grep -qi '^x-oauth-scopes:' <<<"$headers"; then
  missing=""
  for s in repo workflow; do has_scope "$s" || missing="$missing$s,"; done
  [ -z "$missing" ] || stop "gh's token lacks the scope(s) ${missing%,} (it has: ${scopes:-none})" \
    "  fix: gh auth refresh -h github.com -s repo,workflow,delete_repo   (delete_repo is optional: it lets a failed run delete what it created)" \
    "  a personal access token instead: https://github.com/settings/tokens with the same scopes"
  has_scope delete_repo || rollback="off (no delete_repo scope; on failure the repository stays: delete it at $url/settings)"
elif [ "${PLINTH_TOKEN_SOURCE:-}" = prompt ]; then
  rollback="best effort (fine-grained token: needs Administration: write on $owner's repositories)"
else
  stop "gh is using a fine-grained token; whether it reaches a repository that does not exist yet cannot be read" \
    "  fix: run the door with an admin token, typed at a prompt (never on the command line)," \
    "  in a separate terminal window (not through ! in Claude Code: that has no terminal to prompt at):" \
    "    P=$(printf '%q' "$here")" \
    "    \"\$P/with-admin-token.sh\" \"\$P/new-project.sh\" \\" \
    "      $*" \
    "  the token, classic: scopes repo, workflow, delete_repo (https://github.com/settings/tokens)" \
    "  or fine-grained (https://github.com/settings/personal-access-tokens): Repository permissions Administration," \
    "  Contents, Workflows, Pull requests: write on all repositories of $owner (a repository that does not exist" \
    "  yet is not selectable); for an organization owner also Organization permissions Members: read"
fi

# ── 3 owner ──────────────────────────────────────────────────────────────
kind="$(gh api "users/$owner" --jq .type 2>/dev/null)" \
  || stop "owner '$owner' does not exist on GitHub (users/$owner)"
if [ "$kind" = Organization ]; then
  role="$(gh api "orgs/$owner/memberships/$login" --jq .role 2>/dev/null)" \
    || stop "you ($login) are not a member of the organization '$owner', or the token cannot read memberships (classic: read:org; fine-grained: Organization permissions Members: read)" \
      "  fix: ask an owner of $owner for membership, or create it under $login"
else
  [ "$owner" = "$login" ] \
    || stop "'$owner' is a user account other than yours ($login)" "  fix: create it as $login/$name, or under an organization you belong to"
  role=owner
fi

# ── 4 visibility ─────────────────────────────────────────────────────────
if gh api "repos/$repo" --jq .html_url >/dev/null 2>&1; then
  stop "$url already exists; the door creates new repositories only" "  fix: /plinth:floor-check $repo reads what it has"
fi
# An empty directory is where the user wants the project (`mkdir ~/x; cd ~/x;
# claude`, then the door), not a collision; anything in it is (#125). A listing
# that fails (a file, an unreadable directory) is not an empty one.
[ ! -e "$dir" ] || { entries="$(ls -A "$dir" 2>/dev/null)" && [ -z "$entries" ]; } \
  || stop "$dir already exists and is not an empty directory" "  fix: --dir=<another path>   (the door creates ~/<name> itself; an empty directory is fine)"
if git -C "$(dirname "$dir")" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  stop "$dir would be a repository inside the repository $(git -C "$(dirname "$dir")" rev-parse --show-toplevel)" "  fix: --dir=<a path outside it>"
fi
# The license is checked before creating, so a typo does not create and delete.
spdx="$(gh api "/licenses/$lic" --jq .spdx_id 2>/dev/null)" \
  || stop "unknown license: $lic (mit, apache-2.0, gpl-3.0, ... : https://api.github.com/licenses)"
# The archetype and license vocabularies live in the template's copier.yml; a
# copy here would drift. Both are read from it, because copier refuses a value
# outside its own choices (measured: `Invalid choice for 'license': 'GPL-3.0'
# is not in ['MIT', 'Apache-2.0']`) and that refusal lands after the repository
# exists, so an unsupported license would create and delete. Unreadable is not
# a stop: copier is the judge, and a refusal rolls back.
copier_yml="$(gh api "repos/$template_repo/contents/copier.yml?ref=$template_ref" --jq .content 2>/dev/null | base64 -d 2>/dev/null)" || copier_yml=""
choices_of() { sed -n "/^$1:/,/^[a-z_]/p" <<<"$copier_yml" | sed -n 's/^    [^:]*: \([A-Za-z0-9][A-Za-z0-9.-]*\)$/\1/p'; }
arch_choices="$(choices_of archetype)"; lic_choices="$(choices_of license)"
if [ -n "$arch_choices" ] && [ -n "$lic_choices" ]; then
  grep -qxF "$arch" <<<"$arch_choices" || stop "unknown archetype: $arch" "  the template accepts: $(tr '\n' ' ' <<<"$arch_choices")"
  grep -qxF "$spdx" <<<"$lic_choices" || stop "the template does not carry the license $spdx" "  it accepts: $(tr '\n' ' ' <<<"$lic_choices")"
else
  warn "could not read the template's archetype and license lists; copier decides (a refusal rolls back)"
fi

# The owner's shared community-health files. GitHub applies `<owner>/.github`'s
# copy to a repository that carries none of its own, so writing ours would
# replace the owner's convention without saying so. Asked here, before anything
# exists: a lookup that fails is not an answer, and the fix is to retry or to
# choose, not to guess. `--force-defaults` skips the question and renders ours.
#
# Two answers, not one. GitHub decides the pull-request template per file and
# the issue templates per folder: one local form -- or just a `config.yml` --
# stops the whole shared folder being inherited, and the two are never merged.
# `unknown: <why>` rather than a variable: these run in command substitutions,
# which are subshells, so an assignment inside would never reach the caller.
# "A failed lookup is not an answer" is only actionable if the reader learns
# what failed, and `why_unknown` peels the reason back off.
why_unknown() { case "$1" in unknown:*) printf '%s' "${1#unknown: }" ;; *) printf '(no message)' ;; esac; }
shared_of() { # <path>... -> yes (any present) | no (all absent) | unknown (any unreadable)
  local out seen_unknown=""
  for path in "$@"; do
    out="$(gh api "repos/$owner/.github/contents/$path" 2>&1 >/dev/null)" && { echo yes; return; }
    case "$out" in *"Not Found"*|*"404"*) ;; *) seen_unknown="$path: $out" ;; esac
  done
  [ -n "$seen_unknown" ] && echo "unknown: $seen_unknown" || echo no
}
# One template GitHub can actually offer, in the owner's shared folder.
# `.github/ISSUE_TEMPLATE` only: unlike a pull-request template, a default issue
# form is inherited from that path alone, and scripts/floor-check.py queries the
# same one. A name is not enough either -- an empty `bug.md` has the right
# suffix and GitHub offers nothing -- so a candidate is read before it counts.
usable_form() { # <text> <name> -> 0 when GitHub would offer it
  case "$2" in
    *.md) grep -qE '^name:[[:space:]]*[^[:space:]"'"'"']' <<<"$1" ;;
    *)    grep -q '^name:' <<<"$1" && grep -q '^description:' <<<"$1" && grep -q '^body:' <<<"$1" ;;
  esac
}
shared_config_only() { # -> yes when the shared folder holds a config and no form
  gh api "repos/$owner/.github/contents/.github/ISSUE_TEMPLATE" --jq '.[].name' 2>/dev/null |
    grep -qiE '^config\.(yml|yaml)$' && echo yes || echo no
}
shared_forms() { # -> yes (a template GitHub can offer) | no | unknown
  local listing name body enc
  listing="$(gh api "repos/$owner/.github/contents/.github/ISSUE_TEMPLATE" --jq '.[].name' 2>&1)" || {
    case "$listing" in *"Not Found"*|*"404"*) echo no ;;
      *) echo "unknown: .github/ISSUE_TEMPLATE: $listing" ;; esac; return; }
  while read -r name; do
    case "$name" in ""|config.yml|config.yaml) continue ;; *.yml|*.yaml|*.md) ;; *) continue ;; esac
    enc="$(gh api "repos/$owner/.github/contents/.github/ISSUE_TEMPLATE/$name" --jq .content 2>&1)" || {
      echo "unknown: .github/ISSUE_TEMPLATE/$name: $enc"; return; }
    body="$(base64 -d <<<"$enc" 2>&1)" || {
      echo "unknown: .github/ISSUE_TEMPLATE/$name: content could not be decoded ($body)"; return; }
    [ -n "$body" ] || continue
    usable_form "$body" "$name" && { echo yes; return; }
  done <<<"$listing"
  echo no
}
# GitHub applies default community-health files only from a *public* `.github`
# repository. A private one is readable through the API by whoever can see it,
# so believing that read would suppress our copies for something the new public
# repository never inherits.
shared_repo_public() { # -> yes | no | unknown
  local out
  out="$(gh api "repos/$owner/.github" --jq .visibility 2>&1)" || {
    case "$out" in *"Not Found"*|*"404"*) echo no ;; *) echo "unknown: $out" ;; esac; return; }
  [ "$out" = public ] && echo yes || echo no
}
# Three ways to end up rendering our own copies: the caller asked for them, the
# owner publishes no `.github`, or that repository is private and therefore
# never inherited from. Only a lookup that *failed* stops the run.
has_pr=no; has_forms=no
if [ "$force_defaults" = 0 ]; then
  vis="$(shared_repo_public)"
  case "$vis" in
    unknown*) stop "cannot read whether $owner/.github is public" \
               "  the API said: $(why_unknown "$vis")" \
               "  a failed lookup is not an answer: only a public .github repository is inherited from" \
               "  fix: run it again, or pass --force-defaults to render the template's own copies" ;;
    yes)
      # GitHub reads a community-health file from the root, `.github/` or
      # `docs/`. Checking only the root would miss an owner who used either of
      # the other two and write over the template this exists to protect.
      has_pr="$(shared_of PULL_REQUEST_TEMPLATE.md .github/PULL_REQUEST_TEMPLATE.md docs/PULL_REQUEST_TEMPLATE.md)"
      # A directory is not a template, and neither is a filename: the repository
      # would end up with no form anywhere and fail the floor check the box installs.
      has_forms="$(shared_forms)"
      # Computed first, because a `case` nested inside a command substitution is
      # hard to read and was written wrong once. `bash -n` on this machine's
      # bash 3.2 did not report that error; CI's bash 5 may well have. Do not
      # read that as a hole in the check -- read it as a reason not to nest.
      case "$has_pr" in unknown*) bad_lookup="$has_pr" ;; *) bad_lookup="$has_forms" ;; esac
      case "$has_pr$has_forms" in *unknown*)
        stop "cannot read whether $owner/.github publishes shared templates" \
          "  the API said: $(why_unknown "$bad_lookup")" \
          "  a failed lookup is not an answer: writing ours could replace yours, and skipping ours could leave none" \
          "  fix: run it again, or pass --force-defaults to render the template's own copies" ;;
      esac
      # A shared folder holding only a config is not forms, and rendering ours
      # replaces it: GitHub swaps the folder whole. Say so rather than let the
      # owner's contact links and blank-issue setting disappear quietly.
      [ "$has_forms" = no ] && [ "$(shared_config_only)" = yes ] &&
        warn "$owner/.github publishes an issue-template config but no form; the box renders its own forms and config, and yours will not apply to $repo"
      ;;
  esac
fi
own_note=""
[ "$has_pr" = yes ] && own_note="${own_note} pull-request template"
[ "$has_forms" = yes ] && own_note="${own_note} issue forms"
[ -n "$own_note" ] && echo "$owner/.github already publishes:${own_note}; the box will not write over them"

echo "create $repo (public, $spdx, $arch, as $role) from $template_repo@$template_ref in $dir; wall: ruleset + CodeQL; then the first pull request. rollback: $rollback"

# ── create ───────────────────────────────────────────────────────────────
created=0
cleanup() {
  [ "$created" = 1 ] || return 0
  # scripts/e2e.sh reads the start of this line, and of `done:` below, as the
  # proof that this run created the repository; keep both as they are.
  echo "the wall did not go up; deleting $url (the local copy $dir stays)" >&2
  if gh repo delete "$repo" --yes >/dev/null 2>&1; then
    echo "deleted $url" >&2
  else
    printf '!! ROLLBACK FAILED: %s EXISTS WITHOUT A WALL\n!! delete it now: %s/settings (bottom of the page), or: gh repo delete %s --yes\n' \
      "$url" "$url" "$repo" >&2
  fi
}
trap cleanup EXIT

gh repo create "$repo" --public >/dev/null
created=1

# Render. Name, owner, license and package directory are settled here: the
# owner renders pyproject's author and URLs, the license renders LICENSE, and
# copier.yml's validator refuses a name that makes no Python package before
# writing a file. Copier at its pinned version with nothing published after
# the pinned date, without the token, and before the repository exists on
# disk: nothing it writes may be a hook or a config line that a git command
# below, run with the token, would execute. Rendering into a plain directory
# and removing whatever `.git` it left, then initialising, leaves it nothing
# but content (Codex review on #118).
env -u GH_TOKEN -u GITHUB_TOKEN uvx --quiet --from "copier==$copier_version" --exclude-newer "$copier_newer" \
  copier copy --defaults --quiet \
  --data "project_name=$name" --data "owner=$owner" --data "license=$spdx" --data "archetype=$arch" \
  --data "owner_has_pr_template=$([ "$has_pr" = yes ] && echo true || echo false)" \
  --data "owner_has_issue_forms=$([ "$has_forms" = yes ] && echo true || echo false)" \
  --vcs-ref "$template_ref" "gh:$template_repo" "$dir" < /dev/null
rm -rf "$dir/.git"
# init -b main: an empty clone would follow init.defaultBranch, and a `master`
# there leaves the ruleset (~DEFAULT_BRANCH = main) guarding an empty branch.
git init -q -b main "$dir"
git -C "$dir" remote add origin "$url.git"
git -C "$dir" add -A
git -C "$dir" commit -q -m "chore: render $template_repo@$template_ref ($arch, $spdx)"

# The baseline goes straight to main, before the wall: after it nothing does.
# It is also the proof that the token can push (a pasted token with a trailing
# space passes the API, whose headers are trimmed, and fails git's HTTP Basic).
# A throwaway `__push-probe` branch used to carry that proof and went first;
# GitHub adopts the first branch pushed to an empty repository as the default,
# then refuses to delete it, and the wall went up on the probe while main was
# left open (#105). main goes first, and nothing is pushed before it.
if ! err="$(git -C "$dir" push -q -u origin main 2>&1)"; then
  printf 'cannot push to %s:\n%s\n  check: the token has the repo scope (or Contents: write), and no whitespace came along with a paste\n' "$url" "$err" >&2
  exit 1
fi
# Read the default branch back rather than assume the push set it: the ruleset
# below targets ~DEFAULT_BRANCH, so applying it while anything else is default
# leaves main unprotected -- the one thing the door promises.
#
# stdout only. `2>&1` here would fold anything gh writes to stderr into the
# value being compared, and the comparison decides whether a just-created
# repository is deleted; the reason is re-read on the failure path alone.
read_default() { gh api "repos/$repo" --jq .default_branch 2>/dev/null; }
default_branch="$(read_default)" || {
  printf 'could not read the default branch of %s:\n%s\n' "$url" "$(gh api "repos/$repo" 2>&1 >/dev/null)" >&2
  exit 1; }
# Not main: point it at main rather than roll back. main exists -- it was just
# pushed -- so this is one call, and deleting a repository whose only fault is
# which branch HEAD names is worse than the fault. Only a repair that does not
# take rolls back, which is what #105 asks for: the wall goes up on main or the
# repository does not survive.
if [ "$default_branch" != main ]; then
  warn "the default branch of $url was $default_branch, not main; pointing it at main before the wall goes up"
  gh api "repos/$repo" -X PATCH -f default_branch=main >/dev/null 2>&1 || true
  default_branch="$(read_default)" || default_branch="unreadable"
  [ "$default_branch" = main ] ||
    { printf 'the default branch of %s is %s, not main, and could not be changed; the ruleset guards ~DEFAULT_BRANCH, so the wall would go up on the wrong branch\n' "$url" "$default_branch" >&2; exit 1; }
fi

# Labels. The list is `labels.txt` beside this script, shared with
# scripts/floor-check.py so the two cannot drift (#84); the door creates them
# and the checker reports what a repository is missing.
#
# --force: a new repository already carries GitHub's default set, and `wontfix`
# is in both lists. Without it that collision warns on every single run.
# A label that still fails is named and left: labels are a convenience, not a
# wall stone, and rolling a repository back over one would delete a good wall.
grep -vE '^[[:space:]]*(#|$)' "$here/../labels.txt" | while IFS='|' read -r lbl color desc; do
  gh label create "$lbl" --repo "$repo" --color "$color" --description "$desc" --force >/dev/null 2>&1 ||
    warn "could not create the label $lbl; create it by hand:
  gh label create $lbl --repo $repo --color $color"
done

# ── the wall ─────────────────────────────────────────────────────────────
if ! err="$(gh api "repos/$repo/rulesets" -X POST --input "$here/../ruleset.json" 2>&1 >/dev/null)"; then
  printf 'could not apply the ruleset:\n%s\n' "$err" >&2
  exit 1
fi
gh api "repos/$repo" -X PATCH \
  -f 'security_and_analysis[secret_scanning][status]=enabled' \
  -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled' >/dev/null
gh api -X PUT "repos/$repo/vulnerability-alerts" >/dev/null
gh api -X PUT "repos/$repo/automated-security-fixes" >/dev/null
# Actions: SHA pins required, and only GitHub-owned actions plus plinth's own
# reusable workflow may run. Without `coolbress/plinth/*` the first CI run dies
# with startup_failure, no check name ever reports, and the repository is locked.
gh api -X PUT "repos/$repo/actions/permissions" -F enabled=true -f allowed_actions=selected -F sha_pinning_required=true >/dev/null
gh api -X PUT "repos/$repo/actions/permissions/selected-actions" \
  -F github_owned_allowed=true -F verified_allowed=false \
  -f 'patterns_allowed[]=coolbress/plinth/*' >/dev/null
# Merge settings agree with the ruleset, or there is no merge button at all.
# The squash commit is the pull request: its title (checked by ci / pr-title)
# and its description, not a list of the branch's commits (#72).
gh api "repos/$repo" -X PATCH -F allow_merge_commit=false -F allow_rebase_merge=false -F delete_branch_on_merge=true \
  -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY >/dev/null

# CodeQL: the ruleset requires its results through a code_scanning rule, so
# nothing merges until CodeQL has analysed the pull request, and default setup
# analyses only the languages it was enabled for. Enabled twenty seconds after
# the first push, it reported `languages: ["actions"]`: GitHub's language
# detection had not run yet, so the Python under src/ was never scanned while
# the wall said CodeQL enforced (coolbress/dividend_calendar, 2026-09-09, #120
# finding I; the consumer fixed it by hand with the languages spelled out). So
# the detection is waited for, and the list is spelled out: the box is Python
# in every archetype, and its workflows are Actions. Detection that never lists
# Python is a warning, not a stop: the wall stands either way, and the fix is
# the one command below.
deadline=$((SECONDS + first_pr_wait))
while ! gh api "repos/$repo/languages" --jq 'keys[]' 2>/dev/null | grep -qx Python; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    warn "GitHub has not detected Python in $url after $first_pr_wait s; enabling CodeQL default setup with actions and python anyway"
    break
  fi
  sleep 5
done
codeql_fix="gh api -X PATCH repos/$repo/code-scanning/default-setup -f 'languages[]=actions' -f 'languages[]=python'"
gh api -X PATCH "repos/$repo/code-scanning/default-setup" -f state=configured -f query_suite=default \
  -f 'languages[]=actions' -f 'languages[]=python' >/dev/null ||
  # Refused with the list (only measured after detection): enabled bare, which
  # analyses what GitHub has detected so far, and the fix is named.
  { warn "CodeQL default setup refused the language list; enabling it without one. Once it is configured, run: $codeql_fix"
    gh api -X PATCH "repos/$repo/code-scanning/default-setup" -f state=configured -f query_suite=default >/dev/null; }
codeql_enabled="$(date -u +%H:%M:%SZ)"

# ── the first pull request ───────────────────────────────────────────────
# One line, the one the tutorial names. Its workflow must start: a run that
# ends in startup_failure (allowlist, workflow file) reports no check name,
# so the wall would never open. That is a wall failure, and it rolls back.
# CodeQL must pick the pull request up as well: without an analysis the
# code_scanning rule never opens, and a pull request opened before default
# setup has finished configuring is never analysed; its head stays blocked
# until another is pushed. Measured three times: coolbress/plinth-e2e-20260909052724
# (2026-09-09, #62; the door had seen the `dynamic/github-code-scanning/codeql`
# workflow listed, the signal used until then, and the pull request opened at
# 05:28:13Z got no analysis), coolbress/plinth-e2e-34324833382 (2026-09-09, on the
# runner, the same), and coolbress/dividend_calendar (2026-09-09, #120: opened
# 08:31:55Z, default setup `configured` at 08:32:21Z, blocked until an empty
# commit pushed after that cleared the rule). The signal here is the one that
# comes after all of those: default setup reports `configured` with its
# `updated_at` set (that happens as its first run on main, the one enabling
# it queues, completes), that run is listed completed, its analyses of main
# are listed by the code-scanning API, and then a minute has passed. Measured
# on three repositories (#117): coolbress/plinth-e2e-34499093907 (2026-09-10,
# run completed 16:02:54Z, pull request pushed 16:02:56Z: not analysed, merged
# only after the driver's re-push); coolbress/plinth-e2e-34502351744
# (2026-09-10, completed 16:32:28Z, pushed 16:36:18Z: analysed 11 s later);
# coolbress/plinth-e2e-34546889124 (2026-09-11, analyses listed 00:33:15Z and
# 00:33:27Z, run completed 00:33:48Z, updated_at 00:33:49Z, pushed 00:34:54Z:
# analysed 9 s later, merged with no re-push). So the run completing is the
# event, and 2 s after it is too soon while 66 s is enough; the analyses are
# listed before the run completes and are not a signal on their own. Main's
# commit never carries a `CodeQL` check run, and the dynamic workflow is
# `active` the second it is enabled: neither is a signal. The languages are
# read back on the same call. Missing the signal only costs the wait: the
# re-push below covers that case. The times are printed as each is first
# seen, so a live run is its own record.
# ponytail: the minute is a margin, measured to hold at 66 s and to fail at
# 2 s; the boundary between is not measured.
deadline=$((SECONDS + first_pr_wait)); setup=""; main_run=""
for v in updated run analysis; do printf -v "seen_$v" '%s' ''; done
mark() { # <name> <value>: kept and printed whenever the value changes; null and empty are not values
  local var="seen_$1"
  [ -n "$2" ] && [ "$2" != null ] && [ "${!var}" != "$2" ] && { printf -v "$var" '%s' "$2"; echo "  $(date -u +%H:%M:%SZ) $1: $2"; }
  return 0
}
api_first() { # <path> <jq>: the first line, or nothing on any failure (a 404 body is not a value)
  local out; out="$(gh api "$1" --jq "$2" 2>/dev/null)" || return 0; head -1 <<<"$out"
}
while :; do
  setup="$(gh api "repos/$repo/code-scanning/default-setup" \
    --jq '"\(.state) \(.languages // [] | join(",") | if . == "" then "-" else . end) \(.updated_at)"' 2>/dev/null || true)"
  main_run="$(gh api -X GET "repos/$repo/actions/runs" -f branch=main -F per_page=20 \
    --jq '.workflow_runs[] | select(.path == "dynamic/github-code-scanning/codeql" and .status == "completed") | .updated_at' 2>/dev/null | head -1 || true)"
  [ "${setup%% *}" = configured ] && mark updated "$(awk '{print $3}' <<<"$setup")"
  mark run "$main_run"
  mark analysis "$(api_first "repos/$repo/code-scanning/analyses?ref=refs/heads/main&per_page=1" '.[] | "\(.created_at) \(.category)"')"
  [ "${setup%% *}" = configured ] && [ -n "$seen_updated" ] && [ -n "$main_run" ] && [ -n "$seen_analysis" ] && break
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "warning: CodeQL default setup has not completed its first analysis of main after $first_pr_wait s (state: ${setup%% *}, first run on main: ${main_run:-none}, analysis of main listed: ${seen_analysis:-none}); pushing the first pull request anyway" >&2
    break
  fi
  sleep 5
done
# LIVE TEST, reverted next: no minute, so the first push is missed and the door re-pushes.
read -r setup_state codeql_langs _ <<<"$setup"
echo "CodeQL default setup: enabled $codeql_enabled, ${setup_state:-unreadable} with languages [${codeql_langs:-}], first run on main completed ${main_run:-never}, analysis of main listed ${seen_analysis:-never}, first pull request pushed $(date -u +%H:%M:%SZ)"
[ -n "$codeql_langs" ] && ! grep -qw python <<<"$codeql_langs" &&
  warn "CodeQL default setup analyses [$codeql_langs] and not the Python under src/. fix: $codeql_fix"
branch="docs/first-pr"
git -C "$dir" switch -q -c "$branch"
echo 'Made with [plinth](https://github.com/coolbress/plinth).' >> "$dir/README.md"
git -C "$dir" commit -q -am "docs: first pull request through the wall"
git -C "$dir" push -q -u origin "$branch"
head_sha="$(git -C "$dir" rev-parse HEAD)"
# The body follows the shape the new repository actually ends up with, rather
# than one sentence: the door would otherwise honour the convention it just
# installed for every pull request except the one it writes itself. Where the
# owner publishes their own template the two headings are dropped, because
# theirs is the convention and this is not the place to impose ours.
if [ "$has_pr" = yes ]; then
  # Your template's own fields are not filled in here, and cannot be: the box
  # does not know what your headings ask for. It says so instead of pretending,
  # and this pull request exists to be merged in a minute, not to be a record.
  first_pr_body="Opened by /plinth:new-project to prove the wall: every required check must be green before the merge button enables. It adds one line to README.md and nothing else.

Not verified yet: at the moment this is written the checks have not run. That is what this pull request is for. A red check: open its Details and read the last lines of the log. Tutorial: $tutorial

This body does not follow $owner/.github's pull-request template, which this repository inherits: the box cannot answer fields it has not read. Rewrite it with \`gh pr edit $repo --body-file -\` if you want the record to match, or merge it as it is."
else
  first_pr_body="## What and why

Opened by /plinth:new-project to prove the wall. Every required check must be green before the merge button enables, so merging this is the proof that the wall stands and can be opened. It adds one line to README.md and changes nothing else.

## How it was verified

Nothing yet: at the moment this is written the checks have not run. That is what this pull request is for. A red check: open its Details and read the last lines of the log. Tutorial: $tutorial"
fi
pr_url="$(cd "$dir" && gh pr create --repo "$repo" --head "$branch" --title "docs: first pull request through the wall" \
  --body "$first_pr_body")"
# `seen` counts consecutive sightings and resets; `ever_seen` records that the
# run existed at all. Two questions, two variables: "is it stable" wants the
# streak, "did it ever appear" wants the flag, and answering the second with the
# first deletes a repository whose run was listed on the very poll that gave up
# (#108).
# CodeQL missing from the head after a while is answered here, once, with the
# recovery that was printed for the user to type until now: an empty commit
# pushed. A push made after default setup has settled is analysed every time
# it was tried (four recovery pushes and run 2, #62 #120 #117); the first push
# is the one it can miss, and the user should not have to know that. Ninety
# seconds: CodeQL appeared on a head 11 s after its push when it did at all.
deadline=$((SECONDS + first_pr_wait)); seen=0; ever_seen=0; codeql=0; repush=""
repush_at=$((SECONDS + (first_pr_wait < 90 ? first_pr_wait : 90))); repushed=0
while :; do
  runs="$(gh api -X GET "repos/$repo/actions/runs" -f "branch=$branch" -F per_page=20 \
    --jq '.workflow_runs[] | "\(.path) \(.status) \(.conclusion)"' 2>/dev/null || true)"
  if grep -q ' startup_failure$' <<<"$runs"; then
    { echo "the first pull request's workflow failed at startup (no check name will ever report):"
      sed 's/^/  /' <<<"$runs"; echo "  usual causes: the Actions allowlist, or an error in the workflow file"; } >&2
    exit 1
  fi
  # Accept once the run is past startup (queued for a runner, running, or done
  # without startup_failure), seen on two polls in a row.
  if grep -qE "^$template_ci (queued|in_progress|completed) " <<<"$runs"; then seen=$((seen + 1)); ever_seen=1; else seen=0; fi
  # CodeQL's runs do not list under the branch; its check runs on the head do.
  if [ "$codeql" = 0 ]; then
    names="$(gh api "repos/$repo/commits/$head_sha/check-runs" --jq '.check_runs[].name' 2>/dev/null || true)"
    grep -qE '^(CodeQL|Analyze \()' <<<"$names" && { codeql=1; echo "  $(date -u +%H:%M:%SZ) CodeQL on the pull request head: $(grep -E '^(CodeQL|Analyze \()' <<<"$names" | tr '\n' ' ')"; }
  fi
  [ "$seen" -ge 2 ] && [ "$codeql" = 1 ] && break
  if [ "$codeql" = 0 ] && [ "$repushed" = 0 ] && [ "$SECONDS" -ge "$repush_at" ]; then
    echo "  $(date -u +%H:%M:%SZ) CodeQL has not picked up the first pull request; pushing an empty commit once"
    git -C "$dir" commit -q --allow-empty -m 'ci: trigger code scanning' && git -C "$dir" push -q
    head_sha="$(git -C "$dir" rev-parse HEAD)"; repushed=1
    sleep 5; continue   # the new head is read at least once before the deadline can end the wait
  fi
  if [ "$SECONDS" -ge "$deadline" ]; then
    # No CI run at all is a misconfiguration (allowlist, workflow file): a wall
    # failure. A run that appeared but was never seen twice running is not --
    # it exists, so its checks will report, and deleting the repository over a
    # streak that did not close is the wrong direction to be wrong in.
    [ "$ever_seen" = 1 ] || { echo "no run of $template_ci appeared within $first_pr_wait s for $branch; its checks would never report" >&2; exit 1; }
    [ "$seen" -ge 2 ] || echo "warning: a run of $template_ci appeared but was not listed on two polls in a row within $first_pr_wait s; the wall stands and its checks will report" >&2
    # No CodeQL run is timing on GitHub's side: the wall stands, and the next
    # push is analysed within a minute. Say so instead of deleting the repository.
    # Guarded on `codeql`, not implied by reaching here: a short streak now
    # arrives at this line too, and CodeQL may well have been found already.
    if [ "$codeql" = 0 ]; then
      echo "warning: CodeQL has not picked up the first pull request within $first_pr_wait s, $([ "$repushed" = 1 ] && echo "one empty commit pushed" || echo "no re-push yet") (check runs on its head: $(tr '\n' ' ' <<<"$names")); the merge stays blocked until it does" >&2
      repush="    if it stays blocked, push once more: cd $dir && git commit --allow-empty -m 'ci: trigger code scanning' && git push"
    fi
    break
  fi
  sleep 5
done

created=0; trap - EXIT
cat <<EOF
done: $url (public, $spdx, $arch, $template_repo@$template_ref)
  local: $dir
  first pull request: $pr_url
    wait for every check to turn green, then merge (squash). A red check: open its Details and read the last lines of the log. Tutorial: $tutorial
${repush:+$repush
}  next: cd $dir && claude
EOF
[ "${PLINTH_TOKEN_SOURCE:-}" != prompt ] || \
  echo "  if your everyday gh token is fine-grained with selected repositories, add $name to it: https://github.com/settings/personal-access-tokens"
