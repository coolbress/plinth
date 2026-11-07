#!/usr/bin/env bash
# plinth's reusable workflows stay inside the Actions allowlist every consumer
# has (#867). A calling repository's allowlist also applies to the actions used
# inside a reusable workflow it calls: measured on #861, where a third-party
# action in python-ci.yml ended a caller's run in startup_failure with no job
# and no log. plinth's own repository runs with a narrow allowlist too, but that
# is a setting; this holds the rule in the code.
#
# "Every consumer" is what the door gives all archetypes: GitHub-owned actions
# and the patterns on its allow_args line, read from scripts/new-project.sh and
# judged with floor-check.py's own matcher. An archetype's release actions do
# not count: the other archetypes refuse them. Offline; tests/release-allowlist.sh
# holds the template's rendered workflows to the same allowlist, with network.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
door="$root/scripts/new-project.sh"
floor="$root/scripts/floor-check.py"
files=(python-ci.yml pr-label.yml pr-review.yml)
rule="# Rule: a caller's Actions allowlist covers this file; a third-party action stops every consumer's checks (#867)."
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

# Prints one line per refused action and exits 1; exits 0 only if each file was read.
check() { # <workflows dir> [door]
  local dir="$1" door_file="${2:-$door}" allow_args=() owned=false patterns="" a
  eval "$(grep '^allow_args=(' "$door_file")"
  for a in ${allow_args[@]+"${allow_args[@]}"}; do
    case "$a" in 'patterns_allowed[]='*) patterns+="${a#*=}"$'\n' ;; esac
  done
  grep -q -- '-F github_owned_allowed=true' "$door_file" && owned=true
  python3 - "$floor" "$dir" "$owned" "$patterns" "${files[@]}" <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("fc", sys.argv[1]); fc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fc)
root, owned, patterns, names = Path(sys.argv[2]), sys.argv[3] == "true", sys.argv[4].split(), sys.argv[5:]
WHY = ("every consumer's Actions allowlist refuses it, so their checks end in startup_failure with no job "
       "(#861). A third-party action belongs in a step run by a script, or must go through a template release "
       "that widens the door's allowlist")
refused = 0
def refuse(text):
    global refused
    refused += 1
    print(text)
for name in names:
    path, shown = root / name, f".github/workflows/{name}"
    if not path.is_file():
        refuse(f"{shown}: not found, so its actions were not read")
        continue
    for n, value, readable in fc.iter_uses(fc.read(path)):
        if not readable:
            refuse(f"{shown}:{n}: a uses this checker cannot read, so it may name a refused action; "
                   "write it as a plain `uses: owner/repo@sha` line")
        elif value.startswith("./"):
            continue
        elif value.startswith("docker://"):
            refuse(f"{shown}:{n}: {value}: whether a consumer's allowlist lets an image run is not measured; "
                   "measure it before adding one")
        elif not (owned and value.split("/", 1)[0].lower() in fc.GITHUB_OWNED) and not fc.allowlist_allows(value, patterns):
            refuse(f"{shown}:{n}: {value}: {WHY}")
sys.exit(1 if refused else 0)
PY
}

# A copy of the three workflows, with a text appended to one of them as a new job.
seed() { # <file> <text>
  local one
  rm -rf "$work/w"; mkdir "$work/w"
  for one in "${files[@]}"; do cp "$root/.github/workflows/$one" "$work/w/$one"; done
  printf '%s\n' "$2" >> "$work/w/$1"
}
step() { printf '  seeded:\n    runs-on: ubuntu-latest\n    steps:\n      %s\n' "$1"; }

must_refuse() { # <what> <file> <text> <what the output must name>
  local out rc
  seed "$2" "$3"; out="$(check "$work/w" 2>&1)"; rc=$?
  if [ "$rc" = 1 ] && grep -qF -- "$4" <<<"$out" && grep -qF ".github/workflows/$2" <<<"$out"; then ok "$1 fails (must not pass)"
  else bad "$1 passed or failed without naming it (exit $rc): $out"; fi
}
must_allow() { # <what> <file> <text>
  local out
  seed "$2" "$3"
  if out="$(check "$work/w" 2>&1)"; then ok "$1 passes"; else bad "$1 was refused: $out"; fi
}

# Today's three.
if out="$(check "$root/.github/workflows" 2>&1)"; then ok "every action in ${files[*]} is one every consumer allows"
else bad "a reusable workflow uses an action a consumer refuses:"; printf '%s\n' "$out"; fi
for f in "${files[@]}"; do
  [ "$(head -n 1 "$root/.github/workflows/$f")" = "$rule" ] && ok "$f: the rule is its first line" ||
    bad "$f: its first line must be: $rule"
done

# A seeded third-party action in each, with the message that says why.
sha=68559e9000000000000000000000000000000000
for f in "${files[@]}"; do
  must_refuse "$f with a third-party step" "$f" "$(step "- uses: astral-sh/setup-uv@$sha")" \
    "astral-sh/setup-uv@$sha: every consumer's Actions allowlist refuses it, so their checks end in startup_failure with no job (#861). A third-party action belongs in a step run by a script, or must go through a template release that widens the door's allowlist"
done

# Spellings and near misses.
f=python-ci.yml
must_refuse "a quoted third-party action" "$f" "$(step "- uses: \"astral-sh/setup-uv@$sha\"")" "astral-sh/setup-uv@$sha"
must_refuse "a third-party reusable workflow called by a job" "$f" "$(printf '  seeded:\n    uses: o/r/.github/workflows/w.yml@%s\n' "$sha")" "o/r/.github/workflows/w.yml@$sha"
must_refuse "a uses the reader cannot parse" "$f" "$(step "- {uses: astral-sh/setup-uv@$sha}")" "cannot read"
must_refuse "a docker image, not measured" "$f" "$(step "- uses: docker://alpine@sha256:$sha")" "not measured"
must_refuse "an action only some archetypes allow" "$f" "$(step "- uses: pypa/gh-action-pypi-publish@$sha")" "pypa/gh-action-pypi-publish@$sha"
must_refuse "another only some archetypes allow" "$f" "$(step "- uses: docker/build-push-action@$sha")" "docker/build-push-action@$sha"
must_refuse "a name that only starts like plinth's" "$f" "$(step "- uses: coolbress/plinth-x/a@$sha")" "coolbress/plinth-x/a@$sha"
must_refuse "a name that only starts like GitHub's" "$f" "$(step "- uses: actions-x/a@$sha")" "actions-x/a@$sha"

# What must keep passing.
must_allow "a GitHub-owned action" "$f" "$(step "- uses: github/codeql-action/init@$sha")"
must_allow "an action under coolbress/plinth" "$f" "$(step "- uses: coolbress/plinth/.github/actions/a@$sha")"
must_allow "a local ./ action" "$f" "$(step "- uses: ./.github/actions/a")"
must_allow "a third-party name in a comment" "$f" "# uses: astral-sh/setup-uv@$sha"
must_allow "a third-party name inside a run block" "$f" "$(step "- run: |")"$'\n'"          uses: astral-sh/setup-uv@$sha"

# Fails closed: a file it cannot read, a door it cannot read.
seed "$f" ""; rm "$work/w/$f"
out="$(check "$work/w" 2>&1)" && bad "a missing workflow passed" || { grep -qF "$f: not found" <<<"$out" && ok "a missing workflow fails" || bad "a missing workflow failed without naming it: $out"; }
seed "$f" "$(step "- uses: coolbress/plinth/.github/actions/a@$sha")"
grep -v '^allow_args=(' "$door" > "$work/door-no-patterns"
out="$(check "$work/w" "$work/door-no-patterns" 2>&1)" && bad "a door with no allow_args line still allowed plinth's action" ||
  ok "a door with no allow_args line allows no pattern"
sed 's/-F github_owned_allowed=true/-F github_owned_allowed=false/' "$door" > "$work/door-not-owned"
out="$(check "$root/.github/workflows" "$work/door-not-owned" 2>&1)" && bad "a door without GitHub-owned actions still allowed actions/checkout" ||
  ok "a door that does not allow GitHub-owned actions refuses them"

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
