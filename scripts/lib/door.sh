# shellcheck shell=bash
# Helpers both doors use: scripts/new-project.sh (GitHub) and
# scripts/new-project-gitlab.sh (GitLab.com, #353). Sourced, never run.

# A preflight stop: the message and its fix on stderr, exit 2, nothing created.
stop() { printf '%s\n' "$@" >&2; exit 2; }
warn() { printf 'warning: %s\n' "$1" >&2; }
# below <floor> <version>: true when version sorts before floor.
below() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" != "$1" ]; }
# choices_of <question>: the values copier.yml offers for it, one per line,
# from the text in $copier_yml, which the door sets before calling it.
# shellcheck disable=SC2154  # copier_yml is the caller's
choices_of() { sed -n "/^$1:/,/^[a-z_]/p" <<<"$copier_yml" | sed -n 's/^    [^:]*: \([A-Za-z0-9][A-Za-z0-9.-]*\)$/\1/p'; }
# template_pinned: stop unless $template_ref names $template_sha on GitHub now,
# the commit this plinth was tested with (#519). Read with git, which both
# doors already need, through an annotated tag to its commit. A tag that is
# gone, or a github.com that does not answer, is a stop too: what would be
# rendered is then not known.
# shellcheck disable=SC2154  # template_repo, template_ref and template_sha are the caller's
template_pinned() {
  local now
  now="$(GIT_TERMINAL_PROMPT=0 git ls-remote "https://github.com/$template_repo" \
           "refs/tags/$template_ref" "refs/tags/$template_ref^{}" 2>/dev/null \
         | awk -v t="refs/tags/$template_ref" '$2 == t "^{}" { p = $1 } $2 == t { d = $1 } END { print (p != "" ? p : d) }')" || now=""
  [ -n "$now" ] || stop "could not read which commit $template_repo@$template_ref names (git ls-remote https://github.com/$template_repo)" \
    "  fix: run it again; it needs github.com"
  [ "$now" = "$template_sha" ] || stop "the template tag $template_repo@$template_ref names commit $now, not $template_sha, the one this plinth was tested with" \
    "  the tag moved after this plinth was released; nothing was created" \
    "  fix: none here; report it at https://github.com/coolbress/plinth/issues"
}
