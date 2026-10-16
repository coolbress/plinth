#!/usr/bin/env bash
# The upgrade path's driver, `scripts/e2e-upgrade.sh` (#519), against a mocked
# `gh`, a mocked copier and a stub template-update.sh. No network, nothing
# created.
#
# Two properties: exit 0 only when the tested pin landed on every plinth
# `uses:` line and in .copier-answers.yml; and any other exit leaves no
# repository behind without naming it. template-update.sh itself is tested
# in template-update-cases.sh; here it is a stub that writes what an update
# would, with the pins a case asks for.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
real_git="$(command -v git)"
work="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/tmp"
export TMPDIR="$work/tmp"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
old_pin="$(printf '%040d' 1)"; new_pin="$(printf '%040d' 2)"
export OLD_PIN="$old_pin" NEW_PIN="$new_pin" REAL_GIT="$real_git"

# A plinth checkout: release v0.9.0 pinned template v1.0.0 with copier 9.0.0;
# this commit pins v1.1.0. `same` is one whose every release kept the tag;
# `walk` has v0.8.0 at v1.0.0, then v0.9.0 at v1.0.5, a tag tested with the
# same plinth commit as v1.1.0 (the mock's copier.yml says so).
door() { # <ref> <copier version>
  printf 'template_repo="coolbress/plinth-template"\ntemplate_ref="%s"\ncopier_version="%s"\ncopier_newer="2026-01-01"\n' "$1" "$2"
}
plinth() { # <dir> <head ref> <tag>=<ref>... (oldest first)
  local dir="$1" head="$2" t; shift 2
  mkdir -p "$dir/scripts"; "$real_git" init -q -b main "$dir"
  for t in "$@"; do
    door "${t#*=}" 9.0.0 > "$dir/scripts/new-project.sh"
    "$real_git" -C "$dir" add -A && "$real_git" -C "$dir" commit -q -m "${t%%=*}" && "$real_git" -C "$dir" tag "${t%%=*}"
  done
  set -- "$dir" "" "$head"
  door "$3" 9.18.2 > "$1/scripts/new-project.sh"
  "$real_git" -C "$1" commit -q -am new
  cp "$root/scripts/e2e-upgrade.sh" "$1/scripts/"
  cat > "$1/scripts/template-update.sh" <<'STUB'
#!/usr/bin/env bash
# What template-update.sh would leave: a plan, then a worktree beside the
# repository, its branch pushed, a draft pull request.
printf 'template-update %s\n' "$*" >> "$GH_LOG"
top="$(git rev-parse --show-toplevel)"
if [ $# = 0 ]; then
  [ "${PLAN_RC:-0}" = 0 ] || { echo "template-update: no update command"; exit "$PLAN_RC"; }
  echo "Template:   v1.0.0 -> v1.1.0"
  printf '  %s --apply %s --plinth-pin live\n  %s --apply %s --plinth-pin tested\n' "$0" "$(git rev-parse HEAD)" "$0" "$(git rev-parse HEAD)"
  exit 0
fi
[ "${APPLY_RC:-0}" = 0 ] || { echo "copier left conflicts"; exit "$APPLY_RC"; }
wt="$(dirname "$top")/$(basename "$top")-template-v1.1.0"
git -C "$top" worktree add -q -b chore/template-v1.1.0 "$wt"
printf '_commit: %s\nplinth_sha: %s\n' "${TU_TAG:-v1.1.0}" "${TU_ANSWERS:-$NEW_PIN}" > "$wt/.copier-answers.yml"
printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n' "${TU_CI:-$NEW_PIN}" > "$wt/.github/workflows/ci.yml"
[ -z "${TU_YAML:-}" ] || printf 'jobs:\n  extra:\n    uses: coolbress/plinth/.github/workflows/pr-review.yml@%s\n' "$TU_YAML" > "$wt/.github/workflows/extra.yaml"
if [ "${TU_NOLABEL:-0}" = 1 ]; then rm "$wt/.github/workflows/label.yml"
else printf 'jobs:\n  label:\n    uses: coolbress/plinth/.github/workflows/pr-label.yml@%s\n# uses: coolbress/plinth/.github/workflows/pr-review.yml@<sha>\n' "${TU_LABEL:-$NEW_PIN}" > "$wt/.github/workflows/label.yml"; fi
git -C "$wt" commit -q -am update
echo "Draft pull request: https://github.com/tester/x/pull/1"
STUB
  chmod +x "$1/scripts/"*.sh
}
plinth "$work/plinth" v1.1.0 v0.9.0=v1.0.0
plinth "$work/same" v1.1.0 v0.9.0=v1.1.0
plinth "$work/walk" v1.1.0 v0.8.0=v1.0.0 v0.9.0=v1.0.5

cat > "$work/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -u
printf 'gh %s\n' "$*" >> "$GH_LOG"
count() { local n; n="$(cat "$GH_LOG.$1" 2>/dev/null || echo 0)"; n=$((n + 1)); echo "$n" > "$GH_LOG.$1"; echo "$n"; }
copier_yml() { printf 'project_name:\n  type: str\nplinth_sha:\n  type: str\n  default: "%s"\nlicense:\n  default: MIT\n' "$1" | base64; }
case "$*" in
  "api user --jq "*)                  echo "7 tester" ;;
  "api repos/coolbress/plinth-template/contents/copier.yml?ref=v1.0.0 "*) copier_yml "$OLD_PIN" ;;
  "api repos/coolbress/plinth-template/contents/copier.yml?ref=v1.0.5 "*) copier_yml "$NEW_PIN" ;;
  "api repos/coolbress/plinth-template/contents/copier.yml?ref=v1.1.0 "*) [ "${NO_TESTED:-0}" = 0 ] || exit 1; copier_yml "$NEW_PIN" ;;
  "api repos/tester/plinth-e2e-upgrade-42 --jq .description")
                                      [ "${OWNER_RC:-0}" = 0 ] || { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
                                      [ "${CREATE_RC:-0}" = 0 ] || [ "${CREATE_MADE:-0}" = 1 ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
                                      [ -z "${OTHERS:-}" ] || { echo "$OTHERS"; exit 0; }
                                      cat "$GH_LOG.marker" ;;
  "api repos/tester/plinth-e2e-upgrade-42 --jq .full_name")
                                      [ "${EXISTS_RC:-0}" = 0 ] || { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
                                      [ "${CREATE_EXISTS:-0}" = 0 ] || { echo "tester/plinth-e2e-upgrade-42"; exit 0; }
                                      echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
  "repo create "*)                    a="$*"; printf '%s\n' "${a##*--description }" > "$GH_LOG.marker"
                                      [ "${CREATE_RC:-0}" = 0 ] || { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
                                      [ "${CREATE_RACE:-0}" = 0 ] || { echo "GraphQL: Name already exists on this account (createRepository)" >&2; exit 1; }
                                      # made on GitHub, then the job is cancelled before the answer
                                      [ "${CREATE_KILL:-0}" = 0 ] || { kill -TERM "$PPID"; exit 143; } ;;
  "api -X PUT repos/"*"/actions/permissions "*) [ "${ACTIONS_RC:-0}" = 0 ] || { echo "HTTP 403" >&2; exit 1; } ;;
  "repo delete "*)                    n="$(count delete)"; rc="DELETE_RC$n"
                                      [ "${!rc:-0}" = 0 ] || { echo "HTTP 403: Must have admin rights" >&2; exit 1; } ;;
  *)                                  echo "mock gh: unexpected: $*" >&2; exit 4 ;;
esac
exit 0
MOCK
# copier copy at the start's tag: the workflows and answers at its pin.
cat > "$work/bin/uvx" <<'MOCK'
#!/usr/bin/env bash
printf 'uvx %s\n' "$*" >> "$GH_LOG"
[ "${COPIER_RC:-0}" = 0 ] || exit "$COPIER_RC"
dst="${!#}"; mkdir -p "$dst/.github/workflows"
printf '_commit: v1.0.0\nplinth_sha: %s\n' "$OLD_PIN" > "$dst/.copier-answers.yml"
printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n' "$OLD_PIN" > "$dst/.github/workflows/ci.yml"
printf 'jobs:\n  label:\n    uses: coolbress/plinth/.github/workflows/pr-label.yml@%s\n' "$OLD_PIN" > "$dst/.github/workflows/label.yml"
MOCK
# git: a push is logged and succeeds; ls-remote answers the branch at the
# worktree's own head unless STALE_PUSH; everything else is the real git.
cat > "$work/bin/git" <<'MOCK'
#!/usr/bin/env bash
case " $* " in
  *" push "*) printf 'git %s\n' "$*" >> "$GH_LOG"; exit 0 ;;
  *" ls-remote "*) [ "${STALE_PUSH:-0}" = 0 ] && printf '%s\trefs/heads/chore/template-v1.1.0\n' "$("$REAL_GIT" -C "$2" rev-parse HEAD)"; exit 0 ;;
esac
exec "$REAL_GIT" "$@"
MOCK
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH"

pass=0; fail=0
check() { # <name> <expected ok|no> <actual exit code>
  if { [ "$2" = ok ] && [ "$3" = 0 ]; } || { [ "$2" = no ] && [ "$3" != 0 ]; }
  then pass=$((pass+1)); echo "  PASS  $1"
  else fail=$((fail+1)); echo "  FAIL  $1 (exit $3, expected $2)"; sed 's/^/        /' "$work/out"; fi
}
is() { local name="$1"; shift; if "$@"; then pass=$((pass+1)); echo "  PASS  $name"; else fail=$((fail+1)); echo "  FAIL  $name"; sed 's/^/        /' "$work/out"; fi; }
not() { ! "$@"; }
saw() { grep -q -- "$1" "$GH_LOG"; }
said() { grep -q -- "$1" "$work/out"; }
deletes() { [ "$(grep -c '^gh repo delete ' "$GH_LOG")" = "$1" ]; }
runs=0
run() { # [<checkout>] <env assignments...>
  local at="$work/plinth"; case "${1:-}" in /*) at="$1"; shift ;; esac
  runs=$((runs + 1)); export GH_LOG="$work/log.$runs"; : > "$GH_LOG"
  rm -rf "$work/tmp" && mkdir -p "$work/tmp"
  env "$@" "$at/scripts/e2e-upgrade.sh" >"$work/out" 2>&1
}
export GITHUB_RUN_ID=42

echo "-- the start"
run "$work/same";              check "no release pinned another template tag: a failure, not a pass" no $?
is "nothing created"           not saw "^gh repo create"
is "it says why"               said "no release tag before this commit pinned a template tag tested with another plinth commit than $new_pin (v1.1.0's)"
run "$work/walk";              check "a release whose tag has the same pin is passed over" ok $?
is "the start is the release before it, whose pin differs" said "upgrade: from v0.8.0's template v1.0.0 (plinth $old_pin) to v1.1.0"
is "rendered at that release's tag" saw "^uvx .*--vcs-ref v1.0.0 "
run NO_TESTED=1;               check "the tested pin unread: stops before anything is created" no $?
is "nothing created"           not saw "^gh repo create"
run COPIER_RC=1;               check "a render that fails: stops before anything is created" no $?
is "nothing created"           not saw "^gh repo create"

echo "-- the whole path"
run GITHUB_STEP_SUMMARY="$work/summary0"; check "the tested pin lands: exit 0" ok $?
is "rendered at the start's template tag, with the start's copier pin" saw "^uvx --quiet --from copier==9.0.0 .*--vcs-ref v1.0.0 gh:coolbress/plinth-template "
is "a public repository, under the token's user" saw "^gh repo create tester/plinth-e2e-upgrade-42 --public"
is "Actions turned off on it" saw "^gh api -X PUT repos/tester/plinth-e2e-upgrade-42/actions/permissions -F enabled=false"
is "the plan, then --apply with the tested pin" bash -c 'grep -q "^template-update $" "$1" && grep -qE "^template-update --apply [0-9a-f]{40} --plinth-pin tested$" "$1"' _ "$GH_LOG"
is "the start and the target are recorded" said "upgrade: from v0.9.0's template v1.0.0 (plinth $old_pin) to v1.1.0 (tested with plinth $new_pin)"
is "what landed is recorded, in the job summary too" grep -q "upgrade: landed on https://github.com/tester/x/pull/1: 2 plinth uses: line(s) and .copier-answers.yml name $new_pin" "$work/summary0"
is "deleted once"              deletes 1
is "and said"                  said "deleted https://github.com/tester/plinth-e2e-upgrade-42"

echo "-- the tested pin does not land"
run TU_LABEL="$old_pin";       check "label.yml still at the old pin" no $?
is "named, with both SHAs"     said "label.yml calls $old_pin, not $new_pin"
is "deleted"                   deletes 1
run TU_CI="$old_pin";          check "ci.yml still at the old pin" no $?
is "named"                     said "ci.yml calls $old_pin, not $new_pin"
run TU_YAML="$old_pin";        check "a .yaml caller still at the old pin" no $?
is "named"                     said "extra.yaml calls $old_pin, not $new_pin"
run TU_YAML="$new_pin";        check "a .yaml caller at the tested pin passes" ok $?
is "counted with the .yml ones" said "landed on https://github.com/tester/x/pull/1: 3 plinth uses: line(s)"
run TU_NOLABEL=1;              check "no plinth uses: line in label.yml" no $?
is "named"                     said "label.yml has no coolbress/plinth uses: line"
run TU_ANSWERS="$old_pin";     check ".copier-answers.yml still records the old pin" no $?
is "named"                     said "records plinth_sha $old_pin, not $new_pin"
run TU_TAG=v1.0.0;             check ".copier-answers.yml still records the old tag" no $?
is "named"                     said "records _commit v1.0.0, not v1.1.0"
run STALE_PUSH=1;              check "the branch on GitHub is not the update commit" no $?
is "named"                     said "is absent, not the update commit"
is "deleted"                   deletes 1

echo "-- the update stops"
run APPLY_RC=3;                check "a conflict copier left is a failure" no $?
is "named as a conflict"       said "exited 3 (3 is a conflict"
is "deleted"                   deletes 1
run PLAN_RC=1;                 check "a plan that stops is a failure" no $?
is "deleted"                   deletes 1

echo "-- the repository"
run CREATE_EXISTS=1;           check "a name that already exists is not this run's: refused" no $?
is "nothing deleted"           deletes 0
is "it says whose it is not"   said "already exists and this run did not create it"
is "nothing created"           not saw "^gh repo create"
run CREATE_RACE=1;             check "a name taken between the read and the create: refused" no $?
is "nothing deleted"           deletes 0
run EXISTS_RC=1;               check "whether the name is free cannot be read: stops" no $?
is "nothing created"           not saw "^gh repo create"
is "nothing deleted"           deletes 0
run CREATE_KILL=1;             check "cancelled while the create runs: a failure" no $?
is "what the create may have made is deleted" deletes 1
is "not called nothing to delete" not said "nothing to delete"
is "it said the create's answer was lost" said "deleting https://github.com/tester/plinth-e2e-upgrade-42"
run CREATE_KILL=1 OTHERS="someone else's";  check "cancelled while the create runs, and the name is someone else's" no $?
is "it is not deleted"         deletes 0
is "it is named, not deleted"  said "exists without this run's description"
run CREATE_KILL=1 OWNER_RC=1;  check "cancelled while the create runs, and whose it is cannot be read" no $?
is "it is not deleted"         deletes 0
is "named loudly"              said "could not be read"
run CREATE_RC=1;               check "a create that fails without saying, and nothing was made" no $?
is "nothing deleted"           deletes 0
is "it says so"                said "does not exist; nothing to delete"
run CREATE_RC=1 CREATE_MADE=1; check "a create that fails without saying, but made it" no $?
is "deleted, its description being this run's" deletes 1
run ACTIONS_RC=1;              check "Actions that cannot be turned off: a failure" no $?
is "deleted"                   deletes 1
run DELETE_RC1=1;              check "landed but not deleted is a failure, and cleanup tries once more" no $?
is "the deletion is asked again" deletes 2
run DELETE_RC1=1 DELETE_RC2=1 GITHUB_STEP_SUMMARY="$work/summary1"; check "not deleted twice" no $?
is "the repository is named loudly" said "UPGRADE REPOSITORY NOT DELETED: https://github.com/tester/plinth-e2e-upgrade-42 may EXIST"
is "and in the job summary"    grep -q "plinth-e2e-upgrade-42 may EXIST" "$work/summary1"
run TU_CI="$old_pin" DELETE_RC1=1 GITHUB_STEP_SUMMARY="$work/summary2"; check "a pin that did not land, and a deletion that fails" no $?
is "the repository is named loudly" grep -q "plinth-e2e-upgrade-42 may EXIST" "$work/summary2"

echo
echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
