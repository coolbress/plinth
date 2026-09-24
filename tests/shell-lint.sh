#!/usr/bin/env bash
# The two shell checks of `ci / tools`, with its flags: the workflow calls this
# file. Neither tool is pinned, in CI or here, so the versions that ran are
# printed: a pass on another bash or shellcheck is not the CI pass. macOS ships
# bash 3.2 and the runner 5.x, so `bash -n` here can refuse syntax CI accepts.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 1
fail=0

# One file per call: `bash -n a.sh b.sh` parses a.sh only, b.sh is $1.
v="$(bash -c 'echo "$BASH_VERSION"')"; bad=0
for f in scripts/*.sh scripts/lib/*.sh scripts/pr-review/*.sh tests/*.sh; do bash -n "$f" || bad=1; done
if [ "$bad" = 0 ]; then echo "  PASS  bash -n (bash $v)"; else echo "  FAIL  bash -n (bash $v)"; fail=1; fi

if ! command -v shellcheck >/dev/null; then
  echo "  FAIL  shellcheck not found: brew install shellcheck (apt-get install shellcheck)"; fail=1
else
  v="$(shellcheck --version | sed -n 's/^version: //p')"
  if shellcheck -x -S warning scripts/*.sh scripts/lib/*.sh scripts/pr-review/*.sh tests/*.sh; then echo "  PASS  shellcheck $v"
  else echo "  FAIL  shellcheck $v"; fail=1; fi
fi
exit "$fail"
