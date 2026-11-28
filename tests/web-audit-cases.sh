#!/usr/bin/env bash
# `ci / web-audit` (#709): Lighthouse CI and axe-core on a web project's pages.
# It fails on a critical or serious violation of the WCAG 2.2 A and AA rules
# (#1149), the gate step's red, and on nothing else. The steps are not copied here; they are
# extracted from python-ci.yml and run as the runner runs them, so the rule
# tested is the rule shipped.
#
# Two parts:
# - The Verdict step on written results: what each outcome says, a known
#   violation named, the sentence that automated checks catch only part of
#   accessibility. Needs python3 only.
# - The audit step for real, in the pinned Chrome with the lockfile's tools,
#   on two pages served from here: one with known violations (an image
#   without alt text, a field without a label), one without. On Linux x64 the
#   workflow's own Node and Chrome steps install them; elsewhere set
#   WEB_AUDIT_CHROME to a Chrome for Testing and have node and npm on PATH.
#   Without them it stops: on CI that is a FAIL, never a skip; on a laptop it
#   says so and exits 0.
#
# The app image and its Postgres (the step before) need docker and are run by
# canary-web on every pull request, not here.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="$root/.github/workflows/python-ci.yml"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/web-audit.XXXXXX")" || { echo "web-audit-cases: could not make a temp folder" >&2; exit 1; }
srv=""
trap '[ -z "$srv" ] || { kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null; }; rm -rf "$tmp"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | tail -20 | sed 's/^/        | /'; }

# A step's `run: |` block, dedented, by job and step id or name.
job_step() {
  python3 - "$wf" "$1" "$2" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
job, name = sys.argv[2], sys.argv[3]
j = next((i for i, l in enumerate(lines) if l == f"  {job}:"), None)
end = next((i for i in range(j + 1, len(lines)) if lines[i][:3].strip() and lines[i].startswith("  ") and not lines[i].startswith("   ")), len(lines)) if j is not None else 0
at = next((i for i in range(j or 0, end) if lines[i].strip() in (f"- name: {name}", f"- id: {name}")), None)
if j is None or at is None:
    sys.exit(f"step not found: {job} / {name}")
i = next(k for k in range(at, end) if lines[k].strip() == "run: |")
indent = None
for l in lines[i + 1:end]:
    if l.strip() and indent is None:
        indent = len(l) - len(l.lstrip())
    if l.strip() and len(l) - len(l.lstrip()) < indent:
        break
    print(l[indent:] if l.strip() else "")
PY
}
fx="$root/tests/fixtures/web-audit"
for s in "Verdict:verdict" "Critical or serious accessibility violations (axe-core, WCAG 2.2 A and AA):gate" "Audit the pages:audit" "Install Node (official release, SHA256 verified):node" "Install Chrome for Testing (SHA256 verified):chrome"; do
  job_step web-audit "${s%%:*}" > "$tmp/${s##*:}.sh" || { echo "  FAIL  web-audit / ${s%%:*}: step not found in python-ci.yml"; exit 1; }
done
# A web-audit step's literal `env:` values as KEY=VALUE words: the pins the
# install steps check against, passed as the runner passes them.
step_env() {
  python3 -c '
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
j = lines.index("  web-audit:")
at = next(i for i in range(j, len(lines)) if lines[i].strip() == "- name: " + sys.argv[2])
e = next(i for i in range(at, len(lines)) if lines[i].strip() == "env:")
for l in lines[e + 1:]:
    m = re.match(r"^ {10}([A-Z0-9_]+): \"([^\"$ ]*)\"$", l)
    if not m:
        break
    print(m.group(1) + "=" + m.group(2))
' "$wf" "$1"
}

# One run of the Verdict step: the results are in $RUNNER_TEMP/web-audit, the
# outcomes in the environment (each `success` unless the case says otherwise).
verdict() { # case-dir [NAME=outcome ...]
  local d="$1"; shift
  : > "$d/summary"
  env WEB=true CHECKOUT=success APP=success NODE=success CHROME=success TOOLS=success AUDIT=success GATE=success \
    PLINTH_SHA=0123456789abcdef "$@" RUNNER_TEMP="$d" GITHUB_STEP_SUMMARY="$d/summary" bash "$tmp/verdict.sh" > "$d/stdout" 2>&1
  echo "exit $?" >> "$d/stdout"
}
# One run of the gate step on the same results: its exit, then the Verdict with that outcome.
gate() { # case-dir
  local d="$1" rc
  OUT="$d/web-audit" bash "$tmp/gate.sh" > "$d/gate.log" 2>&1; rc=$?
  echo "$rc" > "$d/gate.rc"
  [ "$rc" = 0 ] && verdict "$d" GATE=success || verdict "$d" GATE=failure
}
fresh() { local d="$tmp/c$((pass+fail))"; rm -rf "$d"; mkdir -p "$d/web-audit"; echo "$d"; }
pages() { # dir [no-login]
  python3 - "$1/web-audit/pages.json" "${2:-}" <<'PY'
import json, sys
home = {"page": "/", "who": "logged in", "url": "http://localhost:8000/", "headers": {}, "login": "/accounts/login/"}
if sys.argv[2]:
    home.update(who="not logged in", no_login="TypeError: create_user() missing 1 required positional argument: 'email'")
json.dump([home, {"page": "/accounts/login/", "who": "not logged in",
                  "url": "http://localhost:8000/accounts/login/", "headers": {}}], open(sys.argv[1], "w"))
PY
}
lhr() { # file accessibility
  printf '{"finalDisplayedUrl":"http://localhost:8000/","categories":{"accessibility":{"score":%s},"best-practices":{"score":1},"seo":{"score":0.9},"performance":{"score":0.97}}}' "$2" > "$1"
}
clean_axe() { printf '{"status":200,"violations":[],"incomplete":[],"rules":31}' > "$1"; }
bad_axe() {
  printf '%s' '{"status":200,"rules":30,"incomplete":[],"violations":[{"id":"image-alt","impact":"critical","help":"Images must have alternative text","helpUrl":"https://dequeuniversity.com/rules/axe/4.14/image-alt","nodes":1,"target":["img"]},{"id":"label","impact":"critical","help":"Form elements must have labels","helpUrl":"https://dequeuniversity.com/rules/axe/4.14/label","nodes":2,"target":["input[name=\"text\"]"]}]}' > "$1"
}
has() { grep -qF -- "$2" "$1"; }

echo "-- the job's shape"

# Never skipped, never red from what it finds: no job-level `if:`, and every
# step before the Verdict continues on error.
shape="$(python3 - "$wf" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read().split("\n")
j = text.index("  web-audit:")
end = next((i for i in range(j + 1, len(text)) if re.match(r"^  \S", text[i])), len(text))
job = text[j:end]
s = job.index("    steps:")
if any(re.match(r"^    if:", l) for l in job[:s]):
    print("a job-level if:")
steps, cur = [], None
for l in job[s + 1:]:
    if l.startswith("      - "):
        cur = [l]; steps.append(cur)
    elif cur is not None and (l.startswith("        ") or not l.strip()):
        cur.append(l)
for st in steps:
    name = next((re.sub(r"^\s*-?\s*(name|uses): ", "", l) for l in st if re.match(r"^\s*-?\s*(name|uses): ", l)), "?")
    if name == "Verdict":
        if not any(l.strip() == "if: ${{ !cancelled() }}" for l in st):
            print("the Verdict step does not run after a failed step")
    elif name.startswith("Critical or serious accessibility violations"):
        if any(l.strip() == "continue-on-error: true" for l in st):
            print("the gate step continues on error: a violation would not turn the job red")
    elif not any(l.strip() == "continue-on-error: true" for l in st):
        print(f"no continue-on-error: {name}")
PY
)"
if [ -z "$shape" ]; then ok "no job-level if:, every step but the gate continues on error, the gate does not, the Verdict runs after a failure"
else bad "the job's shape" "$shape"; fi

echo "-- the Verdict step on written results"

d="$(fresh)"; verdict "$d" WEB=false
if has "$d/summary" "pass: web-audit, does not apply (the web input is false: not a web project)" && has "$d/stdout" "exit 0" \
   && ! has "$d/stdout" "::warning::"; then ok "not a web project: a pass that does not apply, no warning"
else bad "not a web project" "$(cat "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; pages "$d"; lhr "$d/web-audit/0.lhr.json" 1; lhr "$d/web-audit/1.lhr.json" 0.95
clean_axe "$d/web-audit/0.axe.json"; clean_axe "$d/web-audit/1.axe.json"; verdict "$d"
if has "$d/summary" "pass: Lighthouse scored / (logged in): accessibility 100, best practices 100, seo 90, performance 97, out of 100; no score fails this job" \
   && has "$d/summary" "pass: no critical or serious violation of the WCAG 2.2 A and AA rules on /accounts/login/ (not logged in): axe-core found none (31 rules applied); automated rules catch only part of accessibility" \
   && has "$d/summary" "| \`/accounts/login/\` (not logged in) | 95 | 100 | 90 | 97 | 0 |" \
   && has "$d/summary" "Automated checks catch only part of accessibility:" \
   && ! has "$d/stdout" "::warning::" && has "$d/stdout" "exit 0" \
   && has "$d/stdout" "- pass: Lighthouse scored / (logged in)" && has "$d/stdout" "### Lighthouse and axe-core on the app's pages"; then
  ok "clean pages: the scores per page, a pass per page for axe-core, the limits of automated checks, no warning; the same text in the log"
else bad "clean pages" "$(cat "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; pages "$d"; lhr "$d/web-audit/0.lhr.json" 0.78; lhr "$d/web-audit/1.lhr.json" 1
bad_axe "$d/web-audit/0.axe.json"; clean_axe "$d/web-audit/1.axe.json"; gate "$d"
if [ "$(cat "$d/gate.rc")" = 1 ] \
   && has "$d/summary" "fail: no critical or serious violation of the WCAG 2.2 A and AA rules on / (logged in): axe-core found 2, image-alt on 1 element (critical: Images must have alternative text); label on 2 elements (critical: Form elements must have labels)" \
   && has "$d/summary" "#### What axe-core found on / (logged in)" \
   && has "$d/summary" "| [label](https://dequeuniversity.com/rules/axe/4.14/label) | critical | 2 | Form elements must have labels | \`input[name=\"text\"]\` |" \
   && has "$d/summary" "Automated checks catch only part of accessibility" && has "$d/stdout" "exit 0"; then
  ok "known critical violations: the gate step exits 1, the Verdict names each rule with its elements"
else bad "known violations" "$(cat "$d/gate.log" "$d/summary" "$d/stdout")"; fi

echo "-- the gate (#1149), on committed axe-core output"
# tests/fixtures/web-audit: serious.axe.json has a critical, a serious and a
# moderate violation; minor.axe.json a moderate and a minor one.
d="$(fresh)"; pages "$d"; lhr "$d/web-audit/0.lhr.json" 1; lhr "$d/web-audit/1.lhr.json" 1
cp "$fx/serious.axe.json" "$d/web-audit/0.axe.json"; cp "$fx/minor.axe.json" "$d/web-audit/1.axe.json"; gate "$d"
if [ "$(cat "$d/gate.rc")" = 1 ] && has "$d/gate.log" "2 critical or serious violation(s) of the WCAG A and AA rules" \
   && has "$d/summary" "fail: no critical or serious violation of the WCAG 2.2 A and AA rules on / (logged in): axe-core found 2, button-name on 1 element (critical: Buttons must have discernible text); color-contrast on 3 elements (serious:" \
   && ! grep -q "^- fail: .*meta-viewport" "$d/summary"; then
  ok "a critical and a serious violation: the gate step fails, and the fail line names those two and not the moderate one"
else bad "the gate on serious.axe.json" "$(cat "$d/gate.log" "$d/summary")"; fi
if has "$d/stdout" "::error title=ci / web-audit::no critical or serious violation of the WCAG 2.2 A and AA rules on / (logged in)" \
   && has "$d/stdout" "failed: no critical or serious violation of the WCAG 2.2 A and AA rules on / (logged in)" \
   && has "$d/stdout" "next: fix what axe-core names on / (logged in) (each rule's link in the job summary says how), and push" \
   && has "$d/stdout" "more: https://github.com/coolbress/plinth/blob/0123456789ab/docs/reference/required-checks.md#ci--web-audit" \
   && has "$d/stdout" "exit 0"; then
  ok "  in #1098's shape: one ::error titled ci / web-audit, then failed, next and more; the Verdict itself exits 0"
else bad "the failure block" "$(cat "$d/stdout")"; fi
if has "$d/summary" "pass: no critical or serious violation of the WCAG 2.2 A and AA rules on /accounts/login/ (not logged in): axe-core found none (64 rules applied); 2 moderate or minor, which fail nothing: meta-viewport on 1 element (moderate: Zooming and scaling must not be disabled); aria-deprecated-role on 1 element (minor: Deprecated ARIA roles must not be used)" \
   && has "$d/summary" "| [aria-deprecated-role](https://dequeuniversity.com/rules/axe/4.14/aria-deprecated-role) | minor | 1 |"; then
  ok "  and a page with only moderate and minor ones passes, listing them"
else bad "moderate and minor listed" "$(cat "$d/summary")"; fi

d="$(fresh)"; pages "$d"; lhr "$d/web-audit/0.lhr.json" 1; lhr "$d/web-audit/1.lhr.json" 1
cp "$fx/minor.axe.json" "$d/web-audit/0.axe.json"; cp "$fx/minor.axe.json" "$d/web-audit/1.axe.json"; gate "$d"
if [ "$(cat "$d/gate.rc")" = 0 ] && ! has "$d/summary" "fail:" && ! has "$d/stdout" "::error" && ! has "$d/stdout" "failed:" && has "$d/stdout" "exit 0"; then
  ok "only moderate and minor violations: the gate passes and nothing fails"
else bad "the gate on minor.axe.json" "$(cat "$d/gate.log" "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; pages "$d"; lhr "$d/web-audit/0.lhr.json" 0; lhr "$d/web-audit/1.lhr.json" 0
printf '{"finalDisplayedUrl":"http://localhost:8000/","categories":{"accessibility":{"score":0.12},"best-practices":{"score":0},"seo":{"score":0},"performance":{"score":0.01}}}' > "$d/web-audit/0.lhr.json"
clean_axe "$d/web-audit/0.axe.json"; clean_axe "$d/web-audit/1.axe.json"; gate "$d"
if [ "$(cat "$d/gate.rc")" = 0 ] && ! has "$d/summary" "fail:" && has "$d/summary" "accessibility 12, best practices 0, seo 0, performance 1, out of 100; no score fails this job"; then
  ok "no score fails the job: Performance 1 and Accessibility 12 with no axe-core violation pass"
else bad "a low score" "$(cat "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; pages "$d"; lhr "$d/web-audit/0.lhr.json" 1; lhr "$d/web-audit/1.lhr.json" 1
cp "$fx/serious.axe.json" "$d/web-audit/0.axe.json"; sed 's/"status":200/"status":500/' "$fx/serious.axe.json" > "$d/web-audit/0.axe.json"; clean_axe "$d/web-audit/1.axe.json"; gate "$d"
if [ "$(cat "$d/gate.rc")" = 0 ] && ! has "$d/summary" "fail:" && has "$d/summary" "not yet confirmed: axe-core on / (logged in). Why: the page answered HTTP 500"; then
  ok "violations on an error page fail nothing: the page was not read"
else bad "error page" "$(cat "$d/gate.log" "$d/summary")"; fi

d="$(fresh)"; pages "$d"; lhr "$d/web-audit/0.lhr.json" 1; lhr "$d/web-audit/1.lhr.json" 1
clean_axe "$d/web-audit/0.axe.json"; clean_axe "$d/web-audit/1.axe.json"; verdict "$d" GATE=failure
if has "$d/summary" "fail: no critical or serious violation of the WCAG 2.2 A and AA rules: the gate step failed on results this step could not read" \
   && has "$d/stdout" "next: read the gate step's log, fix what it names, and push"; then
  ok "a gate that failed on results the Verdict does not read as a violation: still a fail line, never a pass alone"
else bad "gate failed, nothing read" "$(cat "$d/summary" "$d/stdout")"; fi

# The tags axe-core runs, pinned (#1149): WCAG 2.0, 2.1 and 2.2 A and AA, no best-practice.
if grep -qF 'const tags = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"];' "$tmp/audit.sh" \
   && grep -qF 'window.axe.run(document, { runOnly: { type: "tag", values } }), tags)' "$tmp/audit.sh" \
   && ! grep -qF '"best-practice"' "$tmp/audit.sh"; then
  ok "axe-core runs only the wcag2a, wcag2aa, wcag21a, wcag21aa and wcag22aa rules"
else bad "the runOnly tags" "$(grep -n 'tags\|axe.run' "$tmp/audit.sh")"; fi

# The manual checklist, each item with its success criteria (#1149).
d="$(fresh)"; pages "$d"; lhr "$d/web-audit/0.lhr.json" 1; lhr "$d/web-audit/1.lhr.json" 1
clean_axe "$d/web-audit/0.axe.json"; clean_axe "$d/web-audit/1.axe.json"; verdict "$d"
miss=""
for c in "keyboard alone, and nothing traps focus (2.1.1, 2.1.2)" "not hidden under a sticky header or banner (2.4.7, 2.4.11)" \
         "pasting and password managers (3.3.8)" "names the field and the fix (3.3.1, 3.3.3)" "320 CSS pixels wide (1.4.4, 1.4.10)" \
         "matches the page's language (3.1.1)" "same place on every page (3.2.6)" "asked for again in one flow (3.3.7)"; do
  grep -qF -- "- " "$d/summary" && grep -F -- "$c" "$d/summary" | grep -q '^- ' || miss="$miss | $c"
done
if [ -z "$miss" ]; then ok "the summary's manual checklist names each item's WCAG success criteria"
else bad "checklist items missing:$miss" "$(cat "$d/summary")"; fi

d="$(fresh)"; pages "$d"
printf '{"runtimeError":{"code":"ERRORED_DOCUMENT_REQUEST","message":"Lighthouse was unable to reliably load the page you requested. (Status code: 500)"}}' > "$d/web-audit/0.lhr.json"
printf '{"error":"lhci collect exited 1"}' > "$d/web-audit/1.lhr.error.json"
printf '{"status":500,"violations":[],"incomplete":[],"rules":5}' > "$d/web-audit/0.axe.json"
printf '{"error":"TimeoutError: Navigation timeout of 60000 ms exceeded"}' > "$d/web-audit/1.axe.error.json"
verdict "$d"
if has "$d/summary" "not yet confirmed: Lighthouse's scores for / (logged in). Why: Lighthouse was unable to reliably load the page you requested. (Status code: 500). What confirms it: a run where Lighthouse loads the page." \
   && has "$d/summary" "not yet confirmed: Lighthouse's scores for /accounts/login/ (not logged in). Why: lhci collect exited 1. What" \
   && has "$d/summary" "not yet confirmed: axe-core on / (logged in). Why: the page answered HTTP 500, so the audit read an error page. What" \
   && ! has "$d/summary" "pass: axe-core" \
   && has "$d/summary" "not yet confirmed: axe-core on /accounts/login/ (not logged in). Why: TimeoutError: Navigation timeout of 60000 ms exceeded. What" \
   && ! has "$d/summary" "pass: Lighthouse" && has "$d/stdout" "exit 0"; then
  ok "a page Lighthouse or axe-core could not read, or that answered an error: not yet confirmed, never a pass"
else bad "unreadable pages" "$(cat "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; pages "$d"; lhr "$d/web-audit/1.lhr.json" 1; clean_axe "$d/web-audit/1.axe.json"
printf '{"finalDisplayedUrl":"http://localhost:8000/","categories":{"accessibility":{"score":null},"best-practices":{"score":1},"seo":{"score":1},"performance":{"score":null}}}' > "$d/web-audit/0.lhr.json"
printf '{"status":404,"violations":[{"id":"image-alt","impact":"critical","help":"Images must have alternative text","helpUrl":"u","nodes":1,"target":["img"]}],"incomplete":[],"rules":5}' > "$d/web-audit/0.axe.json"
verdict "$d"
if has "$d/summary" "not yet confirmed: Lighthouse's scores for / (logged in). Why: its report has no score for Accessibility, Performance. What" \
   && has "$d/summary" "not yet confirmed: axe-core on / (logged in). Why: the page answered HTTP 404" \
   && ! has "$d/summary" "pass: Lighthouse scored / (logged in)" && ! has "$d/summary" "image-alt" \
   && has "$d/summary" "| \`/\` (logged in) | ? | 100 | 100 | ? | ? |"; then
  ok "a report missing a score, or an error page with violations: not yet confirmed, no pass and no violations from the error page"
else bad "missing score or error page" "$(cat "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; pages "$d" no-login; lhr "$d/web-audit/0.lhr.json" 1; lhr "$d/web-audit/1.lhr.json" 1
clean_axe "$d/web-audit/0.axe.json"; clean_axe "$d/web-audit/1.axe.json"; verdict "$d"
if has "$d/summary" "not yet confirmed: / as a logged-in person. Why: the audit could not log a person in (TypeError: create_user() missing 1 required positional argument: 'email'), so / was audited as a visitor who is not logged in. What" \
   && has "$d/summary" "pass: Lighthouse scored / (not logged in)"; then
  ok "no log-in possible: / is audited as a visitor, and the summary says the logged-in page was not"
else bad "no log-in" "$(cat "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; pages "$d"; lhr "$d/web-audit/1.lhr.json" 1; clean_axe "$d/web-audit/1.axe.json"
printf '{"finalDisplayedUrl":"http://localhost:8000/accounts/login/?next=/","categories":{"accessibility":{"score":0.88},"best-practices":{"score":1},"seo":{"score":0.9},"performance":{"score":1}}}' > "$d/web-audit/0.lhr.json"
printf '{"status":200,"url":"http://localhost:8000/accounts/login/?next=/","violations":[{"id":"html-has-lang","impact":"serious","help":"<html> element must have a lang attribute","helpUrl":"https://dequeuniversity.com/rules/axe/4.14/html-has-lang","nodes":1,"target":["html"]}],"incomplete":[],"rules":20}' > "$d/web-audit/0.axe.json"
verdict "$d"
if has "$d/summary" "not yet confirmed: / as a logged-in person. Why: the audit's session did not hold and the page sent it to /accounts/login/, so the results above for / (logged in) are the log-in page's. What" \
   && has "$d/summary" "after a redirect to http://localhost:8000/accounts/login/?next=/" \
   && has "$d/summary" "(serious: \`<html>\` element must have a lang attribute)" \
   && has "$d/summary" "| \`<html>\` element must have a lang attribute |" \
   && ! has "$d/summary" "/accounts/login/ (not logged in), the audit's session" \
   && ! grep -q "^- fail: .* on / (logged in)" "$d/summary"; then
  ok "a session that did not hold: the logged-in page's results are said to be the log-in page's; markup in a rule's help is quoted"
else bad "session did not hold" "$(cat "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; echo "there is no Dockerfile in the project" > "$d/web-audit/app.why"; verdict "$d" APP=failure AUDIT=skipped
if has "$d/summary" "not yet confirmed: the pages' audit. Why: the app image did not start: there is no Dockerfile in the project. What confirms it: a run that gets past it." \
   && has "$d/stdout" "::warning::" && ! has "$d/summary" "pass:" && ! has "$d/summary" "Automated checks" && has "$d/stdout" "exit 0"; then
  ok "the app did not start: one not-yet-confirmed line with the reason, never a pass"
else bad "app did not start" "$(cat "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; pages "$d"; verdict "$d" CHROME=failure TOOLS=failure AUDIT=skipped
if has "$d/summary" "not yet confirmed: the pages' audit. Why: Chrome for Testing and Lighthouse CI and axe-core did not install" && ! has "$d/summary" "pass:"; then
  ok "a tool that did not install: named, never a pass"
else bad "tool install failed" "$(cat "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; pages "$d"; verdict "$d" AUDIT=failure
if has "$d/summary" "not yet confirmed: the pages' audit. Why: the audit did not finish (its log says why)" && ! has "$d/summary" "pass:"; then
  ok "an audit that crashed: not yet confirmed, never a pass"
else bad "audit crashed" "$(cat "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; pages "$d"; verdict "$d"
if has "$d/summary" "not yet confirmed: Lighthouse's scores for / (logged in). Why: it wrote no report" \
   && has "$d/summary" "not yet confirmed: axe-core on / (logged in). Why: it wrote no report" && ! has "$d/summary" "pass:"; then
  ok "an audit step that succeeded but wrote nothing: not yet confirmed per page, never a pass"
else bad "audit wrote nothing" "$(cat "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; verdict "$d" CHECKOUT=failure APP=skipped AUDIT=skipped
if has "$d/summary" "not yet confirmed: the pages' audit. Why: the checkout did not finish" && has "$d/stdout" "exit 0"; then
  ok "a failed checkout: not yet confirmed, and the job still passes"
else bad "checkout failed" "$(cat "$d/summary" "$d/stdout")"; fi

echo "-- the audit step for real, on a page with known violations and one without"

started=$SECONDS
live_skip() {
  if [ -n "${CI:-}" ]; then bad "the live audit did not run: $1"; else echo "  SKIP  the live audit: $1"; fi
}
tools="$tmp/web-audit-tools"
ready=
if [ "$(uname -s)-$(uname -m)" = Linux-x86_64 ]; then
  # The workflow's own install steps, as the runner runs them.
  : > "$tmp/path"; : > "$tmp/env"
  node_env="$(step_env "Install Node (official release, SHA256 verified)")"
  chrome_env="$(step_env "Install Chrome for Testing (SHA256 verified)")"
  # shellcheck disable=SC2086 # one KEY=VALUE word per pin
  if env $node_env RUNNER_TEMP="$tmp" GITHUB_PATH="$tmp/path" bash "$tmp/node.sh" > "$tmp/node.log" 2>&1 \
     && env $chrome_env RUNNER_TEMP="$tmp" GITHUB_ENV="$tmp/env" bash "$tmp/chrome.sh" > "$tmp/chrome.log" 2>&1; then
    PATH="$(cat "$tmp/path"):$PATH"; export "$(grep '^WEB_AUDIT_CHROME=' "$tmp/env")"
    ready=1
  else
    bad "the workflow's Node or Chrome step failed" "$(cat "$tmp/node.log" "$tmp/chrome.log" 2>/dev/null)"
  fi
elif [ -n "${WEB_AUDIT_CHROME:-}" ] && command -v node >/dev/null && command -v npm >/dev/null; then
  ready=1
else
  live_skip "not Linux x64, and WEB_AUDIT_CHROME, node or npm is not set here"
fi

if [ -n "$ready" ]; then
  # The lockfile from this checkout, installed as the tools step installs the
  # one it fetches.
  mkdir -p "$tools"; cp "$root/scripts/web-audit/package.json" "$root/scripts/web-audit/package-lock.json" "$tools/"
  if ! (cd "$tools" && npm ci --ignore-scripts --no-audit --no-fund) > "$tmp/npm.log" 2>&1; then
    bad "npm ci on scripts/web-audit's lockfile failed" "$(cat "$tmp/npm.log")"; ready=
  fi
fi

if [ -n "$ready" ]; then
  site="$tmp/site"; mkdir -p "$site/known"
  # Two known violations: `image-alt` and `label`.
  cat > "$site/known/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Known violations</title></head>
<body><main><h1>Known violations</h1>
<img src="data:image/gif;base64,R0lGODlhAQABAAAAACw=" width="10" height="10">
<form><input name="text"> <button>Add</button></form>
</main></body>
</html>
HTML
  cat > "$site/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Clean</title>
<meta name="description" content="A page with no known violation"></head>
<body><main><h1>Clean</h1>
<img src="data:image/gif;base64,R0lGODlhAQABAAAAACw=" width="10" height="10" alt="A dot">
<form><label for="t">Text</label> <input id="t" name="text"> <button>Add</button></form>
</main></body>
</html>
HTML
  port="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$site" > "$tmp/http.log" 2>&1 & srv=$!
  for _ in $(seq 30); do curl -fs -o /dev/null "http://127.0.0.1:$port/" && break; sleep 0.2; done
  d="$(fresh)"
  python3 - "$d/web-audit/pages.json" "$port" <<'PY'
import json, sys
u = f"http://127.0.0.1:{sys.argv[2]}"
json.dump([{"page": "/known/", "who": "not logged in", "url": f"{u}/known/", "headers": {"X-Forwarded-Proto": "https"}},
           {"page": "/", "who": "not logged in", "url": f"{u}/", "headers": {"X-Forwarded-Proto": "https"}}],
          open(sys.argv[1], "w"))
PY
  t0=$SECONDS
  TOOLS="$tools" OUT="$d/web-audit" bash "$tmp/audit.sh" > "$d/audit.log" 2>&1; rc=$?
  audit_s=$((SECONDS - t0))
  gate "$d"
  if [ "$rc" = 0 ] && [ "$(cat "$d/gate.rc")" = 1 ] \
     && grep -qE "^- fail: no critical or serious violation of the WCAG 2.2 A and AA rules on /known/ \(not logged in\): axe-core found [0-9]+, .*image-alt on 1 element" "$d/summary" \
     && grep -qE "^- fail: .* on /known/ .*label on 1 element" "$d/summary" \
     && has "$d/stdout" "::error title=ci / web-audit::" \
     && grep -qE "^- pass: no critical or serious violation of the WCAG 2.2 A and AA rules on / \(not logged in\): axe-core found none \([0-9]+ rules applied\)" "$d/summary" \
     && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(d.get("tags") != ["wcag2a","wcag2aa","wcag21a","wcag21aa","wcag22aa"])' "$d/web-audit/1.axe.json" \
     && grep -qE "^- pass: Lighthouse scored /known/ \(not logged in\): accessibility [0-9]+, best practices [0-9]+, seo [0-9]+, performance [0-9]+, out of 100" "$d/summary" \
     && grep -qE "^- pass: Lighthouse scored / \(not logged in\): accessibility 100," "$d/summary" \
     && has "$d/summary" "Automated checks catch only part of accessibility:" && has "$d/stdout" "exit 0"; then
    ok "the pinned Chrome, Lighthouse CI and axe-core fail the known page on image-alt and label, and pass the clean page, with the WCAG tags (audit ${audit_s}s)"
  else
    bad "the live audit" "$(tail -30 "$d/audit.log"; cat "$d/summary" "$d/stdout")"
  fi
  sed -n 's/^- //p' "$d/summary" | sed 's/^/        > /'
  echo "  time: ${audit_s}s to audit two pages, $((SECONDS - started))s with the installs"
fi

# Every not yet confirmed line any case above wrote, in #1156's form (#1100):
# what. Why: reason. What confirms it: run.
nyc="$(cat "$tmp"/c*/summary 2>/dev/null | sed -n 's/^- \(not yet confirmed: .*\)$/\1/p')"
off="$(grep -vE '^not yet confirmed: .+\. Why: .+\. What confirms it: .+\.$' <<<"$nyc" | grep -v '^$' || true)"
if [ -n "$nyc" ] && [ -z "$off" ]; then ok "every not yet confirmed line ($(grep -c . <<<"$nyc")) says what, why and what confirms it"
else bad "not yet confirmed lines not in the form, or none read" "$off"; fi

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
