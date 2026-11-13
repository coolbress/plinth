# shellcheck shell=bash
# Whether a gh credential reaches the repository's Administration, which is
# what lets an agent edit or delete its rulesets and change its checks (#300,
# #922). One copy for scripts/new-project.sh, which asks it of the new
# repository once setup is done, and scripts/guide-state.sh, which asks it
# past the first merge to say whether the token step is done.
#
# `permissions.admin` is the account's role, not the token's reach: a
# fine-grained token with Administration at No access answered `true` for the
# owner, and a read needing Administration answered it 403 (measured
# 2026-09-29; docs/how-to/give-the-agent-a-token.md, step 3). So the role
# decides only when it is a standard one below admin on a personal account's
# repository (in an organization, an organization role can grant "Edit
# repository rules" beside it); under admin, a classic or OAuth token's `repo`
# or `public_repo` scope carries the role, and a fine-grained one (no
# X-OAuth-Scopes header) is asked a read that needs Administration. A 200
# there is read access at least, and whether it can write, which editing the
# ruleset needs, cannot be read. Nothing reads a token: only the role, the
# headers gh returns, and that one read.
#
#   admin_reach <gh command> <owner/repo> <owner kind|?> <user headers|?>
#
# <gh command> is gh, or a function that runs it as the credential to ask.
# <owner kind> is the owner's `type` (User or Organization); `?` reads it,
# only when the role needs it. <user headers> are the response headers of
# `gh api -i user` for that credential, empty when they could not be read;
# `?` reads them, only under admin. Out, one line: admin, none, read, or
# `unknown: <why>`.
admin_reach() {
  local gh_cmd="$1" repo="$2" kind="$3" headers="$4" role scopes probe
  if ! role="$("$gh_cmd" api "repos/$repo" --jq '"\(.permissions.admin) \(.role_name)"' 2>&1)"; then
    echo "unknown: the role on $repo was not read ($(tail -1 <<<"$role" | tr '\t' ' '))"; return
  fi
  # On success the answer is the last line, whatever gh warned above it.
  role="$(tail -1 <<<"$role")"
  case "$role" in
    "false read"|"false triage"|"false write"|"false maintain")
      if [ "$kind" = "?" ]; then
        kind="$("$gh_cmd" api "users/${repo%%/*}" --jq .type 2>/dev/null | tail -1)" || kind=""
      fi
      case "$kind" in
        Organization) echo "unknown: the role on $repo is ${role#false }, in an organization, whose own roles can grant editing its rules" ;;
        "") echo "unknown: the role on $repo is ${role#false }, and whether its owner is an organization was not read" ;;
        *) echo none ;;
      esac ;;
    "true "*)
      if [ "$headers" = "?" ]; then
        headers="$("$gh_cmd" api -i user 2>/dev/null | tr -d '\r' | sed '/^$/,$d')" || headers=""
      fi
      if scopes="$(awk 'tolower($1)=="x-oauth-scopes:"{sub(/^[^:]*: ?/,""); print; found=1; exit} END{exit !found}' <<<"$headers")"; then
        if grep -qE "(^|,) *(repo|public_repo) *(,|$)" <<<"$scopes"; then echo admin
        else echo "unknown: its scopes ($scopes) carry neither repo nor public_repo"; fi
      elif probe="$("$gh_cmd" api "repos/$repo/actions/permissions" --silent 2>&1)"; then
        echo read
      else
        case "$probe" in
          *"HTTP 403"*"not accessible"*|*"not accessible"*"HTTP 403"*) echo none ;;
          *) echo "unknown: the Administration read on $repo failed ($(tail -1 <<<"$probe" | tr '\t' ' '))" ;;
        esac
      fi ;;
    *) echo "unknown: the role on $repo was not read (the answer was '$role')" ;;
  esac
}
