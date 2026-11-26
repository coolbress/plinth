#!/usr/bin/env bash
# When does `ci / deps` report dependency review as not checked (#395)? The
# step is read out of python-ci.yml, not copied, and run with a stub `curl`
# that answers from a file. Only a private repository answered with the bare
# 403 GitHub gave on one without Code Security (recorded in
# tests/fixtures/dependency-review-403-private.json) is "refused"; every other
# answer runs the review, so an outage or another refusal still fails. The
# cases that must NOT be refused come first. Where it is refused, osv-scanner
# compares the pull request's head with its merge base (#1073).
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="$root/.github/workflows/python-ci.yml"
work="$(mktemp -d)" || { echo "deps-served-cases: could not make a temp folder" >&2; exit 1; }; trap 'rm -rf "$work"' EXIT
fails=0
ok()  { echo "  PASS  $1"; }
bad() { echo "  FAIL  $1" >&2; fails=$((fails+1)); }

# Each step of the deps job as its own block of lines, without a YAML library
# (CI's python3 has none): from its `- name:` line to the next step or job.
blocks() {  # <out dir>
  python3 - "$wf" "$1" <<'PY'
import pathlib, re, sys, textwrap
lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
start = next(i for i, l in enumerate(lines) if re.match(r"^  deps:\s*$", l))
end = next((i for i in range(start + 1, len(lines)) if re.match(r"^  \S", lines[i])), len(lines))
job = lines[start:end]
pathlib.Path(sys.argv[2], "job.txt").write_text("\n".join(job) + "\n")
heads = [i for i, l in enumerate(job) if re.match(r"^      - ", l)]
for n, h in enumerate(heads):
    block = job[h:(heads[n + 1] if n + 1 < len(heads) else len(job))]
    m = re.search(r"name: (.+)$", "\n".join(block[:3]), re.M)
    if not m:
        continue
    name = m.group(1).strip()
    safe = re.sub(r"[^A-Za-z]+", "-", name).strip("-")[:40]
    pathlib.Path(sys.argv[2], safe + ".txt").write_text("\n".join(block) + "\n")
    r = next((k for k, l in enumerate(block) if re.match(r"^        run: \|\s*$", l)), None)
    if r is not None:
        body = []
        for l in block[r + 1:]:
            if l.strip() and not l.startswith("          "):
                break
            body.append(l)
        pathlib.Path(sys.argv[2], safe + ".run").write_text(textwrap.dedent("\n".join(body)) + "\n")
PY
}
mkdir -p "$work/steps" && blocks "$work/steps"
cp "$work/steps/Is-dependency-review-served-on-this-repo.run" "$work/step.sh" 2>/dev/null \
  || { echo "  FAIL  no 'Is dependency review served' step with a run block in the deps job" >&2; exit 1; }

mkdir -p "$work/bin"
cat > "$work/bin/curl" <<'SH'
#!/bin/sh
# -o <file> -w '%{http_code}': write the body, print the code. The comparison
# answers from STUB_CODE/STUB_BODY, the SBOM report request from SBOM_CODE/SBOM_BODY;
# a code of "fail" exits 7, as curl does with no answer.
out=""; url=""; while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift ;; http*) url="$1" ;; esac; shift; done
case "$url" in */sbom/generate-report) code="$SBOM_CODE"; body="$SBOM_BODY" ;; *) code="$STUB_CODE"; body="$STUB_BODY" ;; esac
[ "$code" = fail ] && exit 7
cp "$body" "$out"; printf '%s' "$code"
SH
chmod +x "$work/bin/curl"
real="$root/tests/fixtures/dependency-review-403-private.json"
printf '%s' '{"message":"API rate limit exceeded for installation ID 1.","documentation_url":"https://docs.github.com/rest"}' > "$work/ratelimit.json"
printf '%s' '{"message":"Resource not accessible by integration","status":"403"}' > "$work/integration.json"
printf '%s' '[]' > "$work/empty-diff.json"
printf '%s' '' > "$work/nobody.json"
printf '%s' '{"message":"Server Error"}' > "$work/500.json"
# The answer recorded on the probe repository, 2026-10-05.
printf '%s' '{"sbom_url":"https://api.github.com/repos/o/r/dependency-graph/sbom/fetch-report/07fd6b0a-58ee-47a4-80c6-35564ff07211"}' > "$work/sbom.json"
printf '%s' '{"message":"Not Found"}' > "$work/notfound.json"

served() {  # <want: refused|run> <name> <private> <code> <body> [<sbom code> <sbom body>]; FORK from the environment, default false
  local out="$work/out" log="$work/log"; : > "$out"
  PATH="$work/bin:$PATH" GITHUB_OUTPUT="$out" RUNNER_TEMP="$work" GH_TOKEN=t REPO=o/r BASE=b HEAD=h \
    PRIVATE="$3" FORK="${FORK-false}" API=https://api.github.com STUB_CODE="$4" STUB_BODY="$5" \
    SBOM_CODE="${6:-201}" SBOM_BODY="${7:-$work/sbom.json}" bash "$work/step.sh" >"$log" 2>&1
  local rc=$? got; got="$(sed -n 's/^review=//p' "$out")"
  if [ "$rc" -eq 0 ] && [ "$got" = "$1" ]; then ok "$2"; else bad "$2: exit $rc, review='$got', wanted '$1'"; sed 's/^/        /' "$log" >&2; fi
}

served run     'a public repository answered 403 Forbidden runs the review'        false 403 "$real"
served run     'a private repository rate-limited (403, another message) runs it'  true  403 "$work/ratelimit.json"
served run     "a private repository whose token lacks access (403, another message) runs it" true 403 "$work/integration.json"
served run     'a private repository answered 403 with no body runs it'            true  403 "$work/nobody.json"
served run     'a private repository answered 500 runs it'                          true  500 "$work/500.json"
served run     'a private repository answered 404 Forbidden-shaped runs it'         true  404 "$real"
served run     'curl failing (no answer) runs it'                                   true  fail "$real"
served run     'a private repository with the review served (200) runs it'          true  200 "$work/empty-diff.json"
served run     'an unset private flag runs it'                                      ""    403 "$real"
# GitHub answers a fork's comparison 403 as well (its REST docs): a fork runs
# the review, private or not, and an unset flag is not "false".
FORK=true served run 'a private fork answered the recorded 403, its graph answering, runs it' true 403 "$real"
FORK='' served run 'an unset fork flag runs it'                                       true 403 "$real"
# The graph is asked too: a disabled graph answers the same 403 (#395 review).
served run     'the recorded 403 with the graph answering 404 runs it'              true  403 "$real" 404 "$work/notfound.json"
served run     'the recorded 403 with the graph answering 403 runs it'              true  403 "$real" 403 "$real"
served run     'the recorded 403 with the graph not answering runs it'              true  403 "$real" fail "$work/sbom.json"
served run     'the recorded 403 with a 201 that carries no sbom_url runs it'       true  403 "$real" 201 "$work/notfound.json"
served run     'the recorded 403 with the old export answer (200) runs it'         true  403 "$real" 200 "$work/sbom.json"
served refused 'the recorded answer on a private repository, the graph answering, is refused' true 403 "$real"

# Refused (#1073): osv-scanner compares head and merge base, as on GitLab.
# The step is run with a stub `curl` that answers the API from files and
# "downloads" a stub osv-scanner, whose SHA-256 the case passes; the stub
# answers per lockfile, as tests/gitlab-ci-cases.sh's does. Then the Verdict
# step reads what it left.
osv_run="$work/steps/Where-GitHub-refuses-it-compare-the-adde.run"
[ -f "$osv_run" ] || { bad "no 'Where GitHub refuses it, compare ... with osv-scanner' step with a run block in the deps job"; osv_run=/dev/null; }
mkdir -p "$work/osvbin"
cat > "$work/osvbin/curl" <<'SH'
#!/bin/sh
# Downloads (-fsSL) copy $OSV/scanner, or exit 22 when DL=fail. API calls
# answer from $OSV/<compare|headlock|baselock>.{code,body}.
out=""; url=""; while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift ;; http*) url="$1" ;; esac; shift; done
echo "$url" >> "$OSV/curl.log"
case "$url" in
  https://github.com/google/osv-scanner/releases/download/v*/osv-scanner_linux_amd64)
    [ "${DL:-ok}" = fail ] && exit 22; cp "$OSV/scanner" "$out"; exit 0 ;;
  */compare/*) w=compare ;;
  */contents/*ref=mergebase) w=baselock ;;
  */contents/*ref=h) w=headlock ;;
  *) echo "unexpected url $url" >&2; exit 3 ;;
esac
code="$(cat "$OSV/$w.code")"; [ "$code" = fail ] && exit 7
cp "$OSV/$w.body" "$out"; printf '%s' "$code"
SH
chmod +x "$work/osvbin/curl"
cat > "$work/scanner" <<'SH'
#!/usr/bin/env bash
echo "$* db=$OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY" >> "$OSV/scan.log"
prev=""; for a; do [ "$prev" = -L ] && lock="$a"; prev="$a"; done
case "$lock" in */head/uv.lock) w=head ;; */base/uv.lock) w=base ;; *) echo "unexpected lockfile $lock" >&2; exit 2 ;; esac
cat "$OSV/$w.json"
exit "$(cat "$OSV/$w.rc")"
SH
scanner_sha="$(sha256sum "$work/scanner" | cut -d' ' -f1)"
finding() { printf '{"package":{"name":"%s","version":"%s","ecosystem":"PyPI"},"groups":[{"ids":["%s"],"max_severity":"%s"}]}' "$1" "$2" "$3" "$4"; }
report()  { local IFS=,; printf '{"results":[{"source":{"path":"uv.lock","type":"lockfile"},"packages":[%s]}]}' "$*"; }
verdict_run="$work/steps/Verdict.run"
# osv_case <head report> <base report> [key=value ...]: keys head_rc base_rc
# (default 1), compare headlock baselock (HTTP codes, default 200), sev (high),
# sha (the stub's), DL. Sets rc (the osv step's), log, sum (the verdict line).
osv_case() {
  local OSV="$work/osv"; rm -rf "$OSV" "$work/rt"; mkdir -p "$OSV" "$work/rt"
  printf '%s' "$1" > "$OSV/head.json"; printf '%s' "$2" > "$OSV/base.json"; shift 2
  local head_rc=1 base_rc=1 compare=200 headlock=200 baselock=200 sev=high sha="$scanner_sha" DL=ok kv
  for kv; do local "${kv?}"; done
  printf '%s' "$head_rc" > "$OSV/head.rc"; printf '%s' "$base_rc" > "$OSV/base.rc"
  cp "$work/scanner" "$OSV/scanner"
  printf '%s' "$compare" > "$OSV/compare.code"; printf '%s' '{"merge_base_commit":{"sha":"mergebase"}}' > "$OSV/compare.body"
  printf '%s' "$headlock" > "$OSV/headlock.code"; printf 'version = 1\n[[package]]\nname = "a"\nsource = { registry = "https://pypi.org/simple" }\n' > "$OSV/headlock.body"
  printf '%s' "$baselock" > "$OSV/baselock.code"; cp "$OSV/headlock.body" "$OSV/baselock.body"
  [ "$headlock" = 200 ] || printf '{"message":"Not Found"}' > "$OSV/headlock.body"
  [ "$baselock" = 200 ] || printf '{"message":"Not Found"}' > "$OSV/baselock.body"
  log="$(PATH="$work/osvbin:$PATH" OSV="$OSV" DL="$DL" RUNNER_TEMP="$work/rt" GH_TOKEN=t REPO=o/r BASE=b HEAD=h \
    API=https://api.github.com WORKDIR=. PLINTH_DEPS_FAIL_ON_SEVERITY="$sev" OSV_SCANNER_VERSION=2.6.0 \
    OSV_SCANNER_SHA256="$sha" bash "$osv_run" 2>&1)"; rc=$?
  local outcome=success; [ "$rc" = 0 ] || outcome=failure
  : > "$work/sum"
  GITHUB_STEP_SUMMARY="$work/sum" RUNNER_TEMP="$work/rt" EVENT=pull_request SERVED=refused REVIEW=skipped \
    OSV="$outcome" SEVERITY="$sev" ACTOR=someone bash "$verdict_run" >/dev/null 2>&1
  sum="$(head -n 1 "$work/sum")"
}
expect() { # <label> <want rc: 0|1> <verdict line, a regex> [<log text>]
  local got=0; [ "$rc" = 0 ] || got=1
  if [ "$got" = "$2" ] && grep -qE -- "$3" <<<"$sum" \
     && { [ -z "${4:-}" ] || grep -qF -- "$4" <<<"$log$sum"; }
  then ok "$1"; else bad "$1: exit $rc, verdict '$sum'"; sed 's/^/        /' <<<"$log" >&2; fi
}
high="$(finding jinja2 3.1.2 GHSA-high 8.8)"; mod="$(finding requests 2.25.0 GHSA-mod 5.3)"
couldnt='^- fail: dependency review, the scan could not run'

osv_case "$(report "$high")" "$(report)"
expect "refused, an added version with a high advisory fails and names it" 1 \
  '^- fail: dependency review, 1 advisories at high or above on added dependency versions: jinja2 3.1.2 \(GHSA-high, CVSS 8\.8\)$'
if [ "$(wc -l < "$work/osv/scan.log" | tr -d ' ')" = 2 ] && grep -q -- "--download-offline-databases" <(sed -n 1p "$work/osv/scan.log") \
   && ! grep -q -- "--download-offline-databases" <(sed -n 2p "$work/osv/scan.log") \
   && [ "$(grep -c -- "--offline-vulnerabilities --config=$work/rt/plinth-deps/osv-scanner.toml" "$work/osv/scan.log")" = 2 ] \
   && [ "$(sed 's/.* db=//' "$work/osv/scan.log" | sort -u)" = "$work/rt/plinth-deps/osv-db" ] \
   && grep -qF "/repos/o/r/compare/b...h" "$work/osv/curl.log" && grep -qF "/repos/o/r/contents/uv.lock?ref=h" "$work/osv/curl.log" \
   && grep -qF "/repos/o/r/contents/uv.lock?ref=mergebase" "$work/osv/curl.log"
then ok "refused: head and merge base read through the API, the database downloaded once, both scanned offline with plinth's config"
else bad "refused: the scans are not what the GitLab job runs"; sed 's/^/        /' "$work/osv/scan.log" "$work/osv/curl.log" >&2; fi
osv_case "$(report "$mod")" "$(report)"
expect "refused, an added version below the threshold passes, naming osv-scanner" 0 \
  '^- pass: dependency review, no added dependency version with an advisory at high or above \(osv-scanner, the OSV database\)$'
osv_case "$(report "$mod")" "$(report)" sev=moderate
expect "refused, the same version at threshold moderate fails" 1 '^- fail: dependency review, 1 advisories at moderate or above' "requests 2.25.0"
osv_case "$(report "$high")" "$(report "$high")"
expect "refused, a vulnerability already on the merge base does not fail" 0 '^- pass: dependency review, no added dependency version'
osv_case "$(report)" "$(report)" head_rc=0 base_rc=0
expect "refused, nothing found on either side passes" 0 '^- pass: dependency review'
osv_case "$(report "$high")" "" baselock=404 base_rc=128
expect "refused, no uv.lock at the merge base: every locked version counts as added" 1 '^- fail: dependency review, 1 advisories' "no uv.lock at the merge base"
osv_case "$(report "$high")" "$(report)" DL=fail
expect "refused, the osv-scanner download failing fails" 1 "$couldnt"
osv_case "$(report)" "$(report)" sha=0000000000000000000000000000000000000000000000000000000000000000
expect "refused, a download whose SHA-256 differs fails" 1 "$couldnt" "FAILED"
osv_case "$(report)" "$(report)" headlock=404
expect "refused, no uv.lock at the head fails" 1 "$couldnt" "no uv.lock at the head"
osv_case "$(report)" "$(report)" headlock=500
expect "refused, the head's lockfile unreadable (HTTP 500) fails" 1 "$couldnt" "could not be read (HTTP 500)"
osv_case "$(report)" "$(report)" baselock=fail
expect "refused, the merge base's lockfile unanswered fails" 1 "$couldnt" "could not be read (HTTP 000)"
osv_case "$(report)" "$(report)" compare=403
expect "refused, the merge base unreadable fails" 1 "$couldnt" "the merge base of b and h could not be read (HTTP 403)"
osv_case "" "$(report)" head_rc=127
expect "refused, osv-scanner erroring fails" 1 "$couldnt" "osv-scanner exited 127"
osv_case "" "$(report)" head_rc=128
expect "refused, a lockfile naming registry packages that osv-scanner reads as empty fails" 1 "$couldnt" "which names registry packages"
osv_case "not json" "$(report)" head_rc=0
expect "refused, a report that is not JSON fails" 1 "$couldnt" "not the JSON report expected"
: > "$work/sum"
GITHUB_STEP_SUMMARY="$work/sum" RUNNER_TEMP="$work/empty" EVENT=pull_request SERVED=refused REVIEW=skipped OSV=skipped \
  SEVERITY=high ACTOR=someone bash "$verdict_run" >/dev/null 2>&1
if grep -qE '^- not yet confirmed: dependency review, osv-scanner did not run because an earlier step failed' "$work/sum"
then ok "refused, osv-scanner skipped by an earlier failure: not yet confirmed, never a pass"
else bad "refused, osv-scanner skipped: $(cat "$work/sum")"; fi

# The GitLab job's comparison, character for character, and the same
# osv-scanner version and SHA-256: raised together, or this fails.
python3 - "$wf" "$root/gitlab/python-ci.yml" <<'PY' && ok "osv-scanner's version, SHA-256, download, scan and comparison are the GitLab job's" || fails=$((fails+1))
import re, sys, textwrap
gh, gl = (open(p, encoding="utf-8").read() for p in sys.argv[1:3])
gh = gh[gh.index("      - name: Where GitHub refuses it"):]
gh = gh[:gh.index("\n      - name: ", 10)]
gl_deps = gl[gl.index("\ndeps:\n"):]; gl_deps = gl_deps[:gl_deps.index("\n\n# ")]
def one(pattern, text, what):
    found = re.findall(pattern, text, re.M | re.S)
    if len(found) != 1:
        sys.exit(f"  FAIL  {what}: found {len(found)} times")
    return textwrap.dedent(found[0])
bad = []
for key in ("OSV_SCANNER_VERSION", "OSV_SCANNER_SHA256"):
    a, b = one(rf'^ +{key}: "([^"]+)"$', gh, f"GitHub {key}"), one(rf'^ +{key}: "([^"]+)"$', gl_deps, f"GitLab {key}")
    if a != b: bad.append(f"{key}: GitHub {a}, GitLab {b}")
blocks = {
    "plinth_osv": r"^( +plinth_osv\(\) \{\n.*?\n +\}\n)",
    "scan": r"^( +scan\(\) \{\n.*?\n +\}\n)",
    "the comparison": r"<<'PY'\n(.*?\n) *PY\n",
}
for what, pattern in blocks.items():
    a = one(pattern, gh, f"GitHub {what}")
    b = one(pattern, gl if what == "plinth_osv" else gl_deps, f"GitLab {what}")
    if a != b: bad.append(f"{what} differs from the GitLab job's")
for b in bad: print(f"  FAIL  {b}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY

# The review is gated on the output, the verdict step reads it (#437; its
# lines are run in tests/weakened-checks-cases.sh), and the job is never skipped.
review_step="$work/steps/Dependency-review-blocks-vulnerable-vers.txt"
osv_step="$work/steps/Where-GitHub-refuses-it-compare-the-adde.txt"
verdict_step="$work/steps/Verdict.txt"
if ! grep -qE '^    if:' "$work/steps/job.txt" \
   && grep -qF "steps.served.outputs.review != 'refused'" "$review_step" 2>/dev/null \
   && grep -qF "steps.served.outputs.review == 'refused'" "$osv_step" 2>/dev/null \
   && grep -qF 'SERVED: ${{ steps.served.outputs.review }}' "$verdict_step" 2>/dev/null \
   && grep -qF 'OSV: ${{ steps.osv.outcome }}' "$verdict_step" \
   && grep -qF '"$SERVED" = refused' "$verdict_step"
then ok "the review runs unless refused, osv-scanner only when refused, the verdict reads both, the job is never skipped"
else bad "the steps around the probe are not gated as they should be"; fi

echo "-- refused only on a private repository answered 403 Forbidden, where osv-scanner compares head and merge base; everything else runs the review"
[ "$fails" -eq 0 ]
