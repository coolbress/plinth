#!/usr/bin/env bash
# The README install block and the tutorial install block are the same bytes,
# and the block is the two lines the README promises. CI runs those bytes.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

block() { awk '/<!-- install-block:start -->/{p=1;next} /<!-- install-block:end -->/{p=0} p' "$1"; }

readme="$(block "$root/README.md")"
tutorial="$(block "$root/docs/tutorials/getting-started.md")"
[ -n "$readme" ] || { echo "  FAIL  README.md has no install block"; exit 1; }
[ -n "$tutorial" ] || { echo "  FAIL  docs/tutorials/getting-started.md has no install block"; exit 1; }

if ! diff <(printf '%s\n' "$readme") <(printf '%s\n' "$tutorial"); then
  echo "  FAIL  README and tutorial install blocks differ"; exit 1
fi
n="$(grep -c '^claude ' <<<"$readme")"
[ "$n" = 2 ] || { echo "  FAIL  the install block has $n command lines, the README promises two"; exit 1; }
echo "  PASS  README and tutorial install blocks are identical (2 commands)"
