#!/usr/bin/env bash
# The driver of the tier-2 journey, `scripts/e2e.sh`, against a mocked `gh`,
# a stub door and a stub floor checker. No network, nothing created.
#
# One property: exit 0 means the whole journey happened, deletion included,
# and any other exit leaves no repository behind without naming it. The door
# itself is tested in new-project-failpath.sh; here it is a stub that reports
# a first pull request, or fails.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/scripts" "$work/tmp"
# The driver keeps its clone when the journey fails, for a person to read;
# here every failure is staged, so those land under this test's own tree.
export TMPDIR="$work/tmp"

# The driver finds the door and the checker beside itself; copies of the stubs
# sit there, the real ruleset.json one level up (it is only passed along).
cp "$root/scripts/e2e.sh" "$work/scripts/"
cp "$root/ruleset.json" "$work/"
cat > "$work/scripts/new-project.sh" <<'DOOR'
#!/usr/bin/env bash
template_repo="coolbress/plinth-template"
template_ref="v0.0.0-stub"
echo "door $*" >> "$GH_LOG"
# Preflight refuses before creating (DOOR_PREFLIGHT=1); otherwise the door
# announces the creation the way the real one does, then fails or goes on.
[ "${DOOR_PREFLIGHT:-0}" = 0 ] || { echo "https://github.com/$1 already exists; the door creates new repositories only" >&2; exit 2; }
echo "create $1 (public, MIT, cli, as owner) from coolbress/plinth-template@v0.0.0-stub in $2; wall: ruleset + CodeQL; then the first pull request. rollback: on"
[ "${DOOR_RC:-0}" = 0 ] || { echo "the wall did not go up" >&2; exit "$DOOR_RC"; }
all="$*"; dir="${all##*--dir=}"; dir="${dir%% *}"; mkdir -p "$dir/.github/workflows"
echo "    uses: coolbress/plinth/.github/workflows/python-ci.yml@stub-sha" > "$dir/.github/workflows/ci.yml"
printf 'done: https://github.com/%s\n  first pull request: https://github.com/%s/pull/1\n' "$1" "$1"
DOOR
cat > "$work/scripts/floor-check.py" <<'CHK'
#!/usr/bin/env python3
import os, sys
print("  PASS  stub floor check", sys.argv[1:])
sys.exit(int(os.environ.get("FLOOR_RC", "0")))
CHK
chmod +x "$work/scripts/"*

cat > "$work/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -u
printf 'gh %s\n' "$*" >> "$GH_LOG"
count() { local n; n="$(cat "$GH_LOG.$1" 2>/dev/null || echo 0)"; n=$((n + 1)); echo "$n" > "$GH_LOG.$1"; echo "$n"; }
case "$*" in
  "api user --jq "*)                  echo "7 tester" ;;
  "repo create "*)                    [ "${CREATE_RC:-0}" = 0 ] || { echo "HTTP 403: Resource not accessible" >&2; exit "$CREATE_RC"; } ;;
  "repo delete "*)                    n="$(count delete)"; rc="DELETE_RC$n"
                                      [ "$n" = 2 ] && [ "${EXISTS_RC:-0}" != 0 ] && { echo "HTTP 404: Not Found (https://api.github.com/repos/tester/x)" >&2; exit 1; }
                                      [ "${!rc:-0}" = 0 ] || { echo "HTTP 403: Must have admin rights" >&2; exit "${!rc}"; } ;;
  "api repos/"*"/commits/main --jq "*) echo "${MAIN_TIP:-0123456789ab docs: first pull request through the wall (#1)}" ;;   # GitHub appends the number (measured)
  "api repos/"*"/commits/"*)          echo "feedfacefeedfacefeedfacefeedfacefeedface" ;;
  "api repos/"*" --jq .default_branch") echo "${DEFAULT_BRANCH:-main}" ;;
  "pr checks "*"select(.bucket == \"fail\")"*) printf '%s' "${FAILED_CHECKS:-}" ;;
  # The names on the head: CodeQL is there unless CODEQL=0, and appears once the recovery push happened.
  "pr checks "*".[].name")            [ "${CODEQL:-1}" = 1 ] || [ -e "$GH_LOG.pushed" ] && printf 'ci / test\nCodeQL\n' || printf 'ci / test\n' ;;
  "pr view "*)                        if [ -e "$GH_LOG.pushed" ] && [ -n "${STATE_AFTER_PUSH:-}" ]; then echo "$STATE_AFTER_PUSH"; else echo "${STATE:-CLEAN}"; fi ;;
  "pr merge "*)                       [ "${MERGE_RC:-0}" = 0 ] || { echo "Pull request is not mergeable" >&2; exit "$MERGE_RC"; } ;;
esac
exit 0
MOCK
chmod +x "$work/bin/gh"
# git: the recovery commit and push into the door's clone are logged and
# succeed (the clone is a stub directory); every other call is the real git.
real_git="$(command -v git)"
cat > "$work/bin/git" <<STUB
#!/usr/bin/env bash
case "\$*" in
  "-C "*" commit "*|"-C "*" push"*) printf 'git %s\\n' "\$*" >> "\$GH_LOG"; [[ "\$*" == *" push"* ]] && : > "\$GH_LOG.pushed"; exit 0 ;;
esac
exec "$real_git" "\$@"
STUB
chmod +x "$work/bin/git"
export PATH="$work/bin:$PATH"

pass=0; fail=0
check() { # <name> <expected ok|no> <actual exit code>
  if { [ "$2" = ok ] && [ "$3" = 0 ]; } || { [ "$2" = no ] && [ "$3" != 0 ]; }
  then pass=$((pass+1)); echo "  PASS  $1"
  else fail=$((fail+1)); echo "  FAIL  $1 (exit $3, expected $2)"; sed 's/^/        /' "$work/out"; fi
}
is() { local name="$1"; shift; if "$@"; then pass=$((pass+1)); echo "  PASS  $name"; else fail=$((fail+1)); echo "  FAIL  $name"; fi; }
not() { ! "$@"; }
saw() { grep -q -- "$1" "$GH_LOG"; }
said() { grep -q -- "$1" "$work/out"; }
deletes() { [ "$(grep -c '^gh repo delete ' "$GH_LOG")" = "$1" ]; }
run() { # <env assignments...>
  export GH_LOG="$work/log.$RANDOM"; : > "$GH_LOG"
  unset CREATE_RC DELETE_RC1 DELETE_RC2 DOOR_RC DOOR_PREFLIGHT EXISTS_RC DEFAULT_BRANCH FLOOR_RC FAILED_CHECKS STATE STATE_AFTER_PUSH CODEQL MERGE_RC MAIN_TIP GITHUB_STEP_SUMMARY
  env "$@" PLINTH_E2E_WAIT=1 "$work/scripts/e2e.sh" >"$work/out" 2>&1
}
export GITHUB_RUN_ID=42

echo "-- the first assert: create and delete, before the door"
run CREATE_RC=1;           check "a token that cannot create stops before the door" no $?
is "the door never ran"    not saw "^door "
is "nothing to delete"     deletes 0
run DELETE_RC1=1;          check "a token that cannot delete stops before the door" no $?
is "the door never ran"    not saw "^door "
is "the repository it left is named" said "plinth-e2e-42-probe EXISTS"
is "the probe is a sibling name, not the door's" saw "^gh repo create tester/plinth-e2e-42-probe "

echo "-- the door"
run DOOR_PREFLIGHT=1;      check "a door that refuses in preflight (the name exists) fails the journey" no $?
is "nothing is deleted: this run created nothing" deletes 1
is "and it says so"        said "before anything was created; nothing to delete"
run DOOR_RC=1;             check "a door that fails after creating fails the journey" no $?
is "the repository the door left was deleted" deletes 2
is "no merge"              not saw "^gh pr merge"
run DOOR_RC=1 EXISTS_RC=1; check "a door that failed and rolled back itself" no $?
is "the deletion was still attempted (404 is the only 'absent')" deletes 2
is "and read as already gone" said "is already gone"
is "not as a rollback failure" not said "ROLLBACK FAILED"
run DOOR_RC=1 DELETE_RC2=1; check "a door that fails and a deletion that fails (403, not 404)" no $?
is "the repository is named loudly, with gh's words" said "ROLLBACK FAILED: https://github.com/tester/plinth-e2e-42 may EXIST (HTTP 403"

echo "-- the wall, read back"
run DEFAULT_BRANCH=probe;  check "a default branch other than main fails the journey" no $?
is "said which branch"     said "probe"
is "no merge on a wrong default branch" not saw "^gh pr merge"
is "deleted"               deletes 2
run FLOOR_RC=1;            check "a floor check that fails fails the journey" no $?
is "no merge on a failed floor check" not saw "^gh pr merge"
is "deleted"               deletes 2

echo "-- through the wall"
run FAILED_CHECKS=$'  ci / test  https://github.com/o/r/actions/runs/1/job/2\n'
check "a red check fails the journey" no $?
is "the red check is named with its link" said "ci / test  https://github.com/o/r/actions/runs/1/job/2"
is "no merge on a red check" not saw "^gh pr merge"
is "deleted"               deletes 2
run STATE=BLOCKED;         check "never mergeable within the wait fails the journey" no $?
is "the state is named"    said "BLOCKED"
is "no merge while blocked" not saw "^gh pr merge"
is "deleted"               deletes 2
run STATE=BLOCKED CODEQL=0 STATE_AFTER_PUSH=CLEAN
check "CodeQL missing on the head: the recovery commit is pushed once, then the merge" ok $?
is "one recovery commit"   [ "$(grep -c '^git -C .* commit -q --allow-empty' "$GH_LOG")" = 1 ]
is "one push"              [ "$(grep -c '^git -C .* push' "$GH_LOG")" = 1 ]
is "the recovery is said, with its ticket" said "pushing the door's recovery commit once (#117)"
is "merged after it"       saw "^gh pr merge"
run STATE=BLOCKED CODEQL=0; check "CodeQL missing and still blocked after the recovery: fails, no second push" no $?
is "still one push"        [ "$(grep -c '^git -C .* push' "$GH_LOG")" = 1 ]
is "deleted"               deletes 2
run STATE=BLOCKED;         check "CodeQL present and blocked: no recovery push" no $?
is "no push"               not saw "^git -C .* push"
run MERGE_RC=1;            check "a merge that keeps failing fails the journey" no $?
is "deleted"               deletes 2
run MAIN_TIP="0123456789ab chore: something else"
check "a main that does not carry the squash commit fails the journey" no $?
is "deleted"               deletes 2

echo "-- the whole journey"
run;                       check "green checks: merged and deleted" ok $?
is "merged once"           [ "$(grep -c '^gh pr merge ' "$GH_LOG")" = 1 ]
is "probe delete, then the real one" deletes 2
is "the merged commit is reported, number and all" said "merged: 0123456789ab docs: first pull request through the wall (#1)"
is "the deletion is reported" said "deleted https://github.com/tester/plinth-e2e-42"
is "the generator, template and pin are recorded" bash -c 'grep -q "^template: coolbress/plinth-template@v0.0.0-stub feedfacefeed" "$1" && grep -q "python-ci.yml@stub-sha" "$1"' _ "$work/out"
run DELETE_RC2=1 GITHUB_STEP_SUMMARY="$work/summary"
check "merged but not deleted is a failure" no $?
is "the repository is named loudly" said "plinth-e2e-42 EXISTS"
is "and in the job summary"  grep -q "plinth-e2e-42" "$work/summary"

echo
echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
