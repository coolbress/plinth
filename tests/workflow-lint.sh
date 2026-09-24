#!/usr/bin/env bash
# The two workflow checks of `ci / tools`, with its flags: the workflow calls
# this file, and its install step reads the actionlint pin below, so that pin
# is here only; zizmor's is in tests/lint-tools.in. actionlint's binary is per platform: CI installs the
# checksum-verified Linux build, a laptop runs what it has. Another version
# still runs here and says so; in CI (GITHUB_ACTIONS) it is a FAIL.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Bump the version and the checksum together (the release's checksums.txt,
# actionlint_<version>_linux_amd64.tar.gz).
actionlint_version="1.7.12"
# shellcheck disable=SC2034  # read by the install step of plinth-ci.yml
actionlint_sha256="8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"
# zizmor is pinned in tests/lint-tools.in and installed hash-checked from
# tests/lint-tools.txt (tests/lib/lint-tools.sh). 1.30.0 adds a low finding that
# asks for the `$/` self-repository syntax, which actionlint 1.7.12 does not know
# yet; raise both together.
# shellcheck source=tests/lib/lint-tools.sh
. "$root/tests/lib/lint-tools.sh"
zizmor_version="$(lint_tool_version zizmor)"
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
# (allowlist discipline): a hash-checked install, the same one here and in CI.
if ! bin="$(lint_tools_bin)"; then
  echo "${bin/FAIL  /FAIL  zizmor: }"; fail=1
elif "$bin/zizmor" --no-progress .github/workflows/; then
  echo "  PASS  zizmor $zizmor_version${PLINTH_LINT_TOOLS_BIN:+ (from PLINTH_LINT_TOOLS_BIN, not hash-checked)}"
else
  echo "  FAIL  zizmor $zizmor_version"; fail=1
fi
exit "$fail"
