#!/usr/bin/env bash
# The README install block and the tutorial install block are the same bytes,
# and the block is the three lines the README promises. CI runs those bytes.
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
[ "$n" = 3 ] || { echo "  FAIL  the install block has $n command lines, the README promises three"; exit 1; }
# The official marketplace first: one dependency lives there, and a fresh
# configuration does not have it until an interactive first run (#282).
[ "$(head -1 <<<"$(grep '^claude ' <<<"$readme")")" = "claude plugin marketplace add anthropics/claude-plugins-official" ] \
  || { echo "  FAIL  the install block does not add the official marketplace first"; exit 1; }
echo "  PASS  README and tutorial install blocks are identical (3 commands, the official marketplace first)"
