#!/usr/bin/env bash
# Which pull requests pr-review.yml passes without summoning the reviewer, and
# which it goes on to look at (#167).
#
# The decision is a shell script inside the `run:` of pr-review.yml. It is
# lifted out of that file here and run with the env the step gives it, so what
# is tested is the workflow's own text and not a copy of the rule. Both
# directions: a test that only sees passes proves little. The cases that must
# NOT pass matter most here: the first version passed every `Bot` author, and
# coding agents are bots.
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
# The commit lists the step hands the gate, in the shape `pulls/N/commits` gives
# (measured on plinth#178 and plinth-template#17, 2026-09-17).
commits() {  # <file> <login:verified> ...
  python3 - "$@" <<'PY'
import json, sys
out = []
for spec in sys.argv[2:]:
    login, verified = spec.rsplit(":", 1)
    out.append({"author": {"login": login} if login else None,
                "commit": {"verification": {"verified": verified == "true"}}})
json.dump(out, open(sys.argv[1], "w"))
PY
}
commits "$tmp/dependabot.json" 'dependabot[bot]:true'
commits "$tmp/mixed.json"      'dependabot[bot]:true' 'coolbress:true'
commits "$tmp/unsigned.json"   'dependabot[bot]:false'
commits "$tmp/noauthor.json"   ':true'
commits "$tmp/empty.json"
echo 'null' > "$tmp/null.json"
printf '[{"author"' > "$tmp/broken.json"
python3 -c 'import json,sys; json.dump([{"author":{"login":"dependabot[bot]"},"commit":{"verification":{"verified":True}}}]*100, open(sys.argv[1],"w"))' "$tmp/fullpage.json"

gate() {  # <want: the printed reason, or "" for "go on and look"> <name> [VAR=value ...]
  local want="$1" name="$2"; shift 2
  local got rc
  got="$(env -i PATH="$PATH" DRAFT=false MERGED=false PR_STATE=open PASS_RELEASE=false \
           COMMITS_JSON="$tmp/dependabot.json" \
           AUTHOR_LOGIN=coolbress TITLE='fix(door): a title' "$@" bash "$tmp/gate.sh" 2>/dev/null)"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
    echo "  PASS  $name"
  else
    echo "  FAIL  $name: exit $rc, printed '$got', wanted '$want'" >&2; fails=$((fails+1))
  fi
}

BOT='Dependabot pull request: not summoned'
REL='release pull request: not summoned'

gate '' "a person's pull request goes on to the reviewer"
gate 'draft pull request: not reviewed until it is marked ready for review.' 'a draft passes without summoning' DRAFT=true
gate 'pull request already merged or closed: not waiting.' 'a merged pull request passes' MERGED=true
gate 'pull request already merged or closed: not waiting.' 'a closed pull request passes' PR_STATE=closed

# Dependabot, in the three spellings GitHub uses for the one account.
gate "$BOT" 'login dependabot[bot]'  'AUTHOR_LOGIN=dependabot[bot]'
gate "$BOT" 'login app/dependabot'   AUTHOR_LOGIN=app/dependabot
gate "$BOT" 'login dependabot'       AUTHOR_LOGIN=dependabot
gate "$BOT" 'login Dependabot[Bot] in another case' 'AUTHOR_LOGIN=Dependabot[Bot]'
# Every other bot is looked at: coding agents are bots, and their pull requests
# are code (#167, corrected 2026-09-18). Logins as GitHub reports them.
for agent in 'Copilot' 'cursor[bot]' 'claude[bot]' 'devin-ai-integration[bot]' 'google-labs-jules[bot]' 'renovate[bot]' 'github-actions[bot]' 'app/copilot-swe-agent'; do
  gate '' "a pull request by $agent is summoned" "AUTHOR_LOGIN=$agent"
done
gate ''     'a person whose login only contains "bot" is summoned' AUTHOR_LOGIN=robotnik
gate ''     'a person whose login starts with "dependabot" is summoned' AUTHOR_LOGIN=dependabot-fan
gate ''     'a login that ends with the name is summoned' 'AUTHOR_LOGIN=not-dependabot[bot]'
# The author stays Dependabot when someone else pushes to the branch, so the
# commits decide; anything the gate cannot read as "only Dependabot" goes on.
gate ''     "Dependabot's pull request with a person's commit is summoned" 'AUTHOR_LOGIN=dependabot[bot]' COMMITS_JSON="$tmp/mixed.json"
gate ''     'an unverified commit under its name is summoned'  'AUTHOR_LOGIN=dependabot[bot]' COMMITS_JSON="$tmp/unsigned.json"
gate ''     'a commit with no GitHub author is summoned'       'AUTHOR_LOGIN=dependabot[bot]' COMMITS_JSON="$tmp/noauthor.json"
gate ''     'an empty commit list is summoned'                 'AUTHOR_LOGIN=dependabot[bot]' COMMITS_JSON="$tmp/empty.json"
gate ''     'a failed commits call (null) is summoned'         'AUTHOR_LOGIN=dependabot[bot]' COMMITS_JSON="$tmp/null.json"
gate ''     'a truncated commit list is summoned'              'AUTHOR_LOGIN=dependabot[bot]' COMMITS_JSON="$tmp/broken.json"
gate ''     'a missing commit list is summoned'                'AUTHOR_LOGIN=dependabot[bot]' COMMITS_JSON="$tmp/absent.json"
gate ''     'no commit list at all is summoned'                'AUTHOR_LOGIN=dependabot[bot]' COMMITS_JSON=
gate ''     'a full page of commits is summoned: more may follow' 'AUTHOR_LOGIN=dependabot[bot]' COMMITS_JSON="$tmp/fullpage.json"

# The title scripts/make-release.sh writes, and two that only resemble it.
gate "$REL" 'chore(release): v0.5.12 passes where the caller turned it on' PASS_RELEASE=true 'TITLE=chore(release): v0.5.12'
gate ''     'the same title is summoned where the caller did not'          'TITLE=chore(release): v0.5.12'
gate ''     'the same title is summoned when the input is anything but true' PASS_RELEASE=yes 'TITLE=chore(release): v0.5.12'
gate ''     'chore(release-notes): … is summoned'       PASS_RELEASE=true 'TITLE=chore(release-notes): v0.5.12 wording'
gate ''     'chore: release the lock is summoned'       PASS_RELEASE=true 'TITLE=chore: release the lock'
gate ''     'a title that mentions the release title later is summoned' PASS_RELEASE=true 'TITLE=docs: what chore(release): v1 means'
gate ''     'chore(release): without a version is summoned' PASS_RELEASE=true 'TITLE=chore(release): notes'
gate ''     'a version followed by more words is summoned' PASS_RELEASE=true 'TITLE=chore(release): v2 docs only'
gate ''     'a version with a suffix is summoned'          PASS_RELEASE=true 'TITLE=chore(release): v1.2.3-not-a-release'
gate ''     'a two-part version is summoned'               PASS_RELEASE=true 'TITLE=chore(release): v1.2'
# The tag shape here is the one make-release.sh accepts.
if grep -qF '[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]' "$root/scripts/make-release.sh"; then
  echo "  PASS  make-release.sh still accepts only vX.Y.Z"
else
  echo "  FAIL  make-release.sh's tag check changed; the gate's pattern may be stale" >&2; fails=$((fails+1))
fi
# A title is text its author chooses: it must stay data.
gate ''     'a title with shell syntax is not run' PASS_RELEASE=true 'TITLE=$(touch '"$tmp"'/pwned) `touch '"$tmp"'/pwned`; chore(release): v1'
if [ -e "$tmp/pwned" ]; then echo "  FAIL  the title was executed" >&2; fails=$((fails+1)); else echo "  PASS  the title stayed data"; fi
# A draft from a bot says draft: the order of the reasons is part of the text.
gate 'draft pull request: not reviewed until it is marked ready for review.' "Dependabot's draft reports draft" DRAFT=true 'AUTHOR_LOGIN=dependabot[bot]'

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
echo "-- passes without summoning: draft, merged or closed, Dependabot's own commits, a release title where asked; everything else goes on"
