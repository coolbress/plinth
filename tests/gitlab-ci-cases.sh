#!/usr/bin/env bash
# gitlab/python-ci.yml, plinth's pipeline for GitLab.com (#353). Its job
# names and inputs are python-ci.yml's; its pinned tools, the commit types,
# the coverage requirements, the changed-lines judge and the diff-size
# functions named below are the same text. Every job's script goes through
# bash -n and shellcheck; pr-title, deps, floor-check and diff-size are extracted and
# run here against fixtures with the tool downloads stubbed, under GitLab's
# `set -eo pipefail`, so the rule tested is the rule shipped. lint,
# typecheck, test, build and secrets do not run here. GitLab itself never
# runs here: whether GitLab accepts the file is a run on GitLab.com,
# recorded on #353. floor-check installs its PyYAML from PyPI (#528), so
# those cases need network; the other downloads are stubbed.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gl="$root/gitlab/python-ci.yml"
gh="$root/.github/workflows/python-ci.yml"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/gitlab-ci.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
# The job's before_script makes PLINTH_TMP with a bare `mktemp -d` and never
# removes it: a runner discards it, this machine would keep one per job run
# (#575). run_job sends it inside $tmp; the last case counts where a bare
# `mktemp -d` lands, which on macOS 27 was measured not to be TMPDIR.
caller_tmp="$(probe="$(mktemp -d)" && dirname "$probe" && rmdir "$probe")"
caller_dirs() { find "$caller_tmp" -maxdepth 1 -name 'tmp.*' -type d 2>/dev/null | sort; }
caller_before="$(caller_dirs)"

# 3.11 for tomllib, as the image has; at most 3.14, the newest CPython whose
# PyYAML wheels floor-check pins by hash (#528). A newer one finds no pinned
# wheel: raise the pins in gitlab/python-ci.yml, then this bound.
python3 -c 'import sys; sys.exit(not ((3, 11) <= sys.version_info[:2] <= (3, 14)))' \
  || { echo "  FAIL  needs python3 3.11 to 3.14 (tomllib; floor-check's PyYAML wheels are pinned for those); got $(python3 --version 2>&1)"; exit 1; }

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        | /'; }

echo "-- the contract: python-ci.yml's names, pins and the shared text"
# Written out first: bash 3.2 misreads a quote in a heredoc inside $( ).
cat > "$tmp/contract.py" <<'PY'
import re, sys, textwrap
gh, gl = (open(p, encoding="utf-8").read() for p in sys.argv[1:3])
fails = []
# The web archetype is GitHub only (#604): its two jobs have no GitLab twin.
WEB_ONLY = {"migrations", "deploy-check"}
gh_jobs = sorted(j for j in re.findall(r"^  ([a-z][a-z0-9-]*):\s*$", gh.split("\njobs:\n", 1)[1], re.M)
                 if j not in WEB_ONLY)
spec, body = gl.split("\n---\n", 1)
gl_jobs = sorted(j for j in re.findall(r"^([a-z][a-z0-9-]*):\s*$", body, re.M)
                 if j not in ("workflow", "default", "variables", "stages", "include"))
if gh_jobs != gl_jobs:
    fails.append(f"jobs differ: python-ci.yml {gh_jobs}, gitlab {gl_jobs}")
call = gh.split("workflow_call:", 1)[1].split("\n    secrets:", 1)[0].split("\npermissions:", 1)[0]
gh_inputs = set(re.findall(r"^      ([a-z][a-z0-9-]*):\s*$", call, re.M))
gl_inputs = set(re.findall(r"^    ([a-z][a-z0-9-]*):\s*$", spec, re.M))
# GitLab Free has no required checks by name, so no list of them to pass;
# `web` turns on the two web-only jobs above.
NOT_ON_GITLAB = {"floor-check-required-checks", "web"}
if gh_inputs - NOT_ON_GITLAB != gl_inputs:
    fails.append(f"inputs differ: python-ci.yml {sorted(gh_inputs - NOT_ON_GITLAB)}, gitlab {sorted(gl_inputs)}")
for k in ("UV_VERSION", "UV_SHA256", "GITLEAKS_VERSION", "GITLEAKS_SHA256"):
    a = set(re.findall(rf"\b{k}: \"([^\"]+)\"", gh)); b = set(re.findall(rf"\b{k}: \"([^\"]+)\"", gl))
    if len(a) != 1 or a != b:
        fails.append(f"{k}: python-ci.yml {sorted(a)}, gitlab {sorted(b)}")
def heredocs(text, tag):
    return [textwrap.dedent(m) for m in re.findall(rf"<<'{tag}'\n(.*?)\n[ \t]*{tag}\n", text, re.S)]
for tag, mark in (("REQ", "coverage==7"), ("REQ", "diff-cover=="), ("PY", "diff-cover did not finish")):
    a = [h for h in heredocs(gh, tag) if mark in h]; b = [h for h in heredocs(gl, tag) if mark in h]
    if len(a) != 1 or len(b) != 1 or a[0] != b[0]:
        fails.append(f"the {tag} block holding {mark!r} differs ({len(a)} in python-ci.yml, {len(b)} in gitlab)")
def one(text, pattern):
    found = re.findall(pattern, text, re.M)
    return found[0].strip() if len(found) == 1 else f"<{len(found)} matches>"
for what, pattern in (("the commit types", r"types='([^']+)'"),
                      ("TEST", r"^\s*TEST = (re\.compile\(.*\))\s*$"),
                      ("EDGE", r"^\s*EDGE = (.*)$"), ("WRAP", r"^\s*WRAP = (.*)$")):
    a, b = one(gh, pattern), one(gl.split("\ndiff-size:", 1)[1] if what != "the commit types" else gl, pattern)
    if a != b or a.startswith("<"):
        fails.append(f"{what}: python-ci.yml {a!r}, gitlab {b!r}")
def marker(text):   # its lines, indentation aside
    body = text.split("MARKER = ", 1)[1].split("re.IGNORECASE)", 1)[0] if "MARKER = " in text else ""
    return [l.strip() for l in body.split("\n")]
a, b = marker(gh), marker(gl)
if not a or a != b:
    fails.append("MARKER differs")
def config(text):
    return set(re.findall(r'"([^"]+)"', text.split("CONFIG = {", 1)[1].split("}", 1)[0]))
if config(gh) - {"ruleset.json"} != config(gl):   # GitLab's wall is not a file
    fails.append(f"CONFIG: python-ci.yml {sorted(config(gh))}, gitlab {sorted(config(gl))}")
def func(text, name):
    lines = text.split("\n")
    a = next((i for i, l in enumerate(lines) if l.lstrip().startswith(f"def {name}(")), None)
    if a is None:
        return ""
    ind = len(lines[a]) - len(lines[a].lstrip())
    b = a + 1
    while b < len(lines) and (not lines[b].strip() or len(lines[b]) - len(lines[b].lstrip()) > ind):
        b += 1
    return textwrap.dedent("\n".join(lines[a:b])).rstrip()
def agent(text):   # the AGENT kinds and reasons (#657), indentation aside
    body = text.split("AGENT = (", 1)[1].split("\n\n", 1)[0] if "AGENT = (" in text else ""
    return [l.strip() for l in body.split("\n")]
a, b = agent(gh), agent(gl)
if not a or a != b:
    fails.append("AGENT differs")
for name in ("tool_table", "archetype", "markers", "shape", "named", "agent_what"):
    a, b = func(gh, name), func(gl, name)
    if not a or a != b:
        fails.append(f"the diff-size function {name} differs")
if not re.search(r"^  image: [^\s@]+@sha256:[0-9a-f]{64}$", gl, re.M):
    fails.append("the image is not pinned by digest")
if not re.search(r'OSV_SCANNER_SHA256: "[0-9a-f]{64}"', gl) or "sha256sum -c" not in gl.split("plinth_osv()", 1)[1].split("\n      }\n", 1)[0]:
    fails.append("osv-scanner is not checked against a SHA-256")
print("\n".join(fails)); sys.exit(1 if fails else 0)
PY
if out="$(python3 "$tmp/contract.py" "$gh" "$gl" 2>&1)"; then ok "job names, inputs, pins and the shared text match python-ci.yml"; else bad "gitlab/python-ci.yml drifted from python-ci.yml" "$out"; fi

# A job's script, after the shared helpers: `.plinth`'s before_script, the
# overrides given, then the job's script block.
extract() { # <job> -> its `- |` block under script: (before_script: for .plinth), dedented
  python3 - "$gl" "$1" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
job = sys.argv[2]
at = lines.index(f"{job}:")
key = "  before_script:" if job == ".plinth" else "  script:"
i = next(j for j in range(at + 1, len(lines)) if lines[j] == key)
assert lines[i + 1] == "    - |", lines[i + 1]
for l in lines[i + 2:]:
    if l.strip() and not l.startswith("      "):
        break
    print(l[6:])
PY
}
extract .plinth > "$tmp/helpers.sh" || { bad "the shared helpers were not found"; exit 1; }
for job in lint typecheck test secrets pr-title deps diff-size build floor-check; do
  extract "$job" > "$tmp/$job.sh" 2>/dev/null || { bad "$job: no script block found"; continue; }
  if out="$(cat "$tmp/helpers.sh" "$tmp/$job.sh" | bash -n 2>&1)"; then ok "$job: the script parses (bash -n)"
  else bad "$job: the script does not parse" "$out"; fi
  # SC2034: the helpers set plinth_last for the jobs that read it.
  if ! command -v shellcheck >/dev/null; then bad "$job: shellcheck not found (brew install shellcheck, apt-get install shellcheck)"
  elif out="$(cat "$tmp/helpers.sh" "$tmp/$job.sh" | shellcheck -s bash -S warning -e SC2034 - 2>&1)"; then ok "$job: shellcheck"
  else bad "$job: shellcheck" "$out"; fi
done

mkdir -p "$tmp/bin" "$tmp/job-tmp"
# GNU mktemp reads TMPDIR, macOS's did not: a bare `mktemp -d` gets a template.
printf '#!/usr/bin/env bash\n[ "$*" = -d ] && set -- -d "$TMPDIR/tmp.XXXXXXXXXX"\nexec %q "$@"\n' "$(command -v mktemp)" > "$tmp/bin/mktemp"
chmod +x "$tmp/bin/mktemp"
# Runs a job in the current directory with the downloads stubbed; sets $out
# and $rc.
run_job() { # <job>
  rc=0
  out="$( { cat "$tmp/helpers.sh"; echo 'plinth_uv() { :; }; plinth_osv() { :; }; plinth_gitleaks() { :; }'; cat "$tmp/$1.sh"; } \
    | PATH="$tmp/bin:$PATH" TMPDIR="$tmp/job-tmp" bash -eo pipefail 2>&1)" || rc=$?
}
expect() { # <label> <rc> <pattern in out>...
  local label="$1" want="$2"; shift 2
  local p miss=""
  for p in "$@"; do printf '%s' "$out" | grep -qF -- "$p" || miss="$miss missing: $p;"; done
  if [ "$rc" = "$want" ] && [ -z "$miss" ]; then ok "$label"; else bad "$label (exit $rc, wanted $want;$miss)" "$out"; fi
}
refuse() { # <label> <pattern that must not be in out>
  if printf '%s' "$out" | grep -qF -- "$2"; then bad "$1" "$out"; else ok "$1"; fi
}

echo "-- pr-title"
title() { export CI_MERGE_REQUEST_TITLE="$1"; run_job pr-title; unset CI_MERGE_REQUEST_TITLE; }
title "feat: add a thing";            expect "a Conventional Commits title passes" 0 "pass: MR title follows the convention"
title "Draft: fix(cli): exit code";   expect "a draft prefix is left out" 0 "pass: MR title follows the convention"
title "[Draft] docs: a page";         expect "a [Draft] prefix is left out" 0 "pass: MR title follows the convention"
title "research: a corpus note";      expect "an invented type fails" 1 "fail: MR title, it is not Conventional Commits"
title "Draft: research: a note";      expect "a draft with an invented type fails" 1 "fail: MR title"
title "fix: x (#12)";                 expect "a trailing (#N) passes: GitLab's squash adds no number" 0 "pass: MR title"
title "";                             expect "not a merge request: a pass that says so" 0 "pass: MR title, does not apply"
CI_OPEN_MERGE_REQUESTS='g/p!3' run_job pr-title
expect "a branch pipeline while a merge request is open fails, it is not a pass" 1 "fail: MR title, this is a branch pipeline while merge request g/p!3 is open"

echo "-- deps (osv-scanner stubbed: it answers per lockfile from fixtures)"
cat > "$tmp/bin/osv-scanner" <<'SH'
#!/usr/bin/env bash
echo "$* db=$OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY" >> "$STUB/log"
prev=""; for a; do [ "$prev" = -L ] && lock="$a"; prev="$a"; done
if grep -q HEADMARK "$lock"; then w=head; else w=base; fi
cat "$STUB/$w.json"
exit "$(cat "$STUB/$w.rc" 2>/dev/null || echo 0)"
SH
chmod +x "$tmp/bin/osv-scanner"
export STUB="$tmp/stub"
finding() { # <name> <version> <id> <score> -> one package with one group
  printf '{"package":{"name":"%s","version":"%s","ecosystem":"PyPI"},"groups":[{"ids":["%s"],"max_severity":"%s"}]}' "$1" "$2" "$3" "$4"
}
report() { # <packages...> -> an osv-scanner JSON report
  local IFS=,; printf '{"results":[{"source":{"path":"uv.lock","type":"lockfile"},"packages":[%s]}]}' "$*"
}
deps_case() { # <head report> <base report> [head rc] [base rc] [threshold]
  rm -rf "$STUB"; mkdir -p "$STUB"
  printf '%s' "$1" > "$STUB/head.json"; printf '%s' "$2" > "$STUB/base.json"
  printf '%s' "${3:-1}" > "$STUB/head.rc"; printf '%s' "${4:-1}" > "$STUB/base.rc"
  (cd "$repo" && CI_MERGE_REQUEST_IID=1 CI_MERGE_REQUEST_DIFF_BASE_SHA="$base" PLINTH_WORKDIR=. \
     PLINTH_DEPS_FAIL_ON_SEVERITY="${5:-high}" run_job deps && printf '%s\n' "$rc" > "$tmp/rc" && printf '%s' "$out" > "$tmp/out")
  rc="$(cat "$tmp/rc")"; out="$(cat "$tmp/out")"
}
repo="$tmp/deps"; mkdir -p "$repo"
git -C "$repo" init -q -b main; git -C "$repo" config user.email t@example.com; git -C "$repo" config user.name t
git -C "$repo" config commit.gpgsign false
printf 'version = 1\n[[package]]\nname = "a"\nsource = { registry = "https://pypi.org/simple" }\n' > "$repo/uv.lock"
git -C "$repo" add -A; git -C "$repo" commit -qm base; base="$(git -C "$repo" rev-parse HEAD)"
printf '# HEADMARK\n' >> "$repo/uv.lock"; git -C "$repo" commit -qam head

high="$(finding jinja2 3.1.2 GHSA-high 8.8)"; mod="$(finding requests 2.25.0 GHSA-mod 5.3)"
none="$(finding idna 2.10 GHSA-none "")"
deps_case "$(report "$high")" "$(report)"
expect "an added version with a high advisory fails" 1 "fail: dependency review, 1 advisories at high or above on added dependency versions" "jinja2 3.1.2 (GHSA-high, CVSS 8.8)"
grep -q -- "--download-offline-databases" <(sed -n 1p "$STUB/log") && ! grep -q -- "--download-offline-databases" <(sed -n 2p "$STUB/log") \
  && [ "$(sed 's/.* db=//' "$STUB/log" | sort -u | wc -l | tr -d ' ')" = 1 ] && [ "$(wc -l < "$STUB/log" | tr -d ' ')" = 2 ] \
  && grep -q -- "--offline-vulnerabilities" <(sed -n 2p "$STUB/log") \
  && [ "$(grep -c -- "--config=" "$STUB/log")" = 2 ] \
  && ok "the database is downloaded once, both lockfiles are scanned offline against that one copy, each with plinth's own config" \
  || bad "the scans do not share one downloaded database and plinth's config" "$(cat "$STUB/log")"
deps_case "$(report "$high")" "$(report "$high")"
expect "the same advisory at the base is not added: a pass" 0 "pass: dependency review, no added dependency version with an advisory at high or above"
deps_case "$(report "$(finding jinja2 3.1.3 GHSA-high 8.8)")" "$(report "$high")"
expect "a raised version that keeps the advisory counts as added" 1 "fail: dependency review" "jinja2 3.1.3"
deps_case "$(report "$mod")" "$(report)"
expect "a moderate advisory passes at the default threshold" 0 "pass: dependency review"
deps_case "$(report "$mod")" "$(report)" 1 1 moderate
expect "a moderate advisory fails at threshold moderate" 1 "fail: dependency review" "requests 2.25.0"
deps_case "$(report "$none")" "$(report)"
expect "an advisory with no score counts as at or above" 1 "fail: dependency review" "CVSS none"
deps_case "$(report)" "$(report)" 0 0
expect "no finding on either side: a pass" 0 "pass: dependency review"
deps_case "" "$(report)" 127
expect "osv-scanner erroring (the download, a crash) fails" 1 "osv-scanner exited 127" "fail: dependency review, the scan could not run"
deps_case "not json" "$(report)" 0
expect "a report that is not JSON fails" 1 "not the JSON report expected" "fail: dependency review, the scan could not run"
deps_case "" "$(report)" 128
expect "no package found in a lockfile that names registry packages fails" 1 "which names registry packages" "fail: dependency review"
deps_case "$(report)" "" 1 128
expect "no package found in a lockfile that names registry packages fails, at the base too" 1 "fail: dependency review"
(cd "$repo" && CI_MERGE_REQUEST_IID='' run_job deps && printf '%s\n%s' "$rc" "$out" > "$tmp/o"); rc="$(head -1 "$tmp/o")"; out="$(cat "$tmp/o")"
expect "not a merge request: a pass that says so" 0 "pass: dependency review, does not apply"
(cd "$repo" && CI_MERGE_REQUEST_IID='' CI_OPEN_MERGE_REQUESTS='g/p!3' run_job deps && printf '%s\n%s' "$rc" "$out" > "$tmp/o"); rc="$(head -1 "$tmp/o")"; out="$(cat "$tmp/o")"
expect "a branch pipeline while a merge request is open fails" 1 "fail: dependency review, this is a branch pipeline while merge request g/p!3 is open"
# A merge base with no uv.lock: the scan of the empty stand-in finds no
# package, and every locked version counts as added.
repo="$tmp/deps-new"; mkdir -p "$repo"
git -C "$repo" init -q -b main; git -C "$repo" config user.email t@example.com; git -C "$repo" config user.name t
git -C "$repo" config commit.gpgsign false
git -C "$repo" commit -q --allow-empty -m base; base="$(git -C "$repo" rev-parse HEAD)"
printf '# HEADMARK\nversion = 1\n' > "$repo/uv.lock"; git -C "$repo" add -A; git -C "$repo" commit -qm head
deps_case "$(report "$high")" "" 1 128
expect "no uv.lock at the merge base: every finding counts as added" 1 "no uv.lock at the merge base" "jinja2 3.1.2"
deps_case "$(report "$mod")" "" 1 128
expect "no package found in a lockfile with no registry package is an empty scan" 0 "pass: dependency review"
git -C "$repo" rm -q uv.lock; git -C "$repo" commit -qm "drop the lock"
deps_case "$(report)" "$(report)"
expect "no uv.lock at the head fails" 1 "no uv.lock at the head" "fail: dependency review"

echo "-- floor-check"
fc() { # <.gitlab-ci.yml text>
  local d="$tmp/fc$((pass+fail))"; mkdir -p "$d"; printf '%s\n' "$1" > "$d/.gitlab-ci.yml"
  (cd "$d" && run_job floor-check && printf '%s\n%s' "$rc" "$out" > "$tmp/o"); rc="$(head -1 "$tmp/o")"; out="$(cat "$tmp/o")"
}
sha=0123456789abcdef0123456789abcdef01234567
url="https://raw.githubusercontent.com/coolbress/plinth/$sha/gitlab/python-ci.yml"
fc "include:
  - remote: $url
    integrity: sha256-L3/GAoKaw0Arw6hDCKeKQlV1QPEgHYxGBHsH4zG1IY8=
    inputs:
      max-diff-lines: 400"
expect "an include at a full SHA with a checksum passes" 0 "pass: .gitlab-ci.yml includes plinth's GitLab pipeline at a full commit SHA ($sha)" "pass: the include names a checksum"
expect "the GitLab settings it does not read are not yet confirmed" 0 "not yet confirmed: the protected default branch" "not yet confirmed: the merge check \"Pipelines must succeed\"" "not yet confirmed: this include on the default branch, after the merge" "the rest of the floor (the document set, agent settings, the project files); left to /plinth:floor-check"
refuse "nothing it does not read is a pass" "pass: the protected"
refuse "a checksum leaves nothing about it unconfirmed" "not yet confirmed: the bytes GitLab fetched"
fc "include:
  - remote: $url"
expect "no checksum: not yet confirmed, not a failure" 0 "not yet confirmed: the bytes GitLab fetched are plinth's file, the include names no checksum"
fc "include: '$url'"
expect "the one-line form passes, with no checksum" 0 "pass: .gitlab-ci.yml includes" "the include names no checksum"
fc "include:
  - remote: $url
  - local: other.yml
    integrity: sha256-L3/GAoKaw0Arw6hDCKeKQlV1QPEgHYxGBHsH4zG1IY8="
expect "another item's integrity is not this include's" 0 "the include names no checksum"
fc "include:
  - remote: https://raw.githubusercontent.com/coolbress/plinth/v1.16.0/gitlab/python-ci.yml"
expect "an include at a tag fails" 1 "fail: .gitlab-ci.yml includes plinth's GitLab pipeline at a full commit SHA, it includes it at v1.16.0"
fc "include:
  - remote: https://raw.githubusercontent.com/coolbress/plinth/main/gitlab/python-ci.yml"
expect "an include at a branch fails" 1 "it includes it at main"
fc "include:
  - remote: https://raw.githubusercontent.com/coolbress/plinth/main/gitlab/python-ci.yml
variables:
  OLD: $url"
expect "a pinned URL outside the include does not stand in for it" 1 "it includes it at main"
fc "include:
  - remote: $url
  - remote: https://raw.githubusercontent.com/coolbress/plinth/v1.16.0/gitlab/python-ci.yml"
expect "a second include at a tag fails beside a pinned one" 1 "it includes it at v1.16.0"
fc "include:
  - '$url'"
expect "a list item holding only the URL is an include" 0 "pass: .gitlab-ci.yml includes"
fc "include:
  - local: ci/plinth.yml
variables:
  remote: $url
.hidden:
  script:
    - '$url'"
expect "a pinned URL outside the top-level include node (a variable, a script list) is not the include" 1 "no include of https://raw.githubusercontent.com/coolbress/plinth/<commit-sha>/gitlab/python-ci.yml was found"
fc "include:
- remote: $url
  integrity: sha256-L3/GAoKaw0Arw6hDCKeKQlV1QPEgHYxGBHsH4zG1IY8=
stages: [test]"
expect "list items at the key's own indentation are the include" 0 "pass: .gitlab-ci.yml includes" "pass: the include names a checksum"
fc "include:
  - remote: $url
    integrity: sha256-L3/GAoKaw0Arw6hDCKeKQlV1QPEgHYxGBHsH4zG1IY8=
  - remote: https://raw.githubusercontent.com/coolbress/plinth/$(printf 'f%.0s' {1..40})/gitlab/python-ci.yml"
expect "a checksum on one of two includes is not a checksum on both" 0 "not yet confirmed: the bytes GitLab fetched are plinth's file, 1 of 2 includes names no checksum"
refuse "one checksum of two is not a pass" "pass: the include names a checksum"
fc "include:
  remote: $url
  integrity: sha256-L3/GAoKaw0Arw6hDCKeKQlV1QPEgHYxGBHsH4zG1IY8="
expect "the mapping form with a checksum passes" 0 "pass: .gitlab-ci.yml includes" "pass: the include names a checksum"
# An inline flow sequence or mapping is split into its includes, each judged
# on its own (#521); inline syntax that cannot be split fails, naming the line.
main_url="https://raw.githubusercontent.com/coolbress/plinth/main/gitlab/python-ci.yml"
sha2=fedcba9876543210fedcba9876543210fedcba98
url2="https://raw.githubusercontent.com/coolbress/plinth/$sha2/gitlab/python-ci.yml"
fc "include: ['$url', '$main_url']"
expect "a flow sequence with an unpinned second URL fails, naming it (#521)" 1 "it includes it at main"
fc "include: ['$url', \"$url2\"]"
expect "a flow sequence of two pinned URLs passes, and neither names a checksum" 0 "pass: .gitlab-ci.yml includes" "2 of 2 includes names no checksum"
fc "include: ['$url',
  '$main_url']"
expect "a flow sequence over two lines is read as YAML, and its unpinned URL fails" 1 "it includes it at main"
fc "include: {remote: '$url', integrity: 'sha256-L3/GAoKaw0Arw6hDCKeKQlV1QPEgHYxGBHsH4zG1IY8='}"
expect "an inline flow mapping is an include with its checksum" 0 "pass: .gitlab-ci.yml includes" "pass: the include names a checksum"
fc "include:
  - {remote: '$url', integrity: 'sha256-L3/GAoKaw0Arw6hDCKeKQlV1QPEgHYxGBHsH4zG1IY8='}
  - {remote: '$main_url'}"
expect "flow mappings as list items are judged one by one" 1 "it includes it at main"
fc "include: {remote: '$url', inputs: {label: \"a\\\"b, c\", note: 'it''s, ok'}}"
expect "an escaped quote inside a quoted flow value does not end it" 0 "pass: .gitlab-ci.yml includes" "the include names no checksum"
fc "include: {remote: '$url', inputs: {working-directory: \"dir #1\"}} # a comment"
expect "a # inside a quoted flow value is not a comment, one after it is" 0 "pass: .gitlab-ci.yml includes"
fc "include: [it's.yml, '$url', '$main_url'] # it's a comment"
expect "an apostrophe inside a plain value opens no quote" 1 "it includes it at main"
# Read with a YAML parser, not a scanner (#528): a duplicate key takes its
# last value, a quote inside a plain scalar opens nothing, GitLab's tags are
# data, a file that is not YAML fails naming why, and an install that fails
# fails the job.
fc "include: {remote: '$url', remote: '$main_url'}"
expect "a duplicate remote key is judged on its last value, as GitLab reads it (#528)" 1 "it includes it at main"
fc "include: [{remote: '$url', inputs: {x: foo:\"bar}}, {remote: '$main_url', inputs: {x: baz\"}}]"
expect "a quote inside a plain scalar does not hide the next include (#528)" 1 "it includes it at main"
fc "include: ['$url'
lint:
  script: [true]"
expect "a definition that is not YAML fails, naming the parser's error" 1 "it is not YAML that can be read ("
fc ".base:
  script: [true]
include:
  - remote: $url
    integrity: sha256-L3/GAoKaw0Arw6hDCKeKQlV1QPEgHYxGBHsH4zG1IY8=
job:
  script: !reference [.base, script]"
expect "GitLab's !reference tag is data, not a parse error" 0 "pass: .gitlab-ci.yml includes" "pass: the include names a checksum"
fc "include:
  - remote: $url
    integrity: sha256-L3/GAoKaw0Arw6hDCKeKQlV1QPEgHYxGBHsH4zG1IY8=
  - remote: $main_url?x=1"
expect "a plinth URL with a query is not left out: it fails, naming it" 1 "includes plinth by a URL that is not" "?x=1"
fc "include:
  - '$url'
  - https://cdn.jsdelivr.net/gh/coolbress/plinth@main/gitlab/python-ci.yml"
expect "plinth from another host fails, naming the URL" 1 "includes plinth by a URL that is not" "cdn.jsdelivr.net"
fc "spec:
  inputs:
    stage:
      default: test
---
include:
  - remote: $url
    integrity: sha256-L3/GAoKaw0Arw6hDCKeKQlV1QPEgHYxGBHsH4zG1IY8="
expect "an inputs header and its --- separator are read as GitLab lays them out" 0 "pass: .gitlab-ci.yml includes" "pass: the include names a checksum"
fc "a: 1
---
include: ['$url']
---
b: 2"
expect "three documents are not a layout GitLab reads: it fails" 1 "not the layout GitLab reads"
d="$tmp/fc-noinstall"; mkdir -p "$d"; printf 'include:\n  - remote: %s\n' "$url" > "$d/.gitlab-ci.yml"
(cd "$d" && PIP_INDEX_URL=http://127.0.0.1:9/simple PIP_NO_CACHE_DIR=1 PIP_RETRIES=0 PIP_TIMEOUT=2 run_job floor-check \
   && printf '%s\n%s' "$rc" "$out" > "$tmp/o"); rc="$(head -1 "$tmp/o")"; out="$(cat "$tmp/o")"
expect "PyYAML that does not install fails the job, never passes it" 1 "PyYAML did not install"
fc "# include:
#   - remote: $url
lint:
  script: [true]"
expect "an include only in a comment fails" 1 "no include of https://raw.githubusercontent.com/coolbress/plinth/<commit-sha>/gitlab/python-ci.yml was found"
d="$tmp/fc-none"; mkdir -p "$d"
(cd "$d" && run_job floor-check && printf '%s\n%s' "$rc" "$out" > "$tmp/o"); rc="$(head -1 "$tmp/o")"; out="$(cat "$tmp/o")"
expect "no pipeline definition fails" 1 "it could not be read"
d="$tmp/fc-custom"; mkdir -p "$d/ci"; printf 'include:\n  - remote: %s\n' "$url" > "$d/ci/pipeline.yml"
(cd "$d" && CI_CONFIG_PATH=ci/pipeline.yml run_job floor-check && printf '%s\n%s' "$rc" "$out" > "$tmp/o"); rc="$(head -1 "$tmp/o")"; out="$(cat "$tmp/o")"
expect "a custom CI_CONFIG_PATH is the file read" 0 "pass: ci/pipeline.yml includes"

echo "-- diff-size"
repo="$tmp/ds"; mkdir -p "$repo/tests"
git -C "$repo" init -q -b main; git -C "$repo" config user.email t@example.com; git -C "$repo" config user.name t
git -C "$repo" config commit.gpgsign false
printf 'on: x\n' > "$repo/.gitlab-ci.yml"; printf 'def test_a():\n    assert 1\n' > "$repo/tests/test_a.py"
git -C "$repo" add -A; git -C "$repo" commit -qm base; base="$(git -C "$repo" rev-parse HEAD)"
seq 1 30 > "$repo/a.py"; printf 'more: x\n' >> "$repo/.gitlab-ci.yml"; printf 'x\n' > "$repo/notes.md"
git -C "$repo" add -A; git -C "$repo" commit -qm head; head="$(git -C "$repo" rev-parse HEAD)"
ds() { # <max> <description>
  (cd "$repo" && CI_MERGE_REQUEST_IID=1 CI_MERGE_REQUEST_DIFF_BASE_SHA="$base" CI_COMMIT_SHA="$head" CI_MERGE_REQUEST_DESCRIPTION="$2" \
     PLINTH_WORKDIR=. PLINTH_MAX_DIFF_LINES="$1" PLINTH_DIFF_SIZE_EXCLUDE="*.md" run_job diff-size \
     && printf '%s\n%s' "$rc" "$out" > "$tmp/o"); rc="$(head -1 "$tmp/o")"; out="$(cat "$tmp/o")"
}
ds 400 "a change"
expect "within the limit passes, docs excluded" 0 "pass: diff size, 31 lines, within the limit of 400"
expect "an unnamed pipeline change is a WARN" 0 "WARN: .gitlab-ci.yml: the pipeline definition changed, and the description does not name it."
ds 20 "changes .gitlab-ci.yml"
expect "over the limit fails" 1 "fail: diff size, 31 lines, over the limit of 20"
expect "a named pipeline change is listed as named" 1 "named in the description: .gitlab-ci.yml"
ds 0 "x"
expect "max-diff-lines 0 measures without blocking" 0 "pass: diff size, measured and not enforced (max-diff-lines is 0): 31 lines"

# The archetype: line of .copier-answers.yml (#625): /plinth:floor-check reads
# its conditional items from it, so a change to the line, or the file deleted or
# moved, is listed; another answer changed with the line kept is not.
arepo="$tmp/ds-archetype"; mkdir -p "$arepo"
git -C "$arepo" init -q -b main; git -C "$arepo" config user.email t@example.com; git -C "$arepo" config user.name t
git -C "$arepo" config commit.gpgsign false
printf '_commit: v1.21.0\narchetype: backend\nhost: gitlab\n' > "$arepo/.copier-answers.yml"
git -C "$arepo" add -A; git -C "$arepo" commit -qm base; abase="$(git -C "$arepo" rev-parse HEAD)"
git -C "$arepo" checkout -q -b case
dsa() { # <description>: commits the working tree's change on a branch off abase, judges it, then starts the next branch there
  git -C "$arepo" add -A; git -C "$arepo" commit -qm head; ahead="$(git -C "$arepo" rev-parse HEAD)"
  (cd "$arepo" && CI_MERGE_REQUEST_IID=1 CI_MERGE_REQUEST_DIFF_BASE_SHA="$abase" CI_COMMIT_SHA="$ahead" CI_MERGE_REQUEST_DESCRIPTION="$1" \
     PLINTH_WORKDIR=. PLINTH_MAX_DIFF_LINES=400 PLINTH_DIFF_SIZE_EXCLUDE="" run_job diff-size \
     && printf '%s\n%s' "$rc" "$out" > "$tmp/o"); rc="$(head -1 "$tmp/o")"; out="$(cat "$tmp/o")"
  git -C "$arepo" checkout -q main; git -C "$arepo" branch -q -D case; git -C "$arepo" checkout -q -b case
}
sed -i.bak 's/^archetype: backend$/archetype: cli/' "$arepo/.copier-answers.yml"; rm "$arepo/.copier-answers.yml.bak"; dsa "Refactor."
expect "archetype backend to cli: listed, a WARN when the description does not name it" 0 \
  "WARN: .copier-answers.yml: the archetype: line of .copier-answers.yml changed, or the file deleted or moved, and the description does not name it."
git -C "$arepo" rm -q .copier-answers.yml; dsa "Refactor."
expect ".copier-answers.yml deleted: listed whatever its content" 0 \
  "WARN: .copier-answers.yml: the archetype: line of .copier-answers.yml changed, or the file deleted or moved, and the description does not name it."
sed -i.bak 's/^_commit: v1.21.0$/_commit: v1.22.0/' "$arepo/.copier-answers.yml"; rm "$arepo/.copier-answers.yml.bak"; dsa "Updates the template."
expect ".copier-answers.yml changed with the archetype: line kept: not listed" 0 "0 change(s) to the checks, 0 not named in the description."
refuse "and the archetype row is not in the log" "archetype: line"

# The agent's own rules (#657), as on GitHub (#651): a project with the five
# kinds as plinth-template renders them, plus files that only look like them.
# Each case starts from a fresh copy of that project.
grepo="$tmp/ds-agent"
agent_repo() {
  rm -rf "$grepo"; mkdir -p "$grepo/.claude/skills/verify" "$grepo/.claude/output-styles" "$grepo/.gitlab/ci" "$grepo/docs" "$grepo/pkg" "$grepo/src"
  git -C "$grepo" init -q -b main; git -C "$grepo" config user.email t@example.com; git -C "$grepo" config user.name t
  git -C "$grepo" config commit.gpgsign false
  printf '# Rules\n' > "$grepo/AGENTS.md"; ln -s AGENTS.md "$grepo/CLAUDE.md"
  printf '{"permissions": {"deny": ["Bash(cat:*)"]}}\n' > "$grepo/.claude/settings.json"
  printf -- '---\nname: verify\n---\n' > "$grepo/.claude/skills/verify/SKILL.md"
  printf -- '---\nname: plain\n---\n' > "$grepo/.claude/output-styles/plain.md"
  printf '# Notes\n' > "$grepo/docs/AGENTS-notes.md"; printf '# Pkg\n' > "$grepo/pkg/CLAUDE.md"
  printf 'include: []\n' > "$grepo/.gitlab-ci.yml"; printf 'job: {}\n' > "$grepo/.gitlab/ci/jobs.yml"
  printf 'x = 1\n' > "$grepo/src/m.py"
  git -C "$grepo" add -A; git -C "$grepo" commit -qm base; gbase="$(git -C "$grepo" rev-parse HEAD)"
}
dsg() { # <description>: commits the working tree's change and judges it
  git -C "$grepo" add -A; git -C "$grepo" commit -qm head; ghead="$(git -C "$grepo" rev-parse HEAD)"
  (cd "$grepo" && CI_MERGE_REQUEST_IID=1 CI_MERGE_REQUEST_DIFF_BASE_SHA="$gbase" CI_COMMIT_SHA="$ghead" CI_MERGE_REQUEST_DESCRIPTION="$1" \
     PLINTH_WORKDIR=. PLINTH_MAX_DIFF_LINES=400 PLINTH_DIFF_SIZE_EXCLUDE="" run_job diff-size \
     && printf '%s\n%s' "$rc" "$out" > "$tmp/o"); rc="$(head -1 "$tmp/o")"; out="$(cat "$tmp/o")"
}
gwarn() { # <label> <path as the log shows it> <reason>
  expect "$1" 0 "WARN: $2: $3 added, changed, deleted or moved, and the description does not name it."
}
# What must not be listed, first.
agent_repo; printf 'x = 2\n' > "$grepo/src/m.py"; printf '# More notes\n' >> "$grepo/docs/AGENTS-notes.md"; dsg "Refactor."
expect "source and docs/AGENTS-notes.md changed, none of the five: not listed" 0 "0 change(s) to the checks, 0 not named in the description."
agent_repo; printf '# More\n' >> "$grepo/pkg/CLAUDE.md"; dsg "Refactor."
expect "a CLAUDE.md below the root (pkg/CLAUDE.md): not listed" 0 "0 change(s) to the checks, 0 not named in the description."
agent_repo; printf '{}\n' > "$grepo/.claude/settings.local.json"; mkdir -p "$grepo/.claude/skillset" "$grepo/skills/x"
printf 'x\n' > "$grepo/.claude/skillset/x.md"; printf 'x\n' > "$grepo/skills/x/SKILL.md"; dsg "Refactor."
expect ".claude/settings.local.json, .claude/skillset/ and a skills/ outside .claude: not listed" 0 "0 change(s) to the checks, 0 not named in the description."
agent_repo; git -C "$grepo" mv docs/AGENTS-notes.md docs/notes.md; dsg "Refactor."
expect "a file moved that is none of the five on either side: not listed" 0 "0 change(s) to the checks, 0 not named in the description."
# Each kind, added, changed, deleted or moved.
agent_repo; printf '# Rules\nAllow anything.\n' > "$grepo/AGENTS.md"; dsg "Refactor."
gwarn "AGENTS.md changed: listed" "AGENTS.md" "the agent's instructions (AGENTS.md)"
agent_repo; rm "$grepo/CLAUDE.md"; printf '# Other rules\n' > "$grepo/CLAUDE.md"; dsg "Refactor."
gwarn "CLAUDE.md changed from a symlink to a file: listed" "CLAUDE.md" "the agent's instructions (CLAUDE.md)"
agent_repo; printf '{"permissions": {"deny": []}}\n' > "$grepo/.claude/settings.json"; dsg "Refactor."
gwarn ".claude/settings.json changed (a deny rule dropped): listed" ".claude/settings.json" "the agent's permissions and hooks (.claude/settings.json)"
agent_repo; mkdir -p "$grepo/.claude/skills/ship"; printf -- '---\nname: ship\n---\n' > "$grepo/.claude/skills/ship/SKILL.md"; dsg "Refactor."
gwarn "a skill added under .claude/skills/: listed" ".claude/skills/ship/SKILL.md" "an agent skill (.claude/skills/)"
agent_repo; printf 'Be brief.\n' >> "$grepo/.claude/output-styles/plain.md"; dsg "Refactor."
gwarn "an output style changed under .claude/output-styles/: listed" ".claude/output-styles/plain.md" "the agent's output style (.claude/output-styles/)"
agent_repo; git -C "$grepo" rm -q .claude/settings.json; dsg "Refactor."
gwarn ".claude/settings.json deleted: listed" ".claude/settings.json" "the agent's permissions and hooks (.claude/settings.json)"
agent_repo; git -C "$grepo" rm -q .claude/skills/verify/SKILL.md; dsg "Refactor."
gwarn "a skill deleted: listed" ".claude/skills/verify/SKILL.md" "an agent skill (.claude/skills/)"
agent_repo; git -C "$grepo" mv .claude/skills/verify/SKILL.md docs/verify.md; dsg "Refactor."
gwarn "a skill moved out of .claude/skills/: listed" ".claude/skills/verify/SKILL.md -> docs/verify.md" "an agent skill (.claude/skills/)"
agent_repo; git -C "$grepo" mv -f docs/AGENTS-notes.md AGENTS.md; dsg "Refactor."
gwarn "a file moved onto AGENTS.md: listed" "AGENTS.md" "the agent's instructions (AGENTS.md)"
agent_repo; git -C "$grepo" mv .claude/skills/verify .claude/skills/check; dsg "Refactor."
gwarn "a skill renamed inside .claude/skills/: listed" ".claude/skills/verify/SKILL.md -> .claude/skills/check/SKILL.md" "an agent skill (.claude/skills/)"
# Checked before the pipeline-definition kind: a move between .gitlab/ci/ and
# the agent's rules gives the agent's reason, as GitHub's does.
agent_repo; git -C "$grepo" mv .claude/skills/verify/SKILL.md .gitlab/ci/verify.md; dsg "Refactor."
gwarn "a skill moved into .gitlab/ci/: listed as an agent skill" ".claude/skills/verify/SKILL.md -> .gitlab/ci/verify.md" "an agent skill (.claude/skills/)"
agent_repo; mkdir -p "$grepo/.claude/skills/ci"; git -C "$grepo" mv .gitlab/ci/jobs.yml .claude/skills/ci/SKILL.md; dsg "Refactor."
gwarn "a pipeline file moved out of .gitlab/ci/ into .claude/skills/: listed as an agent skill" \
  ".gitlab/ci/jobs.yml -> .claude/skills/ci/SKILL.md" "an agent skill (.claude/skills/)"
agent_repo; printf '{"permissions": {"allow": ["Bash"]}}\n' > "$grepo/.claude/settings.json"; dsg "Widens the allow list in .claude/settings.json."
expect "named in the description: listed as named, no WARN" 0 \
  "named in the description: .claude/settings.json: the agent's permissions and hooks (.claude/settings.json) added, changed, deleted or moved" \
  "1 change(s) to the checks, 0 not named in the description."

(cd "$repo" && CI_MERGE_REQUEST_IID='' CI_OPEN_MERGE_REQUESTS='g/p!3' PLINTH_WORKDIR=. PLINTH_MAX_DIFF_LINES=400 PLINTH_DIFF_SIZE_EXCLUDE="" run_job diff-size \
   && printf '%s\n%s' "$rc" "$out" > "$tmp/o"); rc="$(head -1 "$tmp/o")"; out="$(cat "$tmp/o")"
expect "a branch pipeline while a merge request is open fails" 1 "fail: diff size, this is a branch pipeline while merge request g/p!3 is open"

echo "-- temporary directories (#575)"
made="$(find "$tmp/job-tmp" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
if [ "$made" -gt 0 ]; then ok "the jobs made their $made temporary directories under the test's own"
else bad "the jobs made no temporary directory under the test's own: TMPDIR did not reach them"; fi
new="$(comm -13 <(printf '%s\n' "$caller_before") <(caller_dirs) | sed '/^$/d')"
if [ -z "$new" ]; then ok "no new tmp.* directory where a bare mktemp -d lands ($caller_tmp)"
else bad "new tmp.* directories where a bare mktemp -d lands: the jobs' leak, or another process's" "$new"; fi

echo "-- $fail failed, $pass passed"
[ "$fail" = 0 ]
