#!/usr/bin/env bash
# The door: create a repository with the wall already up, or create nothing.
#
#   new-project.sh [<owner>/]<name> [--license=<spdx>] [--archetype=<a>] [--dir=<path>]
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
# before the wall), labels, CodeQL, ruleset, secret scanning, Dependabot, Actions
# allowlist, squash only, and the first pull request, whose workflow must start.
#
# fail-closed: any failure after creation deletes the repository. Deletion is
# best effort; when it fails the URL is printed loudly. The local clone stays.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The box, at the one tag this version of plinth is tested with, and the
# workflow file it ships (the first pull request's run is looked up by it).
# Raising the tag is the only edit here; when the box becomes
# coolbress/plinth-template the two interim allowlist patterns below go too.
template_repo="coolbress/project-template"
template_ref="v2.18.0"
template_ci=".github/workflows/ci.yml"
claude_floor="2.1.234"
tutorial="https://github.com/coolbress/plinth/blob/main/docs/tutorials/getting-started.md"

usage="usage: new-project.sh [<owner>/]<name> [--license=<spdx>] [--archetype=<a>] [--dir=<path>]"
target=""; lic=mit; arch=cli; dir=""; private=0
for a in "$@"; do case "$a" in
  --private)     private=1 ;;
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
  || stop "'$target' is not <owner>/<name> (letters, digits, . _ -)"
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
    "  fix: run the door with an admin token, typed at a prompt (never on the command line):" \
    "    $here/with-admin-token.sh $here/new-project.sh $*" \
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
[ ! -e "$dir" ] || stop "$dir already exists" "  fix: --dir=<another path>"
if git -C "$(dirname "$dir")" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  stop "$dir would be a repository inside the repository $(git -C "$(dirname "$dir")" rev-parse --show-toplevel)" "  fix: --dir=<a path outside it>"
fi
# The license is checked before creating, so a typo does not create and delete.
spdx="$(gh api "/licenses/$lic" --jq .spdx_id 2>/dev/null)" \
  || stop "unknown license: $lic (mit, apache-2.0, gpl-3.0, ... : https://api.github.com/licenses)"
# The archetype list lives in the template's copier.yml; a copy here would drift.
# Unreadable is not a stop: copier is the judge, and a refusal rolls back.
choices="$(gh api "repos/$template_repo/contents/copier.yml?ref=$template_ref" --jq .content 2>/dev/null \
  | base64 -d 2>/dev/null | sed -n '/^archetype:/,/^[a-z_]/p' | sed -n 's/^    [^:]*: \([a-z][a-z0-9-]*\)$/\1/p')" || choices=""
if [ -n "$choices" ]; then
  grep -qxF "$arch" <<<"$choices" || stop "unknown archetype: $arch" "  the template accepts: $(tr '\n' ' ' <<<"$choices")"
else
  warn "could not read the template's archetype list; copier decides (a refusal rolls back)"
fi

echo "create $repo (public, $spdx, $arch, as $role) from $template_repo@$template_ref in $dir; wall: ruleset + CodeQL; then the first pull request. rollback: $rollback"

# ── create ───────────────────────────────────────────────────────────────
created=0
cleanup() {
  [ "$created" = 1 ] || return 0
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
# init -b main: an empty clone would follow init.defaultBranch, and a `master`
# there leaves the ruleset (~DEFAULT_BRANCH = main) guarding an empty branch.
git init -q -b main "$dir"
git -C "$dir" remote add origin "$url.git"

# Render. Name, license and package directory are settled here (copier.yml's
# validator refuses names that make no Python package, before writing a file).
uvx --quiet copier copy --defaults --quiet \
  --data "project_name=$name" --data "license=$spdx" --data "archetype=$arch" \
  --vcs-ref "$template_ref" "gh:$template_repo" "$dir" < /dev/null
# The box ships MIT; another choice gets GitHub's official text.
[ "$spdx" = MIT ] || gh api "/licenses/$lic" --jq .body > "$dir/LICENSE"
git -C "$dir" add -A
git -C "$dir" commit -q -m "chore: render $template_repo@$template_ref ($arch, $spdx)"

# Prove push works before doing the rest (a pasted token with a trailing space
# passes the API, whose headers are trimmed, and fails git's HTTP Basic).
probe="__push-probe"
if ! err="$(git -C "$dir" push -q origin "HEAD:refs/heads/$probe" 2>&1)"; then
  printf 'cannot push to %s:\n%s\n  check: the token has the repo scope (or Contents: write), and no whitespace came along with a paste\n' "$url" "$err" >&2
  exit 1
fi
git -C "$dir" push -q origin --delete "$probe" || true
# The baseline goes straight to main, before the wall: after it nothing does.
git -C "$dir" push -q -u origin main

# Labels: the PR-type labels the template's label workflow applies, `task` for
# the issue form, and the five triage labels mattpocock-skills expects.
{ for lbl in feat fix docs style refactor perf test build ci chore revert breaking; do echo "$lbl:ededed:PR title type"; done
  echo "task:0052cc:One thing to build"
  for lbl in needs-triage needs-info ready-for-agent ready-for-human wontfix; do echo "$lbl:c5def5:Triage (mattpocock-skills)"; done
} | while IFS=: read -r lbl color desc; do
  gh label create "$lbl" --repo "$repo" --color "$color" --description "$desc" >/dev/null 2>&1 || true
done

# ── the wall ─────────────────────────────────────────────────────────────
# CodeQL first: the ruleset requires the `CodeQL` check, and with default setup
# off that name never reports and the repository is locked from its first PR.
gh api -X PATCH "repos/$repo/code-scanning/default-setup" -f state=configured -f query_suite=default >/dev/null
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
# Interim, tied to template_ref: v2.18.0's ci.yml and label.yml still call
# coolbress/workflows, which uses setup-uv. Both patterns go with the next tag.
gh api -X PUT "repos/$repo/actions/permissions" -F enabled=true -f allowed_actions=selected -F sha_pinning_required=true >/dev/null
gh api -X PUT "repos/$repo/actions/permissions/selected-actions" \
  -F github_owned_allowed=true -F verified_allowed=false \
  -f 'patterns_allowed[]=coolbress/plinth/*' \
  -f 'patterns_allowed[]=coolbress/workflows/*' \
  -f 'patterns_allowed[]=astral-sh/setup-uv@*' >/dev/null
# Merge settings agree with the ruleset, or there is no merge button at all.
gh api "repos/$repo" -X PATCH -F allow_merge_commit=false -F allow_rebase_merge=false -F delete_branch_on_merge=true >/dev/null

# ── the first pull request ───────────────────────────────────────────────
# One line, the one the tutorial names. Its workflow must start: a run that
# ends in startup_failure (allowlist, workflow file) reports no check name,
# so the wall would never open. That is a wall failure, and it rolls back.
branch="docs/first-pr"
git -C "$dir" switch -q -c "$branch"
echo 'Made with [plinth](https://github.com/coolbress/plinth).' >> "$dir/README.md"
git -C "$dir" commit -q -am "docs: first pull request through the wall"
git -C "$dir" push -q -u origin "$branch"
pr_url="$(cd "$dir" && gh pr create --repo "$repo" --head "$branch" --title "docs: first pull request through the wall" \
  --body "Opened by /plinth:new-project to prove the wall: every required check must be green before the merge button enables. A red check: open its Details and read the last lines of the log. Tutorial: $tutorial")"
deadline=$((SECONDS + 120)); seen=0
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
  if grep -qE "^$template_ci (queued|in_progress|completed) " <<<"$runs"; then seen=$((seen + 1)); [ "$seen" -ge 2 ] && break; else seen=0; fi
  [ "$SECONDS" -lt "$deadline" ] || { echo "no run of $template_ci appeared within 120 s for $branch; its checks would never report" >&2; exit 1; }
  sleep 5
done

created=0; trap - EXIT
cat <<EOF
done: $url (public, $spdx, $arch, $template_repo@$template_ref)
  local: $dir
  first pull request: $pr_url
    wait for every check to turn green, then merge (squash). A red check: open its Details and read the last lines of the log. Tutorial: $tutorial
  next: cd $dir && claude
EOF
[ "${PLINTH_TOKEN_SOURCE:-}" != prompt ] || \
  echo "  if your everyday gh token is fine-grained with selected repositories, add $name to it: https://github.com/settings/personal-access-tokens"
