# shellcheck shell=bash
# sq, for every script that prints a command a person pastes into a shell:
# new-project.sh, new-project-gitlab.sh, template-update.sh and
# merge-when-green.sh. Sourced, never run.

# sq <value>: the value as one shell word. A value of only letters, digits and
# ._/=:@%+,- is printed as it is; anything else, the empty value included, goes
# inside single quotes, a single quote in it as '\''. Not printf %q: macOS's
# bash 3.2 %q escapes some bytes of Hangul and prints the rest raw, and the
# line no longer shows as text (#923, #1065). Inside single quotes every byte
# is printed as typed, so the line reads on a screen and pastes back the same.
sq() {
  case "$1" in
    ''|*[!A-Za-z0-9._/=:@%+,-]*) local s=${1//\'/\'\\\'\'}; printf "'%s'" "$s" ;;
    *) printf '%s' "$1" ;;
  esac
}
