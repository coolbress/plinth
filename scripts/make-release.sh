#!/usr/bin/env bash
# Cut a plinth release. Run by a person, twice with the same arguments:
#
#   scripts/make-release.sh vX.Y.Z <notes-file>
#
# Run 1, from an up-to-date `main`: bumps `version` in plugin.json and
# marketplace.json together, opens the `## [X.Y.Z]` section in CHANGELOG.md,
# and commits on `release/vX.Y.Z`. Push it, open the pull request, merge it;
# `main` takes no direct push, and a squash merge changes the commit, so the
# tag cannot be made before that.
# Run 2, from the merged `main`: pushes the annotated tag `vX.Y.Z` and creates
# the GitHub Release. Which run this is follows from the files, not a flag.
#
# The notes file is the *why*, written by a person, and it must say which
# template tag this release was tested with (`tested with <template> <tag>`,
# the constants in scripts/new-project.sh). Without either there is no
# release: `--generate-notes` is an index of pull requests, not an
# explanation, and the tested tag is the only compatibility statement plinth
# makes. The generated index is appended under the notes; .github/release.yml
# groups it.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugin="$root/.claude-plugin/plugin.json"
market="$root/.claude-plugin/marketplace.json"
changelog="$root/CHANGELOG.md"
usage="usage: scripts/make-release.sh vX.Y.Z <notes-file>"
stop() { printf '%s\n' "$@" >&2; exit 1; }

tag="${1:?$usage}"; notes="${2:?$usage}"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || stop "not a vX.Y.Z tag: $tag" "$usage"
ver="${tag#v}"

# -- the notes: a why, and the tested template tag ---------------------------
[ -f "$notes" ] || stop "notes file not found: $notes"
template_repo="$(sed -nE 's/^template_repo="([^"]+)"$/\1/p' "$root/scripts/new-project.sh")"
template_ref="$(sed -nE 's/^template_ref="([^"]+)"$/\1/p' "$root/scripts/new-project.sh")"
[ -n "$template_repo" ] && [ -n "$template_ref" ] || stop "cannot read template_repo/template_ref from scripts/new-project.sh"
tested="tested with ${template_repo##*/} ${template_ref}"
grep -qxF -- "$tested" "$notes" \
  || stop "the notes must say what this release was tested with, on one line, exactly:" "  $tested" \
          "(the tag the door pins in scripts/new-project.sh; change the pin first if it is not the one you tested)"
# Prose, not structure: headings and rules are not a why; letters are.
[ -n "$(grep -vF -- "$tested" "$notes" | grep -vE '^[[:space:]]*#' | tr -cd '[:alpha:]')" ] \
  || stop "the notes say nothing but the tested line and markup: write why this release exists"

# -- where we are: a clean main that equals origin/main ----------------------
cd "$root"
# Tracked files only: the notes file usually sits in the checkout, untracked,
# and nothing here commits or tags an untracked file.
[ -z "$(git status --porcelain --untracked-files=no)" ] || stop "the working tree has uncommitted changes"
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || stop "run this from main (a release starts and ends there)"
# Run 2 reads parents to find the release commit; a shallow boundary would pass for one.
[ "$(git rev-parse --is-shallow-repository)" = false ] || stop "shallow clone; 'git fetch --unshallow' first"
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || stop "main is not at origin/main; pull or push first"
# gh exits 1 for "not found" and for a failed query alike; only the former is "no release".
if out="$(gh release view "$tag" 2>&1)"; then
  stop "release $tag already exists; 'gh release edit $tag' changes it"
elif ! grep -qi 'not found' <<<"$out"; then
  stop "cannot query releases: $out"
fi

version_in() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version", ""))' "$1"; }
# `--exit-code` is 2 when the ref is absent; a transport or auth failure is
# another status and must not read as "absent".
tag_on_origin() {
  local rc=0
  git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1 || rc=$?
  case "$rc" in 0) return 0 ;; 2) return 1 ;; *) stop "cannot list origin's tags (git ls-remote exit $rc); nothing changed" ;; esac
}
branch_on_origin() {
  local rc=0
  git ls-remote --exit-code --heads origin "refs/heads/release/$tag" >/dev/null 2>&1 || rc=$?
  case "$rc" in 0) return 0 ;; 2) return 1 ;; *) stop "cannot list origin's branches (git ls-remote exit $rc); nothing changed" ;; esac
}
current="$(version_in "$plugin")"

# -- run 2: the files already say this version; tag and publish -------------
if [ "$current" = "$ver" ] && [ "$(version_in "$market")" = "$ver" ] && grep -q "^## \[$ver\]" "$changelog"; then
  # The tag goes on the commit that set this version, not on HEAD: a pull
  # request merged after the release one is unreleased and must stay so. The
  # release commit is the newest one whose top-level version is this one while
  # its parent's is not; neither -G (a reorder re-adds the line) nor -S (the
  # string may appear in a dependency) says that.
  version_at() { git show "$1:.claude-plugin/plugin.json" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("version", ""))' 2>/dev/null || true; }
  release_commit=""
  for c in $(git log --format=%H -- "$plugin"); do
    [ "$(version_at "$c")" = "$ver" ] || continue
    [ "$(version_at "$c^")" != "$ver" ] || continue
    release_commit="$c"; break
  done
  [ -n "$release_commit" ] || stop "no commit on main sets version $ver in plugin.json"
  if tag_on_origin; then
    # A push that succeeded before a release that did not: pick up from here.
    # Read the remote tag without creating a local one.
    git fetch -q origin "refs/tags/$tag"
    [ "$(git rev-parse 'FETCH_HEAD^{commit}')" = "$release_commit" ] \
      || stop "$tag already exists on origin and points elsewhere; tags are not moved"
  else
    if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
      # Left behind by a push that failed: reuse it if it is the right one.
      [ "$(git rev-parse "$tag^{commit}")" = "$release_commit" ] \
        || stop "a local $tag points elsewhere; 'git tag -d $tag', then run again"
    else
      git tag -a -m "$tag" "$tag" "$release_commit"
    fi
    git push -q origin "refs/tags/$tag"
  fi
  # --verify-tag: without it gh creates a missing tag silently, and a typo ships.
  gh release create "$tag" --verify-tag --notes-file "$notes" --generate-notes
  echo "released $tag at ${release_commit:0:12}: the notes on top, the generated index under them"
  [ "$release_commit" = "$(git rev-parse HEAD)" ] \
    || echo "main has $(git rev-list --count "$release_commit..HEAD") later commit(s); they stay unreleased"
  exit 0
fi

# -- run 1: bump both manifests and the changelog, commit on a branch --------
[ "$(printf '%s\n%s\n' "$current" "$ver" | sort -V | tail -1)" = "$ver" ] && [ "$current" != "$ver" ] \
  || stop "$ver is not above the current version $current"
if tag_on_origin; then
  stop "$tag already exists on origin; a number is used once"
fi
grep -q '^## \[Unreleased\]$' "$changelog" || stop "CHANGELOG.md has no '## [Unreleased]' section to release from"
# The branch first: a leftover release/vX.Y.Z from an abandoned attempt stops
# here, before any file changes. On origin too: a local `switch -c` would
# succeed and the push would fail non-fast-forward after the files changed.
if branch_on_origin; then
  stop "release/$tag already exists on origin; finish that release or delete the branch first"
fi
git switch -q -c "release/$tag"

python3 - "$plugin" "$market" "$changelog" "$ver" "$(date +%Y-%m-%d)" <<'PY'
import json, pathlib, sys
plugin, market, changelog, ver, today = sys.argv[1:]
for f in (plugin, market):
    p = pathlib.Path(f); d = json.loads(p.read_text()); d["version"] = ver
    p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
p = pathlib.Path(changelog)
# Everything that was under Unreleased is now under the new heading.
p.write_text(p.read_text().replace("## [Unreleased]\n", f"## [Unreleased]\n\n## [{ver}] - {today}\n", 1))
PY

git add "$plugin" "$market" "$changelog"
git commit -q -m "chore(release): $tag"
cat <<MSG
bumped $current -> $ver in plugin.json, marketplace.json and CHANGELOG.md, committed on release/$tag.
next: push the branch, open the pull request, merge it; then from the merged main run
  scripts/make-release.sh $tag $notes
again to push the tag and create the release.
MSG
