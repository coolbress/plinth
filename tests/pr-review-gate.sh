#!/usr/bin/env bash
# Which pull requests pr-review.yml passes without summoning the reviewer, and
# which it goes on to look at (#167).
#
# The decision is a shell script inside the `run:` of pr-review.yml. It is
# lifted out of that file here and run with the env the step gives it, so what
# is tested is the workflow's own text and not a copy of the rule. Both
# directions: a test that only sees passes proves little.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="$root/.github/workflows/pr-review.yml"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

python3 - "$wf" "$tmp/gate.sh" <<'PY'
import sys, pathlib, textwrap
lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
start = next(i for i, ln in enumerate(lines) if ln.rstrip().endswith("<<'SH'"))
end = next(i for i in range(start + 1, len(lines)) if lines[i].strip() == "SH")
body = textwrap.dedent("\n".join(lines[start + 1:end]))
assert "not summoned" in body and "draft pull request" in body, "gate snippet not found; the workflow changed shape"
pathlib.Path(sys.argv[2]).write_text(body + "\n")
PY
[ -s "$tmp/gate.sh" ] || { echo "  FAIL  could not extract the gate snippet" >&2; exit 1; }

fails=0
gate() {  # <want: the printed reason, or "" for "go on and look"> <name> [VAR=value ...]
  local want="$1" name="$2"; shift 2
  local got rc
  got="$(env -i PATH="$PATH" DRAFT=false MERGED=false PR_STATE=open \
           AUTHOR_LOGIN=coolbress AUTHOR_TYPE=User TITLE='fix(door): a title' "$@" bash "$tmp/gate.sh" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
    echo "  PASS  $name"
  else
    echo "  FAIL  $name: exit $rc, printed '$got', wanted '$want'" >&2; fails=$((fails+1))
  fi
}

BOT='bot-authored pull request: not summoned'
REL='release pull request: not summoned'

gate '' "a person's pull request goes on to the reviewer"
gate 'draft pull request: not reviewed until it is marked ready for review.' 'a draft passes without summoning' DRAFT=true
gate 'pull request already merged or closed: not waiting.' 'a merged pull request passes' MERGED=true
gate 'pull request already merged or closed: not waiting.' 'a closed pull request passes' PR_STATE=closed

# The three spellings GitHub uses for one bot account, each without the type,
# so the login rule is what decides; then the type alone.
gate "$BOT" 'login dependabot[bot], no type'  'AUTHOR_LOGIN=dependabot[bot]' AUTHOR_TYPE=
gate "$BOT" 'login app/dependabot, no type'   AUTHOR_LOGIN=app/dependabot AUTHOR_TYPE=
gate "$BOT" 'login dependabot, no type'       AUTHOR_LOGIN=dependabot AUTHOR_TYPE=
gate "$BOT" 'login Dependabot[bot] in another case' 'AUTHOR_LOGIN=Dependabot[Bot]' AUTHOR_TYPE=
gate "$BOT" 'type Bot with a login that does not say so' AUTHOR_LOGIN=some-app AUTHOR_TYPE=Bot
gate ''     'a person whose login only contains "bot" is summoned' AUTHOR_LOGIN=robotnik AUTHOR_TYPE=User
gate ''     'a person whose login starts with "dependabot" is summoned' AUTHOR_LOGIN=dependabot-fan AUTHOR_TYPE=User

# The title scripts/make-release.sh writes, and two that only resemble it.
gate "$REL" 'chore(release): v0.5.12 passes'            'TITLE=chore(release): v0.5.12'
gate ''     'chore(release-notes): … is summoned'       'TITLE=chore(release-notes): v0.5.12 wording'
gate ''     'chore: release the lock is summoned'       'TITLE=chore: release the lock'
gate ''     'a title that mentions the release title later is summoned' 'TITLE=docs: what chore(release): v1 means'
gate ''     'chore(release): without a version is summoned' 'TITLE=chore(release): notes'
gate ''     'a version followed by more words is summoned' 'TITLE=chore(release): v2 docs only'
gate ''     'a version with a suffix is summoned'          'TITLE=chore(release): v1.2.3-not-a-release'
gate ''     'a two-part version is summoned'               'TITLE=chore(release): v1.2'
# The tag shape here is the one make-release.sh accepts.
if grep -qF '[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]' "$root/scripts/make-release.sh"; then
  echo "  PASS  make-release.sh still accepts only vX.Y.Z"
else
  echo "  FAIL  make-release.sh's tag check changed; the gate's pattern may be stale" >&2; fails=$((fails+1))
fi
# A title is text its author chooses: it must stay data.
gate ''     'a title with shell syntax is not run' 'TITLE=$(touch '"$tmp"'/pwned) `touch '"$tmp"'/pwned`; chore(release): v1'
if [ -e "$tmp/pwned" ]; then echo "  FAIL  the title was executed" >&2; fails=$((fails+1)); else echo "  PASS  the title stayed data"; fi
# A draft from a bot says draft: the order of the reasons is part of the text.
gate 'draft pull request: not reviewed until it is marked ready for review.' 'a bot draft reports draft' DRAFT=true AUTHOR_TYPE=Bot

# The release title here is the one make-release.sh writes.
if grep -qF 'git commit -q -m "chore(release): $tag"' "$root/scripts/make-release.sh"; then
  echo "  PASS  make-release.sh still writes chore(release): <tag>"
else
  echo "  FAIL  make-release.sh no longer writes 'chore(release): \$tag'; the gate's pattern is stale" >&2; fails=$((fails+1))
fi
# Title and author reach the script through env:, never ${{ }} inside run:.
if python3 - "$wf" <<'PY'
import re, sys, pathlib
text = pathlib.Path(sys.argv[1]).read_text()
bad = []
for block in re.findall(r"\n\s+run: \|\n((?:\s{10,}.*\n|\s*\n)+)", text):
    for m in re.finditer(r"\$\{\{[^}]*\}\}", block):
        bad.append(m.group(0))
sys.exit(1 if bad else 0)
PY
then echo "  PASS  no \${{ }} inside a run: block of pr-review.yml"
else echo "  FAIL  a run: block of pr-review.yml interpolates \${{ }}" >&2; fails=$((fails+1)); fi

if [ "$fails" -ne 0 ]; then
  echo "-- $fails failed" >&2
  exit 1
fi
echo "-- passes without summoning: draft, merged or closed, bot-authored, release title; everything else goes on"
