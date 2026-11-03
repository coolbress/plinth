#!/usr/bin/env bash
# What `ci / pr-title` says about a pull request's description (#781): the two
# steps after the title check, their `run:` scripts extracted from
# python-ci.yml and run as the job runs them. The fetch step gets plinth's
# scripts from a fake `curl` that serves this checkout; the check step asks a
# fake `gh` that answers the one GraphQL call with a fixture.
# tests/closing-references-cases.sh covers the decision itself; here it is
# what reaches the job: the exit code, the verdict line and the report.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="$root/.github/workflows/python-ci.yml"
command -v jq >/dev/null || { echo "  FAIL  jq is needed to build the fixtures"; exit 1; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

# step <name> <out>: the step of the pr-title job with that name; its `run:`
# script, dedented, to <out>, and the whole step to <out>.step.
step() {
  python3 - "$wf" "$1" "$2" <<'PY'
import re, sys
wf, name, out = sys.argv[1:4]
lines = open(wf, encoding="utf-8").read().split("\n")
start = lines.index("  pr-title:")
end = next(i for i in range(start + 1, len(lines)) if re.match(r"^  [a-z]", lines[i]))
job = lines[start:end]
at = [i for i, l in enumerate(job) if l.strip() == f"- name: {name}"]
if len(at) != 1:
    sys.exit(f"step '{name}' found {len(at)} times in the pr-title job")
i = at[0]; indent = len(job[i]) - len(job[i].lstrip())
j = next((k for k in range(i + 1, len(job)) if job[k].strip().startswith("- ")
          and len(job[k]) - len(job[k].lstrip()) == indent), len(job))
stp = job[i:j]
r = next(k for k, l in enumerate(stp) if l.strip() == "run: |")
deep = len(stp[r]) - len(stp[r].lstrip())
body = []
for l in stp[r + 1:]:
    if l.strip() and len(l) - len(l.lstrip()) <= deep:
        break
    body.append(l[deep + 2:])
open(out, "w", encoding="utf-8").write("\n".join(body).rstrip() + "\n")
open(out + ".step", "w", encoding="utf-8").write("\n".join(stp) + "\n")
PY
}
step "Fetch the description check from the same plinth commit as this workflow" "$work/fetch.sh" \
  || { echo "  FAIL  the fetch step is not in python-ci.yml's pr-title job"; exit 1; }
step "The description closes no issue outside its closing line" "$work/check.sh" \
  || { echo "  FAIL  the description step is not in python-ci.yml's pr-title job"; exit 1; }

SHA=0123456789abcdef0123456789abcdef01234567
cat >"$work/bin/curl" <<'EOF'
#!/usr/bin/env bash
# Fake curl: -o <file> <raw.githubusercontent.com URL> copies that path from
# this checkout; every URL appended to $FX/curl, and $FX/curl_fails fails it.
printf '%s\n' "$*" >>"$FX/curl"
[ -f "$FX/curl_fails" ] && { echo "curl: (22) 404" >&2; exit 22; }
out=""; url=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2 ;; https://*) url="$1"; shift ;; *) shift ;; esac; done
path="${url#https://raw.githubusercontent.com/coolbress/plinth/"$SHA"/}"
[ "$path" != "$url" ] || { echo "fake curl: unexpected $url" >&2; exit 22; }
cp "$ROOT/$path" "$out"
EOF
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FX/calls"
case "$1 $2" in
  "api graphql") cat "$FX/response.json"; exit "$(cat "$FX/gh_rc" 2>/dev/null || echo 0)" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$work/bin/curl" "$work/bin/gh"
export SHA ROOT="$root"

pass=0; fail=0
ok() { echo "  PASS  $1"; pass=$((pass + 1)); }
no() { echo "  FAIL  $1" >&2; for f in "${@:2}"; do [ -f "$f" ] && sed 's/^/        | /' "$f" >&2; done; fail=$((fail + 1)); }

n=0
# setup <description> [refs] [event]: pull request #7 of coolbress/plinth,
# whose merge GitHub says closes the issues in refs; the fetch step has run.
setup() {
  n=$((n + 1)); FX="$work/$n"; export FX; mkdir -p "$FX/temp"; : >"$FX/calls"; : >"$FX/curl"; : >"$FX/summary"
  local refs='[]' r
  for r in ${2:-}; do refs="$(jq -c --argjson num "$r" '. + [{number: $num, repository: {nameWithOwner: "coolbress/plinth"}}]' <<<"$refs")"; done
  jq -n --arg body "$1" --argjson refs "$refs" \
    '{data: {repository: {pullRequest: {body: $body, closingIssuesReferences: {nodes: $refs, pageInfo: {hasNextPage: false}}}}}}' \
    >"$FX/response.json"
  export EVENT_NAME="${3:-pull_request}" PR=7 FETCH=success
  PATH="$work/bin:$PATH" RUNNER_TEMP="$FX/temp" PLINTH_SHA="$SHA" GITHUB_STEP_SUMMARY="$FX/summary" \
    bash "$work/fetch.sh" >"$FX/fetch.out" 2>&1 || { no "the fetch step failed" "$FX/fetch.out"; return 1; }
}
# run <label> <want exit> [the output has this] [the summary has this]
run() {
  local rc
  PATH="$work/bin:$PATH" RUNNER_TEMP="$FX/temp" REPO=coolbress/plinth GH_TOKEN=x GITHUB_STEP_SUMMARY="$FX/summary" \
    bash "$work/check.sh" >"$FX/out" 2>&1; rc=$?
  if [ "$rc" != "$2" ]; then no "$1: exit $rc, want $2" "$FX/out"
  elif [ -n "${3:-}" ] && ! grep -qF -- "$3" "$FX/out"; then no "$1: no \"$3\" in the output" "$FX/out"
  elif [ -n "${4:-}" ] && ! grep -qF -- "$4" "$FX/summary"; then no "$1: no \"$4\" in the summary" "$FX/summary"
  else ok "$1"; fi
}

what=$'## What and why\n\nThe pin moves to v1.5.3.'
how=$'## How it was verified\n\nRan the tests.'
by='Assisted-by: Claude:claude-opus-5-5'

echo "-- the fetch step"
setup "$what"$'\n\n'"$how"$'\n\nCloses #12\n\n'"$by" "12"
if grep -qF "/coolbress/plinth/$SHA/scripts/closing-references.sh" "$FX/curl" \
  && grep -qF "/coolbress/plinth/$SHA/scripts/closing-references.py" "$FX/curl"; then
  ok "both scripts are fetched at the workflow's own commit"
else no "the fetch does not ask for both scripts at $SHA" "$FX/curl"; fi
touch "$FX/curl_fails"
if PATH="$work/bin:$PATH" RUNNER_TEMP="$FX/temp2" PLINTH_SHA="$SHA" bash "$work/fetch.sh" >"$FX/fetch2.out" 2>&1; then
  no "a fetch that fails passes" "$FX/fetch2.out"
else ok "a fetch that fails fails the step"; fi
grep -qF 'PLINTH_SHA: ${{ job.workflow_sha }}' "$work/fetch.sh.step" \
  && ok "the fetch step's commit is job.workflow_sha" || no "the fetch step does not read job.workflow_sha" "$work/fetch.sh.step"
grep -qF 'if: ${{ !cancelled() }}' "$work/check.sh.step" && grep -qF 'FETCH: ${{ steps.fetch-closing.outcome }}' "$work/check.sh.step" \
  && ok "the check runs after a red title and after a failed fetch, and reads the fetch's outcome" \
  || no "the check step's if: or FETCH is not the one tested here" "$work/check.sh.step"

echo "-- a closing keyword in a sentence: fails, quoting the line"
setup "$what It is the second of the two fixes #65 decided to land before v1.0.0."$'\n\n'"$how"$'\n\n'"$by" "65"
run "\"the two fixes #65 decided\" fails the job" 1 "the two fixes #65 decided" "fail: PR description"
grep -qF 'the two fixes #65 decided' "$FX/summary" && ok "the summary quotes the line" || no "the summary does not quote the line" "$FX/summary"
if [ "$(grep -n '^- fail: PR description' "$FX/summary" | cut -d: -f1)" -lt "$(grep -n '^### What merging' "$FX/summary" | cut -d: -f1)" ] 2>/dev/null; then
  ok "the verdict line comes before the report"
else no "the verdict line is not before the report" "$FX/summary"; fi
grep -qE 'number=7( |$)' "$FX/calls" && grep -qE 'owner=coolbress( |$)' "$FX/calls" \
  && ok "it asks GitHub about this repository's #7" || no "the call does not name coolbress/plinth #7" "$FX/calls"
setup "$what This also closes #65, in passing."$'\n\n'"$how"$'\n\nCloses #12\n\n'"$by" "65 12"
run "a sentence closing #65 beside a closing line for #12" 1 "This also closes #65"

echo "-- a review's run reads the same pull request"
setup "$what It is the second of the two fixes #65 decided."$'\n\n'"$how"$'\n\n'"$by" "65" pull_request_review
run "the same description on pull_request_review still fails" 1 "the two fixes #65 decided" "fail: PR description"

echo "-- a closing line, or Part of: passes"
setup "$what"$'\n\n'"$how"$'\n\nCloses #12\n\n'"$by" "12"
run "\`Closes #12\` directly above the attribution" 0 "#12" "pass: PR description"
setup "$what"$'\n\n'"$how"$'\n\nPart of #12\n\n'"$by" ""
run "\`Part of #12\`, which closes nothing" 0 "no issue" "pass: PR description"
setup "$what The two fixes that #65 decided land here."$'\n\n'"$how"$'\n\nPart of #65\n\n'"$by" ""
run "the reworded sentence with \`Part of #65\`" 0 "" "pass: PR description"
grep -q 'fail:' "$FX/summary" && no "a pass wrote a fail line" "$FX/summary" || ok "a pass writes no fail line"

echo "-- not a pull request, or unreadable"
setup "" "" push; export PR=""
run "a push: passes as does not apply, no call to GitHub" 0 "no description" "pass: PR description, does not apply"
[ -s "$FX/calls" ] && no "a push called gh" "$FX/calls" || ok "a push asks GitHub nothing"
setup "$what"$'\n\n'"$how"$'\n\nCloses #12\n\n'"$by" "12"; echo 1 >"$FX/gh_rc"
run "GitHub cannot be read: fails" 1 "could not read" "fail: PR description"
setup "$what"$'\n\n'"$how"$'\n\nCloses #12\n\n'"$by" "12"; export FETCH=failure
run "a failed fetch: fails with its own line, no call to GitHub" 1 "" "fail: PR description, plinth's check could not be fetched"
[ -s "$FX/calls" ] && no "a failed fetch still called gh" "$FX/calls" || ok "a failed fetch asks GitHub nothing"

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
