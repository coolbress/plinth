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
