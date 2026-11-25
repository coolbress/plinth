#!/usr/bin/env bash
# scripts/changelog-fragments.py check (#1136), the step of `ci / docs` that
# fails a pull request writing its line under [Unreleased] instead of in a
# fragment, or adding a fragment run 1 of make-release.sh would refuse. Each
# case is a throwaway directory; the last one is this checkout.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
fails=0
n=0
case_() { # <expected ok|no> <name> <CHANGELOG [Unreleased] body> [<fragment file> <content>]...
  local want="$1" name="$2" unrel="$3" dir rc=0; shift 3
  n=$((n+1)); dir="$work/$n"; mkdir -p "$dir/changelog.d"
  printf '# Changelog\n\n## [Unreleased]\n%b\n## [1.0.0] - 2026-01-01\n\n- Old.\n\n[Unreleased]: https://example.com/compare/v1.0.0...HEAD\n' "$unrel" >"$dir/CHANGELOG.md"
  while [ $# -ge 2 ]; do printf '%b' "$2" >"$dir/changelog.d/$1"; shift 2; done
  "$root/scripts/changelog-fragments.py" check "$dir" >"$work/out" 2>&1 || rc=$?
  if { [ "$want" = ok ] && [ "$rc" = 0 ]; } || { [ "$want" = no ] && [ "$rc" = 1 ]; }; then
    echo "  PASS  $name"
  else
    echo "  FAIL  $name (exit $rc, expected $want)"; sed 's/^/        /' "$work/out"; fails=$((fails+1))
  fi
}
case_ ok "fragments in two sections, nothing under [Unreleased]" '\n' \
  a.md '### Added\n\n- One.\n' b.md '### Fixed\n\n- Two.\n\n### Changed\n\n- Three.\n'
case_ ok "no fragment at all" '\n'
case_ ok "a dot file beside the fragments" '\n' .markdownlint.jsonc '{}\n' a.md '### Added\n\n- One.\n'
case_ ok "a heading inside a fenced block is the entry's" '\n' a.md '### Added\n\n- One:\n\n  ```md\n  ## not a heading\n  ```\n'
case_ no "a line under [Unreleased]" '\n### Added\n\n- Written the old way.\n'
case_ no "a line under [Unreleased] beside a fragment" '\n- Loose.\n' a.md '### Added\n\n- One.\n'
case_ no "an empty fragment" '\n' a.md '\n  \n'
case_ no "a section that is not Keep a Changelog's" '\n' a.md '### Notes\n\n- One.\n'
case_ no "a section name in lower case" '\n' a.md '### added\n\n- One.\n'
case_ no "text before the first heading" '\n' a.md '- One.\n\n### Added\n\n- Two.\n'
case_ no "a section with nothing under it" '\n' a.md '### Added\n\n### Fixed\n\n- Two.\n'
case_ no "a version heading in a fragment" '\n' a.md '### Added\n\n- One.\n\n## [2.0.0]\n'
case_ no "a #### heading in a fragment" '\n' a.md '### Added\n\n#### More\n\n- One.\n'
case_ no "a file that is not .md" '\n' a.txt '### Added\n\n- One.\n'
# This checkout: what `ci / docs` runs on main and on every pull request.
if "$root/scripts/changelog-fragments.py" check "$root" >"$work/out" 2>&1; then
  echo "  PASS  this checkout's fragments read and nothing is under [Unreleased]"
else
  echo "  FAIL  this checkout:"; sed 's/^/        /' "$work/out"; fails=$((fails+1))
fi
[ "$fails" = 0 ] || { echo "-- $fails failed"; exit 1; }
echo "-- every case as expected"
