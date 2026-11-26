#!/usr/bin/env bash
# Raise the plinth-template tag the door renders (#954):
#
#   scripts/raise-template-pin.sh vA.B.C [<commit>]
#
# Reads the tag's commit from GitHub and refuses a tag that does not exist, is
# not a published release, or, when <commit> is given (seven or more hex
# characters, as a release page or the template's CI shows it), names another
# commit. Then edits the places a raise changes, each line only in the tag and
# the commit: scripts/new-project.sh's template_ref and template_sha, the
# README's status line, the tutorial's example line, the summary check in
# tests/new-project-failpath.sh, the canary-template job's name in
# .github/workflows/ci.yml, and one `Changed` line in the changelog fragment
# changelog.d/template-pin.md (#1136), moved when an earlier raise since the
# release wrote one.
# Every edit is made in memory first: a place that is not found as expected
# changes no file.
#
# What it cannot write it prints: what the release brings (the CHANGELOG line
# and the pull request say it), the canary-template re-render, the lines still
# naming the old tag, and whether the next release owes the eval suite. That
# last answer is the one scripts/make-release.sh's run 1 reaches, read through
# the same scripts/lib/template-reads.sh: the template's diff from the tag the
# last release was tested with to the new tag.
#
# Raise once per plinth release, before cutting it, not once per template tag
# (docs/how-to/upgrade-the-template-pin.md).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
usage="usage: scripts/raise-template-pin.sh vA.B.C [<commit>]"
stop() { printf '%s\n' "$@" >&2; exit 1; }
# shellcheck source=scripts/lib/template-reads.sh
. "$root/scripts/lib/template-reads.sh"

tag="${1:-}"; want="${2:-}"
[ -n "$tag" ] || stop "$usage"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || stop "not a vX.Y.Z tag: $tag" "$usage"
[ -z "$want" ] || [[ "$want" =~ ^[0-9a-f]{7,40}$ ]] || stop "not a commit (7 to 40 lowercase hex characters): $want" "$usage"

door="$root/scripts/new-project.sh"
repo="$(sed -nE 's/^template_repo="([^"]+)"$/\1/p' "$door")"
old_ref="$(sed -nE 's/^template_ref="([^"]+)"$/\1/p' "$door")"
old_sha="$(sed -nE 's/^template_sha="([0-9a-f]{40})"$/\1/p' "$door")"
[ -n "$repo" ] && [ -n "$old_ref" ] && [ -n "$old_sha" ] \
  || stop "cannot read template_repo, template_ref and template_sha from scripts/new-project.sh"
name="${repo##*/}"
[ "$tag" != "$old_ref" ] || stop "scripts/new-project.sh already pins $name $tag"

# gh_read <what> <gh args...>: gh's answer, or a stop that tells a 404 (the
# thing is not there) from GitHub not answering.
gh_read() {
  local what="$1" out; shift
  if out="$(gh "$@" 2>&1)"; then printf '%s\n' "$out"; return 0; fi
  case "$out" in
    *"HTTP 404"*) stop "$repo has $what" ;;
    *) stop "cannot read $repo's $tag from GitHub: $out" ;;
  esac
}

# The tag's commit: a lightweight tag names it; an annotated one names a tag
# object that names it.
# Assigned before it is split: a stop inside $(...) ends only the subshell,
# and set -e ends the script on a failed assignment, not on a failed read.
named="$(gh_read "no tag $tag" api "repos/$repo/git/ref/tags/$tag" --jq '.object.type + " " + .object.sha')"
read -r type sha <<<"$named"
for _ in 1 2 3; do
  [ "$type" = tag ] || break
  named="$(gh_read "no tag object $sha" api "repos/$repo/git/tags/$sha" --jq '.object.type + " " + .object.sha')"
  read -r type sha <<<"$named"
done
[ "$type" = commit ] && [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || stop "$repo's tag $tag does not name a commit: $type $sha"
[ -z "$want" ] || [ "${sha#"$want"}" != "$sha" ] \
  || stop "$repo's tag $tag names $sha, not $want: the tag moved, or the commit given is another" \
          "  check which commit the template's checks passed on before pinning either"
draft="$(gh_read "no published release $tag (gh release view $tag --repo $repo)" api "repos/$repo/releases/tags/$tag" --jq .draft)"
[ "$draft" = false ] || stop "$repo has no published release $tag: it is a draft"

# The eval suite, as run 1 of the next release will ask it, read before any edit.
version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$root/.claude-plugin/plugin.json")"
tested="$(released_template_ref "$root/CHANGELOG.md" "$version" "$name")"
[ -n "$tested" ] || stop "CHANGELOG.md's [$version] section has no 'tested with $name <tag>' line," \
  "  which names the tag the next release's eval suite question starts from"
if [ "$tested" = "$tag" ]; then
  template_reads="" template_changed=""
else
  template_agent_reads "$repo" "$tested" "$tag" \
    || stop "cannot read what $repo changed from $tested to $tag: $template_reads_error"
fi

# The edits, all in memory, then written together.
python3 - "$root" "$repo" "$name" "$old_ref" "$old_sha" "$tag" "$sha" <<'PY'
import pathlib, re, sys
root, repo, name, old, old_sha, new, sha = sys.argv[1:8]
root = pathlib.Path(root)
edits = [
    ("scripts/new-project.sh", f'template_ref="{old}"', f'template_ref="{new}"'),
    ("scripts/new-project.sh", f'template_sha="{old_sha}"', f'template_sha="{sha}"'),
    ("README.md", f"[{name} {old}](https://github.com/{repo}/releases/tag/{old})",
                  f"[{name} {new}](https://github.com/{repo}/releases/tag/{new})"),
    ("docs/tutorials/getting-started.md", f" from {repo}@{old} in ", f" from {repo}@{new} in "),
    ("tests/new-project-failpath.sh", f" from {repo}@{old} in ", f" from {repo}@{new} in "),
    (".github/workflows/ci.yml", f"name: canary-template ({name} {old} at {old_sha[:7]})",
                                 f"name: canary-template ({name} {new} at {sha[:7]})"),
    (".github/workflows/ci-text.yml", f"name: canary-template ({name} {old} at {old_sha[:7]})",
                                      f"name: canary-template ({name} {new} at {sha[:7]})"),
]
texts, problems = {}, []
for path, before, after in edits:
    text = texts.setdefault(path, (root / path).read_text(encoding="utf-8"))
    n = text.count(before)
    if n != 1:
        problems.append(f"{path}: found {n} of {before!r}, not one")
        continue
    texts[path] = text.replace(before, after)

# The changelog line, in its own fragment (#1136): the line an earlier raise
# since the release wrote moves to the new tag; without the file, it is written.
path = "changelog.d/template-pin.md"
line = re.compile(r"^(- `/plinth:new-project` renders " + re.escape(name) + r" )v\d+\.\d+\.\d+", re.M)
if (root / path).exists():
    body = (root / path).read_text(encoding="utf-8")
    found = line.findall(body)
    if len(found) != 1:
        problems.append(f"{path}: {len(found)} lines saying what /plinth:new-project renders, not one")
    else:
        texts[path] = line.sub(lambda x: x[1] + new, body, count=1)
else:
    texts[path] = f"### Changed\n\n- `/plinth:new-project` renders {name} {new} instead of {old}.\n"

if problems:
    print("no file changed; these places are not as a pin raise expects:", *problems, sep="\n  ", file=sys.stderr)
    sys.exit(1)
for path, text in texts.items():
    (root / path).parent.mkdir(exist_ok=True)
    (root / path).write_text(text, encoding="utf-8")
PY

echo "raised the template pin: $name $old_ref (${old_sha:0:7}) -> $tag (${sha:0:7})"
echo "edited: scripts/new-project.sh, README.md, docs/tutorials/getting-started.md, tests/new-project-failpath.sh, .github/workflows/ci.yml, .github/workflows/ci-text.yml, changelog.d/template-pin.md"
from="the tag plinth $version was tested with"
if [ -n "$template_reads" ]; then
  echo "eval suite: owed at the next release: $name's diff from $tested ($from) to $tag changes what a new project's agent reads:"
  sed 's/^/  /' <<<"$template_reads"
  echo "  scripts/make-release.sh run 1 asks the why for 'eval suite: <link>' or 'eval suite not run: <why>' (docs/how-to/run-the-eval-suite.md)"
else
  echo "eval suite: not owed by this raise: $name's diff from $tested ($from) to $tag changes none of template/AGENTS.md.jinja, template/CLAUDE.md.jinja, template/.claude/"
fi
echo "still to do:"
echo "  1. tests/template-render.sh --write, to re-render canary-template/ at $tag; if the rendered ci.yml's ci job grants or passes something new, copy it into the canary-template job"
echo "     and copy template/Dockerfile.jinja's FROM lines at $tag into canary-web/Dockerfile, which tests/template-render.sh holds to them (#975)"
plinth_sha_note=""
grep -qx 'copier.yml' <<<"$template_changed" && plinth_sha_note=", and whether plinth_sha's default moved (copier.yml changed)"
echo "  2. changelog.d/template-pin.md: say what a project rendered at $tag receives (gh release view $tag --repo $repo)$plinth_sha_note"
if [ -d "$root/.git" ] || [ -f "$root/.git" ]; then
  left="$(git -C "$root" grep -n -F -e "$old_ref" -e "${old_sha:0:7}" -- ':!CHANGELOG.md' ':!changelog.d' ':!canary-template' || true)"
  if [ -n "$left" ]; then
    echo "  3. these lines still name $old_ref or ${old_sha:0:7}; change each, or keep it when it names the release a thing arrived in:"
    sed 's/^/     /' <<<"$left"
  fi
fi
echo "  then the checks in CONTRIBUTING.md, and a pull request titled 'chore(new-project): render $name $tag' saying what the release brings and the eval suite line above"
