#!/usr/bin/env bash
# Every tests/*.sh is a `run:` step in a workflow. A test file that is committed
# but never wired runs zero times while CI stays green.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

missing=""
for f in "$root"/tests/*.sh; do
  name="$(basename "$f")"
  grep -q -E "^[[:space:]]*run: \./tests/$name\b" "$root"/.github/workflows/*.yml || missing="$missing  $name"$'\n'
done
if [ -n "$missing" ]; then
  echo "  FAIL  tests not wired into .github/workflows/*.yml (they never run):"
  printf '%s' "$missing"; exit 1
fi
n="$(find "$root/tests" -maxdepth 1 -name '*.sh' | wc -l | tr -d ' ')"
echo "  PASS  all $n tests are wired"
