#!/usr/bin/env bash
# The #665 probe: can `claude plugin eval` run the eval suite yet? #647 found
# three blockers: (a) with `dependencies` in plugin.json the with-arm loads no
# plinth; (b) the workspace's AGENTS.md, CLAUDE.md and .claude/ load in neither
# arm; (c) on macOS the sandbox stops git and `uv run`. This runs the probe
# case (eval-suite/probe/) once per arm on plinth as committed at HEAD, its
# real plugin.json included, and prints, per blocker, held, gone or unclear
# with the Claude Code version. The rules are in scripts/eval-suite-probe.py.
#
#   scripts/eval-suite-probe.sh --config-dir DIR [--ceiling USD] [--model NAME] [--out DIR]
#
# DIR is a temporary, logged-in Claude Code configuration directory, never the
# person's own: it is refused when it is, is inside or holds ~/.claude,
# $CLAUDE_CONFIG_DIR as set when this starts, or $HOME. The run never
# publishes its report (--no-publish) and stops at --ceiling (US$1 unless
# set), passed as --max-cost-usd. Two sessions cost about US$0.10 together.
# The records (result.json, the two traces, the verdicts) go to --out; the
# plinth copy, the rendered workspace and the sandbox directories plugin eval
# keeps are deleted at exit.
#
# Exit 0: all three gone. 1: one holds. 2: one is unclear, or the run failed.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() { echo "eval-suite-probe: $*" >&2; exit 2; }
usage() { sed -n '10p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

cfg="" ceiling=1 model=sonnet out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --config-dir) [ $# -ge 2 ] || usage; cfg="$2"; shift 2 ;;
    --ceiling)    [ $# -ge 2 ] || usage; ceiling="$2"; shift 2 ;;
    --model)      [ $# -ge 2 ] || usage; model="$2"; shift 2 ;;
    --out)        [ $# -ge 2 ] || usage; out="$2"; shift 2 ;;
    -h|--help)    usage ;;
    *)            die "unknown argument: $1" ;;
  esac
done
[ -n "$cfg" ] || usage
[[ "$ceiling" =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "--ceiling is an amount in US dollars, like 1 or 0.5 (got: $ceiling)"
[ -d "$cfg" ] || die "--config-dir $cfg is not a directory"

home_real="$(cd "$HOME" && pwd -P)"
own=("$HOME/.claude")
[ -n "${CLAUDE_CONFIG_DIR:-}" ] && own+=("$CLAUDE_CONFIG_DIR")
d="$(cd "$cfg" && pwd -P)"
case "$home_real/" in "$d/"*) die "refusing $cfg: it is or holds your home directory, where your own configuration lives" ;; esac
for o in "${own[@]}"; do
  [ -d "$o" ] || continue
  o="$(cd "$o" && pwd -P)"
  case "$d/" in "$o/"*) die "refusing $cfg: it is your own configuration directory ($o) or inside it; pass a temporary one" ;; esac
  case "$o/" in "$d/"*) die "refusing $cfg: it holds your own configuration directory ($o); pass a temporary one" ;; esac
done
cfg="$d"

for tool in git uv uvx python3 claude tar; do
  command -v "$tool" >/dev/null || die "needs $tool on PATH"
done
export CLAUDE_CONFIG_DIR="$cfg"
claude auth status >/dev/null 2>&1 || die "not logged in in $cfg; run: CLAUDE_CONFIG_DIR='$cfg' claude auth login"

pin() { sed -nE "s/^$1=\"([^\"]+)\"$/\1/p" "$root/scripts/new-project.sh"; }
template_repo="$(pin template_repo)" template_sha="$(pin template_sha)"
copier_version="$(pin copier_version)" copier_newer="$(pin copier_newer)"
for v in template_repo template_sha copier_version copier_newer; do
  [ -n "${!v}" ] || die "no $v in scripts/new-project.sh"
done

if [ -n "$out" ]; then
  [ ! -e "$out" ] || die "--out $out already exists; name a new directory"
  mkdir -p "$out"
else
  out="$(mktemp -d "${TMPDIR:-/tmp}/plinth-probe.XXXXXX")"
fi
out="$(cd "$out" && pwd -P)"
work="$(mktemp -d "${TMPDIR:-/tmp}/plinth-probe-work.XXXXXX")"
work="$(cd "$work" && pwd -P)"

# plugin eval keeps each run's sandbox directory (--keep-temp, and on its own
# when the run wrote to home/ or tmp/), read-only with sealed parts. Only a
# directory named e-* directly under a temporary directory is deleted.
drop_kept() {
  local k parent
  for k in $( { sed -nE 's/^.*kept ([^:]+):.*$/\1/p' "$out/stderr.txt" 2>/dev/null
               python3 -I - "$out/result.json" <<'PY' 2>/dev/null
import json, os, sys
for c in json.load(open(sys.argv[1])).get("cases", []):
    for runs in c.get("arms", {}).values():
        for r in runs:
            if r.get("tracePath"):
                print(os.path.dirname(os.path.dirname(r["tracePath"])))
PY
             } | sort -u); do
    [ -d "$k" ] || continue
    parent="$(cd "$(dirname "$k")" && pwd -P)"
    case "$(basename "$k")" in e-*) ;; *) echo "   left $k: not a plugin eval sandbox directory" >&2; continue ;; esac
    case "$parent" in "$(cd "${TMPDIR:-/tmp}" && pwd -P)"|/tmp|/private/tmp) ;; *) echo "   left $k: not under a temporary directory" >&2; continue ;; esac
    chmod -R u+rwx "$k" 2>/dev/null || true
    rm -rf "$k"
  done
}
cleanup() { drop_kept; rm -rf "$work"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "== records: $out"
printf 'claude=%s model=%s plinth=%s template=%s\n' "$(claude --version 2>/dev/null | head -1)" "$model" \
  "$(git -C "$root" rev-parse HEAD)" "$template_sha" | tee "$out/cond.txt"

# The workspace: the template's cli render, as eval-suite.sh renders it, with a
# marker line no session can guess added to AGENTS.md (CLAUDE.md links to it).
echo "== render $template_repo ($template_sha) as cli"
env -u GH_TOKEN -u GITHUB_TOKEN uvx --quiet --from "copier==$copier_version" --exclude-newer "$copier_newer" \
  copier copy --defaults --quiet \
  --data "project_name=probe" --data "license=MIT" --data "archetype=cli" \
  --vcs-ref "$template_sha" "gh:$template_repo" "$work/fixture" < /dev/null
rm -rf "$work/fixture/.git"
[ -f "$work/fixture/AGENTS.md" ] && [ -f "$work/fixture/.claude/settings.json" ] \
  || die "the render has no AGENTS.md or .claude/settings.json to look for"
marker="Probe marker: plinth-probe-$(python3 -I -c 'import secrets; print(secrets.token_hex(8))')"
printf '\n%s\n' "$marker" >> "$work/fixture/AGENTS.md"
cp "$root/eval-suite/probe/probe-checks.sh" "$work/fixture/probe-checks.sh"
python3 -I - "$work/fixture/.claude/settings.json" "$marker" "$out/probe.json" <<'PY'
import json, sys
style = json.load(open(sys.argv[1])).get("outputStyle")
json.dump({"marker": sys.argv[2], "output_style": style}, open(sys.argv[3], "w"), indent=2)
PY

# The plugin under test: plinth as committed, its plugin.json unchanged, with
# the probe case under an eval directory of its own.
mkdir -p "$work/plugin"
git -C "$root" archive HEAD | tar -x -C "$work/plugin"
mkdir -p "$work/plugin/probe-evals/probe"
cp "$root/eval-suite/probe/case.yaml" "$work/plugin/probe-evals/probe/case.yaml"
sed "s|@FIXTURE@|$work/fixture|" "$root/eval-suite/probe/scaffold.sh" > "$work/plugin/probe-evals/probe/scaffold.sh"
chmod +x "$work/plugin/probe-evals/probe/scaffold.sh"

echo "== claude plugin eval (two sessions, ceiling \$$ceiling, report kept local)"
set +e
(cd "$work" && env -u GH_TOKEN -u GITHUB_TOKEN -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u CLAUDE_CODE_OAUTH_TOKEN \
  DISABLE_AUTOUPDATER=1 claude plugin eval "$work/plugin" \
  --eval-dir probe-evals --case probe --runs 1 --model "$model" \
  --allow-tools Bash --scaffold --trust-plugin --keep-temp \
  --no-publish --max-cost-usd "$ceiling" --threshold 0 \
  --json "$out/result.json" --report "$out/report.html" --output-dir "$work/results") \
  > "$out/stdout.txt" 2> "$out/stderr.txt" < /dev/null
rc=$?
set -e
echo "exit=$rc" > "$out/exit.txt"
[ -f "$out/result.json" ] || die "plugin eval wrote no result (exit $rc); see $out/stderr.txt"

python3 -I - "$out/result.json" "$out" <<'PY'
import json, shutil, sys
r = json.load(open(sys.argv[1]))
open(sys.argv[2] + "/cost.txt", "w").write(f"{r.get('costUsd', 0)}\n")
for c in r.get("cases", []):
    for arm, runs in c.get("arms", {}).items():
        for run in runs[:1]:
            try:
                shutil.copyfile(run["tracePath"], f"{sys.argv[2]}/{arm}-trace.jsonl")
            except (KeyError, OSError, TypeError) as e:
                print(f"   no {arm}-arm trace: {e}", file=sys.stderr)
PY
echo "   cost: \$$(cat "$out/cost.txt") (an API list-price estimate)"
set +e
python3 -I "$root/scripts/eval-suite-probe.py" "$out" | tee "$out/verdict.txt"
v=${PIPESTATUS[0]}
set -e
exit "$v"
