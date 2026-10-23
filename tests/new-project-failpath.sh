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
  "api user --jq .plan"*|"api orgs/"*" --jq .plan"*) step=plan ;;
  "api orgs/"*"/memberships/"*)                  step=membership ;;
  "api /licenses/"*".spdx_id"*)                  step=license-check ;;
  *"/contents/copier.yml"*)                      step=choices ;;
  # The baseline's own CI run is asked for by its commit (#401), and re-run.
  "api -X GET repos/"*"/actions/runs "*"head_sha="*) step=baseline-runs ;;
  *"/rerun-failed-jobs"*)                        step=rerun ;;
  "api -X GET repos/"*"/actions/runs "*)          step=runs ;;
  "api repos/"*"/languages"*)                    step=languages ;;
  "api repos/"*"/code-scanning/default-setup"*)  step=setup-read ;;
  *code-scanning*"languages[]"*)                 step=codeql-langs ;;
  *"/code-scanning/analyses"*)                   step=analyses ;;
  "api repos/"*"/commits/"*"/check-runs"*)       step=checkruns ;;
  # GitHub reads a community-health file from the root, `.github/` or `docs/`,
  # and the door asks about all of them: match the name, not one path.
  *"/contents/"*"PULL_REQUEST_TEMPLATE.md"*)     step=shared-pr ;;
  "api repos/"*"/.github --jq .visibility"*)     step=shared-visibility ;;
  *"/contents/.github/ISSUE_TEMPLATE/"*)         step=shared-form-body ;;
  *"/contents/"*"ISSUE_TEMPLATE"*)               step=shared-forms ;;
  "api repos/"*" --jq "*security_and_analysis*)  step=security-read ;;
  "api repos/"*" --jq .html_url"*)               step=exists ;;
  "api repos/"*" --jq .default_branch"*)         step=default-branch ;;
  "api repos/"*" --jq "*"permissions.admin"*)    step=admin ;;
  "api repos/"*"/actions/permissions --silent"*) step=admin-probe ;;
  *"default_branch=main"*)                       step=set-default ;;
  "repo create"*)                                step=create ;;
  "repo delete"*)                                step=delete ;;
  "label create"*)                               step=label ;;
  "pr create"*)                                  step=pr ;;
  *code-scanning*)                               step=codeql ;;
  *"/rulesets"*"ruleset-merge.json"*)            step=ruleset-merge ;;
  "api repos/"*"/rulesets/"[0-9]*)               step=ruleset-read ;;
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
# A server error at one step: MOCK_5XX=<step>:<code>:<times> answers `gh: HTTP
# <code>` that many times, then succeeds (#356); `times` of 9 never succeeds.
if [ -n "${MOCK_5XX:-}" ] && [ "$step" = "${MOCK_5XX%%:*}" ]; then
  code="${MOCK_5XX#*:}"; times="${code#*:}"; code="${code%%:*}"
  n="$(cat "$HOME/5xx-count" 2>/dev/null || echo 0)"
  if [ "$n" -lt "$times" ]; then echo $((n + 1)) > "$HOME/5xx-count"; echo "gh: Server Error (HTTP $code)" >&2; exit 1; fi
fi
case "$step" in
  auth)          [ "${MOCK_NOAUTH:-0}" = 1 ] && exit 1 ;;
  headers)       printf 'HTTP/2.0 200 OK\n'
                 [ "${MOCK_FINE:-0}" = 1 ] || printf 'X-Oauth-Scopes: %s\n' "${MOCK_SCOPES-gist, read:org, repo, workflow, delete_repo}"
                 printf '\n{"login":"tester"}\n' ;;
  login)         echo tester ;;
  owner)         case "$all" in *users/nobody*) exit 1 ;; *users/someorg*) echo Organization ;; *) echo User ;; esac ;;
  membership)    [ "${MOCK_MEMBER:-1}" = 1 ] || exit 1; echo member ;;
  # The owner's plan, as the door's jq leaves it: a name, or nothing when the
  # token does not read it (measured 2026-10-01: a fine-grained token's
  # `GET /user` carries no `plan`). FAIL_AT=plan is a read that fails.
  plan)          [ "${MOCK_PLAN:-none}" = none ] || echo "$MOCK_PLAN" ;;
  # The new repository's security settings, as the door's jq leaves them: Code
  # Security, then Secret Protection (a comma here, since E= splits on spaces).
  # FAIL_AT=security-read is a read that fails.
  security-read) tr ',' ' ' <<<"${MOCK_SECURITY-disabled,disabled}" ;;
  license-check) case "$all" in *licenses/mit*) echo MIT ;; *licenses/apache-2.0*) echo Apache-2.0 ;; *licenses/gpl-3.0*) echo GPL-3.0 ;; *) exit 1 ;; esac ;;
  # The template's copier.yml, base64 as the contents API answers it. MOCK_CHOICES=
  # garbage is a body base64 cannot decode; nochoices decodes to a copier.yml
  # with no archetype or license choices where the door looks (#629).
  choices)       case "${MOCK_CHOICES:-ok}" in
                   garbage)   printf '!!! not base64 !!!' ;;
                   nochoices) printf 'plinth_sha:\n  type: str\n' | base64 ;;
                   *) printf 'license:\n  type: str\n  default: MIT\n  choices:\n    MIT: MIT\n    Apache-2.0: Apache-2.0\narchetype:\n  type: str\n  choices:\n    CLI: cli\n    Library: library\n    Backend: backend\n    Data: data-ml\n    Web: web\nplinth_sha:\n' | base64 ;;
                 esac ;;
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
  # The account's role on the new repository, as `permissions.admin` and
  # `role_name` answer; the log says whether an environment token was in reach
  # of the call. It is the role, not the token: a fine-grained token with
  # Administration at No access still answers `true` for the owner (measured
  # 2026-09-29, #300).
  admin)         printf 'admin-read GH_TOKEN=%s\n' "${GH_TOKEN:+set}" >> "$GH_LOG"
                 case "${MOCK_ADMIN-true}" in
                   error) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
                   *)     echo "${MOCK_ADMIN-true} ${MOCK_ROLE-admin}" ;;
                 esac ;;
  # A read that needs Administration: a fine-grained token without it gets this
  # 403 (measured, the same token as above); with it, even read-only, a 200.
  admin-probe)   printf 'admin-probe GH_TOKEN=%s\n' "${GH_TOKEN:+set}" >> "$GH_LOG"
                 case "${MOCK_ADMIN_PROBE:-ok}" in
                   denied) echo "gh: Resource not accessible by personal access token (HTTP 403)" >&2; exit 1 ;;
                   error)  echo "gh: HTTP 502" >&2; exit 1 ;;
                 esac ;;
  pr)            echo "https://github.com/tester/probe/pull/1" ;;
  # The door pipes the archetype's ruleset in (`--input -`); keep it for the checks.
  ruleset)       [ -t 0 ] || cat > "$HOME/ruleset-posted.json" ;;
  # The merge ruleset goes as the committed file (`--input <file>`); its id back.
  ruleset-merge) a="$all"; a="${a#*--input }"; cp "${a%% *}" "$HOME/ruleset-merge-posted.json"; echo 9 ;;
  # Read back after the write: what was posted, as GitHub adds to it, unless
  # MOCK_MERGE_READBACK says otherwise (a write that did not take as sent).
  ruleset-read)  if [ -n "${MOCK_MERGE_READBACK:-}" ]; then echo "$MOCK_MERGE_READBACK"
                 else jq '. + {id: 9, rules: [{type: "update", parameters: {update_allows_fetch_and_merge: false}}]}' "$HOME/ruleset-merge-posted.json"; fi ;;
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
  # The baseline's CI run on main, as the door's jq leaves it: id, status,
  # conclusion, attempt, page. It failed by default, as it does on GitHub: its
  # floor-check ran before the wall (#401). Once the door has asked for the
  # re-run, the answer is the second attempt, as MOCK_RERUN says it ended.
  baseline-runs) url=https://github.com/tester/probe/actions/runs/77
                 if [ -e "$HOME/rerun-asked" ]; then
                   case "${MOCK_RERUN:-green}" in
                     green)   echo "77 completed success 2 $url" ;;
                     red)     echo "77 completed failure 2 $url" ;;
                     running) echo "77 in_progress null 2 $url" ;;
                     unlisted) echo "77 completed failure 1 $url" ;;
                   esac
                 else
                   case "${MOCK_BASELINE:-failure}" in
                     failure) echo "77 completed failure 1 $url" ;;
                     success|skipped|neutral) echo "77 completed $MOCK_BASELINE 1 $url" ;;
                     running) echo "77 in_progress null 1 $url" ;;
                     error)   echo "gh: HTTP 502" >&2; exit 1 ;;
                     action_required) echo "77 completed action_required 1 $url" ;;
                     missing) ;;
                   esac
                 fi ;;
  rerun)         [ "${MOCK_RERUN:-green}" = refused ] && { echo "gh: Must have admin rights to Repository. (HTTP 403)" >&2; exit 1; }
                 : > "$HOME/rerun-asked" ;;
  # GitHub's language detection, some time after the first push; then default
  # setup's state and languages, as the door's jq joins them.
  languages)     [ "${MOCK_LANGUAGES:-python}" = python ] && printf 'Python\n' ;;
  setup-read)    printf '%s %s 2026-09-10T00:01:30Z\n' "${MOCK_SETUP:-configured}" "${MOCK_SETUP_LANGS:-actions,python}" ;;
  # Main's analyses, listed before the run completes (measured); a 404 body on
  # stdout, as gh prints one, must not be read as a value.
  analyses)      case "${MOCK_CODEQL_MAIN:-done}" in done) echo '2026-09-10T00:02:00Z /language:python' ;;
                   *) echo '{"message":"no analysis found","status":"404"}'; exit 1 ;; esac ;;
  # `after-repush`: CodeQL appears on the head only once the door has pushed
  # its empty commit (a bare `push -q`, unlike the branch's `push -q -u`).
  checkruns)     printf 'ci / lint\nci / test\n'
                 case "${MOCK_CODEQL:-present}" in
                   present) printf 'CodeQL\nAnalyze (python)\n' ;;
                   after-repush) grep -q 'push -q$' "$GH_LOG" && printf 'CodeQL\nAnalyze (python)\n' ;;
                 esac ;;
esac
exit 0
MOCK

# ── mock: uvx (copier only): renders what the box would ────────────────
cat > "$work/bin/uvx" <<'MOCK'
#!/usr/bin/env bash
set -u
printf 'uvx %s\n' "$*" >> "$GH_LOG"
case "$*" in *copier*copy*) ;; *) exit 0 ;; esac
[ "${MOCK_UVX_ENV:-0}" = 1 ] && env > "$HOME/uvx-env"
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
# The template tag's commit (#519): as GitHub answers an annotated tag, the
# tag object then its commit; MOCK_TAG=moved names another commit, gone
# answers nothing, error fails as an unreachable github.com does.
if [ "$1" = ls-remote ]; then
  printf 'git %s\n' "$*" >> "$GH_LOG"
  case "${MOCK_TAG:-pinned}" in
    pinned) printf '%040d\trefs/tags/%s\n%s\trefs/tags/%s^{}\n' 9 "$TEMPLATE_REF" "$TEMPLATE_SHA" "$TEMPLATE_REF" ;;
    moved)  printf '%040d\trefs/tags/%s\n%040d\trefs/tags/%s^{}\n' 9 "$TEMPLATE_REF" 1 "$TEMPLATE_REF" ;;
    gone)   ;;
    error)  echo "fatal: unable to access 'https://github.com/x/': Could not resolve host" >&2; exit 128 ;;
  esac
  exit 0
fi
for a in "$@"; do
  if [ "$a" = push ]; then
    printf 'git %s\n' "$*" >> "$GH_LOG"
    [ "${FAIL_AT:-}" = push ] && { printf '%b\n' "${MOCK_PUSH_ERR:-mock git: push refused on purpose}" >&2; exit 1; }
    [ "${FAIL_AT:-}" = push-branch ] && [ "${*: -1}" = docs/first-mr ] && { echo "mock git: branch push refused on purpose" >&2; exit 1; }
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
printf '#!/usr/bin/env bash\nprintf "sleep %%s\\n" "$*" >> "${GH_LOG:-/dev/null}"\nexit 0\n' > "$work/bin/sleep"   # the pause is skipped, and logged
printf '#!/usr/bin/env bash\n[ "${MOCK_CLAUDE_OLD:-0}" = 1 ] && { echo "2.0.0 (Claude Code)"; exit 0; }\necho "2.1.290 (Claude Code)"\n' > "$work/bin/claude"
chmod +x "$work/bin/"*
mkdir -p "$work/bin-nouv"; for f in gh git uvx claude sleep; do cp "$work/bin/$f" "$work/bin-nouv/"; done

export REAL_GIT="$real_git"
TEMPLATE_REF="$(sed -nE 's/^template_ref="([^"]+)"$/\1/p' "$root/scripts/new-project.sh")"
TEMPLATE_SHA="$(sed -nE 's/^template_sha="([0-9a-f]{40})"$/\1/p' "$root/scripts/new-project.sh")"
export TEMPLATE_REF TEMPLATE_SHA
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
# The separate terminal is one of two fixes, not a property of the door: a
# browser login with the scopes the door reads runs it in the session (#228).
if grep -qF "gh auth login -s repo,workflow,delete_repo" "$work/home-fine-grained/out"
then ok fine-grained "the stop also names the browser-login fix"
else bad fine-grained "the stop names only the admin-token fix"; fi
# Fix 2's token can be pre-filled: a creation link for the owner with the five
# repository permissions at write, `members=read` only for an organization; the
# repository selection has no parameter, so the stop names it (#285). Actions
# is the baseline's re-run of its failed jobs (#429).
link='https://github.com/settings/personal-access-tokens/new?'
perms='administration=write&contents=write&workflows=write&pull_requests=write&actions=write'
if grep -qF "$link" "$work/home-fine-grained/out" && grep -qF "target_name=tester&" "$work/home-fine-grained/out" \
   && grep -qF "$perms" "$work/home-fine-grained/out" && ! grep -qF "members=read" "$work/home-fine-grained/out" \
   && grep -qF '"All repositories"' "$work/home-fine-grained/out"
then ok fine-grained "fix 2 gives a pre-filled token link for the owner, without members, and names the one choice left"
else bad fine-grained "no pre-filled token link for a personal owner"; grep -F -A2 "personal-access-tokens" "$work/home-fine-grained/out" | sed 's/^/        /'; fi
E="MOCK_FINE=1"       run fine-grained-org err no no "with-admin-token.sh"                     -- someorg/probe
if grep -qF "target_name=someorg&" "$work/home-fine-grained-org/out" && grep -qF "$perms&members=read" "$work/home-fine-grained-org/out"
then ok fine-grained-org "an organization's link adds members=read"
else bad fine-grained-org "no organization token link with members=read"; grep -F "personal-access-tokens/new" "$work/home-fine-grained-org/out" | sed 's/^/        /'; fi
# An owner whose type cannot be read may be an organization: the link cannot
# claim its permissions are all set, and the stop names Members itself (#286 review).
E="MOCK_FINE=1"       run fine-grained-unknown err no no "with-admin-token.sh"                 -- nobody/probe
if grep -qF "the type of nobody could not be read" "$work/home-fine-grained-unknown/out" \
   && grep -qF "Organization permissions Members: read" "$work/home-fine-grained-unknown/out" \
   && ! grep -qF "members=read" "$work/home-fine-grained-unknown/out"
then ok fine-grained-unknown "an unreadable owner type keeps the Members line instead of claiming the link is complete"
else bad fine-grained-unknown "an unreadable owner type is treated as a personal account"; grep -F -A3 "pre-filled" "$work/home-fine-grained-unknown/out" | sed 's/^/        /'; fi
if grep -qF "Organization permissions Members" "$work/home-fine-grained/out" "$work/home-fine-grained-org/out"
then bad fine-grained "the Members line appears when the owner's type was read"
else ok fine-grained "no Members line when the owner's type was read"; fi
# gh reads GH_TOKEN and GITHUB_TOKEN before the login it stores, so with one
# of them set a login or refresh changes nothing the door sees: the stop says
# to unset it first (#245 review).
E="MOCK_FINE=1 GH_TOKEN=x" run fine-grained-env err no no "unset GH_TOKEN"            -- probe
# The environment token usually comes from a shell startup file, so unsetting
# it once is not the end of it; after the clean-up the login and the door stay
# in Claude Code, which is the point of fix 1 (#285).
# ~/.zshenv is named too: every zsh reads it, the agent's own shell included, so
# a token left there survives removing it from ~/.zshrc (RC2 in #65).
if grep -qF "startup file" "$work/home-fine-grained-env/out" && grep -qF "no terminal switch" "$work/home-fine-grained-env/out" \
   && grep -qF ".zshenv, which every zsh reads" "$work/home-fine-grained-env/out"
then ok fine-grained-env "the unset step names the startup file and says the rest stays in Claude Code"
else bad fine-grained-env "the unset step does not say where the token comes from or that the rest stays in Claude Code"; grep -F "unset" "$work/home-fine-grained-env/out" | sed 's/^/        /'; fi
E="MOCK_SCOPES=repo GITHUB_TOKEN=x" run scope-missing-env err no no "unset GITHUB_TOKEN" -- probe
if grep -q "unset GH" "$work/home-fine-grained/out" "$work/home-scope-missing/out"
then bad fine-grained "the unset line appears with no token in the environment"
else ok fine-grained "no unset line without an environment token"; fi
# With the environment token unset, gh may hold no login at all, and
# `gh auth refresh` works only on a stored one: the line names the login (#246).
if grep -qF "gh auth login -s repo,workflow,delete_repo" "$work/home-scope-missing-env/out" \
   && ! grep -qF "gh auth login -s" "$work/home-scope-missing/out"
then ok scope-missing-env "names gh auth login for when no login is stored, only with an environment token"
else bad scope-missing-env "the scope stop does not name gh auth login for an environment-token-only user"; fi
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
# A private repository carries a ruleset only on GitHub Pro, Team or Enterprise
# (#320, #350): an owner whose plan reads free stops here, with the reason and
# the public command, whichever side of the name the flag was typed on.
E="MOCK_PLAN=free"    run private        err no no "tester is on GitHub Free"                -- probe --private
E="MOCK_PLAN=free"    run private-first  err no no "tester is on GitHub Free"                -- --private probe --archetype=backend
if grep -qF "needs GitHub Pro" "$work/home-private/out" && grep -qxF "  public instead, with the whole wall: /plinth:new-project probe" "$work/home-private/out" \
   && grep -qxF "  public instead, with the whole wall: /plinth:new-project probe --archetype=backend" "$work/home-private-first/out"
then ok private "the stop gives the reason and the public command, with the other arguments kept"
else bad private "the stop lacks the reason or the public command"; sed 's/^/        /' "$work/home-private/out" "$work/home-private-first/out"; fi
E="MOCK_PLAN=free"    run private-org-free err no no "needs GitHub Team or Enterprise"       -- someorg/probe --private
# A classic token reads its own plan with read:user, which gh's default login
# does not carry: asking for it stops a Free account here, where otherwise the
# repository would be created and deleted. The mock's default scopes are that login.
run private-no-read-user err no no "gh's token lacks the read:user scope" -- probe --private
if grep -qxF "  fix: gh auth refresh -h github.com -s read:user   (a token typed at a prompt: one with read:user beside its other scopes)" "$work/home-private-no-read-user/out" \
   && grep -qxF "  public instead, with the whole wall: /plinth:new-project probe" "$work/home-private-no-read-user/out"
then ok private-no-read-user "the stop names the one scope and the public command"
else bad private-no-read-user "the stop does not name the fix"; sed 's/^/        /' "$work/home-private-no-read-user/out"; fi
E="GH_TOKEN=x" run private-no-read-user-env err no no "unset GH_TOKEN" -- probe --private
E="FAIL_AT=plan" run private-plan-failed-no-scope err no no "gh's token lacks the read:user scope" -- probe --private
# A plan no scope would show (the scope is there and the answer still carries
# none; an organization's, shown to its owners) is not "free" and not "paid":
# the door goes on and the ruleset call decides (below). Without delete_repo
# that judgment would leave a private repository with no wall behind, so that
# one stops here.
E="MOCK_PLAN=none MOCK_SCOPES=repo,workflow,read:user" run private-unread-no-delete err no no "cannot delete what it creates" -- probe --private
E="FAIL_AT=plan MOCK_SCOPES=repo,workflow,user"        run private-plan-error-no-delete err no no "cannot delete what it creates" -- probe --private
E="MOCK_PLAN=none MOCK_SCOPES=repo,workflow,read:org"  run private-org-unread-no-delete err no no "cannot delete what it creates" -- someorg/probe --private
if grep -qF "gh auth refresh -h github.com -s read:user,delete_repo" "$work/home-private-unread-no-delete/out" \
   && grep -qF "gh auth refresh -h github.com -s delete_repo" "$work/home-private-org-unread-no-delete/out"
then ok private-unread-no-delete "the stop names the scopes that read the plan and delete"
else bad private-unread-no-delete "the stop does not name the fix"; sed 's/^/        /' "$work/home-private-unread-no-delete/out"; fi
# A plan that reads as paid needs no delete_repo to go on: rollback off is said, as for a public one.
E="MOCK_PLAN=pro MOCK_SCOPES=repo,workflow" run private-pro-no-delete ok yes no "rollback: off (no delete_repo scope" -- probe --private
run two-names      err no no "one name only"                                                -- probe other
run bad-option     err no no "unknown option: --nope"                                       -- probe --nope
E="MOCK_EXISTS=1"     run repo-exists   err no no "already exists; the door creates new"     -- probe
run license-typo   err no no "unknown license: bogus"                                       -- probe --license=bogus
# copier refuses a license outside its choices only after the repository exists;
# the door reads the template's own list and stops before creating anything.
run license-unsupported err no no "the template does not carry the license GPL-3.0"          -- probe --license=gpl-3.0
run archetype-typo err no no "the template accepts: cli library backend data-ml web"          -- probe --archetype=service
# The template tag must still name the commit this plinth was tested with
# (#519): moved, gone or unreadable, the door stops before creating anything.
E="MOCK_TAG=moved" run tag-moved err no no "names commit $(printf '%040d' 1), not $TEMPLATE_SHA, the one this plinth was tested with" -- probe
E="MOCK_TAG=gone"  run tag-gone  err no no "could not read which commit coolbress/plinth-template@$TEMPLATE_REF names" -- probe
E="MOCK_TAG=error" run tag-unread err no no "could not read which commit coolbress/plinth-template@$TEMPLATE_REF names" -- probe
if grep -qF "contents/copier.yml" "$work/home-tag-gone/calls.log"; then bad tag-gone "the template's copier.yml was read although its tag was not verified"
else ok tag-gone "nothing is read from the template before its tag is verified"; fi
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

echo "warnings: continue, and say so"
E="GH_TOKEN=x"        run env-token     ok yes no "warning: GH_TOKEN is set in the environment" -- probe
E="GH_TOKEN=x PLINTH_TOKEN_SOURCE=prompt" run env-token-admin ok yes no "" -- probe
if grep -q "warning: GH_TOKEN" "$work/home-env-token-admin/out"; then bad env-token-admin "the admin path warned about its own GH_TOKEN"
else ok env-token-admin "the admin path does not warn about its own GH_TOKEN"; fi
# No sandbox advice from the door: /sandbox on Claude Code 2.1.278 does not
# write sandbox.enabled, and on macOS the sandbox stops this script's own copier
# step (#222, #229). floor-check --sandbox carries what was measured.
E="CLAUDE_CONFIG_DIR=$work/nowhere" run no-toggle-key ok yes no "" -- probe
if grep -qi "sandbox" "$work/home-no-toggle-key/out"; then bad no-toggle-key "the door still gives sandbox advice from a key /sandbox does not write"
else ok no-toggle-key "the door says nothing about the sandbox"; fi
E="MOCK_SCOPES=repo,workflow" run rollback-off ok yes no "rollback: off (no delete_repo scope" -- probe
# The template's copier.yml unread: the warning keeps its text and the door
# goes on, and one line under it names the step that failed and its error, or
# that the text carried no choices (#629). Which step: `gh api` (FAIL_AT=choices),
# `base64 -d` (a body it cannot decode), or neither (a copier.yml without them).
unread="warning: could not read the template's archetype and license lists; copier decides (a refusal rolls back)"
run choices-read ok yes no "" -- probe
E="FAIL_AT=choices" run choices-gh-fails ok yes no "$unread" -- probe
grep -qxF "  gh api failed: mock gh: failing at choices on purpose" "$work/home-choices-gh-fails/out" \
  && ok choices-gh-fails "the line names gh api and its error" || bad choices-gh-fails "the line does not name gh api and its error"
E="MOCK_CHOICES=garbage" run choices-base64-fails ok yes no "$unread" -- probe
grep -qE "^  base64 -d failed: base64: .+" "$work/home-choices-base64-fails/out" \
  && ok choices-base64-fails "the line names base64 -d and its error" || bad choices-base64-fails "the line does not name base64 -d and its error"
E="MOCK_CHOICES=nochoices" run choices-none ok yes no "$unread" -- probe
grep -qxF "  the read succeeded, but copier.yml at $TEMPLATE_SHA lists no archetype or license choices where the door looks: its shape changed, not the network" "$work/home-choices-none/out" \
  && ok choices-none "the line says the text carried no choices" || bad choices-none "the line does not say the text carried no choices"
# A read that succeeds prints nothing new: the failed run's output is the
# successful run's plus exactly the warning and its one line (clock times
# and the case's own directory aside).
if grep -q "could not read the template's\|failed: \|the read succeeded" "$work/home-choices-read/out"; then bad choices-read "a successful read printed the warning or its line"
else ok choices-read "a successful read prints neither the warning nor its line"; fi
same() { sed -E "s#$work/home-$1#HOME#g; s/[0-9]{2}:[0-9]{2}:[0-9]{2}Z/HH:MM:SSZ/g" "$work/home-$1/out"; }
added="$(diff <(same choices-read) <(same choices-gh-fails) | grep '^[<>]')"
if [ "$added" = "$(printf '> %s\n> %s' "$unread" "  gh api failed: mock gh: failing at choices on purpose")" ]
then ok choices-read "the failed read adds the warning and one line to the successful read's output, and changes nothing else"
else bad choices-read "the two outputs differ beyond the warning and its line"; sed 's/^/        /' <<<"$added"; fi
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
# A config and no form: the owner is told theirs stops applying. The answer
# comes from the one listing already read; a second read could fail after the
# first succeeded and silence the warning as "no config" (#101).
if grep -q "warning: tester/.github publishes an issue-template config but no form" "$work/home-shared-forms-config/out" \
  && [ "$(grep -c "contents/.github/ISSUE_TEMPLATE --jq" "$work/home-shared-forms-config/calls.log")" = 1 ]
then ok shared-forms-config "the config-only warning is printed, from a single listing"
else bad shared-forms-config "no warning, or the listing was read twice"; grep -E "ISSUE_TEMPLATE|warning" "$work/home-shared-forms-config/calls.log" "$work/home-shared-forms-config/out" | sed 's/^/        /'; fi
if grep -q "does not follow tester/.github's pull-request template" "$work/home-shared-pr-only/calls.log"; then ok shared-pr-only "the first pull request says it does not follow the inherited template"
else bad shared-pr-only "the first pull request is silent about the inherited template"; fi
if grep -q "^gh pr create.*## What and why" "$work/home-shared-pr-only/calls.log"; then bad shared-pr-only "plinth's headings were imposed over the owner's template"
else ok shared-pr-only "plinth's headings are not imposed over the owner's template"; fi
E="MOCK_SHARED_PR=error MOCK_SHARED_FORMS=error" run forced-defaults ok yes no "" -- probe --force-defaults
run org-member     ok yes no "as member"                                                    -- someorg/probe
run apache         ok yes no "(public, Apache-2.0, cli, as owner)"                           -- probe --license=apache-2.0
run backend        ok yes no "(public, MIT, backend, as owner)"                                -- probe --archetype=backend
run web            ok yes no "(public, MIT, web, as owner)"                                    -- probe --archetype=web
# The spdx id is still looked up (`mit` -> `MIT`); the license *text* is not:
# the template renders LICENSE from the choice, so a fetch would write over it.
if grep -q 'license=Apache-2.0' "$work/home-apache/calls.log" && ! grep -q -- '--jq .body' "$work/home-apache/calls.log"
then ok apache "the chosen license reaches copier, and no license text is fetched over the render"
else bad apache "the license did not reach copier, or its text was fetched over the render"; fi

echo "after creation: any failure deletes"
for at in copier push default-branch codeql ruleset ruleset-merge secret dependabot actions allowlist merge pr; do
  E="FAIL_AT=$at" run "$at" err yes yes "" -- probe
done
# A failing setup call names itself (#356), whatever the error.
for at in secret:"secret scanning and push protection" dependabot:"Dependabot alerts" actions:"the Actions permissions" allowlist:"the Actions allowlist" merge:"the merge settings"; do
  if grep -qF "could not set ${at#*:}" "$work/home-${at%%:*}/out"; then ok "${at%%:*}-named" "the failure names ${at#*:}"
  else bad "${at%%:*}-named" "the failure does not name ${at#*:}"; sed 's/^/        /' "$work/home-${at%%:*}/out"; fi
done
echo "after creation: a GitHub server error on a setup call is tried again (#356)"
E="MOCK_5XX=secret:502:1" run 5xx-once      ok  yes no "secret scanning and push protection: GitHub answered HTTP 502; trying again (1 of 4)" -- probe
E="MOCK_5XX=actions:503:2" run 5xx-twice    ok  yes no "the Actions permissions: GitHub answered HTTP 503; trying again (2 of 4)" -- probe
E="MOCK_5XX=allowlist:502:4" run 5xx-four   ok  yes no "the Actions allowlist: GitHub answered HTTP 502; trying again (4 of 4)" -- probe
E="MOCK_5XX=merge:504:1" run 5xx-merge      ok  yes no "trying again (1 of 4)" -- probe
E="MOCK_5XX=dependabot:502:9" run 5xx-stays err yes yes "could not set Dependabot alerts" -- probe
E="MOCK_5XX=allowlist:500:1" run 5xx-500    err yes yes "could not set the Actions allowlist" -- probe
if [ "$(grep -c 'selected-actions' "$work/home-5xx-500/calls.log")" = 1 ]
then ok 5xx-500 "an HTTP 500 is not tried again: one call"
else bad 5xx-500 "an HTTP 500 was tried again"; fi
if [ "$(grep '^sleep ' "$work/home-5xx-four/calls.log" | head -4 | tr '\n' ' ')" = "sleep 5 sleep 10 sleep 20 sleep 40 " ]
then ok 5xx-four "the pauses before the retries are 5, 10, 20 and 40 seconds"
else bad 5xx-four "the pauses were: $(grep '^sleep ' "$work/home-5xx-four/calls.log" | head -4 | tr '\n' ' ')"; fi
if [ "$(grep -c 'vulnerability-alerts' "$work/home-5xx-stays/calls.log")" = 5 ]
then ok 5xx-stays "a 502 that persists is tried five times in all, then stops"
else bad 5xx-stays "a persistent 502 was not tried exactly five times: $(grep -c 'vulnerability-alerts' "$work/home-5xx-stays/calls.log")"; fi
# The ruleset is a POST: sending it again could create a second ruleset, so it
# is not retried, and its failure keeps its own message.
E="MOCK_5XX=ruleset:502:1" run 5xx-ruleset err yes yes "could not apply the ruleset" -- probe
E="MOCK_5XX=ruleset-merge:502:1" run 5xx-ruleset-merge err yes yes "could not apply the merge ruleset" -- probe
# Accepted, then read back without the admin's exemption: the person could not
# merge. Rolled back like a refusal.
E='MOCK_MERGE_READBACK={"name":"main:_merged_by_an_admin","target":"branch","enforcement":"active","conditions":{},"rules":[{"type":"update"}],"bypass_actors":[]}' run merge-readback err yes yes "the merge ruleset (9) reads back as" -- probe
# The push's hint follows what git said (#271): a GitHub server error is not
# the token, and the fix is to run the door again; an authentication or
# permission refusal keeps the token hint; anything else names both, as
# possibilities. Each still rolls back.
# git's words carry spaces, which E= would split, so they go through the
# environment for the one run.
push_fails() { local case="$1" text="$2" err="$3"
  MOCK_PUSH_ERR="$err" E="FAIL_AT=push" run "$case" err yes yes "$text" -- probe; }
export MOCK_PUSH_ERR
push_fails push-5xx   "not the token: GitHub failed on its side" 'remote: Internal Server Error\n ! [remote rejected] main -> main (Internal Server Error)'
push_fails push-502   "not the token: GitHub failed on its side" "fatal: unable to access 'https://github.com/tester/probe.git/': The requested URL returned error: 502"
push_fails push-auth  "the token has the repo scope" 'remote: Invalid username or token.\nfatal: Authentication failed for x'
push_fails push-403   "the token has the repo scope" "remote: Permission to tester/probe.git denied to tester.\nfatal: unable to access 'https://github.com/tester/probe.git/': The requested URL returned error: 403"
push_fails push-503   "not the token: GitHub failed on its side" 'remote: Service Unavailable\nfatal: unable to access x'
push_fails push-401   "the token has the repo scope" 'error: RPC failed; HTTP 401 curl 22 The requested URL returned error: 401'
push_fails push-other "possibly" 'fatal: the remote end hung up unexpectedly'
unset MOCK_PUSH_ERR
for c in push-5xx push-502 push-503; do
  if grep -q "the token has the repo scope" "$work/home-$c/out" || ! grep -q "run the door again" "$work/home-$c/out"
  then bad "$c" "a server error blames the token, or does not say to run the door again"; sed 's/^/        /' "$work/home-$c/out"
  else ok "$c" "names GitHub, not the token, and says to run the door again"; fi
done
# The fallback also prints the token hint, so it is absent "possibly" that
# shows the refusal was recognised rather than fallen through.
for c in push-auth push-403 push-401; do
  if grep -q "run the door again" "$work/home-$c/out" || grep -q "possibly" "$work/home-$c/out" \
     || ! grep -q "^  check: the token has the repo scope" "$work/home-$c/out"
  then bad "$c" "an authentication refusal was not recognised as one"; sed 's/^/        /' "$work/home-$c/out"
  else ok "$c" "keeps the token hint alone"; fi
done
if grep -q "the token has the repo scope" "$work/home-push-other/out" && grep -q "run the door again" "$work/home-push-other/out" \
   && grep -q "the remote end hung up unexpectedly" "$work/home-push-other/out"
then ok push-other "git's words, then both hints as possibilities"
else bad push-other "an unrecognised push error lost git's words or a hint"; sed 's/^/        /' "$work/home-push-other/out"; fi
E="MOCK_RUNS=startup" run startup-failure err yes yes "failed at startup" -- probe
# A pull request opened before CodeQL default setup has finished configuring is
# never analysed (measured three times, #62 and #120; the comment in the door
# has the times). The wall still stands, so no analysis on the first pull
# request warns and names the re-push; it does not delete the repository.
E="MOCK_CODEQL=absent PLINTH_FIRST_PR_WAIT=1" run codeql-absent ok yes no "warning: CodeQL has not picked up the first pull request" -- probe
if grep -q "git commit --allow-empty" "$work/home-codeql-absent/out"; then ok codeql-absent "the summary names the re-push"
else bad codeql-absent "the summary does not name the re-push"; fi
# The door pushes the recovery itself, once, before it asks the user to: an
# empty commit on the pull request branch after a while with no CodeQL on the
# head (owner decision 2026-09-11, #117). CodeQL picking that up ends the wait
# with no warning and no line to type; never picking it up warns, says the
# re-push happened, and names the manual one.
if [ "$(grep -c '^git -C .* push -q$' "$work/home-codeql-absent/calls.log")" = 1 ] && grep -q "one empty commit pushed" "$work/home-codeql-absent/out"
then ok codeql-absent "one empty commit is pushed by the door, and the warning says so"
else bad codeql-absent "no single re-push by the door"; grep -E 'push|warning' "$work/home-codeql-absent/calls.log" "$work/home-codeql-absent/out" | sed 's/^/        /'; fi
E="MOCK_CODEQL=after-repush PLINTH_FIRST_PR_WAIT=1" run codeql-after-repush ok yes no "CodeQL on the pull request head: CodeQL" -- probe
if ! grep -q "warning: CodeQL" "$work/home-codeql-after-repush/out" && ! grep -q "git commit --allow-empty" "$work/home-codeql-after-repush/out" \
   && [ "$(grep -c '^git -C .* push -q$' "$work/home-codeql-after-repush/calls.log")" = 1 ]
then ok codeql-after-repush "CodeQL on the re-pushed head ends the wait: no warning, nothing to type"
else bad codeql-after-repush "the re-push was not enough, or was repeated"; grep -E 'push|warning|allow-empty' "$work/home-codeql-after-repush/calls.log" "$work/home-codeql-after-repush/out" | sed 's/^/        /'; fi
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
# A leading zero is base 10, not octal: 08 once aborted after the create (#539).
E="PLINTH_FIRST_PR_WAIT=08" run wait-leading-zero ok yes no "" -- probe
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
check "main is pushed before the two rulesets, the first ruleset before the merge one, the pull request after them" \
  '[ "$(grep -E "push -q -u origin main|/rulesets|^gh pr create" "$log" | grep -v "/rulesets/[0-9]" | sed -E "s/^git .*push.*/main/; s/.*rulesets.*ruleset-merge.json.*/merge/; s/.*rulesets.*/ruleset/; s/^gh pr create.*/pr/" | tr "\n" " ")" = "main ruleset merge pr " ]'
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
  'grep -qE "^CodeQL default setup: enabled [0-9:]+Z, configured with languages \[actions,python\], first run on main completed 2026-09-10T00:01:00Z, analysis of main listed 2026-09-10T00:02:00Z /language:python, first pull request pushed [0-9:]+Z$" "$work/home-none/out" && [ "$(grep -cE "^  [0-9:]+Z (updated|run|analysis): " "$work/home-none/out")" = 3 ]'
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
check "the first pull request is one README section on docs/first-pr, and nothing else" \
  '[ "$("$REAL_GIT" -C "$proj" rev-parse --abbrev-ref HEAD)" = docs/first-pr ] && [ "$("$REAL_GIT" -C "$proj" diff --name-only main docs/first-pr)" = README.md ]'
# What the door prints at the end reaches the next session through the
# repository, not the terminal that ran the door (#126): the three sentences, in
# order, in the pull request body (the mock logs it verbatim after `gh pr
# create`) and under a First day heading in README.md; the terminal says where.
three_lines() { # <file>: the three sentences' order in <file>, as one word
  grep -oE "^- (If the merge stays blocked on CodeQL, push once more: .git commit --allow-empty -m .ci: trigger code scanning. && git push|If your everyday gh token is fine-grained with selected repositories, add .probe. to it: https://github.com/settings/personal-access-tokens|Dependabot opens pull requests from the first minute: merge one when every required check is green)" "$1" \
    | sed -E 's/^- If the merge.*/recovery/; s/^- If your everyday.*/token/; s/^- Dependabot.*/dependabot/' | tr "\n" " "; }
check "the first pull request body carries the recovery push, the token line and the Dependabot note, in that order" \
  '[ "$(sed -n "/^gh pr create/,/^gh /p" "$log" | three_lines /dev/stdin)" = "recovery token dependabot " ]'
check "README.md says the same three things under First day, before the first session" \
  '[ "$(sed -n "/^## First day$/,\$p" "$proj/README.md" | three_lines /dev/stdin)" = "recovery token dependabot " ] && grep -q "^Made with \[plinth\]" "$proj/README.md"'
# #153: the Dependabot line also says the door's pull request is #2, names the
# refusal a merge meets while the checks rerun after "Update branch", and says
# to wait rather than approve (measured on a real instance, 2026-09-16: a
# person's own branch update needed no approval once the checks had rerun).
dependabot_says() { # <file>: the Dependabot line carries the three #153 phrases and #179's
  grep -E "^- Dependabot opens pull requests" "$1" | grep -F "CodeQL does not analyse a head Dependabot pushed" | grep -F "pull request is #2" | grep -F "prohibits the merge" | grep -qF "wait for the state to read clean rather than adding an approval"; }
check "the Dependabot line says the door's pull request is #2 and an update waits for checks, not an approval, in the body and README alike" \
  'dependabot_says <(sed -n "/^gh pr create/,/^gh /p" "$log") && dependabot_says "$proj/README.md"'
# The owner's template drops our headings, not the three sentences.
check "the first pull request under the owner's template still carries the three sentences, in order" \
  '[ "$(sed -n "/^gh pr create/,/^gh /p" "$work/home-shared-pr-only/calls.log" | three_lines /dev/stdin)" = "recovery token dependabot " ]'
check "the terminal points at where the same text now lives" \
  'grep -q "are in the pull request.s body and in README.md under \"First day\"" "$work/home-none/out"'
check "CodeQL on the first push means no empty commit is pushed" '! grep -q "push -q$" "$log" && [ "$("$REAL_GIT" -C "$proj" rev-list --count main..docs/first-pr)" = 1 ]'
check "render is final: real name, owner and license in pyproject.toml and uv.lock, src/probe/, no bootstrap.sh" \
  'grep -q probe "$proj/pyproject.toml" && grep -q MIT "$proj/pyproject.toml" && grep -q tester "$proj/pyproject.toml" && grep -q probe "$proj/uv.lock" && [ -d "$proj/src/probe" ] && [ ! -e "$proj/bootstrap.sh" ]'
# The wall per archetype (#127): a service archetype's ruleset requires the
# `image` check its ci.yml carries, from the Actions app; a cli one is
# ruleset.json as committed. Read from what the mock saw on stdin.
check "a cli ruleset is ruleset.json, unchanged" \
  'cmp -s <(jq -S . "$work/home-none/ruleset-posted.json") <(jq -S . "$root/ruleset.json")'
# The merge ruleset is the same file for every archetype and visibility.
check "the merge ruleset is read back after its write, by the id the write returned" \
  '[ "$(grep -nE "/rulesets.*ruleset-merge.json|api repos/tester/probe/rulesets/9" "$work/home-none/calls.log" | sed -E "s/:.*ruleset-merge.json.*/:write/; s/:.*rulesets\/9.*/:read/" | cut -d: -f2 | tr "\n" " ")" = "write read " ]'
check "the merge ruleset posted is ruleset-merge.json, unchanged (cli)" \
  'cmp -s "$work/home-none/ruleset-merge-posted.json" "$root/ruleset-merge.json"'
check "the merge ruleset posted is ruleset-merge.json, unchanged (backend)" \
  'cmp -s "$work/home-backend/ruleset-merge-posted.json" "$root/ruleset-merge.json"'
check "a backend ruleset is the wall plus image, from the same app (check-ruleset.sh passes with image)" \
  '"$root/scripts/check-ruleset.sh" "$work/home-backend/ruleset-posted.json" image >/dev/null'
check "a web ruleset is the wall plus image, ci / migrations and ci / deploy-check, from the same app (#615)" \
  '[ "$(jq -c "[.rules[] | select(.type == \"required_status_checks\") | .parameters.required_status_checks[] | select(.context == \"image\" or .context == \"ci / migrations\" or .context == \"ci / deploy-check\") | .integration_id] | unique" "$work/home-web/ruleset-posted.json")" = "[15368]" ] && [ "$(jq "[.rules[] | select(.type == \"required_status_checks\") | .parameters.required_status_checks[] | select(.context == \"image\" or .context == \"ci / migrations\" or .context == \"ci / deploy-check\")] | length" "$work/home-web/ruleset-posted.json")" = 3 ]'
check "a web render passes archetype=web to copier" 'grep -q "archetype=web" "$work/home-web/calls.log"'
check "the summary line names owner, visibility, license, archetype, role and the template tag" \
  'grep -q "^create tester/probe (public, MIT, cli, as owner) from coolbress/plinth-template@v1.22.0 in " "$work/home-none/out"'
check "the tag's commit is checked, and the template's copier.yml read at that commit, not at the tag (#519)" \
  'grep -q "^git ls-remote https://github.com/coolbress/plinth-template refs/tags/$TEMPLATE_REF " "$log" && grep -qF "contents/copier.yml?ref=$TEMPLATE_SHA" "$log"'
check "copier renders the tag's pinned commit, not the tag: a tag moved after the check changes nothing (#519)" \
  'grep -qE "^uvx .*--vcs-ref $TEMPLATE_SHA gh:coolbress/plinth-template " "$log"'

# The end says whether the credential the agent inherits can change the wall
# (#300), read once setup is done. `permissions.admin` is the account's role,
# not the token's reach: a classic token's `repo` scope carries the role, and a
# fine-grained token is asked a read that needs Administration. Whatever cannot
# be read is not verified, never "no administration".
guide='https://github.com/coolbress/plinth/blob/main/docs/how-to/give-the-agent-a-token.md'
check "the guide is the token page in docs/how-to/" \
  'grep -qxE "# How to give the agent a token that cannot change the checks" "$root/docs/how-to/give-the-agent-a-token.md"'
check "an admin credential is said to have administration, with the guide's section to switch" \
  'grep -q "^  administration: the gh credential this ran with has it on tester/probe" "$work/home-none/out" && grep -qF "$guide" "$work/home-none/out"'
check "the administration line comes after setup, not before the wall" \
  '[ "$(grep -n "admin-read" "$log" | cut -d: -f1)" -gt "$(grep -n "^gh pr create" "$log" | cut -d: -f1)" ]'
E="MOCK_ADMIN=false MOCK_ROLE=write" run admin-false ok yes no "administration: the gh credential this ran with has none on tester/probe" -- probe
if grep -qF "$guide" "$work/home-admin-false/out"; then bad admin-false "a credential without administration is still sent to the guide"
else ok admin-false "no pointer to the guide when there is nothing to switch"; fi
for answer in error null ''; do
  E="MOCK_ADMIN=$answer" run "admin-unread-${answer:-empty}" ok yes no "administration: not verified" -- probe
  out="$work/home-admin-unread-${answer:-empty}/out"
  if grep -qF "$guide" "$out" && ! grep -qE "has (it|none) on" "$out"
  then ok "admin-unread-${answer:-empty}" "an unreadable answer is not verified, never no administration, and names the guide"
  else bad "admin-unread-${answer:-empty}" "an unreadable answer was read as one"; grep -F "administration" "$out" | sed 's/^/        /'; fi
done
# Through with-admin-token.sh the typed token ran setup and is gone; the agent
# inherits gh's own login, so that is the one asked, without the typed token.
if grep -qx "admin-read GH_TOKEN=" "$work/home-env-token-admin/calls.log" \
   && grep -q "^  administration: gh's own login (not the token typed for this run) has it on tester/probe" "$work/home-env-token-admin/out"
then ok env-token-admin "the admin-token path asks about gh's own login, not the typed token"
else bad env-token-admin "the admin-token path reported the typed token"; grep -E "admin-read|administration" "$work/home-env-token-admin/calls.log" "$work/home-env-token-admin/out" | sed 's/^/        /'; fi
if grep -qx "admin-read GH_TOKEN=set" "$work/home-env-token/calls.log"
then ok env-token "outside the admin-token path the credential it ran with is the one asked"
else bad env-token "the environment token was dropped from the administration read"; fi
# A fine-grained stored login under an admin role: the role says nothing about
# the token, so only the Administration read decides, and a 200 there still
# leaves write unknown.
E="MOCK_FINE=1 PLINTH_TOKEN_SOURCE=prompt MOCK_ADMIN_PROBE=denied" run fine-no-admin ok yes no \
  "administration: gh's own login (not the token typed for this run) has none on tester/probe" -- probe
if grep -qx "admin-probe GH_TOKEN=" "$work/home-fine-no-admin/calls.log"
then ok fine-no-admin "the Administration read is asked of gh's own login too"
else bad fine-no-admin "the Administration read used the typed token"; fi
if grep -q "administration: not verified" "$work/home-fine-admin/out" && ! grep -qE "administration: .* has (it|none) on" "$work/home-fine-admin/out"
then ok fine-admin "a fine-grained token that reads Administration is not verified: write cannot be read"
else bad fine-admin "a fine-grained token's Administration read was taken as an answer"; grep -F "administration" "$work/home-fine-admin/out" | sed 's/^/        /'; fi
E="MOCK_FINE=1 PLINTH_TOKEN_SOURCE=prompt MOCK_ADMIN_PROBE=error" run fine-probe-error ok yes no "administration: not verified" -- probe
if grep -qE "administration: .* has (it|none) on" "$work/home-fine-probe-error/out"
then bad fine-probe-error "a failed Administration read was taken as an answer"
else ok fine-probe-error "a failed Administration read, not a 403 refusal, is not verified"; fi
if grep -q "admin-probe" "$work/home-none/calls.log"
then bad none "a classic token was asked the Administration read its scopes already answer"
else ok none "a classic token's reach is its scopes; no Administration read"; fi
# A role that is not admin: the standard ones cannot edit a ruleset; a custom
# organization role might ("Edit repository rules"), so it is not verified.
# In an organization a standard repository role is not the whole answer: an
# organization role can grant "Edit repository rules" on its own (Codex on #343).
E="MOCK_ADMIN=false MOCK_ROLE=write" run admin-org-write ok yes no "administration: not verified" -- someorg/probe
if grep -qE "administration: .* has (it|none) on" "$work/home-admin-org-write/out"
then bad admin-org-write "an organization's write role was read as no administration"
else ok admin-org-write "a standard role below admin in an organization is not verified"; fi
E="MOCK_ADMIN=false MOCK_ROLE=custom-rules" run admin-custom-role ok yes no "administration: not verified" -- probe
if grep -qE "administration: .* has (it|none) on" "$work/home-admin-custom-role/out"
then bad admin-custom-role "a custom role was read as no administration"
else ok admin-custom-role "a custom role without admin is not verified"; fi


echo "private: the wall the plan and the licences allow, each gap named (#350)"
# has <case> <description> <file: out|log|readme> <grep -E pattern>; hasnt is the
# reverse, and a file that is not there is a failure, not an absence.
file_of() { case "$2" in out) echo "$work/home-$1/out" ;; log) echo "$work/home-$1/calls.log" ;; readme) echo "$work/home-$1/probe/README.md" ;; esac; }
has()   { if grep -qE -- "$4" "$(file_of "$1" "$3")"; then ok "$1" "$2"; else bad "$1" "$2"; grep -nE 'private|not raised|not verified|done:' "$work/home-$1/out" | sed 's/^/        /'; fi; }
hasnt() { local f; f="$(file_of "$1" "$3")"
  if [ ! -s "$f" ]; then bad "$1" "$2 (no $3 to read)"
  elif grep -qE -- "$4" "$f"; then bad "$1" "$2"; grep -nE -- "$4" "$f" | head -3 | sed 's/^/        /'; else ok "$1" "$2"; fi; }
# The two reads a private run makes, as the mock logs them; the public case
# below must show neither, and these patterns are shown to match here first.
plan_read='^gh api (user|orgs/[^ ]+) --jq \.plan'
security_read='^gh api repos/[^ ]+ --jq \.security_and_analysis //'
noscan_posted() { # <case>: what was posted is the wall minus the code_scanning rule, and passes as that variant
  "$root/scripts/check-ruleset.sh" --without-code-scanning "$work/home-$1/ruleset-posted.json" >/dev/null &&
    cmp -s <(jq -S . "$work/home-$1/ruleset-posted.json") <(jq -S 'del(.rules[] | select(.type == "code_scanning"))' "$root/ruleset.json"); }
full_posted() { cmp -s <(jq -S . "$work/home-$1/ruleset-posted.json") <(jq -S . "$root/ruleset.json"); }

# GitHub Pro: rulesets stand on a private repository, Code Security and Secret
# Protection cannot be bought. The ruleset goes up without code_scanning,
# CodeQL is not set up or waited for, push protection is left off, and the
# summary names both gaps and what stands in each one's place.
c=private-pro
E="MOCK_PLAN=pro" run $c ok yes no "done: https://github.com/tester/probe (private, MIT, cli, " -- probe --private
has   $c "the repository is created private"                 log '^gh repo create tester/probe --private$'
has   $c "the line before creating says private and the plan" out '^create tester/probe \(private, MIT, cli, as owner\) .*plan: pro'
has   $c "the plan is read"                                  log "$plan_read"
has   $c "the new repository's security settings are read"   log "$security_read"
if noscan_posted $c; then ok $c "the ruleset posted is the public wall minus the code_scanning rule: every check name stays"
else bad $c "the ruleset posted is not the wall minus code_scanning"; fi
hasnt $c "CodeQL default setup is not enabled, read or waited for" log 'code-scanning|/languages|check-runs|^sleep 60'
hasnt $c "nothing about CodeQL is promised or warned"        out 'warning: CodeQL|CodeQL default setup:'
hasnt $c "secret scanning and push protection are not turned on" log 'security_and_analysis\[secret_scanning'
has   $c "Dependabot, the Actions allowlist and the merge settings are set as for a public repository" log 'allow_merge_commit=false'
has   $c "the summary names the code scanning gap, its reason and what stands in its place" out "^  not raised: code scanning\. GitHub Code Security is not enabled on tester/probe.*ci / lint's security rules"
has   $c "the summary names the dependency review gap, what ci / deps does and what stands in its place (#395)" out "^  not raised: dependency review\\..*ci / deps reports.*not checked.*Dependabot alerts"
has   $c "README's First day names the dependency review gap" readme '^- Not raised: dependency review\.'
has   $c "the summary names the push protection gap, its reason and what stands in its place" out '^  not raised: push protection\. GitHub Secret Protection is not enabled on tester/probe.*ci / secrets.*after the push.*revoked'
# Disabled is off, not unobtainable: both lines say where a person can turn
# the product on and that it may be billed; the door itself turns nothing on.
turn_on="On Team or Enterprise it can be turned on in the repository's Settings → Advanced Security, and may be billed\\."
has   $c "the code scanning gap says where it can be turned on, and that it may be billed" out "^  not raised: code scanning\\..*$turn_on"
has   $c "the push protection gap says the same"             out "^  not raised: push protection\\..*$turn_on"
has   $c "README's gaps carry the same guidance"             readme "^- Not raised: code scanning\\..*$turn_on"
hasnt $c "the menu is GitHub.com's name, not GitHub Enterprise Server's" out 'Settings → Code security'
if [ "$(grep -c "Actions minutes" "$work/home-$c/out")" = 1 ]; then ok $c "the summary says once that CI runs on the plan's Actions minutes"
else bad $c "the Actions minutes line is missing or repeated: $(grep -c "Actions minutes" "$work/home-$c/out")"; fi
hasnt $c "nothing is called not verified when everything was read" out 'not verified: (code scanning|push protection)|plan: not verified'
# The next session reads the repository, not the terminal (#126): the gaps are
# under First day too, and the CodeQL lines that do not apply are not.
has   $c "README's First day names both gaps"                readme '^- Not raised: code scanning\.'
has   $c "README's First day names push protection"          readme '^- Not raised: push protection\.'
hasnt $c "README does not tell a repository without CodeQL to push again for it" readme 'push once more|waits for CodeQL|CodeQL does not analyse'
has   $c "README keeps the token line and the Dependabot note" readme '^- Dependabot opens pull requests from the first minute: merge one when every required check is green, or close it\. After "Update branch"'
hasnt $c "the terminal does not point at a recovery push that is not there" out 'the recovery push'
has   $c "the first pull request body carries the gaps"      log '^- Not raised: code scanning\.'

# An organization with both products enabled on the new repository: the wall
# of a public repository, and the private line alone.
c=private-licensed
E="MOCK_PLAN=team MOCK_SECURITY=enabled,enabled" run $c ok yes no "done: https://github.com/someorg/probe (private, MIT, cli, " -- someorg/probe --private
if full_posted $c; then ok $c "the ruleset posted is ruleset.json, code_scanning included"
else bad $c "the ruleset posted is not ruleset.json"; fi
has   $c "push protection is turned on"                      log 'security_and_analysis\[secret_scanning_push_protection\]\[status\]=enabled'
has   $c "CodeQL default setup is enabled with the languages" log 'default-setup -f state=configured -f query_suite=default -f languages\[\]=actions -f languages\[\]=python'
has   $c "CodeQL is waited for, as on a public repository"   out '^CodeQL default setup: enabled'
hasnt $c "with Code Security, no dependency review gap is named (#395)" out 'dependency review'
hasnt $c "no gap is named, and nothing is offered to turn on" out 'not raised|not verified: (code scanning|push protection)|can be turned on'
has   $c "the Actions minutes line is still said"            out "^  private: CI runs on the plan's Actions minutes\$"
has   $c "README says the repository is private and where CI's minutes come from" readme "^- This repository is private: CI runs on the plan's Actions minutes\.\$"
has   $c "README keeps the CodeQL recovery line"             readme 'If the merge stays blocked on CodeQL, push once more'
hasnt $c "README names no gap"                               readme 'Not raised|Not verified'
has   $c "the plan asked about is the organization's"        log '^gh api orgs/someorg --jq \.plan'

# A block that is readable and carries no Code Security key (what a public
# repository answers; a private one on Pro is not measured yet, #352): no
# status is not verified for code scanning, while push protection, which did
# answer, is named as not raised. The rule is left out either way.
c=private-no-scan-key
E="MOCK_PLAN=pro MOCK_SECURITY=unread,disabled" run $c ok yes no "not verified: code scanning. GitHub gave no status for GitHub Code Security on tester/probe" -- probe --private
if noscan_posted $c; then ok $c "no Code Security key: the code_scanning rule is left out"; else bad $c "no Code Security key: the rule was assumed"; fi
has   $c "push protection, which answered, is not raised"    out '^  not raised: push protection\.'
hasnt $c "nothing is turned on"                              log 'security_and_analysis\[secret_scanning|code-scanning'

# One product and not the other: each is decided on its own.
c=private-scan-only
E="MOCK_PLAN=team MOCK_SECURITY=enabled,disabled" run $c ok yes no "not raised: push protection" -- someorg/probe --private
if full_posted $c; then ok $c "Code Security alone: the code_scanning rule is in"; else bad $c "Code Security alone lost the rule"; fi
hasnt $c "Code Security alone: push protection is not turned on" log 'security_and_analysis\[secret_scanning'
hasnt $c "Code Security alone: no code scanning gap"         out '(not raised|not verified): code scanning'
if [ "$(grep -c 'can be turned on' "$work/home-$c/out")" = 1 ]; then ok $c "the guidance is on the one disabled product's line only"
else bad $c "the turn-on guidance is not on exactly one line: $(grep -c 'can be turned on' "$work/home-$c/out")"; fi
c=private-push-only
E="MOCK_PLAN=team MOCK_SECURITY=disabled,enabled" run $c ok yes no "not raised: code scanning" -- someorg/probe --private
if noscan_posted $c; then ok $c "Secret Protection alone: no code_scanning rule"; else bad $c "Secret Protection alone kept the rule"; fi
has   $c "Secret Protection alone: push protection is turned on" log 'security_and_analysis\[secret_scanning_push_protection\]\[status\]=enabled'
hasnt $c "Secret Protection alone: no push protection gap"   out '(not raised|not verified): push protection'

# What the door cannot read is not verified, and the rule is left out: never
# assumed present, and never reported as a product that is missing.
for how in failed:FAIL_AT=security-read no-key:MOCK_SECURITY=unread,unread empty:MOCK_SECURITY= other:MOCK_SECURITY=maybe,maybe; do
  c="private-unread-${how%%:*}"; how="${how#*:}"
  E="MOCK_PLAN=pro $how" run "$c" ok yes no "not verified: code scanning" -- probe --private
  if noscan_posted "$c"; then ok "$c" "unread security settings ($how): the code_scanning rule is left out"
  else bad "$c" "unread security settings ($how): the rule was assumed"; fi
  has   "$c" "push protection is not verified"               out '^  not verified: push protection\.'
  hasnt "$c" "an unread setting is not reported as a missing product" out 'not raised'
  hasnt "$c" "nothing is turned on from an unread setting"   log 'security_and_analysis\[secret_scanning|code-scanning'
  has   "$c" "README says not verified too"                  readme '^- Not verified: code scanning\.'
  has   "$c" "dependency review is named not verified too (#395)" out '^  not verified: dependency review\..*ci / deps reports'
  hasnt "$c" "a setting with no status is not said to be something to turn on" out 'can be turned on'
done
# A plan the token does not read: said before anything exists, and the door
# goes on with the ruleset call as the judge.
for how in unread:MOCK_PLAN=none failed:FAIL_AT=plan; do
  c="private-plan-${how%%:*}"; how="${how#*:} MOCK_SCOPES=repo,workflow,delete_repo,read:user"
  E="$how" run "$c" ok yes no "plan: not verified" -- probe --private
  if [ "$(grep -n 'plan: not verified' "$work/home-$c/out" | head -1 | cut -d: -f1)" -lt "$(grep -n '^create tester/probe' "$work/home-$c/out" | cut -d: -f1)" ] \
     && grep -q '^create tester/probe (private, .*plan: not verified' "$work/home-$c/out"
  then ok "$c" "the unread plan is said before the repository is created ($how)"
  else bad "$c" "the unread plan is not said before creating ($how)"; fi
done
# The ruleset refused with the plan unread: the likely reason is named, and the
# private repository is deleted like any other the door could not finish.
# An organization member and the fine-grained admin path have no scope to add: both go on.
E="MOCK_PLAN=none" run private-plan-org-unread ok yes no "plan: not verified for someorg (an organization's plan is shown to its owners" -- someorg/probe --private
E="MOCK_PLAN=none MOCK_FINE=1 PLINTH_TOKEN_SOURCE=prompt" run private-plan-fine-unread ok yes no "plan: not verified for tester" -- probe --private
E="MOCK_PLAN=none MOCK_SCOPES=repo,workflow,delete_repo,read:user FAIL_AT=ruleset" run private-ruleset-refused err yes yes "the plan of tester was not verified" -- probe --private
has   private-ruleset-refused "the refusal names what a private ruleset needs and the public command" out 'needs GitHub Pro.*/plinth:new-project probe$'
E="MOCK_PLAN=pro FAIL_AT=ruleset" run private-ruleset-fails err yes yes "could not apply the ruleset" -- probe --private
hasnt private-ruleset-fails "a verified plan is not blamed for a ruleset failure" out 'was not verified'
for at in copier push dependabot actions allowlist merge pr; do
  E="MOCK_PLAN=pro FAIL_AT=$at" run "private-fails-$at" err yes yes "" -- probe --private
done
E="MOCK_PLAN=team MOCK_SECURITY=enabled,enabled FAIL_AT=secret" run private-fails-secret err yes yes "could not set secret scanning and push protection" -- someorg/probe --private
E="MOCK_PLAN=team MOCK_SECURITY=enabled,enabled FAIL_AT=codeql" run private-fails-codeql err yes yes "" -- someorg/probe --private
E="MOCK_PLAN=pro FAIL_AT=ruleset MOCK_DELETE_FAILS=1" run private-delete-fails err yes yes "ROLLBACK FAILED: https://github.com/tester/probe EXISTS WITHOUT A WALL" -- probe --private
E="MOCK_PLAN=pro MOCK_RUNS=none PLINTH_FIRST_PR_WAIT=1" run private-run-never err yes yes "its checks would never report" -- probe --private

# The baseline's CI run started before the wall and failed its floor-check
# (#401): once the wall, the labels and the other settings stand, its failed
# jobs are run again. Nothing about that re-run fails the door.
check "the baseline's CI run is looked up by main's first commit" \
  'grep -q "head_sha=$("$REAL_GIT" -C "$proj" rev-parse main)" "$log"'
check "its failed jobs are re-run once, after the ruleset, the labels and the merge settings" \
  '[ "$(grep -c "/rerun-failed-jobs" "$log")" = 1 ] && r="$(grep -n "/rerun-failed-jobs" "$log" | cut -d: -f1)" && for at in "/rulesets" "^gh label create" "allow_merge_commit"; do [ "$r" -gt "$(grep -nE "$at" "$log" | tail -1 | cut -d: -f1)" ] || exit 1; done'
check "the re-run is asked for the run the lookup found" 'grep -q "repos/tester/probe/actions/runs/77/rerun-failed-jobs" "$log"'
check "the summary says the re-run passed and names the run" \
  'grep -qxF "  first commit on main: its CI run failed before the wall was up; its failed jobs were re-run and passed: https://github.com/tester/probe/actions/runs/77" "$work/home-none/out"'
# A run that passed is not re-run, and the summary still says how it ended (#428).
for c in success skipped neutral; do
  E="MOCK_BASELINE=$c" run "baseline-$c" ok yes no \
    "first commit on main: its CI run ended $c, so nothing was re-run: https://github.com/tester/probe/actions/runs/77" -- probe
  hasnt "baseline-$c" "a baseline run that ended $c is not re-run" log 'rerun-failed-jobs'
done
E="MOCK_RERUN=refused" run rerun-refused ok yes no \
  "first commit on main: its CI run failed before the wall was up, and its failed jobs could not be re-run (gh: Must have admin rights to Repository. (HTTP 403)); re-run them: gh run rerun 77 --failed --repo tester/probe   https://github.com/tester/probe/actions/runs/77" -- probe
E="MOCK_RERUN=red PLINTH_FIRST_PR_WAIT=1" run rerun-red ok yes no \
  "first commit on main: its CI run failed before the wall was up, and the re-run of its failed jobs ended failure: https://github.com/tester/probe/actions/runs/77" -- probe
E="MOCK_RERUN=running PLINTH_FIRST_PR_WAIT=1" run rerun-running ok yes no \
  "first commit on main: its CI run failed before the wall was up; the re-run of its failed jobs was still in_progress after 1 s: https://github.com/tester/probe/actions/runs/77" -- probe
E="MOCK_BASELINE=missing PLINTH_FIRST_PR_WAIT=1" run baseline-missing ok yes no \
  "first commit on main: its CI run (.github/workflows/ci.yml) was not found within 1 s, so nothing was re-run; if it shows a red check, re-run its failed jobs: gh run list --repo tester/probe --branch main" -- probe
# A read that fails is not a run that is missing: gh's own words are kept.
E="MOCK_BASELINE=error PLINTH_FIRST_PR_WAIT=1" run baseline-error ok yes no \
  "first commit on main: its CI run could not be read (gh: HTTP 502), so nothing was re-run; if it shows a red check, re-run its failed jobs: gh run list --repo tester/probe --branch main" -- probe
# Only a failed check is the floor-check before the wall; another end is named.
E="MOCK_BASELINE=action_required" run baseline-other ok yes no \
  "first commit on main: its CI run ended action_required, not a failed check, so nothing was re-run: https://github.com/tester/probe/actions/runs/77" -- probe
# Asked for, but the listing never moves past the first attempt.
E="MOCK_RERUN=unlisted PLINTH_FIRST_PR_WAIT=1" run rerun-unlisted ok yes no \
  "first commit on main: its CI run failed before the wall was up; the re-run of its failed jobs was asked for and not listed within 1 s: https://github.com/tester/probe/actions/runs/77" -- probe
for b in missing error other; do hasnt "baseline-$b" "nothing is re-run" log 'rerun-failed-jobs'; done
has none "the wait and the re-run are each said as they start" out "^  [0-9:]+Z main's first CI run: waiting.*\$" 
has none "the re-run is said with the run as it starts" out "^  [0-9:]+Z main's first CI run failed before the wall was up; re-running its failed jobs \(up to 300 s\): https://github.com/tester/probe/actions/runs/77$"
E="MOCK_BASELINE=running PLINTH_FIRST_PR_WAIT=1" run baseline-running ok yes no \
  "first commit on main: its CI run was still in_progress after 1 s, so nothing was re-run; if it ends red, re-run its failed jobs: gh run rerun 77 --failed --repo tester/probe   https://github.com/tester/probe/actions/runs/77" -- probe
hasnt baseline-running "a baseline run still going is not re-run" log 'rerun-failed-jobs'

# With no CodeQL to wait for, a first pull request whose run started ends the wait
# at once: no empty commit, no CodeQL warning, even with the wait spent.
E="MOCK_PLAN=pro MOCK_CODEQL=absent PLINTH_FIRST_PR_WAIT=0" run private-no-codeql-wait ok yes no "" -- probe --private
hasnt private-no-codeql-wait "no CodeQL warning and no re-push on a repository without it" out 'CodeQL has not picked up|allow-empty'
hasnt private-no-codeql-wait "no empty commit is pushed"     log 'push -q$'

# A public repository is as it was: created public, never asked for a plan or
# its security settings, and nothing private in what it prints or writes.
has   none "a public repository is created public"           log '^gh repo create tester/probe --public$'
hasnt none "a public repository's plan is not read"           log "$plan_read"
hasnt none "a public repository's security settings are not read" log "$security_read"
has   none "a public README is there to be read"             readme '^## First day$'
hasnt none "a public summary says nothing about private"     out 'private|Actions minutes|not raised'
hasnt none "a public README says nothing about private"      readme 'Not raised|Not verified|private'

# The two reads' jq, run on what GitHub answers (the mock above only prints
# what they would leave). Read out of the door, so the test cannot drift.
sec_jq="$(sed -nE "s/^sec_jq='(.*)'$/\1/p" "$root/scripts/new-project.sh")"
sec() { jq -r "$sec_jq" <<<"$1" 2>&1; }
is() { if [ "$2" = "$3" ]; then ok sec-jq "$1"; else bad sec-jq "$1: want '$2', got '$3'"; fi; }
is "the door carries its security jq on one line" yes "$([ -n "$sec_jq" ] && echo yes)"
is "both products enabled"            "enabled enabled"   "$(sec '{"security_and_analysis":{"code_security":{"status":"enabled"},"secret_scanning":{"status":"enabled"}}}')"
is "both products disabled"           "disabled disabled" "$(sec '{"security_and_analysis":{"code_security":{"status":"disabled"},"secret_scanning":{"status":"disabled"}}}')"
is "the earlier Advanced Security licence counts as Code Security" "enabled disabled" "$(sec '{"security_and_analysis":{"advanced_security":{"status":"enabled"},"code_security":{"status":"disabled"},"secret_scanning":{"status":"disabled"}}}')"
is "Advanced Security disabled and no code_security key is disabled" "disabled enabled" "$(sec '{"security_and_analysis":{"advanced_security":{"status":"disabled"},"secret_scanning":{"status":"enabled"}}}')"
is "no code security key at all is unread, not disabled" "unread disabled" "$(sec '{"security_and_analysis":{"secret_scanning":{"status":"disabled"},"dependabot_security_updates":{"status":"enabled"}}}')"
is "security_and_analysis null is unread"   "unread unread" "$(sec '{"security_and_analysis":null}')"
is "security_and_analysis absent is unread" "unread unread" "$(sec '{"name":"probe"}')"
is "push protection on is not Secret Protection on" "unread unread" "$(sec '{"security_and_analysis":{"secret_scanning_push_protection":{"status":"enabled"}}}')"

# ── the GitLab door (#353 slice 2, #531, #532) ───────────────────────────
# `--host gitlab` checks, renders, prints the plan, creates the project and
# pushes main; a failure after the create rolls it back (permanently).
# `glab` and `curl` (the template's copier.yml, read from GitHub's raw files)
# are mocks; the git, uvx and claude mocks above are shared.
mkdir -p "$work/glbin"
cat > "$work/glbin/glab" <<'MOCK'
#!/usr/bin/env bash
set -u
printf 'glab %s\n' "$*" >> "$GH_LOG"
all="$*"
case "$all" in
  --version)               case "${MOCK_GLAB_VERSION_FORMAT:-new}" in
                             old)  echo "glab version ${MOCK_GLAB_VERSION:-1.122.0} (2023-01-01)" ;;
                             none) echo "glab (development build)" ;;
                             *)    echo "glab ${MOCK_GLAB_VERSION:-1.122.0} (mock)" ;;
                           esac ;;
  "auth status"*)          [ "${MOCK_GLAB_NOAUTH:-0}" = 1 ] && { echo "x gitlab.com: not logged in" >&2; exit 1; }; echo "gitlab.com: logged in" ;;
  "api --hostname gitlab.com user")              echo '{"id": 7, "username": "tester"}' ;;
  "api --hostname gitlab.com personal_access_tokens/self")
                           case "${MOCK_GL_TOKEN:-api}" in
                             # As GitLab.com answers (measured on #531): a browser login's OAuth
                             # token, and a personal access token without the scope to read itself.
                             oauth) echo '{"message":"400 Bad request - This endpoint requires token type to be a personal access token"}'; exit 1 ;;
                             noscope) echo '{"error":"insufficient_scope","error_description":"The request requires higher privileges than provided by the access token.","scope":"api read_api"}'; exit 1 ;;
                             *)     echo "{\"scopes\": [\"${MOCK_GL_TOKEN:-api}\"]}" ;;
                           esac ;;
  "api --hostname gitlab.com groups/someorg")    [ "${MOCK_GL_GROUP:-1}" = 1 ] || { echo '{"message":"404 Group Not Found"}'; exit 1; }
                           if [ "${MOCK_GL_GROUP_VIS:-public}" = none ]; then
                             echo "{\"id\": 9, \"full_path\": \"someorg\", \"project_creation_level\": \"${MOCK_GL_CREATION:-maintainer}\"}"
                           else
                             echo "{\"id\": 9, \"full_path\": \"someorg\", \"visibility\": \"${MOCK_GL_GROUP_VIS:-public}\", \"project_creation_level\": \"${MOCK_GL_CREATION:-maintainer}\"}"
                           fi ;;
  "api --hostname gitlab.com groups/someorg%2Fprobe")
                           [ "${MOCK_GL_SUBGROUP:-0}" = 1 ] && { echo '{"id": 10, "full_path": "someorg/probe"}'; exit 0; }
                           echo '{"message":"404 Group Not Found"}'; exit 1 ;;
  "api --hostname gitlab.com namespaces/tester") echo '{"id": 70, "kind": "user", "full_path": "tester"}' ;;
  "api --hostname gitlab.com groups/9/members/all/7")
                           [ "${MOCK_GL_LEVEL:-50}" = none ] && { echo '{"message":"404 Not found"}'; exit 1; }
                           echo "{\"access_level\": ${MOCK_GL_LEVEL:-50}}" ;;
  # Every API read names gitlab.com (`--hostname`); only the encoded path is a
  # project read. Anything else falls through and fails.
  "api --hostname gitlab.com projects/tester%2Fprobe"|"api --hostname gitlab.com projects/someorg%2Fprobe")
                           case "${MOCK_GL_EXISTS:-0}" in
                             1)   echo '{"id": 1, "path_with_namespace": "x/y"}' ;;
                             500) echo '{"message":"500 Internal Server Error"}'; echo "glab: 500 Internal Server Error" >&2; exit 1 ;;
                             *)   echo '{"message":"404 Project Not Found"}'; echo "glab: 404 Project Not Found (HTTP 404)" >&2; exit 1 ;;
                           esac ;;
  # A failure that is not a 404, whose words carry the request path, and the
  # path holds "404": only the answer's status may count as not found.
  "api --hostname gitlab.com projects/tester%2Ffoo404")
                           echo '{"message":"500 Internal Server Error"}'
                           echo "glab: GET https://gitlab.com/api/v4/projects/tester%2Ffoo404: 500 Internal Server Error" >&2; exit 1 ;;
  # The create: answers the new project, or fails (MOCK_GL_CREATE=fail).
  "api --hostname gitlab.com -X POST projects "*)
                           [ "${MOCK_GL_CREATE:-ok}" = fail ] && { echo '{"message":{"name":["has already been taken"]}}'; echo "glab: 400 Bad Request" >&2; exit 1; }
                           [ "${MOCK_GL_CREATE:-ok}" = noid ] && { echo '{}'; exit 0; }
                           # glab's update notice goes to stderr on a successful call.
                           echo "[glab] Update available: v1.122.0 -> v1.123.0" >&2
                           ns="tester"; case "$all" in *namespace_id=9*) ns=someorg ;; esac
                           echo "{\"id\": 555, \"path_with_namespace\": \"$ns/probe\", \"web_url\": \"https://gitlab.com/$ns/probe\"}" ;;
  # The rollback: the first DELETE schedules it and renames the path, as
  # GitLab.com does; the second removes it for good.
  "api --hostname gitlab.com -X DELETE projects/555")
                           [ "${MOCK_GL_DELETE_FAILS:-0}" = 1 ] && { echo '{"message":"403 Forbidden"}'; exit 1; }
                           : > "$HOME/scheduled"; echo '{"message":"202 Accepted"}' ;;
  "api --hostname gitlab.com projects/555")
                           if [ ! -e "$HOME/scheduled" ]; then
                             skip=false; [ "${MOCK_GL_WALL_FAIL:-}" = readback-checks ] && skip=true
                             squash=always; [ "${MOCK_GL_WALL_FAIL:-}" = readback-squash ] && squash=default_off
                             method=ff; [ "${MOCK_GL_WALL_FAIL:-}" = readback-method ] && method=merge
                             echo "{\"id\": 555, \"path_with_namespace\": \"tester/probe\", \"only_allow_merge_if_pipeline_succeeds\": true, \"allow_merge_on_skipped_pipeline\": $skip, \"squash_option\": \"$squash\", \"merge_method\": \"$method\"}"; exit 0
                           fi
                           [ "${MOCK_GL_GONE:-0}" = 1 ] && { echo '{"message":"404 Project Not Found"}'; exit 1; }
                           echo '{"id": 555, "path_with_namespace": "tester/probe-deletion_scheduled-555"}' ;;
  "api --hostname gitlab.com -X DELETE projects/555?permanently_remove=true&full_path=tester%2Fprobe-deletion_scheduled-555")
                           [ "${MOCK_GL_PERM_FAILS:-0}" = 1 ] && { echo '{"message":"400 Bad request"}'; exit 1; }
                           echo '{"message":"202 Accepted"}' ;;
  # The wall (#533): main's default protection replaced by plinth's, the
  # merge checks, squash and fast-forward, each read back; then the labels.
  "api --hostname gitlab.com -X DELETE projects/555/protected_branches/main")
                           [ "${MOCK_GL_WALL_FAIL:-}" = unprotect ] && { echo '{"message":"403 Forbidden"}'; exit 1; }
                           # GitLab protects the default branch in a job after the push: it may not be protected yet.
                           [ "${MOCK_GL_WALL_FAIL:-}" = unprotect404 ] && { echo '{"message":"404 Not found"}'; exit 1; }
                           # race: not protected yet at the first DELETE; GitLab's job protects it before the POST.
                           case "${MOCK_GL_WALL_FAIL:-}" in race|race2) [ -e "$HOME/raced" ] || { echo '{"message":"404 Not found"}'; exit 1; } ;; esac ;;
  "api --hostname gitlab.com -X POST projects/555/protected_branches -f name=main -F push_access_level=0 -F merge_access_level=40 -F allow_force_push=false")
                           [ "${MOCK_GL_WALL_FAIL:-}" = protect ] && { echo '{"message":"403 Forbidden"}'; exit 1; }
                           if [ "${MOCK_GL_WALL_FAIL:-}" = race2 ] || { [ "${MOCK_GL_WALL_FAIL:-}" = race ] && [ ! -e "$HOME/raced" ]; }; then
                             : > "$HOME/raced"; echo '{"message":"Protected branch '"'"'main'"'"' already exists"}'; exit 1
                           fi
                           echo '{"name":"main"}' ;;
  "api --hostname gitlab.com -X PUT projects/555 -F only_allow_merge_if_pipeline_succeeds=true -F allow_merge_on_skipped_pipeline=false")
                           [ "${MOCK_GL_WALL_FAIL:-}" = checks ] && { echo '{"message":"400 Bad request"}'; exit 1; }
                           echo '{"id": 555}' ;;
  "api --hostname gitlab.com -X PUT projects/555 -f squash_option=always -f merge_method=ff")
                           [ "${MOCK_GL_WALL_FAIL:-}" = squash ] && { echo '{"message":"400 Bad request"}'; exit 1; }
                           echo '{"id": 555}' ;;
  "api --hostname gitlab.com projects/555/protected_branches/main")
                           force=false; [ "${MOCK_GL_WALL_FAIL:-}" = readback-protect ] && force=true
                           push=0; [ "${MOCK_GL_WALL_FAIL:-}" = readback-push ] && push=30
                           echo "{\"name\":\"main\",\"allow_force_push\":$force,\"push_access_levels\":[{\"access_level\":$push}],\"merge_access_levels\":[{\"access_level\":40}]}" ;;
  "api --hostname gitlab.com -X POST projects/555/labels "*)
                           [ "${MOCK_GL_LABEL_FAIL:-}" != "" ] && case "$all" in *"name=${MOCK_GL_LABEL_FAIL} "*) echo '{"message":"400 Bad request"}'; exit 1 ;; esac
                           echo '{"id": 1}' ;;
  # The first merge request and main's first pipeline (#534).
  "api --hostname gitlab.com -X POST projects/555/merge_requests "*)
                           for a in "$@"; do case "$a" in description=*) printf '%s' "${a#description=}" > "$HOME/mr-description" ;; esac; done
                           [ "${MOCK_GL_MR:-ok}" = fail ] && { echo '{"message":["Another open merge request already exists"]}'; exit 1; }
                           echo '{"iid": 1, "web_url": "https://gitlab.com/tester/probe/-/merge_requests/1"}' ;;
  "api --hostname gitlab.com projects/555/pipelines?ref=main")
                           case "${MOCK_GL_BASELINE:-success}" in
                             none)  echo '[]' ;;
                             error) echo '{"message":"500 Internal Server Error"}'; exit 1 ;;
                             *)     echo "[{\"id\": 77, \"status\": \"${MOCK_GL_BASELINE:-success}\", \"web_url\": \"https://gitlab.com/tester/probe/-/pipelines/77\"}]" ;;
                           esac ;;
  "api --hostname gitlab.com projects/555/pipelines/77/jobs?scope[]=failed")
                           echo '[{"name": "test"}, {"name": "deps"}]' ;;
  *"-X "*|*"--method"*)    echo "mock glab: an unexpected write: $all" >&2; exit 3 ;;
  *)                       echo "mock glab: unexpected call: $all" >&2; exit 4 ;;
esac
exit 0
MOCK
cat > "$work/glbin/curl" <<'MOCK'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$GH_LOG"
# MOCK_GL_CHOICES=0 fails the read as `curl -sS` reports a 404, down as it
# reports a host it cannot resolve; nochoices answers a copier.yml with no
# archetype or license choices where the door looks (#629).
case "$*" in *"/copier.yml"*)
  case "${MOCK_GL_CHOICES:-1}" in
    down)      echo "curl: (6) Could not resolve host: raw.githubusercontent.com" >&2; exit 6 ;;
    1)         printf 'license:\n  type: str\n  choices:\n    MIT: MIT\n    Apache-2.0: Apache-2.0\narchetype:\n  type: str\n  choices:\n    CLI: cli\n    Library: library\n    Backend: backend\n    Data: data-ml\n    Web: web\nplinth_sha:\n' ;;
    nochoices) printf 'plinth_sha:\n  type: str\n' ;;
    *)         echo "curl: (22) The requested URL returned error: 404" >&2; exit 22 ;;
  esac ;;
  *) exit 22 ;; esac
MOCK
chmod +x "$work/glbin/"*
for f in git uvx uv claude sleep; do cp "$work/bin/$f" "$work/glbin/"; done
mkdir -p "$work/glbin-noglab"; for f in git uvx uv claude sleep curl; do cp "$work/glbin/$f" "$work/glbin-noglab/"; done
# gl_run <case> <want exit: ok|err> <want create: yes|no> <want deleted: yes|no> <expected output substring> -- <script args...>
# Created is the create call; deleted is the permanent removal. Nothing may call gh.
gl_run() {
  local case="$1" want_exit="$2" want_create="$3" want_del="$4" want_text="$5"; shift 5; [ "$1" = -- ] && shift
  local home="$work/home-$case" rc ok=1 created=no del=no
  mkdir -p "$home"; export HOME="$home" GH_LOG="$home/calls.log" FIRST_PUSHED_FILE="$home/first-pushed"
  : > "$GH_LOG"
  ( cd "$home" && env ${E:-} PATH="${P:-$work/glbin}:/usr/bin:/bin" "$root/scripts/new-project.sh" "$@" ) >"$home/out" 2>&1; rc=$?
  [ "$want_exit" = ok ] && [ "$rc" -ne 0 ] && ok=0
  [ "$want_exit" = err ] && [ "$rc" -eq 0 ] && ok=0
  grep -q '^glab api --hostname gitlab.com -X POST projects ' "$GH_LOG" && created=yes
  grep -q 'permanently_remove=true' "$GH_LOG" && del=yes
  [ "$created" = "$want_create" ] || ok=0
  [ "$del" = "$want_del" ] || ok=0
  grep -q '^gh ' "$GH_LOG" && ok=0
  [ -z "$want_text" ] || grep -qF -- "$want_text" "$home/out" || ok=0
  if [ "$ok" = 1 ]; then ok "$case" "exit=$rc created=$created deleted=$del"
  else bad "$case" "exit=$rc (want $want_exit) created=$created (want $want_create) deleted=$del (want $want_del) text=${want_text:-any}"; sed 's/^/        /' "$home/out"; grep -E '^(gh |glab api .*-X)' "$GH_LOG" | sed 's/^/        log: /'; fi
  E=""; P=""
}

echo "the GitLab door: checks, render, plan and create (#531, #532)"
gl_run gl-plan ok yes no "create gitlab.com/tester/probe (private, MIT, cli, as owner) from coolbress/plinth-template@" -- probe --host gitlab
if grep -q 'host=gitlab' "$work/home-gl-plan/calls.log" && grep -q 'owner=tester' "$work/home-gl-plan/calls.log" \
   && [ -f "$work/home-gl-plan/probe/LICENSE" ] && grep -qF "created https://gitlab.com/tester/probe (private) and pushed main" "$work/home-gl-plan/out" \
   && [ "$("$real_git" -C "$work/home-gl-plan/probe" remote get-url origin 2>/dev/null)" = https://gitlab.com/tester/probe.git ]
then ok gl-plan "renders with host=gitlab and owner, points origin at gitlab.com, creates and pushes"
else bad gl-plan "the render or its remote is not GitLab's"; grep -E '^uvx' "$work/home-gl-plan/calls.log" | sed 's/^/        /'; fi
gl_run gl-plan-eq ok yes no "create gitlab.com/tester/probe" -- probe --host=gitlab
gl_run gl-public ok yes no "(public, MIT, cli, as owner)" -- probe --host gitlab --public
gl_run gl-group ok yes no "create gitlab.com/someorg/probe (private, Apache-2.0, library, as owner)" -- someorg/probe --host gitlab --license=apache-2.0 --archetype=library
E="MOCK_GL_LEVEL=40" gl_run gl-group-maintainer ok yes no "rollback: off" -- someorg/probe --host gitlab
P="$work/glbin-noglab" gl_run gl-no-glab err no no "glab (GitLab CLI) is not installed" -- probe --host gitlab
E="MOCK_GLAB_VERSION=1.40.0" gl_run gl-glab-old err no no "glab 1.40.0 is below" -- probe --host gitlab
E="MOCK_GLAB_NOAUTH=1" gl_run gl-logged-out err no no "glab auth login --hostname gitlab.com" -- probe --host gitlab
E="MOCK_GL_GROUP=0" gl_run gl-group-missing err no no "group 'someorg' does not exist on GitLab.com" -- someorg/probe --host gitlab
E="MOCK_GL_LEVEL=30" gl_run gl-group-developer err no no "needs the Maintainer role" -- someorg/probe --host gitlab
E="MOCK_GL_LEVEL=none" gl_run gl-group-nonmember err no no "needs the Maintainer role" -- someorg/probe --host gitlab
E="MOCK_GL_EXISTS=1" gl_run gl-exists err no no "already exists" -- probe --host gitlab
gl_run gl-bad-license err no no "the template does not carry the license" -- probe --host gitlab --license=gpl-3.0
E="MOCK_TAG=moved" gl_run gl-tag-moved err no no "names commit $(printf '%040d' 1), not $TEMPLATE_SHA, the one this plinth was tested with" -- probe --host gitlab
E="MOCK_TAG=error" gl_run gl-tag-unread err no no "could not read which commit coolbress/plinth-template@$TEMPLATE_REF names" -- probe --host gitlab
if grep -qF "/copier.yml" "$work/home-gl-tag-moved/calls.log"; then bad gl-tag-moved "the template's copier.yml was read although its tag names another commit"
else ok gl-tag-moved "nothing is read from the template before its tag is verified"; fi
# The GitLab door stops on an unread copier.yml; its stop carries curl's error,
# or that the text carried no choices, through the same helper (#629). The fix
# says to run it again only for a network fault: a 404 is reported instead.
E="MOCK_GL_CHOICES=down" gl_run gl-choices-unread err no no "could not read the template's archetype and license choices (coolbress/plinth-template@$TEMPLATE_REF copier.yml)" -- probe --host gitlab
grep -qxF "  curl failed: curl: (6) Could not resolve host: raw.githubusercontent.com" "$work/home-gl-choices-unread/out" && grep -qF "fix: run it again; it needs raw.githubusercontent.com" "$work/home-gl-choices-unread/out" \
  && ok gl-choices-unread "the stop names curl and its error, and says to run it again" || bad gl-choices-unread "the stop does not name curl and its error"
E="MOCK_GL_CHOICES=0" gl_run gl-choices-404 err no no "  curl failed: curl: (22) The requested URL returned error: 404" -- probe --host gitlab
grep -qF "fix: none here; report it at https://github.com/coolbress/plinth/issues" "$work/home-gl-choices-404/out" \
  && ok gl-choices-404 "a 404 at the pinned commit is reported, not retried" || bad gl-choices-404 "the fix line says to run it again on a 404"
E="MOCK_GL_CHOICES=nochoices" gl_run gl-choices-none err no no "lists no archetype or license choices where the door looks: its shape changed, not the network" -- probe --host gitlab
grep -qF "fix: none here; report it at https://github.com/coolbress/plinth/issues" "$work/home-gl-choices-none/out" \
  && ok gl-choices-none "a shape change is reported, not retried" || bad gl-choices-none "the fix line still says to run it again"
if grep -qF "raw.githubusercontent.com/coolbress/plinth-template/$TEMPLATE_SHA/copier.yml" "$work/home-gl-plan/calls.log" \
   && grep -qE "^uvx .*--vcs-ref $TEMPLATE_SHA gh:coolbress/plinth-template " "$work/home-gl-plan/calls.log"
then ok gl-plan "the template's copier.yml is read, and the template rendered, at the tag's pinned commit (#519)"
else bad gl-plan "the template's copier.yml is not read at the pinned commit"; fi
gl_run gl-bad-arch err no no "unknown archetype: service" -- probe --host gitlab --archetype=service
# The web archetype is GitHub only (#615): refused before any tool or login
# is read, so not one call reaches GitLab, and the message says why.
gl_run gl-web err no no "the web archetype is GitHub only: its deployment and checks are built for GitHub" -- probe --host gitlab --archetype=web
if ! grep -q '^glab ' "$work/home-gl-web/calls.log" && grep -qF "fix: drop --host gitlab" "$work/home-gl-web/out"
then ok gl-web "nothing reached GitLab, and the fix names both ways on"
else bad gl-web "a glab call ran before the refusal, or the fix line is missing"; grep '^glab ' "$work/home-gl-web/calls.log" | sed 's/^/        /'; fi
gl_run gl-bad-host err no no "--host is github or gitlab" -- probe --host bitbucket
gl_run gl-github-public err no no "unknown option: --public" -- probe --public
gl_run gl-case ok yes no "create gitlab.com/tester/probe (private, MIT, cli, as owner)" -- Tester/probe --host gitlab
E="MOCK_GLAB_VERSION_FORMAT=old MOCK_GLAB_VERSION=1.36.0" gl_run gl-glab-old-format err no no "glab 1.36.0 is below" -- probe --host gitlab
E="MOCK_GLAB_VERSION_FORMAT=none" gl_run gl-glab-no-version err no no "could not read glab's version" -- probe --host gitlab
E="MOCK_GL_EXISTS=500" gl_run gl-exists-unread err no no "could not tell whether" -- probe --host gitlab
E="MOCK_GL_TOKEN=read_api" gl_run gl-token-read-only err no no "lacks the api scope" -- probe --host gitlab
E="MOCK_GL_TOKEN=oauth" gl_run gl-token-oauth ok yes no "rollback: best effort" -- probe --host gitlab
E="MOCK_GL_CREATION=owner MOCK_GL_LEVEL=40" gl_run gl-group-owner-only err no no "lets only Owners create projects" -- someorg/probe --host gitlab
E="MOCK_GL_CREATION=noone" gl_run gl-group-noone err no no "lets no one create projects" -- someorg/probe --host gitlab
gl_run gl-bad-name err no no "No Python package name can be made from '9lives'" -- 9lives --host gitlab
gl_run gl-slug-git err no no "is not a GitLab project path" -- foo.git --host gitlab
gl_run gl-slug-end err no no "is not a GitLab project path" -- foo- --host gitlab
gl_run gl-slug-double err no no "is not a GitLab project path" -- foo..bar --host gitlab
gl_run gl-exists-404-in-name err no no "could not tell whether" -- foo404 --host gitlab
# The create and the push (#532): what the create call carries, the credential
# helper the push uses, and the rollback when a step after the create fails.
log="$work/home-gl-plan/calls.log"
if grep -q '^glab api --hostname gitlab.com -X POST projects -f name=probe -f path=probe -F namespace_id=70 -f visibility=private -f default_branch=main' "$log" \
   && [ "$(grep -c -- '-X POST projects -f ' "$log")" = 1 ] && grep -q '^git .*push -u origin main' "$log" \
   && "$real_git" -C "$work/home-gl-plan/probe" config --local --get-all credential.https://gitlab.com.helper | grep -qx '!glab auth git-credential'
then ok gl-plan "creates the project once with its name, namespace, visibility and default branch, and pushes main through glab's credential helper"
else bad gl-plan "the create call or the push is not what #532 says"; grep -E -- '-X POST|push' "$log" | sed 's/^/        /'; fi
E="MOCK_GL_CREATE=fail" gl_run gl-create-fail err yes no "the create call failed, so there is nothing to roll back" -- probe --host gitlab
E="FAIL_AT=push" gl_run gl-push-fail err yes yes "deleted https://gitlab.com/tester/probe for good" -- probe --host gitlab
if grep -q '^glab api --hostname gitlab.com -X DELETE projects/555$' "$work/home-gl-push-fail/calls.log" \
   && grep -qF -- '-X DELETE projects/555?permanently_remove=true&full_path=tester%2Fprobe-deletion_scheduled-555' "$work/home-gl-push-fail/calls.log"
then ok gl-push-fail "the rollback schedules the deletion, then removes it for good with the renamed full_path"
else bad gl-push-fail "the rollback is not the two-step permanent removal"; grep -F -- 'DELETE' "$work/home-gl-push-fail/calls.log" | sed 's/^/        /'; fi
E="FAIL_AT=push MOCK_GL_LEVEL=40" gl_run gl-push-fail-maintainer err yes no "only an Owner of someorg can delete it: ask one to delete https://gitlab.com/someorg/probe" -- someorg/probe --host gitlab
E="FAIL_AT=push MOCK_GL_DELETE_FAILS=1" gl_run gl-push-fail-delete-fails err yes no "ROLLBACK FAILED: https://gitlab.com/tester/probe exists with part of its wall or none" -- probe --host gitlab
E="FAIL_AT=push MOCK_GL_PERM_FAILS=1" gl_run gl-push-fail-partial err yes yes "ROLLBACK PARTLY DONE" -- probe --host gitlab
if grep -qF "https://gitlab.com/projects/555" "$work/home-gl-push-fail-partial/out" && ! grep -qF "https://gitlab.com/tester/probe/edit" "$work/home-gl-push-fail-partial/out"
then ok gl-push-fail-partial "a scheduled-only deletion names the project by its id, not by the path GitLab renamed"
else bad gl-push-fail-partial "the partial rollback points at the stale path"; sed 's/^/        /' "$work/home-gl-push-fail-partial/out"; fi
E="FAIL_AT=push MOCK_GL_GONE=1" gl_run gl-push-fail-gone err yes no "rolled back: deleted https://gitlab.com/tester/probe" -- probe --host gitlab
E="FAIL_AT=push MOCK_GL_TOKEN=oauth" gl_run gl-push-fail-oauth err yes yes "rolled back: deleted https://gitlab.com/tester/probe for good" -- probe --host gitlab
E="MOCK_GL_CREATE=noid" gl_run gl-create-noid err yes no "answered without a project id" -- probe --host gitlab
E="MOCK_GL_GROUP_VIS=none" gl_run gl-public-group-vis-unread err no no "could not read the visibility of the group 'someorg'" -- someorg/probe --host gitlab --public
E="MOCK_GL_GROUP_VIS=none" gl_run gl-private-group-vis-unread ok yes no "create gitlab.com/someorg/probe (private," -- someorg/probe --host gitlab
# Before the create, from #535's review rounds 3 and 4.
E="MOCK_GL_GROUP_VIS=private" gl_run gl-public-private-group err no no "is private" -- someorg/probe --host gitlab --public
E="MOCK_GL_GROUP_VIS=internal" gl_run gl-public-internal-group err no no "is internal" -- someorg/probe --host gitlab --public
E="MOCK_GL_GROUP_VIS=private" gl_run gl-private-private-group ok yes no "create gitlab.com/someorg/probe (private," -- someorg/probe --host gitlab
E="MOCK_GL_TOKEN=noscope" gl_run gl-token-noscope err no no "lacks the api scope" -- probe --host gitlab
gl_run gl-reserved err no no "is a name GitLab reserves" -- raw --host gitlab
# The wall (#533): the calls with their values, the read-back, the labels; a
# wall call or a read-back that fails rolls the project back, a label does not.
log="$work/home-gl-plan/calls.log"
want_wall='-X DELETE projects/555/protected_branches/main
-X POST projects/555/protected_branches -f name=main -F push_access_level=0 -F merge_access_level=40 -F allow_force_push=false
-X PUT projects/555 -F only_allow_merge_if_pipeline_succeeds=true -F allow_merge_on_skipped_pipeline=false
-X PUT projects/555 -f squash_option=always -f merge_method=ff'
missing=""; while IFS= read -r w; do grep -qF -- "glab api --hostname gitlab.com $w" "$log" || missing="$missing [$w]"; done <<<"$want_wall"
labels_n="$(grep -vcE '^[[:space:]]*(#|$)' "$root/labels.txt")"
if [ -z "$missing" ] && [ "$(grep -c -- '-X POST projects/555/labels ' "$log")" = "$labels_n" ] \
   && grep -qF -- '-X POST projects/555/labels -f name=feat -f color=#ededed -f description=PR title type' "$log" \
   && grep -q 'glab api --hostname gitlab.com projects/555/protected_branches/main$' "$log"
then ok gl-plan "raises the wall with its values, reads it back, and creates every label in labels.txt"
else bad gl-plan "the wall calls are not what #533 says:$missing"; grep -E -- 'protected_branches|-X PUT|labels' "$log" | head -8 | sed 's/^/        /'; fi
if grep -qF "wall: main protected (no push, Maintainers merge, no force push); merges only when the pipeline succeeds, a skipped one not counted; squash, fast-forward" "$work/home-gl-plan/out" \
   && grep -qF "GitLab Free has no required checks by name: a merge request that drops a job from .gitlab-ci.yml still merges when what is left passes (docs/reference/gitlab-ci.md)" "$work/home-gl-plan/out"
then ok gl-plan "the last lines name the wall and what GitLab Free cannot hold"
else bad gl-plan "the last lines do not name the wall or GitLab Free's limit"; tail -4 "$work/home-gl-plan/out" | sed 's/^/        /'; fi
# Each failing step names itself (with GitLab's answer for a call), rolls the
# project back, and makes no wall call after it.
while IFS='|' read -r f msg after; do
  E="MOCK_GL_WALL_FAIL=$f" gl_run "gl-wall-$f" err yes yes "$msg" -- probe --host gitlab
  o="$work/home-gl-wall-$f"
  if grep -qF "rolled back: deleted https://gitlab.com/tester/probe for good" "$o/out" \
     && { [ -z "$after" ] || ! grep -qF -- "$after" "$o/calls.log"; } && ! grep -qF -- "/labels " "$o/calls.log"
  then ok "gl-wall-$f" "rolled back, no later wall call or label"
  else bad "gl-wall-$f" "no rollback line, or a call after the failing step"; grep -E -- 'protected_branches|-X PUT|labels' "$o/calls.log" | head -6 | sed 's/^/        /'; fi
done <<'CASES'
unprotect|could not remove GitLab's default protection of main: 403 Forbidden|-X POST projects/555/protected_branches
protect|could not protect main: GitLab answered: {"message":"403 Forbidden"}|-X PUT projects/555
checks|could not set the merge checks: GitLab answered: {"message":"400 Bad request"}|squash_option=always
squash|could not require squash and fast-forward merges: GitLab answered: {"message":"400 Bad request"}|gitlab.com projects/555/protected_branches/main
readback-protect|main's protection did not read back as set|
readback-push|main's protection did not read back as set|
readback-checks|the merge settings did not read back as set|
readback-squash|the merge settings did not read back as set|
readback-method|the merge settings did not read back as set|
CASES
# A wall step failing where the login cannot delete: protection may already be up.
E="MOCK_GL_WALL_FAIL=checks MOCK_GL_LEVEL=40" gl_run gl-wall-checks-maintainer err yes no "rollback is off: https://gitlab.com/someorg/probe stays, with part of its wall or none, and only an Owner of someorg can delete it" -- someorg/probe --host gitlab
E="MOCK_GL_WALL_FAIL=checks MOCK_GL_DELETE_FAILS=1" gl_run gl-wall-checks-delete-fails err yes no "ROLLBACK FAILED: https://gitlab.com/tester/probe exists with part of its wall or none" -- probe --host gitlab
E="MOCK_GL_WALL_FAIL=unprotect404" gl_run gl-wall-unprotect404 ok yes no "wall: main protected" -- probe --host gitlab
E="MOCK_GL_WALL_FAIL=race" gl_run gl-wall-race ok yes no "wall: main protected" -- probe --host gitlab
if [ "$(grep -c -- '-X POST projects/555/protected_branches ' "$work/home-gl-wall-race/calls.log")" = 2 ] \
   && [ "$(grep -c -- '-X DELETE projects/555/protected_branches/main' "$work/home-gl-wall-race/calls.log")" = 2 ]
then ok gl-wall-race "GitLab's protection landing between the DELETE and the POST is deleted again, and the POST retried once"
else bad gl-wall-race "the race was not retried as delete then post"; grep protected_branches "$work/home-gl-wall-race/calls.log" | sed 's/^/        /'; fi
E="MOCK_GL_WALL_FAIL=race2" gl_run gl-wall-race2 err yes yes "could not protect main: GitLab answered: {\"message\":\"Protected branch 'main' already exists\"}" -- probe --host gitlab
# The first merge request and the baseline (#534).
o="$work/home-gl-plan"
if grep -qF -- '-X POST projects/555/merge_requests -f source_branch=docs/first-mr -f target_branch=main -f title=docs: first merge request through the wall -F remove_source_branch=true' "$o/calls.log" \
   && [ "$(grep -c -- '-X POST projects/555/merge_requests ' "$o/calls.log")" = 1 ] \
   && grep -q 'push -u origin docs/first-mr$' "$o/calls.log" \
   && grep -qx '## What and why' "$o/mr-description" && grep -qx '## How it was verified' "$o/mr-description" && grep -qx '## First day' "$o/mr-description" \
   && ! grep -q 'Assisted-by' "$o/mr-description" \
   && [ "$("$real_git" -C "$o/probe" log -1 --format=%s docs/first-mr)" = "docs: first merge request through the wall" ] \
   && "$real_git" -C "$o/probe" show docs/first-mr:README.md | grep -qx '## First day'
then ok gl-plan "opens one merge request from docs/first-mr, in the template's shape, with First day in README.md"
else bad gl-plan "the first merge request is not what #534 says"; grep -E -- 'merge_requests|first-mr' "$o/calls.log" | cut -c1-200 | sed 's/^/        /'; sed 's/^/        desc: /' "$o/mr-description" 2>/dev/null | head -20; fi
want_tail='  first merge request: https://gitlab.com/tester/probe/-/merge_requests/1
  first pipeline on main: success: https://gitlab.com/tester/probe/-/pipelines/77'
if grep -qF "done: https://gitlab.com/tester/probe (private, MIT, cli, coolbress/plinth-template@" "$o/out" \
   && grep -qF -- "$want_tail" "$o/out" \
   && grep -qF "  compute minutes: each pipeline uses the namespace's GitLab.com compute minutes, about 4 to 5 for this one (measured on #353); the quota is at https://gitlab.com/-/profile/usage_quotas" "$o/out" \
   && grep -qF "  next: cd $o/probe && claude" "$o/out" && ! grep -q "not done yet" "$o/out"
then ok gl-plan "the last lines name the project, the merge request, the baseline, the wall and both Free limits"
else bad gl-plan "the last lines are not what #534 says"; tail -12 "$o/out" | sed 's/^/        /'; fi
E="PLINTH_ASSISTED_BY=Claude:claude-opus-5-5" gl_run gl-assisted ok yes no "first merge request: https://gitlab.com/tester/probe/-/merge_requests/1" -- probe --host gitlab
if [ "$(tail -1 "$work/home-gl-assisted/mr-description")" = "Assisted-by: Claude:claude-opus-5-5" ]
then ok gl-assisted "an AI-assisted run ends the description with its Assisted-by line"
else bad gl-assisted "no Assisted-by line last"; tail -3 "$work/home-gl-assisted/mr-description" 2>/dev/null | sed 's/^/        /'; fi
E="PLINTH_ASSISTED_BY=Claude" gl_run gl-assisted-bad err no no "PLINTH_ASSISTED_BY must be <agent>:<model>" -- probe --host gitlab
E="MOCK_GL_MR=fail PLINTH_ASSISTED_BY=Claude:claude-opus-5-5" gl_run gl-mr-fail ok yes no "first merge request: not opened (GitLab answered: {\"message\":[\"Another open merge request already exists\"]}); open it: cd $work/home-gl-mr-fail/probe && glab mr create --source-branch docs/first-mr --target-branch main --title 'docs: first merge request through the wall' --description-file .git/plinth-first-mr.md --remove-source-branch --yes" -- probe --host gitlab
# The printed command opens the same merge request: its description is kept.
if [ "$(cat "$work/home-gl-mr-fail/mr-description")" = "$(cat "$work/home-gl-mr-fail/probe/.git/plinth-first-mr.md")" ] \
   && [ "$(tail -1 "$work/home-gl-mr-fail/probe/.git/plinth-first-mr.md")" = "Assisted-by: Claude:claude-opus-5-5" ]
then ok gl-mr-fail "the description the call sent is kept for the command that opens it"
else bad gl-mr-fail "the recovery command would open a different merge request"; fi
E="FAIL_AT=push-branch" gl_run gl-mr-push-fail ok yes no "first merge request: not opened (the push of docs/first-mr failed: mock git: branch push refused on purpose)" -- probe --host gitlab
# A --dir with a space: every printed cd is quoted, so it runs when pasted.
spaced="$work/home-gl-mr-spaced/My Project"; spaced_q="$(printf %q "$spaced")"
E="FAIL_AT=push-branch" gl_run gl-mr-spaced ok yes no "push and open it: cd $spaced_q && git push -u origin docs/first-mr" -- probe --host gitlab "--dir=$spaced"
grep -qF "  next: cd $spaced_q && claude" "$work/home-gl-mr-spaced/out" \
  && ok gl-mr-spaced "the next line quotes the directory too" || bad gl-mr-spaced "the next line does not quote the directory"
grep -q -- '-X POST projects/555/merge_requests ' "$work/home-gl-mr-push-fail/calls.log" \
  && bad gl-mr-push-fail "a merge request was asked for after its branch failed to push" || ok gl-mr-push-fail "no merge request without its branch"
E="MOCK_GL_BASELINE=running PLINTH_FIRST_PR_WAIT=20" gl_run gl-baseline-running ok yes no "first pipeline on main: not confirmed: still running after 20 s: https://gitlab.com/tester/probe/-/pipelines/77" -- probe --host gitlab
[ "$(grep -c 'pipelines?ref=main$' "$work/home-gl-baseline-running/calls.log")" = 3 ] \
  && ok gl-baseline-running "polls every 10 s until the wait ends" || bad gl-baseline-running "polls: $(grep -c 'pipelines?ref=main$' "$work/home-gl-baseline-running/calls.log")"
E="MOCK_GL_BASELINE=none PLINTH_FIRST_PR_WAIT=0" gl_run gl-baseline-none ok yes no "first pipeline on main: not confirmed: not listed within 0 s" -- probe --host gitlab
E="MOCK_GL_BASELINE=none PLINTH_FIRST_PR_WAIT=08" gl_run gl-wait-leading-zero ok yes no "first pipeline on main: not confirmed: not listed within 8 s" -- probe --host gitlab
E="MOCK_GL_BASELINE=error PLINTH_FIRST_PR_WAIT=0" gl_run gl-baseline-error ok yes no "first pipeline on main: not confirmed: could not be read (500 Internal Server Error)" -- probe --host gitlab
E="MOCK_GL_BASELINE=failed" gl_run gl-baseline-failed ok yes no "first pipeline on main: failed (failed jobs: test, deps), not re-run: https://gitlab.com/tester/probe/-/pipelines/77" -- probe --host gitlab
grep -q '/retry' "$work/home-gl-baseline-failed/calls.log" && bad gl-baseline-failed "a red baseline was re-run" || ok gl-baseline-failed "a red baseline is not re-run"
E="MOCK_GL_LABEL_FAIL=task" gl_run gl-label-fail ok yes no "could not create the label task: GitLab answered: {\"message\":\"400 Bad request\"}" -- probe --host gitlab
E="MOCK_GL_SUBGROUP=1" gl_run gl-subgroup err no no "a subgroup already holds that path" -- someorg/probe --host gitlab
if [ ! -e "$work/home-gl-bad-name/9lives" ]; then ok gl-bad-name "a name the template refuses stops before the render"
else bad gl-bad-name "a refused name left a directory behind"; fi
# Run it with every token name glab and gh read set, and look at what copier
# was given: none of them may reach it (#535 review round 3).
E="GH_TOKEN=gh1 GITHUB_TOKEN=gh2 GITLAB_TOKEN=gl1 GITLAB_ACCESS_TOKEN=gl2 OAUTH_TOKEN=gl3 MOCK_UVX_ENV=1" gl_run gl-render-env ok yes no "create gitlab.com/tester/probe" -- probe --host gitlab
if [ -f "$work/home-gl-render-env/uvx-env" ] && ! grep -qE '^(GH_TOKEN|GITHUB_TOKEN|GITLAB_TOKEN|GITLAB_ACCESS_TOKEN|OAUTH_TOKEN)=' "$work/home-gl-render-env/uvx-env"
then ok gl-render-env "copier's environment holds none of gh's or glab's token variables"
else bad gl-render-env "a token variable reached copier"; grep -E 'TOKEN' "$work/home-gl-render-env/uvx-env" 2>/dev/null | cut -d= -f1 | sed 's/^/        /'; fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
