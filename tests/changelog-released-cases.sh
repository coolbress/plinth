#!/usr/bin/env bash
# What scripts/changelog-released.py, a step of `ci / docs`, says about a pull
# request's CHANGELOG.md (#881): a section whose version has a `vX.Y.Z` tag may
# not change, unless the change puts it back as the tag has it or the
# description names the version on a `Corrects released section:` line.
#
# Each case is a throwaway git repository. #877's case is built the way it
# happened: a line added under [Unreleased] on a branch, a release on main that
# turns [Unreleased] into the tagged version, then main merged into the branch.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/changelog-released.py"

work="$(mktemp -d "${TMPDIR:-/tmp}/changelog-released.XXXXXX")"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        | /'; }

g() { git -C "$repo" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c tag.gpgsign=false "$@" >/dev/null 2>&1; }

# changelog <unreleased lines> <sections after it> <link lines>
changelog() {
  printf '# Changelog\n\nAll notable changes.\n\n## [Unreleased]\n%s\n%s\n%s\n' "$1" "$2" "$3" >"$repo/CHANGELOG.md"
}
s100='## [1.0.0] - 2026-01-01

### Added

- the first thing.
'
l100='[Unreleased]: https://example.invalid/compare/v1.0.0...HEAD
[1.0.0]: https://example.invalid/releases/tag/v1.0.0'
s110='## [1.1.0] - 2026-02-01

### Added

- a main line.
- another main line.
'
l110='[Unreleased]: https://example.invalid/compare/v1.1.0...HEAD
[1.1.0]: https://example.invalid/releases/tag/v1.1.0
[1.0.0]: https://example.invalid/releases/tag/v1.0.0'

# A repository at 1.0.0 (tagged), [Unreleased] holding two lines on main,
# a branch `feature` that adds a third under them, then the 1.1.0 release on
# main (tagged).
n=0
fresh() {
  n=$((n + 1)); repo="$work/$n"; mkdir -p "$repo"; g init -q -b main
  changelog '' "$s100" "$l100"; g add -A; g commit -qm 1.0.0; g tag v1.0.0
  changelog '
### Added

- a main line.
- another main line.
' "$s100" "$l100"; g commit -qam unreleased
  g checkout -qb feature
  changelog '
### Added

- a main line.
- another main line.
- the feature line.
' "$s100" "$l100"; g commit -qam feature
  g checkout -q main
  changelog '' "$s110
$s100" "$l110"; g commit -qam 'chore(release): v1.1.0'; g tag v1.1.0
}

# run <label> <want exit> <want text> [BASE] [HEAD] [body] [event]
run() {
  local label="$1" want="$2" text="$3" out rc=0
  out="$(cd "$repo" && EVENT="${7-pull_request}" BASE="${4:-main}" HEAD_REV="${5:-HEAD}" PR_BODY="${6:-}" python3 "$script" 2>&1)" || rc=$?
  if [ "$rc" != "$want" ]; then bad "$label: exit $rc, want $want" "$out"; return; fi
  if ! grep -qF -- "$text" <<<"$out"; then bad "$label: output lacks '$text'" "$out"; return; fi
  ok "$label"
}

# 1. #877's shape: the branch's line was under [Unreleased]; after main is
# merged in, git keeps it where it sat, now inside the released [1.1.0].
fresh
g checkout -q feature
if ! g merge -q --no-edit main; then bad "#877 fixture: the merge of main into the branch conflicted"; fi
if ! sed -n '/^## \[1.1.0\]/,/^## \[1.0.0\]/p' "$repo/CHANGELOG.md" | grep -q 'the feature line'; then
  bad "#877 fixture: the merged line did not land inside [1.1.0]" "$(cat "$repo/CHANGELOG.md")"
fi
run "#877's shape: a line merged into the tagged [1.1.0] fails, naming the section" 1 '::error::CHANGELOG.md [1.1.0]'
run "#877's shape: the failure says to move the line under [Unreleased]" 1 'under [Unreleased]'

# 2. The same line under [Unreleased], on a branch from the released main.
fresh
g checkout -qb feature2 main
changelog '
### Added

- the feature line.
' "$s110
$s100" "$l110"; g commit -qam feature2
run "the same line under [Unreleased] passes" 0 'PASS'

# 3. Release run 1: [Unreleased] becomes [1.2.0], untagged, and the link
# lines at the foot change.
fresh
g checkout -qb release/v1.2.0 main
changelog '' "## [1.2.0] - 2026-03-01

### Added

- a newer line.

$s110
$s100" "[Unreleased]: https://example.invalid/compare/v1.2.0...HEAD
[1.2.0]: https://example.invalid/releases/tag/v1.2.0
[1.1.0]: https://example.invalid/releases/tag/v1.1.0
[1.0.0]: https://example.invalid/releases/tag/v1.0.0"
g commit -qam 'chore(release): v1.2.0'
run "release run 1 (a new, untagged section) passes" 0 'PASS'

# 4. A deliberate correction of a released section.
fresh
g checkout -qb fix-typo main
changelog '' "$s110
${s100/the first thing/the first thing, corrected}" "$l110"; g commit -qam typo
run "a correction to tagged [1.0.0] without the line fails" 1 '::error::CHANGELOG.md [1.0.0]'
run "a correction named on a 'Corrects released section: 1.0.0' line passes" 0 'PASS' main HEAD $'Fixes a typo.\n\nCorrects released section: 1.0.0\n'
run "the line names versions, and only those pass: naming 1.1.0 fails 1.0.0" 1 '::error::CHANGELOG.md [1.0.0]' main HEAD 'Corrects released section: 1.1.0'
run "the line inside an HTML comment does not count" 1 '::error::CHANGELOG.md [1.0.0]' main HEAD '<!-- Corrects released section: 1.0.0 -->'
run "two versions on one line both pass" 0 'PASS' main HEAD 'Corrects released section: 1.1.0, 1.0.0'

run "the line inside a code fence (a quoted example) does not count" 1 '::error::CHANGELOG.md [1.0.0]' main HEAD $'```text\nCorrects released section: 1.0.0\n```'

# A heading or link line that is not a version's, inside a released section,
# does not hide the lines below it.
fresh
g checkout -qb inner main
changelog '' "$s110
${s100/- the first thing./- the first thing.

## A note

[x]: https://example.invalid/x

- a line added below them.}" "$l110"; g commit -qam inner
run "a line added below an inner heading and link line in tagged [1.0.0] fails" 1 '::error::CHANGELOG.md [1.0.0]'

# 5. #880's shape: main carries the slip, and the fix puts the section back
# as the tag has it.
fresh
g checkout -q feature; g merge -q --no-edit main; g checkout -q main; g merge -q --ff-only feature
g checkout -qb move-back main
changelog '
### Added

- the feature line.
' "$s110
$s100" "$l110"; g commit -qam move-back
run "putting a section back as its tag has it passes" 0 'as v1.1.0 has it'

# #840's shape: a line landed inside the already-tagged [1.0.0], the next
# release (1.2.0) was tagged with it there, and the fix moves it to [1.2.0].
fresh
g checkout -qb slip main
changelog '' "$s110
${s100/- the first thing./- the first thing.
- the late line.}" "$l110"; g commit -qam slip
run "#840's shape: the line landing inside tagged [1.0.0] fails, naming it" 1 '::error::CHANGELOG.md [1.0.0]' main slip
g checkout -q main; g merge -q --ff-only slip
s120='## [1.2.0] - 2026-03-01

### Added

- a 1.2.0 line.
'
changelog '' "$s120
$s110
${s100/- the first thing./- the first thing.
- the late line.}" "$l110"; g commit -qam 'chore(release): v1.2.0'; g tag v1.2.0
g checkout -qb move-to-120 main
changelog '' "${s120/- a 1.2.0 line./- a 1.2.0 line.
- the late line.}
$s110
$s100" "$l110"; g commit -qam move
run "#840's fix: moving the line to [1.2.0] without the line fails, naming [1.2.0]" 1 '::error::CHANGELOG.md [1.2.0]'
run "  while [1.0.0], back as v1.0.0 has it, passes" 1 'PASS  [1.0.0] changed, back as v1.0.0 has it'
run "  and with 'Corrects released section: 1.2.0' it passes" 0 'named on the description' main HEAD 'Corrects released section: 1.2.0'

# 6. Removing a tagged section is a change too.
fresh
g checkout -qb drop main
changelog '' "$s110" "$l110"; g commit -qam drop
run "removing tagged [1.0.0] fails" 1 '::error::CHANGELOG.md [1.0.0]'

# 7. Not a pull request: nothing to compare against, a pass that says so.
run "not a pull request passes and says so" 0 'not a pull request' main HEAD '' push

# 8. Fail closed: no tags read, or a base that does not resolve.
fresh
g tag -d v1.0.0; g tag -d v1.1.0
run "no vX.Y.Z tag read fails rather than finding every section free" 1 '::error::'
fresh
run "a base that does not resolve fails" 1 '::error::' no-such-rev

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
