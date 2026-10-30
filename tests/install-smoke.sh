#!/usr/bin/env bash
# Installs plinth the way the README says and checks what arrived.
#
# Runs against a fresh Claude Code config dir unless CLAUDE_CONFIG_DIR is set, so
# it can run on a laptop without touching the real installation; the fresh one
# is removed at exit (it holds every pinned plugin, ~200 MB, and a laptop that
# ran this daily filled its disk). Set CLAUDE_CONFIG_DIR to keep one. Needs network:
# it clones plinth's pinned plugins and the latest release (for the upgrade
# path at the end). Two substitutions
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
[ "${#lines[@]}" = 2 ] || { echo "  FAIL  expected 2 README install lines, got ${#lines[@]}"; exit 1; }
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
    print(f"  FAIL  missing={missing} not-clean={bad} not-a-dependency-or-left-behind={extra if fresh else 'not checked'}"); sys.exit(1)
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
expect plinth@plinth "Skills (5)" "arsenal" "floor-check" "guide" "new-project" "template-update" "Hooks (0)"
expect taste-skill@plinth "Skills (1)  design-taste-frontend" "Hooks (0)"
# 15 of the 27 skills upstream ships (#520, #593, #704, #714): 6 more are listed
# in mattpocock-skills-extra, and six are in neither (#475, #477, #714).
added=(to-spec to-tickets wayfinder improve-codebase-architecture handoff retro writing-for-agents)
extra=(ask-matt grill-with-docs prototype research wizard wait-what)
leaving=(grill-me setup-matt-pocock-skills teach to-questionnaire implement-spec pr
  resolving-merge-conflicts "${extra[@]}")
expect mattpocock-skills@plinth "Skills (15)" "implement" "tdd" "code-review" "triage" "grilling" "${added[@]}" "Hooks (0)"
not_expect() {  # not_expect <plugin> <skill>...: none on the details' Skills line
  local out p
  out="$(claude plugin details "$1" | grep -E '^ *Skills \(')"
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

[ "${fresh:-no}" = yes ] || { echo "  INFO  extra plugin and upgrade path not checked: a kept configuration"; exit 0; }
# On the clean install too, the six still listed arrive beside the fifteen,
# none of the seven #704 and #714 added is under both names, and
# resolving-merge-conflicts, gone upstream, is not listed (#714).
echo "+ claude plugin install mattpocock-skills-extra@plinth -y"; claude plugin install mattpocock-skills-extra@plinth -y
expect mattpocock-skills-extra@plinth "Skills (6)" "${extra[@]}" "Hooks (0)"
not_expect mattpocock-skills-extra@plinth resolving-merge-conflicts
not_expect mattpocock-skills-extra@plinth "${added[@]}"
expect mattpocock-skills@plinth "Skills (15)" "${added[@]}"

# The installed skills and the template plinth renders name the same glossary
# file (#714): mattpocock/skills v1.3.2 renamed CONTEXT.md to GLOSSARY.md, and a
# rendered project whose AGENTS.md and docs/agents/domain.md point to the old
# name would have the skills write one file and the pointers read another. The
# template files are read at the commit scripts/new-project.sh renders; the
# skills are the ones each mattpocock entry mounts, as installed above.
tsha="$(sed -nE 's/^template_sha="([0-9a-f]{40})"$/\1/p' "$root/scripts/new-project.sh")"
[ -n "$tsha" ] || { echo "  FAIL  no template_sha in scripts/new-project.sh"; exit 1; }
tdir="$CLAUDE_CONFIG_DIR/template-files"; mkdir -p "$tdir"
for p in template/docs/agents/domain.md template/AGENTS.md.jinja \
         template/.github/ISSUE_TEMPLATE/end-or-hand-over.yml template/.gitlab/issue_templates/End-or-hand-over.md; do
  curl -fsSL --retry 3 -o "$tdir/$(basename "$p")" "https://raw.githubusercontent.com/coolbress/plinth-template/$tsha/$p" \
    || { echo "  FAIL  could not read $p at plinth-template $tsha"; exit 1; }
done
claude plugin list --json | python3 -c '
import json, re, sys
from pathlib import Path
root, tdir = Path(sys.argv[1]), Path(sys.argv[2])
installed = {p["id"]: Path(p["installPath"]) for p in json.load(sys.stdin)}
entries = {e["name"]: e for e in json.loads((root / ".claude-plugin/marketplace.json").read_text())["plugins"]}
named = {}  # file name -> the skill files that name it
for name in ("mattpocock-skills", "mattpocock-skills-extra"):
    for skill in entries[name]["skills"]:
        for f in sorted((installed[name + "@plinth"] / skill).rglob("*.md")):
            for m in set(re.findall(r"\b(?:CONTEXT|GLOSSARY)\.md\b", f.read_text(encoding="utf-8"))):
                named.setdefault(m, []).append(name + "/" + skill[2:] + "/" + f.name)
m = re.search(r"Root \*\*`([^`]+)`\*\*: the glossary", (tdir / "domain.md").read_text(encoding="utf-8"))
want = m.group(1) if m else None
fail = [] if want else ["docs/agents/domain.md names no root glossary file"]
if want and want not in (tdir / "AGENTS.md.jinja").read_text(encoding="utf-8"):
    fail.append("AGENTS.md does not name " + want + ", the glossary docs/agents/domain.md names")
if want and want not in named:
    fail.append("the template names " + want + ", which no installed skill names: " + str(sorted(named)))
for other in sorted(set(named) - {want}):
    fail.append(", ".join(named[other]) + " name " + other + "; the template names " + str(want))
for f in fail:
    print("  FAIL  " + f)
if fail:
    sys.exit(1)
print("  PASS  the installed skills and the rendered template name one glossary file, " + want)
' "$root" "$tdir"
# The end-or-hand-over form, from the same commit, may name only skills this
# default install lists (its `/retro`, bare /retro in the GitLab template);
# GitLab's `/label` quick action is not a skill.
default="$(for p in plinth@plinth "${deps[@]}"; do claude plugin details "$p" | grep -E '^ *Skills \('; done \
  | sed -E 's/^ *Skills \([0-9]+\) *//' | tr ', ' '\n\n' | sed '/^$/d' | sort -u)"
for f in "$tdir/end-or-hand-over.yml" "$tdir/End-or-hand-over.md"; do
  cmds="$(grep -oE "(^|[[:space:]\`])/[a-z][a-z0-9-]*" "$f" | sed -E 's|^[^/]*/||' | grep -vx label | sort -u)"
  [ -n "$cmds" ] || { echo "  FAIL  $(basename "$f") names no skill: its retrospective line is gone"; exit 1; }
  while IFS= read -r c; do
    grep -qxF -- "$c" <<<"$default" || { echo "  FAIL  $(basename "$f") names /$c, which the default install does not carry"; exit 1; }
  done <<<"$cmds"
  echo "  PASS  $(basename "$f") names only default skills: $(tr '\n' ' ' <<<"$cmds")"
done

# The upgrade path, from the latest release to this checkout, in a second
# configuration this run creates (so a kept CLAUDE_CONFIG_DIR skips it): install
# the release, move the marketplace to this checkout, `claude plugin update
# plinth@plinth`, then the one-time commands the README's upgrade paragraph
# names. A moved dependency is not installed by `update` and its old copy
# stays (measured for #477), so this is where a move that needs a command shows.
# The marketplace is a directory, read in place: the release is a shallow clone
# of its tag, then replaced by this checkout's files, its version raised so that
# `update` sees a newer one (a pull request carries the released version).
upgrade_cmds=("claude plugin install plinth@plinth" "claude plugin prune")
# The docs name them in this order; the other order leaves no mattpocock-skills
# skill until `install` runs.
for doc in README.md docs/tutorials/getting-started.md; do
  grep -qF "\`${upgrade_cmds[0]}\` and then \`${upgrade_cmds[1]}\`" <<<"$(tr -s ' \n' ' ' <"$root/$doc")" \
    || { echo "  FAIL  $doc does not name \`${upgrade_cmds[0]}\` and then \`${upgrade_cmds[1]}\`"; exit 1; }
done
# A raised dependency pin is fetched by neither `update plinth` nor
# `install plinth@plinth`: the entry's new skill list is read against the old
# commit's files, and a skill the old commit keeps elsewhere goes missing
# (measured for #714). Each entry is updated by name, as the docs say.
dep_cmds=("claude plugin update mattpocock-skills@plinth" "claude plugin update mattpocock-skills-extra@plinth")
for doc in README.md docs/tutorials/getting-started.md; do
  for c in "${dep_cmds[@]}"; do
    grep -qF "\`$c\`" "$root/$doc" || { echo "  FAIL  $doc does not name \`$c\`"; exit 1; }
  done
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
  # A release whose plugin.json still names a dependency in the official
  # marketplace (v1.11.0 and earlier) needs it added to install at all.
  if grep -q '"marketplace": "claude-plugins-official"' "$up/mkt/.claude-plugin/plugin.json"; then
    claude plugin marketplace add anthropics/claude-plugins-official >/dev/null
  fi
  claude plugin marketplace add "$up/mkt" >/dev/null
  claude plugin install plinth@plinth -y >/dev/null
  # With the release's mattpocock-skills-extra installed too: the case where a
  # skill moved between the two entries (#704) could end up under both names.
  claude plugin install mattpocock-skills-extra@plinth -y >/dev/null
  rm -rf "$up/mkt" && mkdir "$up/mkt"
  (cd "$root" && git ls-files -z -co --exclude-standard | tar --null -T - -cf -) | tar -xf - -C "$up/mkt"
  for m in plugin.json marketplace.json; do
    sed -i.bak -E 's/"version": "[^"]+"/"version": "999.0.0"/' "$up/mkt/.claude-plugin/$m"
    grep -qF '"version": "999.0.0"' "$up/mkt/.claude-plugin/$m" || { echo "  FAIL  could not raise the version in $m"; exit 1; }
  done
  echo "+ claude plugin update plinth@plinth"; claude plugin update plinth@plinth
  claude plugin list --json | python3 -c 'import json, sys
for p in json.load(sys.stdin):
    print("  INFO  after update alone: %s errors=%s" % (p["id"], p.get("errors", [])))'
  for c in "${upgrade_cmds[@]}"; do echo "+ $c -y"; read -ra cmd <<<"$c"; "${cmd[@]}" -y; done
  for c in "${dep_cmds[@]}"; do echo "+ $c"; read -ra cmd <<<"$c"; "${cmd[@]}"; done
  # check_list holds no ponytail-skills here: the release installed it as a
  # dependency, and `prune` removed it once plinth no longer names it (#598).
  # mattpocock-skills-extra was installed by hand, so `prune` keeps it.
  deps+=(mattpocock-skills-extra@plinth)
  check_list yes
  expect mattpocock-skills@plinth "Skills (15)" "${added[@]}" "Hooks (0)"
  not_expect mattpocock-skills@plinth "${leaving[@]}"
  # The six still listed stay beside the fifteen (#593), and the seven #704 and #714
  # moved are not under both names.
  expect mattpocock-skills-extra@plinth "Skills (6)" "${extra[@]}" "Hooks (0)"
  not_expect mattpocock-skills-extra@plinth resolving-merge-conflicts
  not_expect mattpocock-skills-extra@plinth "${added[@]}"
  # /ponytail-audit comes back the same way, from the entry the marketplace keeps (#598).
  echo "+ claude plugin install ponytail-skills@plinth -y"; claude plugin install ponytail-skills@plinth -y
  expect ponytail-skills@plinth "Skills (1)" "ponytail-audit" "Hooks (0)"
)
