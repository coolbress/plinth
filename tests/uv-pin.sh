#!/usr/bin/env bash
# Every uv release a workflow downloads is one version and one checksum (#841): the
# copies in this repository, and the template's rendered release workflows at
# the tag scripts/new-project.sh pins. Dependabot never raises a version written
# in an environment variable, so nothing else keeps them together; two that
# disagree fail here, and so does a checksum that is not the release's own. The
# `ghcr.io/astral-sh/uv` images in Dockerfiles are not these: they are pinned by
# digest, and this test does not read them.
#
# The order of a raise follows from it: the template's copies first, in a
# template release, then plinth's copies and `template_ref` in one pull request.
# Before that tag exists, read the template's branch:
#   TEMPLATE_URL=<path or URL> TEMPLATE_REF=<branch> tests/uv-pin.sh
# Reads the network: the template and the release's checksum, and unreadable is
# a FAIL. The must-not-pass cases run first.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template_url="${TEMPLATE_URL:-https://github.com/coolbress/plinth-template}"
ref="${TEMPLATE_REF:-$(sed -n 's/^template_ref="\(.*\)"$/\1/p' "$root/scripts/new-project.sh")}"
tarball="uv-x86_64-unknown-linux-gnu.tar.gz"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

cat >"$work/pins.py" <<'PY'
# pins.py <tree>: stdout "<version> <sha256> <copies>" and, on stderr, one line
# per file; exit 1 with the reason when the tree's copies are not one pin. A
# file counts when it downloads uv or names a pin; Markdown only describes one,
# and tests/ holds this test's own fixtures.
import os, re, sys
TARBALL = 'f="uv-x86_64-unknown-linux-gnu.tar.gz"'
URL = "astral-sh/uv/releases/download/"
SKIP = {".git", ".claude", ".venv", "node_modules", "tests", "evidence"}
tree = sys.argv[1]
problems, versions, shas, copies = [], set(), set(), 0
for d, dirs, names in os.walk(tree):
    dirs[:] = [x for x in dirs if x not in SKIP]
    for name in sorted(names):
        if name.endswith(".md"):
            continue
        path = os.path.join(d, name)
        if os.path.islink(path):  # not a copy, and a template's may dangle
            continue
        with open(path, errors="ignore") as fh:
            text = fh.read()
        v = re.findall(r'\bUV_VERSION: "([^"]*)"', text)
        s = re.findall(r'\bUV_SHA256: "([^"]*)"', text)
        urls = text.count(URL)
        if not (v or s or urls):
            continue
        rel = os.path.relpath(path, tree)
        through_pin = text.count(URL + "${UV_VERSION}/$f")
        if not len(v) == len(s) == urls == through_pin == text.count(TARBALL):
            problems.append(f"{rel}: {urls} download(s), {through_pin} through ${{UV_VERSION}}, "
                            f"{text.count(TARBALL)} of the linux tarball, {len(v)} UV_VERSION, {len(s)} UV_SHA256")
        bad = [x for x in s if not re.fullmatch(r"[0-9a-f]{64}", x)]
        if bad:
            problems.append(f"{rel}: UV_SHA256 is not a sha256: {bad[0]!r}")
        versions.update(v); shas.update(s); copies += len(v)
        print(f"        {rel}: {len(v)}", file=sys.stderr)
if copies == 0:
    problems.append("no uv pin found")
if len(versions) > 1:
    problems.append("versions disagree: " + ", ".join(sorted(versions)))
if len(shas) > 1:
    problems.append("checksums disagree: " + ", ".join(sorted(shas)))
if problems:
    print("; ".join(problems))
    sys.exit(1)
print(versions.pop(), shas.pop(), copies)
PY
pins() { python3 "$work/pins.py" "$1"; }

# copy <dir> <file> <version> <sha>: one install step, in the shape the workflows use.
A="1111111111111111111111111111111111111111111111111111111111111111"
B="2222222222222222222222222222222222222222222222222222222222222222"
copy() {
  mkdir -p "$(dirname "$1/$2")"
  cat >>"$1/$2" <<EOF
          UV_VERSION: "$3"
          UV_SHA256: "$4"
          f="$tarball"
          curl -o "\$d/\$f" "https://github.com/astral-sh/uv/releases/download/\${UV_VERSION}/\$f"
EOF
}

# Must not pass.
t="$work/same"; copy "$t" a.yml 1.2.3 "$A"; copy "$t" a.yml 1.2.3 "$A"; copy "$t" 'b/{% if x %}c.yml{% endif %}' 1.2.3 "$A"
if out="$(pins "$t" 2>/dev/null)" && [ "$out" = "1.2.3 $A 3" ]; then ok "three copies of one pin read as one, whatever the file is called"
else bad "three copies of one pin: $out"; fi

t="$work/version"; copy "$t" a.yml 1.2.3 "$A"; copy "$t" b.yml 1.2.4 "$A"
if out="$(pins "$t" 2>/dev/null)"; then bad "two versions pass: $out"; else ok "two versions fail ($out)"; fi

t="$work/sum"; copy "$t" a.yml 1.2.3 "$A"; copy "$t" b.yml 1.2.3 "$B"
if out="$(pins "$t" 2>/dev/null)"; then bad "two checksums pass: $out"; else ok "two checksums fail ($out)"; fi

t="$work/short"; copy "$t" a.yml 1.2.3 "abc"
if out="$(pins "$t" 2>/dev/null)"; then bad "a checksum that is no sha256 passes: $out"; else ok "a checksum that is no sha256 fails ($out)"; fi

t="$work/hardcoded"; copy "$t" a.yml 1.2.3 "$A"
printf '%s\n' 'curl -o x https://github.com/astral-sh/uv/releases/download/9.9.9/uv.tar.gz' >>"$t/a.yml"
if out="$(pins "$t" 2>/dev/null)"; then bad "a download past the pin passes: $out"; else ok "a download past the pin fails ($out)"; fi

t="$work/nosum"; mkdir -p "$t"; printf '          UV_VERSION: "1.2.3"\n' >"$t/a.yml"
if out="$(pins "$t" 2>/dev/null)"; then bad "a version with no checksum passes: $out"; else ok "a version with no checksum fails ($out)"; fi

t="$work/none"; mkdir -p "$t"; printf 'nothing here\n' >"$t/a.yml"
if out="$(pins "$t" 2>/dev/null)"; then bad "a tree with no pin passes: $out"; else ok "a tree with no pin fails ($out)"; fi

t="$work/skipped"; copy "$t" a.yml 1.2.3 "$A"; copy "$t" tests/fixture.yml 0.0.1 "$B"
printf 'UV_VERSION: "0.0.1"\n' >"$t/notes.md"
if out="$(pins "$t" 2>/dev/null)" && [ "$out" = "1.2.3 $A 1" ]; then ok "fixtures under tests/ and Markdown are not pins"
else bad "fixtures under tests/ and Markdown: $out"; fi

# The real files.
echo "  plinth's copies:"
if here="$(pins "$root")"; then
  read -r version sha copies <<<"$here"
  ok "plinth's $copies copies name uv $version"
else
  version=""; bad "plinth's copies are not one pin: $here"
fi

if [ -n "$version" ]; then
  upstream="$(curl -fsSL --retry 3 "https://github.com/astral-sh/uv/releases/download/$version/$tarball.sha256" 2>/dev/null | awk '{print $1}')"
  if [ -z "$upstream" ]; then bad "could not read uv $version's checksum from its release; cannot verify"
  elif [ "$upstream" = "$sha" ]; then ok "the checksum is the one uv $version's release publishes for $tarball"
  else bad "uv $version's release publishes $upstream for $tarball; the pin says $sha"; fi
fi

echo "  the template's copies at $ref:"
if git clone -q --depth 1 --branch "$ref" -c advice.detachedHead=false "$template_url" "$work/template" 2>/dev/null; then
  if there="$(pins "$work/template")"; then
    if [ -n "$version" ] && [ "${there% *}" = "$version $sha" ]; then ok "the template at $ref names the same pin (${there##* } copies)"
    else bad "the template at $ref pins ${there% *}; plinth pins ${version:-nothing agreed}. Raise the template's first, release it, then raise plinth's and template_ref in one pull request"; fi
  else
    bad "the template's copies at $ref are not one pin: $there"
  fi
else
  bad "could not read the template at $ref; cannot verify"
fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
