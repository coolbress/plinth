#!/usr/bin/env bash
# `ci / web-audit` (#709): Lighthouse CI and axe-core on a web project's pages,
# reported and never failing. The steps are not copied here; they are
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

tmp="$(mktemp -d "${TMPDIR:-/tmp}/web-audit.XXXXXX")"
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
for s in "Verdict:verdict" "Audit the pages:audit" "Install Node (official release, SHA256 verified):node" "Install Chrome for Testing (SHA256 verified):chrome"; do
  job_step web-audit "${s%%:*}" > "$tmp/${s##*:}.sh" || { echo "  FAIL  web-audit / ${s%%:*}: step not found in python-ci.yml"; exit 1; }
done

# One run of the Verdict step: the results are in $RUNNER_TEMP/web-audit, the
# outcomes in the environment (each `success` unless the case says otherwise).
verdict() { # case-dir [NAME=outcome ...]
  local d="$1"; shift
  : > "$d/summary"
  env WEB=true CHECKOUT=success APP=success NODE=success CHROME=success TOOLS=success AUDIT=success \
    "$@" RUNNER_TEMP="$d" GITHUB_STEP_SUMMARY="$d/summary" bash "$tmp/verdict.sh" > "$d/stdout" 2>&1
  echo "exit $?" >> "$d/stdout"
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
    elif not any(l.strip() == "continue-on-error: true" for l in st):
        print(f"no continue-on-error: {name}")
PY
)"
if [ -z "$shape" ]; then ok "no job-level if:, every step before the Verdict continues on error, the Verdict runs after a failure"
else bad "the job's shape" "$shape"; fi

echo "-- the Verdict step on written results"

d="$(fresh)"; verdict "$d" WEB=false
if has "$d/summary" "pass: web-audit, does not apply (the web input is false: not a web project)" && has "$d/stdout" "exit 0" \
   && ! has "$d/stdout" "::warning::"; then ok "not a web project: a pass that does not apply, no warning"
else bad "not a web project" "$(cat "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; pages "$d"; lhr "$d/web-audit/0.lhr.json" 1; lhr "$d/web-audit/1.lhr.json" 0.95
clean_axe "$d/web-audit/0.axe.json"; clean_axe "$d/web-audit/1.axe.json"; verdict "$d"
if has "$d/summary" "pass: Lighthouse scored / (logged in): accessibility 100, best practices 100, seo 90, performance 97, out of 100; no score is judged yet" \
   && has "$d/summary" "pass: axe-core's automated rules found no accessibility violation on /accounts/login/ (not logged in) (31 rules applied); they catch only part of accessibility" \
   && has "$d/summary" "| \`/accounts/login/\` (not logged in) | 95 | 100 | 90 | 97 | 0 |" \
   && has "$d/summary" "Automated checks catch only part of accessibility." \
   && ! has "$d/stdout" "::warning::" && has "$d/stdout" "exit 0" \
   && has "$d/stdout" "- pass: Lighthouse scored / (logged in)" && has "$d/stdout" "### Lighthouse and axe-core on the app's pages"; then
  ok "clean pages: the scores per page, a pass per page for axe-core, the limits of automated checks, no warning; the same text in the log"
else bad "clean pages" "$(cat "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; pages "$d"; lhr "$d/web-audit/0.lhr.json" 0.78; lhr "$d/web-audit/1.lhr.json" 1
bad_axe "$d/web-audit/0.axe.json"; clean_axe "$d/web-audit/1.axe.json"; verdict "$d"
if has "$d/summary" "not yet confirmed: no accessibility violation axe-core's automated rules find on / (logged in), it found 2: image-alt on 1 element (critical: Images must have alternative text); label on 2 elements (critical: Form elements must have labels); fixing them confirms it" \
   && has "$d/stdout" "::warning::not yet confirmed: no accessibility violation axe-core's automated rules find on / (logged in)" \
   && has "$d/summary" "#### What axe-core found on / (logged in)" \
   && has "$d/summary" "| [label](https://dequeuniversity.com/rules/axe/4.14/label) | critical | 2 | Form elements must have labels | \`input[name=\"text\"]\` |" \
   && has "$d/summary" "Automated checks catch only part of accessibility." && has "$d/stdout" "exit 0"; then
  ok "known violations: each rule named with its elements, in the summary and as a warning, and the job still passes"
else bad "known violations" "$(cat "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; pages "$d"
printf '{"runtimeError":{"code":"ERRORED_DOCUMENT_REQUEST","message":"Lighthouse was unable to reliably load the page you requested. (Status code: 500)"}}' > "$d/web-audit/0.lhr.json"
printf '{"error":"lhci collect exited 1"}' > "$d/web-audit/1.lhr.error.json"
printf '{"status":500,"violations":[],"incomplete":[],"rules":5}' > "$d/web-audit/0.axe.json"
printf '{"error":"TimeoutError: Navigation timeout of 60000 ms exceeded"}' > "$d/web-audit/1.axe.error.json"
verdict "$d"
if has "$d/summary" "not yet confirmed: Lighthouse's scores for / (logged in), Lighthouse was unable to reliably load the page you requested. (Status code: 500); a run where Lighthouse loads the page confirms it" \
   && has "$d/summary" "not yet confirmed: Lighthouse's scores for /accounts/login/ (not logged in), lhci collect exited 1;" \
   && has "$d/summary" "not yet confirmed: / (logged in) answered HTTP 500, so the audit read an error page" \
   && has "$d/summary" "not yet confirmed: axe-core on /accounts/login/ (not logged in), TimeoutError: Navigation timeout of 60000 ms exceeded;" \
   && ! has "$d/summary" "pass: Lighthouse" && has "$d/stdout" "exit 0"; then
  ok "a page Lighthouse or axe-core could not read, or that answered an error: not yet confirmed, never a pass"
else bad "unreadable pages" "$(cat "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; pages "$d" no-login; lhr "$d/web-audit/0.lhr.json" 1; lhr "$d/web-audit/1.lhr.json" 1
clean_axe "$d/web-audit/0.axe.json"; clean_axe "$d/web-audit/1.axe.json"; verdict "$d"
if has "$d/summary" "not yet confirmed: / as a logged-in person, the audit could not log a person in (TypeError: create_user() missing 1 required positional argument: 'email'), so / was audited as a visitor who is not logged in;" \
   && has "$d/summary" "pass: Lighthouse scored / (not logged in)"; then
  ok "no log-in possible: / is audited as a visitor, and the summary says the logged-in page was not"
else bad "no log-in" "$(cat "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; pages "$d"; lhr "$d/web-audit/1.lhr.json" 1; clean_axe "$d/web-audit/1.axe.json"
printf '{"finalDisplayedUrl":"http://localhost:8000/accounts/login/?next=/","categories":{"accessibility":{"score":0.88}}}' > "$d/web-audit/0.lhr.json"
printf '{"status":200,"url":"http://localhost:8000/accounts/login/?next=/","violations":[{"id":"html-has-lang","impact":"serious","help":"<html> element must have a lang attribute","helpUrl":"https://dequeuniversity.com/rules/axe/4.14/html-has-lang","nodes":1,"target":["html"]}],"incomplete":[],"rules":20}' > "$d/web-audit/0.axe.json"
verdict "$d"
if has "$d/summary" "not yet confirmed: / as a logged-in person, the audit's session did not hold and the page sent it to /accounts/login/, so the results above for / (logged in) are the log-in page's;" \
   && has "$d/summary" "after a redirect to http://localhost:8000/accounts/login/?next=/" \
   && has "$d/summary" "(serious: \`<html>\` element must have a lang attribute)" \
   && has "$d/summary" "| \`<html>\` element must have a lang attribute |" \
   && ! has "$d/summary" "/accounts/login/ (not logged in), the audit's session"; then
  ok "a session that did not hold: the logged-in page's results are said to be the log-in page's; markup in a rule's help is quoted"
else bad "session did not hold" "$(cat "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; echo "there is no Dockerfile in the project" > "$d/web-audit/app.why"; verdict "$d" APP=failure AUDIT=skipped
if has "$d/summary" "not yet confirmed: the pages' audit, the app image did not start: there is no Dockerfile in the project; a run that gets past it confirms it" \
   && has "$d/stdout" "::warning::" && ! has "$d/summary" "pass:" && ! has "$d/summary" "Automated checks" && has "$d/stdout" "exit 0"; then
  ok "the app did not start: one not-yet-confirmed line with the reason, never a pass"
else bad "app did not start" "$(cat "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; pages "$d"; verdict "$d" CHROME=failure TOOLS=failure AUDIT=skipped
if has "$d/summary" "not yet confirmed: the pages' audit, Chrome for Testing and Lighthouse CI and axe-core did not install" && ! has "$d/summary" "pass:"; then
  ok "a tool that did not install: named, never a pass"
else bad "tool install failed" "$(cat "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; pages "$d"; verdict "$d" AUDIT=failure
if has "$d/summary" "not yet confirmed: the pages' audit, the audit did not finish (its log says why)" && ! has "$d/summary" "pass:"; then
  ok "an audit that crashed: not yet confirmed, never a pass"
else bad "audit crashed" "$(cat "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; pages "$d"; verdict "$d"
if has "$d/summary" "not yet confirmed: Lighthouse's scores for / (logged in), it wrote no report" \
   && has "$d/summary" "not yet confirmed: axe-core on / (logged in), it wrote no report" && ! has "$d/summary" "pass:"; then
  ok "an audit step that succeeded but wrote nothing: not yet confirmed per page, never a pass"
else bad "audit wrote nothing" "$(cat "$d/summary" "$d/stdout")"; fi

d="$(fresh)"; verdict "$d" CHECKOUT=failure APP=skipped AUDIT=skipped
if has "$d/summary" "not yet confirmed: the pages' audit, the checkout did not finish" && has "$d/stdout" "exit 0"; then
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
  if RUNNER_TEMP="$tmp" GITHUB_PATH="$tmp/path" bash "$tmp/node.sh" > "$tmp/node.log" 2>&1 \
     && RUNNER_TEMP="$tmp" GITHUB_ENV="$tmp/env" bash "$tmp/chrome.sh" > "$tmp/chrome.log" 2>&1; then
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
  verdict "$d"
  if [ "$rc" = 0 ] \
     && grep -qE "^- not yet confirmed: no accessibility violation axe-core's automated rules find on /known/ \(not logged in\), it found [0-9]+: .*image-alt on 1 element" "$d/summary" \
     && grep -qE "^- not yet confirmed: no accessibility violation .* on /known/ .*label on 1 element" "$d/summary" \
     && has "$d/stdout" "::warning::not yet confirmed: no accessibility violation axe-core's automated rules find on /known/" \
     && grep -qE "^- pass: axe-core's automated rules found no accessibility violation on / \(not logged in\) \([0-9]+ rules applied\)" "$d/summary" \
     && grep -qE "^- pass: Lighthouse scored /known/ \(not logged in\): accessibility [0-9]+, best practices [0-9]+, seo [0-9]+, performance [0-9]+, out of 100" "$d/summary" \
     && grep -qE "^- pass: Lighthouse scored / \(not logged in\): accessibility 100," "$d/summary" \
     && has "$d/summary" "Automated checks catch only part of accessibility." && has "$d/stdout" "exit 0"; then
    ok "the pinned Chrome, Lighthouse CI and axe-core report the known page's image-alt and label, and pass the clean page (audit ${audit_s}s)"
  else
    bad "the live audit" "$(tail -30 "$d/audit.log"; cat "$d/summary" "$d/stdout")"
  fi
  sed -n 's/^- //p' "$d/summary" | sed 's/^/        > /'
  echo "  time: ${audit_s}s to audit two pages, $((SECONDS - started))s with the installs"
fi

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
