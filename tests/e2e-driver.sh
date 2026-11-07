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
cp "$root/scripts/e2e.sh" "$root/scripts/description-fields.py" "$work/scripts/"
mkdir -p "$work/scripts/lib"; cp "$root/scripts/lib/rulesets.sh" "$work/scripts/lib/"
cp "$root/ruleset.json" "$root/ruleset-merge.json" "$work/"
cat > "$work/scripts/new-project.sh" <<'DOOR'
#!/usr/bin/env bash
template_repo="coolbress/plinth-template"
template_ref="v0.0.0-stub"
echo "door $*" >> "$GH_LOG"
# Preflight refuses before creating (DOOR_PREFLIGHT=1); otherwise the door
# announces the creation the way the real one does, then fails or goes on.
[ "${DOOR_PREFLIGHT:-0}" = 0 ] || { echo "https://github.com/$1 already exists; the door creates new repositories only" >&2; exit 2; }
echo "create $1 (public, MIT, cli, as owner) from coolbress/plinth-template@v0.0.0-stub in $2; wall: ruleset + CodeQL; then the first pull request. rollback: on"
# The create itself failed (the name existed after a preflight read that missed): no rollback line.
[ "${DOOR_CREATE_FAILED:-0}" = 0 ] || { echo "GraphQL: Name already exists on this account (createRepository)" >&2; exit 1; }
# Failed after creating: the real door's rollback lines, which the driver reads as proof of creation.
[ "${DOOR_RC:-0}" = 0 ] || { echo "the wall did not go up; deleting https://github.com/$1 (the local copy stays)" >&2
  if [ "${EXISTS_RC:-0}" != 0 ]; then echo "deleted https://github.com/$1" >&2; else echo "!! ROLLBACK FAILED: https://github.com/$1 EXISTS WITHOUT A WALL" >&2; fi; exit "$DOOR_RC"; }
all="$*"; dir="${all##*--dir=}"; dir="${dir%% *}"; mkdir -p "$dir/.github/workflows"
# Two calling files and a commented call, as the template renders them. DOOR_NO_PINS: none.
if [ "${DOOR_NO_PINS:-0}" = 0 ]; then
  { echo "    uses: coolbress/plinth/.github/workflows/python-ci.yml@stub-sha"
    echo "#       uses: coolbress/plinth/.github/workflows/pr-review.yml@<the full commit SHA the ci job calls>"
    echo "      - uses: actions/checkout@stub-action-sha"; } > "$dir/.github/workflows/ci.yml"
  echo "    uses: coolbress/plinth/.github/workflows/pr-label.yml@stub-sha" > "$dir/.github/workflows/label.yml"
else
  echo "      - uses: actions/checkout@stub-action-sha" > "$dir/.github/workflows/ci.yml"
fi
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
  # A token GitHub refuses: the real gh exits 1 and prints the error body on
  # stdout, where --jq is not applied, and its own line on stderr (#288).
  "api user --jq "*)                  [ "${USER_401:-0}" = 0 ] || { printf '{\n  "message": "Bad credentials",\n  "status": "401"\n}\n'; echo "gh: Bad credentials (HTTP 401)" >&2; exit 1; }
                                      [ "${USER_NO_LOGIN:-0}" = 0 ] || { echo "7 "; exit 0; }
                                      echo "7 tester" ;;
  "repo create "*)                    [ "${CREATE_EXISTS:-0}" = 0 ] || { echo "GraphQL: Name already exists on this account (createRepository)" >&2; exit 1; }
                                      [ "${CREATE_RC:-0}" = 0 ] || { echo "HTTP 403: Resource not accessible" >&2; exit "$CREATE_RC"; } ;;
  "repo delete "*)                    n="$(count delete)"; rc="DELETE_RC$n"
                                      # The probe after a create that failed: absent (404) unless its answer was merely lost.
                                      [ "$n" = 1 ] && [ "${CREATE_RC:-0}" != 0 ] && [ "${PROBE_LOST:-0}" = 0 ] && { echo "HTTP 404: Not Found (https://api.github.com/repos/tester/x-probe)" >&2; exit 1; }
                                      [ "$n" = 2 ] && [ "${EXISTS_RC:-0}" != 0 ] && { echo "HTTP 404: Not Found (https://api.github.com/repos/tester/x)" >&2; exit 1; }
                                      # A cancellation landing on the last deletion: the runner signals the tree, gh dies by it, so does the driver.
                                      [ "$n" = 2 ] && [ "${DELETE_KILL:-0}" != 0 ] && { kill -TERM "$PPID"; exit 143; }
                                      [ "${!rc:-0}" = 0 ] || { echo "HTTP 403: Must have admin rights" >&2; exit "${!rc}"; } ;;
  # The merge ruleset (#568): its id by name (MERGE_IDS, one per line; empty is
  # none), then the ruleset as GitHub returns it (MERGE_READBACK, or the file
  # with server fields and the update rule's parameter added).
  "api --paginate repos/"*"/rulesets?per_page=100 --jq "*) printf '%s' "${MERGE_IDS-5}" ;;
  "api repos/"*"/rulesets/"*)         if [ -n "${MERGE_READBACK:-}" ]; then echo "$MERGE_READBACK"; else
                                        jq '. + {id: 5, rules: [{type: "update", parameters: {update_allows_fetch_and_merge: false}}]}' "$MERGE_FILE"; fi ;;
  "api repos/"*"/commits/main --jq "*) echo "${MAIN_TIP:-0123456789ab docs: first pull request through the wall (#1)}" ;;   # GitHub appends the number (measured)
  "api repos/"*"/commits/"*)          echo "feedfacefeedfacefeedfacefeedfacefeedface" ;;
  "api repos/"*" --jq .default_branch") echo "${DEFAULT_BRANCH:-main}" ;;
  # A release branch's run (#862): the pull request's head, its CI run, the
  # floor-check job, and that job's log as gh prints it (measured on a real
  # run: name, step, the runner's timestamp; the script's own text and the
  # step's env come before the line the job echoes).
  "pr view "*"headRefOid"*)           printf '%s\n' "${PR_HEAD-feedfacefeedfacefeedfacefeedfacefeedface}" ;;
  "api -X GET repos/"*"/actions/runs "*"head_sha="*"label.yml"*) printf '%s\n' "${LABEL_RUN-success $GITHUB_SHA}" ;;
  "api -X GET repos/"*"/actions/runs "*"head_sha="*) printf '%s' "${CI_RUN-77}" ;;
  "api repos/"*"/actions/runs/"*"/jobs"*) printf '%s' "${FLOOR_JOB-88}" ;;
  "run view "*"--log"*)               [ "${LOG_EMPTY:-0}" = 0 ] || exit 0
                                      called="${CALLED_SHA-$GITHUB_SHA}"
                                      printf 'ci / floor-check\tUNKNOWN STEP\t2026-11-07T07:32:21.5Z \033[36;1mecho "plinth ${PLINTH_SHA}"\033[0m\r\n'
                                      printf 'ci / floor-check\tUNKNOWN STEP\t2026-11-07T07:32:21.5Z   PLINTH_SHA: %s\r\n' "$called"
                                      printf 'ci / floor-check\tUNKNOWN STEP\t2026-11-07T07:32:23.1Z plinth %s\r\n' "$called" ;;
  "pr checks "*"select(.bucket == \"fail\")"*) printf '%s' "${FAILED_CHECKS:-}" ;;
  # The record line after the merge (#164), required checks only: RECORD_RC makes every read fail with that exit.
  "pr checks "*"--required --json name,bucket "*) [ -z "${RECORD_RC:-}" ] || { echo "HTTP 502: Bad Gateway" >&2; exit "$RECORD_RC"; }; printf 'ci / test=pass\nimage=pass\n' ;;
  # The names on the head: CodeQL is there unless CODEQL=0, and appears once the recovery push happened.
  # With --json the real gh exits 0 whatever the buckets (2.79.0); CHECKS_RC is the exit of the first
  # CHECKS_FAILS reads (default: every one), names printed all the same: the driver must read the exit.
  "pr checks "*".[].name")            n="$(count names)"
                                      [ "${CODEQL:-1}" = 1 ] || [ -e "$GH_LOG.pushed" ] && printf 'ci / test\nCodeQL\n' || printf 'ci / test\n'
                                      [ -z "${CHECKS_RC:-}" ] || [ "$n" -gt "${CHECKS_FAILS:-999}" ] || { echo "HTTP 502: Bad Gateway" >&2; exit "$CHECKS_RC"; } ;;
  "pr view "*"--json body "*)         [ -z "${BODY_RC:-}" ] || { echo "HTTP 502: Bad Gateway" >&2; exit "$BODY_RC"; }
                                      printf '{"data":{"repository":{"pullRequest":{"body":"%s"}}}}\n' "${FIRST_BODY:-## What I checked myself\\n\\nread\\n\\nReview: none (not yet)}" ;;
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
  "-C "*" commit "*) printf 'git %s\\n' "\$*" >> "\$GH_LOG"; cat "\$2"/.github/workflows/*.yml > "\$GH_LOG.committed"; exit 0 ;;
  "-C "*" push"*) [ "\${PUSH_RC:-0}" = 0 ] || { echo "remote: refusing to allow a token to update a workflow" >&2; exit "\$PUSH_RC"; }
    printf 'git %s\\n' "\$*" >> "\$GH_LOG"; : > "\$GH_LOG.pushed"; exit 0 ;;
esac
exec "$real_git" "\$@"
STUB
chmod +x "$work/bin/git"
export PATH="$work/bin:$PATH" MERGE_FILE="$work/ruleset-merge.json"

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
# The wait is 2 s, not 1: e2e.sh reads its deadline from $SECONDS, whole seconds,
# and a 1 s deadline set at the end of a wall-clock second is already reached at
# the first poll's check, so a case that needs a second poll (a read that
# succeeds, the recovery push, the merge after it) fails before it. With 2 s a
# tick before the first check leaves 1 < 2, and the 2 s sleep makes the second
# poll the last one, unless the first poll itself takes over a second (the
# mocks take milliseconds). Every timed-out case now takes 2 s (#156).
# Each run's log is numbered, not named by $RANDOM: the mock keeps counters
# beside it (.delete, .names, .pushed) that the truncation below does not
# reset, and a name drawn twice gave a later run an earlier one's count (#201).
runs=0
run() { # <env assignments...> [-- <arguments to e2e.sh...>]
  local envs=() args=()
  while [ $# -gt 0 ]; do [ "$1" = -- ] && { shift; args=("$@"); break; }; envs+=("$1"); shift; done
  set -- ${envs[@]+"${envs[@]}"}
  runs=$((runs + 1)); export GH_LOG="$work/log.$runs"; : > "$GH_LOG"
  unset USER_401 USER_NO_LOGIN RECORD_RC CREATE_RC CREATE_EXISTS PROBE_LOST DELETE_RC1 DELETE_RC2 DELETE_RC3 DELETE_KILL CHECKS_RC CHECKS_FAILS DOOR_RC DOOR_PREFLIGHT DOOR_CREATE_FAILED EXISTS_RC DEFAULT_BRANCH FLOOR_RC FAILED_CHECKS STATE STATE_AFTER_PUSH CODEQL MERGE_RC MAIN_TIP GITHUB_STEP_SUMMARY MERGE_IDS MERGE_READBACK PLINTH_E2E_ARCHETYPE GITHUB_REF GITHUB_SHA DOOR_NO_PINS PUSH_RC PR_HEAD CI_RUN FLOOR_JOB LOG_EMPTY CALLED_SHA LABEL_RUN
  env "$@" PLINTH_E2E_WAIT=2 "$work/scripts/e2e.sh" ${args[@]+"${args[@]}"} >"$work/out" 2>&1
}
export GITHUB_RUN_ID=42

echo "-- the first pull request's description, as ci / pr-title reads it (#856)"
run;                       check "a filled description: the journey goes on" ok $?
is "the log says the check warns about neither field" said "first pull request's description: pass: PR description, says which review ran"
run 'FIRST_BODY=## What and why\n\nx'; check "a description missing both: a line in the log, and the journey goes on" ok $?
is "the log names what is missing" said "first pull request's description: not yet confirmed: PR description, does not say which review ran"
run BODY_RC=1;             check "a description that cannot be read does not stop the journey" ok $?
is "the log says it was not read" said "first pull request's description: not read"

echo "-- the token's user, before anything is created"
run USER_401=1;            check "a token GitHub refuses stops at the user lookup" no $?
is "nothing created or deleted" not saw "^gh repo "
is "it names the token, in gh's words" said "Bad credentials (HTTP 401)"
is "no repository is named as left behind" not said "EXISTS"
run USER_NO_LOGIN=1;       check "an answer with no login is a failed lookup, whatever gh's exit" no $?
is "nothing created or deleted" not saw "^gh repo "
run USER_401=1 -- tester;  check "an owner given on the command line does not carry a refused token past the lookup" no $?
is "nothing created or deleted" not saw "^gh repo "
run -- "";                 check "an empty owner argument falls back to the token's user" ok $?
is "the probe is under the token's user" saw "^gh repo create tester/"

echo "-- the first assert: create and delete, before the door"
run CREATE_RC=1;           check "a token that cannot create stops before the door" no $?
is "the door never ran"    not saw "^door "
is "the deletion was still asked, and 404 is the proof nothing exists" deletes 1
run CREATE_EXISTS=1;       check "a probe name that already exists is not this run's: refused" no $?
is "nothing deleted"       deletes 0
is "it says whose it is not" said "already exists and this run did not create it"
run CREATE_RC=1 PROBE_LOST=1; check "a create whose answer was lost, but the probe exists: deleted, and the journey goes on" ok $?
is "it says the answer was lost" said "the create's answer was lost"
is "the door ran"          saw "^door "
run DELETE_RC1=1;          check "a token that cannot delete stops before the door" no $?
is "the door never ran"    not saw "^door "
is "the repository it left is named" said "plinth-e2e-42-probe EXISTS"
is "the probe is a sibling name, not the door's" saw "^gh repo create tester/plinth-e2e-42-probe "

echo "-- the door"
run DOOR_PREFLIGHT=1;      check "a door that refuses in preflight (the name exists) fails the journey" no $?
is "nothing is deleted: this run created nothing" deletes 1
is "and it says so"        said "before anything was created; nothing to delete"
run DOOR_CREATE_FAILED=1;  check "a door whose create failed (the name existed) fails the journey" no $?
is "nothing is deleted: not ours" deletes 1
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
# The checker judges push protection only without --actions-token (#303): the
# e2e run is where the door's own call is read back, with a token that can.
is "the checker is called for the repository" said "stub floor check.*'--repo'"
is "and without --actions-token" not said "stub floor check.*--actions-token"
is "no merge on a failed floor check" not saw "^gh pr merge"
is "deleted"               deletes 2
is "the checker is given the merge ruleset" said "stub floor check.*'--merge-ruleset', '[^']*/ruleset-merge.json'"
run MERGE_IDS=;            check "no merge ruleset on the door-made repository fails the journey" no $?
is "no merge without the merge ruleset" not saw "^gh pr merge"
is "deleted"               deletes 2
run MERGE_IDS=$'5\n6';     check "two merge rulesets fail the journey" no $?
is "deleted"               deletes 2
run MERGE_READBACK='{"name":"main: merged by an admin","target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"rules":[{"type":"update"}],"bypass_actors":[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}]}'
check "a merge ruleset in another shape fails the journey" no $?
is "the shape it read is named" said '"bypass_mode":"always"'
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
run STATE=BLOCKED CODEQL=0 CHECKS_RC=8; check "exit 8 (pending, without --json) is a read: CodeQL missing on it is pushed" no $?
is "one push"              [ "$(grep -c '^git -C .* push' "$GH_LOG")" = 1 ]
run STATE=BLOCKED CODEQL=0 CHECKS_RC=1; check "any other exit is not a read: not evidence that CodeQL is absent" no $?
is "no push, whatever was listed" not saw "^git -C .* push"
is "the unreadable answer is said, with gh's exit and words" said "could not read the checks on https://github.com/tester/plinth-e2e-42/pull/1 (gh exited 1: ci / test HTTP 502: Bad Gateway)"
is "deleted"               deletes 2
run STATE=BLOCKED CODEQL=0 CHECKS_RC=1 CHECKS_FAILS=1; check "read again next poll: the push waits for a readable answer" no $?
is "one push, after the read that succeeded" [ "$(grep -c '^git -C .* push' "$GH_LOG")" = 1 ]
is "two reads"             [ "$(cat "$GH_LOG.names")" = 2 ]
run MERGE_RC=1;            check "a merge that keeps failing fails the journey" no $?
is "deleted"               deletes 2
run MAIN_TIP="0123456789ab chore: something else"
check "a main that does not carry the squash commit fails the journey" no $?
is "deleted"               deletes 2

echo "-- the whole journey"
run GITHUB_STEP_SUMMARY="$work/summary0"; check "green checks: merged and deleted" ok $?
is "the merge ruleset is read back before the merge" said "^merge ruleset: 5, as ruleset-merge.json"
# The instance is a backend, the archetype with the `image` check, and never
# the door's cli default by omission or by another value (#164).
is "the door renders a backend instance" [ "$(grep -c '^door tester/plinth-e2e-42 --dir=.* --archetype=backend$' "$GH_LOG")" = 1 ]
is "the archetype is said"  said "^archetype: backend$"
is "and in the job summary" grep -q "^archetype: backend " "$work/summary0"
is "the checks the pull request waited for are listed by name" said "^checks: ci / test=pass image=pass $"
# The web journey (#615): the same driver, the door asked for the web
# archetype, under a name of its own so both journeys of one run never meet.
run PLINTH_E2E_ARCHETYPE=web GITHUB_STEP_SUMMARY="$work/summary-web"; check "the web journey: merged and deleted" ok $?
is "the door renders a web instance" [ "$(grep -c '^door tester/plinth-e2e-web-42 --dir=.* --archetype=web$' "$GH_LOG")" = 1 ]
is "the archetype is said, in the job summary too" bash -c 'grep -q "^archetype: web$" "$1" && grep -q "^archetype: web " "$2"' _ "$work/out" "$work/summary-web"
is "its own repository is deleted" said "deleted https://github.com/tester/plinth-e2e-web-42"
run PLINTH_E2E_ARCHETYPE=cli; check "an archetype other than backend or web stops before anything" no $?
is "it says which it takes" said "PLINTH_E2E_ARCHETYPE is backend or web (got: cli)"
is "nothing created or deleted" not saw "^gh repo "
run RECORD_RC=1;           check "a record read that keeps failing does not turn a finished journey red" ok $?
is "read three times, required checks only" [ "$(grep -c '^gh pr checks .*--required --json name,bucket ' "$GH_LOG")" = 3 ]
is "the line says it was not read, with gh's exit and words" said "^checks: unread (gh exited 1 after 3 attempts: HTTP 502: Bad Gateway)$"
is "merged and deleted all the same" deletes 2
is "merged once"           [ "$(grep -c '^gh pr merge ' "$GH_LOG")" = 1 ]
is "probe delete, then the real one" deletes 2
is "the merged commit is reported, number and all" said "merged: 0123456789ab docs: first pull request through the wall (#1)"
is "the deletion is reported" said "deleted https://github.com/tester/plinth-e2e-42"
is "the generator, template and pin are recorded" bash -c 'grep -q "^template: coolbress/plinth-template@v0.0.0-stub feedfacefeed" "$1" && grep -q "python-ci.yml@stub-sha" "$1"' _ "$work/out"
run DELETE_RC2=1;          check "merged but not deleted is a failure, and cleanup tries once more" no $?
is "the deletion is asked again" deletes 3
is "and reported"          said "deleted https://github.com/tester/plinth-e2e-42"
run DELETE_RC2=1 DELETE_RC3=1 GITHUB_STEP_SUMMARY="$work/summary"
check "merged and not deleted twice is a failure" no $?
is "the repository is named loudly, apart from a rollback" said "MERGED, NOT DELETED: https://github.com/tester/plinth-e2e-42 may EXIST"
is "and in the job summary"  grep -q "MERGED, NOT DELETED: https://github.com/tester/plinth-e2e-42" "$work/summary"
run DELETE_KILL=1;         check "a cancellation landing on the last deletion: the trap is still armed" no $?
is "the deletion is asked again" deletes 3
is "and reported"          said "deleted https://github.com/tester/plinth-e2e-42"
run DELETE_KILL=1 DELETE_RC3=1 GITHUB_STEP_SUMMARY="$work/summary2"
check "a cancellation, then a deletion that fails" no $?
is "the repository is named loudly" said "MERGED, NOT DELETED: https://github.com/tester/plinth-e2e-42 may EXIST"
is "and in the job summary"  grep -q "plinth-e2e-42" "$work/summary2"

echo "-- a release branch calls plinth at its own commit (#862)"
rel=0123456789abcdef0123456789abcdef01234567
other=fedcba9876543210fedcba9876543210fedcba98
release=(GITHUB_REF=refs/heads/release/v9.9.9 "GITHUB_SHA=$rel")
committed() { grep -q -- "$1" "$GH_LOG.committed"; }
before_merge() { [ "$(grep -n "$1" "$GH_LOG" | head -1 | cut -d: -f1)" -lt "$(grep -n '^gh pr merge ' "$GH_LOG" | head -1 | cut -d: -f1)" ]; }
run "${release[@]}" GITHUB_STEP_SUMMARY="$work/summary-rel"; check "the release journey: merged and deleted" ok $?
is "ci.yml's call moved to the run's commit" committed "^    uses: coolbress/plinth/.github/workflows/python-ci.yml@$rel\$"
is "label.yml's call moved too" committed "^    uses: coolbress/plinth/.github/workflows/pr-label.yml@$rel\$"
is "no call stays at the template's pin" not committed "plinth/.*@stub-sha"
is "the commented call is left as the template wrote it" committed "^#       uses: coolbress/plinth/.github/workflows/pr-review.yml@<the full"
is "another action's pin is left alone" committed "actions/checkout@stub-action-sha"
is "one commit, pushed before the merge" bash -c '[ "$(grep -c "^git -C .* commit " "$1")" = 1 ] && [ "$(grep -c "^git -C .* push" "$1")" = 1 ]' _ "$GH_LOG"
is "the push comes before the merge" before_merge "^git -C .* push"
is "the pins line shows the run's commit" said "^pins: .*python-ci.yml@$rel"
is "the log shows the called job.workflow_sha equal to it" said "^called job.workflow_sha: $rel, this run's commit\$"
is "and so does the job summary" grep -q "^called job.workflow_sha: $rel" "$work/summary-rel"
is "the log shows the label run at it too" said "^called pr-label.yml: success at $rel\$"
is "the head's run was asked for" saw "^gh api -X GET repos/tester/plinth-e2e-42/actions/runs .*head_sha=feedface"
is "deleted" deletes 2
run "${release[@]}" PLINTH_E2E_ARCHETYPE=web; check "the web journey on a release branch too" ok $?
is "its calls moved" committed "python-ci.yml@$rel"

run "${release[@]}" "CALLED_SHA=$other"; check "a called run at another commit fails the journey" no $?
is "both commits are named" said "the called job.workflow_sha is $other, not this run's commit $rel"
is "deleted" deletes 2
run "${release[@]}" LOG_EMPTY=1; check "a log with no plinth line fails: nothing read is not a pass" no $?
is "it says it could not read one" said "could not read the called job.workflow_sha"
is "deleted" deletes 2
for gone in PR_HEAD= CI_RUN= FLOOR_JOB=; do
  run "${release[@]}" "$gone"; check "no answer for $gone fails the journey" no $?
  is "it says it could not read one" said "could not read the called job.workflow_sha"
  is "the log is not read" not saw "^gh run view "
  is "deleted" deletes 2
done
for got in "startup_failure null" "null null" "success $other" ""; do
  run "${release[@]}" "LABEL_RUN=$got"; check "a label run that reads \"$got\" fails: it is in no ruleset, so nothing else would" no $?
  is "it says what it read" said "label.yml's run on .* reads \"${got:-nothing}\""
  is "deleted" deletes 2
done
run "${release[@]}" PUSH_RC=1; check "a push of the moved calls that fails stops the journey" no $?
is "no merge" not saw "^gh pr merge"
is "deleted" deletes 2
run "${release[@]}" DOOR_NO_PINS=1; check "a render that calls plinth nowhere fails: nothing moved is not a pass" no $?
is "it says so" said "no coolbress/plinth call to move"
is "nothing pushed" not saw "^git -C .* push"
is "no merge" not saw "^gh pr merge"
is "deleted" deletes 2
run GITHUB_REF=refs/heads/release/v9.9.9 GITHUB_SHA=abc123; check "a release branch with no full commit stops before anything" no $?
is "it says what it got" said "GITHUB_SHA is not a full commit (got: abc123)"
is "nothing created" not saw "^gh repo "
run GITHUB_REF=refs/heads/release/v9.9.9; check "a release branch with no commit at all stops too" no $?
is "nothing created" not saw "^gh repo "

echo "-- every other ref keeps the template's pin (#862)"
for ref in refs/heads/main refs/heads/fix/e2e refs/heads/release/notes refs/tags/release/v9.9.9 refs/tags/v9.9.9; do
  run "GITHUB_REF=$ref" "GITHUB_SHA=$rel"; check "$ref: merged and deleted" ok $?
  is "nothing committed or pushed" not saw "^git -C "
  is "the pins line keeps the template's pin" said "^pins: .*python-ci.yml@stub-sha"
  is "no called run is read" not saw "^gh run view "
  is "no called line" not said "called job.workflow_sha"
done
run; check "no ref at all (a person's run): merged and deleted" ok $?
is "nothing committed or pushed" not saw "^git -C "
is "the pins line keeps the template's pin" said "^pins: .*python-ci.yml@stub-sha"

echo
echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
