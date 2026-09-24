# shellcheck shell=bash
# The owner's shared community-health files: which of `<owner>/.github`'s
# copies apply to a new repository. Sourced by scripts/new-project.sh, which
# fetches with `gh api` and passes each answer in; nothing here reads the
# network, so tests/shared-github-cases.sh runs every decision on fixtures.
#
# A fetched answer is `ok:<output>` when `gh api` succeeded and `err:<output>`
# when it failed, `<output>` being gh's own words. A 404 is an answer (absent);
# any other failure is not, and becomes `unknown: <why>`.
#
# Two answers, not one. GitHub decides the pull-request template per file and
# the issue templates per folder: one local form -- or just a `config.yml` --
# stops the whole shared folder being inherited, and the two are never merged.
# `unknown: <why>` rather than a variable: these run in command substitutions,
# which are subshells, so an assignment inside would never reach the caller.
# "A failed lookup is not an answer" is only actionable if the reader learns
# what failed, and `why_unknown` peels the reason back off.
why_unknown() { case "$1" in unknown:*) printf '%s' "${1#unknown: }" ;; *) printf '(no message)' ;; esac; }
shared_of() { # <path> <fetched>... -> yes (any present) | no (all absent) | unknown (any unreadable)
  local seen_unknown=""
  while [ "$#" -ge 2 ]; do
    case "$2" in
      ok:*) echo yes; return ;;
      err:*"Not Found"*|err:*"404"*) ;;
      err:*) seen_unknown="$1: ${2#err:}" ;;
      *) seen_unknown="$1: not a fetched answer" ;;
    esac
    shift 2
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
# `config-only` comes from the same listing as the forms answer: a second read
# of the folder could fail after the first succeeded, and a failed read is not
# "no config" (#101). The listing is the names, one per line; each candidate's
# content (base64, as the contents API gives it) follows as a <name> <fetched> pair.
shared_forms() { # <listing fetched> [<name> <content fetched>]... -> yes (a template GitHub can offer) | no | config-only | unknown
  local listing="$1" name body enc config=no i
  shift
  case "$listing" in
    ok:*) listing="${listing#ok:}" ;;
    err:*"Not Found"*|err:*"404"*) echo no; return ;;
    *) echo "unknown: .github/ISSUE_TEMPLATE: ${listing#err:}"; return ;;
  esac
  while read -r name; do
    case "$name" in "") continue ;; config.yml|config.yaml) config=yes; continue ;; *.yml|*.yaml|*.md) ;; *) continue ;; esac
    enc=""
    for ((i = 1; i < $#; i += 2)); do [ "${!i}" = "$name" ] && { i=$((i + 1)); enc="${!i}"; break; }; done
    case "$enc" in
      ok:*) enc="${enc#ok:}" ;;
      err:*) echo "unknown: .github/ISSUE_TEMPLATE/$name: ${enc#err:}"; return ;;
      *) echo "unknown: .github/ISSUE_TEMPLATE/$name: not fetched"; return ;;
    esac
    body="$(base64 -d <<<"$enc" 2>&1)" || {
      echo "unknown: .github/ISSUE_TEMPLATE/$name: content could not be decoded ($body)"; return; }
    [ -n "$body" ] || continue
    usable_form "$body" "$name" && { echo yes; return; }
  done <<<"$listing"
  [ "$config" = yes ] && echo config-only || echo no
}
# GitHub applies default community-health files only from a *public* `.github`
# repository. A private one is readable through the API by whoever can see it,
# so believing that read would suppress our copies for something the new public
# repository never inherits.
shared_repo_public() { # <fetched visibility> -> yes | no | unknown
  case "$1" in
    ok:public) echo yes ;;
    ok:*) echo no ;;
    err:*"Not Found"*|err:*"404"*) echo no ;;
    *) echo "unknown: ${1#err:}" ;;
  esac
}
