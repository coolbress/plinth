#!/usr/bin/env bash
# Installs plinth the way the README says and checks what arrived.
#
# Runs against a fresh Claude Code config dir unless CLAUDE_CONFIG_DIR is set, so
# it can run on a laptop without touching the real installation; the fresh one
# is removed at exit (it holds every pinned plugin, ~200 MB, and a laptop that
# ran this daily filled its disk). Set CLAUDE_CONFIG_DIR to keep one. Needs network:
# it clones the official marketplace and the pinned plugins. Two substitutions
# make the README's lines runnable in CI: the marketplace source is this checkout
# instead of GitHub (so a pull request tests itself), and `install` gets `-y`
# because there is no TTY.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -z "${CLAUDE_CONFIG_DIR:-}" ]; then
  CLAUDE_CONFIG_DIR="$(mktemp -d)"; trap 'rm -rf "$CLAUDE_CONFIG_DIR"' EXIT
fi
export CLAUDE_CONFIG_DIR
echo "config dir: $CLAUDE_CONFIG_DIR"

# The mattpocock-skills range plinth is tested against. It cannot live in plugin.json:
# a "version" there is resolved against {name}--v* tags on mattpocock/skills, which has
# none, and install fails with no-matching-tag. The official marketplace pins a commit;
# this check turns red when that pin leaves the range.
matt_min="1.2.3"; matt_max_exclusive="2.0.0"

# The Claude Code floor has one source, the door's own check; the README and the
# tutorial state it. CI runs this file twice: on the stable release and on the
# floor itself, so the floor is a version the install was seen to work on.
floor="$(sed -nE 's/^claude_floor="([^"]+)"$/\1/p' "$root/scripts/new-project.sh")"
[ -n "$floor" ] || { echo "  FAIL  no claude_floor in scripts/new-project.sh"; exit 1; }
for doc in README.md docs/tutorials/getting-started.md; do
  grep -qF "$floor or newer" "$root/$doc" \
    || { echo "  FAIL  $doc does not state the floor as \"$floor or newer\""; exit 1; }
done
# e2e runs the door with one pinned release: below the floor, the door stops
# and the release gate can never pass.
e2e_v="$(sed -nE 's/^ *CLAUDE_VERSION: "([^"]+)"$/\1/p' "$root/.github/workflows/e2e.yml")"
[ "$(printf '%s\n%s\n' "$floor" "${e2e_v:-0}" | sort -V | head -1)" = "$floor" ] \
  || { echo "  FAIL  e2e.yml pins claude ${e2e_v:-?}, below the floor $floor: the door would stop"; exit 1; }
v="$(claude --version | awk '{print $1}')"
[ "$(printf '%s\n%s\n' "$floor" "$v" | sort -V | head -1)" = "$floor" ] \
  || { echo "  FAIL  claude $v is below the supported floor $floor"; exit 1; }
echo "  PASS  claude $v (floor $floor)"

# git: below this, `git checkout` segfaults in the tree-less partial clone the installer
# makes for a git-subdir source and leaves index.lock behind; the installer's retry dies on
# that lock and prints only "index.lock: File exists" (#171). Measured: 2.30.1 to 2.35.3
# crash, 2.37.0 and newer do not; 2.36 was not measured.
git_floor="2.37.0"
git_v="$(git --version | awk '{print $3}')"
[ "$(printf '%s\n%s\n' "$git_floor" "$git_v" | sort -V | head -1)" = "$git_floor" ] \
  || { echo "  FAIL  git $git_v is below $git_floor: the install would fail on a stale index.lock (#171). fix: upgrade git (macOS: brew install git)"; exit 1; }
echo "  PASS  git $git_v (floor $git_floor)"

claude plugin validate --strict "$root"
claude plugin validate --strict "$root/.claude-plugin/plugin.json"
claude plugin validate --strict "$root/skills"

# The README block, as written, into this fresh configuration: nothing is added
# first. Adding the official marketplace here once hid that the block alone
# left plinth failing to load (#282).
lines=()
while IFS= read -r l; do lines+=("$l"); done \
  < <(awk '/<!-- install-block:start -->/{p=1;next} /<!-- install-block:end -->/{p=0} p' "$root/README.md" | grep '^claude ')
[ "${#lines[@]}" = 3 ] || { echo "  FAIL  expected 3 README install lines, got ${#lines[@]}"; exit 1; }
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
want = ["plinth@plinth", "taste-skill@plinth", "last30days@plinth", "ponytail-skills@plinth",
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
expect plinth@plinth "Skills (4)" "arsenal" "floor-check" "new-project" "template-update" "Hooks (0)"
expect ponytail-skills@plinth "Skills (6)" "Hooks (0)"
expect taste-skill@plinth "Skills (13)" "Hooks (0)"
