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
step "Check the title" "$work/title.sh" \
  || { echo "  FAIL  the title step is not in python-ci.yml's pr-title job"; exit 1; }
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
  # The highest issue and pull request numbers (#826): $FX/highest.json, or
  # $FX/highest_rc failing the call; any other query is the description's.
  "api graphql") if [[ "$*" == *"pullRequests(first: 1"* ]]; then
      [ -f "$FX/highest_rc" ] && { echo "HTTP 403: Resource not accessible by integration" >&2; exit "$(cat "$FX/highest_rc")"; }
      cat "$FX/highest.json"; exit 0
    fi
    cat "$FX/response.json"; exit "$(cat "$FX/gh_rc" 2>/dev/null || echo 0)" ;;
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
  # This repository's newest issue is #40 and its newest pull request #41.
  echo '{"data":{"repository":{"issues":{"nodes":[{"number":40}]},"pullRequests":{"nodes":[{"number":41}]}}}}' >"$FX/highest.json"
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

echo "-- the title: GitHub's own revert title (#839)"
# title_is <label> <want exit> <title> [the output has this] [the summary has this]
title_is() {
  local rc; : >"$work/title.sum"
  GITHUB_STEP_SUMMARY="$work/title.sum" TITLE="$3" bash "$work/title.sh" >"$work/title.out" 2>&1; rc=$?
  if [ "$rc" != "$2" ]; then no "$1: exit $rc, want $2" "$work/title.out"
  elif [ -n "${4:-}" ] && ! grep -qF -- "$4" "$work/title.out"; then no "$1: no \"$4\" in the output" "$work/title.out"
  elif [ -n "${5:-}" ] && ! grep -qF -- "$5" "$work/title.sum"; then no "$1: no \"$5\" in the summary" "$work/title.sum"
  else ok "$1"; fi
}
form='Revert "type(scope): summary"'
title_is "a revert of a valid title passes" 0 'Revert "feat(x): y"' "" "pass: PR title follows the convention"
title_is "a revert of a breaking title passes" 0 'Revert "feat(api)!: y"'
title_is "a revert of a revert of a valid title passes" 0 'Revert "Revert "feat: y""'
title_is "three reverts deep passes" 0 'Revert "Revert "Revert "feat: y"""'
title_is "a revert of a title with quotes in it passes" 0 'Revert "fix: say "hi" twice"'
title_is "a revert of an invalid title fails, naming the form that passes" 1 'Revert "fix stuff"' "$form" "fail: PR title, it is not Conventional Commits"
title_is "... and the summary names it too" 1 'Revert "fix stuff"' "" "$form"
title_is "a revert of an invented type fails" 1 'Revert "research: a note"' "$form"
title_is "a revert of a revert of an invalid title fails" 1 'Revert "Revert "fix stuff""' "$form"
title_is "an empty revert fails" 1 'Revert ""' "$form"
title_is "a revert of an empty revert fails" 1 'Revert "Revert """' "$form"
title_is "no closing quote fails" 1 'Revert "feat: y' "$form"
title_is "a closing quote missing inside a nested revert fails" 1 'Revert "Revert "feat: y"' "$form"
title_is "words after the closing quote fail" 1 'Revert "feat: y" and more' "$form"
title_is "the (#N) suffix rule still holds inside the quotes" 1 'Revert "fix: x (#12)"' "$form" "fail: PR title, it ends in a number"
title_is "... and its summary names the form that passes" 1 'Revert "fix: x (#12)"' "" "$form"
title_is "... and after them" 1 'Revert "fix: x" (#12)' "$form"
title_is "\"Revert\" with no quotes is still free form" 1 'Revert feat: y' "Rewrite it as type(scope): summary"
title_is "lowercase \"revert\" with quotes is still free form" 1 'revert "feat: y"' "Rewrite it as type(scope): summary"
title_is "the conventional revert: title still passes" 0 'revert: undo the thing'
title_is "a plain title that fails does not offer the revert form" 1 'fix stuff' "Rewrite it as type(scope): summary"

echo "-- the label for a revert title (#839): pr-label.yml's step, run with a fake gh"
python3 - "$root/.github/workflows/pr-label.yml" "$work/label.sh" <<'PY2'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
r = next(i for i, l in enumerate(lines) if l.strip() == "run: |")
deep = len(lines[r]) - len(lines[r].lstrip())
body = []
for l in lines[r + 1:]:
    if l.strip() and len(l) - len(l.lstrip()) <= deep:
        break
    body.append(l[deep + 2:])
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(body).rstrip() + "\n")
PY2
mkdir -p "$work/labelbin"
cat >"$work/labelbin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view") exit 0 ;;
  "pr edit") printf '%s\n' "$*" >>"$LABEL_CALLS" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$work/labelbin/gh"
# labels <label> <title> <the label it adds, or nothing>
labels() {
  LABEL_CALLS="$work/label.calls"; export LABEL_CALLS; : >"$LABEL_CALLS"
  if ! PATH="$work/labelbin:$PATH" TITLE="$2" NUMBER=7 REPO=o/r IS_FORK=false bash "$work/label.sh" >"$work/label.out" 2>&1; then no "$1: the step failed" "$work/label.out"
  elif [ -z "$3" ] && [ -s "$LABEL_CALLS" ]; then no "$1: it added a label" "$LABEL_CALLS"
  elif [ -n "$3" ] && ! grep -qF -- "--add-label $3" "$LABEL_CALLS"; then no "$1: no label $3" "$work/label.out" "$LABEL_CALLS"
  else ok "$1"; fi
}
labels "a revert title GitHub writes is labelled revert" 'Revert "feat(x): y"' revert
labels "a nested one too" 'Revert "Revert "feat: y""' revert
labels "revert: summary still is" 'revert: undo it' revert
labels "feat: summary still is feat" 'feat: y' feat
labels "a free-form title gets none" 'Revert the thing' ""

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

echo "-- what the person checked and which review ran (#810): a warning, never a red"
grep -qF "/coolbress/plinth/$SHA/scripts/description-fields.py" "$FX/curl" \
  && ok "the fields check is fetched at the workflow's own commit too" || no "description-fields.py is not fetched at $SHA" "$FX/curl"
checked=$'## What I checked myself\n\nOpened the preview: the new heading shows, and `make check` printed 12 passed.'
# fields <label> <checked section> <review line>: closes nothing, so only the fields can warn.
fields() { setup "$what"$'\n\n'"$2"$'\n\n'"$how"$'\n\n'"$3"$'\n\nPart of #12\n\n'"$by" ""; run "$1" 0; }
quiet() { # no warning and both pass lines
  if grep -q 'not yet confirmed' "$FX/summary" || grep -q '::warning::' "$FX/out"; then no "$1: it warned" "$FX/out" "$FX/summary"
  elif grep -qF 'pass: PR description, says what the person checked themselves' "$FX/summary" \
    && grep -qF 'pass: PR description, says which review ran' "$FX/summary"; then ok "$1: no warning, two pass lines"
  else no "$1: the two pass lines are missing" "$FX/summary"; fi
}
warns() { # <label> <field words> <what the summary also says>: a ::warning:: and a not yet confirmed line naming the field
  if grep -qF "::warning::not yet confirmed: PR description, $2" "$FX/out" \
    && grep -qF -- "- not yet confirmed: PR description, $2" "$FX/summary" && grep -qF -- "$3" "$FX/summary"; then ok "$1"
  else no "$1: no warning for \"$2\" saying \"$3\"" "$FX/out" "$FX/summary"; fi
}
fields "filled: what was opened and what it showed, a fresh-context review" "$checked" 'Review: fresh-context'
quiet "filled"
fields "skipped with a reason, no review with a reason" $'## What I checked myself\n\nSkipped: a typo fix in a comment, nothing to open.' 'Review: none (a one-word typo)'
quiet "Skipped: <reason>"
fields "a third-party review named" "$checked" 'Review: third-party (Codex)'
quiet "third-party (<name>)"
fields "empty: the template's comment left alone, no Review line" $'## What I checked myself\n\n<!-- What you ran, opened or read, and what you saw. -->' ''
warns "an empty section warns, saying how to fill it or skip it" "does not say what the person checked themselves" "Skipped: <reason>"
warns "a missing Review line warns, naming the four answers" "does not say which review ran" "fresh-context | third-party (<name>) | same-session (not independent) | none (<reason>)"
fields "bare \"done\" in both" $'## What I checked myself\n\nDone.' 'Review: done'
warns "\"done\" alone in the section warns" "does not say what the person checked themselves" "\"done\""
warns "\"Review: done\" warns" "does not say which review ran" "Review:"
fields "\"Skipped:\" with no reason, \"none\" with no reason" $'## What I checked myself\n\nSkipped:' 'Review: none'
warns "\"Skipped:\" alone warns" "does not say what the person checked themselves" "Skipped: <reason>"
warns "\"Review: none\" alone warns" "does not say which review ran" "none (<reason>)"
fields "the form's four answers left as they are, \"third-party\" with no name" $'## What I checked myself\n\n- [x] done' 'Review: fresh-context | third-party (<name>) | same-session (not independent) | none (<reason>)'
warns "\"- [x] done\" warns" "does not say what the person checked themselves" "says only \"- [x] done\""
warns "the four answers copied from the form warn" "does not say which review ran" "line says \"fresh-context | thir\""
for r in 'third-party' 'none (<reason>)' 'none of the findings were fixed'; do
  fields "Review: $r" "$checked" "Review: $r"; warns "\"Review: $r\" warns" "does not say which review ran" "Review:"
done
fields "a heading with a colon, a same-session review" $'## What I checked myself:\n\nRan make check: 12 passed.' 'Review: same-session (not independent)'
quiet "\"## What I checked myself:\""
fields "\"done\" over two lines" $'## What I checked myself\n\nDone\n.' 'Review: fresh-context'
if [ "$(grep -c 'does not say what the person checked' "$FX/summary")" = 1 ] && ! grep -q '^- \.' "$FX/summary"; then ok "a quote over two lines stays one verdict line"
else no "a quote over two lines split the verdict line" "$FX/summary"; fi
fields "the fields script crashes" "$checked" 'Review: fresh-context'
echo 'raise SystemExit("boom")' >"$FX/temp/plinth-closing/description-fields.py"; run "a crashed fields script: the job still passes" 0
warns "... and says the fields were not read" "the fields were not read" "re-run this job"
setup "$what"$'\n\n'"$how"$'\n\n'"$by" ""
run "a description without either field still passes" 0 "" "pass: PR description, merging it closes"
warns "without the section it warns" "does not say what the person checked themselves" "What I checked myself"
setup "$what It is the second of the two fixes #65 decided."$'\n\n'"$checked"$'\n\nReview: fresh-context\n\n'"$by" "65"
run "a red closing check still writes the fields' lines" 1 "" "pass: PR description, says which review ran"

echo "-- a bare #N above the highest issue or pull request number (#826): a warning, never a red"
filled="$checked"$'\n\nReview: fresh-context'
numbers() { setup "$what $1"$'\n\n'"$filled"$'\n\nPart of #12\n\n'"$by" ""; run "$2" 0; }
nowarn() { # <label>: no warning about a number, and the fields' two pass lines are there
  if grep -q 'above the highest' "$FX/out" "$FX/summary"; then no "$1: it warned about a number" "$FX/out" "$FX/summary"
  else quiet "$1"; fi
}
numbers "The pin follows #457 in the template." "a bare #457 above #41: the job passes"
if grep -qF '::warning::not yet confirmed: PR description, #457 is above the highest issue or pull request number here (#41)' "$FX/out" \
  && grep -qF 'owner/repo#N' "$FX/out"; then ok "... with a warning naming #457 and the owner/repo#N form"
else no "no warning names #457 and owner/repo#N" "$FX/out" "$FX/summary"; fi
grep -qF -- '- not yet confirmed: PR description, #457 is above' "$FX/summary" && ok "... and its line in the summary" || no "the summary has no line for #457" "$FX/summary"
numbers "It follows #457, as #457 and #500 said." "two numbers above, one twice"
[ "$(grep -c '::warning::not yet confirmed: PR description, #457 is above' "$FX/out")" = 1 ] && grep -qF '#500 is above' "$FX/out" \
  && ok "one warning per reference: #457 once, #500 once" || no "not one warning per reference" "$FX/out"
numbers "It follows coolbress/plinth-template#457 and plinth-template#81." "owner/repo#N and repo#N"
nowarn "owner/repo#N and repo#N"
numbers "Run \`gh issue view #457\` and see the fence."$'\n\n```\nCloses #500\n```' "inside a code span and a fenced block"
nowarn "#457 in a code span, #500 in a fenced block"
numbers "See [#457](https://github.com/coolbress/plinth-template/issues/457), <https://example.com/x#500> and https://example.com/a#600." "inside links"
nowarn "#457 as a link's text, #500 and #600 in URLs"
numbers "It follows #40 and #41, and &#457; is an entity." "the highest numbers themselves, and an HTML entity"
nowarn "#40 and #41, which the repository has"
numbers "Nothing to number here." "a description with no number"
nowarn "a description with no number"
numbers "<!-- #457 in a comment -->It follows #12." "a number in an HTML comment"
nowarn "#457 in an HTML comment"
setup "$what It follows #457."$'\n\n'"$filled"$'\n\nPart of #12\n\n'"$by" ""; echo 1 >"$FX/highest_rc"
run "the highest number cannot be read: the job passes" 0 "the highest issue or pull request number could not be read"
[ "$(grep -c 'could not be read' "$FX/out")" = 1 ] && ok "... saying why in one line" || no "not one line saying why" "$FX/out"
nowarn "... and warning nothing about #457"
setup "$what It follows #457."$'\n\n'"$filled"$'\n\nPart of #12\n\n'"$by" ""; echo '{"errors":[{"message":"x"}]}' >"$FX/highest.json"
run "an answer without the numbers: the job passes" 0 "the highest issue or pull request number could not be read"
nowarn "... and warning nothing"
setup "$what It follows #457."$'\n\n'"$filled"$'\n\nPart of #12\n\n'"$by" ""
echo 'raise SystemExit("boom")' >"$FX/temp/plinth-closing/description-fields.py"; run "a crashed fields script with a bare #457: the job still passes" 0

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
