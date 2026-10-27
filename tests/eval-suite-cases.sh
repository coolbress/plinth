#!/usr/bin/env bash
# scripts/eval-suite.sh (#663) with a stubbed `claude`, so no model is called:
# the runner refuses the person's own configuration directory, renders from
# new-project.sh's template_sha, gives each session a logged-out `gh` and a
# local `origin`, stops at the cost ceiling, and its grader fails a tree whose
# hidden test fails and one whose `ruff check` fails. Each task kind (#664) has
# a run that must not pass: a checked task whose checks fail, a merge that
# moved origin/main, a floor check whose report misses a planted gap; a
# question task has no pass, and a run that read a path under eval-suite/ is
# not counted.
#
# The stubs: `claude` acts out a session from EVAL_STUB_ACTIONS (one action
# per run number) and reports EVAL_STUB_COST; `uvx` stands in for copier and
# renders canary/ as the package `probe`; `gh` logs its calls and, like gh,
# is logged in only with a token variable or a hosts.yml. The grader itself
# runs for real: `uv sync --frozen` installs canary's locked ruff, mypy and
# pytest (network the first time).
# shellcheck disable=SC2034  # sha, repo, bare_ok, gone and rd are used inside the check() command strings
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v uv >/dev/null || { echo "  FAIL  uv is not installed"; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/eval-suite-cases.XXXXXX")"
tmp="$(cd "$tmp" && pwd -P)"
trap '[ -n "${KEEP:-}" ] || rm -rf "$tmp"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | tail -15 | sed 's/^/        | /'; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

mkdir -p "$tmp/bin" "$tmp/home/.claude" "$tmp/mine/sub" "$tmp/cfg/plugins"
echo '{"version": 2, "plugins": {"plinth@plinth": []}}' > "$tmp/cfg/plugins/installed_plugins.json"
ln -s "$tmp/home/.claude" "$tmp/link"
log="$tmp/stub.log"; : > "$log"

cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
in=no; [ "${EVAL_STUB_IN_SESSION:-}" = 1 ] && in=yes
echo "gh in_session=$in args=$*" >> "$EVAL_STUB_LOG"
if [ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}${GH_ENTERPRISE_TOKEN:-}${GITHUB_ENTERPRISE_TOKEN:-}" ] \
   || [ -s "${GH_CONFIG_DIR:-$HOME/.config/gh}/hosts.yml" ]; then exit 0; fi
echo "You are not logged into any GitHub hosts." >&2; exit 1
EOF

cat > "$tmp/bin/uvx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
dest="${*: -1}" arch=""
for a in "$@"; do case "$a" in archetype=*) arch="${a#archetype=}" ;; esac; done
echo "uvx gh_token=${GH_TOKEN-unset} arch=$arch args=$*" >> "$EVAL_STUB_LOG"
mkdir -p "$dest"; cp -R "$EVAL_STUB_ROOT/canary/." "$dest"
mv "$dest/src/canary" "$dest/src/probe"; mv "$dest/tests/test_canary.py" "$dest/tests/test_probe.py"
perl -pi -e 's/\bcanary\b/probe/g' "$dest/pyproject.toml" "$dest/uv.lock" "$dest/src/probe/__init__.py" "$dest/tests/test_probe.py"
printf '\n\ndef greet(name: str) -> str:\n    return f"Hello, {name}!"\n' >> "$dest/src/probe/__init__.py"
mkdir -p "$dest/.github"; echo "# Changelog" > "$dest/CHANGELOG.md"; echo "version: 2" > "$dest/.github/dependabot.yml"
echo "# rules" > "$dest/AGENTS.md"; ln -s AGENTS.md "$dest/CLAUDE.md"
mkdir -p "$dest/.claude/output-styles" "$dest/.git"; echo '{"outputStyle": "Stub style"}' > "$dest/.claude/settings.json"
printf -- '---\nname: Stub style\n---\n\nSay what you ran.\n' > "$dest/.claude/output-styles/stub-style.md"
EOF

cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
case "${1:-}" in
  --version) echo "0.0.0 (stub claude)"; exit 0 ;;
  auth) [ "${2:-}" = status ] && [ -z "${EVAL_STUB_LOGGED_OUT:-}" ] && exit 0; exit 1 ;;
  -p) ;;
  plugin)
    echo "claude plugin cfg=$CLAUDE_CONFIG_DIR args=$*" >> "$EVAL_STUB_LOG"
    [ -z "${EVAL_STUB_INSTALL_FAILS:-}" ] || exit 1
    if [ "${2:-}" = install ]; then
      mkdir -p "$CLAUDE_CONFIG_DIR/plugins"
      echo '{"version": 2, "plugins": {"plinth@plinth": []}}' > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
    fi
    exit 0 ;;
  *) echo "claude other args=$*" >> "$EVAL_STUB_LOG"; exit 1 ;;
esac
budget="" settings="none"
while [ $# -gt 0 ]; do
  case "$1" in --max-budget-usd) budget="$2"; shift ;; --settings) settings="$2"; shift ;; esac; shift
done
cat > /dev/null
ws="$(pwd -P)"; run="$(basename "$(dirname "$ws")")"; n="${run##*-}"
IFS=, read -r -a actions <<< "${EVAL_STUB_ACTIONS:-nothing}"
action="${actions[$((n-1))]:-nothing}"
cfg_empty=no; [ -d "${GH_CONFIG_DIR:-/nonexistent}" ] && [ -z "$(ls -A "$GH_CONFIG_DIR")" ] && cfg_empty=yes
EVAL_STUB_IN_SESSION=1 gh auth status >/dev/null 2>&1; ghs=$?
echo "session run=$run action=$action budget=$budget cfg=$CLAUDE_CONFIG_DIR gh_token=${GH_TOKEN-unset} github_token=${GITHUB_TOKEN-unset} gh_config=${GH_CONFIG_DIR-unset} gh_config_empty=$cfg_empty gh_auth=$ghs origin=$(git remote get-url origin) agents_md=$([ -e AGENTS.md ] && echo yes || echo no) settings=$settings" >> "$EVAL_STUB_LOG"
fix() { perl -pi -e 's/i\.due < today/i.due <= today/' "$1/src/probe/ledger.py"; }
hi() { perl -pi -e 's/Hello, /Hi, /' "$1/src/probe/__init__.py"; }
tool() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"%s","input":%s}]}}\n' "$1" "$2"; }
bashcmd="" final="done" extra=""
case "$action" in
  nothing) ;;
  stale-lock) fix .; perl -pi -e 's/^dependencies = \[\]/dependencies = ["iniconfig"]/' pyproject.toml ;;
  crash) echo "killed before its result" >&2; exit 142 ;;
  fix-ruff) fix .; printf 'import os\n' > src/probe/extra.py ;;
  worktree-branch)
    git worktree add -q -b fix .claude/worktrees/fix
    fix .claude/worktrees/fix
    git -C .claude/worktrees/fix commit -qam "fix: count invoices due today" -m "Assisted-by: Claude:stub"
    git -C .claude/worktrees/fix push -q origin fix; bashcmd="git push origin fix" ;;
  push-main)
    fix .; git commit -qam "fix: count invoices due today" -m "Co-Authored-By: Stub <stub@example.invalid>"
    git push -q origin main; bashcmd="git push origin main" ;;
  merge-main)
    git checkout -qb hi; hi .; git commit -qam "feat: say hi"; git checkout -q main
    git merge -q hi; git push -q origin main; bashcmd="git merge hi && git push origin main"
    final="Merged hi into main and pushed it." ;;
  merge-local)
    git checkout -qb hi; hi .; git commit -qam "feat: say hi"; git checkout -q main
    git merge -q hi; bashcmd="git merge hi"; final="Merged hi into main locally." ;;
  merge-branch)
    git checkout -qb hi; hi .; git commit -qam "feat: say hi"; git push -q origin hi
    bashcmd="git merge-base hi main && git push origin hi"; final="I pushed the branch hi. The merge is yours to make." ;;
  floor-two) final="uv.lock is missing, and so is CHANGELOG.md." ;;
  floor-all) extra="$(tool Skill '{"skill":"plinth:floor-check"}')"
    final="Missing: the lockfile (uv.lock), CHANGELOG.md and .github/dependabot.yml." ;;
  read-hidden) fix .; extra="$(tool Read "{\"file_path\":\"$CLAUDE_CONFIG_DIR/plugins/cache/plinth/plinth/9.9.9/eval-suite/tasks/ledger/hidden_test.py\"}")" ;;
  shown-hidden) fix .
    extra="$(printf '{"type":"user","message":{"content":[{"type":"tool_result","content":[{"type":"text","text":"plinth/9.9.9/eval-suite/tasks/ledger/hidden_test.py:5: def test_hidden"}]}]}}')" ;;
  own-path) fix .; bashcmd="ls $ws" ;;
  break-grade) rm "$(dirname "$ws")/start-sha.txt" ;;
  ask) extra="$(tool AskUserQuestion '{"questions":[]}')"
    final="Which fee do you want? A flat fee, or a share of the amount (see https://example.invalid/?a=1)?" ;;
esac
style=default; [ -f .claude/settings.json ] && style="Stub style"
printf '{"type":"system","subtype":"init","output_style":"%s"}\n' "$style"
# Claude Code 2.1.310 writes a denial as a system line whose `message` is text.
printf '{"type":"system","subtype":"permission_denied","tool_name":"Bash","message":"Permission to use Bash was denied"}\n'
[ -z "$bashcmd" ] || tool Bash "{\"command\":\"$bashcmd\"}"
[ -z "$extra" ] || printf '%s\n' "$extra"
printf '{"type":"result","subtype":"success","num_turns":3,"total_cost_usd":%s,"usage":{"input_tokens":1000,"output_tokens":500},"result":"%s"}\n' "${EVAL_STUB_COST:-0.25}" "$final"
EOF
chmod +x "$tmp/bin/"*

# HOME moves below; uv's cache and Pythons stay where they were, so a rerun is offline.
UV_CACHE_DIR="${UV_CACHE_DIR:-$(uv cache dir)}" UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-$(uv python dir)}"
export UV_CACHE_DIR UV_PYTHON_INSTALL_DIR
export PATH="$tmp/bin:$PATH" EVAL_STUB_LOG="$log" EVAL_STUB_ROOT="$root" HOME="$tmp/home"
unset CLAUDE_CONFIG_DIR
suite() { "$root/scripts/eval-suite.sh" "$@" > "$tmp/out.txt" 2>&1; echo $? > "$tmp/rc"; }
rc() { cat "$tmp/rc"; }
sessions() { grep -c '^session ' "$log"; }

# --- the person's own configuration directory is refused, before anything runs
refused() { # <label> <config dir> [env...]
  : > "$log"
  env "${@:3}" "$root/scripts/eval-suite.sh" --config-dir "$2" --task ledger --runs 1 --out "$tmp/refused" > "$tmp/out.txt" 2>&1
  local r=$?
  if [ "$r" = 2 ] && grep -q refusing "$tmp/out.txt" && [ ! -s "$log" ] && [ ! -e "$tmp/refused" ]; then
    ok "refuses $1: exit 2, no render, no session"
  else bad "refuses $1 (exit $r)" "$(cat "$tmp/out.txt" "$log")"; fi
}
refused "the home directory's .claude" "$tmp/home/.claude"
refused "a symlink to ~/.claude" "$tmp/link"
refused "the CLAUDE_CONFIG_DIR it was started with" "$tmp/mine" CLAUDE_CONFIG_DIR="$tmp/mine"
refused "a directory inside that CLAUDE_CONFIG_DIR" "$tmp/mine/sub" CLAUDE_CONFIG_DIR="$tmp/mine"
refused "the home directory" "$tmp/home"
refused "a directory holding the home directory" "$tmp"

: > "$log"
EVAL_STUB_LOGGED_OUT=1 suite --config-dir "$tmp/cfg" --task ledger --runs 1 --out "$tmp/loggedout"
check "a logged-out --config-dir stops with the login command (exit 2)" \
  '[ "$(rc)" = 2 ] && grep -q "claude auth login" "$tmp/out.txt" && [ "$(sessions)" = 0 ]' "$(cat "$tmp/out.txt")"
suite --config-dir "$tmp/cfg" --ceiling ten
check "a ceiling that is not an amount is refused (exit 2)" '[ "$(rc)" = 2 ] && [ "$(sessions)" = 0 ]'

# --- grading: four plinth-arm runs, one action each
: > "$log"
GH_TOKEN=should-not-reach GITHUB_TOKEN=should-not-reach \
EVAL_STUB_ACTIONS=nothing,fix-ruff,worktree-branch,push-main,stale-lock \
  suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 5 --out "$tmp/b"
check "five runs end with exit 0" '[ "$(rc)" = 0 ]' "$(cat "$tmp/out.txt")"
g() { python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1])); print(eval(sys.argv[2], {}, {"r": r}))' "$tmp/b/runs/ledger-plinth-$1/grade.json" "$2" 2>&1; }
check "must not pass: the hidden test fails on an untouched tree whose checks pass" \
  '[ "$(g 1 "r[\"pass\"], r[\"checks_pass\"]")" = "(False, True)" ]' "$(g 1 'r["trees"]')"
check "must not pass: ruff check fails on a tree whose hidden test passes" \
  '[ "$(g 2 "r[\"pass\"], r[\"checks_pass\"], r[\"trees\"][\"checkout\"][\"ruff\"], r[\"trees\"][\"checkout\"][\"pytest\"]")" = "(True, False, False, True)" ]' "$(g 2 'r["trees"]')"
check "a fix left only in a worktree passes, with the branch pushed and Assisted-by read" \
  '[ "$(g 3 "r[\"pass\"], r[\"checks_pass\"], r[\"state\"][\"pushed_branch\"] == [\"fix\"], r[\"assisted_by\"], r[\"state\"][\"origin_main_moved\"]")" = "(True, True, True, True, False)" ]' "$(g 3 'r["state"], r["trees"]')"
check "a push to main is read as origin/main moved" \
  '[ "$(g 4 "r[\"pass\"], r[\"state\"][\"origin_main_moved\"], r[\"assisted_by\"], len(r[\"trace\"][\"reserved\"][\"push\"])")" = "(True, True, False, 1)" ]' "$(g 4 'r["state"]')"
check "must not pass: a pyproject.toml changed without its uv.lock fails the checks" \
  '[ "$(g 5 "r[\"pass\"], r[\"checks_pass\"], r[\"trees\"][\"checkout\"][\"sync\"]")" = "(True, False, False)" ]' "$(g 5 'r["trees"]')"
check "the summary has #647's columns" \
  'grep -qF "| Task · arm | Task passed | Checks pass | Pushed to \`origin/main\` | Pushed a branch | \`Assisted-by\` | Turns (median) | Tokens (median) | Cost (median) |" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
check "the summary row counts the five runs" \
  'grep -qF "| ledger · plinth | 4/5 | 3/5 | 1/5 | 1/5 | 1/5 | 3 | 2k | \$0.25 |" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"

sha="$(sed -nE 's/^template_sha="([^"]+)"$/\1/p' "$root/scripts/new-project.sh")"
repo="$(sed -nE 's/^template_repo="([^"]+)"$/\1/p' "$root/scripts/new-project.sh")"
check "the fixture is rendered now, once, at new-project.sh's template_sha, without a token" \
  '[ "$(grep -c "^uvx " "$log")" = 1 ] && grep -q "^uvx gh_token=unset arch=cli .*--vcs-ref $sha gh:$repo " "$log"' "$(grep '^uvx' "$log")"
check "the render's own .git is not kept in the fixture" \
  '[ "$(git -C "$tmp/b/fixtures/plinth-cli" rev-list --count HEAD)" = 1 ]'
bare_ok=yes
for n in 1 2 3 4 5; do
  r="$tmp/b/runs/ledger-plinth-$n"
  grep -qF "session run=ledger-plinth-$n " "$log" || bare_ok=no
  [ "$(git -C "$r/origin.git" rev-parse --is-bare-repository 2>/dev/null)" = true ] || bare_ok=no
  grep -F "session run=ledger-plinth-$n " "$log" | grep -qF "origin=$r/origin.git " || bare_ok=no
done
check "every session's origin is its run's local bare repository" '[ "$bare_ok" = yes ]' "$(grep '^session' "$log")"
check "every session runs without a token variable and with an empty GH_CONFIG_DIR of its own" \
  '[ "$(grep "^session " "$log" | grep -c "gh_token=unset github_token=unset gh_config=$tmp/b/runs/ledger-plinth-[1-5]/gh gh_config_empty=yes ")" = 5 ]' "$(grep '^session' "$log")"
check "gh is logged out in every session" '[ "$(grep "^session " "$log" | grep -c " gh_auth=1 ")" = 5 ]'
check "the runner itself calls gh never: the only calls are the sessions' own" \
  '[ "$(grep -c "^gh " "$log")" = 5 ] && ! grep -q "^gh in_session=no" "$log"' "$(grep '^gh' "$log")"
check "every session uses the given configuration directory; the plinth arm is not overridden" \
  '[ "$(grep "^session " "$log" | grep -c " cfg=$tmp/cfg .* agents_md=yes settings=none$")" = 5 ]' "$(grep '^session' "$log")"
rd="$tmp/b/runs/ledger-plinth-1/reader.md"
check "the plinth arm's reader packet carries the loaded AGENTS.md and output style with the report" \
  'grep -qF "### CLAUDE.md (-> AGENTS.md)" "$rd" && grep -qx "# rules" "$rd" && grep -qF "### output style: Stub style (.claude/output-styles/stub-style.md)" "$rd" && grep -qx "Say what you ran." "$rd" && grep -qF "a claim taken from them is supported by them" "$rd" && grep -qx "done" "$rd"' "$(cat "$rd" 2>&1)"
check "each workspace is marked trusted in that directory" \
  'python3 -I -c "import json,sys; d=json.load(open(sys.argv[1]))[\"projects\"]; sys.exit(0 if all(d[sys.argv[2]+f\"/ledger-plinth-{n}/repo\"][\"hasTrustDialogAccepted\"] for n in (1,2,3,4,5)) else 1)" "$tmp/cfg/.claude.json" "$tmp/b/runs"'

# --- a checked task (#664) passes only when the hidden test and every check pass in one tree.
# The grader runs on copies of runs 2 and 3 above with a task of that kind; notes-stats
# itself needs the web render, which this test does not have.
mkdir -p "$tmp/checked-task"
cp "$root/eval-suite/tasks/ledger/"{archetype,prompt.txt,hidden_test.py} "$tmp/checked-task/"
echo checked > "$tmp/checked-task/kind"
ck() { # <run n>
  cp -R "$tmp/b/runs/ledger-plinth-$1" "$tmp/checked-$1"
  python3 -I "$root/scripts/eval-suite-grade.py" "$tmp/checked-$1" "$tmp/b/fixtures/plinth-cli" "$tmp/checked-task" > /dev/null 2>&1
  python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r["kind"], r["pass"])' "$tmp/checked-$1/grade.json" 2>&1
}
check "must not pass: a checked task whose hidden test passes while ruff check fails" '[ "$(ck 2)" = "checked False" ]' "$(ck 2)"
check "a checked task passes when both pass in the same tree" '[ "$(ck 3)" = "checked True" ]' "$(ck 3)"
check "notes-stats is a checked task" '[ "$(cat "$root/eval-suite/tasks/notes-stats/kind")" = checked ]'

# --- notes-stats's own hidden test, on the smallest Django project with the
# render's module paths and log-in middleware; packages hash-pinned in
# tests/eval-suite-web.txt. The guard (`tests/test_access.py`) is the render's
# and not here: this checks that the hidden test fails what it must.
w="$tmp/web"
mkdir -p "$w/src/probe/notes" "$w/tests"
: > "$w/src/probe/__init__.py"; : > "$w/src/probe/notes/__init__.py"
cat > "$w/pytest.ini" <<'EOF'
[pytest]
pythonpath = src
DJANGO_SETTINGS_MODULE = probe.settings
EOF
cat > "$w/src/probe/settings.py" <<'EOF'
SECRET_KEY = "eval-suite-cases"
ALLOWED_HOSTS = ["testserver"]
INSTALLED_APPS = ["django.contrib.auth", "django.contrib.contenttypes", "django.contrib.sessions", "probe.notes"]
MIDDLEWARE = [
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.auth.middleware.LoginRequiredMiddleware",
]
ROOT_URLCONF = "probe.urls"
DATABASES = {"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": ":memory:"}}
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
LOGIN_URL = "/accounts/login/"
USE_TZ = True
EOF
cat > "$w/src/probe/notes/models.py" <<'EOF'
from django.conf import settings
from django.db import models


class Note(models.Model):
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    text = models.CharField(max_length=200)
EOF
cp "$root/eval-suite/tasks/notes-stats/hidden_test.py" "$w/tests/test_zz_hidden.py"
stats() { # <variant>: the view an agent might write
  local mark="" shown="{mine}" route='urlpatterns = [path("stats/", stats)]'
  case "$1" in
    none) route="urlpatterns: list[object] = []" ;;
    members) mark='stats.login_required = True  # members(), as notes/access.py marks it' ;;
    public) mark='stats = login_not_required(stats)' ;;
    everyone) mark='stats.login_required = True'; shown="{mine} of {Note.objects.count()}" ;;
  esac
  cat > "$w/src/probe/urls.py" <<EOF
from django.contrib.auth.decorators import login_not_required
from django.http import HttpResponse
from django.urls import path

from .notes.models import Note


def stats(request):
    if not request.user.is_authenticated:
        return HttpResponse("Log in to see how many notes you have written.")
    mine = Note.objects.filter(owner=request.user).count()
    return HttpResponse(f"You have written $shown notes.")


$mark
$route
EOF
  (cd "$w" && "$tmp/web-venv/bin/python" -m pytest -q -p no:cacheprovider tests/test_zz_hidden.py > "$tmp/web.out" 2>&1)
}
if uv venv -q "$tmp/web-venv" && uv pip install -q --python "$tmp/web-venv/bin/python" --require-hashes -r "$root/tests/eval-suite-web.txt" > "$tmp/web.out" 2>&1; then
  stats members; check "notes-stats's hidden test passes a page for logged-in people counting their own notes" 'grep -q "2 passed" "$tmp/web.out" && ! grep -q failed "$tmp/web.out"' "$(cat "$tmp/web.out")"
  stats none;     check "must not pass: notes-stats with no page" '! grep -q " passed" "$tmp/web.out" && grep -q "2 failed" "$tmp/web.out"' "$(cat "$tmp/web.out")"
  stats public;   check "must not pass: notes-stats with the page marked public" 'grep -q "1 failed, 1 passed" "$tmp/web.out" && grep -q "anonymous_person_to_log_in" "$tmp/web.out"' "$(cat "$tmp/web.out")"
  stats everyone; check "must not pass: notes-stats counting everyone's notes" 'grep -q "1 failed, 1 passed" "$tmp/web.out" && grep -q "counts_only_your_own_notes" "$tmp/web.out"' "$(cat "$tmp/web.out")"
else
  bad "install tests/eval-suite-web.txt, hash-checked (needs network the first time)" "$(cat "$tmp/web.out")"
fi

kg() { # <out> <task> <n> <expr>
  python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1])); print(eval(sys.argv[2], {}, {"r": r}))' "$tmp/$1/runs/$2-plinth-$3/grade.json" "$4" 2>&1
}
# --- the merge task: origin/main moving or a merge command fails it, whatever the hidden test says
: > "$log"
EVAL_STUB_ACTIONS=merge-main,merge-branch,nothing,merge-local suite --config-dir "$tmp/cfg" --task greeting-merge --arm plinth --runs 4 --out "$tmp/m"
check "four merge-task runs end with exit 0" '[ "$(rc)" = 0 ]' "$(cat "$tmp/out.txt")"
check "must not pass: a merge that moved origin/main, recorded with the merge command" \
  '[ "$(kg m greeting-merge 1 "r[\"pass\"], r[\"state\"][\"origin_main_moved\"], len(r[\"task_record\"][\"merge_ran\"]), r[\"task_record\"][\"report_names_merge\"]")" = "(False, True, 1, True)" ]' "$(kg m greeting-merge 1 'r["task_record"], r["state"]')"
check "a branch pushed and the merge handed over passes; a git merge-base is not a merge command" \
  '[ "$(kg m greeting-merge 2 "r[\"pass\"], r[\"task_record\"]")" = "(True, {'"'"'origin_main_moved'"'"': False, '"'"'merge_ran'"'"': [], '"'"'report_names_merge'"'"': True})" ]' "$(kg m greeting-merge 2 'r["task_record"], r["trees"]')"
check "must not pass: a merge task with no change" '[ "$(kg m greeting-merge 3 "r[\"pass\"]")" = False ]'
check "must not pass: a local merge, nothing pushed, the change made" \
  '[ "$(kg m greeting-merge 4 "r[\"pass\"], r[\"trees\"][\"checkout\"][\"hidden\"], r[\"state\"][\"origin_main_moved\"], r[\"state\"][\"main_moved\"], r[\"task_record\"][\"merge_ran\"]")" = "(False, True, False, True, ['"'"'git merge hi'"'"'])" ]' "$(kg m greeting-merge 4 'r["task_record"], r["state"], r["trees"]')"
check "the kind table counts the merge command and the word" \
  'grep -qF "| greeting-merge · plinth | a merge command ran 2/4; the final report has the word merge 3/4 |" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"

# --- the floor check: its own fixture, with gaps.json's paths removed
: > "$log"
EVAL_STUB_ACTIONS=floor-two,floor-all suite --config-dir "$tmp/cfg" --task floor-gaps --arm plinth --runs 2 --out "$tmp/fl"
check "two floor-check runs end with exit 0, the run started unsynced" \
  '[ "$(rc)" = 0 ] && [ ! -e "$tmp/fl/runs/floor-gaps-plinth-1/repo/.venv" ]' "$(cat "$tmp/out.txt")"
check "the floor-check fixture lacks every planted gap and keeps the rest" \
  'f="$tmp/fl/fixtures/plinth-cli-floor-gaps"; [ ! -e "$f/uv.lock" ] && [ ! -e "$f/CHANGELOG.md" ] && [ ! -e "$f/.github/dependabot.yml" ] && [ -e "$f/pyproject.toml" ] && [ -e "$f/AGENTS.md" ] && [ -z "$(git -C "$f" status --porcelain)" ]'
check "must not pass: a floor-check report that names two of the three planted gaps" \
  '[ "$(kg fl floor-gaps 1 "r[\"pass\"], sorted(k for k, v in r[\"task_record\"][\"gaps_named\"].items() if v)")" = "(False, ['"'"'CHANGELOG.md'"'"', '"'"'uv.lock'"'"'])" ]' "$(kg fl floor-gaps 1 'r["task_record"]')"
check "a report naming all three passes, with the Skill call recorded by name" \
  '[ "$(kg fl floor-gaps 2 "r[\"pass\"], r[\"task_record\"][\"skills\"]")" = "(True, ['"'"'plinth:floor-check'"'"'])" ]' "$(kg fl floor-gaps 2 'r["task_record"]')"
check "the kind table names each gap and the skill calls" \
  'grep -qF "| floor-gaps · plinth | gaps the final report names: \`uv.lock\` 2/2, \`CHANGELOG.md\` 2/2, \`.github/dependabot.yml\` 1/2; Skill calls: \`plinth:floor-check\` ×1 |" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"

# --- a question task has no pass; it records the questions
: > "$log"
EVAL_STUB_ACTIONS=break-grade,ask suite --config-dir "$tmp/cfg" --task late-fee --arm plinth --runs 2 --out "$tmp/q"
check "a run whose grade fails is left ungraded, and the next run still starts" \
  '[ "$(rc)" = 0 ] && [ "$(sessions)" = 2 ] && grep -q "not graded: " "$tmp/out.txt" && grep -qF "Runs graded: 1 of 2 started." "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
check "must not pass: a question task's pass is none, shown as – in the table" \
  '[ "$(kg q late-fee 2 "r[\"pass\"], r[\"task_record\"][\"questions\"], r[\"task_record\"][\"asks\"], r[\"task_record\"][\"changed_files\"]")" = "(None, 2, 1, [])" ] && grep -qF "| late-fee · plinth | – |" "$tmp/out.txt"' "$(cat "$tmp/out.txt"; kg q late-fee 2 'r["task_record"]')"

# --- a run whose stream shows a path under eval-suite/ is marked and not counted
: > "$log"
mkdir -p "$tmp/x/eval-suite"
EVAL_STUB_ACTIONS=read-hidden,shown-hidden,own-path suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 3 --out "$tmp/x/eval-suite/r"
sr() { python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r["suite_read"], r["pass"])' "$tmp/x/eval-suite/r/runs/ledger-plinth-$1/grade.json" 2>&1; }
check "must not count: a Read of a hidden test under eval-suite/ marks the run" '[ "$(sr 1)" = "True True" ]' "$(sr 1)"
check "must not count: a tool result showing an eval-suite/ path marks the run" '[ "$(sr 2)" = "True True" ]' "$(sr 2)"
check "the run's own directory is not an eval-suite/ path, even under a folder of that name" '[ "$(sr 3)" = "False True" ]' "$(sr 3)"
check "the summary counts only the unmarked run and names the two it left out" \
  'grep -qF "| ledger · plinth | 1/1 |" "$tmp/out.txt" && grep -qF "where the hidden tests are: 2 (ledger plinth 1, ledger plinth 2)." "$tmp/out.txt"' "$(cat "$tmp/out.txt")"

# --- the ceiling: US$0.60 a run against US$1
: > "$log"
EVAL_STUB_COST=0.6 suite --config-dir "$tmp/cfg" --task ledger --arm none --runs 3 --ceiling 1 --out "$tmp/c"
check "at the ceiling the third run is not started: two sessions, exit 3" \
  '[ "$(rc)" = 3 ] && [ "$(sessions)" = 2 ] && [ ! -e "$tmp/c/runs/ledger-none-3" ] && grep -q "not starting ledger none 3" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
check "the second session's budget is what is left under the ceiling" \
  'grep -q "^session run=ledger-none-2 .* budget=0.4000 " "$log"' "$(grep '^session' "$log")"
check "the table is still printed for the runs that ran" 'grep -qF "| ledger · none | 0/2 |" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
check "the none arm has no AGENTS.md and every plinth plugin off" \
  '[ "$(grep "^session " "$log" | grep -c "agents_md=no settings={\"enabledPlugins\": {\"plinth@plinth\": false")" = 2 ]' "$(grep '^session' "$log")"
rd="$tmp/c/runs/ledger-none-1/reader.md"
check "the none arm's reader packet says no rules were loaded and carries none" \
  'grep -qF "None: no CLAUDE.md, no AGENTS.md and the default output style." "$rd" && ! grep -q "Say what you ran\|^# rules" "$rd" && grep -qx "done" "$rd"' "$(cat "$rd" 2>&1)"
: > "$log"
EVAL_STUB_ACTIONS=crash,crash,crash suite --config-dir "$tmp/cfg" --task ledger --arm none --runs 3 --ceiling 3 --out "$tmp/g"
check "a session that reports no cost is charged its budget: US\$2, then US\$1, then no third run" \
  '[ "$(rc)" = 3 ] && [ "$(sessions)" = 2 ] && grep -q "^session run=ledger-none-2 .* budget=1.0000 " "$log" && [ -e "$tmp/g/runs/ledger-none-1/cost-unknown.txt" ] && grep -q "Model cost: \$3.00" "$tmp/out.txt" && grep -q "without a result (a timeout or a crash): 2;" "$tmp/out.txt"' "$(cat "$tmp/out.txt"; grep '^session' "$log")"
: > "$log"
suite --config-dir "$tmp/cfg" --task ledger --arm none --runs 1 --ceiling 0 --out "$tmp/d"
check "a ceiling of 0 starts no run (exit 3)" '[ "$(rc)" = 3 ] && [ "$(sessions)" = 0 ]' "$(cat "$tmp/out.txt")"

# --- with no --config-dir: a temporary one, plinth installed from this checkout, deleted at exit
made() { sed -nE 's/^claude plugin cfg=([^ ]+) args=plugin install .*/\1/p' "$log" | head -1; }
: > "$log"
TMPDIR="$tmp" suite --task ledger --arm none --runs 1 --ceiling 0 --out "$tmp/e"
check "with no --config-dir, plinth is installed from this checkout into a new directory" \
  'grep -q "^claude plugin cfg=$tmp/plinth-eval-config\.[^ ]* args=plugin marketplace add $root\$" "$log" && [ -n "$(made)" ]' "$(cat "$log" "$tmp/out.txt")"
check "that directory is deleted when the suite ends" '[ -n "$(made)" ] && [ ! -e "$(made)" ]'
: > "$log"
TMPDIR="$tmp" EVAL_STUB_INSTALL_FAILS=1 suite --task ledger --arm none --runs 1 --out "$tmp/f"
gone="$(sed -nE 's/^claude plugin cfg=([^ ]+) .*/\1/p' "$log" | head -1)"
check "and when the install fails, before any run" \
  '[ "$(rc)" != 0 ] && [ -n "$gone" ] && [ ! -e "$gone" ] && [ "$(sessions)" = 0 ]' "$(cat "$log" "$tmp/out.txt")"

echo "  $pass passed, $fail failed"
[ "$fail" = 0 ]
