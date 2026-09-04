#!/usr/bin/env bash
# Installs plinth the way the README says and checks what arrived.
#
# Runs against a fresh Claude Code config dir unless CLAUDE_CONFIG_DIR is set, so
# it can run on a laptop without touching the real installation. Needs network:
# it clones the official marketplace and the pinned plugins. Two substitutions
# make the README's lines runnable in CI: the marketplace source is this checkout
# instead of GitHub (so a pull request tests itself), and `install` gets `-y`
# because there is no TTY.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$(mktemp -d)}"
echo "config dir: $CLAUDE_CONFIG_DIR"

# The mattpocock-skills range plinth is tested against. It cannot live in plugin.json:
# a "version" there is resolved against {name}--v* tags on mattpocock/skills, which has
# none, and install fails with no-matching-tag. The official marketplace pins a commit;
# this check turns red when that pin leaves the range.
matt_min="1.2.3"; matt_max_exclusive="2.0.0"

floor="2.1.234"
v="$(claude --version | awk '{print $1}')"
[ "$(printf '%s\n%s\n' "$floor" "$v" | sort -V | head -1)" = "$floor" ] \
  || { echo "  FAIL  claude $v is below the supported floor $floor"; exit 1; }
echo "  PASS  claude $v (floor $floor)"

claude plugin validate --strict "$root"
claude plugin validate --strict "$root/.claude-plugin/plugin.json"
claude plugin validate --strict "$root/skills"

echo "+ claude plugin marketplace add anthropics/claude-plugins-official   # the README's clean-machine line"
claude plugin marketplace add anthropics/claude-plugins-official

lines=()
while IFS= read -r l; do lines+=("$l"); done \
  < <(awk '/<!-- install-block:start -->/{p=1;next} /<!-- install-block:end -->/{p=0} p' "$root/README.md" | grep '^claude ')
[ "${#lines[@]}" = 2 ] || { echo "  FAIL  expected 2 README install lines, got ${#lines[@]}"; exit 1; }
for line in "${lines[@]}"; do
  line="${line//coolbress\/plinth/$root}"
  case "$line" in *" plugin install "*) line="$line -y" ;; esac
  echo "+ $line"
  eval "$line"
done

echo "-- claude plugin list --json"
python3 - "$(claude plugin list --json)" "$matt_min" "$matt_max_exclusive" <<'PY'
import json, sys
plugins = {p["id"]: p for p in json.loads(sys.argv[1])}
range_min, range_max = (tuple(int(x) for x in v.split(".")) for v in sys.argv[2:4])
want = ["plinth@plinth", "frontend-design@plinth", "last30days@plinth", "ponytail-skills@plinth",
        "mattpocock-skills@claude-plugins-official"]
for i, p in sorted(plugins.items()):
    print(f"  {i:45} {str(p.get('version')):12} enabled={p.get('enabled')} errors={p.get('errors', [])}")
missing = [w for w in want if w not in plugins]
bad = [i for i, p in plugins.items() if not p.get("enabled") or p.get("errors")]
if missing or bad:
    print(f"  FAIL  missing={missing} not-clean={bad}"); sys.exit(1)
print("  PASS  everything installed, enabled, no errors")
matt_version = plugins["mattpocock-skills@claude-plugins-official"]["version"]
matt_tuple = tuple(int(x) for x in matt_version.split(".")[:3])
if not (range_min <= matt_tuple < range_max):
    print(f"  FAIL  mattpocock-skills {matt_version} is outside the tested range >={sys.argv[2]} <{sys.argv[3]}"); sys.exit(1)
print(f"  PASS  mattpocock-skills {matt_version} is inside the tested range >={sys.argv[2]} <{sys.argv[3]}")
PY

expect() {  # expect <plugin> <needle>...
  local out p
  out="$(claude plugin details "$1")"
  for p in "${@:2}"; do
    grep -qF -- "$p" <<<"$out" || { echo "  FAIL  $1: expected '$p' in:"; printf '        %s\n' "$out"; return 1; }
  done
  echo "  PASS  $1: ${*:2}"
}
expect plinth@plinth "Skills (3)" "arsenal" "floor-check" "new-project" "Hooks (0)"
expect ponytail-skills@plinth "Skills (6)" "Hooks (0)"
expect frontend-design@plinth "Skills (1)"
