#!/usr/bin/env bash
# shellcheck disable=SC2034  # the checks read their variables inside eval strings
# scripts/raise-template-pin.sh (#954). No network: the script runs in a
# throwaway copy of the files a pin raise edits, and `gh` is mocked. The
# verdict is what changed in those files and what the script printed.
#
# One property: a raise edits the places #947's and #952's raises edited by
# hand, each line changed only in the tag and the commit, and nothing when
# the tag does not exist, is not a published release, names another commit
# than the one given, or the template's diff cannot be read. What it says
# about the eval suite comes from scripts/lib/template-reads.sh, the reading
# scripts/make-release.sh's run 1 asks from.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

mkdir -p "$work/bin"
# Tags, tag objects and releases come from files the cases write:
#   $work/tags      <tag> <commit|tag> <sha>   (git/ref/tags/<tag>)
#   $work/tagobjs   <tag object sha> <commit>  (git/tags/<sha>)
#   $work/releases  <tag>                      (releases/tags/<tag>)
# Anything else is GitHub's 404. COMPARE_OUT is the compare's --jq output.
cat >"$work/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -u
printf 'gh %s\n' "$*" >>"$GH_LOG"
nf() { echo '{"message":"Not Found","status":"404"}gh: Not Found (HTTP 404)' >&2; exit 1; }
[ "${GH_RC:-0}" = 0 ] || { echo "error connecting to api.github.com" >&2; exit "$GH_RC"; }
case "$2" in
  repos/*/git/ref/tags/*)
    line="$(awk -v t="${2##*/}" '$1 == t' "$W/tags" 2>/dev/null)"; [ -n "$line" ] || nf
    set -- $line; echo "$2 $3" ;;
  repos/*/git/tags/*)
    line="$(awk -v s="${2##*/}" '$1 == s' "$W/tagobjs" 2>/dev/null)"; [ -n "$line" ] || nf
    set -- $line; echo "commit $2" ;;
  repos/*/releases/tags/*)
    grep -qx "${2##*/}" "$W/releases" 2>/dev/null || nf; echo false ;;
  repos/*/compare/*)
    [ "${COMPARE_RC:-0}" = 0 ] || { echo "error connecting to api.github.com" >&2; exit "$COMPARE_RC"; }
    printf '%s\n' "${COMPARE_OUT:-0}" ;;
  *) echo "unexpected gh call: $*" >&2; exit 9 ;;
esac
MOCK
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH" W="$work" GH_LOG="$work/gh.log"

files=(scripts/new-project.sh README.md docs/tutorials/getting-started.md
       tests/new-project-failpath.sh .github/workflows/ci.yml CHANGELOG.md)
door="$root/scripts/new-project.sh"
old_ref="$(sed -nE 's/^template_ref="([^"]+)"$/\1/p' "$door")"
old_sha="$(sed -nE 's/^template_sha="([0-9a-f]{40})"$/\1/p' "$door")"
version="$(sed -nE 's/^ *"version": "([^"]+)".*/\1/p' "$root/.claude-plugin/plugin.json" | head -1)"
tested="$(awk -v v="## [$version]" 'index($0, v) == 1 {on=1; next} /^## \[/ {on=0} on' "$root/CHANGELOG.md" |
          sed -nE 's/^tested with plinth-template (v[^ ]+)$/\1/p')"
new_sha="1234567890abcdef1234567890abcdef12345678"

fresh() { # a new copy of the files, committed, so `git diff` is the raise
  rm -rf "$work/repo"; mkdir -p "$work/repo/scripts/lib"
  for f in "${files[@]}" .claude-plugin/plugin.json; do
    mkdir -p "$work/repo/$(dirname "$f")"; cp "$root/$f" "$work/repo/$f"
  done
  cp "$root/scripts/raise-template-pin.sh" "$work/repo/scripts/" 2>/dev/null
  cp "$root/scripts/lib/template-reads.sh" "$work/repo/scripts/lib/"
  # No changelog fragment of a raise, whatever the real checkout has today: on
  # a branch carrying a raise it holds a line the script would move, not add.
  # Another fragment beside it is left alone (#1136).
  mkdir -p "$work/repo/changelog.d"
  printf '### Added\n\n- An entry.\n' >"$work/repo/changelog.d/other.md"
  git -C "$work/repo" init -q && git -C "$work/repo" add -A &&
    git -C "$work/repo" -c user.name=t -c user.email=t@example.com commit -qm base
  : >"$work/gh.log"
  printf 'v9.9.9 commit %s\nv9.9.8 tag aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nv9.9.7 commit %s\n' "$new_sha" "$new_sha" >"$work/tags"
  printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa %s\n' "$new_sha" >"$work/tagobjs"
  printf 'v9.9.9\nv9.9.8\n' >"$work/releases"   # v9.9.7: a tag with no release
}
raise() { (cd "$work/repo" && scripts/raise-template-pin.sh "$@") >"$work/out" 2>&1; }
unchanged() { git -C "$work/repo" diff --quiet && [ -z "$(git -C "$work/repo" status --porcelain)" ]; }

[ -n "$old_ref" ] && [ -n "$old_sha" ] && [ -n "$tested" ] ||
  { echo "  FAIL  cannot read the pin, the version or its tested line"; exit 1; }
[ -x "$root/scripts/raise-template-pin.sh" ] || bad "scripts/raise-template-pin.sh exists and is executable"

# ---- Must not pass: nothing changes.
fresh; raise v9.9.6
check "a tag that does not exist is refused" '! grep -q "^raised" "$work/out" && grep -q "no tag v9.9.6" "$work/out" && unchanged'
fresh; raise v9.9.9 abcdef0
check "a tag naming another commit than the one given is refused" '! grep -q "^raised" "$work/out" && grep -q "names $new_sha, not abcdef0" "$work/out" && unchanged'
fresh; raise v9.9.7
check "a tag with no published release is refused" '! grep -q "^raised" "$work/out" && grep -q "no published release" "$work/out" && unchanged'
fresh; raise "$old_ref"
check "the tag already pinned is refused" '! grep -q "^raised" "$work/out" && grep -q "already" "$work/out" && unchanged'
fresh; raise 1.2.3
check "a tag not in vX.Y.Z form is refused" '! grep -q "^raised" "$work/out" && grep -q "not a vX.Y.Z tag" "$work/out" && unchanged'
fresh; COMPARE_RC=1 raise v9.9.9
check "a template diff that cannot be read is refused before any edit" '! grep -q "^raised" "$work/out" && grep -q "cannot read what" "$work/out" && unchanged'
fresh; GH_RC=1 raise v9.9.9
check "GitHub not answering is not read as a missing tag" '! grep -q "^raised" "$work/out" && grep -q "cannot read" "$work/out" && ! grep -q "no tag" "$work/out" && unchanged'

# ---- The raise: the same edits as #947's and #952's.
fresh; COMPARE_OUT=$'1\nREADME.md' raise v9.9.9 "${new_sha:0:7}"; rc=$?
check "a published tag naming the given commit is raised" '[ "$rc" = 0 ] && grep -q "^raised the template pin: plinth-template $old_ref (${old_sha:0:7}) -> v9.9.9 (${new_sha:0:7})" "$work/out"'
git -C "$work/repo" add -N changelog.d/template-pin.md   # new: counted in the diff
diffs="$(git -C "$work/repo" diff --numstat | awk '{print $3, $1, $2}' | sort)"
want="$(printf '%s\n' ".github/workflows/ci.yml 1 1" "changelog.d/template-pin.md 3 0" "README.md 1 1" \
          "docs/tutorials/getting-started.md 1 1" "scripts/new-project.sh 2 2" "tests/new-project-failpath.sh 1 1" | sort)"
check "it changes the five files #947 and #952 changed by hand, and canary-template's name (#958)" '[ "$diffs" = "$want" ] || { echo "$diffs" >&2; false; }'
# Each removed line, with the tag and the commit moved, is the added line.
moved="$(git -C "$work/repo" diff -U0 -- . ':!CHANGELOG.md' ':!changelog.d' | grep '^-[^-]' | cut -c2- |
         sed -e "s/$old_ref/v9.9.9/g" -e "s/$old_sha/$new_sha/g" -e "s/${old_sha:0:7}/${new_sha:0:7}/g")"
added="$(git -C "$work/repo" diff -U0 -- . ':!CHANGELOG.md' ':!changelog.d' | grep '^+[^+]' | cut -c2-)"
check "every edited line differs only in the tag and the commit" '[ -n "$moved" ] && [ "$moved" = "$added" ]'
check "new-project.sh pins the tag's full commit" 'grep -qx "template_sha=\"$new_sha\"" "$work/repo/scripts/new-project.sh" && grep -qx "template_ref=\"v9.9.9\"" "$work/repo/scripts/new-project.sh"'
check "canary-template's name says the new tag and commit" 'grep -qF "name: canary-template (plinth-template v9.9.9 at ${new_sha:0:7})" "$work/repo/.github/workflows/ci.yml"'
check "a changelog fragment says it, one Changed line naming the new tag, and reads as a fragment (#1136)" '[ "$(cat "$work/repo/changelog.d/template-pin.md")" = "$(printf "### Changed\n\n- \`/plinth:new-project\` renders plinth-template v9.9.9 instead of %s." "$old_ref")" ] && "$root/scripts/changelog-fragments.py" check "$work/repo" >/dev/null'
check "CHANGELOG.md and the other fragment are untouched" 'git -C "$work/repo" diff --quiet -- CHANGELOG.md changelog.d/other.md'
check "it prints that no eval suite is owed for a diff that misses what the agent reads" 'grep -q "^eval suite: not owed" "$work/out" && grep -q "from $tested" "$work/out"'
check "it prints what is left: the re-render, canary-web's FROM lines, the CHANGELOG text, the pull request" 'grep -q "tests/template-render.sh --write" "$work/out" && grep -q "FROM lines at v9.9.9 into canary-web/Dockerfile" "$work/out" && grep -q "gh release view v9.9.9" "$work/out" && grep -q "chore(new-project): render plinth-template v9.9.9" "$work/out"'
check "it reads the compare from the tag the last release was tested with" 'grep -q "compare/$tested\.\.\.v9\.9\.9" "$work/gh.log"'

# A second raise before the release moves the same line, not a new one.
git -C "$work/repo" add -A && git -C "$work/repo" -c user.name=t -c user.email=t@example.com commit -qm first
printf 'v9.9.10 commit %s\n' "abcdefabcdefabcdefabcdefabcdefabcdefabcd" >>"$work/tags"; echo v9.9.10 >>"$work/releases"
COMPARE_OUT=$'1\ntemplate/AGENTS.md.jinja' raise v9.9.10
frag="$(cat "$work/repo/changelog.d/template-pin.md")"
check "a second raise moves the fragment's line instead of adding one" '! grep -q "v9.9.9" <<<"$frag" && grep -c "renders plinth-template v9.9.10" <<<"$frag" | grep -qx 1'
check "it prints that the eval suite is owed and which file says so" 'grep -q "^eval suite: owed" "$work/out" && grep -q "^  template/AGENTS.md.jinja$" "$work/out"'

# An annotated tag names a tag object; the commit is behind it.
fresh; COMPARE_OUT=0 raise v9.9.8
check "an annotated tag is followed to its commit" 'grep -qx "template_sha=\"$new_sha\"" "$work/repo/scripts/new-project.sh" && grep -q "git/tags/aaaaaaaa" "$work/gh.log"'

# The eval-suite answers make-release.sh would reach, through the same reading.
fresh; COMPARE_OUT=$'2\ntemplate/.claude/settings.json\ntemplate/README.md.jinja' raise v9.9.9
check "a change under template/.claude/ is owed" 'grep -q "^eval suite: owed" "$work/out" && grep -q "^  template/.claude/settings.json$" "$work/out"'
fresh; COMPARE_OUT=300 raise v9.9.9
check "a list GitHub cut short at 300 files is owed" 'grep -q "^eval suite: owed" "$work/out" && grep -q "over 300 files" "$work/out"'
fresh; COMPARE_OUT=$'1\ncopier.yml' raise v9.9.9
check "a moved copier.yml asks whether plinth_sha's default moved" 'grep -q "plinth_sha" "$work/out"'
check "make-release.sh reads the eval suite through the same library" \
  'grep -q "^\. \"\$root/scripts/lib/template-reads.sh\"" "$root/scripts/make-release.sh" && grep -q "template_agent_reads \"\$template_repo\" \"\$prev_ref\" \"\$template_ref\"" "$root/scripts/make-release.sh" && grep -q "released_template_ref \"\$changelog\"" "$root/scripts/make-release.sh"'

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
