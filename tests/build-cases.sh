#!/usr/bin/env bash
# `ci / build` on fixture projects (#889), python-ci.yml's two steps and
# gitlab/python-ci.yml's job. The steps are not copied here: they are
# extracted and run as the runner runs them, so the rule tested is the rule
# shipped. `uv` is a shim that logs each call and runs the real one, so a
# case can say which commands ran.
#
# Fixtures: a project without a workspace, and a uv workspace whose root
# depends on a member, beside a packaged member it does not depend on, a
# member with no [build-system], one with `tool.uv.package = false` and one
# excluded, each of whose modules exits on import, and a member named like a
# PyPI package; and a workspace whose root uv does not package.
#
# Needs uv and python3, and the network: the build backend (hatchling) comes
# from PyPI, and the failing case asks PyPI for the member.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="$root/.github/workflows/python-ci.yml"
gl="$root/gitlab/python-ci.yml"

real_uv="$(command -v uv)" || { echo "  FAIL  uv is not installed"; exit 1; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/build-cases.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

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
i = next((k for k in range(at, end) if lines[k].strip() == "run: |"), None)
if i is None:
    sys.exit(f"not a run: | block: {job} / {name}")
indent = None
for l in lines[i + 1:end]:
    if l.strip() and indent is None:
        indent = len(l) - len(l.lstrip())
    if l.strip() and len(l) - len(l.lstrip()) < indent:
        break
    print(l[indent:] if l.strip() else "")
PY
}
# A GitLab job's `- |` block under script: (before_script: for .plinth), dedented.
gl_job() {
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
job_step build build > "$tmp/gh-build.sh" || { bad "build / build: not found in python-ci.yml" "$(cat "$tmp/gh-build.sh")"; exit 1; }
job_step build "Install smoke, wheel and sdist into a clean venv" > "$tmp/gh-smoke.sh" \
  || { bad "build / install smoke: not found in python-ci.yml"; exit 1; }
gl_job .plinth > "$tmp/gl-helpers.sh" && gl_job build > "$tmp/gl-build.sh" \
  || { bad "build: not found in gitlab/python-ci.yml"; exit 1; }

mkdir -p "$tmp/bin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$UV_LOG"\nexec %q "$@"\n' "$real_uv" > "$tmp/bin/uv"
chmod +x "$tmp/bin/uv"

# --- fixtures -------------------------------------------------------------
pkg() { # <dir> <name> <dependencies, TOML list body> <extra TOML>...
  local d="$1" name="$2" deps="$3"; shift 3
  mkdir -p "$d/src/$(printf '%s' "$name" | tr '.-' '__')"
  { printf '[project]\nname = "%s"\nversion = "0.1.0"\nrequires-python = ">=3.11"\ndependencies = [%s]\n' "$name" "$deps"
    printf '%s\n' "$@"; } > "$d/pyproject.toml"
}
backend='[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"'

single="$tmp/fixture-single"
pkg "$single" plinth-fixture-plain "" "$backend"
echo 'X = 1' > "$single/src/plinth_fixture_plain/__init__.py"

ws="$tmp/fixture-workspace"
pkg "$ws" plinth-fixture-app '"plinth-fixture-core", "six"' "$backend" \
  '[tool.uv.sources]' 'plinth-fixture-core = { workspace = true }' 'six = { workspace = true }' \
  '[tool.uv.workspace]' 'members = ["packages/*"]' 'exclude = ["packages/skipped"]'
printf 'from plinth_fixture_core import X\nfrom six import WORKSPACE\n' > "$ws/src/plinth_fixture_app/__init__.py"
# Named as a package on PyPI (six 1.17.0 there): the root must get this one.
pkg "$ws/packages/six" six "" "$backend"
echo 'WORKSPACE = True' > "$ws/packages/six/src/six/__init__.py"
pkg "$ws/packages/core" plinth-fixture-core "" "$backend"
echo 'X = 1' > "$ws/packages/core/src/plinth_fixture_core/__init__.py"
# Not packaged: no [build-system], or one with tool.uv.package = false.
pkg "$ws/packages/virtual" plinth-fixture-virtual ""
echo 'raise SystemExit("plinth_fixture_virtual was imported")' > "$ws/packages/virtual/src/plinth_fixture_virtual/__init__.py"
pkg "$ws/packages/unpackaged" plinth-fixture-unpackaged "" "$backend" '[tool.uv]' 'package = false'
echo 'raise SystemExit("plinth_fixture_unpackaged was imported")' > "$ws/packages/unpackaged/src/plinth_fixture_unpackaged/__init__.py"
# Packaged, but not a dependency of the root: built, not installed, not imported.
pkg "$ws/packages/extra" plinth-fixture-extra "" "$backend"
echo 'raise SystemExit("plinth_fixture_extra was imported")' > "$ws/packages/extra/src/plinth_fixture_extra/__init__.py"
# Packaged, but excluded from the workspace.
pkg "$ws/packages/skipped" plinth-fixture-skipped "" "$backend"
echo 'raise SystemExit("plinth_fixture_skipped was imported")' > "$ws/packages/skipped/src/plinth_fixture_skipped/__init__.py"

# A root uv does not package (no [build-system]): --all-packages leaves it out.
# It never passed before either: plain `uv build` made an sdist that does not
# install, its workspace members missing from it (measured for #889).
vroot="$tmp/fixture-virtual-root"
pkg "$vroot" plinth-fixture-root '"plinth-fixture-core"' \
  '[tool.uv.sources]' 'plinth-fixture-core = { workspace = true }' '[tool.uv.workspace]' 'members = ["packages/*"]'
rm -r "$vroot/src"
pkg "$vroot/packages/core" plinth-fixture-core "" "$backend"
echo 'X = 1' > "$vroot/packages/core/src/plinth_fixture_core/__init__.py"

for f in "$single" "$ws" "$vroot"; do
  (cd "$f" && "$real_uv" lock -q) || { bad "uv lock failed in ${f##*/}"; exit 1; }
done

# --- runners --------------------------------------------------------------
# Each run is on a fresh copy; sets $out, $rc and $log (uv's calls).
copy() { rm -rf "$tmp/run"; cp -R "$1" "$tmp/run"; : > "$tmp/uv.log"; }
gh_run() { # <fixture>: `uv sync --locked`, then the build and smoke steps
  copy "$1"; rc=0
  mkdir -p "$tmp/runner"; rm -rf "$tmp/runner"/*
  out="$(cd "$tmp/run" && "$real_uv" sync --locked -q 2>&1 \
    && export PATH="$tmp/bin:$PATH" UV_LOG="$tmp/uv.log" RUNNER_TEMP="$tmp/runner" \
    && bash -e "$tmp/gh-build.sh" 2>&1 && bash -e "$tmp/gh-smoke.sh" 2>&1)" || rc=$?
  log="$(cat "$tmp/uv.log")"
}
gl_run() { # <fixture>: the build job, the uv download stubbed
  copy "$1"; rc=0
  out="$( { cat "$tmp/gl-helpers.sh"; echo 'plinth_uv() { :; }'; cat "$tmp/gl-build.sh"; } \
    | PATH="$tmp/bin:$PATH" UV_LOG="$tmp/uv.log" PLINTH_WORKDIR="$tmp/run" bash -eo pipefail 2>&1)" || rc=$?
  log="$(cat "$tmp/uv.log")"
}
expect() { # <label> <rc> <pattern in out>...
  local label="$1" want="$2"; shift 2
  local p miss=""
  for p in "$@"; do printf '%s' "$out" | grep -qF -- "$p" || miss="$miss missing: $p;"; done
  if [ "$rc" = "$want" ] && [ -z "$miss" ]; then ok "$label"; else bad "$label (exit $rc, wanted $want;$miss)" "$out"; fi
}
refuse() { # <label> <pattern that must not be in out>...
  local p hit=""
  for p in "${@:2}"; do printf '%s' "$out" | grep -qF -- "$p" && hit="$hit found: $p;"; done
  if [ -z "$hit" ]; then ok "$1"; else bad "$1 ($hit)" "$out"; fi
}
in_dist() { # <label> <expected `ls dist` of the last run>
  local got; got="$(ls "$tmp/run/dist" 2>&1 | tr '\n' ' ')"
  if [ "$got" = "$2" ]; then ok "$1"; else bad "$1" "got: $got"$'\n'"wanted: $2"; fi
}

# uv's calls before this change, for the project without a workspace:
# `uv build`, the name read, then a venv and an install per file in dist/.
read_name="run python -c import tomllib,pathlib;print(tomllib.loads(pathlib.Path(\"pyproject.toml\").read_text())[\"project\"][\"name\"])"
before_single="build
$read_name
venv --quiet .smoke
pip install --quiet --python .smoke/bin/python dist/plinth_fixture_plain-0.1.0-py3-none-any.whl
venv --quiet .smoke
pip install --quiet --python .smoke/bin/python dist/plinth_fixture_plain-0.1.0.tar.gz"
# The one call this change adds: the read of the build plan, `uv run python -`.
same_calls() { # <label>
  local got; got="$(printf '%s\n' "$log" | grep -vxF 'run python -' | grep -vxF 'sync --locked')"
  if [ "$got" = "$before_single" ] && [ "$(printf '%s\n' "$log" | grep -cxF 'run python -')" = 1 ]; then ok "$1"
  else bad "$1" "got:"$'\n'"$log"$'\n'"wanted, besides one 'run python -':"$'\n'"$before_single"; fi
}

for side in gh gl; do
  echo "-- $side: a project without a workspace"
  "${side}_run" "$single"
  expect "$side: passes, the wheel and the sdist installed and imported" 0 "import plinth_fixture_plain ok" \
    "OK dist/plinth_fixture_plain-0.1.0-py3-none-any.whl" "OK dist/plinth_fixture_plain-0.1.0.tar.gz"
  same_calls "$side: runs the commands it ran before, plus the read of the build plan"

  echo "-- $side: a uv workspace whose root depends on a member"
  "${side}_run" "$ws"
  expect "$side: passes, the member installed from dist/ beside the root" 0 \
    "import plinth_fixture_app ok" "import plinth_fixture_core ok" "import six ok" \
    "OK dist/plinth_fixture_app-0.1.0-py3-none-any.whl" "OK dist/plinth_fixture_app-0.1.0.tar.gz"
  expect "$side: a packaged member the root does not depend on is named, not imported" 0 \
    "plinth_fixture_extra not imported: plinth-fixture-app does not depend on plinth-fixture-extra"
  refuse "$side: neither the unpackaged members nor the excluded one is imported" \
    "was imported" "import plinth_fixture_virtual" "import plinth_fixture_unpackaged" "import plinth_fixture_skipped" "import plinth_fixture_extra"
  in_dist "$side: --all-packages builds the root and the packaged members only" \
    "plinth_fixture_app-0.1.0-py3-none-any.whl plinth_fixture_app-0.1.0.tar.gz plinth_fixture_core-0.1.0-py3-none-any.whl plinth_fixture_core-0.1.0.tar.gz plinth_fixture_extra-0.1.0-py3-none-any.whl plinth_fixture_extra-0.1.0.tar.gz six-0.1.0-py3-none-any.whl six-0.1.0.tar.gz "
  if [ "$("$tmp/run/.smoke/bin/python" -c 'import importlib.metadata as md; print(md.version("six"))' 2>&1)" = 0.1.0 ]; then
    ok "$side: the member named like a PyPI package is the one built in dist/"
  else bad "$side: six came from the index, not dist/" "$("$tmp/run/.smoke/bin/python" -m pip --version 2>&1; ls "$tmp/run/.smoke/lib"/*/site-packages)"; fi
  if printf '%s\n' "$log" | grep -qxF 'build --all-packages' \
    && [ "$(printf '%s\n' "$log" | grep -cE -- '--find-links dist --constraint [^ ]+ dist/plinth_fixture_app-')" = 2 ] \
    && ! printf '%s\n' "$log" | grep -qE 'pip install.*plinth_fixture_(core|extra)'; then
    ok "$side: builds with --all-packages and installs the root's two files only, each with --find-links dist"
  else bad "$side: the workspace's uv calls" "$log"; fi

  echo "-- $side: a uv workspace whose root is not a package"
  "${side}_run" "$vroot"
  expect "$side: fails, saying the root is not a package uv builds" 1 \
    "no wheel or sdist of plinth-fixture-root in dist/: uv builds a workspace's root only when it is a package"
done

echo "-- the commands before this change, on the workspace"
copy "$ws"; rc=0
out="$(cd "$tmp/run" && "$real_uv" sync --locked -q && "$real_uv" build -q && "$real_uv" venv -q .smoke \
  && "$real_uv" pip install --quiet --python .smoke/bin/python dist/plinth_fixture_app-0.1.0-py3-none-any.whl 2>&1)" || rc=$?
expect "uv build then a plain install fails: the member is not on the index" 1 "not found in the package registry"

echo
echo "build cases: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
