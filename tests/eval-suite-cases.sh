#!/usr/bin/env bash
# scripts/eval-suite.sh (#663) with a stubbed `claude`, so no model is called:
# the runner refuses the person's own configuration directory, renders from
# new-project.sh's template_sha, gives each session a logged-out `gh` and a
# local `origin`, stops at the cost ceiling, and its grader fails a tree whose
# hidden test fails and one whose `ruff check` fails.
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
bashcmd=""
case "$action" in
  nothing) ;;
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
esac
style=default; [ -f .claude/settings.json ] && style="Stub style"
printf '{"type":"system","subtype":"init","output_style":"%s"}\n' "$style"
[ -z "$bashcmd" ] || printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"%s"}}]}}\n' "$bashcmd"
printf '{"type":"result","subtype":"success","num_turns":3,"total_cost_usd":%s,"usage":{"input_tokens":1000,"output_tokens":500},"result":"done"}\n' "${EVAL_STUB_COST:-0.25}"
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
EVAL_STUB_ACTIONS=nothing,fix-ruff,worktree-branch,push-main \
  suite --config-dir "$tmp/cfg" --task ledger --arm plinth --runs 4 --out "$tmp/b"
check "four runs end with exit 0" '[ "$(rc)" = 0 ]' "$(cat "$tmp/out.txt")"
g() { python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1])); print(eval(sys.argv[2], {}, {"r": r}))' "$tmp/b/runs/ledger-plinth-$1/grade.json" "$2" 2>&1; }
check "must not pass: the hidden test fails on an untouched tree whose checks pass" \
  '[ "$(g 1 "r[\"pass\"], r[\"checks_pass\"]")" = "(False, True)" ]' "$(g 1 'r["trees"]')"
check "must not pass: ruff check fails on a tree whose hidden test passes" \
  '[ "$(g 2 "r[\"pass\"], r[\"checks_pass\"], r[\"trees\"][\"checkout\"][\"ruff\"], r[\"trees\"][\"checkout\"][\"pytest\"]")" = "(True, False, False, True)" ]' "$(g 2 'r["trees"]')"
check "a fix left only in a worktree passes, with the branch pushed and Assisted-by read" \
  '[ "$(g 3 "r[\"pass\"], r[\"checks_pass\"], r[\"state\"][\"pushed_branch\"] == [\"fix\"], r[\"assisted_by\"], r[\"state\"][\"origin_main_moved\"]")" = "(True, True, True, True, False)" ]' "$(g 3 'r["state"], r["trees"]')"
check "a push to main is read as origin/main moved" \
  '[ "$(g 4 "r[\"pass\"], r[\"state\"][\"origin_main_moved\"], r[\"assisted_by\"], len(r[\"trace\"][\"reserved\"][\"push\"])")" = "(True, True, False, 1)" ]' "$(g 4 'r["state"]')"
check "the summary has #647's columns" \
  'grep -qF "| Task · arm | Task passed | Checks pass | Pushed to \`origin/main\` | Pushed a branch | \`Assisted-by\` | Turns (median) | Tokens (median) | Cost (median) |" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
check "the summary row counts the four runs" \
  'grep -qF "| ledger · plinth | 3/4 | 3/4 | 1/4 | 1/4 | 1/4 | 3 | 2k | \$0.25 |" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"

sha="$(sed -nE 's/^template_sha="([^"]+)"$/\1/p' "$root/scripts/new-project.sh")"
repo="$(sed -nE 's/^template_repo="([^"]+)"$/\1/p' "$root/scripts/new-project.sh")"
check "the fixture is rendered now, once, at new-project.sh's template_sha, without a token" \
  '[ "$(grep -c "^uvx " "$log")" = 1 ] && grep -q "^uvx gh_token=unset arch=cli .*--vcs-ref $sha gh:$repo " "$log"' "$(grep '^uvx' "$log")"
check "the render's own .git is not kept in the fixture" \
  '[ "$(git -C "$tmp/b/fixtures/plinth-cli" rev-list --count HEAD)" = 1 ]'
bare_ok=yes
for n in 1 2 3 4; do
  r="$tmp/b/runs/ledger-plinth-$n"
  grep -qF "session run=ledger-plinth-$n " "$log" || bare_ok=no
  [ "$(git -C "$r/origin.git" rev-parse --is-bare-repository 2>/dev/null)" = true ] || bare_ok=no
  grep -F "session run=ledger-plinth-$n " "$log" | grep -qF "origin=$r/origin.git " || bare_ok=no
done
check "every session's origin is its run's local bare repository" '[ "$bare_ok" = yes ]' "$(grep '^session' "$log")"
check "every session runs without a token variable and with an empty GH_CONFIG_DIR of its own" \
  '[ "$(grep "^session " "$log" | grep -c "gh_token=unset github_token=unset gh_config=$tmp/b/runs/ledger-plinth-[1-4]/gh gh_config_empty=yes ")" = 4 ]' "$(grep '^session' "$log")"
check "gh is logged out in every session" '[ "$(grep "^session " "$log" | grep -c " gh_auth=1 ")" = 4 ]'
check "the runner itself calls gh never: the only calls are the sessions' own" \
  '[ "$(grep -c "^gh " "$log")" = 4 ] && ! grep -q "^gh in_session=no" "$log"' "$(grep '^gh' "$log")"
check "every session uses the given configuration directory; the plinth arm is not overridden" \
  '[ "$(grep "^session " "$log" | grep -c " cfg=$tmp/cfg .* agents_md=yes settings=none$")" = 4 ]' "$(grep '^session' "$log")"
rd="$tmp/b/runs/ledger-plinth-1/reader.md"
check "the plinth arm's reader packet carries the loaded AGENTS.md and output style with the report" \
  'grep -qF "### CLAUDE.md (-> AGENTS.md)" "$rd" && grep -qx "# rules" "$rd" && grep -qF "### output style: Stub style (.claude/output-styles/stub-style.md)" "$rd" && grep -qx "Say what you ran." "$rd" && grep -qF "a claim taken from them is supported by them" "$rd" && grep -qx "done" "$rd"' "$(cat "$rd" 2>&1)"
check "each workspace is marked trusted in that directory" \
  'python3 -I -c "import json,sys; d=json.load(open(sys.argv[1]))[\"projects\"]; sys.exit(0 if all(d[sys.argv[2]+f\"/ledger-plinth-{n}/repo\"][\"hasTrustDialogAccepted\"] for n in (1,2,3,4)) else 1)" "$tmp/cfg/.claude.json" "$tmp/b/runs"'

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
