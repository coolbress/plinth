# shellcheck shell=bash
# Helpers both doors use: scripts/new-project.sh (GitHub) and
# scripts/new-project-gitlab.sh (GitLab.com, #353). Sourced, never run.

# A preflight stop: the message and its fix on stderr, exit 2, nothing created.
# The misses collected before it (miss, below) come first, so one run names
# every item that is missing, not only the first (#1067).
stop() {
  local total=$((n_miss + 1))
  [ "$total" -lt 2 ] || printf '%s things to fix; nothing was created:\n' "$total" >&2
  [ "$n_miss" = 0 ] || printf '%s\n' "${misses[@]}" >&2
  printf '%s\n' "$@" >&2; exit 2
}
# miss <line>...: a missing tool, login, scope or identity, kept for one stop
# that names them all (#1067). The first line is the problem, the indented ones
# its fix, as for stop. misses_stop stops with them when there are any.
misses=(); n_miss=0
miss() { misses+=("$@"); n_miss=$((n_miss + 1)); }
misses_stop() {
  [ "$n_miss" != 0 ] || return 0
  [ "$n_miss" -lt 2 ] || printf '%s things to fix; nothing was created:\n' "$n_miss" >&2
  printf '%s\n' "${misses[@]}" >&2; exit 2
}
# git_identity: a miss when git cannot name the author or the committer of the
# first commit. The GitHub door creates the repository before it commits, so a
# machine where git cannot work out an identity would fail after the create;
# the GitLab door commits first (#1067). Read in /, where no repository's own
# configuration applies: the doors commit in a new folder, with the global one.
git_identity() {
  local v err
  for v in GIT_AUTHOR_IDENT GIT_COMMITTER_IDENT; do
    if ! err="$(git -C / var "$v" 2>&1 >/dev/null)"; then
      miss "git cannot tell who makes the first commit ($(grep -m1 '^fatal:' <<<"$err" || echo "git var $v failed"))" \
        "  fix: git config --global user.name \"Your Name\"" \
        "  fix: git config --global user.email \"you@example.com\""
      return 0
    fi
  done
}
# name_fits <name>: stops when the repository name (the owner or namespace not
# counted) is longer than 46 characters. The template names the Python package
# after it, and from 47 lines of the rendered code pass ruff's 100, so the new
# project's own lint check is red from its first commit
# (coolbress/plinth-template#318). The door holds the limit, not the template's
# validator: `copier update` validates the recorded answer again, and would
# refuse an existing project with a longer name (coolbress/plinth-template#323).
name_limit=46
name_fits() {
  [ "${#1}" -le "$name_limit" ] || stop "the name is ${#1} characters; the limit is $name_limit: a longer name makes the new project's own lint check fail, because its Python package takes the same name and lines of the rendered code then pass the 100 characters the check allows; nothing was read or created" \
    "  fix: choose a name of $name_limit characters or fewer"
}
warn() { printf 'warning: %s\n' "$1" >&2; }
# below <floor> <version>: true when version sorts before floor.
below() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" != "$1" ]; }
# choices_of <question>: the values copier.yml offers for it, one per line,
# from the text in $copier_yml, which the door sets before calling it.
# shellcheck disable=SC2154  # copier_yml is the caller's
choices_of() { sed -n "/^$1:/,/^[a-z_]/p" <<<"$copier_yml" | sed -n 's/^    [^:]*: \([A-Za-z0-9][A-Za-z0-9.-]*\)$/\1/p'; }
# read_into <var> <step> <command...>: runs the command and stores its stdout
# in <var>. When it fails, <var> is empty, read_fault says "<step> failed: " and
# the command's first stderr line, cut to 200 characters, and it returns the
# command's exit status (#629). gh's and curl's errors carry the URL and the
# HTTP status, never a token. The callers run under set -e: call it where that
# is off (`if`, `||`).
read_fault=""
read_into() {
  local var="$1" step="$2" err out rc=0 msg; shift 2
  err="$(mktemp)" || { printf -v "$var" '%s' ''; read_fault="$step failed: no temporary file for its error (mktemp)"; return 1; }
  out="$("$@" 2>"$err")" || rc=$?
  if [ "$rc" -eq 0 ]; then printf -v "$var" '%s' "$out"; read_fault=""
  else
    msg="$(head -1 "$err" | cut -c1-200)"; [ -n "$msg" ] || msg="exit $rc, nothing on stderr"
    printf -v "$var" '%s' ''; read_fault="$step failed: $msg"   # not '': bash 3.2 then leaves it unset
  fi
  rm -f "$err"; return "$rc"
}
# unread_why: the one line that says why $copier_yml yielded no choices, for
# the warning (GitHub door) or the stop (GitLab door) that follows: the step
# read_into saw fail and its error, or, when every step succeeded, that the
# text carries no choices where choices_of looks, which is a change of
# copier.yml's shape, not a network fault (#629).
# shellcheck disable=SC2154  # template_sha is the caller's
unread_why() {
  if [ -n "$read_fault" ]; then printf '%s\n' "$read_fault"
  else printf 'the read succeeded, but copier.yml at %s lists no archetype or license choices where the door looks: its shape changed, not the network\n' "$template_sha"; fi
}
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
