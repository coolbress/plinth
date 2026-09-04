#!/usr/bin/env bash
# The door's failure paths, offline. The one property scripts/new-project.sh
# must keep: nothing is created until preflight passes, and once created,
# any failure deletes the repository. The success path is visible by eye; the
# failure paths only by failing them, which needs a repository, so `gh` is a
# mock. It records every call and fails at the step FAIL_AT names. The
# verdicts: was `gh repo create` called, was `gh repo delete` called.
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
  "api /licenses/"*)                             step=license ;;
  *"/contents/copier.yml"*)                      step=choices ;;
  "api -X GET repos/"*"/actions/runs "*)          step=runs ;;
  "api repos/"*" --jq .html_url"*)               step=exists ;;
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
if [ "$step" = "${FAIL_AT:-}" ]; then echo "mock gh: failing at $step on purpose" >&2; exit 1; fi
case "$step" in
  auth)          [ "${MOCK_NOAUTH:-0}" = 1 ] && exit 1 ;;
  headers)       printf 'HTTP/2.0 200 OK\n'
                 [ "${MOCK_FINE:-0}" = 1 ] || printf 'X-Oauth-Scopes: %s\n' "${MOCK_SCOPES-gist, read:org, repo, workflow, delete_repo}"
                 printf '\n{"login":"tester"}\n' ;;
  login)         echo tester ;;
  owner)         case "$all" in *users/nobody*) exit 1 ;; *users/someorg*) echo Organization ;; *) echo User ;; esac ;;
  membership)    [ "${MOCK_MEMBER:-1}" = 1 ] || exit 1; echo member ;;
  license-check) case "$all" in *licenses/mit*) echo MIT ;; *licenses/apache-2.0*) echo Apache-2.0 ;; *) exit 1 ;; esac ;;
  license)       echo "MOCK LICENSE BODY" ;;
  choices)       printf 'archetype:\n  type: str\n  choices:\n    CLI: cli\n    Library: library\n    Backend: backend\n    Data: data-ml\nlicense:\n' | base64 ;;
  exists)        [ "${MOCK_EXISTS:-0}" = 1 ] || exit 1; echo "https://github.com/x/y" ;;
  delete)        [ "${MOCK_DELETE_FAILS:-0}" = 1 ] && exit 1 ;;
  pr)            echo "https://github.com/tester/probe/pull/1" ;;
  runs)          case "${MOCK_RUNS:-ok}" in
                   ok)      printf '.github/workflows/label.yml completed success\n.github/workflows/ci.yml queued null\n' ;;
                   startup) printf '.github/workflows/ci.yml completed startup_failure\n' ;;
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
if [ "${FAIL_AT:-}" = copier ]; then echo "mock copier: refusing on purpose" >&2; exit 1; fi
dst="${!#}"; pname=""; plic=""
for a in "$@"; do case "$a" in project_name=*) pname="${a#*=}" ;; license=*) plic="${a#*=}" ;; esac; done
: "${pname:?mock copier: no --data project_name}"; : "${plic:?mock copier: no --data license}"
# `-` last inside the brackets: GNU tr reads '.- ' as a range (a CI-only failure, 2026-08-28).
pkg="$(printf '%s' "$pname" | sed 's/[.[:space:]-]/_/g' | tr '[:upper:]' '[:lower:]')"
mkdir -p "$dst/tests" "$dst/src/$pkg" "$dst/.github/workflows"
printf 'MIT\n' > "$dst/LICENSE"
printf '# %s\n' "$pname" > "$dst/README.md"
printf 'name = "%s"\nlicense = "%s"\n' "$pkg" "$plic" > "$dst/pyproject.toml"
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
  mkdir -p "$home"; export HOME="$home" GH_LOG="$home/calls.log"; : > "$GH_LOG"
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
E="MOCK_FINE=1"       run fine-grained  err no no "with-admin-token.sh"                      -- probe
run owner-unknown  err no no "does not exist on GitHub"                                      -- nobody/probe
run owner-other    err no no "user account other than yours"                                -- alice/probe
E="MOCK_MEMBER=0"     run org-nonmember err no no "not a member of the organization"         -- someorg/probe
run private        err no no "private repositories are not supported yet"                   -- probe --private
run private-first  err no no "private repositories are not supported yet"                   -- --private probe
run two-names      err no no "one name only"                                                -- probe other
run bad-option     err no no "unknown option: --nope"                                       -- probe --nope
E="MOCK_EXISTS=1"     run repo-exists   err no no "already exists; the door creates new"     -- probe
run license-typo   err no no "unknown license: bogus"                                       -- probe --license=bogus
run archetype-typo err no no "the template accepts: cli library backend data-ml"            -- probe --archetype=service
mkdir -p "$work/home-dir-exists/probe"
run dir-exists     err no no "already exists"                                               -- probe
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
run org-member     ok yes no "as member"                                                    -- someorg/probe

echo "after creation: any failure deletes"
for at in copier push codeql ruleset secret dependabot actions allowlist merge pr; do
  E="FAIL_AT=$at" run "$at" err yes yes "" -- probe
done
E="FAIL_AT=license" run license err yes yes "" -- probe --license=apache-2.0
E="MOCK_RUNS=startup" run startup-failure err yes yes "failed at startup" -- probe
E="FAIL_AT=ruleset MOCK_DELETE_FAILS=1" run delete-fails err yes yes "ROLLBACK FAILED: https://github.com/tester/probe EXISTS WITHOUT A WALL" -- probe

echo "success: nothing is deleted, and the order is baseline, wall, first pull request"
run none ok yes no "first pull request: https://github.com/tester/probe/pull/1" -- probe
log="$work/home-none/calls.log"; proj="$work/home-none/probe"
check() { if eval "$2"; then ok none "$1"; else bad none "$1"; fi; }
check "main is pushed before the ruleset, the pull request after it" \
  '[ "$(grep -E "push -q -u origin main|/rulesets|^gh pr create" "$log" | sed -E "s/^git .*push.*/main/; s/.*rulesets.*/ruleset/; s/^gh pr create.*/pr/" | tr "\n" " ")" = "main ruleset pr " ]'
check "CodeQL default setup precedes the ruleset" 'grep -E "code-scanning|/rulesets" "$log" | head -1 | grep -q code-scanning'
check "the Actions allowlist names coolbress/plinth/*" 'grep -q "patterns_allowed\[\]=coolbress/plinth/\*" "$log"'
check "Actions: selected, SHA pins required" 'grep -q "allowed_actions=selected -F sha_pinning_required=true" "$log"'
check "the default branch is main" '[ "$("$REAL_GIT" -C "$proj" rev-parse --verify -q main)" != "" ]'
check "the first pull request is one README line on docs/first-pr" \
  '[ "$("$REAL_GIT" -C "$proj" rev-parse --abbrev-ref HEAD)" = docs/first-pr ] && [ "$("$REAL_GIT" -C "$proj" diff --stat main docs/first-pr | tail -1 | grep -o "[0-9]* insertion")" = "1 insertion" ]'
check "render is final: real name and license in pyproject.toml and uv.lock, src/probe/, no bootstrap.sh" \
  'grep -q probe "$proj/pyproject.toml" && grep -q MIT "$proj/pyproject.toml" && grep -q probe "$proj/uv.lock" && [ -d "$proj/src/probe" ] && [ ! -e "$proj/bootstrap.sh" ]'
check "the summary line names owner, visibility, license, archetype, role and the template tag" \
  'grep -q "^create tester/probe (public, MIT, cli, as owner) from coolbress/project-template@v2.18.0 in " "$work/home-none/out"'

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
