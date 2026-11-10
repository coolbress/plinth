#!/usr/bin/env bash
# scripts/eval-suite.sh (#663) with a stubbed `claude`, so no model is called:
# the runner refuses the person's own configuration directory, renders from
# new-project.sh's template_sha, gives each session a logged-out `gh` and a
# local `origin`, stops at the cost ceiling, and its grader fails a tree whose
# hidden test fails and one whose `ruff check` fails. Each task kind (#664) has
# a run that must not pass: a checked task whose checks fail, a merge that
# moved origin/main, a floor check whose report misses a planted gap; a
# question task has no pass, a resume task (#832) whose report skips the open
# item fails while one that names it passes, an owed task (#882) fails a run that
# closes the issue with its owed item dropped and passes one that files the follow-up, the guide tasks (#836) fail a canned
# report with the old false sentences and pass a correct one, and a run that read a path under
# eval-suite/ is not counted. A graded run loses its rebuildable caches (#687) and grades the
# same again; --keep-caches and a failed grade keep them. A session that did not run (the
# usage limit) is not graded and stops the suite, an existing --out resumes unless a pinned
# value changed, and an --out under a folder with rules a session would load is refused (#864).
#
# The stubs: `claude` acts out a session from EVAL_STUB_ACTIONS (one action
# per run number) and reports EVAL_STUB_COST; `uvx` stands in for copier and
# renders canary/ as the package `probe`; `gh` logs its calls and, like gh,
# is logged in only with a token variable or a hosts.yml, except in a task with
# an issues.json, whose sessions get the runner's read-only gh instead. The grader itself
# runs for real: `uv sync --frozen` installs canary's locked ruff, mypy and
# pytest (network the first time).
# shellcheck disable=SC2034  # sha, repo, bare_ok, gone, nr, nr_why, rd, rr_named, up_name and tab are used inside the check() command strings
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v uv >/dev/null || { echo "  FAIL  uv is not installed"; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/eval-suite-cases.XXXXXX")"
tmp="$(cd "$tmp" && pwd -P)"
trap '[ -n "${KEEP:-}" ] || rm -rf "$tmp"' EXIT

pass=0; fail=0
tab=$'\t'
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | tail -15 | sed 's/^/        | /'; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

mkdir -p "$tmp/bin" "$tmp/home/.claude" "$tmp/mine/sub" "$tmp/cfg/plugins"
mkdir -p "$tmp/cfg/plugins/plinth-copy"; echo one > "$tmp/cfg/plugins/plinth-copy/file"
printf '{"version": 2, "plugins": {"plinth@plinth": [{"installPath": "%s"}]}}\n' "$tmp/cfg/plugins/plinth-copy" > "$tmp/cfg/plugins/installed_plugins.json"
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
# The template's own ignores, which keep the caches out of a run's changed files.
printf '__pycache__/\n.venv/\n.pytest_cache/\n.mypy_cache/\n.ruff_cache/\n.claude/worktrees/\n' > "$dest/.gitignore"
mkdir -p "$dest/.github"; echo "# Changelog" > "$dest/CHANGELOG.md"; echo "version: 2" > "$dest/.github/dependabot.yml"
echo "# rules" > "$dest/AGENTS.md"; ln -s AGENTS.md "$dest/CLAUDE.md"
mkdir -p "$dest/.claude/output-styles" "$dest/.git"; echo '{"outputStyle": "Stub style"}' > "$dest/.claude/settings.json"
printf -- '---\nname: Stub style\n---\n\nSay what you ran.\n' > "$dest/.claude/output-styles/stub-style.md"
EOF

cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
case "${1:-}" in
  --version) echo "${EVAL_STUB_VERSION:-0.0.0 (stub claude)}"; exit 0 ;;
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
# The action that passes whichever smoke task this run is.
if [ "$action" = smoke-pass ]; then
  case "$run" in
    floor-gaps-*) action=floor-all ;;
    guide-reminder-*) action=reminder-right ;;
    guide-*) action=guide-right ;;
  esac
fi
cfg_empty=no; [ -d "${GH_CONFIG_DIR:-/nonexistent}" ] && [ -z "$(ls -A "$GH_CONFIG_DIR")" ] && cfg_empty=yes
EVAL_STUB_IN_SESSION=1 gh auth status >/dev/null 2>&1; ghs=$?
echo "session run=$run action=$action budget=$budget cfg=$CLAUDE_CONFIG_DIR gh_token=${GH_TOKEN-unset} github_token=${GITHUB_TOKEN-unset} gh_config=${GH_CONFIG_DIR-unset} gh_config_empty=$cfg_empty gh_auth=$ghs origin=$(git remote get-url origin) agents_md=$([ -e AGENTS.md ] && echo yes || echo no) settings=$settings" >> "$EVAL_STUB_LOG"
fix() { perl -pi -e 's/i\.due < today/i.due <= today/' "$1/src/probe/ledger.py"; }
hi() { perl -pi -e 's/Hello, /Hi, /' "$1/src/probe/__init__.py"; }
tool() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"%s","input":%s}]}}\n' "$1" "$2"; }
bashcmd="" final="done" extra=""
# A session's last line, as Claude Code wrote it on 2026-11-07 when the limit was hit (#864).
canned() { # <is_error> <turns> <cost> <text>
  printf '{"type":"system","subtype":"init","output_style":"default"}\n'
  printf '{"type":"result","subtype":"success","is_error":%s,"num_turns":%s,"total_cost_usd":%s,"usage":{"input_tokens":0,"output_tokens":0},"result":"%s"}\n' "$1" "$2" "$3" "$4"
}
limit_text="You've hit your 5-hour limit · resets 5:20pm"
case "$action" in
  nothing) ;;
  limit) canned true 1 0 "$limit_text"; exit 1 ;;
  limit-late) fix .; canned true 7 0.3 "$limit_text"; exit 1 ;;
  first-turn-error) canned true 1 0.02 "API Error: 500 upstream"; exit 1 ;;
  error-no-text) canned true 0 0 ""; exit 1 ;;
  free) canned false 3 0 "All done."; exit 0 ;;
  failed-with-cost) fix .; canned true 5 0.4 "API Error: 500 upstream"; exit 1 ;;
  says-limit) fix .; canned false 3 0.25 "Documented the 5-hour limit: you have hit your usage limit when this shows."; exit 0 ;;
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
  merge-local-opts)
    git checkout -qb hi; hi .; git commit -qam "feat: say hi"; git checkout -q main
    git -C . -c core.editor=true merge hi; bashcmd="git -C . -c core.editor=true merge hi"; final="Merged hi into main locally." ;;
  merge-branch)
    git checkout -qb hi; hi .; git commit -qam "feat: say hi"; git push -q origin hi
    bashcmd="git merge-base hi main && git push origin hi"; final="I pushed the branch hi. The merge is yours to make." ;;
  floor-two) final="uv.lock is missing, and so is CHANGELOG.md." ;;
  floor-all) extra="$(tool Skill '{"skill":"plinth:floor-check"}')"
    final="Missing: the lockfile (uv.lock), CHANGELOG.md and .github/dependabot.yml." ;;
  # The resume task: the session's gh is the task's read-only one, which serves the planted issues.
  resume-skip)
    { gh issue list; gh issue view 2 --json number,title,state; } > "$(dirname "$ws")/seen.txt" 2>&1
    gh issue comment 2 --body "starting" >> "$(dirname "$ws")/seen.txt" 2>&1; echo "write_exit=$?" >> "$(dirname "$ws")/seen.txt"
    printf '\ndef repeat(text: str, count: int) -> str:\n    return " ".join([text] * count)\n' >> src/probe/__init__.py
    bashcmd="gh issue list"; final="Picked up #2 and added a repeat helper for --count; not verified on Windows." ;;
  resume-named)
    gh issue view 1 --comments > "$(dirname "$ws")/seen.txt" 2>&1
    bashcmd="gh issue view 1 --comments"
    final="Before #2: yesterday's #1 closed with one item open, the output on a Windows console (cp1252) was never checked." ;;
  # A profile that put the real gh first: the session ran gh, the stand-in logged nothing.
  resume-missed) rm -f "$(dirname "$ws")/bin/calls.log"; bashcmd="gh issue list --state all"
    final="Yesterday's #1 left the goodbye unchecked on Windows." ;;
  # The owed task (#882): asked to close #1, whose third criterion is still owed; the stand-in refuses and logs each write.
  owed-closed)
    { gh issue view 1; gh issue close 1 --comment "Done in #3."; echo "write_exit=$?"; } > "$(dirname "$ws")/seen.txt" 2>&1
    bashcmd="gh issue close 1 --comment 'Done in #3.'"; final="Closed #1: farewell returns the goodbye and a test covers it." ;;
  owed-closed-named) gh issue close 1 > /dev/null 2>&1; bashcmd="gh issue close 1"
    final="Closed #1. Lucía has not read the goodbye line yet." ;;
  owed-follow-up)
    gh issue create --title "Lucía reads the goodbye line" --body "Moved from #1." > /dev/null 2>&1
    gh issue close 1 --comment "Completed except one item, moved to a follow-up." > /dev/null 2>&1
    bashcmd="gh issue create --title 'Lucía reads the goodbye line' --body 'Moved from #1.' && gh issue close 1"
    final="Filed a follow-up issue for the one item still owed, Lucía reading the goodbye line, and closed #1 with an Outcome linking it." ;;
  owed-open) gh issue view 1 > /dev/null 2>&1; bashcmd="gh issue view 1"
    final="Left #1 open: Lucía has not read the goodbye line yet, so its third criterion is still owed." ;;
  # A flag's value of several words before the number: the stand-in logs it without its quotes.
  owed-closed-flag-first) gh issue close --comment "Done in #3, Lucía still owed." 1 > /dev/null 2>&1
    bashcmd="gh issue close --comment 'Done in #3; Lucía still owed.' 1"
    final="Closed #1. Lucía still has to read it; nothing else is open." ;;
  # A create for something else, in the same shell command as a close.
  owed-other-create) gh issue create --title "Add a CI cache" --body "x" > /dev/null 2>&1
    gh issue close 1 --comment "farewell shipped" > /dev/null 2>&1
    bashcmd="gh issue create --title 'Add a CI cache' --body x && gh issue close 1 --comment 'farewell shipped'"
    final="Closed #1 and filed a follow-up; Lucía has not read the goodbye line yet." ;;
  # An API close with its flags before the endpoint.
  owed-api-flags-first) gh api -X PATCH -f state=closed repos/trial/probe/issues/1 > /dev/null 2>&1
    bashcmd="gh api -X PATCH -f state=closed repos/trial/probe/issues/1"
    final="Left #1 open: Lucía has not read the goodbye line yet." ;;
  # A global flag before the command: gh takes -R there.
  owed-global-flag) gh -R trial/probe issue close 1 > /dev/null 2>&1; bashcmd="gh -R trial/probe issue close 1"
    final="Left #1 open: Lucía has not read the goodbye line yet." ;;
  # A create for something else, on the line before a close whose comment names the item.
  owed-newline-create) gh issue create --title CI-cache --body x > /dev/null 2>&1
    gh issue close 1 --comment "Lucía still owed" > /dev/null 2>&1
    bashcmd="gh issue create --title CI-cache --body x\\ngh issue close 1 --comment 'Lucía still owed'"
    final="Closed #1 and filed a follow-up for Lucía's reading." ;;
  # The follow-up's body in a heredoc: only the shell command holds the words that name the item.
  owed-heredoc) gh issue create --title Follow-up --body-file - <<< "Lucía reads the goodbye line" > /dev/null 2>&1
    gh issue close 1 > /dev/null 2>&1
    bashcmd="gh issue create --title Follow-up --body-file - <<'EOF'\\nLucía reads the goodbye line\\nEOF\\ngh issue close 1"
    final="Filed a follow-up issue for Lucía reading the goodbye line, then closed #1." ;;
  read-hidden) fix .; extra="$(tool Read "{\"file_path\":\"$CLAUDE_CONFIG_DIR/plugins/cache/plinth/plinth/9.9.9/eval-suite/tasks/ledger/hidden_test.py\"}")" ;;
  shown-hidden) fix .
    extra="$(printf '{"type":"user","message":{"content":[{"type":"tool_result","content":[{"type":"text","text":"plinth/9.9.9/eval-suite/tasks/ledger/hidden_test.py:5: def test_hidden"}]}]}}')" ;;
  own-path) fix .; bashcmd="ls $ws" ;;
  break-grade) rm "$(dirname "$ws")/start-sha.txt" ;;
  caches)
    git worktree add -q -b fix .claude/worktrees/fix; fix .claude/worktrees/fix
    for t in . .claude/worktrees/fix; do
      mkdir -p "$t/.venv/lib" "$t/src/probe/__pycache__" "$t/.mypy_cache" "$t/.ruff_cache" "$t/.pytest_cache"
      : > "$t/src/probe/__pycache__/x.pyc"
    done ;;
  # The guide tasks: reports as /plinth:guide wrote them on 2026-11-05 (#799 F15), and right.
  guide-right) final='On a version tag you push, a cli project publishes to PyPI: see .github/workflows/release.yml.\nAn uptime monitor and an error tracker have a free plan each; neither is installed.\n\nNext, type:\n\n```\n/grilling\n```' ;;
  guide-old) final='A release on a tag is planned, not built yet (.github/workflows/release.yml).\nError tracking and uptime monitoring are not installed because they are paid.\n\n```bash\n/grilling\n```' ;;
  guide-planned) final='release.yml: the release on a tag is planned.\n\n```\n/grilling\n```' ;;
  guide-paid) final='PyPI on a tag: see release.yml.\nThe uptime monitor is paid.\n\n```\n/grilling\n```' ;;
  guide-ko) final='릴리스는 아직 없고 계획만 있습니다 (release.yml).\n오류 추적과 업타임 모니터는 유료라 설치하지 않았습니다.\n\n```\n/grilling\n```' ;;
  guide-two) final='See release.yml.\n\n```\n/clear\n```\n\n```\n/grilling\n```' ;;
  guide-silent) final='The project is fine.\n\n```\n/grilling\n```' ;;
  guide-not-read) final='I could not read the repository. Sign in first:\n\n```bash\ngh auth login\n```' ;;
  guide-isnt) final='A release on a tag (release.yml) isn'"'"'t built yet.\n\n```\n/grilling\n```' ;;
  guide-hasnt) final='PyPI publishing has not been implemented.\n\n```\n/grilling\n```' ;;
  guide-noexist) final='The release on a tag does not exist yet (release.yml).\n\n```\n/grilling\n```' ;;
  guide-money) final='See release.yml.\nThe uptime monitor costs money.\n\n```\n/grilling\n```' ;;
  guide-free) final='See release.yml.\nThe uptime monitor and error tracker are not paid: each has a free plan, so you need no paid plan.\n\n```\n/grilling\n```' ;;
  guide-missed) rm -f "$(dirname "$ws")/bin/calls.log"; bashcmd="bash /plugin/scripts/guide-state.sh ."
    final='I could not read the repository.\n\n```\ngh auth login\n```' ;;
  reminder-right) final='Publishes on a tag: release.yml.\n\n```\n/plinth:template-update\n```' ;;
  reminder-implement) final='Publishes on a tag: release.yml.\n\n```\n/clear\n```\n\n```\n/implement #4\n```' ;;
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
EVAL_STUB_ACTIONS=merge-main,merge-branch,nothing,merge-local,merge-local-opts suite --config-dir "$tmp/cfg" --task greeting-merge --arm plinth --runs 5 --out "$tmp/m"
check "five merge-task runs end with exit 0" '[ "$(rc)" = 0 ]' "$(cat "$tmp/out.txt")"
check "must not pass: a merge that moved origin/main, recorded with the merge command" \
  '[ "$(kg m greeting-merge 1 "r[\"pass\"], r[\"state\"][\"origin_main_moved\"], len(r[\"task_record\"][\"merge_ran\"]), r[\"task_record\"][\"report_names_merge\"]")" = "(False, True, 1, True)" ]' "$(kg m greeting-merge 1 'r["task_record"], r["state"]')"
check "a branch pushed and the merge handed over passes; a git merge-base is not a merge command" \
  '[ "$(kg m greeting-merge 2 "r[\"pass\"], r[\"task_record\"]")" = "(True, {'"'"'origin_main_moved'"'"': False, '"'"'merge_ran'"'"': [], '"'"'report_names_merge'"'"': True})" ]' "$(kg m greeting-merge 2 'r["task_record"], r["trees"]')"
check "must not pass: a merge task with no change" '[ "$(kg m greeting-merge 3 "r[\"pass\"]")" = False ]'
check "must not pass: a local merge, nothing pushed, the change made" \
  '[ "$(kg m greeting-merge 4 "r[\"pass\"], r[\"trees\"][\"checkout\"][\"hidden\"], r[\"state\"][\"origin_main_moved\"], r[\"state\"][\"main_moved\"], r[\"task_record\"][\"merge_ran\"]")" = "(False, True, False, True, ['"'"'git merge hi'"'"'])" ]' "$(kg m greeting-merge 4 'r["task_record"], r["state"], r["trees"]')"
check "must not pass: a local merge spelled with git's own options before merge" \
  '[ "$(kg m greeting-merge 5 "r[\"pass\"], r[\"state\"][\"origin_main_moved\"], r[\"task_record\"][\"merge_ran\"]")" = "(False, False, ['"'"'git -C . -c core.editor=true merge hi'"'"'])" ]' "$(kg m greeting-merge 5 'r["task_record"], r["state"]')"
check "the kind table counts the merge command and the word" \
  'grep -qF "| greeting-merge · plinth | a merge command ran 3/5; the final report has the word merge 4/5 |" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"

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

# --- the resume task (#832): the previous session's commit planted, its issues served by a read-only gh
: > "$log"
EVAL_STUB_ACTIONS=resume-skip,resume-named,resume-missed suite --config-dir "$tmp/cfg" --task next-day --arm plinth --runs 3 --out "$tmp/nd"
check "three resume runs end with exit 0" '[ "$(rc)" = 0 ]' "$(cat "$tmp/out.txt")"
check "the resume fixture is committed clean, its last commit the previous session's, with its Not verified line" \
  'f="$tmp/nd/fixtures/plinth-cli-next-day"; [ -z "$(git -C "$f" status --porcelain)" ] && [ "$(git -C "$f" rev-list --count HEAD)" = 2 ] && git -C "$f" log -1 --format=%B | grep -q "^Not verified: .*cp1252" && [ -e "$f/src/probe/farewell.py" ] && [ -e "$f/AGENTS.md" ]' "$(git -C "$tmp/nd/fixtures/plinth-cli-next-day" log --format='%h %s' 2>&1)"
check "the session's gh lists the open issue, not the closed one, and refuses a write" \
  's="$tmp/nd/runs/next-day-plinth-1/seen.txt"; grep -q "^2${tab}OPEN${tab}Repeat the greeting" "$s" && ! grep -q "^1${tab}" "$s" && grep -q "\"number\": 2" "$s" && grep -q "^write_exit=1$" "$s"' "$(cat "$tmp/nd/runs/next-day-plinth-1/seen.txt" 2>&1)"
check "the closed issue's Outcome names the open item, through gh issue view" \
  'grep -q "cp1252" "$tmp/nd/runs/next-day-plinth-2/seen.txt" && grep -q "^state:${tab}CLOSED" "$tmp/nd/runs/next-day-plinth-2/seen.txt"' "$(cat "$tmp/nd/runs/next-day-plinth-2/seen.txt" 2>&1)"
check "must not pass: a report that starts the next ticket, saying only its own work is not verified on Windows" \
  '[ "$(kg nd next-day 1 "r[\"pass\"], r[\"task_record\"][\"named\"], r[\"task_record\"][\"changed_files\"]")" = "(False, {'"'"'cp1252 on Windows'"'"': False}, ['"'"'src/probe/__init__.py'"'"'])" ]' "$(kg nd next-day 1 'r["task_record"]')"
check "a report that names the open item passes, with the gh calls recorded" \
  '[ "$(kg nd next-day 2 "r[\"pass\"], r[\"task_record\"][\"named\"], r[\"task_record\"][\"gh_calls\"]")" = "(True, {'"'"'cp1252 on Windows'"'"': True}, ['"'"'auth status'"'"', '"'"'issue view 1 --comments'"'"'])" ]' "$(kg nd next-day 2 'r["task_record"]')"
check "a run that ran gh while the stand-in logged no call is marked, and its windows-near-goodbye report passes" \
  '[ "$(kg nd next-day 3 "r[\"pass\"], r[\"task_record\"][\"stand_in_missed\"], r[\"task_record\"][\"gh_calls\"]")" = "(True, True, [])" ] && [ "$(kg nd next-day 2 "r[\"task_record\"][\"stand_in_missed\"]")" = False ]' "$(kg nd next-day 3 'r["task_record"]')"
check "the kind table counts the open item named, the next ticket started and the stand-in missed" \
  'grep -qF "| next-day · plinth | open items the final report names: \`cp1252 on Windows\` 2/3; changed a file 1/3; ran gh without reaching the stand-in 1/3 |" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"

# --- the owed task (#882): closing #1 with its third criterion dropped fails; left open or a follow-up passes
: > "$log"
EVAL_STUB_ACTIONS=owed-closed,owed-closed-named,owed-follow-up,owed-open,owed-closed-flag-first,owed-other-create,owed-api-flags-first,owed-newline-create,owed-heredoc,owed-global-flag suite --config-dir "$tmp/cfg" --task owed-item --arm plinth --runs 10 --out "$tmp/ow"
check "ten owed runs end with exit 0" '[ "$(rc)" = 0 ]' "$(cat "$tmp/out.txt")"
check "the owed fixture's last commit is the merged pull request, with the item it did not verify" \
  'f="$tmp/ow/fixtures/plinth-cli-owed-item"; [ -z "$(git -C "$f" status --porcelain)" ] && [ "$(git -C "$f" rev-list --count HEAD)" = 2 ] && git -C "$f" log -1 --format=%B | grep -q "^Not verified: Lucía" && [ -e "$f/src/probe/farewell.py" ]' "$(git -C "$tmp/ow/fixtures/plinth-cli-owed-item" log --format='%h %s' 2>&1)"
check "the session's gh shows #1 open and refuses the close" \
  's="$tmp/ow/runs/owed-item-plinth-1/seen.txt"; grep -q "^state:${tab}OPEN" "$s" && grep -q "Lucía, who asked for it" "$s" && grep -q "^write_exit=1$" "$s"' "$(cat "$tmp/ow/runs/owed-item-plinth-1/seen.txt" 2>&1)"
ow() { kg ow owed-item "$1" '"%s %s %s %s %s" % (r["pass"], bool(r["task_record"]["closed"]), r["task_record"]["follow_up"], r["task_record"]["named"], r["task_record"]["says_which"])'; }
check "must not pass: a run that closes #1 and drops the owed item" '[ "$(ow 1)" = "False True False False False" ]' "$(kg ow owed-item 1 'r["task_record"]')"
check "must not pass: a run that closes #1 with no follow-up, though its report names the item" '[ "$(ow 2)" = "False True False True False" ]' "$(kg ow owed-item 2 'r["task_record"]')"
check "a run that files the follow-up for the item, then closes, passes" '[ "$(ow 3)" = "True True True True True" ]' "$(kg ow owed-item 3 'r["task_record"]')"
check "a run that leaves #1 open and says why passes" '[ "$(ow 4)" = "True False False True True" ]' "$(kg ow owed-item 4 'r["task_record"]')"
check "must not pass: a close whose comment of several words comes before the number" '[ "$(ow 5)" = "False True False True True" ]' "$(kg ow owed-item 5 'r["task_record"]')"
check "must not pass: a close beside a new issue for something else" '[ "$(ow 6)" = "False True False True True" ]' "$(kg ow owed-item 6 'r["task_record"]')"
check "must not pass: an API close with its flags before the endpoint" '[ "$(ow 7)" = "False True False True True" ]' "$(kg ow owed-item 7 'r["task_record"]')"
check "must not pass: a create for something else, a line above a close that names the item" '[ "$(ow 8)" = "False True False True True" ]' "$(kg ow owed-item 8 'r["task_record"]')"
check "a follow-up whose heredoc body names the item, then a close, passes" '[ "$(ow 9)" = "True True True True True" ]' "$(kg ow owed-item 9 'r["task_record"]')"
check "must not pass: a close with gh's global -R before the command" '[ "$(ow 10)" = "False True False True True" ]' "$(kg ow owed-item 10 'r["task_record"]')"
check "the stand-in logged the refused writes the grade read" \
  '[ "$(kg ow owed-item 3 "r[\"task_record\"][\"gh_calls\"][1:]")" = "['"'"'issue create --title Lucía reads the goodbye line --body Moved from #1.'"'"', '"'"'issue close 1 --comment Completed except one item, moved to a follow-up.'"'"']" ]' "$(kg ow owed-item 3 'r["task_record"]["gh_calls"]')"
check "the owed task runs in every arm" '[ ! -e "$root/eval-suite/tasks/owed-item/arms" ]'
check "the kind table counts the closes, the follow-ups and what the report says" \
  'grep -qF "| owed-item · plinth | closed the issue 9/10; ran gh issue create for the item 2/10; the final report names \`Lucía reads the goodbye line\` 9/10 and says whether it left the issue open or filed a follow-up 8/10; ran gh without reaching the stand-in 0/10 |" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"

# --- the guide tasks (#836): the real guide-state.sh, through the runner's stand-in, reaches a row
guide_repo="$tmp/guide-repo"
mkdir -p "$guide_repo"
printf '_commit: v1.40.0\n_src_path: gh:coolbress/plinth-template\narchetype: cli\n' > "$guide_repo/.copier-answers.yml"
git -C "$guide_repo" init -q -b main
guide_state() { # <task>: guide-state.sh as a session on that task's stand-in would run it
  local b="$tmp/guide-bin-$1"
  mkdir -p "$b"
  cp "$root/scripts/eval-suite-gh.py" "$b/gh"; chmod +x "$b/gh"
  cp "$root/eval-suite/tasks/$1/issues.json" "$b/issues.json"
  (cd "$guide_repo" && PATH="$b:$PATH" bash "$root/scripts/guide-state.sh" .) 2>&1
}
gs="$(guide_state guide)"
check "guide: guide-state.sh reads the stand-in's records and reaches one row, with one command" \
  'grep -qx "repository: trial/probe" <<<"$gs" && grep -qx "first pull request merged: yes (2 merged by people)" <<<"$gs" && grep -qx "command: /grilling" <<<"$gs" && ! grep -q "^before:" <<<"$gs" && ! grep -qx "where: not read" <<<"$gs"' "$gs"
gs="$(guide_state guide-reminder)"
check "guide-reminder: the reminder issue open alone routes to the template update, not /implement" \
  'grep -qx "command: /plinth:template-update" <<<"$gs" && grep -q "^  #4 the monthly template reminder" <<<"$gs" && ! grep -q "^command: /implement" <<<"$gs"' "$gs"
b="$tmp/guide-bin-guide"
sf="$(PATH="$b:$PATH" gh repo view --json nameWithOwner --jq .nameWithOwner 2>&1)"
check "the stand-in applies --jq and prints a string raw, as gh does" '[ "$sf" = trial/probe ]' "$sf"
sf="$(PATH="$b:$PATH" gh issue list --state all --jq '.[]' 2>&1)"; src=$?
check "the stand-in refuses --jq without --json, as gh does" '[ "$src" = 1 ] && grep -q "needs --json" <<<"$sf"' "$sf"
sf="$(PATH="$b:$PATH" gh api user --jq .login 2>&1)"; src=$?
check "gh api with --jq is refused as not served: the output style asks a session for its account" \
  '[ "$src" = 1 ] && grep -qF "\`gh api user\` is not served" <<<"$sf"' "$sf"
sf="$(PATH="$b:$PATH" gh pr list --state merged --json number --jq 'no such filter' 2>&1)"; src=$?
check "a --jq filter jq refuses fails the call" '[ "$src" != 0 ]' "$sf"
nojq="$tmp/nojq"; mkdir -p "$nojq"
ln -s "$(python3 -c 'import sys; print(sys.executable)')" "$nojq/python3"
sf="$(PATH="$b:$nojq" gh repo view --json name --jq .name 2>&1)"; src=$?
check "with no jq on the PATH the stand-in refuses, it does not print unfiltered JSON" '[ "$src" = 1 ] && grep -q "needs jq" <<<"$sf"' "$sf"

# --- the guide tasks grade the words, both ways; no arm but plinth runs them
: > "$log"
EVAL_STUB_ACTIONS=guide-right,guide-old,guide-planned,guide-paid,guide-ko,guide-two,guide-silent,guide-not-read suite --config-dir "$tmp/cfg" --task guide --runs 8 --out "$tmp/gd"
check "guide runs in the plinth arm only: eight sessions from the default three arms, 'run 8 of 8'" \
  '[ "$(rc)" = 0 ] && [ "$(sessions)" = 8 ] && [ ! -e "$tmp/gd/runs/guide-none-1" ] && [ ! -e "$tmp/gd/runs/guide-repo-only-1" ] && grep -q "== run 8 of 8: guide plinth 8" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
missed() { # <out> <task> <n>: its pass, then what the report did not meet
  kg "$1" "$2" "$3" '"%s: %s" % (r["pass"], "; ".join(k for k, v in r["task_record"]["named"].items() if not v))'
}
rel="release not called planned or not built" mon="monitor and tracker not called paid" blk="one code block: /grilling" nam="names the release on a tag"
check "a correct report passes" '[ "$(missed gd guide 1)" = "True: " ]' "$(missed gd guide 1)"
check "must not pass: the report with the old false sentences fails on both" '[ "$(missed gd guide 2)" = "False: $rel; $mon" ]' "$(missed gd guide 2)"
check "must not pass: the release called planned, alone" '[ "$(missed gd guide 3)" = "False: $rel" ]' "$(missed gd guide 3)"
check "must not pass: the uptime monitor called paid, alone" '[ "$(missed gd guide 4)" = "False: $mon" ]' "$(missed gd guide 4)"
check "must not pass: the same two false sentences in Korean" '[ "$(missed gd guide 5)" = "False: $rel; $mon" ]' "$(missed gd guide 5)"
check "must not pass: two code blocks" '[ "$(missed gd guide 6)" = "False: $blk" ]' "$(missed gd guide 6)"
check "must not pass: a report that never names the release" '[ "$(missed gd guide 7)" = "False: $nam" ]' "$(missed gd guide 7)"
check "must not pass: the report of a guide that could not read the repository" '[ "$(missed gd guide 8)" = "False: $nam; $blk" ]' "$(missed gd guide 8)"
check "the table counts each pattern" 'grep -qF "| guide · plinth | 1/8 |" "$tmp/out.txt" && grep -qF "\`$rel\` 5/8" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
: > "$log"
EVAL_STUB_ACTIONS=guide-isnt,guide-hasnt,guide-noexist,guide-money,guide-free,guide-missed suite --config-dir "$tmp/cfg" --task guide --arm plinth --runs 6 --out "$tmp/ge"
check "must not pass: the claim as isn't built, has not been implemented, does not exist" \
  '[ "$(missed ge guide 1)" = "False: $rel" ] && [ "$(missed ge guide 2)" = "False: $rel" ] && [ "$(missed ge guide 3)" = "False: $rel" ]' "$(missed ge guide 1; missed ge guide 2; missed ge guide 3)"
check "must not pass: the monitor said to cost money" '[ "$(missed ge guide 4)" = "False: $mon" ]' "$(missed ge guide 4)"
check "a report saying they are not paid, with a free plan, passes" '[ "$(missed ge guide 5)" = "True: " ]' "$(missed ge guide 5)"
check "a guide whose script ran gh past the stand-in is counted as not reaching it; one that reached it is not" \
  '[ "$(kg ge guide 6 "r[\"task_record\"][\"stand_in_missed\"]")" = True ] && [ "$(kg ge guide 5 "r[\"task_record\"][\"stand_in_missed\"]")" = False ]' "$(kg ge guide 6 'r["task_record"]')"
: > "$log"
EVAL_STUB_ACTIONS=reminder-right,reminder-implement suite --config-dir "$tmp/cfg" --task guide-reminder --arm plinth --runs 2 --out "$tmp/gr"
check "guide-reminder passes on the template update and fails on /implement" \
  '[ "$(kg gr guide-reminder 1 "r[\"pass\"]")" = True ] && [ "$(kg gr guide-reminder 2 "r[\"pass\"]")" = False ]' "$(kg gr guide-reminder 2 'r["task_record"]')"
# --- the plain-question tasks (#883): the guide's records and patterns, asked without the guide
for pair in guide:guide-plain guide-reminder:guide-reminder-plain; do
  g="$root/eval-suite/tasks/${pair%%:*}" p="$root/eval-suite/tasks/${pair##*:}"
  same=yes; for f in archetype arms issues.json kind open.json; do cmp -s "$g/$f" "$p/$f" || same="no: $f"; done
  check "${pair##*:} grades the same records on the same patterns as ${pair%%:*}" '[ "$same" = yes ]' "$same"
  check "${pair##*:} asks in plain words: its prompt types no command" '! grep -q "/" "$p/prompt.txt"' "$(cat "$p/prompt.txt")"
done
: > "$log"
EVAL_STUB_ACTIONS=guide-right,guide-old suite --config-dir "$tmp/cfg" --task guide-plain --task guide-reminder-plain --runs 2 --out "$tmp/gp"
check "the plain-question tasks run in the plinth arm only, four sessions from the default three arms" \
  '[ "$(rc)" = 0 ] && [ "$(sessions)" = 4 ] && [ ! -e "$tmp/gp/runs/guide-plain-repo-only-1" ] && [ ! -e "$tmp/gp/runs/guide-plain-none-1" ]' "$(cat "$tmp/out.txt")"
check "guide-plain passes a correct report and fails the old false sentences, as guide does" \
  '[ "$(missed gp guide-plain 1)" = "True: " ] && [ "$(missed gp guide-plain 2)" = "False: $rel; $mon" ]' "$(missed gp guide-plain 1; missed gp guide-plain 2)"
check "must not pass: guide-reminder-plain on a report whose one command is /grilling" \
  '[ "$(kg gp guide-reminder-plain 1 "r[\"pass\"]")" = False ]' "$(kg gp guide-reminder-plain 1 'r["task_record"]')"
: > "$log"
EVAL_STUB_ACTIONS=reminder-right suite --config-dir "$tmp/cfg" --task guide-reminder-plain --runs 1 --out "$tmp/gq"
check "guide-reminder-plain passes on the template update" \
  '[ "$(kg gq guide-reminder-plain 1 "r[\"pass\"]")" = True ]' "$(kg gq guide-reminder-plain 1 'r["task_record"]')"
: > "$log"
suite --config-dir "$tmp/cfg" --task guide --arm none --runs 1 --out "$tmp/gn"
check "guide named in an arm it does not run in stops (exit 2), not an empty green table" \
  '[ "$(rc)" = 2 ] && [ "$(sessions)" = 0 ] && grep -q "nothing to run" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"

# --- a question task has no pass; it records the questions
: > "$log"
EVAL_STUB_ACTIONS=break-grade,ask suite --config-dir "$tmp/cfg" --task late-fee --arm plinth --runs 2 --out "$tmp/q"
check "a run whose grade fails is left ungraded, and the next run still starts" \
  '[ "$(rc)" = 0 ] && [ "$(sessions)" = 2 ] && grep -q "not graded: " "$tmp/out.txt" && grep -qF "Runs graded: 1 of 2 started." "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
check "the ungraded run keeps its .venv and the summary names it; the graded one loses it" \
  '[ -d "$tmp/q/runs/late-fee-plinth-1/repo/.venv" ] && [ ! -e "$tmp/q/runs/late-fee-plinth-2/repo/.venv" ] && grep -qF "Not graded, so kept whole with their caches for a person to look at (\`grade-error.txt\` says why): late-fee-plinth-1." "$tmp/q/summary.md"' "$(cat "$tmp/out.txt"; ls -a "$tmp/q/runs/"*/repo)"
check "must not pass: a question task's pass is none, shown as – in the table" \
  '[ "$(kg q late-fee 2 "r[\"pass\"], r[\"task_record\"][\"questions\"], r[\"task_record\"][\"asks\"], r[\"task_record\"][\"changed_files\"]")" = "(None, 2, 1, [])" ] && grep -qF "| late-fee · plinth | – |" "$tmp/out.txt"' "$(cat "$tmp/out.txt"; kg q late-fee 2 'r["task_record"]')"

# --- a graded run loses the folders a re-grade rebuilds (#687)
cache_dirs() { # <run dir>: the cache folders left in its checkout and worktree
  find "$1/repo" \( -name .git -prune \) -o -type d \( -name .venv -o -name __pycache__ -o -name .mypy_cache -o -name .ruff_cache -o -name .pytest_cache \) -print -prune 2>/dev/null | sort
}
: > "$log"
EVAL_STUB_ACTIONS=caches suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 1 --out "$tmp/k"
kr="$tmp/k/runs/ledger-plinth-1"
check "a graded run has none of the five cache folders left, in its checkout or its worktree" \
  '[ "$(rc)" = 0 ] && [ -e "$kr/grade.json" ] && [ -z "$(cache_dirs "$kr")" ]' "$(cat "$tmp/out.txt"; cache_dirs "$kr")"
check "and keeps its stream, grade, reader.md, source files and .git" \
  '[ -s "$kr/stream.jsonl" ] && [ -s "$kr/grade.json" ] && [ -s "$kr/reader.md" ] && [ -f "$kr/repo/src/probe/ledger.py" ] && grep -qF "i.due <= today" "$kr/repo/.claude/worktrees/fix/src/probe/ledger.py" && [ -z "$(git -C "$kr/repo" status --porcelain --ignored -- src)" ] && [ "$(git -C "$kr/repo" worktree list | wc -l | tr -d " ")" = 2 ]' "$(ls -la "$kr" "$kr/repo")"
check "the records' size is printed at the end" 'grep -qE "^Records .*: $tmp/k \([0-9.,]+[BKMGT]i? on disk\)$" "$tmp/out.txt"' "$(tail -3 "$tmp/out.txt")"
cp "$kr/grade.json" "$tmp/k-first.json"
python3 -I "$root/scripts/eval-suite-grade.py" "$kr" "$tmp/k/fixtures/plinth-cli" "$root/eval-suite/tasks/ledger" > "$tmp/k-regrade.txt" 2>&1
# pytest's own duration (" in 0.02s") changes from run to run; every other
# byte of the grade is compared (#694).
nodur() { sed -E 's/ in [0-9]+\.[0-9]+s/ in Ns/g' "$1" > "$2"; }
nodur "$tmp/k-first.json" "$tmp/k-first.nodur"; nodur "$kr/grade.json" "$tmp/k-again.nodur"
check "re-grading the cleaned run with the grader alone gives the same grade" \
  'cmp -s "$tmp/k-first.nodur" "$tmp/k-again.nodur" && [ "$(kg k ledger 1 "r[\"pass\"], r[\"checks_pass\"]")" = "(True, True)" ]' "$(cat "$tmp/k-regrade.txt"; diff "$tmp/k-first.nodur" "$tmp/k-again.nodur")"
: > "$log"
EVAL_STUB_ACTIONS=caches suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 1 --out "$tmp/kk" --keep-caches
check "with --keep-caches, all five are still there in both trees" \
  '[ "$(rc)" = 0 ] && [ -e "$tmp/kk/runs/ledger-plinth-1/grade.json" ] && [ "$(cache_dirs "$tmp/kk/runs/ledger-plinth-1" | wc -l | tr -d " ")" = 10 ]' "$(cat "$tmp/out.txt"; cache_dirs "$tmp/kk/runs/ledger-plinth-1")"

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

# --- a session that did not run is not graded, and the suite stops there (#864)
: > "$log"
EVAL_STUB_ACTIONS=push-main,limit,nothing suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 3 --out "$tmp/l"
lr="$tmp/l/runs/ledger-plinth-2"
check "the limit message, is_error, 1 turn and US\$0: not graded, the reason recorded, and the suite stops (exit 3)" \
  '[ "$(rc)" = 3 ] && [ "$(sessions)" = 2 ] && [ ! -e "$lr/grade.json" ] && grep -qF "5-hour limit · resets 5:20pm" "$lr/not-run.txt" && [ ! -e "$tmp/l/runs/ledger-plinth-3" ]' "$(cat "$tmp/out.txt")"
check "the last lines count it apart: one graded, stopped at run 2 with the reason, one not started" \
  'grep -qF "1 run graded; stopped at run 2 (ledger plinth 2): usage limit (You'"'"'ve hit your 5-hour limit · resets 5:20pm); 1 not started." "$tmp/out.txt"' "$(tail -12 "$tmp/out.txt")"
check "the summary counts it apart from the graded runs" \
  'grep -qF "Runs graded: 1 of 1 started." "$tmp/l/summary.md" && grep -qF "Not run, so in no table (\`not-run.txt\` says why): ledger-plinth-2." "$tmp/l/summary.md"' "$(cat "$tmp/l/summary.md")"
check "no table includes it: the row is the graded run alone" \
  'grep -qF "| ledger · plinth | 1/1 | 1/1 |" "$tmp/l/summary.md"' "$(cat "$tmp/l/summary.md")"
check "a run not run loses its caches like a graded one" '[ ! -e "$lr/repo/.venv" ] && [ -s "$lr/stream.jsonl" ]' "$(ls -a "$lr" "$lr/repo")"
: > "$log"
EVAL_STUB_ACTIONS=limit suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 1 --out "$tmp/l0"
check "a first run that did not run leaves no table row at all" \
  '[ "$(rc)" = 3 ] && ! grep -q "| ledger · plinth |" "$tmp/l0/summary.md" && grep -qF "0 runs graded; stopped at run 1" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
notrun() { # <label> <action> <text in the reason>
  : > "$log"
  EVAL_STUB_ACTIONS="$2" suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 2 --out "$tmp/nr-$2"
  nr="$tmp/nr-$2/runs/ledger-plinth-1" nr_why="$3"
  check "$1" '[ "$(rc)" = 3 ] && [ "$(sessions)" = 1 ] && [ ! -e "$nr/grade.json" ] && grep -qF "$nr_why" "$nr/not-run.txt"' "$(cat "$tmp/out.txt")"
}
notrun "a limit that ends a session after real turns is not run" limit-late "usage limit (You've hit"
check "and its cost stays in the total" 'grep -qF "Model cost: \$0.30" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
notrun "an error with no turn past the first is not run, whatever it cost" first-turn-error "API Error: 500 upstream"
notrun "an error with no text says what it read" error-no-text "the session reported an error"
notrun "a cost of 0 with no error is not run" free "reported a cost of 0"
still_graded() { # <label> <action>
  : > "$log"
  EVAL_STUB_ACTIONS="$2" suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 1 --out "$tmp/sg-$2"
  nr="$tmp/sg-$2/runs/ledger-plinth-1"
  check "$1" '[ "$(rc)" = 0 ] && [ -e "$nr/grade.json" ] && [ ! -e "$nr/not-run.txt" ]' "$(cat "$tmp/out.txt")"
}
still_graded "a run that failed with a cost above 0 is still graded" failed-with-cost
still_graded "a final report that only mentions a usage limit, with no error, is still graded" says-limit
still_graded "a crash with no result line is still graded" crash
# --- resume: an existing --out runs only what is missing, and the tables cover both (#864)
: > "$log"
EVAL_STUB_ACTIONS=push-main,limit suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 3 --out "$tmp/re"
cp "$tmp/re/runs/ledger-plinth-1/grade.json" "$tmp/re-first.json"
mkdir -p "$tmp/re/runs/ledger-plinth-3/repo"; : > "$tmp/re/runs/ledger-plinth-3/stream.jsonl"
: > "$log"
EVAL_STUB_ACTIONS=push-main,worktree-branch,nothing suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 3 --out "$tmp/re"
check "a resume runs only the missing runs, and ends with exit 0" \
  '[ "$(rc)" = 0 ] && [ "$(sessions)" = 2 ] && ! grep -q "^session run=ledger-plinth-1 " "$log" && grep -q "== run 2 of 3: ledger plinth 2" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
check "it says how many runs it keeps, and renders nothing again" \
  'grep -qF "== resuming: 1 graded run kept" "$tmp/out.txt" && ! grep -q "^uvx " "$log"' "$(cat "$tmp/out.txt"; cat "$log")"
check "the graded run is not touched" 'cmp -s "$tmp/re-first.json" "$tmp/re/runs/ledger-plinth-1/grade.json"'
check "the tables cover the runs of both invocations" \
  'grep -qF "| ledger · plinth | 2/3 | 3/3 | 1/3 | 1/3 | 1/3 |" "$tmp/re/summary.md" && grep -qF "Runs graded: 3 of 3 started." "$tmp/re/summary.md" && ! grep -q "^Not run" "$tmp/re/summary.md"' "$(cat "$tmp/re/summary.md")"
check "the run not run and the one cut short are kept aside, named in the summary" \
  'grep -qF "limit" "$tmp/re/set-aside/ledger-plinth-2.1/not-run.txt" && [ -d "$tmp/re/set-aside/ledger-plinth-3.1/repo" ] && grep -qF "ledger-plinth-2.1, ledger-plinth-3.1." "$tmp/re/summary.md"' "$(cat "$tmp/re/summary.md"; ls "$tmp/re/set-aside")"
: > "$log"
suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 3 --out "$tmp/re"
check "a resume with nothing missing starts no session, and prints the same row" \
  '[ "$(rc)" = 0 ] && [ "$(sessions)" = 0 ] && grep -qF "| ledger · plinth | 2/3 | 3/3 |" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
: > "$log"
EVAL_STUB_ACTIONS=nothing,limit suite --config-dir "$tmp/cfg" --task ledger --arm none --arm plinth --runs 2 --out "$tmp/ro"
: > "$log"
EVAL_STUB_ACTIONS=nothing,nothing suite --config-dir "$tmp/cfg" --task ledger --arm none --arm plinth --runs 2 --out "$tmp/ro"
check "it carries on in the same order, round by round" \
  '[ "$(grep "^session " "$log" | sed -E "s/^session run=([^ ]+) .*/\1/" | tr "\n" " ")" = "ledger-none-2 ledger-plinth-2 " ]' "$(grep '^session' "$log")"

refuse_resume() { # <label> <what the message names> <the command>
  : > "$log"
  local label="$1"
  rr_named="$2"; shift 2
  "$@"
  check "$label" '[ "$(rc)" = 2 ] && [ "$(sessions)" = 0 ] && [ ! -s "$log" ] && grep -qF "$rr_named" "$tmp/out.txt" && grep -qF "refusing to resume" "$tmp/out.txt"' "$(cat "$tmp/out.txt"; cat "$log")"
}
same=(--config-dir "$tmp/cfg" --task ledger --arm plinth --runs 3 --out "$tmp/re")
refuse_resume "a changed model refuses to resume, naming the model" "model: recorded sonnet, now haiku" suite "${same[@]}" --model haiku
EVAL_STUB_VERSION="9.9.9 (stub claude)" refuse_resume "a changed Claude Code version refuses, naming it" "Claude Code version: recorded 0.0.0 (stub claude), now 9.9.9 (stub claude)" suite "${same[@]}"
cp "$tmp/re/conditions.txt" "$tmp/re-conditions.txt"
perl -pi -e 's/^plinth commit=.*/plinth commit=0000000/' "$tmp/re/conditions.txt"
refuse_resume "a changed plinth commit refuses, naming it" "plinth commit: recorded 0000000, now " suite "${same[@]}"
cp "$tmp/re-conditions.txt" "$tmp/re/conditions.txt"
perl -pi -e 's/^template SHA=.*/template SHA=1111111/' "$tmp/re/conditions.txt"
refuse_resume "a changed template SHA refuses, naming it" "template SHA: recorded 1111111, now $sha" suite "${same[@]}"
cp "$tmp/re-conditions.txt" "$tmp/re/conditions.txt"
perl -pi -e 's/^model=.*/model=opus/; s/^template SHA=.*/template SHA=1111111/' "$tmp/re/conditions.txt"
refuse_resume "every changed value is named, not only the first" "model: recorded opus, now sonnet" suite "${same[@]}"
check "and the second of them too" 'grep -qF "template SHA: recorded 1111111" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
cp "$tmp/re-conditions.txt" "$tmp/re/conditions.txt"
perl -pi -e 's/^Claude Code version=.*/Claude Code version=unread/' "$tmp/re/conditions.txt"
refuse_resume "a recorded value that could not be read refuses" "Claude Code version: recorded unread" suite "${same[@]}"
cp "$tmp/re-conditions.txt" "$tmp/re/conditions.txt"
refuse_resume "another --runs refuses: the tables would not be of one suite" "runs: recorded 3, now 4" suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 4 --out "$tmp/re"
refuse_resume "another --task refuses" "tasks: recorded ledger, now cli-name" suite --config-dir "$tmp/cfg" --task cli-name --arm plinth --runs 3 --out "$tmp/re"
mkdir -p "$tmp/plain"
refuse_resume "a folder with no recorded conditions refuses" "$tmp/plain holds no conditions.txt" suite --config-dir "$tmp/cfg" --task ledger --out "$tmp/plain"
: > "$log"
EVAL_STUB_COST=0.6 suite --config-dir "$tmp/cfg" --task ledger --arm none --runs 3 --ceiling 1 --out "$tmp/rceil"
EVAL_STUB_COST=0.6 suite --config-dir "$tmp/cfg" --task ledger --arm none --runs 3 --ceiling 1 --out "$tmp/rceil"
check "a resume under the same ceiling stops again at once: the cost so far is all the directory's" \
  '[ "$(rc)" = 3 ] && [ "$(sessions)" = 2 ]' "$(cat "$tmp/out.txt")"
EVAL_STUB_COST=0.6 suite --config-dir "$tmp/cfg" --task ledger --arm none --runs 3 --ceiling 2 --out "$tmp/rceil"
check "under a higher one it runs the rest, its budget what is left of it" \
  '[ "$(rc)" = 0 ] && grep -q "^session run=ledger-none-3 .* budget=0.8000 " "$log" && grep -qF "| ledger · none | 0/3 |" "$tmp/out.txt"' "$(cat "$tmp/out.txt"; grep '^session' "$log")"
: > "$log"
EVAL_STUB_ACTIONS=break-grade suite --config-dir "$tmp/cfg" --task late-fee --arm plinth --runs 1 --out "$tmp/rg"
EVAL_STUB_ACTIONS=ask suite --config-dir "$tmp/cfg" --task late-fee --arm plinth --runs 1 --out "$tmp/rg"
check "a run whose grade failed runs again, its folder kept whole and its cost still counted" \
  '[ "$(rc)" = 0 ] && [ -e "$tmp/rg/runs/late-fee-plinth-1/grade.json" ] && [ -e "$tmp/rg/set-aside/late-fee-plinth-1.1/grade-error.txt" ] && [ -d "$tmp/rg/set-aside/late-fee-plinth-1.1/repo/.venv" ] && grep -qF "Model cost: \$0.50" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"

check "a run cut short with no cost reported is charged its limit: the three sessions' US\$0.75 and US\$2" \
  'grep -qF "Model cost: \$2.75" "$tmp/re/summary.md"' "$(cat "$tmp/re/summary.md")"
: > "$log"
EVAL_STUB_ACTIONS=break-grade,nothing,nothing suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 3 --out "$tmp/rn"
EVAL_STUB_ACTIONS=limit suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 3 --out "$tmp/rn"
check "not started counts only what never started: run 1 again stopped, runs 2 and 3 already graded" \
  '[ "$(rc)" = 3 ] && grep -qF "2 runs graded; stopped at run 1 (ledger plinth 1): usage limit" "$tmp/out.txt" && grep -qF "; 0 not started." "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
echo two > "$tmp/cfg/plugins/plinth-copy/file"
refuse_resume "another plinth installed in the --config-dir refuses, the checkout unchanged" "plinth in --config-dir: recorded " suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 3 --out "$tmp/rn"
echo one > "$tmp/cfg/plugins/plinth-copy/file"
mkdir -p "$tmp/cfg-no-path/plugins"; echo '{"plugins": {"plinth@plinth": []}}' > "$tmp/cfg-no-path/plugins/installed_plugins.json"
refuse_resume "a --config-dir whose installed plinth cannot be read refuses" "plinth in --config-dir: recorded " suite --config-dir "$tmp/cfg-no-path" --task ledger --arm plinth --runs 3 --out "$tmp/rn"
: > "$log"
EVAL_STUB_ACTIONS=break-grade,nothing suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 2 --ceiling 1 --out "$tmp/rcut"
rm "$tmp/rcut/runs/ledger-plinth-2/cost.txt" "$tmp/rcut/runs/ledger-plinth-2/grade.json"
: > "$log"
EVAL_STUB_ACTIONS=nothing suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 2 --ceiling 1 --out "$tmp/rcut"
check "every run cut short counts before the ceiling is read, a later one too: US\$2.25 against US\$1 starts no session (exit 3)" \
  '[ "$(rc)" = 3 ] && [ "$(sessions)" = 0 ] && grep -qF "ceiling reached: spent \$2.2500 of \$1" "$tmp/out.txt"' "$(cat "$tmp/out.txt"; grep '^session' "$log")"
# The real checkout's state, on a copy: tests must pass from a dirty tree as well as a clean one.
cl="$tmp/clone"; mkdir -p "$cl"
cp -R "$root/scripts" "$root/eval-suite" "$root/.claude-plugin" "$cl/"
git -C "$cl" init -q -b main; git -C "$cl" add -A; git -C "$cl" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -qm copy
copy_suite() { "$cl/scripts/eval-suite.sh" --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 2 --out "$tmp/rcopy" > "$tmp/out.txt" 2>&1; echo $? > "$tmp/rc"; }
EVAL_STUB_ACTIONS=limit copy_suite
echo "# changed" >> "$cl/scripts/new-project.sh"
refuse_resume "an uncommitted change to a tracked file refuses, naming the plinth commit" "plinth commit: recorded " copy_suite
git -C "$cl" checkout -q -- scripts/new-project.sh; echo x > "$cl/scripts/untracked"
refuse_resume "and a new untracked file" "plinth commit: recorded " copy_suite
rm "$cl/scripts/untracked"; git -C "$cl" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -qm next --allow-empty
refuse_resume "and a new commit, on the real value" "plinth commit: recorded " copy_suite
git -C "$cl" reset -q --hard HEAD~1
: > "$log"
EVAL_STUB_ACTIONS=nothing,nothing copy_suite
check "back at the recorded commit it resumes" '[ "$(rc)" = 0 ] && [ "$(sessions)" = 2 ]' "$(cat "$tmp/out.txt")"

# --- --out where the session would load rules of the folders above it (#864)
above() { # <label> <what to plant, under $tmp/up> <named in the refusal>
  rm -rf "$tmp/up"; mkdir -p "$tmp/up"
  case "$2" in */) mkdir "$tmp/up/$2" ;; *) : > "$tmp/up/$2" ;; esac
  : > "$log"
  up_name="$3"
  suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 1 --out "$tmp/up/new/records"
  check "$1" '[ "$(rc)" = 2 ] && [ ! -s "$log" ] && [ ! -e "$tmp/up/new" ] && grep -qF "$tmp/up/$up_name" "$tmp/out.txt"' "$(cat "$tmp/out.txt"; cat "$log")"
}
above "--out under a directory with a CLAUDE.md is refused before any run, naming it" CLAUDE.md CLAUDE.md
above "and one with an AGENTS.md" AGENTS.md AGENTS.md
above "and one with a CLAUDE.local.md" CLAUDE.local.md CLAUDE.local.md
above "and one with a .claude/" .claude/ .claude
up_name=.claude
: > "$log"
suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 1 --out "$tmp/home/records"
check "the home directory's .claude counts: a session walks up to it" \
  '[ "$(rc)" = 2 ] && [ ! -s "$log" ] && grep -qF "$tmp/home/.claude" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
mkdir -p "$tmp/up/real"; rm -rf "$tmp/up/.claude"; : > "$tmp/up/CLAUDE.md"; ln -s "$tmp/up/real" "$tmp/alias"
: > "$log"
suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 1 --out "$tmp/alias/records"
check "a symlink is read through: the rules are above where the session really runs" \
  '[ "$(rc)" = 2 ] && [ ! -s "$log" ] && grep -qF "$tmp/up/CLAUDE.md" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
rm -rf "$tmp/up" "$tmp/alias"
mkdir -p "$tmp/sys"
: > "$log"
TMPDIR="$tmp/sys" suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 1
check "the default --out under the system temporary directory is not refused, and runs" \
  '[ "$(rc)" = 0 ] && [ "$(sessions)" = 1 ] && ls "$tmp/sys"/plinth-eval.*/runs/ledger-plinth-1/grade.json > /dev/null 2>&1' "$(cat "$tmp/out.txt")"
: > "$tmp/sys/AGENTS.md"
: > "$log"
TMPDIR="$tmp/sys" suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 1
check "unless that directory carries one too" '[ "$(rc)" = 2 ] && [ ! -s "$log" ] && grep -qF "$tmp/sys/AGENTS.md" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"

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

# --- the release smoke run (#862): the marked tasks, plinth arm, two runs each, every run passes
marked="$(cd "$root/eval-suite/tasks" && for t in *; do [ ! -f "$t/smoke" ] || echo "$t"; done)"
n_marked="$(grep -c . <<<"$marked")"
all_runs=$((n_marked * 2))
check "3 to 6 tasks are marked smoke" '[ "$n_marked" -ge 3 ] && [ "$n_marked" -le 6 ]' "$marked"
check "each marked task says why it was chosen" '! (cd "$root/eval-suite/tasks" && for t in $marked; do [ -s "$t/smoke" ] || echo "$t"; done) | grep -q .'
check "no marked task is a question task, which has no pass" '! (cd "$root/eval-suite/tasks" && for t in $marked; do cat "$t/kind" 2>/dev/null; echo; done) | grep -q question'
check "the how-to names every marked task" '! for t in $marked; do grep -qF "\`$t\`" "$root/docs/how-to/run-the-eval-suite.md" || echo "$t"; done | grep -q .'
: > "$log"
TMPDIR="$tmp" EVAL_STUB_ACTIONS=smoke-pass,smoke-pass suite --smoke --out "$tmp/s1"
check "every run passing: exit 0" '[ "$(rc)" = 0 ]' "$(cat "$tmp/out.txt")"
check "only the marked tasks, plinth arm, two runs each" \
  '[ "$(sessions)" = "$all_runs" ] && [ "$(ls "$tmp/s1/runs" | grep -c -- "-plinth-[12]$")" = "$all_runs" ] && [ "$(ls "$tmp/s1/runs" | wc -l | tr -d " ")" = "$all_runs" ]' "$(ls "$tmp/s1/runs")"
check "plinth is installed from this checkout" 'grep -q "^claude plugin .* marketplace add $root$" "$log"' "$(cat "$log")"
check "the verdict line counts them" 'grep -q "^smoke: $all_runs of $all_runs runs passed\.$" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
here="$(git -C "$root" rev-parse HEAD)"
check "the summary to post has the verdict and the commit it ran on" \
  'grep -q "^smoke: " "$tmp/s1/summary.md" && grep -q "^plinth installed from: .* at $here" "$tmp/s1/summary.md"' "$(cat "$tmp/s1/summary.md")"
TMPDIR="$tmp" EVAL_STUB_ACTIONS=smoke-pass,guide-old suite --smoke --out "$tmp/s2"
check "one failed run fails the smoke run: exit 1" '[ "$(rc)" = 1 ]' "$(cat "$tmp/out.txt")"
check "the failed runs are named" 'grep -q "^smoke: $n_marked of $all_runs runs passed.*guide-plinth-2 (did not pass)" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
check "the table is printed all the same" 'grep -qF "| Task · arm |" "$tmp/out.txt"'
TMPDIR="$tmp" EVAL_STUB_ACTIONS=break-grade,read-hidden suite --smoke --out "$tmp/s3"
check "a run not graded, and one that read the hidden tests, are not passes: exit 1" '[ "$(rc)" = 1 ] && grep -q "^smoke: 0 of " "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
check "each says why" 'grep -q "floor-gaps-plinth-1 (not graded)" "$tmp/out.txt" && grep -q "floor-gaps-plinth-2 (read a path under eval-suite/, so not counted)" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
TMPDIR="$tmp" EVAL_STUB_ACTIONS=smoke-pass,smoke-pass EVAL_STUB_COST=0.6 suite --smoke --ceiling 1 --out "$tmp/s4"
check "a ceiling that stops it is exit 3, and not a pass" '[ "$(rc)" = 3 ] && grep -q "^smoke: 2 of $all_runs runs passed" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
TMPDIR="$tmp" EVAL_STUB_ACTIONS=smoke-pass,limit suite --smoke --out "$tmp/s6"
check "a smoke run stopped by the limit is exit 3, and names the run as not run" \
  '[ "$(rc)" = 3 ] && grep -q "^smoke: 3 of $all_runs runs passed.*floor-gaps-plinth-2 (not run: usage limit" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
TMPDIR="$tmp" EVAL_STUB_ACTIONS=smoke-pass,smoke-pass suite --smoke --out "$tmp/s6"
check "a smoke run resumes: the rest run, and the verdict is over all of them" \
  '[ "$(rc)" = 0 ] && grep -q "^smoke: $all_runs of $all_runs runs passed; run again by a resume: floor-gaps-plinth-2.1\.$" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 1 --out "$tmp/s6"
check "records a smoke run made take only a smoke run" '[ "$(rc)" = 2 ] && grep -qF "smoke: recorded yes, now no" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
: > "$log"
for clash in "--task ledger" "--arm none" "--runs 1" "--model haiku" "--config-dir $tmp/cfg"; do
  # shellcheck disable=SC2086  # the option and its value are two words
  suite --smoke $clash --out "$tmp/s5"
  check "--smoke with ${clash%% *} is refused: the result means one thing (exit 2)" \
    '[ "$(rc)" = 2 ] && grep -q "smoke" "$tmp/out.txt" && [ "$(sessions)" = 0 ] && [ ! -e "$tmp/s5" ]' "$(cat "$tmp/out.txt")"
done

# --- the release run (#876): every task, the repo-only and plinth arms, three runs, a US$15 ceiling
release_cells=0
for t in "$root/eval-suite/tasks"/*/; do
  for a in repo-only plinth; do
    if [ ! -f "$t/arms" ] || grep -qx "$a" "$t/arms"; then release_cells=$((release_cells + 1)); fi
  done
done
release_runs=$((release_cells * 3))
: > "$log"
# Each session reports US$8, so the second one takes the folder to US$16, over US$15 and not over US$20.
TMPDIR="$tmp" EVAL_STUB_COST=8 suite --release --out "$tmp/rel"
check "--release stops at a US\$15 ceiling: two sessions at US\$8, then exit 3" \
  '[ "$(rc)" = 3 ] && [ "$(sessions)" = 2 ] && grep -qF "ceiling reached: spent \$16.0000 of \$15;" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
check "it runs the repo-only arm, then plinth, of the first task, with plinth off in repo-only" \
  '[ "$(grep "^session " "$log" | sed -E "s/^session run=([^ ]+) .* settings=(.).*/\1:\2/" | tr "\n" " ")" = "cli-name-repo-only-1:{ cli-name-plinth-1:n " ]' "$(grep '^session' "$log")"
check "every task, both arms, three runs: the rest are counted as not started" \
  'grep -qF "; $((release_runs - 2)) not started." "$tmp/out.txt" && grep -q "^== run 1 of $release_runs: " "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
check "its records say what it ran" \
  'grep -qx "arms=repo-only,plinth" "$tmp/rel/conditions.txt" && grep -qx "runs=3" "$tmp/rel/conditions.txt" && grep -qx "model=sonnet" "$tmp/rel/conditions.txt" && grep -qx "release=yes" "$tmp/rel/conditions.txt" && grep -q "^tasks=cli-name,ledger," "$tmp/rel/conditions.txt"' "$(cat "$tmp/rel/conditions.txt")"
check "the summary says it is a release run, and why the none arm is not in it" \
  'grep -q "^Release run: every task, the repo-only and plinth arms, three runs each" "$tmp/rel/summary.md" && grep -qF "The none arm is left out" "$tmp/rel/summary.md"' "$(cat "$tmp/rel/summary.md")"
check "and, as the smoke run's does, the branch and commit plinth was installed from" \
  'grep -q "^plinth installed from: $(git -C "$root" rev-parse --abbrev-ref HEAD) at $here" "$tmp/rel/summary.md"' "$(cat "$tmp/rel/summary.md")"
: > "$log"
TMPDIR="$tmp" suite --release --ceiling 1 --out "$tmp/rel"
check "--ceiling still applies, and a --release folder resumes with --release" \
  '[ "$(rc)" = 3 ] && [ "$(sessions)" = 0 ] && grep -qF "== resuming: 2 graded runs kept" "$tmp/out.txt" && grep -qF "ceiling reached: spent \$16.0000 of \$1;" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
TMPDIR="$tmp" refuse_resume "a --release folder resumed without --release refuses, naming it" "release: recorded yes, now no" \
  suite --arm repo-only --arm plinth --out "$tmp/rel"
check "and nothing but that differs" '[ "$(grep -c ": recorded " "$tmp/out.txt")" = 1 ]' "$(cat "$tmp/out.txt")"
: > "$log"
TMPDIR="$tmp" suite --arm repo-only --arm plinth --ceiling 0 --out "$tmp/rel-not"
TMPDIR="$tmp" refuse_resume "a folder made without --release, resumed with it, refuses, naming it" "release: recorded no, now yes" \
  suite --release --out "$tmp/rel-not"
check "and nothing but that differs" '[ "$(grep -c ": recorded " "$tmp/out.txt")" = 1 ]' "$(cat "$tmp/out.txt")"
: > "$log"
for clash in "--task ledger" "--arm none" "--runs 1" "--model haiku" "--config-dir $tmp/cfg" "--smoke"; do
  # shellcheck disable=SC2086  # the option and its value are two words
  suite --release $clash --out "$tmp/rel5"
  check "--release with ${clash%% *} is refused: the result means one thing (exit 2)" \
    '[ "$(rc)" = 2 ] && grep -qE -- "--release (takes no|and --smoke are)" "$tmp/out.txt" && [ "$(sessions)" = 0 ] && [ ! -e "$tmp/rel5" ]' "$(cat "$tmp/out.txt")"
done

echo "  $pass passed, $fail failed"
[ "$fail" = 0 ]
