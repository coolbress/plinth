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
#
# The list fails closed (#870): every workflow_call file is in files or in
# excluded, with its reason, or the test fails naming it. A uses: in a checked
# file that calls another workflow of this repository makes that file checked
# too, at the copy in this checkout: a call pinned to another commit is not read
# at that commit, and workflows of other repositories are not read at all. A
# uses: of anything else in this repository (a composite action, say) is not
# read either, so it fails.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
door="$root/scripts/new-project.sh"
floor="$root/scripts/floor-check.py"
files=(python-ci.yml pr-label.yml pr-review.yml)
excluded=("plinth-ci.yml|only plinth's own ci.yml calls it, under plinth's own allowlist")
rule="# Rule: a caller's Actions allowlist covers this file; a third-party action stops every consumer's checks (#867)."
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

# Prints one line per refused action or unlisted file and exits 1; exits 0 only
# if each checked file was read and every workflow_call file is in a list.
check() { # <workflows dir> [door]
  local dir="$1" door_file="${2:-$door}" allow_args=() owned=false patterns="" a
  eval "$(grep '^allow_args=(' "$door_file")"
  for a in ${allow_args[@]+"${allow_args[@]}"}; do
    case "$a" in 'patterns_allowed[]='*) patterns+="${a#*=}"$'\n' ;; esac
  done
  grep -q -- '-F github_owned_allowed=true' "$door_file" && owned=true
  python3 - "$floor" "$dir" "$owned" "$patterns" "${files[@]}" -- ${excluded[@]+"${excluded[@]}"} <<'PY'
import importlib.util, re, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("fc", sys.argv[1]); fc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fc)
root, owned, patterns, rest = Path(sys.argv[2]), sys.argv[3] == "true", sys.argv[4].split(), sys.argv[5:]
names = rest[:rest.index("--")]
excluded = dict(e.partition("|")[::2] for e in rest[rest.index("--") + 1:])
WHY = ("every consumer's Actions allowlist refuses it, so their checks end in startup_failure with no job "
       "(#861). A third-party action belongs in a step run by a script, or must go through a template release "
       "that widens the door's allowlist")
refused = 0
def refuse(text):
    global refused
    refused += 1
    print(text)
THIS_REPO = r"\./|coolbress/plinth/"
THIS_REPO_WORKFLOW = re.compile(rf"(?:{THIS_REPO})\.github/workflows/([^@/]+)(?:@.*)?$", re.I)
checked = list(names)
for name in checked:  # grows while it runs: a called file is read in its turn
    path, shown = root / name, f".github/workflows/{name}"
    if not path.is_file():
        refuse(f"{shown}: not found, so its actions were not read")
        continue
    for n, value, readable in fc.iter_uses(fc.read(path)):
        if not readable:
            refuse(f"{shown}:{n}: a uses this checker cannot read, so it may name a refused action; "
                   "write it as a plain `uses: owner/repo@sha` line")
            continue
        called = THIS_REPO_WORKFLOW.match(value)
        if called:
            if called.group(1) not in checked:
                checked.append(called.group(1))
        elif re.match(THIS_REPO, value, re.I):
            refuse(f"{shown}:{n}: {value}: an action this test does not read (composite or other), so its own "
                   "actions would meet every consumer's allowlist unchecked; use a workflow in .github/workflows, "
                   "or teach this test to read it first")
            continue
        if value.startswith("./"):
            continue
        elif value.startswith("docker://"):
            refuse(f"{shown}:{n}: {value}: whether a consumer's allowlist lets an image run is not measured; "
                   "measure it before adding one")
        elif not (owned and value.split("/", 1)[0].lower() in fc.GITHUB_OWNED) and not fc.allowlist_allows(value, patterns):
            refuse(f"{shown}:{n}: {value}: {WHY}")
for path in sorted(p for p in root.iterdir() if p.suffix in {".yml", ".yaml"}):
    shown = f".github/workflows/{path.name}"
    if path.name in checked or not any(re.search(r"\bworkflow_call\b", line) for _, _, line in fc.yaml_lines(fc.read(path))):
        continue
    if path.name not in excluded:
        refuse(f"{shown}: names workflow_call, so a consumer may call it, and is "
               "neither checked nor excluded: add it to files, or to excluded with its reason")
    elif not excluded[path.name].strip():
        refuse(f"{shown}: excluded with no reason: state why no consumer calls it")
for name in excluded:
    if not (root / name).is_file():
        refuse(f".github/workflows/{name}: excluded, but not found: remove it from excluded")
sys.exit(1 if refused else 0)
PY
}

# A copy of every workflow, with a text appended to one of them, or to a new file.
seed() { # <file> <text>
  rm -rf "$work/w"; mkdir "$work/w"
  cp "$root/.github/workflows/"*.yml "$work/w/"
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

# An action of this repository is not read (a composite action, say), so it fails.
unread_action="an action this test does not read (composite or other)"
must_refuse "an action under coolbress/plinth" "$f" "$(step "- uses: coolbress/plinth/.github/actions/a@$sha")" "coolbress/plinth/.github/actions/a@$sha: $unread_action"
must_refuse "the same, with owner and repo in another case" "$f" "$(step "- uses: CoolBress/Plinth/.github/actions/a@$sha")" "CoolBress/Plinth/.github/actions/a@$sha: $unread_action"
must_refuse "a local ./ action" "$f" "$(step "- uses: ./.github/actions/a")" "./.github/actions/a: $unread_action"
must_refuse "an action at the root, by ./" "$f" "$(step "- uses: ./")" "./: $unread_action"
must_refuse "a path that leaves and re-enters .github" "$f" "$(step "- uses: ./.github/../.github/workflows/plinth-ci.yml")" "$unread_action"
must_refuse "a path that leaves .github/workflows" "$f" "$(step "- uses: ./.github/workflows/../actions/a")" "$unread_action"

# What must keep passing.
must_allow "a GitHub-owned action" "$f" "$(step "- uses: github/codeql-action/init@$sha")"
must_allow "a third-party name in a comment" "$f" "# uses: astral-sh/setup-uv@$sha"
must_allow "a third-party name inside a run block" "$f" "$(step "- run: |")"$'\n'"          uses: astral-sh/setup-uv@$sha"

# A workflow_call file in neither list fails, naming the file (#870).
unread="neither checked nor excluded: add it to files, or to excluded with its reason"
must_refuse "a new reusable workflow, block form" new.yml "$(printf 'on:\n  workflow_call:\n')" "$unread"
must_refuse "a new reusable workflow, one line" new.yml "on: workflow_call" "$unread"
must_refuse "a new reusable workflow, in a list" new.yml "on: [push, workflow_call]" "$unread"
must_refuse "a new reusable workflow, quoted flow form" new.yml '"on": {"workflow_call": {}}' "$unread"
must_refuse "a new reusable workflow, .yaml" new.yaml "on: workflow_call" "$unread"
must_allow "a new workflow that is not reusable" new.yml "on: [push]"
must_allow "a new workflow naming workflow_call in a comment" new.yml "# on: workflow_call"
must_allow "a new workflow naming workflow_call in a run block" new.yml "$(step "- run: |")"$'\n'"          echo workflow_call"

# The one exclusion: named, with a reason, and not read.
must_allow "a third-party action in the excluded file" plinth-ci.yml "$(step "- uses: astral-sh/setup-uv@$sha")"
out="$(excluded=(); check "$root/.github/workflows" 2>&1)" && bad "plinth-ci.yml passed with no exclusion" || {
  grep -qF "plinth-ci.yml: names workflow_call" <<<"$out" && ok "plinth-ci.yml without its exclusion fails" || bad "plinth-ci.yml failed without being named: $out"; }
out="$(excluded=("plinth-ci.yml| "); check "$root/.github/workflows" 2>&1)" && bad "an exclusion with no reason passed" || {
  grep -qF "plinth-ci.yml: excluded with no reason" <<<"$out" && ok "an exclusion with no reason fails" || bad "an exclusion with no reason failed without saying so: $out"; }

seed "$f" ""; rm "$work/w/plinth-ci.yml"
out="$(check "$work/w" 2>&1)" && bad "an exclusion naming a file that is not there passed" || {
  grep -qF ".github/workflows/plinth-ci.yml: excluded, but not found" <<<"$out" && ok "an exclusion naming a file that is not there fails" || bad "a stale exclusion failed without naming it: $out"; }

# A checked file calling another workflow of this repository checks that file too.
job_calls() { printf '  seeded:\n    uses: %s\n' "$1"; }
reusable_with() { printf 'on: workflow_call\njobs:\n%s\n' "$1"; }
third_party="$(reusable_with "$(step "- uses: astral-sh/setup-uv@$sha")")"
called_refused() { # <what> <uses in python-ci.yml> <called file> <its text> <what the output must name>
  local out rc
  seed "$f" "$(job_calls "$2")"; [ -z "$3" ] || printf '%s\n' "$4" >> "$work/w/$3"
  out="$(check "$work/w" 2>&1)"; rc=$?
  if [ "$rc" = 1 ] && grep -qF -- "$5" <<<"$out"; then ok "$1 fails (must not pass)"
  else bad "$1 passed or failed without naming it (exit $rc): $out"; fi
}
named="astral-sh/setup-uv@$sha: every consumer"
called_refused "a third-party action in a file called by ./" ./.github/workflows/called.yml called.yml "$third_party" ".github/workflows/called.yml:6: $named"
called_refused "a third-party action in a file called by owner/repo" "coolbress/plinth/.github/workflows/called.yml@$sha" called.yml "$third_party" ".github/workflows/called.yml:6: $named"
called_refused "the same, with owner and repo in another case" "CoolBress/Plinth/.github/workflows/called.yml@$sha" called.yml "$third_party" ".github/workflows/called.yml:6: $named"
called_refused "a called file that is not there" ./.github/workflows/gone.yml "" "" ".github/workflows/gone.yml: not found"
line=$(( $(wc -l < "$root/.github/workflows/plinth-ci.yml") + 4 ))
called_refused "the excluded file, once a checked file calls it" ./.github/workflows/plinth-ci.yml plinth-ci.yml "$(step "- uses: astral-sh/setup-uv@$sha")" ".github/workflows/plinth-ci.yml:$line: $named"
seed "$f" "$(job_calls ./.github/workflows/first.yml)"
reusable_with "$(job_calls "coolbress/plinth/.github/workflows/second.yml@$sha")" > "$work/w/first.yml"
printf '%s\n' "$third_party" > "$work/w/second.yml"
out="$(check "$work/w" 2>&1)" && bad "a third-party action two calls away passed" || {
  grep -qF ".github/workflows/second.yml:6: $named" <<<"$out" && ok "a third-party action two calls away fails" || bad "two calls away failed without naming it: $out"; }
seed "$f" "$(job_calls ./.github/workflows/called.yml)"
reusable_with "$(step "- uses: actions/checkout@$sha")" > "$work/w/called.yml"
if out="$(check "$work/w" 2>&1)"; then ok "a clean reusable workflow a checked file calls counts as checked"; else bad "a clean called workflow was refused: $out"; fi
seed "$f" "$(job_calls ./.github/workflows/first.yml)"
reusable_with "$(job_calls ./.github/workflows/second.yml)" > "$work/w/first.yml"
reusable_with "$(job_calls ./.github/workflows/first.yml)" > "$work/w/second.yml"
if out="$(check "$work/w" 2>&1)"; then ok "two files calling each other end and pass"; else bad "a call cycle was refused: $out"; fi

# Fails closed: a file it cannot read, a door it cannot read.
seed "$f" ""; rm "$work/w/$f"
out="$(check "$work/w" 2>&1)" && bad "a missing workflow passed" || { grep -qF "$f: not found" <<<"$out" && ok "a missing workflow fails" || bad "a missing workflow failed without naming it: $out"; }
seed "$f" "$(job_calls "coolbress/plinth/.github/workflows/pr-label.yml@$sha")"
grep -v '^allow_args=(' "$door" > "$work/door-no-patterns"
out="$(check "$work/w" "$work/door-no-patterns" 2>&1)" && bad "a door with no allow_args line still allowed a call to plinth's workflow" || {
  grep -qF "pr-label.yml@$sha: every consumer" <<<"$out" && ok "a door with no allow_args line allows no pattern, so a call to plinth's workflow fails" ||
    bad "a door with no allow_args line failed for another reason: $out"; }
sed 's/-F github_owned_allowed=true/-F github_owned_allowed=false/' "$door" > "$work/door-not-owned"
out="$(check "$root/.github/workflows" "$work/door-not-owned" 2>&1)" && bad "a door without GitHub-owned actions still allowed actions/checkout" ||
  ok "a door that does not allow GitHub-owned actions refuses them"

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
