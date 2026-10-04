#!/usr/bin/env bash
# Pass without summoning, or go on? Run by the second step of
# .github/workflows/pr-review.yml with that step's env (DRAFT, MERGED,
# PR_STATE, AUTHOR_LOGIN, HEAD_SHA, TITLE, PASS_RELEASE) plus ACTIVITY_JSON,
# the pushes to the head branch, and FILES_JSON, the changed files, read only
# for a release title. It prints the reason when the check passes
# here and nothing when the reviewer is to be looked for.
# tests/pr-review-gate.sh runs this file.
set -euo pipefail
# Drafts are never summoned; a ready head must show its own evidence,
# and summonses per commit are limited (two, in the workflow). This check asks
# "was this commit reviewed", so it used to re-run on every push: 29
# runs on one pull request, 76 in a day, new heads queueing behind old
# 900-second waits. Fix locally while draft, verify here once ready.
# GitHub blocks merging a draft anyway.
if [ "${DRAFT:-false}" = "true" ]; then
  echo "draft pull request: not reviewed until it is marked ready for review."
  exit 0
fi
if [ "${MERGED:-false}" = "true" ] || [ "${PR_STATE:-open}" != "open" ]; then
  echo "pull request already merged or closed: not waiting."
  exit 0
fi
# Dependabot's pull requests (#167), by name and nothing wider. The
# first version passed every author of type `Bot`; coding agents are
# `Bot` too (`cursor[bot]`, `claude[bot]`, `devin-ai-integration[bot]`)
# and their pull requests are code, the ones a review is for. The three
# spellings GitHub uses for the one account: `dependabot[bot]` in the
# payload (measured on plinth#178), `app/dependabot` in gh, and
# `dependabot` as an actor. To have one reviewed, comment the summons
# on it yourself.
#
# The author of a pull request does not change when someone else
# pushes to its branch (measured on plinth-template#17: author
# `dependabot[bot]`, second commit a person's), and a commit's author
# is whatever its writer typed: a commit signed by anyone, with
# Dependabot's address as the author, reads `author.login:
# dependabot[bot]`, `verified: true`. What cannot be typed is who
# pushed. The repository's activity log names the authenticated
# account behind every push to the branch, so: every push to this
# branch is Dependabot's, and the newest one is this head. A log that
# is missing, unreadable, empty, a full page (more may follow) or not
# yet at this head counts as "not only Dependabot".
login="$(printf '%s' "${AUTHOR_LOGIN:-}" | tr '[:upper:]' '[:lower:]')"
case "$login" in
  'dependabot[bot]'|app/dependabot|dependabot)
    if python3 - "${ACTIVITY_JSON:-}" "${HEAD_SHA:-}" <<'PYGATE'
import json, sys
try:
    pushes = json.load(open(sys.argv[1]))
    head = sys.argv[2]
    ok = (isinstance(pushes, list) and 0 < len(pushes) < 100 and len(head) == 40
          and pushes[0].get("after") == head          # newest first
          and all((p.get("actor") or {}).get("login") == "dependabot[bot]" for p in pushes))
except Exception:
    ok = False
sys.exit(0 if ok else 1)
PYGATE
    then
      echo "Dependabot pull request: not summoned"
      exit 0
    fi
    echo "Dependabot pull request, but not every push to its branch is Dependabot's: looked at like any other" >&2 ;;
esac
# A release pull request, only where the caller turned it on: the
# title scripts/make-release.sh writes, whole, with the only tag shape
# it accepts, and the diff its run 1 writes (#384). The author chooses
# the title, so the title alone passed any pull request that took it;
# the diff is checked too: exactly the two manifests and CHANGELOG.md,
# modified; in each manifest its one `"version"` line replaced by the
# title's version, a higher one; in CHANGELOG.md lines added, the `[Unreleased]` link aside.
# FILES_JSON is `pulls/:n/files`; one that is missing, unreadable, a full
# page or lacks a patch counts as "not a release's diff". What this does
# not cover: the release note's own text.
if [ "${PASS_RELEASE:-false}" = "true" ] \
   && printf '%s' "${TITLE:-}" | grep -Eq '^chore\(release\): v[0-9]+\.[0-9]+\.[0-9]+$'; then
  if python3 - "${FILES_JSON:-}" "${TITLE#chore(release): v}" <<'PYREL'
import json, re, sys
manifests = {".claude-plugin/plugin.json", ".claude-plugin/marketplace.json"}
want = manifests | {"CHANGELOG.md"}
def why():
    try:
        files = json.load(open(sys.argv[1]))
    except Exception:
        return "the changed files could not be read"
    version = sys.argv[2]
    if not isinstance(files, list):
        return "the changed files could not be read"
    if len(files) >= 100:
        return "the changed files fill a page; more may follow"
    names = {f.get("filename") for f in files if isinstance(f, dict)}
    if names != want or len(files) != len(want):
        extra, missing = sorted(map(str, names - want)), sorted(want - names)
        return "changed files are not the release's three" + \
            (f"; also {', '.join(extra)}" if extra else "") + (f"; missing {', '.join(missing)}" if missing else "")
    ver = re.compile(r'^[+-]\s*"version":\s*"[0-9]+\.[0-9]+\.[0-9]+",?\s*$')
    for f in files:
        name, patch = f["filename"], f.get("patch")
        if f.get("status") != "modified" or not isinstance(patch, str):
            return f"{name} is not a plain modification with a patch"
        lines = [l for l in patch.split("\n") if l[:1] in "+-" and l]
        if name in manifests:
            # One version line out, one in: an added line beside the old one
            # would leave two `"version"` keys, read differently by parsers.
            added = [l for l in lines if l.startswith("+")]
            removed = [l for l in lines if l.startswith("-")]
            if not all(ver.match(l) for l in lines) or len(added) != 1 \
               or len(removed) != 1 or f'"{version}"' not in added[0]:
                return f"{name} does not replace its one version line with {version}"
            # Forward only, as make-release.sh moves it.
            num = lambda l: tuple(int(x) for x in re.findall(r"[0-9]+", l.split(":", 1)[1]))
            if num(added[0]) <= num(removed[0]):
                return f"{name} does not move its version forward to {version}"
        elif any(l.startswith("-") and not l.startswith("-[Unreleased]: ") for l in lines):
            return "CHANGELOG.md removes a line other than the [Unreleased] link"
    return ""
reason = why()
if reason:
    print(f"release title, but not a release's diff: {reason}; looked at like any other", file=sys.stderr)
sys.exit(1 if reason else 0)
PYREL
  then
    echo "release pull request: not summoned"
    exit 0
  fi
fi
