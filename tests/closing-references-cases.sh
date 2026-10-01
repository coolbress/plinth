#!/usr/bin/env bash
# What scripts/closing-references.sh, a step of `ci / docs`, says about a pull
# request's description (#293), against a fake `gh` that answers the one
# GraphQL call with a fixture and records it.
#
# GitHub's list of the issues a merge will close is the fixture's `refs`; the
# description is its `body`. The step fails on every listed issue the closing
# line does not name, and on anything it could not read.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/closing-references.sh"
command -v jq >/dev/null || { echo "  FAIL  jq is needed to build the fixtures"; exit 1; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Fake gh: every call appended to $FX/calls, the answer is $FX/response.json.
printf '%s\n' "$*" >>"$FX/calls"
case "$1 $2" in
  "api graphql") cat "$FX/response.json"; exit "$(cat "$FX/gh_rc" 2>/dev/null || echo 0)" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$work/bin/gh"

n=0
# setup <description> [refs: "12 other/repo#5 ..."]: pull request #7 of
# coolbress/plinth, whose merge GitHub says closes the issues in refs.
setup() {
  n=$((n + 1)); FX="$work/$n"; export FX; mkdir -p "$FX"; : >"$FX/calls"
  local refs='[]' r repo
  for r in ${2:-}; do
    repo="coolbress/plinth"; case "$r" in *"#"*) repo="${r%%#*}"; r="${r##*#}" ;; esac
    refs="$(jq -c --arg repo "$repo" --argjson num "$r" '. + [{number: $num, repository: {nameWithOwner: $repo}}]' <<<"$refs")"
  done
  jq -n --arg body "$1" --argjson refs "$refs" \
    '{data: {repository: {pullRequest: {body: $body, closingIssuesReferences: {nodes: $refs, pageInfo: {hasNextPage: false}}}}}}' \
    >"$FX/response.json"
  export EVENT=pull_request PR=7
}

pass=0; fail=0
# check <label> <want exit> [the output has this] [the output has none of this]
check() {
  local label="$1" want_rc="$2" must="${3:-}" mustnot="${4:-}" rc ok=yes
  PATH="$work/bin:$PATH" REPO=coolbress/plinth GITHUB_STEP_SUMMARY="$FX/summary" bash "$script" >"$FX/out" 2>&1; rc=$?
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
has() {  # <label> <text the last output must hold>
  if grep -qF -- "$2" "$FX/out"; then echo "  PASS  $1"; pass=$((pass + 1))
  else echo "  FAIL  $1: no \"$2\" in the output" >&2; sed 's/^/        out: /' "$FX/out" >&2; fail=$((fail + 1)); fi
}

what=$'## What and why\n\nThe pin moves to v1.5.3.'
how=$'## How it was verified\n\nRan the tests.'
by='Assisted-by: Claude:claude-opus-5-5'

echo "-- a closing keyword in a sentence: fails, naming the issue and the line"
setup "$what It is the second of the two fixes #65 decided to land before v1.0.0."$'\n\n'"$how"$'\n\n'"$by" "65"
check "\"the two fixes #65 decided\" and no closing line"      1 "#65"
has   "the offending line is quoted"                           "the two fixes #65 decided"
has   "the message says how to reword"                         "Reword"
has   "the message says where a real closing line goes"        "Closes #65"
has   "the failure is an ::error:: annotation"                 "::error::"
grep -qF '#65' "$FX/summary" 2>/dev/null || { echo "  FAIL  the job summary does not name #65" >&2; fail=$((fail + 1)); }
setup "$what"$'\n\nThe release carries the\nfixes #65 decided on after the first run:\n\n'"$how"$'\n\n'"$by" "65"
check "a wrapped sentence whose line starts with the keyword"  1 "#65"
setup "$what This also closes #65, in passing."$'\n\n'"$how"$'\n\nCloses #284\n\n'"$by" "65 284"
check "prose closes #65 beside a closing line for #284"        1 "#65" "#284:"
setup "$what (#139, closes #117)."$'\n\n'"$how"$'\n\n'"$by" "117"
check "\"(#139, closes #117)\" in a release's prose"           1 "#117"
setup "$what"$'\n\n'"$how"$'\n\nNote: this fixes #65 for good\n'"$by" "65"
check "a keyword inside a line shaped like a trailer"          1 "#65"
setup "$what This fixes #12 in part."$'\n\n'"$how"$'\n\nPart of #12\n\n'"$by" "12"
check "prose closes #12 and the last line says \`Part of #12\`"  1 "This fixes #12 in part"
setup "$what Resolved: #65 is done."$'\n\n'"$how"$'\n\n'"$by" "65"
check "a keyword with a colon before the number"               1 "Resolved: #65"

echo "-- a closing line that is not in the closing position"
setup "$what"$'\n\n'"$how"$' This is the second of the two\nfixes #65\n\n'"$by" "65"
check "a wrapped sentence whose last line is only keyword and number" 1 "#65"
setup "$what"$'\n\n'"$how"$' This is the second of the two\nfixes #65.\nNote: decided before v1.0.0\n'"$by" "65"
check "the same, with a full stop and a trailer-shaped line below" 1 "#65"
setup "$what"$'\n\nCloses #309\n\n'"$how"$'\n\n'"$by" "309"
check "\`Closes #309\` between two sections"                   1 "move it"
setup "$what"$'\n\n'"$how"$'\n\nCloses #12 and the docs half of #13\n\n'"$by" "12"
check "a last line that says more than the closing"            1 "#12"

setup "$what"$'\n\n'"$how"$'\n\nPart of this work includes two\nfixes #65\n\n'"$by" "65"
check "a wrapped sentence that starts with \"Part of\""         1 "#65"
setup "$what"$'\n\n'"$how"$'\n\nfixes #65\nRelated to what the release decided.\n\n'"$by" "65"
check "a sentence that starts with \"Related to\" below the keyword line" 1 "#65"

echo "-- an issue GitHub closes that no line names"
setup "$what"$'\n\n'"$how"$'\n\n'"$by" "70"
check "linked by hand in the sidebar"                          1 "Development"
setup "$what"$'\n\n'"$how"$'\n\nCloses #5\n\n'"$by" "other/repo#5"
check "the same number in another repository"                  1 "other/repo#5"

echo "-- the closing line: passes"
setup "$what"$'\n\n'"$how"$'\n\nCloses #12\n\n'"$by" "12"
check "\`Closes #12\` directly above the attribution"          0 "#12"
grep -qF 'FAIL' "$FX/summary" 2>/dev/null && { echo "  FAIL  a pass wrote a failure to the job summary" >&2; fail=$((fail + 1)); }
grep -qE 'number=7( |$)' "$FX/calls" && grep -qE 'owner=coolbress( |$)' "$FX/calls" && grep -qE 'name=plinth( |$)' "$FX/calls" \
  || { echo "  FAIL  the call does not ask for coolbress/plinth #7" >&2; sed 's/^/        gh: /' "$FX/calls" >&2; fail=$((fail + 1)); }
setup "$what"$'\n\n'"$how"$'\n\nCloses #12.\n\n'"$by" "12"
check "a full stop after the number"                           0
setup "$what"$'\n\n'"$how"$'\n\nfixes #12\n'"$by" "12"
check "another keyword, lower case, no blank line"             0
setup "$what"$'\n\n'"$how"$'\n\nCloses #12\nCloses #13\n\n'"$by"$'\nAssisted-by: Codex:gpt-5.4' "12 13"
check "two closing lines above two trailers"                   0
setup "$what"$'\n\n'"$how"$'\n\nCloses #12, closes #13\n\n'"$by" "12 13"
check "two issues on one closing line"                         0
setup "$what"$'\n\n'"$how"$'\n\nCloses coolbress/plinth#12\n\n'"$by" "12"
check "the repository written out"                             0
setup "$what"$'\n\n'"$how"$'\n\nCloses Coolbress/Plinth#12\n\n'"$by" "12"
check "the repository in another letter case"                  0
setup "$what"$'\n\n'"$how"$'\n\nCloses https://github.com/coolbress/plinth/issues/12\n\n'"$by" "12"
check "the issue as a URL"                                     0
setup "$what"$'\n\n'"$how"$'\n\nCloses GH-12\n\n'"$by" "12"
check "the issue as GH-12"                                     0
setup "$what"$'\n\n'"$how"$'\n\nPart of #13\nCloses #12\n\n'"$by" "12"
check "\`Part of\` above the closing line, in its paragraph"   0
setup "$what"$'\n\n'"$how"$'\n\nCloses #12\nRelated to #13, #14 and coolbress/plinth-template#31.\n\n'"$by" "12"
check "\`Related to\` with several issues and a full stop"     0
setup "$what"$'\n\n'"$how"$'\n\nCloses other/repo#5\n\n'"$by" "other/repo#5"
check "an issue of another repository, named with it"          0
setup "$what"$'\n\n'"$how"$'\n\nCloses #12\nPart of #13\n\n'"$by" "12"
check "\`Part of\` between the closing line and the attribution" 0
setup "$what"$'\n\n'"$how"$'\n\nCloses #12' "12"
check "no attribution: the closing line is the last line"      0
setup "$(printf '%s\r\n\r\n%s\r\n\r\nCloses #12\r\n\r\n%s\r\n' "$what" "$how" "$by")" "12"
check "CRLF line endings, as the web editor saves them"        0

echo "-- nothing to close: passes"
setup "$what"$'\n\n'"$how"$'\n\nPart of #12\n\n'"$by"
check "\`Part of #12\`"                                        0
setup "$what"$'\n\n'"$how"$'\n\nRelated to #12\n\n'"$by"
check "\`Related to #12\`"                                     0
setup "$what #65 decided two fixes; this is the second."$'\n\n'"$how"$'\n\n'"$by"
check "an issue named in prose with no keyword before it"      0
setup ""
jq '.data.repository.pullRequest.body = null' "$FX/response.json" >"$FX/r" && mv "$FX/r" "$FX/response.json"
check "no description at all"                                  0

echo "-- not a pull request: a pass, and no call"
setup "$what" "65"; export EVENT=push; unset PR
check "a push to main"                                         0 "not a pull request"
[ -s "$FX/calls" ] && { echo "  FAIL  a push made gh calls" >&2; fail=$((fail + 1)); }

echo "-- what cannot be read fails, it does not pass"
setup "$what"$'\n\nCloses #12' "12"; unset PR
check "a pull request event with no number"                    1
setup "$what"$'\n\nCloses #12' "12"; echo 1 >"$FX/gh_rc"
check "gh fails"                                               1 "could not read"
setup "$what"$'\n\nCloses #12' "12"; echo '{"data":{"repository":{"pullRequest":null}}}' >"$FX/response.json"
check "the answer holds no pull request"                       1 "could not read"
setup "$what"$'\n\nCloses #12' "12"; echo 'HTTP 502' >"$FX/response.json"
check "the answer is not JSON"                                 1 "could not read"
setup "$what"$'\n\nCloses #12' "12"
jq 'del(.data.repository.pullRequest.closingIssuesReferences)' "$FX/response.json" >"$FX/r" && mv "$FX/r" "$FX/response.json"
check "the answer holds no closing list"                       1 "could not read"
setup "$what"$'\n\nCloses #12' "12"
jq '.data.repository.pullRequest.closingIssuesReferences.pageInfo.hasNextPage = true' "$FX/response.json" >"$FX/r" && mv "$FX/r" "$FX/response.json"
check "the closing list has a second page"                     1 "more than"

echo "-- $pass passed, $fail failed"
[ "$fail" -eq 0 ]
