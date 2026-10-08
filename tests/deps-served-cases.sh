#!/usr/bin/env bash
# When does `ci / deps` report dependency review as not checked (#395)? The
# step is read out of python-ci.yml, not copied, and run with a stub `curl`
# that answers from a file. Only a private repository answered with the bare
# 403 GitHub gave on one without Code Security (recorded in
# tests/fixtures/dependency-review-403-private.json) is "refused"; every other
# answer runs the review, so an outage or another refusal still fails. The
# cases that must NOT be refused come first.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="$root/.github/workflows/python-ci.yml"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
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

# The review is gated on the output, the verdict step reads it (#437; its
# lines are run in tests/weakened-checks-cases.sh), and the job is never skipped.
review_step="$work/steps/Dependency-review-blocks-vulnerable-vers.txt"
verdict_step="$work/steps/Verdict.txt"
if ! grep -qE '^    if:' "$work/steps/job.txt" \
   && grep -qF "steps.served.outputs.review != 'refused'" "$review_step" 2>/dev/null \
   && grep -qF 'SERVED: ${{ steps.served.outputs.review }}' "$verdict_step" 2>/dev/null \
   && grep -qF '"$SERVED" = refused' "$verdict_step" \
   && grep -qF "not yet confirmed: dependency review" "$verdict_step"
then ok "the review runs unless refused, the verdict says not yet confirmed when refused, the job is never skipped"
else bad "the steps around the probe are not gated as they should be"; fi

echo "-- refused only on a private repository answered 403 Forbidden; everything else runs the review"
[ "$fails" -eq 0 ]
