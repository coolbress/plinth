#!/usr/bin/env bash
# What scripts/release-gate.sh, the step of `ci / release-gate` (#863), says
# about a pull request, against a fake `gh` that answers the e2e runs call with
# a fixture, and a throwaway git repository whose HEAD^1..HEAD is the pull
# request's diff, as the merge commit's is on the runner.
#
# A release (a release/v* branch, a `chore(release):` title, or a changed
# "version" line in either manifest) passes only on a green e2e run on its
# head from a release/v* branch, the run started last speaking. Anything else
# passes at once. Anything it cannot read fails.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/release-gate.sh"
command -v jq >/dev/null || { echo "  FAIL  jq is needed to build the fixtures"; exit 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/release-gate.XXXXXX")"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Fake gh: every call appended to $FX/calls. The runs call prints
# $FX/runs.json through the --jq filter it was given, as gh does, and exits
# with $FX/gh_rc (an error prints $FX/runs.json to stderr instead).
printf '%s\n' "$*" >>"$FX/calls"
[ "$1" = api ] || { echo "fake gh: unexpected $*" >&2; exit 1; }
rc="$(cat "$FX/gh_rc" 2>/dev/null || echo 0)"
if [ "$rc" != 0 ]; then cat "$FX/runs.json" >&2; exit "$rc"; fi
filter=""; prev=""
for a in "$@"; do [ "$prev" = --jq ] && filter="$a"; prev="$a"; done
jq -r "${filter:-.}" "$FX/runs.json"
EOF
chmod +x "$work/bin/gh"

sha=1111111111111111111111111111111111111111
n=0
# setup <branch> <title> <version change: none|plugin|marketplace>
setup() {
  n=$((n + 1)); FX="$work/$n"; export FX; mkdir -p "$FX/repo/.claude-plugin"; : >"$FX/calls"
  (
    cd "$FX/repo" || exit 1
    git init -q && git config user.email t@example.com && git config user.name t
    printf '{\n  "name": "plinth",\n  "version": "1.0.0"\n}\n' >.claude-plugin/plugin.json
    printf '{\n  "name": "plinth",\n  "version": "1.0.0",\n  "plugins": []\n}\n' >.claude-plugin/marketplace.json
    echo a >README.md
    git add -A && git commit -qm base
    echo b >>README.md
    case "$3" in
      plugin) sed -i.bak 's/"1.0.0"/"1.1.0"/' .claude-plugin/plugin.json ;;
      marketplace) sed -i.bak 's/"1.0.0"/"1.1.0"/' .claude-plugin/marketplace.json ;;
      oneline) printf '{ "name": "plinth", "version": "1.1.0" }\n' >.claude-plugin/plugin.json ;;
      reformat) printf '{"name": "plinth", "version": "1.0.0"}\n' >.claude-plugin/plugin.json ;;
    esac
    rm -f .claude-plugin/*.bak
    git add -A && git commit -qm head
  )
  echo '{"total_count":0,"workflow_runs":[]}' >"$FX/runs.json"
  export EVENT=pull_request HEAD_REF="$1" TITLE="$2" HEAD_SHA="$sha"
}
# runs <conclusion|status> <branch> <started> ...: the e2e runs on $sha.
runs() {
  local out='[]'
  while [ $# -ge 3 ]; do
    out="$(jq -c --arg c "$1" --arg b "$2" --arg t "$3" --arg s "$sha" '. + [{
      head_sha: $s, head_branch: $b, run_started_at: $t,
      status: (if ($c|IN("success","failure","cancelled")) then "completed" else $c end),
      conclusion: (if ($c|IN("success","failure","cancelled")) then $c else null end),
      html_url: ("https://github.com/coolbress/plinth/actions/runs/" + $t)}]' <<<"$out")"
    shift 3
  done
  jq -c '{total_count: length, workflow_runs: .}' <<<"$out" >"$FX/runs.json"
}

pass=0; fail=0
# check <label> <want exit> [the output has this] [the output has none of this]
check() {
  local label="$1" want_rc="$2" must="${3:-}" mustnot="${4:-}" rc ok=yes
  (cd "$FX/repo" && PATH="$work/bin:$PATH" REPO=coolbress/plinth GITHUB_STEP_SUMMARY="$FX/summary" \
    bash "$script") >"$FX/out" 2>&1; rc=$?
  [ "$rc" = "$want_rc" ] || ok=no
  if [ -n "$must" ] && ! grep -qF -- "$must" "$FX/out"; then ok=no; fi
  if [ -n "$mustnot" ] && grep -qF -- "$mustnot" "$FX/out"; then ok=no; fi
  if [ "$ok" = yes ]; then echo "  PASS  $label"; pass=$((pass + 1))
  else
    echo "  FAIL  $label: exit $rc (want $want_rc)${must:+, wanted \"$must\"}${mustnot:+, refused \"$mustnot\"}" >&2
    sed 's/^/        out: /' "$FX/out" >&2
    fail=$((fail + 1))
  fi
}
holds() {  # <label> <command...>: the command succeeds
  local label="$1"; shift
  if "$@"; then echo "  PASS  $label"; pass=$((pass + 1))
  else echo "  FAIL  $label" >&2; fail=$((fail + 1)); fi
}
called() {  # <label> <0|1: whether the runs API was called>
  local got=0; [ -s "$FX/calls" ] && got=1
  if [ "$got" = "$2" ]; then echo "  PASS  $1"; pass=$((pass + 1))
  else echo "  FAIL  $1: runs API called=$got, want $2" >&2; fail=$((fail + 1)); fi
}

echo "-- not a release: passes at once, reads nothing"
setup feat/x "feat: a thing" none
check "a feature branch with no version change passes"           0 "not a release"
called "and asks GitHub nothing"                                  0
holds "the summary has a pass line" grep -qF 'pass:' "$FX/summary"
setup main "feat: a thing" none
EVENT=push check "a push to main is not a pull request: passes"  0 "not a pull request"

echo "-- a release with no green e2e on its head fails, with the dispatch command"
setup release/v1.1.0 "chore(release): v1.1.0" plugin
check "a release branch with no e2e run fails"                    1 "gh workflow run e2e.yml --ref release/v1.1.0"
holds "the failure is an ::error:: annotation" grep -qF '::error::' "$FX/out"
called "the runs API was asked"                                   1
holds "it asks for the runs on the pull request's head" grep -qF "head_sha=$sha" "$FX/calls"

setup release/v1.1.0 "chore(release): v1.1.0" plugin
runs success release/v1.1.0 2026-11-10T10:00:00Z
check "a release branch with a green e2e on its head passes"      0 "green"

setup release/v1.1.0 "chore(release): v1.1.0" plugin
runs success release/v1.1.0 2026-11-10T10:00:00Z failure release/v1.1.0 2026-11-10T11:00:00Z
check "a green run, then a red one started later: fails"          1 "gh workflow run e2e.yml"
setup release/v1.1.0 "chore(release): v1.1.0" plugin
runs failure release/v1.1.0 2026-11-10T10:00:00Z success release/v1.1.0 2026-11-10T11:00:00Z
check "a red run, then a green one started later: passes"         0
setup release/v1.1.0 "chore(release): v1.1.0" plugin
runs success release/v1.1.0 2026-11-10T10:00:00Z in_progress release/v1.1.0 2026-11-10T11:00:00Z
check "a run still going, started after a green one: fails"       1 "in_progress"
setup release/v1.1.0 "chore(release): v1.1.0" plugin
runs success main 2026-11-10T10:00:00Z
check "a green run on another branch at that commit does not count (#862)" 1 "release/v"

echo "-- what makes a pull request a release"
setup chore/bump "chore: bump" plugin
check "a changed version line in plugin.json, on any branch"      1 "plugin.json"
setup chore/bump "chore: bump" marketplace
check "a changed version line in marketplace.json, on any branch" 1 "marketplace.json"
setup chore/bump "chore: bump" oneline
check "a version moved onto a shared line and raised is still a change" 1 "plugin.json"
setup chore/fmt "style: one line" reformat
check "a manifest reformatted, its version the same, is not a release" 0 "not a release"
setup chore/bump "chore: bump" plugin
runs success chore/bump 2026-11-10T10:00:00Z
check "a version change off release/v*: its e2e never tested this commit's calls" 1 "release/v"
setup chore/x "chore(release): v1.1.0" none
check "a chore(release) title alone"                              1 "gh workflow run e2e.yml"
setup release/v1.1.0 "docs: x" none
check "a release/v* branch alone"                                 1 "gh workflow run e2e.yml"

echo "-- anything unread fails"
setup release/v1.1.0 "chore(release): v1.1.0" plugin
echo 'gh: Not Found (HTTP 404)' >"$FX/runs.json"; echo 1 >"$FX/gh_rc"
check "a missing e2e.yml (404) fails"                             1 "HTTP 404"
setup release/v1.1.0 "chore(release): v1.1.0" plugin
HEAD_SHA="" check "an empty head SHA fails"                       1 "::error::"
setup feat/x "feat: a thing" none
(cd "$FX/repo" && git checkout -q --orphan lone && git commit -qm lone)
check "a diff that cannot be read fails, not a pass"              1 "::error::"
setup feat/x "feat: a thing" none
HEAD_REF="" check "a pull request with no head branch fails" 1 "::error::"

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
