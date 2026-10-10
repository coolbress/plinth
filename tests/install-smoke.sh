#!/usr/bin/env bash
# Installs plinth the way the README says and checks what arrived.
#
# Runs against a fresh Claude Code config dir unless CLAUDE_CONFIG_DIR is set, so
# it can run on a laptop without touching the real installation; the fresh one
# is removed at exit (it holds every pinned plugin, ~200 MB, and a laptop that
# ran this daily filled its disk). Set CLAUDE_CONFIG_DIR to keep one. Needs network:
# it clones the official marketplace, the pinned plugins and the latest
# release (for the upgrade path at the end). Two substitutions
# make the README's lines runnable in CI: the marketplace source is this checkout
# instead of GitHub (so a pull request tests itself), and `install` gets `-y`
# because there is no TTY.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Before removing the fresh dir, stop what still writes into it: a `claude` this
# script started, and the `git clone` under it, whose arguments name the dir.
# Left running after a TERM or HUP, they recreate it once it is gone (#345).
# Only the fresh dir: what names a caller's own dir is the caller's.
cleanup() {
  local pat
  pat="$(printf '%s' "$CLAUDE_CONFIG_DIR" | sed 's/[][\\.*^$+?(){}|]/\\&/g')(\$|[ /])"
  pkill -P $$ || true; pkill -f -- "$pat" || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -P $$ >/dev/null || pgrep -f -- "$pat" >/dev/null || break
    sleep 0.2
  done
  pkill -KILL -P $$ || true; pkill -KILL -f -- "$pat" || true
  rm -rf "$CLAUDE_CONFIG_DIR"
}
if [ -z "${CLAUDE_CONFIG_DIR:-}" ]; then
  CLAUDE_CONFIG_DIR="$(mktemp -d)"; trap cleanup EXIT; fresh=yes
fi
# claude catches Ctrl-C and ends without a signal status, so bash would go on
# to the next line; the trap runs once that claude returns and stops here.
trap 'exit 130' INT
export CLAUDE_CONFIG_DIR
echo "config dir: $CLAUDE_CONFIG_DIR"

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
# The default set is plinth plus plugin.json's dependencies, read here so the
# list below and the hook check after it follow the manifest.
deps=()
while IFS= read -r d; do deps+=("$d"); done < <(python3 - "$root/.claude-plugin/plugin.json" <<'PY'
import json, sys
for d in json.load(open(sys.argv[1]))["dependencies"]:
    print(f"{d['name']}@{d['marketplace']}" if isinstance(d, dict) else f"{d}@plinth")
PY
)
[ "${#deps[@]}" -gt 0 ] || { echo "  FAIL  no dependencies read from plugin.json"; exit 1; }

# check_list <fresh:yes|no>: what `claude plugin list` holds is plinth plus the
# dependencies, each enabled and without an error.
check_list() {
python3 - "$(claude plugin list --json)" "$1" plinth@plinth "${deps[@]}" <<'PY'
import json, sys
plugins = {p["id"]: p for p in json.loads(sys.argv[1])}
fresh, want = sys.argv[2] == "yes", sys.argv[3:]
for i, p in sorted(plugins.items()):
    print(f"  {i:45} {str(p.get('version')):12} enabled={p.get('enabled')} errors={p.get('errors', [])}")
missing = [w for w in want if w not in plugins]
bad = [i for i, p in plugins.items() if not p.get("enabled") or p.get("errors")]
# A catalog entry that is not a dependency (last30days, ponytail) arriving
# anyway would bring its hook with it, and a dependency an upgrade moved
# leaves its old copy behind. Only a configuration this run created can say
# so: a kept one may hold what its owner installed.
extra = [i for i in plugins if i not in want]
if missing or bad or (fresh and extra):
    print(f"  FAIL  missing={missing} not-clean={bad} installed-but-not-a-dependency={extra if fresh else 'not checked'}"); sys.exit(1)
print("  PASS  everything installed, enabled, no errors" + (
    ", and nothing else" if fresh
    else f"; a kept configuration, so what else it holds is not checked: {extra}"))
PY
}
check_list "${fresh:-no}"

expect() {  # expect <plugin> <needle>...
  local out p
  out="$(claude plugin details "$1")"
  for p in "${@:2}"; do
    grep -qF -- "$p" <<<"$out" || { echo "  FAIL  $1: expected '$p' in:"; printf '        %s\n' "$out"; return 1; }
  done
  echo "  PASS  $1: ${*:2}"
}
expect plinth@plinth "Skills (4)" "arsenal" "floor-check" "new-project" "template-update" "Hooks (0)"
expect ponytail-skills@plinth "Skills (1)" "ponytail-audit"
expect taste-skill@plinth "Skills (1)  design-taste-frontend" "Hooks (0)"
# 20 of the 25 skills upstream ships (#475, #477); the other five never reach a session.
leaving=(grill-me setup-matt-pocock-skills teach to-questionnaire writing-for-agents)
expect mattpocock-skills@plinth "Skills (20)" "ask-matt" "implement" "tdd" "wizard" "Hooks (0)"
not_expect() {  # not_expect <plugin> <needle>...
  local out p
  out="$(claude plugin details "$1")"
  for p in "${@:2}"; do
    ! grep -qw -- "$p" <<<"$out" || { echo "  FAIL  $1: '$p' should not be listed"; return 1; }
  done
  echo "  PASS  $1: none of ${*:2}"
}
not_expect mattpocock-skills@plinth "${leaving[@]}"
# The default set runs no hook (#354): every dependency, whatever the list
# holds, reports none once installed. This reads Claude Code's inventory of the
# installed plugin, so a hook that inventory does not list is not seen here.
for dep in "${deps[@]}"; do expect "$dep" "Hooks (0)"; done

# The upgrade path, from the latest release to this checkout, in a second
# configuration this run creates (so a kept CLAUDE_CONFIG_DIR skips it): install
# the release, move the marketplace to this checkout, `claude plugin update
# plinth@plinth`, then the one-time commands the README's upgrade paragraph
# names. A moved dependency is not installed by `update` and its old copy
# stays (measured for #477), so this is where a move that needs a command shows.
# The marketplace is a directory, read in place: the release is a shallow clone
# of its tag, then replaced by this checkout's files, its version raised so that
# `update` sees a newer one (a pull request carries the released version).
[ "${fresh:-no}" = yes ] || { echo "  INFO  upgrade path not checked: a kept configuration"; exit 0; }
upgrade_cmds=("claude plugin install plinth@plinth" "claude plugin prune")
readme_flat="$(tr -s ' \n' ' ' <"$root/README.md")"
for c in "${upgrade_cmds[@]}"; do
  grep -qF "\`$c\`" <<<"$readme_flat" || { echo "  FAIL  README's upgrade paragraph does not name \`$c\`"; exit 1; }
done
tag="$(git ls-remote --tags --refs https://github.com/coolbress/plinth.git 'v*' | sed 's|.*refs/tags/||' | sort -V | tail -1)"
[ -n "$tag" ] || { echo "  FAIL  no release tag read from github.com/coolbress/plinth"; exit 1; }
up="$CLAUDE_CONFIG_DIR/upgrade-path"
mkdir -p "$up/cfg"
git -c advice.detachedHead=false clone -q --depth 1 --branch "$tag" https://github.com/coolbress/plinth.git "$up/mkt"
rm -rf "$up/mkt/.git"
(
  export CLAUDE_CONFIG_DIR="$up/cfg"
  echo "-- upgrade path: $tag, then this checkout"
  claude plugin marketplace add anthropics/claude-plugins-official >/dev/null
  claude plugin marketplace add "$up/mkt" >/dev/null
  claude plugin install plinth@plinth -y >/dev/null
  rm -rf "$up/mkt" && mkdir "$up/mkt"
  (cd "$root" && git ls-files -z -co --exclude-standard | tar --null -T - -cf -) | tar -xf - -C "$up/mkt"
  sed -i.bak -E 's/"version": "[^"]+"/"version": "999.0.0"/' "$up/mkt/.claude-plugin/plugin.json" "$up/mkt/.claude-plugin/marketplace.json"
  echo "+ claude plugin update plinth@plinth"; claude plugin update plinth@plinth
  claude plugin list --json | python3 -c 'import json, sys
for p in json.load(sys.stdin):
    print("  INFO  after update alone: %s errors=%s" % (p["id"], p.get("errors", [])))'
  for c in "${upgrade_cmds[@]}"; do echo "+ $c -y"; read -ra cmd <<<"$c"; "${cmd[@]}" -y; done
  check_list yes
  expect mattpocock-skills@plinth "Skills (20)" "Hooks (0)"
)
