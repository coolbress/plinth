#!/usr/bin/env bash
# Every tool download from a github.com release in python-ci.yml, plinth-ci.yml
# and e2e.yml sends the job's token (#878). An anonymous request is the class
# GitHub sheds first: on 2026-11-09 it answered anonymous requests with 504 for
# about two hours while authenticated ones went through, and every consumer's
# required checks download uv from a release.
#
# The form is one, so this test can read it:
#   GITHUB_TOKEN: ${{ github.token }}          (in the step's env)
#   curl ... ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} ... \
#     "https://github.com/<owner>/<repo>/releases/download/..."
# An empty or missing token leaves the request anonymous, as before. curl sends
# a header given with -H to the first host only: the redirect to the storage
# host goes without it, unless --location-trusted, which this test refuses.
# gitlab/python-ci.yml is not read: a GitLab pipeline has no GitHub token.
#
# Two parts: the workflows' text, with must-not-pass cases first, then one real
# download of the pinned uv with and without a token, with `curl -v` showing
# which host got the header (the value masked). Reads the network; an
# unreadable download is a FAIL.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
files=(python-ci.yml plinth-ci.yml e2e.yml)
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

cat >"$work/check.py" <<'PY'
# check.py <file>...: one line per release download that does not send the
# token; exit 1 when there is one, 2 when a file has no release download at all.
import re, sys
FRAG = '${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"}'
ENV = re.compile(r'^\s+GITHUB_TOKEN: \$\{\{ (github\.token|secrets\.GITHUB_TOKEN) \}\}\s*$')
URL = re.compile(r'https://github\.com/[^/\s"]+/[^/\s"]+/releases/(latest/)?download/')
STEP = re.compile(r'^(\s*)- (name|uses|id|run|env|if|with):')
problems, empty = [], []
for path in sys.argv[1:]:
    lines = open(path).read().splitlines()
    found = 0
    for n, line in enumerate(lines):
        if not URL.search(line) or line.lstrip().startswith("#"):
            continue
        found += 1
        # The command: this line and the backslash-continued lines before it.
        start = n
        while start > 0 and lines[start - 1].rstrip().endswith("\\"):
            start -= 1
        cmd = " ".join(lines[start:n + 1])
        # The step: back to the nearest `- ` at a step's indent.
        s = n
        while s > 0 and not STEP.match(lines[s]):
            s -= 1
        step = lines[s:n]
        where = f"{path.rsplit('/', 1)[-1]}:{n + 1}"
        if not re.search(r'\bcurl\b', cmd):
            problems.append(f"{where}: a release download that is not curl; write it in the form this test reads")
        elif FRAG not in cmd:
            problems.append(f"{where}: curl to a github.com release without {FRAG}")
        elif "--location-trusted" in cmd:
            problems.append(f"{where}: --location-trusted sends the token to the redirect host too")
        elif not any(ENV.match(l) for l in step):
            problems.append(f"{where}: the step's env has no GITHUB_TOKEN: ${{{{ github.token }}}}")
    if not found:
        empty.append(path)
for p in problems:
    print(p)
for p in empty:
    print(f"{p}: no github.com release download found; this test reads nothing there")
sys.exit(1 if problems else 2 if empty else 0)
PY
check() { python3 "$work/check.py" "$@"; }

# A copy of the three workflows with the first <old> in one of them replaced by
# <new>, literally, so a seeded fault sits in a real step.
seed() { # <file> <old> <new>
  rm -rf "$work/w"; mkdir "$work/w"
  for f in "${files[@]}"; do cp "$root/.github/workflows/$f" "$work/w/"; done
  python3 -c 'import sys; p, o, n = sys.argv[1:]; t = open(p).read(); open(p, "w").write(t.replace(o, n, 1))' \
    "$work/w/$1" "$2" "$3"
}
must_refuse() { # <what> <file> <old> <new> <what the output must name>
  local out rc
  seed "$2" "$3" "$4"
  if cmp -s "$work/w/$2" "$root/.github/workflows/$2"; then bad "$1: the seed changed nothing"; return; fi
  out="$(check "$work/w/"*.yml 2>&1)"; rc=$?
  if [ "$rc" = 1 ] && grep -qF -- "$5" <<<"$out"; then ok "$1 fails (must not pass)"
  else bad "$1 passed or failed without naming it (exit $rc): $out"; fi
}

echo "must not pass:"
frag='${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} '
for f in "${files[@]}"; do
  must_refuse "$f: a download without the token" "$f" "$frag" "" "curl to a github.com release without"
done
must_refuse "a token in a step with no GITHUB_TOKEN in its env" e2e.yml \
  '          GITHUB_TOKEN: ${{ github.token }}'$'\n' "" "the step's env has no GITHUB_TOKEN"
must_refuse "--location-trusted" python-ci.yml "$frag" "$frag--location-trusted " "--location-trusted"
seed e2e.yml "" ""
python3 -c 'import sys; p, frag = sys.argv[1:]; t = open(p).read(); open(p, "w").write(t.replace(frag, "", 1).replace("/releases/download/${UV_VERSION}/", "/releases/latest/download/", 1))' \
  "$work/w/e2e.yml" "$frag"
out="$(check "$work/w/"*.yml 2>&1)"; rc=$?
[ "$rc" = 1 ] && grep -qF "curl to a github.com release without" <<<"$out" && ok "a releases/latest/download URL without the token fails (must not pass)" ||
  bad "a releases/latest/download URL without the token passed (exit $rc)"
must_refuse "a release download by wget" plinth-ci.yml "curl -fsSL --retry 3 $frag" "wget -q " "not curl"
seed e2e.yml "" ""  # then every release URL in it moved off github.com
python3 -c 'import sys; p = sys.argv[1]; t = open(p).read(); open(p, "w").write(t.replace("https://github.com/", "https://example.invalid/"))' "$work/w/e2e.yml"
check "$work/w/"*.yml >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "a file with no release download left fails (must not pass)" ||
  bad "a file with no release download passed (exit $rc)"

echo "the workflows:"
if out="$(check "${files[@]/#/$root/.github/workflows/}" 2>&1)"; then
  n="$(cat "${files[@]/#/$root/.github/workflows/}" | grep -cE 'https://github\.com/[^/]+/[^/]+/releases/(latest/)?download/')"
  ok "every github.com release download sends the token ($n: ${files[*]})"
else bad "a release download is anonymous:"; printf '%s\n' "$out"; fi

# The real thing, on this machine's curl: the uv release the workflows pin, its
# checksum, and which hosts the header went to. In CI the token is the job's
# own, masked in the log; elsewhere a placeholder, which github.com ignores.
echo "one real download (curl $(curl --version | head -n 1 | cut -d' ' -f2)):"
wf="$root/.github/workflows/python-ci.yml"
v="$(sed -n 's/^ *UV_VERSION: "\(.*\)"$/\1/p' "$wf" | head -n 1)"
sum="$(sed -n 's/^ *UV_SHA256: "\(.*\)"$/\1/p' "$wf" | head -n 1)"
u="https://github.com/astral-sh/uv/releases/download/${v}/uv-x86_64-unknown-linux-gnu.tar.gz"
download() { # <token or empty> <log>: the workflows' own curl form, with -v
  GITHUB_TOKEN="$1" bash -c 'curl -fsSL -v --retry 3 ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} -o "$1" "$2"' _ "$work/uv.tgz" "$u" 2>"$2"
}
hosts() { # <log>: "<host> <auth|none>" per request, in order
  awk 'tolower($0) ~ /^> host:/ { if (h) print h, a; h=$3; a="none" }
       tolower($0) ~ /^> authorization:/ { a="auth" }
       END { if (h) print h, a }' "$1" | tr -d '\r'
}
shown() { grep -iE '^> (host|authorization):|^< (HTTP|location):' "$1" | tr -d '\r' |
  sed -E 's/^(> [Aa]uthorization:).*/\1 ***/; s/^(< location: [^?]*)\?.*/\1?.../I; s/^/        /'; }
token="${GITHUB_TOKEN:-placeholder-not-a-token}"
[ -n "${GITHUB_TOKEN:-}" ] && echo "        with the job's token" || echo "        with a placeholder token (no GITHUB_TOKEN here)"
for t in "$token" ""; do
  label="$([ -n "$t" ] && echo "with a token" || echo "with no token")"
  rm -f "$work/uv.tgz"
  if ! download "$t" "$work/log"; then bad "$label: the download failed: $(grep -i 'curl:' "$work/log" | tail -n 1)"; continue; fi
  shown "$work/log"
  if echo "$sum  $work/uv.tgz" | sha256sum -c - >/dev/null 2>&1 || echo "$sum  $work/uv.tgz" | shasum -a 256 -c - >/dev/null 2>&1
  then ok "$label: uv $v downloaded and its checksum verified"
  else bad "$label: uv $v downloaded but its checksum is not $sum"; fi
  got="$(hosts "$work/log" | paste -sd, -)"
  if [ -n "$t" ]; then
    # The first request, to github.com, with it; every redirect after it without.
    if [[ "$got" =~ ^github\.com\ auth,.+$ ]] && [[ "${got#*,}" != *auth* ]]; then
      ok "$label: the header went to github.com and not to the redirect host ($got)"
    else bad "$label: expected the header on github.com only and on no redirect after it; got $got"; fi
  else
    [[ "$got" != *auth* ]] && ok "$label: no header on any request ($got)" || bad "$label: a header was sent ($got)"
  fi
done

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
