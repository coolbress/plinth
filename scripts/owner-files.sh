#!/usr/bin/env bash
# Which community-health files the owner's public `.github` repository
# publishes for a new repository to inherit, beyond the pull-request template
# and the issue forms that scripts/new-project.sh reads itself (#772).
# Read-only. /plinth:new-project runs it before it asks about a code of
# conduct, and new-project.sh runs it before it renders.
#
#   owner-files.sh [<owner>]    # default: the gh login
#
# Prints two lines, each `yes`, `no` or `unknown: <why>`:
#   code_of_conduct: ...
#   security_policy: ...
# GitHub applies these from a public `.github` repository only, and reads
# each from its root, `.github/` or `docs/`; a private or missing `.github`
# is `no` for both. A failed lookup is `unknown`, never `no`: the caller
# stops or asks rather than guess. Exit 0 whenever it printed both lines.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/shared-github.sh
. "$here/lib/shared-github.sh"
[ $# -le 1 ] || { echo "usage: owner-files.sh [<owner>]" >&2; exit 2; }
gh_read() { # <gh api args>... -> ok:<output> | err:<output>
  local out
  if out="$(gh api "$@" 2>&1)"; then printf 'ok:%s' "$out"; else printf 'err:%s' "$out"; fi
}
owner="${1:-}"
if [ -z "$owner" ]; then
  login="$(gh_read user --jq .login)"
  case "$login" in
    ok:?*) owner="${login#ok:}" ;;
    *) why="${login#err:}"; why="${why#ok:}"
       printf 'code_of_conduct: unknown: the gh login could not be read (%s)\nsecurity_policy: unknown: the gh login could not be read (%s)\n' "${why:-no login}" "${why:-no login}"
       exit 0 ;;
  esac
fi
vis="$(shared_repo_public "$(gh_read "repos/$owner/.github" --jq .visibility)")"
case "$vis" in
  unknown*) printf 'code_of_conduct: unknown: %s/.github: %s\nsecurity_policy: unknown: %s/.github: %s\n' \
              "$owner" "$(why_unknown "$vis")" "$owner" "$(why_unknown "$vis")"; exit 0 ;;
  no) printf 'code_of_conduct: no\nsecurity_policy: no\n'; exit 0 ;;
esac
for pair in code_of_conduct:CODE_OF_CONDUCT.md security_policy:SECURITY.md; do
  key="${pair%%:*}"; file="${pair#*:}"; answers=()
  for path in "$file" ".github/$file" "docs/$file"; do
    answers+=("$path" "$(gh_read "repos/$owner/.github/contents/$path" --silent)")
  done
  printf '%s: %s\n' "$key" "$(shared_of "${answers[@]}")"
done
