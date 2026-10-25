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
#
# Arms: none (the render without AGENTS.md, CLAUDE.md and .claude/, plugins
# off), repo-only (the render, plugins off), plinth (the render, plinth on).
# Tasks: the directories under eval-suite/tasks/, run in the order below.
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
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
all_tasks=(cli-name ledger about greeting-push)
all_arms=(none repo-only plinth)
per_run_cap=2
session_timeout=900

die() { echo "eval-suite: $*" >&2; exit 2; }
usage() { sed -n '9,10p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

cfg="" ceiling=10 runs=3 model=sonnet out="" tasks=() arms=()
while [ $# -gt 0 ]; do
  case "$1" in
    --config-dir) [ $# -ge 2 ] || usage; cfg="$2"; shift 2 ;;
    --ceiling)    [ $# -ge 2 ] || usage; ceiling="$2"; shift 2 ;;
    --runs)       [ $# -ge 2 ] || usage; runs="$2"; shift 2 ;;
    --task)       [ $# -ge 2 ] || usage; tasks+=("$2"); shift 2 ;;
    --arm)        [ $# -ge 2 ] || usage; arms+=("$2"); shift 2 ;;
    --model)      [ $# -ge 2 ] || usage; model="$2"; shift 2 ;;
    --out)        [ $# -ge 2 ] || usage; out="$2"; shift 2 ;;
    -h|--help)    usage ;;
    *)            die "unknown argument: $1" ;;
  esac
done
[[ "$ceiling" =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "--ceiling is an amount in US dollars, like 10 or 2.5 (got: $ceiling)"
[[ "$runs" =~ ^[1-9][0-9]*$ ]] || die "--runs is a whole number from 1 (got: $runs)"
[ "${#tasks[@]}" -gt 0 ] || tasks=("${all_tasks[@]}")
[ "${#arms[@]}" -gt 0 ] || arms=("${all_arms[@]}")
for t in "${tasks[@]}"; do [ -f "$root/eval-suite/tasks/$t/prompt.txt" ] || die "no task $t (tasks: ${all_tasks[*]})"; done
for a in "${arms[@]}"; do case " ${all_arms[*]} " in *" $a "*) ;; *) die "no arm $a (arms: ${all_arms[*]})" ;; esac; done

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

# Every pin the render needs, from the door; a missing one stops here.
pin() { sed -nE "s/^$1=\"([^\"]+)\"$/\1/p" "$root/scripts/new-project.sh"; }
template_repo="$(pin template_repo)" template_ref="$(pin template_ref)" template_sha="$(pin template_sha)"
copier_version="$(pin copier_version)" copier_newer="$(pin copier_newer)"
for v in template_repo template_ref template_sha copier_version copier_newer; do
  [ -n "${!v}" ] || die "no $v in scripts/new-project.sh"
done

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
  [ ! -e "$out" ] || die "--out $out already exists; name a new directory"
  mkdir -p "$out"
else
  out="$(mktemp -d "${TMPDIR:-/tmp}/plinth-eval.XXXXXX")"
fi
out="$(cd "$out" && pwd -P)"
mkdir -p "$out/fixtures" "$out/runs"
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
    commit_fixture "$f"
  done
done

spent() {
  set -- "$out/runs/"*/cost.txt
  [ -e "$1" ] || { echo 0; return; }
  awk '{s += $1} END {printf "%.4f", s + 0}' "$@"
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

run_one() { # <task> <arm> <n> <budget>
  local task="$1" arm="$2" n="$3" budget="$4" a fx r rc start
  a="$(tr -d '[:space:]' < "$root/eval-suite/tasks/$task/archetype")"
  fx="$out/fixtures/$([ "$arm" = none ] && echo none || echo plinth)-$a"
  r="$out/runs/$task-$arm-$n"
  mkdir -p "$r/gh"
  git init -q --bare "$r/origin.git"
  git clone -q "$fx" "$r/repo"
  git -C "$r/repo" remote set-url origin "$r/origin.git"
  git -C "$r/repo" push -q origin main
  git -C "$r/repo" config user.name trial
  git -C "$r/repo" config user.email trial@example.invalid
  (cd "$r/repo" && env -u VIRTUAL_ENV uv sync --quiet --frozen)
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
        GH_CONFIG_DIR="$r/gh" CLAUDE_CONFIG_DIR="$cfg" DISABLE_AUTOUPDATER=1 \
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
  python3 -I "$root/scripts/eval-suite-grade.py" "$r" "$fx" "$root/eval-suite/tasks/$task" | sed 's/^/   /'
}

stopped=""
total=$(( runs * ${#tasks[@]} * ${#arms[@]} ))
i=0
for n in $(seq 1 "$runs"); do
  for t in "${tasks[@]}"; do
    for a in "${arms[@]}"; do
      s="$(spent)"
      if over "$s" "$ceiling"; then
        stopped="ceiling reached: spent \$$s of \$$ceiling; not starting $t $a $n or the $(( total - i - 1 )) runs after it"
        break 3
      fi
      budget="$(awk -v c="$ceiling" -v s="$s" -v m="$per_run_cap" 'BEGIN { l = c - s; printf "%.4f", (l < m ? l : m) }')"
      i=$(( i + 1 ))
      echo "== run $i of $total: $t $a $n (budget \$$budget, spent \$$s)"
      run_one "$t" "$a" "$n" "$budget"
    done
  done
done

table="$(python3 -I "$root/scripts/eval-suite-summary.py" "$out/runs" "$(IFS=,; echo "${tasks[*]}")" "$(IFS=,; echo "${arms[*]}")")"
{
  echo "Template $template_repo@$template_ref ($template_sha), model $model, $(claude --version 2>/dev/null | head -1)."
  echo
  echo "$table"
  [ -z "$stopped" ] || { echo; echo "Stopped: $stopped."; }
} | tee "$out/summary.md"
echo
echo "Records (streams, final reports, grades): $out"
[ -z "$stopped" ] || exit 3
