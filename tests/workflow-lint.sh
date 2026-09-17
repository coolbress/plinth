#!/usr/bin/env bash
# The two workflow checks of `ci / tools`, with its flags: the workflow calls
# this file, and its install step reads the actionlint pin below, so the pins
# here are the only ones. actionlint's binary is per platform: CI installs the
# checksum-verified Linux build, a laptop runs what it has. Another version
# still runs here and says so; in CI (GITHUB_ACTIONS) it is a FAIL.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Bump the version and the checksum together (the release's checksums.txt,
# actionlint_<version>_linux_amd64.tar.gz).
actionlint_version="1.7.12"
# shellcheck disable=SC2034  # read by the install step of plinth-ci.yml
actionlint_sha256="8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"
# 1.30.0 adds a low finding that asks for the `$/` self-repository syntax, which
# actionlint 1.7.12 does not know yet; raise both together.
zizmor_version="1.29.0"
cd "$root" || exit 1
fail=0

# actionlint also runs shellcheck over every `run:` block. `job.workflow_sha`
# is real (python-ci.yml fetches the checker with it, measured) but not in
# actionlint's schema yet; that one message is ignored.
if ! command -v actionlint >/dev/null; then
  echo "  FAIL  actionlint not found: brew install actionlint (https://github.com/rhysd/actionlint)"; fail=1
else
  v="$(actionlint -version | head -1)"
  if [ "$v" != "$actionlint_version" ] && [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "  FAIL  actionlint $v is not the pinned $actionlint_version"; fail=1
  elif ! actionlint -color -ignore 'property "workflow_sha" is not defined'; then
    echo "  FAIL  actionlint $v"; fail=1
  elif [ "$v" != "$actionlint_version" ]; then
    echo "  PASS  actionlint $v (CI pins $actionlint_version: this is not the pinned pass)"
  else
    echo "  PASS  actionlint $v"
  fi
fi

# Security audit of the workflows, every severity: these files run in
# consumers' repositories, the widest blast radius here. Not an action
# (allowlist discipline); pipx is on the runner, uvx where plinth is installed.
# Same package, same version either way.
if command -v pipx >/dev/null; then run="pipx run"
elif command -v uvx >/dev/null; then run="uvx"
else run=""; fi
if [ -z "$run" ]; then
  echo "  FAIL  zizmor: neither pipx nor uvx found: install uv (https://docs.astral.sh/uv/)"; fail=1
elif $run "zizmor==$zizmor_version" --no-progress .github/workflows/; then
  echo "  PASS  zizmor $zizmor_version ($run)"
else
  echo "  FAIL  zizmor $zizmor_version ($run)"; fail=1
fi
exit "$fail"
