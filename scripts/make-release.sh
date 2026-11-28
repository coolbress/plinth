#!/usr/bin/env bash
# Cut a plinth release. Run by a person, twice with the same arguments:
#
#   scripts/make-release.sh vX.Y.Z <why-file>
#
# Run 1, from an up-to-date `main`: bumps `version` in plugin.json and
# marketplace.json together, opens the `## [X.Y.Z]` section in CHANGELOG.md
# with the why-file's text above the entries of the fragments in changelog.d/
# (scripts/changelog-fragments.py; #1136), deletes the fragments, moves the
# link references at the end of the file, and commits on `release/vX.Y.Z`.
# Push it, open the pull request, run `e2e` on the branch, then merge it: `main`
# takes no direct push, and a squash merge changes the commit, so the tag cannot
# be made before that. The merge is what reaches an installation with
# auto-update on (the version moves on the default branch), so `e2e` comes
# before it (#855).
# Run 2, from the merged `main`: pushes the annotated tag `vX.Y.Z` and creates
# the GitHub Release. Which run this is follows from the files, not a flag.
# Run 2 first asks for a green `e2e` run (.github/workflows/e2e.yml: the real
# repository journey, deletion included) on the very commit it is about to tag,
# or on a commit with that commit's tree: the same files, which is what a squash
# merge of an up-to-date release branch leaves. `gh workflow run e2e.yml --ref
# release/vX.Y.Z` before the merge provides it; so do the nightly run and
# `--ref main` on the commit itself. Not the latest green run, not one on other
# files, not a failed, skipped or running one: the commit and the tree are
# compared and the conclusion is read.
#
# The why is written by a person, and it must say which template tag this
# release was tested with (`tested with <template> <tag>`, the constants in
# scripts/new-project.sh). Without either there is no release:
# `--generate-notes` is an index of pull requests, not an explanation, and the
# tested tag is the only compatibility statement plinth makes. Run 1 takes the
# why as a file, as `git commit -F` takes a message, and keeps it in
# CHANGELOG.md; nothing reads the file again. Run 2 reads the version's section
# of the merged `main`, runs run 1's checks again on the why above its first
# `###` (the pull request can change it), and publishes the section, heading
# left out, as the Release's text with the generated index under it;
# .github/release.yml groups the index. Run 2 accepts the second argument and
# does not read it.
#
# Run 1 also asks for the eval suite (#700) when the template tag the door pins
# moved since the release before (that section's tested line) and the
# template's diff between the two tags touches a file a new project's agent
# reads: template/AGENTS.md.jinja, template/CLAUDE.md.jinja, anything under
# template/.claude/ (settings, the output style, the default skills). The run
# it names is scripts/eval-suite.sh --release (#876). The why
# then carries one of three lines, which stay in the section and the Release:
#   eval suite: <https://github.com/<owner>/<repo>/issues/<n>#issuecomment-<id>>
#   eval suite: on the release candidate
#   eval suite not run: <the reason>
# The second (#1134) is the run on release/vX.Y.Z, which gives the smoke
# verdict too: its link cannot be in the commit it tests, so it goes in the
# release pull request's description, and run 2 reads it there (the pull
# request titled `chore(release): vX.Y.Z` that the release commit belongs to),
# refuses without it, and publishes it in the Release in place of the line.
# A release whose pin did not move, or whose move touches none of those
# files, is not asked.
#
# Run 1 holds the train (#1132): it stops, before any change, when origin's
# highest vX.Y.Z tag is less than 7 days old, unless the why carries one line
#   hotfix: <reason>
# which stays in the section and the Release. An empty reason always stops.
# A release the owner decided to cut early that is not a hotfix carries
# instead one line naming the comment that records the decision:
#   train exception: <https://github.com/<owner>/<repo>/issues/<n>#issuecomment-<id>>
# Run 1 reads that comment through gh and stops when it cannot; the line stays
# in the section and the Release. A why with both lines stops.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugin="$root/.claude-plugin/plugin.json"
market="$root/.claude-plugin/marketplace.json"
changelog="$root/CHANGELOG.md"
usage="usage: scripts/make-release.sh vX.Y.Z <why-file>"
stop() { printf '%s\n' "$@" >&2; exit 1; }
# shellcheck source=scripts/lib/template-reads.sh
. "$root/scripts/lib/template-reads.sh"

tag="${1:?$usage}"; why_file="${2:-}"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || stop "not a vX.Y.Z tag: $tag" "$usage"
ver="${tag#v}"

# -- the why: prose, and the tested template tag ------------------------------
template_repo="$(sed -nE 's/^template_repo="([^"]+)"$/\1/p' "$root/scripts/new-project.sh")"
template_ref="$(sed -nE 's/^template_ref="([^"]+)"$/\1/p' "$root/scripts/new-project.sh")"
[ -n "$template_repo" ] && [ -n "$template_ref" ] || stop "cannot read template_repo/template_ref from scripts/new-project.sh"
tested="tested with ${template_repo##*/} ${template_ref}"
# The suite's link, as the why or the release pull request's description gives it.
suite_link_re='^eval suite: <https://github\.com/[^/[:space:]]+/[^/[:space:]]+/(issues|pull)/[0-9]+#issuecomment-[0-9]+>$'
# The suite run on the release candidate, which also gives the smoke verdict
# (#1134): the link cannot be in the commit it tests, so the why says this and
# the release pull request's description carries the link.
candidate_line="eval suite: on the release candidate"
# The same test for the why-file in run 1 and the section in run 2. Reads the
# text on stdin; $1 names it in the refusal.
check_why() {
  local text; text="$(cat)"
  grep -qxF -- "$tested" <<<"$text" \
    || stop "$1 must say what this release was tested with, on one line, exactly:" "  $tested" \
            "(the tag the door pins in scripts/new-project.sh; change the pin first if it is not the one you tested)"
  # Prose, not structure: headings and rules are not a why; letters are.
  [ -n "$(grep -vF -- "$tested" <<<"$text" | grep -vE '^[[:space:]]*#' | tr -cd '[:alpha:]')" ] \
    || stop "$1 says nothing but the tested line and markup: write why this release exists"
  # It sits under the version's `##` heading as prose. A `##` or `###` line
  # would cut the section; any other level fails markdownlint there (a second
  # h1, or a skipped level), and `ci / docs` with it.
  if grep -qE '^ {0,3}#{1,6}([[:space:]]|$)' <<<"$text"; then
    stop "$1 has a heading line; the why is prose under the version's heading, and a heading would cut the section:" \
         "$(grep -nE '^ {0,3}#{1,6}([[:space:]]|$)' <<<"$text")"
  fi
}

# -- where we are: a clean main that equals origin/main ----------------------
cd "$root"
# Tracked files only: a why-file may sit in the checkout, untracked, and
# nothing here commits or tags an untracked file.
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

# -- run 2: the manifests already say this version; tag and publish ---------
if [ "$current" = "$ver" ] && [ "$(version_in "$market")" = "$ver" ]; then
  [ -z "$why_file" ] || echo "run 2 publishes the why in CHANGELOG.md; $why_file is not read"
  # The section: under its heading, to the next version's heading or the link
  # references (the [Unreleased] line heads them), with its edges trimmed.
  section="$(python3 - "$changelog" "$ver" <<'PY'
import re, sys
m = re.search(r"^## \[" + re.escape(sys.argv[2]) + r"\][^\n]*\n(.*?)(?=^## \[|^\[Unreleased\]: |\Z)",
              open(sys.argv[1]).read(), re.M | re.S)
print(m[1].strip() if m else "")
PY
)"
  [ -n "$section" ] || stop "CHANGELOG.md has no '## [$ver]' section with text under it; run 2 publishes that section"
  check_why "the why above the first ### of CHANGELOG.md's [$ver] section" <<<"$(awk '/^### /{exit} 1' <<<"$section")"
  on_candidate=""; grep -qxF -- "$candidate_line" <<<"$(awk '/^### /{exit} 1' <<<"$section")" && on_candidate=1
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
  # The suite run on the candidate (#1134): its link is in the release pull
  # request's description, and goes into the Release in place of the line.
  if [ -n "$on_candidate" ]; then
    body="$(gh api "repos/{owner}/{repo}/commits/$release_commit/pulls" \
              --jq ".[] | select(.title == \"chore(release): $tag\") | .body" 2>&1)" \
      || stop "cannot read the release pull request of ${release_commit:0:12}: $body"
    link="$(tr -d '\r' <<<"$body" | grep -E '^eval suite:' || true)"
    [ "$(grep -c . <<<"$link")" = 1 ] && [[ "$link" =~ $suite_link_re ]] \
      || stop "the section says '$candidate_line'; the description of the pull request 'chore(release): $tag' must then carry the run's link on one line, alone, in angle brackets:" \
              "  eval suite: <https://github.com/<owner>/<repo>/issues/<n>#issuecomment-<id>>" \
              "it has: ${link:-no 'eval suite:' line}"
    section="$(awk -v c="$candidate_line" -v l="$link" '$0 == c { print l; next } 1' <<<"$section")"
    echo "the suite's run on the candidate: $link"
  fi
  # Tier 2 on this exact commit, green, or no tag. GitHub filters on head_sha;
  # the select repeats it so a mock or a lenient server cannot widen the
  # answer. `conclusion // status` names a running run as such.
  runs="$(gh api -X GET "repos/{owner}/{repo}/actions/workflows/e2e.yml/runs" -f "head_sha=$release_commit" -F per_page=100 \
            --jq ".workflow_runs[] | select(.head_sha == \"$release_commit\") | \"\(.conclusion // .status) \(.html_url)\"" 2>&1)" \
    || stop "cannot query the e2e runs on ${release_commit:0:12}: $runs"
  if grep -q '^success ' <<<"$runs"; then
    e2e_line="e2e green on ${release_commit:0:12}: $(grep -m1 '^success ' <<<"$runs" | cut -d' ' -f2)"
  else
    # Or on the same files (#855): the release branch's run, whose commit the
    # squash replaced. The tree holds every file the run used, e2e.yml and the
    # door included, so an equal tree is the same proof on another commit. The
    # commit is asked of GitHub: a merged branch is deleted, and its head is in
    # no clone. The newest 100 runs only: an older green run asks for a new one.
    # A commit whose tree cannot be read is passed over and named if nothing
    # else matches: it can only cost a refusal, never make a run count.
    listed="$(gh api -X GET "repos/{owner}/{repo}/actions/workflows/e2e.yml/runs" -F per_page=100 \
                --jq '.workflow_runs[] | "\(.conclusion // .status) \(.head_sha) \(.html_url)"' 2>&1)" \
      || stop "cannot list the e2e runs: $listed"
    tree="$(git rev-parse "$release_commit^{tree}")"
    e2e_line=""; unread=""
    while read -r sha url; do
      got="$(gh api "repos/{owner}/{repo}/git/commits/$sha" --jq .tree.sha 2>/dev/null)" \
        || { unread="$unread ${sha:0:12}"; continue; }
      [ "$got" = "$tree" ] || continue
      e2e_line="e2e green on ${sha:0:12}, with the tree of ${release_commit:0:12}, the commit being tagged: $url"
      break
    done < <(sed -n 's/^success //p' <<<"$listed" | awk '!seen[$1]++')
    [ -n "$e2e_line" ] \
      || stop "no green e2e run on ${release_commit:0:12}, the commit being tagged, or on a commit with its tree; a release needs one (the real repository journey, deletion included):" \
              "${runs:-  (no run on that commit)}" \
              ${unread:+"  could not read the tree of:$unread"} \
              "  run it: gh workflow run e2e.yml --ref main   (while main is at that commit; if main has moved on, a branch at it)" \
              "  a run already started on the release branch counts once it is green, if the merge left its files unchanged" \
              "  then, once it is green, run this again"
  fi
  echo "$e2e_line"
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
  gh release create "$tag" --verify-tag --notes-file - --generate-notes <<<"$section"
  echo "released $tag at ${release_commit:0:12}: the CHANGELOG.md section on top, the generated index under it"
  [ "$release_commit" = "$(git rev-parse HEAD)" ] \
    || echo "main has $(git rev-list --count "$release_commit..HEAD") later commit(s); they stay unreleased"
  exit 0
fi

# -- run 1: bump both manifests and the changelog, commit on a branch --------
[ -n "$why_file" ] || stop "run 1 needs the why-file: why this release exists, and the tested line" "$usage"
[ -f "$why_file" ] || stop "why-file not found: $why_file"
check_why "the why-file" < "$why_file"
[ "$(printf '%s\n%s\n' "$current" "$ver" | sort -V | tail -1)" = "$ver" ] && [ "$current" != "$ver" ] \
  || stop "$ver is not above the current version $current"
if tag_on_origin; then
  stop "$tag already exists on origin; a number is used once"
fi
# The train (#1132): at most one release a week. Sooner is a hotfix, and the
# why says so on one line, `hotfix: <reason>`, which the section and the
# Release then carry. The release before is origin's highest vX.Y.Z tag, and
# its age is the tag's own date, the tagger's.
hotfix_line="$(grep -E '^hotfix:' "$why_file" || true)"
[ "$(grep -c . <<<"$hotfix_line")" -le 1 ] || stop "the why-file has more than one 'hotfix:' line:" "$hotfix_line"
if [ -n "$hotfix_line" ] && [ -z "$(tr -cd '[:alpha:]' <<<"${hotfix_line#hotfix:}")" ]; then
  stop "the why's 'hotfix:' line must give the reason: a published advisory reaching what plinth ships or pins," \
       "installing plinth as the README says failing, or a consumer's required check failing because of plinth"
fi
# An early release that is not a hotfix (#1132's exception of 2026-11-27):
# one line naming the comment that records the decision, read here so a link
# to nothing does not pass.
exception_line="$(grep -E '^train exception:' "$why_file" || true)"
if [ -n "$exception_line" ]; then
  [ "$(grep -c . <<<"$exception_line")" -le 1 ] || stop "the why-file has more than one 'train exception:' line:" "$exception_line"
  [ -z "$hotfix_line" ] || stop "the why-file has both a 'hotfix:' and a 'train exception:' line; an early release is one or the other"
  exception_re='^train exception: <https://github\.com/([^/[:space:]]+/[^/[:space:]]+)/issues/[0-9]+#issuecomment-([0-9]+)>$'
  [[ "$exception_line" =~ $exception_re ]] \
    || stop "the 'train exception:' line must be the link to the comment that records the decision, in angle brackets:" \
            "  train exception: <https://github.com/<owner>/<repo>/issues/<n>#issuecomment-<id>>"
  exc_repo="${BASH_REMATCH[1]}"; exc_id="${BASH_REMATCH[2]}"
  exc_body="$(gh api "repos/$exc_repo/issues/comments/$exc_id" --jq .body 2>/dev/null)" && [ -n "$exc_body" ] \
    || stop "cannot read the comment the 'train exception:' line names ($exc_repo comment $exc_id); nothing changed"
fi
# The decisions page says what is true at the release (#1221): a
# `not built yet` marker whose issue is closed as completed stops here, as
# does a marker whose issue cannot be read. One closed another way is printed
# for the person and does not stop.
markers="$("$root/scripts/stale-decision-markers.sh" 2>&1)" \
  || stop "docs/reference/decisions-in-force.md is not what is true; nothing changed:" "$markers"
grep '^for a person:' <<<"$markers" >&2 || true
rc=0; tags="$(git ls-remote --exit-code --tags --refs origin 'refs/tags/v*' 2>&1)" || rc=$?
case "$rc" in 0|2) ;; *) stop "cannot list origin's tags (git ls-remote exit $rc); nothing changed" ;; esac
prev_tag="$(sed -nE 's|^[0-9a-f]+[[:space:]]+refs/tags/(v[0-9]+\.[0-9]+\.[0-9]+)$|\1|p' <<<"$tags" | sort -V | tail -1)"
if [ -n "$prev_tag" ]; then
  git fetch -q origin "refs/tags/$prev_tag" || stop "cannot fetch $prev_tag from origin; nothing changed"
  # Run 2 makes annotated tags; a lightweight one has no date of its own, and
  # its commit's date could be older than the release, so it stops.
  [ "$(git cat-file -t FETCH_HEAD)" = tag ] \
    || stop "$prev_tag on origin is not an annotated tag, so its release date cannot be read; nothing changed"
  born="$(git cat-file tag FETCH_HEAD | sed -nE 's/^tagger .* ([0-9]+) [-+][0-9]{4}$/\1/p')"
  [[ "$born" =~ ^[0-9]+$ ]] || stop "cannot read the date of $prev_tag; nothing changed"
  age=$(( $(date +%s) - born ))
  if [ "$age" -lt $(( 7 * 86400 )) ] && [ -z "$hotfix_line" ] && [ -z "$exception_line" ]; then
    stop "$prev_tag is $(( age / 86400 )) days $(( age % 86400 / 3600 )) hours old: plinth releases at most once a week (docs/how-to/cut-a-release.md)." \
         "wait until it is 7 days old, or, for a hotfix, add one line to the why-file:" \
         "  hotfix: <reason>" \
         "(a published advisory reaching what plinth ships or pins, installing plinth as the README says failing," \
         " or a consumer's required check failing because of plinth); the release section and the Release carry it." \
         "An early release the owner decided on, not a hotfix, names the comment that records the decision instead:" \
         "  train exception: <https://github.com/<owner>/<repo>/issues/<n>#issuecomment-<id>>"
  fi
  echo "the release before, $prev_tag, is $(( age / 86400 )) days old${hotfix_line:+; $hotfix_line}${exception_line:+; $exception_line}"
fi
grep -q '^## \[Unreleased\]$' "$changelog" || stop "CHANGELOG.md has no '## [Unreleased]' section to release from"
grep -qE '^\[Unreleased\]: [^[:space:]]+/compare/[^[:space:]]+\.\.\.HEAD$' "$changelog" \
  || stop "CHANGELOG.md has no '[Unreleased]: <repository>/compare/<tag>...HEAD' link reference to move"
# The entries come from the fragments, one file per pull request (#1136). A
# fragment that does not read, or a line left under [Unreleased], stops here,
# before any file changes; an untracked one would be written and not deleted.
[ -z "$(git ls-files --others --exclude-standard -- changelog.d)" ] \
  || stop "changelog.d/ has untracked files; commit them through a pull request or remove them:" \
          "$(git ls-files --others --exclude-standard -- changelog.d)"
entries="$(python3 "$root/scripts/changelog-fragments.py" assemble "$root")" \
  || stop "no file changed: the fragments in changelog.d/ do not make a release section (above)"
# The eval suite (#647, #700): when the pinned template moved since the release
# before and the move changes a file a new project's agent reads, the why must
# carry the suite's posted table or the reason it was not run. Asked from the
# template's own diff, through gh; a diff that cannot be read asks, too.
suite_line="$(grep -E '^eval suite( not run)?:' "$why_file" || true)"
[ "$(grep -c . <<<"$suite_line")" -le 1 ] || stop "the why-file has more than one 'eval suite' line:" "$suite_line"
prev_ref="$(released_template_ref "$changelog" "$current" "${template_repo##*/}")"
[ -n "$prev_ref" ] || stop "CHANGELOG.md's [$current] section has no 'tested with ${template_repo##*/} <tag>' line;" \
  "  it names the template the release before was tested with, which run 1 compares the pin with"
if [ "$prev_ref" != "$template_ref" ]; then
  # Over 300 files the list is cut short (GitHub's limit); a cut list asks.
  template_agent_reads "$template_repo" "$prev_ref" "$template_ref" \
    || stop "cannot read what $template_repo changed from $prev_ref to $template_ref: $template_reads_error"
  reads="$template_reads"
  if [ -n "$reads" ]; then
    case "$suite_line" in
      "$candidate_line") ;;
      "eval suite:"*)
        # In angle brackets: a bare URL in the section fails markdownlint (MD034), and `ci / docs` with it.
        [[ "$suite_line" =~ $suite_link_re ]] \
          || stop "the why's 'eval suite:' line must be the link to the comment with the suite's table, alone, in angle brackets:" \
                  "  eval suite: <https://github.com/<owner>/<repo>/issues/<n>#issuecomment-<id>>" "it says: $suite_line" ;;
      "eval suite not run:"*)
        [ -n "$(tr -cd '[:alpha:]' <<<"${suite_line#eval suite not run:}")" ] \
          || stop "the why's 'eval suite not run:' line must give the reason" ;;
      *)
        stop "the template pin moved from $prev_ref to $template_ref, which changes what a new project's agent reads:" \
             "$(sed 's/^/  /' <<<"$reads")" \
             "run the eval suite's release run, scripts/eval-suite.sh --release (docs/how-to/run-the-eval-suite.md)," \
             "post its table, and add to the why-file one line:" \
             "  eval suite: <https://github.com/<owner>/<repo>/issues/<n>#issuecomment-<id>>" \
             "or, to run it once on the release candidate, where it gives the smoke verdict too, the line" \
             "  $candidate_line" \
             "and the link in the release pull request's description;" \
             "or, if it is not run, the reason, which the release section then carries:" \
             "  eval suite not run: <why>" ;;
    esac
    echo "template $prev_ref -> $template_ref changes what the agent reads; the why says: $suite_line"
  fi
fi
# The branch first: a leftover release/vX.Y.Z from an abandoned attempt stops
# here, before any file changes. On origin too: a local `switch -c` would
# succeed and the push would fail non-fast-forward after the files changed.
if branch_on_origin; then
  stop "release/$tag already exists on origin; finish that release or delete the branch first"
fi
git switch -q -c "release/$tag"

python3 - "$plugin" "$market" "$changelog" "$ver" "$(date +%Y-%m-%d)" "$why_file" "$entries" <<'PY'
import json, pathlib, re, sys
plugin, market, changelog, ver, today, why_file, entries = sys.argv[1:]
for f in (plugin, market):
    p = pathlib.Path(f); d = json.loads(p.read_text()); d["version"] = ver
    p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
p = pathlib.Path(changelog); text = p.read_text()
# The links first, so that nothing in the why is taken for them: Unreleased
# compares from the new tag, and the new version links its Release. Neither
# exists before run 2; plinth-ci.yml's link check skips the two links of the
# version plugin.json names.
text = re.sub(r"^\[Unreleased\]: (\S+)/compare/\S+\.\.\.HEAD$",
              lambda m: f"[Unreleased]: {m[1]}/compare/v{ver}...HEAD\n[{ver}]: {m[1]}/releases/tag/v{ver}",
              text, count=1, flags=re.M)
# The why under the new heading, then the fragments' sections; [Unreleased]
# stays, empty, above it.
head, sep, rest = text.partition("## [Unreleased]\n")
why = pathlib.Path(why_file).read_text().strip()
body = f"{why}\n\n{entries.strip()}" if entries.strip() else why
p.write_text(f"{head}{sep}\n## [{ver}] - {today}\n\n{body}\n\n{rest.lstrip()}")
PY

git add "$plugin" "$market" "$changelog"
# The fragments go in the same commit that writes them out (#1136); dot files
# such as changelog.d/.markdownlint.jsonc stay, as the assembler skips them.
for f in "$root"/changelog.d/*.md; do if [ -e "$f" ]; then git rm -q -- "$f"; fi; done
git commit -q -m "chore(release): $tag"
if grep -qxF -- "$candidate_line" "$why_file"; then
  gate_run="the eval suite's release run, which gives the smoke verdict too (#1134)"
  gate_cmd="git switch release/$tag && scripts/eval-suite.sh --release"
  gate_where="posts its table on #647, and puts the comment's link in the pull request's description on one line, which run 2 puts in the Release:
  eval suite: <https://github.com/<owner>/<repo>/issues/<n>#issuecomment-<id>>"
else
  gate_run="the smoke run (about US\$0.90)"
  gate_cmd="git switch release/$tag && scripts/eval-suite.sh --smoke"
  gate_where="posts its table on #647:"
fi
cat <<MSG
bumped $current -> $ver in plugin.json, marketplace.json and CHANGELOG.md, deleted the fragments in changelog.d/, committed on release/$tag;
the why is in the [$ver] section now, and nothing reads $why_file again.
next: push the branch, open the pull request, and run e2e on the branch:
  gh workflow run e2e.yml --ref release/$tag
beside it, the owner runs $gate_run from a clone on this branch (it needs the owner's Claude login; every smoke row must pass), and $gate_where
  $gate_cmd
name the e2e run and that comment in the pull request's description.
once e2e is green, merge with scripts/merge-when-green.sh <n>, which stops until then but does not read the smoke run: the merge is what reaches an installation with auto-update on.
then from the merged main run
  scripts/make-release.sh $tag
again to push the tag and create the release.
MSG
