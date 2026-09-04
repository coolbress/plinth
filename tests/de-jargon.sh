#!/usr/bin/env bash
# Public text must not carry internal vocabulary. The list is tests/de-jargon.txt,
# one extended regex per line. Korean translations (*.ko.md) are exempt.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 1
list="tests/de-jargon.txt"

scan() {  # scan <file>... ; prints hits, returns 1 if any
  local hit=0 p out
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if out="$(grep -n -I -E -- "$p" "$@" 2>/dev/null)"; then
      printf '  FAIL  %s\n' "$p"; printf '        %s\n' "$out"; hit=1
    fi
  done < <(grep -v -E '^[[:space:]]*(#|$)' "$list")
  return $hit
}

# Self-check first: a gate that cannot catch a planted word is not a gate.
planted="$(mktemp)"; echo "see direction/04 and goppi" >"$planted"
if scan "$planted" >/dev/null; then echo "  FAIL  the gate did not catch a planted word"; rm -f "$planted"; exit 1; fi
rm -f "$planted"
echo "  PASS  the gate catches a planted word"

files=()
while IFS= read -r f; do files+=("$f"); done \
  < <(git ls-files --cached --others --exclude-standard | grep -v -E '\.ko\.md$' | grep -v -E '^tests/de-jargon\.(txt|sh)$')
if scan "${files[@]}"; then
  echo "  PASS  no internal vocabulary in ${#files[@]} files"
else
  echo "-- fix the text or, if the word is legitimately public, edit $list"; exit 1
fi
