#!/usr/bin/env bash
# The door's failure paths, offline. The one property scripts/new-project.sh
# must keep: nothing is created until preflight passes, and once created, a
# failure that leaves the wall down deletes the repository.
#
# "Any failure deletes" is not the contract and has not been for a while: a
# label that cannot be created, a CodeQL default setup slow to configure or to
# pick the first pull request up, a CI run seen but not seen twice, and a
# default branch repaired before the wall went up all warn and carry on. Each
# of those has a case here asserting `deleted=no`, because a rollback over one
# of them would delete a repository whose wall is standing (#97).
#
# The success path is visible by eye; the failure paths only by failing them,
# which needs a repository, so `gh` is a mock. It records every call and fails
# at the step FAIL_AT names. The verdicts: was `gh repo create` called, was
# `gh repo delete` called.
# shellcheck disable=SC2034  # log and proj are used inside the check() command strings
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
real_git="$(command -v git)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/claude"
printf '{"sandbox":{"enabled":true}}' > "$work/claude/settings.json"

# ── mock: gh ─────────────────────────────────────────────────────────────
cat > "$work/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -u
printf 'gh %s\n' "$*" >> "$GH_LOG"
all="$*"; step=other
case "$all" in
  "auth status"*)                                step=auth ;;
  "api -i user"*)                                step=headers ;;
  "api user --jq .login"*)                       step=login ;;
  "api users/"*)                                 step=owner ;;
  "api orgs/"*"/memberships/"*)                  step=membership ;;
  "api /licenses/"*".spdx_id"*)                  step=license-check ;;
  *"/contents/copier.yml"*)                      step=choices ;;
  "api -X GET repos/"*"/actions/runs "*)          step=runs ;;
  "api repos/"*"/languages"*)                    step=languages ;;
  "api repos/"*"/code-scanning/default-setup"*)  step=setup-read ;;
  *code-scanning*"languages[]"*)                 step=codeql-langs ;;
  *"/code-scanning/analyses"*)                   step=analyses ;;
  "api repos/"*"/actions/workflows"*)            step=workflows ;;
  "api repos/"*"/commits/"*"/check-runs"*)       step=checkruns ;;
  # GitHub reads a community-health file from the root, `.github/` or `docs/`,
  # and the door asks about all of them: match the name, not one path.
  *"/contents/"*"PULL_REQUEST_TEMPLATE.md"*)     step=shared-pr ;;
  "api repos/"*"/.github --jq .visibility"*)     step=shared-visibility ;;
  *"/contents/.github/ISSUE_TEMPLATE/"*)         step=shared-form-body ;;
  *"/contents/"*"ISSUE_TEMPLATE"*)               step=shared-forms ;;
  "api repos/"*" --jq .html_url"*)               step=exists ;;
  "api repos/"*" --jq .default_branch"*)         step=default-branch ;;
  *"default_branch=main"*)                       step=set-default ;;
  "repo create"*)                                step=create ;;
  "repo delete"*)                                step=delete ;;
  "label create"*)                               step=label ;;
  "pr create"*)                                  step=pr ;;
  *code-scanning*)                               step=codeql ;;
  *"/rulesets"*)                                 step=ruleset ;;
  *security_and_analysis*)                       step=secret ;;
  *vulnerability-alerts*|*automated-security-fixes*) step=dependabot ;;
  *selected-actions*)                            step=allowlist ;;
  *actions/permissions*)                         step=actions ;;
  *allow_merge_commit*)                          step=merge ;;
esac
# `codeql` fails both PATCHes (with the language list and the bare fallback);
# `codeql-langs` refuses only the list.
if [ "$step" = "${FAIL_AT:-}" ] || { [ "$step" = codeql-langs ] && [ "${FAIL_AT:-}" = codeql ]; }; then
  echo "mock gh: failing at $step on purpose" >&2; exit 1; fi
case "$step" in
  auth)          [ "${MOCK_NOAUTH:-0}" = 1 ] && exit 1 ;;
  headers)       printf 'HTTP/2.0 200 OK\n'
                 [ "${MOCK_FINE:-0}" = 1 ] || printf 'X-Oauth-Scopes: %s\n' "${MOCK_SCOPES-gist, read:org, repo, workflow, delete_repo}"
                 printf '\n{"login":"tester"}\n' ;;
  login)         echo tester ;;
  owner)         case "$all" in *users/nobody*) exit 1 ;; *users/someorg*) echo Organization ;; *) echo User ;; esac ;;
  membership)    [ "${MOCK_MEMBER:-1}" = 1 ] || exit 1; echo member ;;
  license-check) case "$all" in *licenses/mit*) echo MIT ;; *licenses/apache-2.0*) echo Apache-2.0 ;; *licenses/gpl-3.0*) echo GPL-3.0 ;; *) exit 1 ;; esac ;;
  choices)       printf 'license:\n  type: str\n  default: MIT\n  choices:\n    MIT: MIT\n    Apache-2.0: Apache-2.0\narchetype:\n  type: str\n  choices:\n    CLI: cli\n    Library: library\n    Backend: backend\n    Data: data-ml\nplinth_sha:\n' | base64 ;;
  # The owner's shared community-health files: present, absent (404) or
  # unreadable (any other failure). `gh` prints "Not Found" on a 404.
  shared-pr)     case "${MOCK_SHARED_PR:-absent}" in
                   present) echo '{"path":"PULL_REQUEST_TEMPLATE.md"}' ;;
                   error)   echo "mock gh: HTTP 500" >&2; exit 1 ;;
                   *)       echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
                 esac ;;
  # The door asks for `--jq .[].name`, so the mock answers names, one per line.
  # `gitkeep` and `config` are folders that exist and hold no template.
  # Only a public `.github` repository is inherited from; a private one is
  # readable through the API and applies to nothing.
  shared-visibility)
                 case "${MOCK_SHARED_VISIBILITY:-public}" in
                   private) echo private ;;
                   error)   echo "mock gh: HTTP 500" >&2; exit 1 ;;
                   missing) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
                   *)       echo public ;;
                 esac ;;
  # The listing (names, one per line) and then each candidate's content, which
  # the door reads before believing the name.
  shared-forms)  case "${MOCK_SHARED_FORMS:-absent}" in
                   present|empty) printf 'bug.yml\n' ;;
                   gitkeep) printf '.gitkeep\n' ;;
                   config)  printf 'config.yml\n' ;;
                   error)   echo "mock gh: HTTP 500" >&2; exit 1 ;;
                   *)       echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
                 esac ;;
  shared-form-body)
                 case "${MOCK_SHARED_FORMS:-absent}" in
                   present) printf 'name: Bug\ndescription: x\nlabels: [bug]\nbody: []\n' | base64 ;;
                   empty)   printf '' | base64 ;;
                   *)       echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
                 esac ;;
  exists)        [ "${MOCK_EXISTS:-0}" = 1 ] || exit 1; echo "https://github.com/x/y" ;;
  # GitHub adopts the first branch pushed to an empty repository as the default.
  # The mock answers what the door pushed first, so a run that pushes anything
  # before main is a run whose default branch is not main (#105). Once the door
  # has repaired it, the answer is main -- unless the repair itself failed, so
  # `FAIL_AT=set-default` is a repair that does not take.
  default-branch) if [ -e "$FIRST_PUSHED_FILE.patched" ]; then echo main
                  else echo "${MOCK_DEFAULT_BRANCH:-$(cat "$FIRST_PUSHED_FILE" 2>/dev/null)}"; fi ;;
  set-default)   : > "$FIRST_PUSHED_FILE.patched" ;;
  delete)        [ "${MOCK_DELETE_FAILS:-0}" = 1 ] && exit 1 ;;
  pr)            echo "https://github.com/tester/probe/pull/1" ;;
  # On main the door asks for default setup's first run, completed: the jq
  # leaves its `updated_at`, so the answer is a time, or nothing.
  runs)          case "$all" in *branch=main*) case "${MOCK_CODEQL_MAIN:-done}" in done) echo 2026-09-10T00:01:00Z ;; error) exit 1 ;; esac; exit 0 ;; esac
                 case "${MOCK_RUNS:-ok}" in
                   ok)      printf '.github/workflows/label.yml completed success\n.github/workflows/ci.yml queued null\n' ;;
                   startup) printf '.github/workflows/ci.yml completed startup_failure\n' ;;
                   # Listed once, then gone: the run exists, but the door never
                   # sees it on two polls in a row (#108).
                   once)    if [ -e "$FIRST_PUSHED_FILE.run-seen" ]; then printf '.github/workflows/label.yml completed success\n'
                            else : > "$FIRST_PUSHED_FILE.run-seen"; printf '.github/workflows/label.yml completed success\n.github/workflows/ci.yml queued null\n'; fi ;;
                   # No run at all: a real misconfiguration, and still fatal.
                   none)    printf '.github/workflows/label.yml completed success\n' ;;
                 esac ;;
  # GitHub's language detection, some time after the first push; then default
  # setup's state and languages, as the door's jq joins them.
  languages)     [ "${MOCK_LANGUAGES:-python}" = python ] && printf 'Python\n' ;;
  setup-read)    printf '%s %s 2026-09-10T00:01:30Z\n' "${MOCK_SETUP:-configured}" "${MOCK_SETUP_LANGS:-actions,python}" ;;
  # The other candidates the door records: the dynamic workflow, and main's
  # analysis listed (the one the push waits for, with the run); a 404 body on
  # stdout, as gh prints one, must not be read as a value.
  workflows)     echo 'active, created 2026-09-10T00:00:30Z, updated 2026-09-10T00:01:00Z' ;;
  analyses)      case "${MOCK_CODEQL_MAIN:-done}" in done) echo '2026-09-10T00:02:00Z /language:python' ;;
                   *) echo '{"message":"no analysis found","status":"404"}'; exit 1 ;; esac ;;
  checkruns)     printf 'ci / lint\nci / test\n'; [ "${MOCK_CODEQL:-present}" = present ] && printf 'CodeQL\nAnalyze (python)\n' ;;
esac
exit 0
MOCK

# ── mock: uvx (copier only): renders what the box would ────────────────
cat > "$work/bin/uvx" <<'MOCK'
#!/usr/bin/env bash
set -u
printf 'uvx %s\n' "$*" >> "$GH_LOG"
case "$*" in *copier*copy*) ;; *) exit 0 ;; esac
if [ "${FAIL_AT:-}" = copier ]; then echo "mock copier: refusing on purpose" >&2; exit 1; fi
dst="${!#}"; pname=""; plic=""; powner=""
for a in "$@"; do case "$a" in project_name=*) pname="${a#*=}" ;; license=*) plic="${a#*=}" ;; owner=*) powner="${a#*=}" ;; esac; done
: "${pname:?mock copier: no --data project_name}"; : "${plic:?mock copier: no --data license}"
: "${powner:?mock copier: no --data owner}"
# `-` last inside the brackets: GNU tr reads '.- ' as a range (a CI-only failure, 2026-08-28).
pkg="$(printf '%s' "$pname" | sed 's/[.[:space:]-]/_/g' | tr '[:upper:]' '[:lower:]')"
mkdir -p "$dst/tests" "$dst/src/$pkg" "$dst/.github/workflows"
printf '%s\n' "$plic" > "$dst/LICENSE"
printf '# %s\n' "$pname" > "$dst/README.md"
printf 'name = "%s"\nlicense = "%s"\nauthors = [{ name = "%s" }]\n' "$pkg" "$plic" "$powner" > "$dst/pyproject.toml"
printf 'name = "%s"\n' "$pkg" > "$dst/uv.lock"
: > "$dst/src/$pkg/__init__.py"; printf 'name: CI\n' > "$dst/.github/workflows/ci.yml"
printf '_commit: mock\n' > "$dst/.copier-answers.yml"
exit 0
MOCK

# ── mock: git (push only) · uv (presence) · claude (version) ───────────
cat > "$work/bin/git" <<'MOCK'
#!/usr/bin/env bash
set -u
[ "$1" = --version ] && { echo "git version ${MOCK_GIT_VERSION:-2.45.0}"; exit 0; }
for a in "$@"; do
  if [ "$a" = push ]; then
    printf 'git %s\n' "$*" >> "$GH_LOG"
    [ "${FAIL_AT:-}" = push ] && { echo "mock git: push refused on purpose" >&2; exit 1; }
    # An empty repository takes the first branch pushed as its default branch,
    # and the gh mock reads this file back. Last argument, minus any refspec
    # prefix: `HEAD:refs/heads/x` pushes `x`, `-u origin main` pushes `main`.
    if [ ! -e "$FIRST_PUSHED_FILE" ]; then
      last="${*: -1}"; printf '%s' "${last##*[:/]}" > "$FIRST_PUSHED_FILE"
    fi
    exit 0
  fi
done
exec "$REAL_GIT" "$@"
MOCK
printf '#!/usr/bin/env bash\nexit 0\n' > "$work/bin/uv"
printf '#!/usr/bin/env bash\nexit 0\n' > "$work/bin/sleep"   # the poll's pause, skipped
printf '#!/usr/bin/env bash\n[ "${MOCK_CLAUDE_OLD:-0}" = 1 ] && { echo "2.0.0 (Claude Code)"; exit 0; }\necho "2.1.240 (Claude Code)"\n' > "$work/bin/claude"
chmod +x "$work/bin/"*
mkdir -p "$work/bin-nouv"; for f in gh git uvx claude sleep; do cp "$work/bin/$f" "$work/bin-nouv/"; done

export REAL_GIT="$real_git"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export CLAUDE_CONFIG_DIR="$work/claude"
unset GH_TOKEN GITHUB_TOKEN PLINTH_TOKEN_SOURCE

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %-16s %s\n' "$1" "$2"; }
bad() { fail=$((fail+1)); printf '  FAIL  %-16s %s\n' "$1" "$2"; }
# run <case> <want exit: ok|err> <want create: yes|no> <want delete: yes|no> <expected output substring> -- <script args...>
# E="VAR=x ..." sets environment for the run; P=<dir> replaces the mock bin directory. Both reset after.
run() {
  local case="$1" want_exit="$2" want_create="$3" want_del="$4" want_text="$5"; shift 5; [ "$1" = -- ] && shift
  local home="$work/home-$case" rc created=no del=no ok=1
  mkdir -p "$home"; export HOME="$home" GH_LOG="$home/calls.log" FIRST_PUSHED_FILE="$home/first-pushed"
  : > "$GH_LOG"; rm -f "$FIRST_PUSHED_FILE" "$FIRST_PUSHED_FILE.patched" "$FIRST_PUSHED_FILE.run-seen"
  ( cd "$home" && env ${E:-} PATH="${P:-$work/bin}:/usr/bin:/bin" "$root/scripts/new-project.sh" "$@" ) >"$home/out" 2>&1; rc=$?
  grep -q '^gh repo create' "$GH_LOG" && created=yes
  grep -q '^gh repo delete' "$GH_LOG" && del=yes
  [ "$want_exit" = ok ] && [ "$rc" -ne 0 ] && ok=0
  [ "$want_exit" = err ] && [ "$rc" -eq 0 ] && ok=0
  [ "$created" = "$want_create" ] || ok=0
  [ "$del" = "$want_del" ] || ok=0
  [ -z "$want_text" ] || grep -qF -- "$want_text" "$home/out" || ok=0
  if [ "$ok" = 1 ]; then
    ok "$case" "exit=$rc created=$created deleted=$del"
  else
    bad "$case" "exit=$rc (want $want_exit) created=$created (want $want_create) deleted=$del (want $want_del) text=${want_text:-any}"
    sed 's/^/        /' "$home/out"
  fi
  E=""; P=""
}

echo "preflight: nothing is created, and the message names the fix"
P="$work/bin-nouv" run no-uv          err no no "uv is not installed"                       -- probe
E="MOCK_CLAUDE_OLD=1" run claude-old    err no no "below the supported floor"                -- probe
E="MOCK_GIT_VERSION=2.27.0" run git-old  err no no "git 2.27.0 is too old"                    -- probe
E="FAIL_AT=headers"   run token-unread   err no no "cannot read api.github.com/user"          -- probe
E="MOCK_NOAUTH=1"     run gh-logged-out err no no "gh auth login"                            -- probe
E="MOCK_SCOPES=repo"  run scope-missing err no no "lacks the scope(s) workflow"              -- probe
E="MOCK_FINE=1"       run fine-grained  err no no "with-admin-token.sh"                      -- probe --archetype=backend
# The fix line is copied out of wrapped chat output. One ~250-character line
# with two absolute plugin paths arrived as three commands, three times (#125):
# so it is printed as three short lines, a directory assignment, a call
# through it, and the arguments joined by a backslash (#132: the call with
# its arguments still wrapped at 80 columns). `P=` runs on its own if the
# paste splits the lines; the backslash keeps the call and its arguments one
# command.
if grep -qxF "    P=$root/scripts" "$work/home-fine-grained/out" \
   && grep -qxF '    "$P/with-admin-token.sh" "$P/new-project.sh" \' "$work/home-fine-grained/out" \
   && grep -qxF '      probe --archetype=backend' "$work/home-fine-grained/out"
then ok fine-grained "the fix is three short lines: P=<scripts dir>, the call through \$P \\, the arguments"
else bad fine-grained "the fix line is not in the copy-safe three-line shape"; grep -A4 "fix:" "$work/home-fine-grained/out" | sed 's/^/        /'; fi
# Pasted as one block into a shell, the three lines are two commands and the
# arguments reach the second one (the paste is simulated; the copy is not).
# No terminal here, so the token comes from stdin, as in CI.
paste_script="$(printf '%s\n' "P=$root/scripts" '"$P/with-admin-token.sh" /bin/echo RAN \' '  probe --archetype=backend')"
paste_out="$(bash -c "$paste_script" <<<"ghp_$(printf 'x%.0s' $(seq 36))" 2>&1)"
case "$paste_out" in *"RAN probe --archetype=backend"*) ok fine-grained "the three lines pasted into bash run as one call with its arguments" ;;
  *) bad fine-grained "the pasted three lines did not reach the call's arguments"; printf '%s\n' "$paste_out" | sed 's/^/        /' ;; esac
# A user typed the hint's placeholder literally; the refusal must name the
# bare form as valid, or an agent "corrects" it to owner/name (#125).
run angle-brackets err no no "is not <name> or <owner>/<name>"                                 -- '<probe>'
run owner-unknown  err no no "does not exist on GitHub"                                      -- nobody/probe
run owner-other    err no no "user account other than yours"                                -- alice/probe
E="MOCK_MEMBER=0"     run org-nonmember err no no "not a member of the organization"         -- someorg/probe
# The owner's shared templates decide what the box writes. A lookup that failed
# is not an answer: writing ours could replace theirs, skipping ours could leave
# none, so it stops before the repository exists (#88).
E="MOCK_SHARED_PR=error"    run shared-unreadable  err no no "cannot read whether tester/.github publishes" -- probe
# "A failed lookup is not an answer" is only actionable if the reader is told
# what failed. The functions run in command substitutions, which are subshells,
# so the reason travels on stdout beside the verdict.
if grep -qF "the API said: docs/PULL_REQUEST_TEMPLATE.md: mock gh: HTTP 500" "$work/home-shared-unreadable/out"
then ok shared-unreadable "the stop carries the path and the API's own words, not a placeholder"
else bad shared-unreadable "the stop does not say what failed"; grep -A2 "cannot read" "$work/home-shared-unreadable/out" | sed 's/^/        /'; fi
E="MOCK_SHARED_FORMS=error" run shared-forms-error err no no "--force-defaults"                             -- probe
run private        err no no "private repositories are not supported yet"                   -- probe --private
run private-first  err no no "private repositories are not supported yet"                   -- --private probe
run two-names      err no no "one name only"                                                -- probe other
run bad-option     err no no "unknown option: --nope"                                       -- probe --nope
E="MOCK_EXISTS=1"     run repo-exists   err no no "already exists; the door creates new"     -- probe
run license-typo   err no no "unknown license: bogus"                                       -- probe --license=bogus
# copier refuses a license outside its choices only after the repository exists;
# the door reads the template's own list and stops before creating anything.
run license-unsupported err no no "the template does not carry the license GPL-3.0"          -- probe --license=gpl-3.0
run archetype-typo err no no "the template accepts: cli library backend data-ml"            -- probe --archetype=service
# `mkdir ~/x; cd ~/x; claude` then the door: an empty directory is where the
# user wants the project, not a collision (#125). A non-empty one still is.
mkdir -p "$work/home-dir-exists/probe"; : > "$work/home-dir-exists/probe/notes.txt"
run dir-exists     err no no "already exists and is not an empty directory"                 -- probe
mkdir -p "$work/home-dir-empty/probe"
run dir-empty      ok yes no "" -- probe
# A listing that fails is not an empty directory: refused here, not after the
# repository exists (a Sonnet review of this change).
mkdir -p "$work/home-dir-unreadable/probe"; chmod 000 "$work/home-dir-unreadable/probe"
run dir-unreadable err no no "already exists and is not an empty directory"                 -- probe
chmod 755 "$work/home-dir-unreadable/probe"
mkdir -p "$work/home-nested" && ( cd "$work/home-nested" && "$real_git" init -q -b main )
run nested         err no no "inside the repository"                                        -- probe
# --private is refused before any gh call at all.
if [ ! -s "$work/home-private/calls.log" ]; then ok private-no-call "no gh call before the refusal"
else bad private-no-call "gh was called before refusing --private"; fi

echo "warnings: continue, and say so"
E="GH_TOKEN=x"        run env-token     ok yes no "warning: GH_TOKEN is set in the environment" -- probe
E="GH_TOKEN=x PLINTH_TOKEN_SOURCE=prompt" run env-token-admin ok yes no "" -- probe
if grep -q "warning: GH_TOKEN" "$work/home-env-token-admin/out"; then bad env-token-admin "the admin path warned about its own GH_TOKEN"
else ok env-token-admin "the admin path does not warn about its own GH_TOKEN"; fi
E="CLAUDE_CONFIG_DIR=$work/nowhere" run sandbox-off ok yes no "warning: sandbox is off" -- probe
mkdir -p "$work/claude-local"; printf '{}' > "$work/claude-local/settings.json"; printf '{"sandbox":{"enabled":true}}' > "$work/claude-local/settings.local.json"
E="CLAUDE_CONFIG_DIR=$work/claude-local" run sandbox-local ok yes no "" -- probe
if grep -q "warning: sandbox" "$work/home-sandbox-local/out"; then bad sandbox-local "sandbox on in settings.local.json still warned"
else ok sandbox-local "sandbox on in settings.local.json is seen"; fi
E="MOCK_SCOPES=repo,workflow" run rollback-off ok yes no "rollback: off (no delete_repo scope" -- probe
E="MOCK_FINE=1 PLINTH_TOKEN_SOURCE=prompt" run fine-admin ok yes no "rollback: best effort" -- probe
# Labels are a convenience, not a wall stone: a failed create names the label and
# the run carries on. A rollback over a label would delete a repository whose wall is up.
E="FAIL_AT=label"     run label-fails   ok yes no "warning: could not create the label task" -- probe
E="MOCK_SHARED_PR=present MOCK_SHARED_FORMS=present" run shared-both ok yes no "already publishes: pull-request template issue forms" -- probe
E="MOCK_SHARED_PR=present" run shared-pr-only ok yes no "already publishes: pull-request template" -- probe
# Only a public `.github` is inherited from. A private one reads fine through the
# API and applies to nothing, so believing it would leave the new repository with
# neither the owner's templates nor ours.
E="MOCK_SHARED_VISIBILITY=private MOCK_SHARED_PR=present MOCK_SHARED_FORMS=present" run shared-private ok yes no "" -- probe
if grep -q -- "owner_has_pr_template=false" "$work/home-shared-private/calls.log" \
  && ! grep -q "contents/PULL_REQUEST_TEMPLATE" "$work/home-shared-private/calls.log"
then ok shared-private "a private .github is not inherited from, and is not even asked for its files"
else bad shared-private "a private .github was treated as shared"; fi
E="MOCK_SHARED_VISIBILITY=missing" run shared-no-repo ok yes no "" -- probe
E="MOCK_SHARED_VISIBILITY=error"   run shared-vis-error err no no "cannot read whether tester/.github is public" -- probe
# A folder is not a template. floor-check.py reads a `.gitkeep`-only folder as
# "no local forms, the shared set applies"; the box must read the owner's folder
# the same way, or the repository ends up with no forms anywhere (#88).
for empty in gitkeep config empty; do
  E="MOCK_SHARED_FORMS=$empty" run "shared-forms-$empty" ok yes no "" -- probe
  if grep -q -- "owner_has_issue_forms=false" "$work/home-shared-forms-$empty/calls.log"
  then ok "shared-forms-$empty" "a shared folder holding only $empty is not forms; the box renders its own"
  else bad "shared-forms-$empty" "the box suppressed its forms for a folder with no usable template"; fi
done
if grep -q "does not follow tester/.github's pull-request template" "$work/home-shared-pr-only/calls.log"; then ok shared-pr-only "the first pull request says it does not follow the inherited template"
else bad shared-pr-only "the first pull request is silent about the inherited template"; fi
if grep -q "^gh pr create.*## What and why" "$work/home-shared-pr-only/calls.log"; then bad shared-pr-only "plinth's headings were imposed over the owner's template"
else ok shared-pr-only "plinth's headings are not imposed over the owner's template"; fi
E="MOCK_SHARED_PR=error MOCK_SHARED_FORMS=error" run forced-defaults ok yes no "" -- probe --force-defaults
run org-member     ok yes no "as member"                                                    -- someorg/probe
run apache         ok yes no "(public, Apache-2.0, cli, as owner)"                           -- probe --license=apache-2.0
# The spdx id is still looked up (`mit` -> `MIT`); the license *text* is not:
# the template renders LICENSE from the choice, so a fetch would write over it.
if grep -q 'license=Apache-2.0' "$work/home-apache/calls.log" && ! grep -q -- '--jq .body' "$work/home-apache/calls.log"
then ok apache "the chosen license reaches copier, and no license text is fetched over the render"
else bad apache "the license did not reach copier, or its text was fetched over the render"; fi

echo "after creation: any failure deletes"
for at in copier push default-branch codeql ruleset secret dependabot actions allowlist merge pr; do
  E="FAIL_AT=$at" run "$at" err yes yes "" -- probe
done
E="MOCK_RUNS=startup" run startup-failure err yes yes "failed at startup" -- probe
# A pull request opened before CodeQL default setup has finished configuring is
# never analysed (measured three times, #62 and #120; the comment in the door
# has the times). The wall still stands, so no analysis on the first pull
# request warns and names the re-push; it does not delete the repository.
E="MOCK_CODEQL=absent PLINTH_FIRST_PR_WAIT=1" run codeql-absent ok yes no "warning: CodeQL has not picked up the first pull request" -- probe
if grep -q "git commit --allow-empty" "$work/home-codeql-absent/out"; then ok codeql-absent "the summary names the re-push"
else bad codeql-absent "the summary does not name the re-push"; fi
# The readiness signal is two reads: default setup reports `configured`, and
# its first run on main has completed. Either one missing within the wait
# warns, pushes anyway, and keeps the re-push at the end.
E="MOCK_CODEQL_MAIN=absent PLINTH_FIRST_PR_WAIT=1" run codeql-main-late ok yes no "warning: CodeQL default setup has not completed its first analysis of main" -- probe
E="MOCK_SETUP=not-configured PLINTH_FIRST_PR_WAIT=1" run codeql-unconfigured ok yes no "warning: CodeQL default setup has not completed its first analysis of main" -- probe
# A read that fails (rate limit, a 5xx) is not an answer and not a wall failure:
# the poll asks again, the wait runs out, and the repository stays (a Sonnet
# review of this change: the unguarded read aborted the door under set -e).
E="MOCK_CODEQL_MAIN=error PLINTH_FIRST_PR_WAIT=1" run codeql-main-unreadable ok yes no "warning: CodeQL default setup has not completed its first analysis of main" -- probe
if ! grep -q "analysis: {" "$work/home-codeql-main-unreadable/out" && grep -q "analysis of main listed: none" "$work/home-codeql-main-unreadable/out"
then ok codeql-main-unreadable "a 404 body is not recorded as an analysis (run 2 of the measurement did)"
else bad codeql-main-unreadable "the 404 body was read as an analysis"; grep analysis "$work/home-codeql-main-unreadable/out" | sed 's/^/        /'; fi
if grep -q "(state: not-configured, first run on main: 2026-09-10T00:01:00Z, analysis of main listed: 2026-09-10T00:02:00Z /language:python)" "$work/home-codeql-unconfigured/out"; then ok codeql-unconfigured "the warning says which of the reads is missing"
else bad codeql-unconfigured "the warning does not say what was read"; grep warning "$work/home-codeql-unconfigured/out" | sed 's/^/        /'; fi
# Default setup enabled before GitHub's language detection has run analyses
# `actions` alone (#120 finding I): detection that never lists Python warns, and
# the list is spelled out on the enable regardless.
E="MOCK_LANGUAGES=none PLINTH_FIRST_PR_WAIT=1" run languages-late ok yes no "warning: GitHub has not detected Python" -- probe
if grep -q "code-scanning/default-setup -f state=configured -f query_suite=default -f languages\[\]=actions -f languages\[\]=python" "$work/home-languages-late/calls.log"
then ok languages-late "default setup is still enabled with actions and python spelled out"
else bad languages-late "default setup was enabled without the language list"; grep code-scanning "$work/home-languages-late/calls.log" | sed 's/^/        /'; fi
# A list GitHub refuses: enabled bare, the fix named, no rollback (the wall stands).
E="FAIL_AT=codeql-langs" run codeql-langs-refused ok yes no "warning: CodeQL default setup refused the language list" -- probe
if [ "$(grep -c "code-scanning/default-setup -f state=configured" "$work/home-codeql-langs-refused/calls.log")" = 2 ] \
   && grep -q "PATCH repos/tester/probe/code-scanning/default-setup -f 'languages\[\]=actions' -f 'languages\[\]=python'" "$work/home-codeql-langs-refused/out"
then ok codeql-langs-refused "the bare enable follows, and the fix line carries the list"
else bad codeql-langs-refused "no bare enable, or no fix line"; grep -E "code-scanning|warning" "$work/home-codeql-langs-refused/calls.log" "$work/home-codeql-langs-refused/out" | sed 's/^/        /'; fi
# What default setup reports analysing is read back: Python missing is said,
# with the one command that adds it.
E="MOCK_SETUP_LANGS=actions" run codeql-actions-only ok yes no "warning: CodeQL default setup analyses [actions] and not the Python under src/" -- probe
if grep -q "fix: gh api -X PATCH repos/tester/probe/code-scanning/default-setup -f 'languages\[\]=actions' -f 'languages\[\]=python'" "$work/home-codeql-actions-only/out"
then ok codeql-actions-only "the fix is the one PATCH measured to work"
else bad codeql-actions-only "no fix line"; grep warning "$work/home-codeql-actions-only/out" | sed 's/^/        /'; fi
# "Seen twice in a row" is about stability; "did it ever appear" is about
# existence. One counter answered both, so a run listed on the poll that ran out
# of time was reported as never appearing and the repository was deleted (#108).
# A run seen once: the wall stands, it warns, it does not delete.
E="MOCK_RUNS=once PLINTH_FIRST_PR_WAIT=1" run run-seen-once ok yes no "was not listed on two polls in a row" -- probe
# No run at all is still a misconfiguration, and still fatal.
E="MOCK_RUNS=none PLINTH_FIRST_PR_WAIT=1" run run-never err yes yes "its checks would never report" -- probe
# The race the same bug produced in this suite: with the budget spent before the
# first poll returns, the door must still not delete a repository whose run it
# just listed. `=0` is `=1` with the timing taken out.
E="MOCK_CODEQL=absent PLINTH_FIRST_PR_WAIT=0" run deadline-zero ok yes no "warning: CodeQL has not picked up the first pull request" -- probe
E="PLINTH_FIRST_PR_WAIT=soon" run wait-typo err no no "PLINTH_FIRST_PR_WAIT must be a whole number" -- probe
# The defect #105 was: a throwaway probe branch was pushed first, GitHub adopted
# it as the default branch of the empty repository and then refused to delete
# it, and the ruleset (~DEFAULT_BRANCH) went up on the probe while main was left
# open. A default branch that is not main is repaired, not rolled back: main was
# just pushed, so pointing HEAD at it costs one call, and deleting a repository
# over which branch HEAD names is worse than the fault.
E="MOCK_DEFAULT_BRANCH=__push-probe" run default-branch-repaired ok yes no "was __push-probe, not main" -- probe
if grep -q -- "-X PATCH -f default_branch=main" "$work/home-default-branch-repaired/calls.log" &&
   [ "$(grep -n "default_branch=main" "$work/home-default-branch-repaired/calls.log" | head -1 | cut -d: -f1)" \
     -lt "$(grep -n "/rulesets" "$work/home-default-branch-repaired/calls.log" | head -1 | cut -d: -f1)" ]
then ok default-branch-repaired "the default branch is pointed at main before the ruleset is applied"
else bad default-branch-repaired "the ruleset was applied without the default branch being repaired"; fi
# A repair that does not take is the one thing that rolls back: the wall would
# otherwise go up on the wrong branch and leave main open.
E="MOCK_DEFAULT_BRANCH=__push-probe FAIL_AT=set-default" run default-branch-stuck err yes yes "could not be changed" -- probe
E="FAIL_AT=ruleset MOCK_DELETE_FAILS=1" run delete-fails err yes yes "ROLLBACK FAILED: https://github.com/tester/probe EXISTS WITHOUT A WALL" -- probe

echo "success: nothing is deleted, and the order is baseline, wall, first pull request"
run none ok yes no "first pull request: https://github.com/tester/probe/pull/1" -- probe
log="$work/home-none/calls.log"; proj="$work/home-none/probe"
check() { if eval "$2"; then ok none "$1"; else bad none "$1"; fi; }
check "main is pushed before the ruleset, the pull request after it" \
  '[ "$(grep -E "push -q -u origin main|/rulesets|^gh pr create" "$log" | sed -E "s/^git .*push.*/main/; s/.*rulesets.*/ruleset/; s/^gh pr create.*/pr/" | tr "\n" " ")" = "main ruleset pr " ]'
# main must be the *first* push: an empty repository adopts the first branch
# pushed as its default, and the ruleset targets ~DEFAULT_BRANCH (#105).
check "main is the first branch pushed" \
  'grep -E "^git .*push" "$log" | head -1 | grep -q -- "push -q -u origin main"'
check "no throwaway probe branch is pushed" '! grep -q "push-probe" "$log"'
check "the default branch is read back from the API before the ruleset is applied" \
  'grep -E "jq .default_branch|/rulesets" "$log" | head -1 | grep -q default_branch'
check "CodeQL default setup is enabled after GitHub lists the languages, with actions and python spelled out" \
  'grep -E "/languages|code-scanning/default-setup -f state" "$log" | head -1 | grep -q "/languages --jq" && grep -q "state=configured -f query_suite=default -f languages\[\]=actions -f languages\[\]=python" "$log"'
check "default setup reports configured and its first run on main has completed before the first pull request is pushed" \
  '[ "$(grep -E "default-setup --jq|branch=main|push -q -u origin docs/first-pr" "$log" | sed -E "s/.*default-setup --jq.*/setup/; s/.*branch=main.*/main/; s/.*docs\/first-pr.*/push/" | head -3 | tr "\n" " ")" = "setup main push " ]'
check "the door prints the times it saw, so a live run is its own record" \
  'grep -qE "^CodeQL default setup: enabled [0-9:]+Z, configured with languages \[actions,python\], first run on main completed 2026-09-10T00:01:00Z, analysis of main listed 2026-09-10T00:02:00Z /language:python, first pull request pushed [0-9:]+Z$" "$work/home-none/out" && [ "$(grep -cE "^  [0-9:]+Z (updated|workflow|run|analysis): " "$work/home-none/out")" = 4 ]'
check "the first pull request head is checked for a CodeQL check run" 'grep -q "/check-runs" "$log"'
check "the Actions allowlist names coolbress/plinth/*" 'grep -q "patterns_allowed\[\]=coolbress/plinth/\*" "$log"'
check "the Actions allowlist names nothing else" '[ "$(grep -o "patterns_allowed" "$log" | wc -l | tr -d " ")" = 1 ]'
check "Actions: selected, SHA pins required" 'grep -q "allowed_actions=selected -F sha_pinning_required=true" "$log"'
check "the squash commit is the pull request title and description" 'grep -q "squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY" "$log"'
# Issue forms are inherited from `.github/ISSUE_TEMPLATE` alone, and that is the
# only path floor-check.py reads: asking anywhere else would suppress our forms
# for something GitHub never offers.
check "issue forms are looked for in .github/ISSUE_TEMPLATE and nowhere else" \
  'grep -q "contents/.github/ISSUE_TEMPLATE --jq" "$log" && ! grep -q "docs/ISSUE_TEMPLATE" "$log"'
check "all three locations GitHub reads a shared pull-request template from are asked about" \
  '[ "$(grep -c "contents/.*PULL_REQUEST_TEMPLATE.md" "$log")" = 3 ]'
# Order, not shape: every question about the owner is answered before anything
# exists, so a wrong answer costs nothing.
check "the owner's shared templates are asked about before anything is created" \
  '[ "$(grep -n "^gh repo create" "$log" | cut -d: -f1)" -gt "$(grep -nE "contents/(.github/)?(PULL_REQUEST_TEMPLATE.md|ISSUE_TEMPLATE)|/.github --jq .visibility" "$log" | tail -1 | cut -d: -f1)" ]'
check "an owner with no shared templates gets the box's own copies" \
  'grep -q -- "owner_has_pr_template=false" "$log" && grep -q -- "owner_has_issue_forms=false" "$log"'
# The body is multi-line and the mock logs `gh $*`, so its first line lands on
# the `gh pr create` line and the rest follows: look for the pieces, not a shape.
check "the first pull request body carries the two sections, not one sentence" \
  'grep -q "^gh pr create.*## What and why" "$log" && grep -q "^## How it was verified$" "$log"'
check "the first pull request says what has not been verified yet" \
  'grep -q "the checks have not run" "$log"'
check "labels with a colon in the name are created with a hex colour (wayfinder:map)" 'grep -q "label create wayfinder:map --repo tester/probe --color 5319e7" "$log"'
check "every wayfinder label docs/agents/issue-tracker.md names is created (the map, and its 4 child types)" \
  '[ "$(grep -cE "label create wayfinder:(map|research|grilling|prototype|task) " "$log")" = 5 ]'
check "every label is created with --force, so GitHub's default set (wontfix) does not warn on every run" \
  'grep -q "^gh label create.* --force$" "$log" && [ "$(grep -c "^gh label create" "$log")" = "$(grep -c "^gh label create.* --force$" "$log")" ]'
check "the default branch is main" '[ "$("$REAL_GIT" -C "$proj" rev-parse --verify -q main)" != "" ]'
check "the first pull request is one README line on docs/first-pr" \
  '[ "$("$REAL_GIT" -C "$proj" rev-parse --abbrev-ref HEAD)" = docs/first-pr ] && [ "$("$REAL_GIT" -C "$proj" diff --stat main docs/first-pr | tail -1 | grep -o "[0-9]* insertion")" = "1 insertion" ]'
check "render is final: real name, owner and license in pyproject.toml and uv.lock, src/probe/, no bootstrap.sh" \
  'grep -q probe "$proj/pyproject.toml" && grep -q MIT "$proj/pyproject.toml" && grep -q tester "$proj/pyproject.toml" && grep -q probe "$proj/uv.lock" && [ -d "$proj/src/probe" ] && [ ! -e "$proj/bootstrap.sh" ]'
check "the summary line names owner, visibility, license, archetype, role and the template tag" \
  'grep -q "^create tester/probe (public, MIT, cli, as owner) from coolbress/plinth-template@v1.3.0 in " "$work/home-none/out"'

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
