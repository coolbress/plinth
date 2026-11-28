#!/usr/bin/env bash
# The two workflow checks of `ci / tools`, with its flags: the workflow calls
# this file, and its install step reads the actionlint pin below, so that pin
# is here only; zizmor's is in tools/lint/pyproject.toml. actionlint's binary is per platform: CI installs the
# checksum-verified Linux build, a laptop runs what it has. Another version
# still runs here and says so; in CI (GITHUB_ACTIONS) it is a FAIL.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Bump the version and the checksum together (the release's checksums.txt,
# actionlint_<version>_linux_amd64.tar.gz).
actionlint_version="1.7.12"
# shellcheck disable=SC2034  # read by the install step of plinth-ci.yml
actionlint_sha256="8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"
# zizmor is pinned in tools/lint/pyproject.toml and installed hash-checked from
# its uv.lock (tests/lib/lint-tools.sh). From 1.30.0 a low finding asks for the
# `$/` self-repository syntax, which actionlint 1.7.12 does not know yet: that
# audit is off in .github/zizmor.yml until both move to it (#1220).
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

# FC-D09's shape, measured again with every zizmor (#1114): an AI agent action
# on a trigger whose text others write, with contents: write and a secret, and
# no author check. zizmor 1.33.1 at --min-severity medium reports nothing for
# these four triggers (measured 2026-11-28; 1.29.0 on 2026-11-25). For
# issue_comment, pull_request_target and workflow_run it reports
# dangerous-triggers, gated or not: the trigger, not this shape. When zizmor
# reports one of the four, FC-D09 may retire for it: this case fails to say so.
if [ -n "${bin:-}" ] && [ -x "$bin/zizmor" ]; then
  shape="$(mktemp -d)" || { echo "  FAIL  could not make a temp folder"; exit 1; }
  reported=""
  for t in issues pull_request_review_comment discussion discussion_comment; do
    # shellcheck disable=SC2016  # ${{ }} is the workflow's expression, written as text
    printf 'name: agent\non:\n  %s:\npermissions:\n  contents: write\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: anthropics/claude-code-action@%s # v1\n        with:\n          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}\n' \
      "$t" "$(printf '%040d' 0)" > "$shape/$t.yml"
    "$bin/zizmor" --no-progress --offline --min-severity medium --format plain "$shape/$t.yml" >/dev/null 2>&1 || reported="$reported $t"
  done
  rm -rf "$shape"
  if [ -z "$reported" ]; then echo "  PASS  zizmor $zizmor_version reports nothing on FC-D09's shape (issues, pull_request_review_comment, discussion, discussion_comment): FC-D09 stays"
  else echo "  FAIL  zizmor $zizmor_version now reports FC-D09's shape on:$reported. Record it in skills/floor-check/reference.md#experimental-reads and decide whether FC-D09 retires for those triggers (#1114)"; fail=1; fi
fi
exit "$fail"
