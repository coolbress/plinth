#!/usr/bin/env bash
# Public text must not carry internal vocabulary. The list is tests/de-jargon.txt,
# one extended regex per line. Korean translations (*.ko.md) are exempt.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 1
list="tests/de-jargon.txt"

unreleased="$(mktemp)"; trap 'rm -f "$unreleased"' EXIT
scan() {  # scan <file>... ; prints hits, returns 1 if any
  # A pattern marked "@history " skips the released sections of a file named
  # CHANGELOG.md: it reads that file only up to its second "## [" heading.
  local hit=0 p out f files
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    files=("$@")
    if [ "${p#@history }" != "$p" ]; then
      p="${p#@history }"; files=()
      for f in "$@"; do
        if [ "$(basename "$f")" = CHANGELOG.md ]; then
          awk '/^## \[/{n++} n<2' "$f" >"$unreleased"
          out="$(grep -n -I -E -- "$p" "$unreleased" 2>/dev/null)" \
            && { printf '  FAIL  %s\n' "$p"; printf '        %s\n' "$out" | sed "s|^        |        $f:|"; hit=1; }
        else
          files+=("$f")
        fi
      done
      [ "${#files[@]}" -eq 0 ] && continue
    fi
    if out="$(grep -n -I -E -- "$p" "${files[@]}" 2>/dev/null)"; then
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
# The history exemption covers released CHANGELOG.md sections only (#752).
dir="$(mktemp -d)"
printf 'the evidence is in plinth-lab\n' >"$dir/page.md"
printf '# Changelog\n\n## [Unreleased]\n\n## [1.0.0]\n\n- moved to plinth-lab\n' >"$dir/CHANGELOG.md"
if scan "$dir/page.md" >/dev/null; then echo "  FAIL  the gate did not catch plinth-lab in a page"; exit 1; fi
if ! scan "$dir/CHANGELOG.md" >/dev/null; then echo "  FAIL  the gate caught plinth-lab in a released CHANGELOG section"; exit 1; fi
printf '# Changelog\n\n## [Unreleased]\n\n- the lab holds it\n\n## [1.0.0]\n' >"$dir/CHANGELOG.md"
if scan "$dir/CHANGELOG.md" >/dev/null; then echo "  FAIL  the gate did not catch the lab term in [Unreleased]"; exit 1; fi
printf 'a GitLab project, gitlab-ci and labels\n' >"$dir/page.md"
if ! scan "$dir/page.md" >/dev/null; then echo "  FAIL  the gate caught GitLab or labels as the lab term"; exit 1; fi
rm -rf "$dir"
echo "  PASS  plinth-lab and the lab term fail in a page and in [Unreleased], not in a released CHANGELOG section"

files=()
while IFS= read -r f; do files+=("$f"); done \
  < <(git ls-files --cached --others --exclude-standard | grep -v -E '\.ko\.md$' | grep -v -E '^tests/de-jargon\.(txt|sh)$')
if scan "${files[@]}"; then
  echo "  PASS  no internal vocabulary in ${#files[@]} files"
else
  echo "-- fix the text or, if the word is legitimately public, edit $list"; exit 1
fi
