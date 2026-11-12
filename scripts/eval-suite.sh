#!/usr/bin/env bash
# The eval suite (#663): the same beginner tasks, with and without plinth,
# through `claude -p`, each run graded afterwards; then #647's summary table.
# It runs on demand before a release that changes the rendered agent files
# (AGENTS.md, .claude/, the output style) or a default skill, never in CI: it
# spends model usage and needs a login. How to run it, and what it costs:
# docs/how-to/run-the-eval-suite.md.
#
#   scripts/eval-suite.sh [--config-dir DIR] [--ceiling USD] [--runs N]
#                         [--task NAME]... [--arm NAME]... [--model NAME] [--out DIR]
#                         [--keep-caches] [--smoke | --release]
#
# Arms: none (the render without AGENTS.md, CLAUDE.md and .claude/, plugins
# off), repo-only (the render, plugins off), plinth (the render, plinth on).
# Tasks: the directories under eval-suite/tasks/, run in the order below. A
# task's `kind` file names how it is graded (eval-suite-grade.py); a task with
# a gaps.json gets a fixture of its own, with those paths removed, and so does
# one with a previous/ folder: its files, committed on top as the squash commit
# of the merged pull request its issues.json names. A task with an issues.json
# gives its sessions a read-only gh (eval-suite-gh.py) that serves those
# records offline instead of the logged-out one, and needs jq for its --jq. A
# task with an `arms` file runs only in the arms it lists: guide and
# guide-reminder grade what /plinth:guide says, which only the plinth arm has;
# guide-plain and guide-reminder-plain ask the same in plain words, in that arm,
# so plinth without the guide is graded on the same patterns (#883).
# guide-fresh and guide-busy run the guide on a project with no merge yet and
# on one under way (#907); a task's report.json says what the grade records of
# its final report besides the pass: the tool use of the step it is at, and,
# for the busy one, the failing check and the pin behind. A task with a
# plinth_pin runs on a fixture of its own whose workflows call plinth at that
# commit, not at the template's default.
#
# The configuration directory is a temporary one, never the person's own: with
# no --config-dir one is made, plinth is installed into it from this checkout,
# the person logs in once, and it is deleted at exit. A --config-dir is kept,
# and refused when it is, is inside or holds ~/.claude, $CLAUDE_CONFIG_DIR as
# set when this starts, or $HOME.
#
# No GitHub repository is created or read by a run: each run's `origin` is a
# local bare repository, and the session gets an empty GH_CONFIG_DIR and no
# token variable, so `gh` is logged out. The fixtures are rendered here, from
# scripts/new-project.sh's template_sha, which fetches the public template.
#
# Before each run the cost so far is added up; at or over the ceiling, that run
# and the ones after it are not started, the table is printed and the exit
# status is 3. Each session's own budget is the smaller of US$2 and what is
# left, so the overrun is bounded by the run in flight. The cost is the API
# list-price estimate each session reports (`total_cost_usd`); a session that
# reports none (a timeout, a crash) is charged its whole budget.
#
# --smoke is the release smoke run (#862): the tasks with a `smoke` file (it says
# why each was chosen), the plinth arm, two runs each, on the default model, with
# plinth installed from this checkout. It takes no --task, --arm, --runs, --model
# or --config-dir (a kept folder holds whichever plinth was installed in it), so
# its result always means the same thing: exit 0 only when every one of those
# runs was graded, passed and did not read the hidden tests, 1 otherwise, 3 when
# the ceiling stopped it. Its summary names this checkout's branch and commit.
# Without --smoke the exit says nothing about what passed.
#
# --release is the run a release that must run the suite uses (#876, #647's
# Decision of 2026-11-09): every task, the repo-only and plinth arms, three runs
# each, on the default model, under a US$15 ceiling unless --ceiling names
# another. The none arm is left out: nothing a plinth or template release
# changes reaches it. Like --smoke it takes no --task, --arm, --runs, --model or
# --config-dir, and its summary says it is a release run and names this
# checkout's branch and commit; its exit is the default suite's.
#
# A session that did not really run (eval-suite-grade.py --not-run: the usage
# limit, or an error on its first turn, or a cost of 0) is not graded: it gets a
# not-run.txt with the reason it gave, is in no table, and the suite stops there,
# exit 3, as at the ceiling. A crash or a timeout is graded.
#
# An --out that exists resumes it (#864): every run with a grade.json is kept, the
# rest run in the same order, and the tables cover them all. A run there with no
# grade.json moves to set-aside/ first, its cost still counted. conditions.txt
# records what must not differ; a different value refuses, naming it. The ceiling
# is not one of them, and counts the directory's whole cost.
#
# An --out under a folder with a CLAUDE.md, CLAUDE.local.md, AGENTS.md or .claude/
# is refused before anything runs: Claude Code loads those from parent folders, so
# every arm would read them and the arms would stop differing by the rules under test.
#
# Once a run is graded, its checkout and worktrees lose the folders a re-grade
# rebuilds (the grader's CACHES: .venv and the tool caches), so the records
# stay small (#687); --keep-caches keeps them. A run whose grade failed is left
# whole for a person to look at. At the end the records' size is printed.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
all_tasks=(cli-name ledger about greeting-push notes-stats greeting-merge floor-gaps next-day owed-item guide guide-fresh guide-busy guide-reminder guide-plain guide-reminder-plain friend-311 late-fee skip-mypy)
all_arms=(none repo-only plinth)
per_run_cap=2
session_timeout=900

die() { echo "eval-suite: $*" >&2; exit 2; }
usage() { sed -n '9,11p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

cfg="" ceiling=10 runs=3 model=sonnet out="" tasks=() arms=() keep_caches="" smoke="" release="" runs_said="" model_said="" ceiling_said=""
while [ $# -gt 0 ]; do
  case "$1" in
    --config-dir) [ $# -ge 2 ] || usage; cfg="$2"; shift 2 ;;
    --ceiling)    [ $# -ge 2 ] || usage; ceiling="$2"; ceiling_said=1; shift 2 ;;
    --runs)       [ $# -ge 2 ] || usage; runs="$2"; runs_said=1; shift 2 ;;
    --task)       [ $# -ge 2 ] || usage; tasks+=("$2"); shift 2 ;;
    --arm)        [ $# -ge 2 ] || usage; arms+=("$2"); shift 2 ;;
    --model)      [ $# -ge 2 ] || usage; model="$2"; model_said=1; shift 2 ;;
    --out)        [ $# -ge 2 ] || usage; out="$2"; shift 2 ;;
    --keep-caches) keep_caches=1; shift ;;
    --smoke)      smoke=1; shift ;;
    --release)    release=1; shift ;;
    -h|--help)    usage ;;
    *)            die "unknown argument: $1" ;;
  esac
done
if [ -n "$release" ]; then
  [ -z "$smoke" ] || die "--release and --smoke are two different runs; name one"
  [ "${#tasks[@]}" = 0 ] && [ "${#arms[@]}" = 0 ] && [ -z "$runs_said" ] && [ -z "$model_said" ] && [ -z "$cfg" ] \
    || die "--release takes no --task, --arm, --runs, --model or --config-dir: it is always the same run, on plinth from this checkout"
  arms=(repo-only plinth) runs=3
  [ -n "$ceiling_said" ] || ceiling=15
fi
[[ "$ceiling" =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "--ceiling is an amount in US dollars, like 10 or 2.5 (got: $ceiling)"
[[ "$runs" =~ ^[1-9][0-9]*$ ]] || die "--runs is a whole number from 1 (got: $runs)"
if [ -n "$smoke" ]; then
  [ "${#tasks[@]}" = 0 ] && [ "${#arms[@]}" = 0 ] && [ -z "$runs_said" ] && [ -z "$model_said" ] && [ -z "$cfg" ] \
    || die "--smoke takes no --task, --arm, --runs, --model or --config-dir: it is always the same run, on plinth from this checkout"
  for t in "${all_tasks[@]}"; do [ ! -f "$root/eval-suite/tasks/$t/smoke" ] || tasks+=("$t"); done
  [ "${#tasks[@]}" -gt 0 ] || die "--smoke: no task has a smoke file"
  arms=(plinth) runs=2
fi
[ "${#tasks[@]}" -gt 0 ] || tasks=("${all_tasks[@]}")
[ "${#arms[@]}" -gt 0 ] || arms=("${all_arms[@]}")
for t in "${tasks[@]}"; do
  [ -f "$root/eval-suite/tasks/$t/prompt.txt" ] || die "no task $t (tasks: ${all_tasks[*]})"
  k="test"; [ ! -f "$root/eval-suite/tasks/$t/kind" ] || k="$(tr -d '[:space:]' < "$root/eval-suite/tasks/$t/kind")"
  case "$k" in test|checked|merge|floor-check|resume|owed|question) ;; *) die "task $t: unknown kind $k" ;; esac
done
for a in "${arms[@]}"; do case " ${all_arms[*]} " in *" $a "*) ;; *) die "no arm $a (arms: ${all_arms[*]})" ;; esac; done
# Whether a task runs in an arm: all of them, unless its `arms` file lists fewer.
task_in_arm() { # <task> <arm>
  local f="$root/eval-suite/tasks/$1/arms"
  [ ! -f "$f" ] || grep -qx "$2" "$f"
}
cells=0
for t in "${tasks[@]}"; do
  for a in "${arms[@]}"; do
    if task_in_arm "$t" "$a"; then cells=$(( cells + 1 )); fi
  done
done
[ "$cells" -gt 0 ] || die "nothing to run: no task named runs in the arms named (a task's arms file lists the arms it runs in)"

# The person's own configuration, as it is before anything here changes it.
home_real="$(cd "$HOME" && pwd -P)"
own=("$HOME/.claude")
[ -n "${CLAUDE_CONFIG_DIR:-}" ] && own+=("$CLAUDE_CONFIG_DIR")
refuse_own() { # <dir>
  local d o
  d="$(cd "$1" && pwd -P)"
  case "$home_real/" in "$d/"*) die "refusing $1: it is or holds your home directory, where your own configuration lives" ;; esac
  for o in "${own[@]}"; do
    [ -d "$o" ] || continue
    o="$(cd "$o" && pwd -P)"
    case "$d/" in "$o/"*) die "refusing $1: it is your own configuration directory ($o) or inside it; pass a temporary one" ;; esac
    case "$o/" in "$d/"*) die "refusing $1: it holds your own configuration directory ($o); pass a temporary one" ;; esac
  done
}

for tool in git uv uvx python3 perl claude; do
  command -v "$tool" >/dev/null || die "needs $tool on PATH"
done
for t in "${tasks[@]}"; do
  [ ! -f "$root/eval-suite/tasks/$t/issues.json" ] || command -v jq >/dev/null || die "task $t needs jq on PATH: its read-only gh filters with it"
done

# Every pin the render needs, from the door; a missing one stops here.
pin() { sed -nE "s/^$1=\"([^\"]+)\"$/\1/p" "$root/scripts/new-project.sh"; }
template_repo="$(pin template_repo)" template_ref="$(pin template_ref)" template_sha="$(pin template_sha)"
copier_version="$(pin copier_version)" copier_newer="$(pin copier_newer)"
for v in template_repo template_ref template_sha copier_version copier_newer; do
  [ -n "${!v}" ] || die "no $v in scripts/new-project.sh"
done

# The folders a session's Claude Code reads rules from are its workspace's parents.
# Walks the real path of the nearest folder that exists, since --out may not yet.
refuse_rules_above() { # <dir>
  local d="$1" f
  while [ ! -d "$d" ]; do d="$(dirname "$d")"; done
  d="$(cd "$d" && pwd -P)"
  while :; do
    for f in CLAUDE.md CLAUDE.local.md AGENTS.md .claude; do
      [ ! -e "$d/$f" ] && [ ! -L "$d/$f" ] \
        || die "refusing records under $d/$f: every arm's session would load it from that parent folder, so the arms would stop differing by the rules under test. Name another --out, outside it"
    done
    [ "$d" != / ] || break
    d="$(dirname "$d")"
  done
}
refuse_rules_above "${out:-${TMPDIR:-/tmp}}"

# What this suite is measuring: uncommitted changes count, by a hash of them.
plinth_state() {
  local head changes
  head="$(git -C "$root" rev-parse HEAD 2>/dev/null)" && changes="$(git -C "$root" status --porcelain 2>/dev/null)" \
    || { echo unread; return; }
  [ -n "$changes" ] || { echo "$head"; return; }
  echo "$head+uncommitted-$( { echo "$changes"; git -C "$root" diff HEAD
    git -C "$root" ls-files -o --exclude-standard -z | xargs -0 -r git -C "$root" hash-object --; } | git hash-object --stdin)"
}
# A --config-dir keeps whichever plinth is installed in it, whatever is checked out
# here, so its installed files are pinned too. No readable installed plinth: unread.
cfg_named="$cfg"  # Below, a temporary one takes its place.
installed_plinth() {
  [ -n "$cfg_named" ] || { echo "none (installed from this checkout)"; return; }
  python3 -I - "$cfg_named/plugins/installed_plugins.json" 2>/dev/null <<'PY' || echo unread
import hashlib, json, os, sys
d = json.load(open(sys.argv[1]))
h = hashlib.sha256()
for e in d.get("plugins", d)["plinth@plinth"] or sys.exit(1):
    top = e["installPath"]
    if not os.path.isdir(top):
        sys.exit(1)
    for at, dirs, files in os.walk(top):
        dirs.sort()
        for f in sorted(files):
            h.update(os.path.relpath(os.path.join(at, f), top).encode())
            h.update(open(os.path.join(at, f), "rb").read())
print(h.hexdigest())
PY
}
claude_version="$(claude --version 2>/dev/null | head -1 || true)"
conditions() {
  printf 'plinth commit=%s\n' "$(plinth_state)"
  printf 'plinth in --config-dir=%s\n' "$(installed_plinth)"
  printf 'template SHA=%s\n' "$template_sha"
  printf 'model=%s\n' "$model"
  printf 'Claude Code version=%s\n' "${claude_version:-unread}"
  printf 'tasks=%s\n' "$(IFS=,; echo "${tasks[*]}")"
  printf 'arms=%s\n' "$(IFS=,; echo "${arms[*]}")"
  printf 'runs=%s\n' "$runs"
  printf 'smoke=%s\n' "$([ -n "$smoke" ] && echo yes || echo no)"
  printf 'release=%s\n' "$([ -n "$release" ] && echo yes || echo no)"
}
resuming=""
if [ -n "$out" ] && [ -e "$out" ]; then
  [ -f "$out/conditions.txt" ] \
    || die "refusing to resume --out $out: $out holds no conditions.txt, so it is not a suite's records with its fixtures made; name a new directory"
  changed=""
  while IFS='=' read -r k v; do
    was="$(sed -n "s/^$k=//p" "$out/conditions.txt")"
    if [ "$was" != "$v" ] || [ "$v" = unread ]; then changed="$changed
  $k: recorded ${was:-nothing}, now $v"; fi
  done < <(conditions)
  [ -z "$changed" ] || die "refusing to resume $out, because a run under other values is not the same measurement:$changed
Run the original command, or name a new directory."
  resuming=1
fi

made_cfg=""
cleanup() { [ -z "$made_cfg" ] || rm -rf "$made_cfg"; }
trap cleanup EXIT
# claude catches Ctrl-C and returns; stop here instead of starting the next run.
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

if [ -n "$cfg" ]; then
  [ -d "$cfg" ] || die "--config-dir $cfg is not a directory"
  refuse_own "$cfg"
  cfg="$(cd "$cfg" && pwd -P)"
else
  cfg="$(mktemp -d "${TMPDIR:-/tmp}/plinth-eval-config.XXXXXX")"
  cfg="$(cd "$cfg" && pwd -P)"
  made_cfg="$cfg"
  refuse_own "$cfg"
  echo "== temporary configuration directory: $cfg (deleted at exit)"
  CLAUDE_CONFIG_DIR="$cfg" claude plugin marketplace add "$root"
  CLAUDE_CONFIG_DIR="$cfg" claude plugin install plinth@plinth -y
fi
export CLAUDE_CONFIG_DIR="$cfg"
if ! claude auth status >/dev/null 2>&1; then
  [ -n "$made_cfg" ] && [ -t 0 ] || die "not logged in in $cfg; run: CLAUDE_CONFIG_DIR='$cfg' claude auth login"
  echo "== log in for this run (a browser opens; the login stays in the temporary directory)"
  claude auth login
  claude auth status >/dev/null 2>&1 || die "still not logged in in $cfg"
fi
python3 -I - "$cfg/plugins/installed_plugins.json" <<'PY' || die "plinth@plinth is not installed in $cfg; run: CLAUDE_CONFIG_DIR='$cfg' claude plugin install plinth@plinth"
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if "plinth@plinth" in d.get("plugins", d) else 1)
PY
# Off in the none and repo-only arms: every plugin plinth's marketplace lists.
plugins_off="$(python3 -I - "$root/.claude-plugin/marketplace.json" <<'PY'
import json, sys
names = [p["name"] for p in json.load(open(sys.argv[1]))["plugins"]]
print(json.dumps({"enabledPlugins": {f"{n}@plinth": False for n in names}}))
PY
)"

if [ -n "$out" ]; then
  mkdir -p "$out"
else
  out="$(mktemp -d "${TMPDIR:-/tmp}/plinth-eval.XXXXXX")"
fi
out="$(cd "$out" && pwd -P)"
mkdir -p "$out/fixtures" "$out/runs" "$out/set-aside"
echo "== records: $out"

# Fixtures, rendered now from the pinned commit, the way the door renders.
needed=()
for t in "${tasks[@]}"; do
  a="$(tr -d '[:space:]' < "$root/eval-suite/tasks/$t/archetype")"
  case " ${needed[*]-} " in *" $a "*) ;; *) needed+=("$a") ;; esac
done
commit_fixture() { # <dir>
  git -C "$1" init -q -b main
  git -C "$1" add -A
  git -C "$1" -c user.name=trial -c user.email=trial@example.invalid -c commit.gpgsign=false commit -qm initial
}
# The paths a task's gaps.json removes from its fixture, one per line.
gaps() { # <task>
  local g="$root/eval-suite/tasks/$1/gaps.json"
  [ -f "$g" ] || return 0
  python3 -I -c 'import json, sys; print("\n".join(g["path"] for g in json.load(open(sys.argv[1]))))' "$g"
}
# Whether a task runs on a fixture of its own: it removes gaps, plants a previous session or pins plinth.
own_fixture() {
  [ -f "$root/eval-suite/tasks/$1/gaps.json" ] || [ -d "$root/eval-suite/tasks/$1/previous" ] \
    || [ -f "$root/eval-suite/tasks/$1/plinth_pin" ]
}
# A task's plinth_pin (#907): the plinth commit its project calls, whatever the
# template's default is, so the guide's pin line is the task's own. Every
# workflow call of coolbress/plinth at a full SHA, and the recorded plinth_sha,
# move to it; a render with no such call stops here.
pin_plinth() { # <task> <fixture>
  local f="$root/eval-suite/tasks/$1/plinth_pin" pin w
  [ -f "$f" ] || return 0
  pin="$(tr -d '[:space:]' < "$f")"
  [[ "$pin" =~ ^[0-9a-f]{40}$ ]] || die "task $1: plinth_pin is not a full commit SHA (got: $pin)"
  for w in "$2"/.github/workflows/*.yml "$2"/.github/workflows/*.yaml; do
    [ -f "$w" ] || continue
    PIN="$pin" perl -pi -e 's{(coolbress/plinth/\.github/workflows/[^\s@]+@)[0-9a-fA-F]{40}}{$1$ENV{PIN}}g' "$w"
  done
  [ ! -f "$2/.copier-answers.yml" ] || PIN="$pin" perl -pi -e 's{^plinth_sha: .*$}{plinth_sha: $ENV{PIN}}' "$2/.copier-answers.yml"
  grep -qsE "coolbress/plinth/\.github/workflows/[^[:space:]@]+@$pin" "$2"/.github/workflows/*.y*ml \
    || die "task $1: plinth_pin names $pin, but the render has no workflow that calls coolbress/plinth at a full commit SHA"
}
# The fixture a task runs on: its archetype's, or its own.
fixture_of() { # <task> <arm>
  local a
  a="$(tr -d '[:space:]' < "$root/eval-suite/tasks/$1/archetype")"
  printf '%s/fixtures/%s-%s%s' "$out" "$([ "$2" = none ] && echo none || echo plinth)" "$a" \
    "$(own_fixture "$1" && echo "-$1")"
}
# The squash commit message of the merged pull request in a task's issues.json.
merged_message() { # <task>
  python3 -I -c '
import json, sys
p = [p for p in json.load(open(sys.argv[1]))["pulls"] if p["state"] == "MERGED"][0]
print("%s (#%d)\n\n%s" % (p["title"], p["number"], p["body"]))' "$root/eval-suite/tasks/$1/issues.json"
}
make_fixtures() {
  for a in "${needed[@]}"; do
    echo "== render $template_repo@$template_ref ($template_sha) as $a"
    r="$out/fixtures/render-$a"
    env -u GH_TOKEN -u GITHUB_TOKEN uvx --quiet --from "copier==$copier_version" --exclude-newer "$copier_newer" \
      copier copy --defaults --quiet \
      --data "project_name=probe" --data "license=MIT" --data "archetype=$a" \
      --vcs-ref "$template_sha" "gh:$template_repo" "$r" < /dev/null
    rm -rf "$r/.git"
    for kind in plinth none; do
      f="$out/fixtures/$kind-$a"
      mkdir -p "$f"; cp -R "$r/." "$f"
      [ ! -d "$root/eval-suite/plant/$a" ] || cp -R "$root/eval-suite/plant/$a/." "$f"
      [ "$kind" = plinth ] || rm -rf "$f/AGENTS.md" "$f/CLAUDE.md" "$f/.claude"
    done
  done
  for t in "${tasks[@]}"; do
    a="$(tr -d '[:space:]' < "$root/eval-suite/tasks/$t/archetype")"
    own_fixture "$t" || continue
    for kind in plinth none; do
      f="$out/fixtures/$kind-$a-$t"
      mkdir -p "$f"; cp -R "$out/fixtures/$kind-$a/." "$f"
      while IFS= read -r p; do
        [ -e "$f/$p" ] || die "task $t: gaps.json names $p, which the $a render does not have"
        rm -f "$f/$p"
      done < <(gaps "$t")
      pin_plinth "$t" "$f"
      commit_fixture "$f"
      [ -d "$root/eval-suite/tasks/$t/previous" ] || continue
      cp -R "$root/eval-suite/tasks/$t/previous/." "$f"
      git -C "$f" add -A
      merged_message "$t" | git -C "$f" -c user.name=trial -c user.email=trial@example.invalid \
        -c commit.gpgsign=false commit -qF -
    done
  done
  for a in "${needed[@]}"; do
    for kind in plinth none; do commit_fixture "$out/fixtures/$kind-$a"; done
  done
}
graded_runs() { find "$out/runs" -mindepth 2 -maxdepth 2 -name grade.json | wc -l | tr -d ' '; }
# Every run folder is a run that started, in this invocation or an earlier one.
not_started() { echo "$(( total - $(find "$out/runs" -mindepth 1 -maxdepth 1 -type d | wc -l) ))"; }
plural() { [ "$1" = 1 ] && echo "$1 $2" || echo "$1 $3"; }
if [ -n "$resuming" ]; then
  echo "== resuming: $(plural "$(graded_runs)" "graded run" "graded runs") kept; the rest run in order, on the fixtures already here"
else
  make_fixtures
  # Last: a folder without this file never finished its setup, and is not resumed.
  conditions > "$out/conditions.txt"
fi

spent() {
  find "$out/runs" "$out/set-aside" -mindepth 2 -maxdepth 2 -name cost.txt -exec cat {} + \
    | awk '{s += $1} END {printf "%.4f", s + 0}'
}
over() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a >= b) }'; }

# A beginner accepts the trust dialog once; an untrusted workspace ignores the
# project's permissions.allow (#647), so every arm's workspace is trusted.
trust() { # <workspace>
  python3 -I - "$cfg/.claude.json" "$1" <<'PY'
import json, os, sys
path, ws = sys.argv[1], sys.argv[2]
d = json.load(open(path)) if os.path.exists(path) else {}
d.setdefault("projects", {}).setdefault(ws, {})["hasTrustDialogAccepted"] = True
tmp = path + ".eval-suite"
with open(tmp, "w") as f:
    json.dump(d, f, indent=2)
os.replace(tmp, path)
PY
}

drop_caches() { # <run dir>
  [ -z "$keep_caches" ] || return 0
  python3 -I "$root/scripts/eval-suite-grade.py" --drop-caches "$1" 2>> "$1/grade-error.txt" \
    | sed 's/^/   /' || echo "   caches not dropped: $(tail -1 "$1/grade-error.txt")"
}

run_one() { # <task> <arm> <n> <budget>
  local task="$1" arm="$2" n="$3" budget="$4" fx r rc start
  fx="$(fixture_of "$task" "$arm")"
  r="$out/runs/$task-$arm-$n"
  mkdir -p "$r/gh"
  # A task with records gets the read-only gh, ahead of any other on the session's PATH.
  local path="$PATH"
  if [ -f "$root/eval-suite/tasks/$task/issues.json" ]; then
    mkdir -p "$r/bin"
    cp "$root/scripts/eval-suite-gh.py" "$r/bin/gh"; chmod +x "$r/bin/gh"
    cp "$root/eval-suite/tasks/$task/issues.json" "$r/bin/issues.json"
    path="$r/bin:$PATH"
  fi
  git init -q --bare "$r/origin.git"
  git clone -q "$fx" "$r/repo"
  git -C "$r/repo" remote set-url origin "$r/origin.git"
  git -C "$r/repo" push -q origin main
  git -C "$r/repo" config user.name trial
  git -C "$r/repo" config user.email trial@example.invalid
  # A fixture whose lockfile is a planted gap starts unsynced, as a fresh clone of it would.
  [ ! -f "$r/repo/uv.lock" ] || (cd "$r/repo" && env -u VIRTUAL_ENV uv sync --quiet --frozen)
  git -C "$r/repo" rev-parse HEAD > "$r/start-sha.txt"
  trust "$r/repo"
  local settings=()
  [ "$arm" = plinth ] || settings=(--settings "$plugins_off")
  printf '%s %s %s model=%s template=%s claude=%s\n' "$task" "$arm" "$n" "$model" "$template_sha" \
    "$(claude --version 2>/dev/null | head -1)" > "$r/cond.txt"
  start=$(date +%s)
  set +e
  # perl's alarm is the timeout: `timeout` is not on a stock macOS.
  (cd "$r/repo" && printf '%s' "$(cat "$root/eval-suite/tasks/$task/prompt.txt")" \
    | env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u GITHUB_ENTERPRISE_TOKEN -u GH_HOST \
        -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u CLAUDE_CODE_OAUTH_TOKEN -u VIRTUAL_ENV \
        GH_CONFIG_DIR="$r/gh" CLAUDE_CONFIG_DIR="$cfg" DISABLE_AUTOUPDATER=1 PATH="$path" \
        perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$session_timeout" \
        claude -p --model "$model" --permission-mode auto --output-format stream-json --verbose \
        --max-budget-usd "$budget" ${settings[@]+"${settings[@]}"}) > "$r/stream.jsonl" 2> "$r/stderr.txt"
  rc=$?
  set -e
  echo "exit=$rc seconds=$(( $(date +%s) - start ))" > "$r/exit.txt"
  # A session that ended without its result line (a timeout, a crash) reported
  # no cost; it may have spent up to its budget, so that is what it is charged.
  python3 -I -c '
import json, sys
cost = None
for line in open(sys.argv[1], errors="replace"):
    try:
        m = json.loads(line)
    except ValueError:
        continue
    if isinstance(m, dict) and m.get("type") == "result":
        cost = float(m.get("total_cost_usd") or 0)
print(sys.argv[2] if cost is None else cost)
sys.exit(3 if cost is None else 0)' "$r/stream.jsonl" "$budget" > "$r/cost.txt" \
    || { echo "charged its whole budget: the session reported no cost" > "$r/cost-unknown.txt"
         echo "   no cost reported; charged the run's budget, \$$budget"; }
  echo "   $task $arm $n: $(cat "$r/exit.txt") cost=\$$(cat "$r/cost.txt")"
  python3 -I "$root/scripts/eval-suite-grade.py" --not-run "$r"
  if [ -f "$r/not-run.txt" ]; then
    echo "   not run, so not graded: $(cat "$r/not-run.txt")"
    drop_caches "$r"
    return 0
  fi
  # A grade that fails leaves the run ungraded, counted under the table; the next run still starts.
  if python3 -I "$root/scripts/eval-suite-grade.py" "$r" "$fx" "$root/eval-suite/tasks/$task" 2> "$r/grade-error.txt" \
    | sed 's/^/   /'; then
    drop_caches "$r"
  else
    echo "   not graded: $(tail -1 "$r/grade-error.txt"); its folder is kept whole"
  fi
}

# A run cut short (Ctrl-C, a closed terminal) reported no cost, so it is charged a
# run's limit: all of them now, since the ceiling read before any later run must count them.
for d in "$out/runs/"*/; do
  if [ -e "$d/stream.jsonl" ] && [ ! -e "$d/cost.txt" ]; then
    echo "$per_run_cap" > "$d/cost.txt"
    echo "charged a run's limit: the session was cut short before it reported a cost" > "$d/cost-unknown.txt"
  fi
done
# A run a resume runs again: what it left stays for a person, and its cost counted.
set_aside() { # <run dir>
  [ -e "$1" ] || return 0
  local k=1
  while [ -e "$out/set-aside/$(basename "$1").$k" ]; do k=$(( k + 1 )); done
  mv "$1" "$out/set-aside/$(basename "$1").$k"
}
stopped=""
total=$(( runs * cells ))
i=0
for n in $(seq 1 "$runs"); do
  for t in "${tasks[@]}"; do
    for a in "${arms[@]}"; do
      task_in_arm "$t" "$a" || continue
      if [ -f "$out/runs/$t-$a-$n/grade.json" ]; then i=$(( i + 1 )); continue; fi
      s="$(spent)"
      if over "$s" "$ceiling"; then
        stopped="Stopped: ceiling reached: spent \$$s of \$$ceiling; not starting $t $a $n; $(not_started) not started"
        break 3
      fi
      budget="$(awk -v c="$ceiling" -v s="$s" -v m="$per_run_cap" 'BEGIN { l = c - s; printf "%.4f", (l < m ? l : m) }')"
      i=$(( i + 1 ))
      set_aside "$out/runs/$t-$a-$n"
      echo "== run $i of $total: $t $a $n (budget \$$budget, spent \$$s)"
      run_one "$t" "$a" "$n" "$budget"
      if [ -f "$out/runs/$t-$a-$n/not-run.txt" ]; then
        stopped="$(plural "$(graded_runs)" run runs) graded; stopped at run $i ($t $a $n): $(cat "$out/runs/$t-$a-$n/not-run.txt"); $(not_started) not started"
        break 3
      fi
    done
  done
done

# Every run the smoke run asked for, passed. A run not started, not graded or
# not counted is not a pass.
smoke_verdict() {
  python3 -I - "$out/runs" "$total" <<'PY'
import json, sys
from pathlib import Path
runs, want = Path(sys.argv[1]), int(sys.argv[2])
good, bad = 0, []
for d in sorted(p for p in runs.iterdir() if p.is_dir()):
    g = d / "grade.json"
    if (d / "not-run.txt").exists():
        bad.append(f"{d.name} (not run: {(d / 'not-run.txt').read_text().strip()})")
        continue
    if not g.exists():
        bad.append(f"{d.name} (not graded)")
        continue
    r = json.loads(g.read_text())
    if r.get("suite_read"):
        bad.append(f"{d.name} (read a path under eval-suite/, so not counted)")
    elif r.get("pass") is not True:
        bad.append(f"{d.name} (did not pass)")
    else:
        good += 1
again = sorted(p.name for p in (runs.parent / "set-aside").iterdir())
print(
    f"smoke: {good} of {want} runs passed"
    + (f"; not passed: {', '.join(bad)}" if bad else "")
    + (f"; run again by a resume: {', '.join(again)}" if again else "")
    + "."
)
sys.exit(0 if good == want else 1)
PY
}
verdict="" smoke_failed=""
[ -z "$smoke" ] || verdict="$(smoke_verdict)" || smoke_failed=1
# Both release runs install plinth from this checkout; their summary names which commit.
if [ -n "$smoke$release" ]; then
  dirty=""; [ -z "$(git -C "$root" status --porcelain 2>/dev/null)" ] || dirty=", with uncommitted changes"
  verdict="${verdict:+$verdict
}plinth installed from: $(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unread) at $(git -C "$root" rev-parse HEAD 2>/dev/null || echo unread)$dirty."
fi
table="$(python3 -I "$root/scripts/eval-suite-summary.py" "$out/runs" "$(IFS=,; echo "${tasks[*]}")" "$(IFS=,; echo "${arms[*]}")")"
{
  [ -z "$release" ] || { echo "Release run: every task, the repo-only and plinth arms, three runs each, ceiling \$$ceiling. The none arm is left out: nothing a release changes reaches it (#647's Decision of 2026-11-09)."; echo; }
  echo "Template $template_repo@$template_ref ($template_sha), model $model, $(claude --version 2>/dev/null | head -1)."
  echo
  echo "$table"
  [ -z "$stopped" ] || { echo; echo "$stopped."; }
  [ -z "$verdict" ] || { echo; echo "$verdict"; }
} | tee "$out/summary.md"
echo
echo "Records (streams, final reports, grades): $out ($(du -sh "$out" | awk '{print $1}') on disk)"
if [ -n "$stopped" ]; then
  echo "To carry on (after the reset, or with a higher --ceiling): the same command with --out '$out'."
  exit 3
fi
[ -z "$smoke_failed" ] || exit 1
