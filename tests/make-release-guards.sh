#!/usr/bin/env bash
# The guards of `scripts/make-release.sh`. No network: the script runs in a
# throwaway clone of this repository's release files with a bare `origin`,
# and `gh` is mocked; the verdict is what changed and what `gh` was asked.
#
# One property: no release goes out without its *why* and the template tag it
# was tested with. Everything else (tag format, both manifests moving together,
# main only, no duplicate) is a wall around that property.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

cat > "$work/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -u
printf 'gh %s\n' "$*" >> "$GH_LOG"
case "$*" in
  "release view"*)   exit "${VIEW_RC:-1}" ;;   # default: no release yet
  "release create"*) exit 0 ;;
esac
exit 0
MOCK
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"

# A repository with exactly the files the release touches or reads, and a bare
# origin so that pushes and fetches are real.
repo="$work/repo"; origin="$work/origin.git"
mkdir -p "$repo/.claude-plugin" "$repo/scripts"
cp "$root"/.claude-plugin/plugin.json "$root"/.claude-plugin/marketplace.json "$repo/.claude-plugin/"
cp "$root"/CHANGELOG.md "$repo/"
cp "$root"/scripts/make-release.sh "$root"/scripts/new-project.sh "$repo/scripts/"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -C "$repo" "$@"; }
g init -q -b main; g add -A; g commit -q -m "fixture"
git clone -q --bare "$repo" "$origin"
g remote add origin "$origin"; g fetch -q origin; g branch -q -u origin/main

current="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$repo/.claude-plugin/plugin.json")"
next="${current%%.*}.$(( $(cut -d. -f2 <<<"$current") + 1 )).0"
template="$(sed -nE 's/^template_repo="[^"]*\/([^"]+)"$/\1/p' "$repo/scripts/new-project.sh") $(sed -nE 's/^template_ref="([^"]+)"$/\1/p' "$repo/scripts/new-project.sh")"

pass=0; fail=0
check() { # <name> <expected ok|no> <actual exit code>
  if { [ "$2" = ok ] && [ "$3" = 0 ]; } || { [ "$2" = no ] && [ "$3" != 0 ]; }
  then pass=$((pass+1)); echo "  PASS  $1"
  else fail=$((fail+1)); echo "  FAIL  $1 (exit $3, expected $2)"; fi
}
is() { # <name> <condition...>
  local name="$1"; shift
  if "$@"; then pass=$((pass+1)); echo "  PASS  $name"
  else fail=$((fail+1)); echo "  FAIL  $name"; fi
}
gh_log_has() { grep -q -- "$1" "$GH_LOG" 2>/dev/null; }
version_in() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("version"))' "$repo/.claude-plugin/$1"; }
untouched() { [ -z "$(g status --porcelain)" ] && [ "$(g rev-parse --abbrev-ref HEAD)" = main ]; }

run() { export GH_LOG="$work/log.$RANDOM"; : > "$GH_LOG"; (cd "$repo" && "$repo/scripts/make-release.sh" "$@") >"$work/out" 2>&1; }

printf '## Why\n\nA reason a person wrote.\n\ntested with %s\n' "$template" > "$work/why.md"
printf 'tested with %s\n' "$template" > "$work/only-tested.md"
printf '## Why\n\nA reason.\n' > "$work/no-tested.md"
printf '## Why\n\nA reason.\n\ntested with %s v0.0.0-not-the-pin\n' "${template%% *}" > "$work/wrong-tested.md"
: > "$work/empty.md"

echo "-- tag format"
run "$next" "$work/why.md";        check "a tag without the v prefix is refused"       no $?
run "v${next%.*}" "$work/why.md";  check "a tag that is not vX.Y.Z is refused"         no $?
is "nothing changed" untouched

echo "-- notes guard"
run "v$next" "$work/missing.md";      check "a missing notes file is refused"                       no $?
run "v$next" "$work/empty.md";        check "an empty notes file is refused"                        no $?
run "v$next" "$work/no-tested.md";    check "notes without the tested-template line are refused"    no $?
run "v$next" "$work/wrong-tested.md"; check "a tested-template line naming another tag is refused"  no $?
run "v$next" "$work/only-tested.md";  check "the tested-template line alone is not a why"           no $?
is "nothing changed" untouched
is "gh release create was never called" bash -c '! grep -q "release create" "$work"/log.* 2>/dev/null'

echo "-- where it runs"
echo x > "$repo/dirty"
run "v$next" "$work/why.md";       check "a dirty tree is refused"                    no $?
rm "$repo/dirty"
g switch -q -c other
run "v$next" "$work/why.md";       check "a branch other than main is refused"        no $?
g switch -q main; g branch -q -D other
g commit -q --allow-empty -m "ahead"; g push -q origin main; g reset -q --hard HEAD~1
run "v$next" "$work/why.md";       check "a main behind origin/main is refused"       no $?
g merge -q --ff-only origin/main
g commit -q --allow-empty -m "local only"
run "v$next" "$work/why.md";       check "a main ahead of origin/main is refused"     no $?
g reset -q --hard origin/main
is "nothing changed" untouched

echo "-- bump"
run "v${current%%.*}.0.0" "$work/why.md"; check "a version not above the current one is refused" no $?
is "nothing changed" untouched
run "v$next" "$work/why.md";       check "a higher version bumps"                         ok $?
is "plugin.json moved"             [ "$(version_in plugin.json)" = "$next" ]
is "marketplace.json moved with it" [ "$(version_in marketplace.json)" = "$next" ]
is "CHANGELOG got the section"     grep -q "^## \[$next\] - $(date +%Y-%m-%d)$" "$repo/CHANGELOG.md"
is "CHANGELOG keeps Unreleased above it" bash -c 'grep -n "^## \[" "$1" | head -2 | tr "\n" " " | grep -q "Unreleased.*\[$2\]"' _ "$repo/CHANGELOG.md" "$next"
is "committed on release/v$next"   [ "$(g rev-parse --abbrev-ref HEAD)" = "release/v$next" ]
is "the tree is clean after the commit" [ -z "$(g status --porcelain)" ]
is "the commit title is chore(release): v$next" [ "$(g log -1 --format=%s)" = "chore(release): v$next" ]
is "no tag yet"                    [ -z "$(g tag -l)" ]
is "no release yet"                bash -c '! grep -q "release create" "$GH_LOG"'

echo "-- tag and release, after the merge"
g switch -q main; g merge -q --ff-only "release/v$next"; g push -q origin main
export VIEW_RC=0
run "v$next" "$work/why.md";       check "an existing release is refused"                 no $?
is "no second release"             bash -c '! grep -q "release create" "$GH_LOG"'
unset VIEW_RC
run "v$next" "$work/why.md";       check "from the merged main it tags and releases"      ok $?
is "the tag is on origin"          git -C "$origin" show-ref --verify --quiet "refs/tags/v$next"
is "the tag points at main"        [ "$(git -C "$origin" rev-parse "v$next^{commit}")" = "$(git -C "$origin" rev-parse main)" ]
is "gh release create --verify-tag --notes-file --generate-notes" bash -c 'grep -q -- "release create v$1 --verify-tag --notes-file .* --generate-notes" "$GH_LOG"' _ "$next"
is "the tree is still clean"       untouched

echo "-- a pushed tag without a release resumes"
g tag -d "v$next" >/dev/null; git -C "$origin" tag -d "v$next" >/dev/null
g tag -a -m "v$next" "v$next"; g push -q origin "v$next"; g tag -d "v$next" >/dev/null   # pushed from another machine
run "v$next" "$work/why.md";       check "an existing tag at HEAD is reused"              ok $?
is "the release was created"       bash -c 'grep -q "release create" "$GH_LOG"'

echo "-- a tag that already exists elsewhere"
git -C "$origin" tag "v${next%.*}.9" "main~1"
run "v${next%.*}.9" "$work/why.md"; check "a number whose tag exists on origin is not bumped to" no $?
is "nothing changed" untouched

echo
echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
