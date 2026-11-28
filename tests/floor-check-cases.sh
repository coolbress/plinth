#!/usr/bin/env bash
# The floor checker's verdicts on fixtures, offline: a complete backend
# instance passes, and each planted defect is named. A checker that cannot
# fail is not a check.
# shellcheck disable=SC2034  # the rules_* fixtures are used inside wall() command strings
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root/scripts/floor-check.py"
# #219 reads scripts/new-project.sh beside the checker (the real one here, not
# a fixture): captured once so the fixtures stay a PASS across a pin raise.
target_ref="$(sed -nE 's/^template_ref="([^"]+)"$/\1/p' "$root/scripts/new-project.sh")"
target_sha="$(sed -nE 's/^template_sha="([^"]+)"$/\1/p' "$root/scripts/new-project.sh")"
# The short list's template sources are read at the pin (#969).
# shellcheck source=tests/lib/template-checkout.sh
. "$root/tests/lib/template-checkout.sh"
work="$(mktemp -d)" || { echo "floor-check-cases: could not make a temp folder" >&2; exit 1; }; trap 'rm -rf "$work"' EXIT
# Each fixture directory tag_names makes also answers that the target tag was
# tested with the plinth the fixtures call, all zeros (#511), so the update
# line is not held for the pin (#1183), unless a case wrote another first.
tested_is() { # <fixture dir> <plinth_sha default>: the target tag's copier.yml
  mkdir -p "$1/repos/coolbress/plinth-template/contents"
  printf 'plinth_sha:\n  type: str\n  default: "%s"\n' "$2" | base64 | tr -d '\n' | jq -R '{encoding: "base64", content: .}' \
    > "$1/repos/coolbress/plinth-template/contents/copier.yml?ref=$target_sha.json"
}
tag_names() { # <fixture dir> <commit>: what the target tag names on GitHub (#519)
  mkdir -p "$1/repos/coolbress/plinth-template/commits"
  printf '{"sha":"%s"}\n' "$2" > "$1/repos/coolbress/plinth-template/commits/$target_ref.json"
  [ -e "$1/repos/coolbress/plinth-template/contents/copier.yml?ref=$target_sha.json" ] || tested_is "$1" "$(printf '%040d' 0)"
}
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
# A case names the check it expects and the state that check reports (#1103):
# `FC-… <state>`, not a sentence, so a wording change breaks only the golden
# files (tests/floor-check-golden.sh), which hold every line byte for byte.
# The checker's trace pairs each line it prints with its id and state.
export FLOOR_CHECK_TRACE="$work/emitted"; : > "$FLOOR_CHECK_TRACE"
# A line two checks print alike is credited to neither: the trace holds every
# run so far, so it cannot say which printed it here (a case names its text).
states() { # <output>: the `<id> <state>` of each of its lines
  awk -F'\t' 'NR==FNR { if (NF > 1) m[$2] = ($2 in m && m[$2] != $1) ? "?" : $1; next }
               ($0 in m) && m[$0] != "?" { print m[$0] }' "$FLOOR_CHECK_TRACE" - <<<"$1"
}
reports() { states "$1" | grep -qxF -- "$2"; }   # <output> <`<id> <state>`>: that check reported that state in it
is() { reports "$1" "$2 $3"; }                    # <output> <id> <state>
sees() { # <output> <expectation> <grep options and pattern>: by id and state when the expectation is `FC-… <state>`, else the pattern
  local o="$1" e="$2"; shift 2
  case "$e" in FC-[A-Z][0-9][0-9]\ [a-z]*) reports "$o" "$e" ;; *) grep -q "$@" <<<"$o" ;; esac
}

good="$work/good"; mkdir -p "$good/.github/ISSUE_TEMPLATE" "$good/.claude" "$good/src/app"
cat > "$good/CONTRIBUTING.md" <<'MD'
# Contributing
Run the checks with `uv sync` and `uv run pytest`.
Open a pull request against main; squash is the only merge method.
Line 4
Line 5
Line 6
Line 7
Line 8
Line 9
Line 10
MD
printf 'MIT\n' > "$good/LICENSE"; printf '# app\n\nSee [CONTRIBUTING](CONTRIBUTING.md).\n' > "$good/README.md"
printf '# Changelog\n' > "$good/CHANGELOG.md"; printf '# Agents\n' > "$good/AGENTS.md"; printf '# Security\n' > "$good/SECURITY.md"
printf 'version: 2\n' > "$good/.github/dependabot.yml"
for f in bug feature task; do printf 'name: %s\ndescription: "x"\nlabels: ["%s"]\nbody: []\n' "$f" "$f" > "$good/.github/ISSUE_TEMPLATE/$f.yml"; done
printf '* text=auto eol=lf\nuv.lock linguist-generated\n' > "$good/.gitattributes"
cat > "$good/.claude/settings.json" <<'JSON'
{"permissions":{"deny":["Bash(git push --force:*)","Bash(git push -f:*)","Bash(git push *--force*)","Bash(git push * -f)","Bash(git push * -f *)","Bash(git push *+*)","Bash(git * push *--force*)","Bash(git * push -f)","Bash(git * push -f *)","Bash(git * push * -f)","Bash(git * push * -f *)","Bash(git * push *+*)","Bash(rm -rf:*)","Bash(gh auth token*)","Read(./.env)","Bash(. *.env*)","Bash(source *.env*)","Bash(cat *.env)","Bash(grep *.env)","Read(~/.config/gh/**)"]}}
JSON
printf '[project]\nname = "app"\n' > "$good/pyproject.toml"; : > "$good/uv.lock"
printf 'archetype: backend\n_src_path: gh:coolbress/plinth-template\n_commit: %s\n' "$target_ref" > "$good/.copier-answers.yml"
cat > "$good/src/app/__main__.py" <<'PYSRC'
import json, logging, os
os.environ["APP_PORT"]
class JsonFormatter(logging.Formatter):
    def format(self, record):
        return json.dumps({"message": record.getMessage()})
PYSRC
printf 'APP_PORT=8000\n' > "$good/.env.example"
printf 'FROM python:3.12-slim@sha256:%064d\nRUN uv sync --locked\nUSER app\nCMD ["python", "-m", "app"]\n' 0 > "$good/Dockerfile"
printf '.git\n.env\n.venv\n' > "$good/.dockerignore"
mkdir -p "$good/.github/workflows"
printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%040d\n  image:\n    steps:\n      - run: docker build -t t .\n      - run: docker run --rm t\n' 0 > "$good/.github/workflows/ci.yml"
# A backend publishes its image on a version tag (plinth-template 1.30.0, #706).
printf 'name: Release\non:\n  push:\n    tags: ["v*"]\npermissions: {}\njobs:\n  image:\n    steps:\n      - run: docker push "ghcr.io/$GITHUB_REPOSITORY:${GITHUB_REF_NAME#v}"\n' > "$good/.github/workflows/release.yml"
# Tracked-file evidence needs an index, so the fixture is a git work tree (#95).
git -C "$good" init -q 2>/dev/null && git -C "$good" add -A

out="$(python3 "$checker" --root "$good" --no-network 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q -- '-- 0 failed' <<<"$out"; then ok "complete backend instance passes offline"
else bad "complete backend instance should pass:"; printf '%s\n' "$out" | grep -E 'FAIL' | sed 's/^/        /'; fi

# Exit 0 with the wall unchecked is not "the floor is intact". The summary
# counts what was not verified, as SKIP lines, and the exit code stays 0 so a
# consumer CI that treats 0 as pass keeps working (#119).
skips() { # <description> <expected summary tail> <checker args...>
  local desc="$1" want="$2"; shift 2
  local out; out="$(python3 "$checker" "$@" 2>&1)"; local rc=$?
  local n; n="$(grep -c '^  SKIP ' <<<"$out")"
  if [ "$rc" = 0 ] && grep -q -- "-- 0 failed, $want" <<<"$out" && [ "$n" = "${want%% *}" ]; then ok "$desc"
  else bad "$desc (rc=$rc, SKIP lines=$n, expected '-- 0 failed, $want')"; printf '%s\n' "$out" | grep -E 'SKIP|INFO|failed' | sed 's/^/        /'; fi
}
skips "offline with --repo: the wall and the labels are counted as not verified, exit stays 0" \
  "2 not verified" --root "$good" --repo o/r --no-network
# A read that did not happen is one the person can make: plain not verified,
# with no count of SKIPs that cannot be read here (#1002).
out="$(python3 "$checker" --root "$good" --repo o/r --no-network 2>&1)"
if grep -q -- '^-- 0 failed, 2 not verified$' <<<"$out" && ! grep -q 'cannot be read here' <<<"$out"
then ok "offline: a failed read is plain not verified, not counted as unreadable here"
else bad "offline read marked unreadable"; grep -E 'SKIP|failed' <<<"$out" | sed 's/^/        /'; fi
skips "offline without --repo: the unchecked wall is counted once" \
  "1 not verified" --root "$good" --no-network
noarch="$work/noarch"; rm -rf "$noarch"; cp -R "$good" "$noarch"; rm "$noarch/.copier-answers.yml"
skips "no archetype: the skipped conditional items are counted (and template drift, which also reads .copier-answers.yml)" \
  "3 not verified" --root "$noarch" --no-network

# Planted defects, each must be named.
plant() { # <description> <shell to break the copy> <`<id> fail` expected>
  local copy="$work/case"; rm -rf "$copy"; cp -R "$good" "$copy"
  ( cd "$copy" && eval "$2" )
  local out; out="$(python3 "$checker" --root "$copy" --no-network 2>&1)"
  if [ "$3" = "__none__" ]; then
    if grep -q -- '-- 0 failed' <<<"$out"; then ok "$1"; else bad "$1 (should not fail)"; printf '%s\n' "$out" | grep FAIL | sed 's/^/        /'; fi
    return
  fi
  if reports "$out" "$3"; then ok "$1"; else bad "$1 (expected $3)"; printf '%s\n' "$out" | grep FAIL | sed 's/^/        /'; fi
}
infos() { # <description> <shell to break the copy> <`<id> <state>` expected>
  local copy="$work/case"; rm -rf "$copy"; cp -R "$good" "$copy"
  ( cd "$copy" && eval "$2" )
  local out; out="$(python3 "$checker" --root "$copy" --no-network 2>&1)"
  if reports "$out" "$3"; then ok "$1"; else bad "$1 (expected $3)"; printf '%s\n' "$out" | grep -E 'INFO|SKIP|FAIL' | sed 's/^/        /'; fi
}
warns() { # <description> <shell to break the copy> <`<id> warn` expected>
  local copy="$work/case"; rm -rf "$copy"; cp -R "$good" "$copy"
  ( cd "$copy" && eval "$2" )
  local out; out="$(python3 "$checker" --root "$copy" --no-network 2>&1)"
  if reports "$out" "$3"; then ok "$1"; else bad "$1 (expected $3)"; printf '%s\n' "$out" | grep -E 'WARN|FAIL' | sed 's/^/        /'; fi
}
plant "stub CONTRIBUTING is caught" "printf '# Contributing\nSee the wiki.\n' > CONTRIBUTING.md" "FC-A06 fail"
plant "unpinned base image is caught" "sed -i.bak 's/@sha256:[0-9a-f]*//' Dockerfile" "FC-C20 fail"
plant "root user is caught" "sed -i.bak 's/^USER app/USER root/' Dockerfile" "FC-C21 fail"
plant "undocumented env var is caught" "printf 'x\n' > .env.example" "FC-C28 fail"
plant "missing token deny is caught" "printf '{\"permissions\":{\"deny\":[]}}' > .claude/settings.json" "FC-B05 fail"
plant "a Read-only .env deny is caught" "sed -i.bak 's/\"Bash(\. \*\.env\*)\",\"Bash(source \*\.env\*)\",//' .claude/settings.json" "FC-B07 fail"
plant "a sourcing deny without its closing parenthesis is caught" "sed -i.bak 's/\"Bash(source \*\.env\*)\"/\"Bash(source .env*\"/' .claude/settings.json" "FC-B08 fail"
plant "a sourcing deny spelt with a ? is caught: only * is a wildcard" "sed -i.bak 's/\"Bash(source \*\.env\*)\"/\"Bash(source .en?)\"/' .claude/settings.json" "FC-B08 fail"
plant "a settings without the cat rule is caught" "sed -i.bak 's/\"Bash(cat \*\.env)\",//' .claude/settings.json" "FC-B09 fail"
plant "a grep rule that names only .env.example is caught" "sed -i.bak 's/\"Bash(grep \*\.env)\"/\"Bash(grep *.env.example)\"/' .claude/settings.json" "FC-B10 fail"
plant "a sourcing deny that names only .env.local is caught" "sed -i.bak 's/\"Bash(source \*\.env\*)\"/\"Bash(source *.env.local*)\"/' .claude/settings.json" "FC-B08 fail"
# The force-push item names the spellings it found denied (#942): the
# template's rules pass, the two old rules alone warn with the lines to add,
# and neither of those two is still a FAIL.
fp_out() { local copy="$work/case"; rm -rf "$copy"; cp -R "$good" "$copy"; ( cd "$copy" && eval "$1" ); python3 "$checker" --root "$copy" --no-network 2>&1; }
out="$(fp_out :)"
if is "$out" FC-B03 pass; then ok "the template's force-push rules pass, naming each spelling (#942)"
else bad "the template's force-push rules should pass naming each spelling"; grep 'force push' <<<"$out" | sed 's/^/        /'; fi
only_two="python3 -c 'import json; p=\".claude/settings.json\"; j=json.load(open(p)); d=j[\"permissions\"][\"deny\"]; j[\"permissions\"][\"deny\"]=[\"Bash(git push --force:*)\",\"Bash(git push -f:*)\"]+[x for x in d if \"push\" not in x]; json.dump(j,open(p,\"w\"))'"
out="$(fp_out "$only_two")"
if is "$out" FC-B03 warn \
  && is "$out" FC-B03 info \
  && grep -q -- '-- 0 failed' <<<"$out"; then ok "the two old force-push rules alone are a WARN with the rules to add (#942)"
else bad "the two old force-push rules alone should WARN with the rules to add"; grep -E 'force push|add to' <<<"$out" | sed 's/^/        /'; fi
# A trailing ` *` matches the bare command only as a rule's one wildcard:
# `Bash(git push * -f *)` leaves `git push origin b -f` open (#946 review).
no_end_f="python3 -c 'import json; p=\".claude/settings.json\"; j=json.load(open(p)); j[\"permissions\"][\"deny\"]=[x for x in j[\"permissions\"][\"deny\"] if x not in (\"Bash(git push * -f)\",\"Bash(git * push -f)\",\"Bash(git * push * -f)\")]; json.dump(j,open(p,\"w\"))'"
out="$(fp_out "$no_end_f")"
if is "$out" FC-B03 warn \
  && is "$out" FC-B03 info; then ok "a rule ending \` -f *\` does not stand in for one ending \` -f\`: a WARN naming the three (#946)"
else bad "rules ending \` -f *\` alone should WARN for a trailing -f"; grep -E 'force push|add to' <<<"$out" | sed 's/^/        /'; fi
plant "no force-push rule at all fails" "python3 -c 'import json; p=\".claude/settings.json\"; j=json.load(open(p)); j[\"permissions\"][\"deny\"]=[x for x in j[\"permissions\"][\"deny\"] if \"push\" not in x]; json.dump(j,open(p,\"w\"))'" "FC-B03 fail"
plant "a deny of --force-with-lease alone is not the floor" "python3 -c 'import json; p=\".claude/settings.json\"; j=json.load(open(p)); j[\"permissions\"][\"deny\"]=[\"Bash(git push --force-with-lease)\"]+[x for x in j[\"permissions\"][\"deny\"] if \"push\" not in x]; json.dump(j,open(p,\"w\"))'" "FC-B03 fail"
plant "broken doc link is caught" "printf '[x](nope.md)\n' >> README.md" "FC-A27 fail"
# A *.md symbolic link whose target is missing was read like a file and
# crashed the checker before any verdict (#525). It is a FAIL naming the link
# and its target, every other item is still reported, and a link to a file
# that exists is read through it.
plant "a dangling *.md link is a FAIL naming the link and its target (#525)" "ln -s MISSING.md CLAUDE.md" "FC-A27 fail"
plant "a *.md link to an existing file is read through it" "ln -s README.md NOTES.md" "__none__"
dl="$work/dangling"; rm -rf "$dl"; cp -R "$good" "$dl"; ln -s MISSING.md "$dl/CLAUDE.md"
out="$(python3 "$checker" --root "$dl" --no-network --verdicts "$dl.verdicts" 2>&1)"; rc=$?
if [ "$rc" = 1 ] && [ -s "$dl.verdicts" ] && ! grep -q Traceback <<<"$out" && is "$out" FC-A01 pass \
  && grep -q -- '-- 1 failed' <<<"$out"; then ok "a dangling *.md link still writes the verdicts and reports the other items"
else bad "a dangling *.md link stops the checker (rc=$rc, verdicts $( [ -s "$dl.verdicts" ] && echo written || echo missing ))"; printf '%s\n' "$out" | grep -E 'Traceback|Error|FAIL|failed' | sed 's/^/        /'; fi
# A proprietary notice grants nothing and is still the LICENSE item (#995):
# the item asks that the file is there, not what it grants. The text is
# plinth-template v1.48.0's for license=Proprietary.
pr="$work/proprietary"; rm -rf "$pr"; cp -R "$good" "$pr"
printf '%s\n' 'Copyright (c) 2026 tester. All rights reserved.' '' \
  'This software and its source code are proprietary and confidential. No' \
  'license or right to use, copy, modify, merge, publish, distribute,' \
  'sublicense or sell it is granted to anyone, except by written permission of' \
  'the copyright holder.' > "$pr/LICENSE"
out="$(python3 "$checker" --root "$pr" --no-network 2>&1)"
if is "$out" FC-A01 pass && grep -q -- '-- 0 failed' <<<"$out"; then ok "a proprietary notice passes the LICENSE item"
else bad "a proprietary notice does not pass the LICENSE item"; grep -E 'LICENSE|FAIL' <<<"$out" | sed 's/^/        /'; fi
# Three failing states no other case reached (#1103: every state a check
# declares is reached by a fixture).
plant "uv.lock not folded in diffs is caught" "printf '* text=auto eol=lf\n' > .gitattributes" "FC-A25 fail"
plant "a .gitattributes driver that needs local git config is caught" \
  "printf '* text=auto eol=lf\nuv.lock linguist-generated\n*.py diff=mine\n' > .gitattributes" "FC-A26 fail"
plant ".claude/settings.json that is not JSON is caught" "printf '{' > .claude/settings.json" "FC-B02 fail"
# The service archetype's files, each failing state once (#1103).
plant "a missing Dockerfile is caught" "rm Dockerfile" "FC-C19 fail"
plant "an image not built from the lockfile is caught" "sed -i.bak 's/uv sync --locked/uv sync/' Dockerfile" "FC-C22 fail"
plant "a missing .dockerignore is caught" "rm .dockerignore" "FC-C24 fail"
plant "a .dockerignore that lets .venv in is caught" "printf '.git\n.env\n' > .dockerignore" "FC-C25 fail"
plant "a missing .env.example is caught" "rm .env.example" "FC-C27 fail"
plant "unlabelled issue form is caught" "printf 'name: t\ndescription: \"x\"\nbody: []\n' > .github/ISSUE_TEMPLATE/task.yml" "FC-A15 fail"
plant "missing lockfile is caught" "rm uv.lock" "FC-C02 fail"
# The image check is the service archetypes' own required check (#127): the job
# has to exist in the caller, and a cli instance is not asked for it.
plant "a service instance whose ci.yml has no image job is caught" "rm .github/workflows/ci.yml" "FC-D06 fail"
plant "a cli instance is not asked for the image job" "sed -i.bak 's/backend/cli/' .copier-answers.yml && rm .github/workflows/ci.yml" "__none__" || true
# Issue forms: GitHub reads every form in the folder whatever it is called, in
# either YAML spelling, plus the legacy Markdown templates. A name this checker
# did not expect is not a missing form (#85).
plant "forms under other filenames are accepted" \
  "cd .github/ISSUE_TEMPLATE && mv bug.yml bug_report.yml && mv feature.yml feature_request.yml && mv task.yml work_item.yml" "__none__" || true
plant "forms spelled .yaml are accepted" \
  "cd .github/ISSUE_TEMPLATE && for f in *.yml; do mv \"\$f\" \"\${f%.yml}.yaml\"; done" "__none__" || true
plant "a legacy Markdown template counts as a form and is not read as a broken one" \
  "rm .github/ISSUE_TEMPLATE/*.yml && printf -- '---\nname: Bug\nabout: x\n---\nWhat happened?\n' > .github/ISSUE_TEMPLATE/bug.md" "__none__" || true
plant "config.yml is configuration, not a form" \
  "rm .github/ISSUE_TEMPLATE/*.yml && printf 'blank_issues_enabled: false\n' > .github/ISSUE_TEMPLATE/config.yml" "FC-A10 fail"
# An empty folder is not a local template set: GitHub falls back to the owner's
# shared forms, and offline that cannot be checked. Absence is not concluded here.
infos "an empty folder falls through to inheritance, not to a verdict" \
  "rm .github/ISSUE_TEMPLATE/*.yml" "FC-A10 unknown"
plant "an empty folder alone is not called a missing form" "rm .github/ISSUE_TEMPLATE/*.yml" "__none__" || true
warns "front matter with an empty name is named as unusable" \
  "printf -- '---\nname:\n---\n' > .github/ISSUE_TEMPLATE/bug.md" "FC-A12 warn"
plant "a defect inside a renamed form is still caught" \
  "cd .github/ISSUE_TEMPLATE && mv task.yml work_item.yml && printf 'name: t\ndescription: \"x\"\nbody: []\n' > work_item.yml" "FC-A15 fail"
# Widening the net must not fail a repository that passed yesterday: `.yml` keeps
# its severity, and a defect found only because `.yaml` and `.md` are now read is
# a WARN. `labels:` is plinth policy, not GitHub's syntax (#85).
plant "an unlabelled .yaml next to good forms warns, it does not fail" \
  "printf 'name: e\ndescription: \"x\"\nbody: []\n' > .github/ISSUE_TEMPLATE/extra.yaml" "__none__" || true
plant "an unlabelled .yml still fails" \
  "printf 'name: e\ndescription: \"x\"\nbody: []\n' > .github/ISSUE_TEMPLATE/extra.yml" "FC-A15 fail"
# The two other per-form checks, each in both severities (#1103: every state
# a check declares is reached by a fixture).
plant "a .yml without description fails" \
  "printf 'name: e\nlabels: [x]\nbody: []\n' > .github/ISSUE_TEMPLATE/extra.yml" "FC-A13 fail"
warns "a .yaml without description warns" \
  "printf 'name: e\nlabels: [x]\nbody: []\n' > .github/ISSUE_TEMPLATE/extra.yaml" "FC-A13 warn"
plant "a .yml value that starts with * fails" \
  "printf 'name: e\ndescription: *x\nlabels: [x]\nbody: []\n' > .github/ISSUE_TEMPLATE/extra.yml" "FC-A14 fail"
warns "a .yaml value that starts with * warns" \
  "printf 'name: e\ndescription: *x\nlabels: [x]\nbody: []\n' > .github/ISSUE_TEMPLATE/extra.yaml" "FC-A14 warn"
# An invalid extra warns, because the repository passed without that file being
# read. A repository whose *every* template is invalid never passed the old
# filename check either, so it fails: leaving it green would be a loosening.
warns "an empty Markdown template beside good forms only warns" \
  ": > .github/ISSUE_TEMPLATE/bug.md" "FC-A12 warn"
plant "an empty Markdown template beside good forms does not fail" \
  ": > .github/ISSUE_TEMPLATE/bug.md" "__none__" || true
plant "an empty Markdown template as the only one fails" \
  "rm .github/ISSUE_TEMPLATE/*.yml && : > .github/ISSUE_TEMPLATE/bug.md" "FC-A17 fail"
plant "a bare name: as the only template fails" \
  "rm .github/ISSUE_TEMPLATE/*.yml && printf -- '---\nname:\n---\n' > .github/ISSUE_TEMPLATE/bug.md" "FC-A17 fail"
plant "a quoted empty name as the only template fails" \
  "rm .github/ISSUE_TEMPLATE/*.yml && printf -- '---\nname: \"\"\n---\n' > .github/ISSUE_TEMPLATE/bug.md" "FC-A17 fail"
# GitHub rejects a form whose `body` is not a sequence. The check is new ground,
# so it never fails on its own; it decides usability only for the extensions this
# checker did not read before.
plant "a .yaml whose body is not a list is not a usable template" \
  "rm .github/ISSUE_TEMPLATE/*.yml && printf 'name: x\ndescription: x\nlabels: [x]\nbody: nope\n' > .github/ISSUE_TEMPLATE/custom.yaml" "FC-A17 fail"
plant "the same defect in .yml, which passed before, only warns" \
  "cd .github/ISSUE_TEMPLATE && for f in bug feature task; do printf 'name: %s\ndescription: x\nlabels: [\"%s\"]\nbody: nope\n' \$f \$f > \$f.yml; done" "__none__" || true
warns "the .yml body defect is still named" \
  "printf 'name: bug\ndescription: x\nlabels: [\"bug\"]\nbody: nope\n' > .github/ISSUE_TEMPLATE/bug.yml" "FC-A16 warn"
plant "block-list labels are accepted" "printf 'name: t\ndescription: \"x\"\nlabels:\n  - task\nbody: []\n' > .github/ISSUE_TEMPLATE/task.yml" "__none__" || true
plant "multi-stage and --platform FROM are understood" "printf 'FROM --platform=linux/amd64 python:3.12-slim@sha256:%064d AS base\nFROM base\nRUN uv sync --locked\nUSER app\nCMD [\"python\", \"-m\", \"app\"]\n' 0 > Dockerfile" "__none__" || true

# The three predicates #42 deferred (#95): a tracked dotenv file, an action not
# pinned to a commit, a service with no JSON logs. Each is new ground, so each
# is a WARN and never a FAIL; each names the path and carries its repair; and
# what the checker cannot read is a SKIP, never a PASS.
says() { # <description> <shell to change the copy> <`<id> <state>` expected>
  local copy="$work/case"; rm -rf "$copy"; cp -R "$good" "$copy"
  ( cd "$copy" && eval "$2" )
  local out; out="$(python3 "$checker" --root "$copy" --no-network 2>&1)"
  if reports "$out" "$3"; then ok "$1"; else bad "$1 (expected $3)"; printf '%s\n' "$out" | grep -E 'WARN|FAIL|SKIP' | sed 's/^/        /'; fi
}
quiet() { # <description> <shell to change the copy> <ERE no WARN, FAIL or SKIP line may match>
  local copy="$work/case"; rm -rf "$copy"; cp -R "$good" "$copy"
  ( cd "$copy" && eval "$2" )
  local out; out="$(python3 "$checker" --root "$copy" --no-network 2>&1)"; local rc=$?
  if [ "$rc" = 0 ] && ! grep -qE -- "(WARN|FAIL|SKIP).*($3)" <<<"$out"; then ok "$1"
  else bad "$1 (rc=$rc, no WARN, FAIL or SKIP should mention '$3')"; printf '%s\n' "$out" | grep -E 'WARN|FAIL|SKIP' | sed 's/^/        /'; fi
}
wf() { printf 'jobs:\n  t:\n    runs-on: ubuntu-latest\n    steps:\n'; printf '      %s\n' "$@"; }  # a workflow with these step lines
sha40="$(printf '%040d' 0)"; sha64="$(printf '%064d' 0)"

# Dotenv: the evidence is the index, not the disk. An untracked local `.env` is
# what `.gitignore` is for; a tracked one is in every clone.
says  "the good fixture says no dotenv file is tracked" ":" "FC-A28 pass"
warns "a tracked .env is named" "printf 'AUDIT_DUMMY=not-a-secret\n' > .env && git add -f .env" "FC-A28 warn"
says  "a tracked .env carries its repair" "printf 'A=b\n' > .env && git add -f .env" "FC-A28 info"
warns "a tracked dotenv in a subdirectory is named by its path" "mkdir -p deploy && printf 'A=b\n' > deploy/.env.production && git add -f deploy/.env.production" "FC-A28 warn"
# The repair line is pasted into a shell, and the path is the repository's to choose.
says  "a path with shell syntax in it is quoted in the repair" "mkdir 'a\$(touch PWN)' && printf 'A=b\n' > 'a\$(touch PWN)/.env' && git add -f ." "FC-A28 info"
# A file name is any bytes, and macOS refuses to create one that is not UTF-8,
# so git is a shim here: the listing must be decoded without a traceback.
mkdir -p "$work/gitshim"; printf '#!/bin/sh\nprintf "caf\\351.txt\\0README.md\\0"\n' > "$work/gitshim/git"; chmod +x "$work/gitshim/git"
out="$(PATH="$work/gitshim:$PATH" python3 "$checker" --root "$good" --no-network 2>&1)"
if is "$out" FC-A28 pass && ! grep -q Traceback <<<"$out"; then ok "a file name that is not UTF-8 does not abort the check"
else bad "a non-UTF-8 file name"; printf '%s\n' "$out" | grep -E 'dotenv|Error|Traceback' | sed 's/^/        /'; fi
quiet "an untracked local .env is not the defect" "printf 'A=b\n' > .env" "dotenv"
quiet "tracked placeholders are allowed" "printf 'A=\n' | tee .env.sample > .env.template && git add -f .env.example .env.sample .env.template" "dotenv"
quiet "a tracked directory named .env is not a dotenv file" "mkdir .env && printf 'x\n' > .env/pyvenv.cfg && git add -f .env/pyvenv.cfg" "dotenv"
says  "outside a git work tree the dotenv check is not verified, not passed" "rm -rf .git" "FC-A28 unknown"

# Actions: every `uses:` in .github/workflows, read as workflow syntax.
says  "the good fixture's SHA-pinned reusable workflow passes" ":" "FC-D01 pass"
warns "an action pinned to a tag is named with its file and line" "wf '- uses: actions/checkout@v4' > .github/workflows/t.yml" "FC-D01 warn"
says  "a tag-pinned action carries the command that finds its SHA" "wf '- uses: actions/checkout@v4' > .github/workflows/t.yml" "FC-D01 info"
says  "a ref with shell syntax in it is quoted in the repair" "wf '- uses: a/b@\$(id)' > .github/workflows/t.yml" "FC-D01 info"
warns "a branch ref, a short SHA and a quoted value are all unpinned" "wf '- uses: a/b@main' '- uses: c/d@3d3c42e' '- uses: \"e/f/sub@v1\"' > .github/workflows/t.yaml" "FC-D01 warn"
warns "a docker action pinned to a tag is unpinned" "wf '- uses: docker://alpine:3.20' > .github/workflows/t.yml" "FC-D01 warn"
quiet "SHA pins, a local action, a docker digest, a comment and a run block are not findings" \
  "wf '- uses: actions/checkout@$sha40 # v4' '- uses: ./.github/actions/x' '- uses: docker://alpine@sha256:$sha64' '# - uses: old/one@v1' '- run: |' '    uses: not/yaml@v1' '  env:' '    A: b' > .github/workflows/t.yml" "pinned|workflow"
quiet "the word uses inside a run line is not a uses key" "wf '- run: grep -rn \"uses:\" .github/workflows' > .github/workflows/t.yml" "pins not verified"
# A `: |` inside a trailing comment is not a block scalar (#334); one ending the key's value is.
warns "a comment ending in ': |' does not hide the uses below it" "printf 'jobs:  # note: |\n  t:\n    steps:\n      - uses: actions/checkout@v4\n' > .github/workflows/t.yml" "FC-D01 warn"
warns "a comment ending in ': >' does not hide it either" "printf 'jobs:\n  t:  # a: >-\n    steps:\n      - uses: actions/checkout@v4\n' > .github/workflows/t.yml" "FC-D01 warn"
quiet "an explicit-key run block (? run, then : |) is still a block" "wf '- ? run' '  : |' '    uses: not/yaml@v1' > .github/workflows/t.yml" "pinned|workflow"
quiet "a run block with a trailing comment is still a block" "wf '- run: |  # note: |' '    uses: not/yaml@v1' '- \"a # b\": |' '    uses: not/yaml@v1' > .github/workflows/t.yml" "pinned|workflow"
says  "a uses this checker cannot read is not verified, not passed" "wf '- {uses: actions/checkout@v4}' > .github/workflows/t.yml" "FC-D01 unknown"
says  "an explicit-key uses is not verified either" "wf '- ? uses' '  : actions/checkout@v4' > .github/workflows/t.yml" "FC-D01 unknown"
says  "an anchored uses key is not verified either" "wf '- &step uses: actions/checkout@v4' > .github/workflows/t.yml" "FC-D01 unknown"
says  "a uses later in a flow mapping is not verified either" "wf '- {name: a, uses: actions/checkout@v4}' > .github/workflows/t.yml" "FC-D01 unknown"
says  "a repository with no workflow says so rather than pass" "sed -i.bak 's/backend/cli/' .copier-answers.yml && rm -r .github/workflows" "FC-D01 info"

# JSON logs: a service archetype's source, read statically. A hint is a hint:
# the PASS line says it is not proof of what the process prints.
says  "the good fixture's formatter is a static hint, and is called one" ":" "FC-C26 pass"
warns "a service that only prints is named with its entry point" "printf 'print(\"plain text startup\")\n' > src/app/__main__.py" "FC-C26 warn"
warns "a hint that is only a comment is not a hint" "printf '# TODO: add pythonjsonlogger\nprint(1)\n' > src/app/__main__.py" "FC-C26 warn"
says  "structlog's JSONRenderer is a hint" "printf 'import structlog\nstructlog.configure(processors=[structlog.processors.JSONRenderer()])\n' > src/app/__main__.py" "FC-C26 pass"
says  "python-json-logger in another module is a hint, named by its path" "printf 'print(1)\n' > src/app/__main__.py && printf 'from pythonjsonlogger import jsonlogger\n' > src/app/log.py" "FC-C26 pass"
says  "logging this checker does not recognise is not verified, not passed" "printf 'import logging\nlogging.basicConfig()\n' > src/app/__main__.py" "FC-C26 unknown"
says  "logging imported beside other modules is still logging" "printf 'import json, logging, sys\nlogging.basicConfig(stream=sys.stdout)\n' > src/app/__main__.py" "FC-C26 unknown"
quiet "unrecognised logging is not called a defect either" "printf 'import logging\nlogging.basicConfig()\n' > src/app/__main__.py" "no logging found"
quiet "a cli instance is not asked for JSON logs" "sed -i.bak 's/backend/cli/' .copier-answers.yml && printf 'print(1)\n' > src/app/__main__.py" "JSON logs"

# The ticket's reproduction, all three at once: three WARNs, and the exit code
# consumers merge on does not move.
repro="$work/repro"; rm -rf "$repro"; cp -R "$good" "$repro"
( cd "$repro" && printf 'AUDIT_DUMMY=not-a-secret\n' > .env && git add -f .env \
  && wf '- uses: actions/checkout@v4' > .github/workflows/extra.yml && printf 'print("plain text startup")\n' > src/app/__main__.py )
out="$(python3 "$checker" --root "$repro" --no-network 2>&1)"; rc=$?
if [ "$rc" = 0 ] && [ "$(grep -c '^  WARN ' <<<"$out")" = 3 ] && grep -q -- '-- 0 failed' <<<"$out"; then ok "the three new findings are WARNs and the floor still exits 0"
else bad "the #95 reproduction (rc=$rc)"; printf '%s\n' "$out" | grep -E 'WARN|FAIL|failed' | sed 's/^/        /'; fi

# Inheritance, against a fixture API. The claim "the shared set is read when the
# repository has none" needs a fixture; without one it is an assertion (#85).
inh="$work/inh-api"; mkdir -p "$inh/repos/o/.github/contents/.github/ISSUE_TEMPLATE"
form_b64() { printf 'name: %s\ndescription: "x"\nlabels: ["%s"]\nbody: []\n' "$1" "$1" | base64 | tr -d '\n'; }
printf '[{"name":"bug.yml"},{"name":"feature.yml"}]' > "$inh/repos/o/.github/contents/.github/ISSUE_TEMPLATE.json"
for f in bug feature; do printf '{"content":"%s"}' "$(form_b64 $f)" > "$inh/repos/o/.github/contents/.github/ISSUE_TEMPLATE/$f.yml.json"; done
inherit() { # <description> <`<id> <state>` expected> <local ISSUE_TEMPLATE shell, or ""> [api dir]
  local copy="$work/inh"; rm -rf "$copy"; cp -R "$good" "$copy"
  rm -rf "$copy/.github/ISSUE_TEMPLATE"; [ -n "$3" ] && ( cd "$copy" && eval "$3" )
  local out; out="$(FLOOR_CHECK_API_DIR="${4:-$inh}" python3 "$checker" --root "$copy" --repo o/r 2>&1)"
  if reports "$out" "$2"; then ok "$1"; else bad "$1 (expected $2)"; printf '%s\n' "$out" | grep -E 'issue form|inherited' | sed 's/^/        /'; fi
}
inherit "the owner's shared forms are read when the repository has none" "FC-A10 pass" ""
inherit "a local .gitkeep is not a template: the shared set still applies" "FC-A10 pass" "mkdir -p .github/ISSUE_TEMPLATE && : > .github/ISSUE_TEMPLATE/.gitkeep"
inherit "a local form suppresses the shared set, and says so" "FC-A11 info" "mkdir -p .github/ISSUE_TEMPLATE && printf 'name: t\ndescription: \"x\"\nlabels: [\"t\"]\nbody: []\n' > .github/ISSUE_TEMPLATE/t.yml"
# A file listed but unreadable is an API failure, not an absent template.
bad_api="$work/inh-bad"; mkdir -p "$bad_api/repos/o/.github/contents/.github"
printf '[{"name":"bug.md"}]' > "$bad_api/repos/o/.github/contents/.github/ISSUE_TEMPLATE.json"
inherit "an unreadable inherited file is not verified, not absent" "FC-A10 unknown" "" "$bad_api"
out_bad="$(rm -rf "$work/inh"; cp -R "$good" "$work/inh"; rm -rf "$work/inh/.github/ISSUE_TEMPLATE"; FLOOR_CHECK_API_DIR="$bad_api" python3 "$checker" --root "$work/inh" --repo o/r 2>&1)"
if grep -qE "FAIL.*(issue form|neither local)" <<<"$out_bad"; then bad "an unreadable inherited file was called absent"
else ok "an unreadable inherited file yields no absence verdict"; fi
# A readable config next to an unreadable form: reading the config says nothing
# about whether the forms are there, so absence must still not be concluded.
mixed_api="$work/inh-mixed"; mkdir -p "$mixed_api/repos/o/.github/contents/.github/ISSUE_TEMPLATE"
printf '[{"name":"config.yml"},{"name":"bug.md"}]' > "$mixed_api/repos/o/.github/contents/.github/ISSUE_TEMPLATE.json"
printf '{"content":"%s"}' "$(printf 'blank_issues_enabled: false\n' | base64 | tr -d '\n')" \
  > "$mixed_api/repos/o/.github/contents/.github/ISSUE_TEMPLATE/config.yml.json"
out_mix="$(rm -rf "$work/inh"; cp -R "$good" "$work/inh"; rm -rf "$work/inh/.github/ISSUE_TEMPLATE"; FLOOR_CHECK_API_DIR="$mixed_api" python3 "$checker" --root "$work/inh" --repo o/r 2>&1)"
if grep -qE "FAIL.*(issue template|neither local)" <<<"$out_mix"; then bad "a readable config was taken as proof the forms are absent"
else ok "a readable config next to an unreadable form yields no absence verdict"; fi
is "$out_mix" FC-A10 unknown && ok "the unreadable form is named" || bad "the unreadable form is not named"

# A listing holding only a config proves no form is there: configuration is never
# fetched, so a failed read of it cannot hide that.
cfg_api="$work/inh-cfg"; mkdir -p "$cfg_api/repos/o/.github/contents/.github"
printf '[{"name":"config.yml"}]' > "$cfg_api/repos/o/.github/contents/.github/ISSUE_TEMPLATE.json"
inherit "a shared listing of only a config is a real absence, not an unread file" "FC-A10 fail" "" "$cfg_api"

# Nothing local and nothing shared: a 404 on the listing is a real absence.
none_api="$work/inh-none"; mkdir -p "$none_api/repos/o"
inherit "no templates anywhere is still caught" "FC-A10 fail" "" "$none_api"

# The wall, against a fixture API laid out like api.github.com paths.
api="$work/api"; mkdir -p "$api/repos/o/r/rules/branches" "$api/repos/o/r/rulesets"
# What an admin token reads from repos/o/r: push protection is under
# security_and_analysis, which a token without administration does not get (#303).
repo_meta='"default_branch":"main","squash_merge_commit_title":"PR_TITLE","squash_merge_commit_message":"PR_BODY"'
good_meta="{$repo_meta,\"security_and_analysis\":{\"secret_scanning\":{\"status\":\"enabled\"},\"secret_scanning_push_protection\":{\"status\":\"enabled\"}}}"
printf '%s' "$good_meta" > "$api/repos/o/r.json"
good_rules='[{"type":"deletion","ruleset_source_type":"Repository","ruleset_id":1},{"type":"non_fast_forward","ruleset_source_type":"Repository","ruleset_id":1},{"type":"pull_request","parameters":{"allowed_merge_methods":["squash"]},"ruleset_source_type":"Repository","ruleset_id":1},{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"ci / a","integration_id":15368},{"context":"ci / b","integration_id":15368},{"context":"CodeQL"}]},"ruleset_source_type":"Repository","ruleset_id":1},{"type":"code_scanning","parameters":{"code_scanning_tools":[{"tool":"CodeQL","alerts_threshold":"errors","security_alerts_threshold":"high_or_higher"}]},"ruleset_source_type":"Repository","ruleset_id":1}]'
printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"
printf '{"bypass_actors":[]}' > "$api/repos/o/r/rulesets/1.json"
mkdir -p "$api/repos/o/r/code-scanning"
# The default branch's ci.yml (#325), read through the contents API in any run with the network.
mkdir -p "$api/repos/o/r/contents/.github/workflows"
jq -n --arg c "$(base64 < "$good/.github/workflows/ci.yml" | tr -d '\n')" '{type: "file", encoding: "base64", content: $c}' \
  > "$api/repos/o/r/contents/.github/workflows/ci.yml.json"
good_setup='{"state":"configured","languages":["actions","python"],"query_suite":"default"}'
printf '%s' "$good_setup" > "$api/repos/o/r/code-scanning/default-setup.json"
# Dependabot alerts on with none open, security updates on, and no open secret
# scanning alert (#1118): GitHub answers the first with a 204, read as {}.
mkdir -p "$api/repos/o/r/dependabot" "$api/repos/o/r/secret-scanning"
printf '{}' > "$api/repos/o/r/vulnerability-alerts.json"
printf '[]' > "$api/repos/o/r/dependabot/alerts?state=open&per_page=100.json"
printf '{"enabled":true,"paused":false}' > "$api/repos/o/r/automated-security-fixes.json"
printf '[]' > "$api/repos/o/r/secret-scanning/alerts?state=open&per_page=100&hide_secret=true.json"
# The same answers where gh serves them (its mock below drops the query).
printf '[]' > "$api/repos/o/r/dependabot/alerts.json"; printf '[]' > "$api/repos/o/r/secret-scanning/alerts.json"
# The Actions allowlist the door sets, and private vulnerability reporting on (#747).
mkdir -p "$api/repos/o/r/actions/permissions"
good_perms='{"enabled":true,"allowed_actions":"selected","sha_pinning_required":true}'
good_allow='{"github_owned_allowed":true,"verified_allowed":false,"patterns_allowed":["coolbress/plinth/*"]}'
printf '%s' "$good_perms" > "$api/repos/o/r/actions/permissions.json"
printf '%s' "$good_allow" > "$api/repos/o/r/actions/permissions/selected-actions.json"
printf '{"enabled":true}' > "$api/repos/o/r/private-vulnerability-reporting.json"
# The Actions token settings and the tag ruleset the door sets (#772): the
# fixture is a backend, which releases from a v* tag.
good_wperms='{"default_workflow_permissions":"read","can_approve_pull_request_reviews":false}'
printf '%s' "$good_wperms" > "$api/repos/o/r/actions/permissions/workflow.json"
good_tags="$(jq -c '. + {id: 3}' "$root/ruleset-tags.json")"
good_listing='[{"id":1,"target":"branch","source_type":"Repository"},{"id":3,"target":"tag","source_type":"Repository"}]'
printf '%s' "$good_listing" > "$api/repos/o/r/rulesets?per_page=100.json"
printf '%s' "$good_tags" > "$api/repos/o/r/rulesets/3.json"
wall() { # <description> <expected substring in output> [shell that edits the fixture first]
  local out; [ -n "${3:-}" ] && eval "$3"
  out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" 2>&1)"
  # A summary naming N not verified must sit above exactly N SKIP lines.
  local n want; n="$(grep -c '^  SKIP ' <<<"$out")"; want="${2##*failed, }"; want="${want%% *}"
  if sees "$out" "$2" -- "$2" && { [[ "$2" != "-- "*"not verified"* ]] || [ "$n" = "$want" ]; }; then ok "$1"
  else bad "$1 (expected '$2', SKIP lines=$n)"; printf '%s\n' "$out" | grep -E 'FAIL|SKIP|failed' | sed 's/^/        /'; fi
  printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"; printf '{"bypass_actors":[]}' > "$api/repos/o/r/rulesets/1.json"
  printf '%s' "$good_meta" > "$api/repos/o/r.json"
  printf '%s' "$good_setup" > "$api/repos/o/r/code-scanning/default-setup.json"
  printf '%s' "$good_perms" > "$api/repos/o/r/actions/permissions.json"
  printf '%s' "$good_allow" > "$api/repos/o/r/actions/permissions/selected-actions.json"
  printf '{"enabled":true}' > "$api/repos/o/r/private-vulnerability-reporting.json"
  printf '%s' "$good_wperms" > "$api/repos/o/r/actions/permissions/workflow.json"
  printf '%s' "$good_listing" > "$api/repos/o/r/rulesets?per_page=100.json"; printf '%s' "$good_tags" > "$api/repos/o/r/rulesets/3.json"
}
wall "intact wall passes" "-- 0 failed"
wall "squash commits are the pull request title and description" "FC-E08 pass"
wall "drifted squash settings are caught" "FC-E08 fail" "printf '{\"default_branch\":\"main\",\"squash_merge_commit_title\":\"COMMIT_OR_PR_TITLE\",\"squash_merge_commit_message\":\"COMMIT_MESSAGES\"}' > \"$api/repos/o/r.json\""
wall "invisible squash settings are SKIP, not a pass" "FC-E08 unknown" "printf '{\"default_branch\":\"main\"}' > \"$api/repos/o/r.json\""
# A repository the door damaged before #105: the default branch is the throwaway
# probe, the whole wall stands on that branch, and `main` has no rules at all.
# Following the default branch reports it as a wall standing -- the checker
# telling someone `main` is guarded while anyone can force-push it (#107).
damaged="mv \"$api/repos/o/r/rules/branches/main.json\" \"$api/repos/o/r/rules/branches/__push-probe.json\"; printf '{\"default_branch\":\"__push-probe\",\"squash_merge_commit_title\":\"PR_TITLE\",\"squash_merge_commit_message\":\"PR_BODY\"}' > \"$api/repos/o/r.json\""
wall "a default branch that is not main is reported, not passed over" "FC-E07 warn" "$damaged"
wall "the finding says main is the branch left unprotected" "FC-E07 warn" "$damaged"
wall "the fix carries the one command that repairs it" "FC-E07 info" "$damaged"
# Never a FAIL. `ci / floor-check` runs with --repo in every consumer's CI, so a
# FAIL blocks their merges -- and a repository whose default is deliberately
# `master` or `trunk` is not broken, it just is not what the door builds (#106).
eval "$damaged"
out_db="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --expect-checks "ci / a, ci / b" 2>&1)"; rc_db=$?
if [ "$rc_db" = 0 ] && ! grep -q "FAIL.*default branch" <<<"$out_db"; then ok "a default branch that is not main never fails the floor (consumer CI keeps merging)"
else bad "a wrong default branch changed the exit code (rc=$rc_db) or produced a FAIL"; printf '%s
' "$out_db" | grep -E 'FAIL' | sed 's/^/        /'; fi
# Said once and plainly, not only as the prefix on each rule line.
if is "$out_db" FC-E07 info; then ok "the branch the wall was checked on is stated once, not only as a prefix"
else bad "the output never states which branch the wall was checked on"; fi
printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"
printf '%s' "$good_meta" > "$api/repos/o/r.json"
rm -f "$api/repos/o/r/rules/branches/__push-probe.json"
# The default branch is read from the repository, so a token or an API that does
# not report it must not be read as "main, fine": not verified, like every other
# API-backed check here.
wall "a default branch the API does not report is not verified rather than passed" \
  "FC-E07 unknown" \
  "printf '{\"squash_merge_commit_title\":\"PR_TITLE\",\"squash_merge_commit_message\":\"PR_BODY\"}' > \"$api/repos/o/r.json\""
wall "a repository whose default branch is main is unchanged: no warning, no new noise" "-- 0 failed"
wall "a healthy repository still says which branch the wall was checked on" "FC-E07 info"
wall "dropped required check is caught" "FC-E19 fail" "sed -i.bak 's/,{\"context\":\"ci \/ b\",\"integration_id\":15368}//' \"$api/repos/o/r/rules/branches/main.json\""
wall "a dropped required check comes with the one command that requires it again" "FC-E19 info" "sed -i.bak 's/,{\"context\":\"ci \/ b\",\"integration_id\":15368}//' \"$api/repos/o/r/rules/branches/main.json\""
wall "widened merge methods are caught" "FC-E17 fail" "sed -i.bak 's/\[\"squash\"\]/[\"squash\",\"merge\"]/' \"$api/repos/o/r/rules/branches/main.json\""
wall "bypass actor is caught" "FC-E24 fail" "printf '{\"bypass_actors\":[{\"actor_id\":5,\"actor_type\":\"RepositoryRole\"}]}' > \"$api/repos/o/r/rulesets/1.json\""
wall "no rules at all is caught" "FC-E12 fail" "printf '[]' > \"$api/repos/o/r/rules/branches/main.json\""
wall "invisible bypass actors are SKIP, not a pass" "FC-E24 unknown" "printf '{}' > \"$api/repos/o/r/rulesets/1.json\""
# Labels have no fixture yet at this point, so that read is the one SKIP of an
# intact wall; the invisible bypass actors are the second.
wall "an intact wall against the fixture counts only the label read as not verified" "-- 0 failed, 1 not verified"
wall "invisible bypass actors are counted as not verified" "-- 0 failed, 2 not verified" "printf '{}' > \"$api/repos/o/r/rulesets/1.json\""
wall "an unreadable repository is counted, not passed" "-- 0 failed, 2 not verified" "printf '[]' > \"$api/repos/o/r.json\""
# Old-style branch protection and no ruleset, as measured on a test repository
# for #1104 (2026-11-25): with either token rules/branches/main and rulesets are
# [], branches/main says protected: true, and branches/main/protection is the
# rule set to an admin token and a 403 to the Actions token (contents: read),
# served here as unparseable, which is how a fixture says the API failed. The
# checker reads neither branches path today and calls that wall down; the state
# the adopter path gives it is `review` (#1103's model, a person reads the old
# protection; #1107). This pins today's verdict so that change is made on purpose.
oapi="$work/api-oldstyle"; rm -rf "$oapi"; cp -R "$api" "$oapi"
mkdir -p "$oapi/repos/o/r/branches/main"
printf '[]' > "$oapi/repos/o/r/rules/branches/main.json"; printf '[]' > "$oapi/repos/o/r/rulesets?per_page=100.json"
printf '%s' '{"name":"main","protected":true,"protection":{"enabled":true,"required_status_checks":{"enforcement_level":"non_admins","contexts":["test"],"checks":[{"context":"test","app_id":15368}]}}}' \
  > "$oapi/repos/o/r/branches/main.json"
old_protection='{"required_status_checks":{"strict":true,"contexts":["test"],"checks":[{"context":"test","app_id":15368}]},"required_pull_request_reviews":{"dismiss_stale_reviews":false,"require_code_owner_reviews":false,"require_last_push_approval":false,"required_approving_review_count":0},"required_signatures":{"enabled":false},"enforce_admins":{"enabled":false},"required_linear_history":{"enabled":false},"allow_force_pushes":{"enabled":false},"allow_deletions":{"enabled":false},"block_creations":{"enabled":false},"required_conversation_resolution":{"enabled":false},"lock_branch":{"enabled":false},"allow_fork_syncing":{"enabled":false}}'
oldstyle() { # <description> <protection body> [checker args...]
  local desc="$1" out rc; printf '%s' "$2" > "$oapi/repos/o/r/branches/main/protection.json"; shift 2
  out="$(FLOOR_CHECK_API_DIR="$oapi" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" \
         --expect-checks "ci / a, ci / b" "$@" 2>&1)"; rc=$?
  if [ "$rc" = 1 ] && is "$out" FC-E12 fail \
     && ! grep -qiE 'protected|branch protection' <<<"$out"; then ok "$desc"
  else bad "$desc (rc=$rc)"; grep -E 'FAIL|wall|protect' <<<"$out" | sed 's/^/        /'; fi
}
oldstyle "old-style protection, admin token: today the wall is down, the protection unread" "$old_protection"
oldstyle "old-style protection, Actions token (403): today the wall is down, the protection unread" "HTTP 403 Resource not accessible by integration" --actions-token
# The merge ruleset (ruleset-merge.json, #568): the one ruleset allowed a
# bypass actor, and only in its exact shape. Its own copy of the fixture API.
mapi="$work/api-merge"; rm -rf "$mapi"; cp -R "$api" "$mapi"
b_rule='{"type":"update","ruleset_source_type":"Repository","ruleset_id":2}'
# As an admin token reads it: the whole ruleset, scope and actor.
b_actors="$(jq -c '. + {id: 2}' "$root/ruleset-merge.json")"
merge_wall() { # <description> <expected regex> [shell that edits $mapi first] [checker args...]
  local desc="$1" want="$2" edit="${3:-}" out; shift; shift; [ $# -gt 0 ] && shift
  jq -c ". + [$b_rule]" <<<"$good_rules" > "$mapi/repos/o/r/rules/branches/main.json"
  printf '%s' "$b_actors" > "$mapi/repos/o/r/rulesets/2.json"; printf '{"bypass_actors":[]}' > "$mapi/repos/o/r/rulesets/1.json"
  jq -c '. + {permissions: {admin: true, push: true}}' <<<"$good_meta" > "$mapi/repos/o/r.json"
  [ -n "$edit" ] && eval "$edit"
  out="$(FLOOR_CHECK_API_DIR="$mapi" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" \
         --expect-checks "ci / a, ci / b" "$@" 2>&1)"
  if sees "$out" "$want" -E -- "$want"; then ok "$desc"
  else bad "$desc (expected /$want/)"; grep -E 'FAIL|SKIP|WARN|merge|bypass|failed' <<<"$out" | sed 's/^/        /'; fi
}
M=(--merge-ruleset "$root/ruleset-merge.json")
merge_wall "the merge ruleset in its shape passes" "FC-E25 pass" "" "${M[@]}"
merge_wall "the merge ruleset's admin bypass is not a bypass FAIL" '^-- 0 failed' "" "${M[@]}"
merge_wall "the first ruleset is still held to no bypass actor beside it" "FC-E24 pass" "" "${M[@]}"
merge_wall "a missing merge ruleset is a WARN with the command that adds it" \
  "FC-E25 warn" "printf '%s' \"\$good_rules\" > \"$mapi/repos/o/r/rules/branches/main.json\"" "${M[@]}"
merge_wall "a missing merge ruleset names the upgrade command" \
  "FC-E25 info" "printf '%s' \"\$good_rules\" > \"$mapi/repos/o/r/rules/branches/main.json\"" "${M[@]}"
merge_wall "a missing merge ruleset fails nothing (consumer CI keeps merging)" \
  '^-- 0 failed' "printf '%s' \"\$good_rules\" > \"$mapi/repos/o/r/rules/branches/main.json\"" "${M[@]}"
# Not in effect is not absent: GitHub leaves a disabled, evaluate-mode or
# mis-scoped ruleset out of the branch's rules, and the repository's list
# still has it.
not_in_effect() { # <jq edit of B> -> shell for merge_wall: B listed but out of the branch's rules
  printf '%s' "printf '%s' \"\$good_rules\" > \"$mapi/repos/o/r/rules/branches/main.json\"; printf '[{\"id\":1,\"source_type\":\"Repository\"},{\"id\":2,\"source_type\":\"Repository\"}]' > \"$mapi/repos/o/r/rulesets?per_page=100.json\"; jq -c '$1' <<<\"\$b_actors\" > \"$mapi/repos/o/r/rulesets/2.json\""
}
merge_wall "a disabled merge ruleset is a FAIL, not the missing WARN" "FC-E25 fail" "$(not_in_effect '.enforcement = "disabled"')" "${M[@]}"
merge_wall "a merge ruleset in evaluate mode is a FAIL" "FC-E25 fail" "$(not_in_effect '.enforcement = "evaluate"')" "${M[@]}"
merge_wall "a merge ruleset scoped off the default branch is a FAIL" "FC-E25 fail" "$(not_in_effect '.conditions.ref_name.include = ["refs/heads/other"]')" "${M[@]}"
rm -f "$mapi/repos/o/r/rulesets?per_page=100.json"
merge_wall "a list with no update rule anywhere is still the missing WARN" "FC-E25 warn" \
  "printf '%s' \"\$good_rules\" > \"$mapi/repos/o/r/rules/branches/main.json\"; printf '[{\"id\":1,\"source_type\":\"Repository\"}]' > \"$mapi/repos/o/r/rulesets?per_page=100.json\"" "${M[@]}"
merge_wall "a list that cannot be read is not verified, not the missing WARN" "FC-E25 unknown" \
  "printf '%s' \"\$good_rules\" > \"$mapi/repos/o/r/rules/branches/main.json\"; printf '{}' > \"$mapi/repos/o/r/rulesets?per_page=100.json\"" "${M[@]}"
rm -f "$mapi/repos/o/r/rulesets?per_page=100.json"
merge_wall "a merge ruleset bypassed through a pull request, not exempt, is caught" "FC-E25 fail" \
  "printf '{\"bypass_actors\":[{\"actor_id\":5,\"actor_type\":\"RepositoryRole\",\"bypass_mode\":\"pull_request\"}]}' > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
merge_wall "a merge ruleset bypassed always is caught" "FC-E25 fail" \
  "printf '{\"bypass_actors\":[{\"actor_id\":5,\"actor_type\":\"RepositoryRole\",\"bypass_mode\":\"always\"}]}' > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
merge_wall "a merge ruleset bypassed by the write role is caught" "FC-E25 fail" \
  "printf '{\"bypass_actors\":[{\"actor_id\":4,\"actor_type\":\"RepositoryRole\",\"bypass_mode\":\"exempt\"}]}' > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
merge_wall "a merge ruleset with no bypass actor is caught (nobody could merge)" "FC-E25 fail" \
  "printf '{\"bypass_actors\":[]}' > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
merge_wall "update beside other rules in one ruleset is caught" "FC-E25 fail" \
  "jq -c '. + [{\"type\":\"deletion\",\"ruleset_source_type\":\"Repository\",\"ruleset_id\":2}]' \"$mapi/repos/o/r/rules/branches/main.json\" > \"$mapi/x\" && mv \"$mapi/x\" \"$mapi/repos/o/r/rules/branches/main.json\"" "${M[@]}"
merge_wall "...and its bypass actor is then a bypass FAIL as well" "FC-E24 fail" \
  "jq -c '. + [{\"type\":\"deletion\",\"ruleset_source_type\":\"Repository\",\"ruleset_id\":2}]' \"$mapi/repos/o/r/rules/branches/main.json\" > \"$mapi/x\" && mv \"$mapi/x\" \"$mapi/repos/o/r/rules/branches/main.json\"" "${M[@]}"
merge_wall "a merge ruleset widened to every branch is caught (it would stop every branch push but the admin's)" "FC-E25 fail" \
  "jq -c '.conditions.ref_name.include = [\"~ALL\"]' <<<\"\$b_actors\" > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
merge_wall "a merge ruleset with its actor right and its scope unread is not verified, not passed" "FC-E25 unknown" \
  "jq -c '{bypass_actors}' <<<\"\$b_actors\" > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
merge_wall "...and then no PASS for it" '^-- 0 failed, 2 not verified' \
  "jq -c '{bypass_actors}' <<<\"\$b_actors\" > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
merge_wall "a bypass actor on the first ruleset still fails beside a good merge ruleset" "FC-E24 fail" \
  "printf '%s' \"\$b_actors\" > \"$mapi/repos/o/r/rulesets/1.json\"" "${M[@]}"
merge_wall "unreadable merge bypass actors are SKIP, never PASS" "FC-E25 unknown" \
  "printf '{}' > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
merge_wall "unreadable merge bypass actors are counted as not verified" '^-- 0 failed, 2 not verified' \
  "printf '{}' > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
merge_wall "with the Actions token they are left to /plinth:floor-check" \
  "FC-E25 review" \
  "printf '{}' > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}" --actions-token
merge_wall "an update rule from an organization ruleset is not verified, not passed" "FC-E25 unknown" \
  "jq -c '. + [{\"type\":\"update\",\"ruleset_source_type\":\"Organization\",\"ruleset_id\":9}]' <<<\"\$good_rules\" > \"$mapi/repos/o/r/rules/branches/main.json\"" "${M[@]}"
# Guidance or boundary (#569): the login's role on the repository decides,
# since GitHub lets the admin role past the merge ruleset whatever the token.
as_login() { # <admin true|false|absent> -> shell for merge_wall: the repository as that login reads it
  case "$1" in
    absent) printf '%s' "printf '%s' \"\$good_meta\" > \"$mapi/repos/o/r.json\"" ;;
    *) printf '%s' "jq -c '. + {permissions: {admin: $1, push: true}}' <<<\"\$good_meta\" > \"$mapi/repos/o/r.json\"" ;;
  esac
}
no_b="printf '%s' \"\$good_rules\" > \"$mapi/repos/o/r/rules/branches/main.json\""
merge_wall "an admin login is guidance" "FC-E26 info" "$(as_login true)" "${M[@]}"
merge_wall "an admin login is guidance with the merge ruleset missing too" "FC-E26 info" "$(as_login true); $no_b" "${M[@]}"
merge_wall "a non-admin login with the merge ruleset standing is a boundary" "FC-E26 pass" "$(as_login false)" "${M[@]}"
merge_wall "...and the boundary fails nothing" '^-- 0 failed, 1 not verified$' "$(as_login false)" "${M[@]}"
merge_wall "a non-admin login with no merge ruleset is guidance, not a boundary" "FC-E26 info" "$(as_login false); $no_b" "${M[@]}"
merge_wall "a non-admin login with an unreadable merge ruleset is not verified, never a boundary" "FC-E26 unknown" \
  "$(as_login false); printf '{}' > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
# As a collaborator's token reads it (#569's run): scope, no actors, and GitHub's answer for this login.
collab_b() { printf '%s' "jq -c 'del(.bypass_actors) + {current_user_can_bypass: \"$1\"}' <<<\"\$b_actors\" > \"$mapi/repos/o/r/rulesets/2.json\""; }
merge_wall "a collaborator that can never bypass the merge ruleset is a boundary, its actors unread" \
  "FC-E26 pass" "$(as_login false); $(collab_b never)" "${M[@]}"
merge_wall "...while the unread actors stay not verified" "FC-E25 unknown" "$(as_login false); $(collab_b never)" "${M[@]}"
merge_wall "a collaborator GitHub says can bypass it is not a boundary" "FC-E26 unknown" "$(as_login false); $(collab_b exempt)" "${M[@]}"
merge_wall "no answer for this login is not a boundary" "FC-E26 unknown" \
  "$(as_login false); printf '%s' \"\$(jq -c 'del(.bypass_actors)' <<<\"\$b_actors\")\" > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
merge_wall "a read-only login with no merge ruleset is a boundary, not guidance (it cannot merge at all)" \
  "FC-E26 pass" "$(as_login false); jq -c '.permissions.push = false' \"$mapi/repos/o/r.json\" > \"$mapi/x\" && mv \"$mapi/x\" \"$mapi/repos/o/r.json\"; $no_b" "${M[@]}"
merge_wall "a non-admin login whose write access cannot be read is not verified" \
  "FC-E26 unknown" "$(as_login false); jq -c 'del(.permissions.push)' \"$mapi/repos/o/r.json\" > \"$mapi/x\" && mv \"$mapi/x\" \"$mapi/repos/o/r.json\"; $no_b" "${M[@]}"
merge_wall "a role that cannot be read is not verified" "FC-E26 unknown" "$(as_login absent)" "${M[@]}"
merge_wall "...and counted as not verified, not passed" '^-- 0 failed, 2 not verified$' "$(as_login absent)" "${M[@]}"
# Without the branch's rules (#583): the wall's own SKIP or FAIL stands, and
# the line is still printed, from the role alone.
no_rules="printf '[]' > \"$mapi/repos/o/r/rules/branches/main.json\""
bad_rules="printf 'not json' > \"$mapi/repos/o/r/rules/branches/main.json\""
push_false="jq -c '.permissions.push = false' \"$mapi/repos/o/r.json\" > \"$mapi/x\" && mv \"$mapi/x\" \"$mapi/repos/o/r.json\""
merge_wall "no rules: the wall's FAIL stands" "FC-E12 fail" "$(as_login false); $no_rules" "${M[@]}"
merge_wall "no rules: an admin login is guidance" "FC-E26 info" "$(as_login true); $no_rules" "${M[@]}"
merge_wall "no rules: a login with write access is guidance" "FC-E26 info" "$(as_login false); $no_rules" "${M[@]}"
merge_wall "no rules: a login without write access is a boundary" "FC-E26 pass" "$(as_login false); $push_false; $no_rules" "${M[@]}"
merge_wall "no rules: an unread role is not verified" "FC-E26 unknown" "$(as_login absent); $no_rules" "${M[@]}"
merge_wall "unreadable rules: the wall's SKIP stands" "FC-E12 unknown" "$(as_login false); $bad_rules" "${M[@]}"
merge_wall "unreadable rules: a login with write access is not verified, never a boundary" "FC-E26 unknown" "$(as_login false); $bad_rules" "${M[@]}"
merge_wall "unreadable rules: an admin login is guidance" "FC-E26 info" "$(as_login true); $bad_rules" "${M[@]}"
merge_wall "unreadable rules: a login without write access is a boundary" "FC-E26 pass" "$(as_login false); $push_false; $bad_rules" "${M[@]}"
merge_wall "unreadable rules: an unread role is not verified" "FC-E26 unknown" "$(as_login absent); $bad_rules" "${M[@]}"
merge_wall "no rules, with the Actions token: not decided" "FC-E26 review" "$(as_login false); $no_rules" "${M[@]}" --actions-token
merge_wall "unreadable rules, with the Actions token: not decided" "FC-E26 review" "$(as_login false); $bad_rules" "${M[@]}" --actions-token
merge_wall "with the Actions token it is not decided" "FC-E26 review" "$(as_login false)" "${M[@]}" --actions-token
merge_wall "...and it is left to /plinth:floor-check, not passed" '^-- 0 failed, [0-9]+ not verified, [0-9]+ left to /plinth:floor-check$' "$(as_login false)" "${M[@]}" --actions-token
for who in true false absent; do
  jq -c ". + [$b_rule]" <<<"$good_rules" > "$mapi/repos/o/r/rules/branches/main.json"
  printf '%s' "$b_actors" > "$mapi/repos/o/r/rulesets/2.json"; eval "$(as_login "$who")"
  out="$(FLOOR_CHECK_API_DIR="$mapi" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" \
         --expect-checks "ci / a, ci / b" "${M[@]}" --actions-token 2>&1)"
  if grep -q '^  PASS  the merge' <<<"$out" || grep -q 'the merge: guidance\|the merge: boundary' <<<"$out"; then
    bad "with the Actions token and admin=$who, no guidance or boundary is said"
  else ok "with the Actions token and admin=$who, no guidance or boundary is said"; fi
done
merge_wall "without --merge-ruleset nothing is said about the merge" '^-- ' "$(as_login false)"
if FLOOR_CHECK_API_DIR="$mapi" python3 "$checker" --root "$good" --no-network --repo o/r --expect-checks "ci / a, ci / b" 2>&1 | grep -q 'the merge:'; then
  bad "without --merge-ruleset no merge line is printed"; else ok "without --merge-ruleset no merge line is printed"; fi
# Without --merge-ruleset nothing says what B should be: its bypass actor is
# held to the first ruleset's rule (fail-closed), and the gap is named.
merge_wall "without --merge-ruleset the shape is said not compared" "FC-E25 info"
merge_wall "without --merge-ruleset its bypass actor is not let through" "FC-E24 fail"
# The approvals required against who can merge (#1150): a WARN either way
# they do not fit, never a FAIL. With the merge ruleset standing, only admins
# merge, so the agent's own account (write) is not a person here.
collab() { # <login>:<admin|write|bot> ...: the collaborators list
  local c rows=() l r
  for c in "$@"; do l="${c%%:*}"; r="${c#*:}"
    case "$r" in
      admin) rows+=("{\"login\":\"$l\",\"type\":\"User\",\"permissions\":{\"admin\":true,\"push\":true}}") ;;
      write) rows+=("{\"login\":\"$l\",\"type\":\"User\",\"permissions\":{\"admin\":false,\"push\":true}}") ;;
      bot)   rows+=("{\"login\":\"$l\",\"type\":\"Bot\",\"permissions\":{\"admin\":true,\"push\":true}}") ;;
    esac; done
  local IFS=,; printf '[%s]' "${rows[*]}" > "$mapi/repos/o/r/collaborators?per_page=100.json"
}
count() { # <approvals> [owners]: the pull_request rule requires that many, with code owners' review when said
  jq -c --argjson n "$1" --argjson o "$([ "${2:-}" = owners ] && echo true || echo false)" "map(if .type == \"pull_request\" then .parameters.required_approving_review_count = \$n | .parameters.require_code_owner_review = \$o else . end) + [$b_rule]" \
    <<<"$good_rules" > "$mapi/repos/o/r/rules/branches/main.json"
}
merge_wall "one person and the agent's account, no approval: a PASS" "FC-E35 pass" "count 0; collab o:admin agent:write" "${M[@]}"
merge_wall "  and the agent's account is not counted as a person" "and 1 person can merge \(o\)" "count 0; collab o:admin agent:write" "${M[@]}"
merge_wall "two admins and no approval required: a WARN" "FC-E35 warn" "count 0; collab o:admin b:admin agent:write" "${M[@]}"
merge_wall "  naming both" "2 people can merge \(b, o\) and no approval is required" "count 0; collab o:admin b:admin agent:write" "${M[@]}"
merge_wall "  with the two-people command" "add-ruleset-rule.sh o/r two-people" "count 0; collab o:admin b:admin agent:write" "${M[@]}"
merge_wall "  and fails nothing" '^-- 0 failed' "count 0; collab o:admin b:admin agent:write" "${M[@]}"
# An approval counts from anyone with write, so with code owners' review off
# the agent's own account can give it: one person is not alone then. With it
# on, only those CODEOWNERS names count.
co() { mkdir -p "$good/.github"; printf '%s\n' "$@" > "$good/.github/CODEOWNERS"; }
nco() { rm -f "$good/.github/CODEOWNERS"; }
merge_wall "one approval, code owners' review off, the agent's account can approve: not alone" "FC-E35 pass" "count 1; collab o:admin agent:write" "${M[@]}"
merge_wall "one approval, code owners' review on, CODEOWNERS names only o: a WARN" "FC-E35 warn" "count 1 owners; collab o:admin agent:write; co '* @o' '/.github/ @o'" "${M[@]}"
merge_wall "  saying their own pull requests cannot merge" "only o can give one that counts \(code owners' review is on, and CODEOWNERS names no one else with write\): a pull request of theirs cannot merge" "count 1 owners; collab o:admin agent:write; co '* @o'" "${M[@]}"
merge_wall "  with the one-person command" "add-ruleset-rule.sh o/r one-person" "count 1 owners; collab o:admin agent:write; co '* @o'" "${M[@]}"
merge_wall "  and fails nothing" '^-- 0 failed' "count 1 owners; collab o:admin agent:write; co '* @o'" "${M[@]}"
merge_wall "code owners' review on and no CODEOWNERS file: a WARN saying so" "no CODEOWNERS file is here" "count 1 owners; collab o:admin agent:write; nco" "${M[@]}"
merge_wall "CODEOWNERS names o and b (write), o merges: a PASS, not one-person" "FC-E35 pass" "count 1 owners; collab o:admin b:write agent:write; co '* @o @B' '/.github/ @o @acme/team'" "${M[@]}"
merge_wall "one approval and only o with write: a WARN" "FC-E35 warn" "count 1; collab o:admin; nco" "${M[@]}"
merge_wall "one approval and two admins: a PASS" "FC-E35 pass" "count 1; collab o:admin b:admin agent:write" "${M[@]}"
merge_wall "a bot with admin is not a person" "FC-E35 pass" "count 0; collab o:admin dependabot:bot" "${M[@]}"
# The review of #1235: an author cannot approve their own pull request, so
# two people with two approvals required leaves each one short; and a team
# in CODEOWNERS may hold approvers this does not read, so the count is not
# made and nothing weaker is suggested.
merge_wall "two approvals and two people who can approve: a WARN" "FC-E35 warn" "count 2; collab o:admin b:admin; nco" "${M[@]}"
merge_wall "  with the two-people command, not one-person" "add-ruleset-rule.sh o/r two-people" "count 2; collab o:admin b:admin; nco" "${M[@]}"
merge_wall "two approvals and three who can approve: a PASS" "FC-E35 pass" "count 2; collab o:admin b:admin c:write; nco" "${M[@]}"
# The second review: the approvals come from any writer, and a code owner's
# is required besides, so the two are counted apart: three writers, two of
# them code owners, two approvals required, is a PASS.
merge_wall "two approvals, three writers, two of them code owners: a PASS" "FC-E35 pass" "count 2 owners; collab o:admin alice:write bob:write; co '* @o @alice'" "${M[@]}"
merge_wall "two approvals, three writers, one code owner: a WARN, that owner's own cannot merge" "only o can give one that counts \(code owners' review is on" "count 2 owners; collab o:admin alice:write bob:write; co '* @o'" "${M[@]}"
merge_wall "code owners' review on, CODEOWNERS names a team and only o: not counted, an INFO" "FC-E35 info" "count 1 owners; collab o:admin agent:write; co '* @o @acme/maintainers'" "${M[@]}"
merge_wall "  naming the team" "CODEOWNERS names @acme/maintainers, whose members are not read here" "count 1 owners; collab o:admin agent:write; co '* @o @acme/maintainers'" "${M[@]}"
fc_out="$(FLOOR_CHECK_API_DIR="$mapi" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" "${M[@]}" 2>&1)"
if grep -q "one-person" <<<"$fc_out"; then bad "  and no one-person command beside a team"; else ok "  and no one-person command beside a team"; fi
nco
# Without the merge ruleset, everyone with write can merge: the agent's own
# account is one of them (FC-E25 says to add the ruleset).
merge_wall "no merge ruleset: write counts" "FC-E35 warn" "count 0; collab o:admin agent:write; jq -c 'map(select(.type != \"update\"))' \"$mapi/repos/o/r/rules/branches/main.json\" > \"$mapi/x\" && mv \"$mapi/x\" \"$mapi/repos/o/r/rules/branches/main.json\"" "${M[@]}"
merge_wall "collaborators not readable: an INFO, not a SKIP" "FC-E35 info" "count 0; rm -f \"$mapi/repos/o/r/collaborators?per_page=100.json\"" "${M[@]}"
merge_wall "  that adds nothing unverified (the one is the labels, offline)" '^-- 0 failed, 1 not verified$' "count 0; rm -f \"$mapi/repos/o/r/collaborators?per_page=100.json\"" "${M[@]}"
merge_wall "collaborators not readable with the Actions token: left to the skill" "FC-E35 review" "count 0; rm -f \"$mapi/repos/o/r/collaborators?per_page=100.json\"" "${M[@]}" --actions-token
merge_wall "no person with admin among the collaborators: an INFO" "FC-E35 info" "count 0; collab agent:write; nco" "${M[@]}"
merge_wall "no approval count in the rule: nothing said" '^-- ' "collab o:admin b:admin; rm -f \"$mapi/x\"" "${M[@]}"
fc_out="$(FLOOR_CHECK_API_DIR="$mapi" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" "${M[@]}" 2>&1)"
if grep -q "approvals required\|can merge (" <<<"$fc_out"; then bad "no approval count in the rule: no FC-E35 line"; else ok "no approval count in the rule: no FC-E35 line"; fi
rm -f "$mapi/repos/o/r/collaborators?per_page=100.json"
# CodeQL: enforced by the code_scanning rule (the door since #41) or by
# a `CodeQL` check name (repositories the door created before that). Either
# holds the wall; neither does not. The fixture carries both.
strip_name='map(if .type=="required_status_checks" then .parameters.required_status_checks |= map(select(.context!="CodeQL")) else . end)'
strip_rule='map(select(.type!="code_scanning"))'
rule_for() { # <tool> [alerts_threshold] [security_alerts_threshold] [ruleset_id]
  printf '{"type":"code_scanning","parameters":{"code_scanning_tools":[{"tool":"%s","alerts_threshold":"%s","security_alerts_threshold":"%s"}]},"ruleset_source_type":"Repository","ruleset_id":%s}' "$1" "${2:-errors}" "${3:-high_or_higher}" "${4:-1}"
}
rules_rule_only="$(jq -c "$strip_name" <<<"$good_rules")"
rules_name_only="$(jq -c "$strip_rule" <<<"$good_rules")"
rules_neither="$(jq -c "$strip_name | $strip_rule" <<<"$good_rules")"
rules_other_tool="$(jq -c "$strip_name | $strip_rule + [\$r]" --argjson r "$(rule_for Semgrep)" <<<"$good_rules")"
wall "CodeQL as a rule, not a name, passes" "FC-E21 pass" "printf '%s' \"\$rules_rule_only\" > \"$api/repos/o/r/rules/branches/main.json\""
wall "CodeQL as a legacy check name passes" "FC-E21 pass" "printf '%s' \"\$rules_name_only\" > \"$api/repos/o/r/rules/branches/main.json\""
wall "CodeQL neither rule nor name is caught" "FC-E21 fail" "printf '%s' \"\$rules_neither\" > \"$api/repos/o/r/rules/branches/main.json\""
wall "a code_scanning rule for another tool is caught" "FC-E21 fail" "printf '%s' \"\$rules_other_tool\" > \"$api/repos/o/r/rules/branches/main.json\""
# The rule's alert thresholds are the policy: `none` on both is a rule that
# blocks nothing, and it printed `CodeQL enforced (rule)` (#96). The live
# policy is compared with --ruleset; equal or stricter passes, weaker fails,
# a field that cannot be read is not verified, and a check name proves none
# of it.
policy() { # <alerts_threshold> <security_alerts_threshold> -- the fixture with the rule's thresholds replaced
  jq -c "$strip_rule + [\$r]" --argjson r "$(rule_for CodeQL "$1" "$2")" <<<"$good_rules" > "$api/repos/o/r/rules/branches/main.json"
}
wall "both thresholds weakened to none is caught" "FC-E22 fail" "policy none none"
wall "the security threshold alone weakened is caught, and named alone" "FC-E22 fail" "policy errors critical"
wall "the alerts threshold alone weakened is caught, and named alone" "FC-E22 fail" "policy none high_or_higher"
wall "a weakened rule fails the run" "-- 1 failed" "policy none none"
wall "a weakened rule names where to repair it" "FC-E22 info" "policy none none"
wall "a weakened rule is caught even with the legacy check name also required" "FC-E22 fail" "policy none none"
wall "equal thresholds pass" "FC-E22 pass" "policy errors high_or_higher"
wall "stricter thresholds pass" "FC-E22 pass" "policy errors_and_warnings medium_or_higher"
wall "the strictest thresholds pass" "FC-E22 pass" "policy all all"
wall "a missing threshold field is not verified, not passed" "FC-E22 unknown" "jq -c '$strip_rule + [{\"type\":\"code_scanning\",\"parameters\":{\"code_scanning_tools\":[{\"tool\":\"CodeQL\",\"alerts_threshold\":\"errors\"}]},\"ruleset_source_type\":\"Repository\",\"ruleset_id\":1}]' <<<\"\$good_rules\" > \"$api/repos/o/r/rules/branches/main.json\""
wall "a missing threshold field is counted as not verified" "-- 0 failed, 2 not verified" "jq -c '$strip_rule + [{\"type\":\"code_scanning\",\"parameters\":{\"code_scanning_tools\":[{\"tool\":\"CodeQL\"}]},\"ruleset_source_type\":\"Repository\",\"ruleset_id\":1}]' <<<\"\$good_rules\" > \"$api/repos/o/r/rules/branches/main.json\""
wall "a threshold value GitHub does not document is not verified" "FC-E22 unknown" "policy severe high_or_higher"
wall "a legacy check name does not claim the thresholds" "FC-E22 unknown" "printf '%s' \"\$rules_name_only\" > \"$api/repos/o/r/rules/branches/main.json\""
wall "a legacy check name counts the thresholds as not verified" "-- 0 failed, 2 not verified" "printf '%s' \"\$rules_name_only\" > \"$api/repos/o/r/rules/branches/main.json\""
# Two rulesets both with a CodeQL rule: GitHub enforces every rule, so the
# strictest governs. A second, weaker ruleset is not a weakening.
# shellcheck disable=SC2016  # evaluated by wall(), where $r and $a expand
two='jq -c ". + [\$r]" --argjson r "$(rule_for CodeQL none none 2)" <<<"$good_rules" > "$api/repos/o/r/rules/branches/main.json"; printf "{\"bypass_actors\":[]}" > "$api/repos/o/r/rulesets/2.json"'
wall "a second ruleset with a weaker CodeQL rule is not a weakening" "FC-E22 pass" "$two"
wall "two rulesets, the strict one holds: nothing failed" "-- 0 failed, 1 not verified" "$two"
# shellcheck disable=SC2016  # evaluated by wall(), where $r and $a expand
two_weak='jq -c "$strip_rule + [\$a, \$b]" --argjson a "$(rule_for CodeQL none critical)" --argjson b "$(rule_for CodeQL errors none 2)" <<<"$good_rules" > "$api/repos/o/r/rules/branches/main.json"; printf "{\"bypass_actors\":[]}" > "$api/repos/o/r/rulesets/2.json"'
wall "two weak rulesets do not add up to the policy" "FC-E22 fail" "$two_weak"
# The rule is only as wide as the languages default setup analyses: enabled
# before detection it analysed `actions` alone while the wall said enforced
# (#120 finding I). Python missing is named with its fix; an unreadable setup
# (the Actions token in CI) is not verified, never a pass.
wall "the languages default setup analyses are reported" "FC-E23 pass"
wall "default setup without python is caught, with the fix" "FC-E23 warn" "printf '{\"state\":\"configured\",\"languages\":[\"actions\"]}' > \"$api/repos/o/r/code-scanning/default-setup.json\""
wall "the fix for a missing language is the one PATCH" "FC-E23 info" "printf '{\"state\":\"configured\",\"languages\":[\"actions\"]}' > \"$api/repos/o/r/code-scanning/default-setup.json\""
wall "unreadable default setup is SKIP, not a pass" "FC-E23 unknown" "rm \"$api/repos/o/r/code-scanning/default-setup.json\""
wall "unreadable default setup is counted as not verified" "-- 0 failed, 2 not verified" "rm \"$api/repos/o/r/code-scanning/default-setup.json\""
# Push protection (#303): GitHub refuses a push carrying a secret in a format
# it knows, where `ci / secrets` reports one only after it is on GitHub. The
# door turns it on; a repository the door did not make, or one where it was
# switched off, is named with the call that turns it on. A WARN, never a FAIL:
# `ci / floor-check` is a required check, and a repository that passed before
# this item existed still passes. Each state has its fixture; a token that
# does not get `security_and_analysis` is not verified, never a pass.
security() { # <json for security_and_analysis, or nothing to leave the key out> -- the repository as that token reads it
  printf '{%s%s}' "$repo_meta" "${1:+,\"security_and_analysis\":$1}" > "$api/repos/o/r.json"
}
pp_off='{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"disabled"}}'
wall "push protection on is a PASS" "FC-E09 pass"
wall "push protection off is a WARN" "FC-E09 warn" "security '$pp_off'"
wall "push protection on says who can push past it" "FC-E09 pass"
wall "push protection off says who could push past it once on" "FC-E09 info" "security '$pp_off'"
wall "push protection off carries the call that turns it on, and says what the call needs" \
  "FC-E09 info" "security '$pp_off'"
wall "push protection off never fails the floor, and is not counted as not verified" "-- 0 failed, 1 not verified" "security '$pp_off'"
wall "security settings the token does not get are SKIP, not a pass" "FC-E09 unknown" "security"
wall "security settings the token does not get are counted as not verified" "-- 0 failed, 2 not verified" "security"
wall "security settings GitHub answers as null are SKIP" "FC-E09 unknown" "security null"
wall "security settings without a push protection entry are SKIP, not read as off" "FC-E09 unknown" "security '{\"secret_scanning\":{\"status\":\"enabled\"}}'"
wall "a push protection status that is neither enabled nor disabled is SKIP" "FC-E09 unknown" "security '{\"secret_scanning_push_protection\":{\"status\":\"paused\"}}'"
wall "security settings that are not an object are SKIP, and not blamed on the token" "FC-E09 unknown" "security '[]'"
wall "a push protection entry that is not an object is SKIP, not a crash" "FC-E09 unknown" "security '{\"secret_scanning_push_protection\":\"enabled\"}'"
for state in "$pp_off" "" null '{"secret_scanning":{"status":"enabled"}}'; do
  security "$state"
  out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" 2>&1)"
  if [ "$(grep -cE '^  (PASS|WARN|FAIL|SKIP) +push protection' <<<"$out")" = 1 ] && ! grep -qE '^  (PASS|FAIL) +push protection' <<<"$out"; then ok "push protection ${state:-left out} gets one verdict, neither a PASS nor a FAIL"
  else bad "push protection ${state:-left out} got a PASS, a FAIL, or not exactly one verdict"; grep 'push protection' <<<"$out" | sed 's/^/        /'; fi
done
printf '%s' "$good_meta" > "$api/repos/o/r.json"
# The item belongs to the repository, not to the rules: it is reported where no
# rule governs the branch too.
wall "push protection is reported when the wall is down" "FC-E09 pass" "printf '[]' > \"$api/repos/o/r/rules/branches/main.json\""
# Private vulnerability reporting (#747): SECURITY.md names its form, which is
# off until turned on. On is a PASS, off a WARN with the call, unread a SKIP;
# a private repository is not offered it, and SECURITY.md names another route.
wall "private vulnerability reporting on is a PASS" "FC-E11 pass"
wall "private vulnerability reporting off is a WARN" "FC-E11 warn" "printf '{\"enabled\":false}' > \"$api/repos/o/r/private-vulnerability-reporting.json\""
wall "private vulnerability reporting off carries the call that turns it on" "FC-E11 info" "printf '{\"enabled\":false}' > \"$api/repos/o/r/private-vulnerability-reporting.json\""
wall "private vulnerability reporting unread is a SKIP, counted" "-- 0 failed, 2 not verified" "rm \"$api/repos/o/r/private-vulnerability-reporting.json\""
# With the Actions token an unanswered setting is left to the skill (#1103:
# every state a check declares is reached by a fixture).
rm "$api/repos/o/r/private-vulnerability-reporting.json"
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" --actions-token 2>&1)"
if is "$out" FC-E11 review; then ok "private vulnerability reporting unread with the Actions token is left to the skill"
else bad "private vulnerability reporting unread with the Actions token is left to the skill"; grep -i "vulnerability" <<<"$out" | sed 's/^/        /'; fi
printf '{"enabled":true}' > "$api/repos/o/r/private-vulnerability-reporting.json"
wall "private vulnerability reporting on a private repository is an INFO, not read" "FC-E11 info" "jq -c '. + {private: true}' <<<\"\$good_meta\" > \"$api/repos/o/r.json\"; rm \"$api/repos/o/r/private-vulnerability-reporting.json\""
# SECURITY.md's route against the repository (#747): an instance rendered
# before the template asked `visibility`, updated with --defaults, names the
# form on a private repository too. The must-not-pass direction first.
sec="$good/SECURITY.md"; cp "$sec" "$work/SECURITY.md.keep"
form_md="printf '# Security\\n\\n**Do not open a public issue.** Use the repository%ss private reporting form:\\n**Security → Report a vulnerability**\\n' \"'\" > \"$sec\""
issue_md="printf '# Security\\n\\nOpen an issue in this repository. It is private, so only people with access\\n' > \"$sec\""
private_meta="jq -c '. + {private: true}' <<<\"\$good_meta\" > \"$api/repos/o/r.json\""
route() { wall "$@"; cp "$work/SECURITY.md.keep" "$sec"; }
route "must not pass: a private repository whose SECURITY.md names the form is a WARN" "FC-E10 warn" "$form_md; $private_meta"
route "...with the update that re-renders it" "FC-E10 info" "$form_md; $private_meta"
route "a public repository whose SECURITY.md names an issue is a WARN" "FC-E10 warn" "$issue_md; jq -c '. + {private: false}' <<<\"\$good_meta\" > \"$api/repos/o/r.json\""
route "a route mismatch never fails the floor" "-- 0 failed, 1 not verified" "$form_md; $private_meta"
out="$(eval "$issue_md; $private_meta"; FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --expect-checks "ci / a, ci / b" 2>&1)"; cp "$work/SECURITY.md.keep" "$sec"; printf '%s' "$good_meta" > "$api/repos/o/r.json"
! grep -q "WARN  SECURITY.md" <<<"$out" && ok "a private repository whose SECURITY.md names an issue is not warned" || bad "a matching private route was warned"
out="$(eval "$form_md"; jq -c '. + {private: false}' <<<"$good_meta" > "$api/repos/o/r.json"; FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --expect-checks "ci / a, ci / b" 2>&1)"; cp "$work/SECURITY.md.keep" "$sec"; printf '%s' "$good_meta" > "$api/repos/o/r.json"
! grep -q "WARN  SECURITY.md" <<<"$out" && is "$out" FC-E11 pass && ok "a public repository whose SECURITY.md names the form is not warned" || bad "a matching public route was warned"
out="$(eval "$form_md"; printf '{"default_branch":"main"}' > "$api/repos/o/r.json"; FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --expect-checks "ci / a, ci / b" 2>&1)"; cp "$work/SECURITY.md.keep" "$sec"; printf '%s' "$good_meta" > "$api/repos/o/r.json"
! grep -q "WARN  SECURITY.md" <<<"$out" && ok "visibility the API does not report is not judged" || bad "a route was judged with no visibility read"
# The Actions allowlist (#747): a `uses:` the allowlist refuses ends its run in
# startup_failure with no job and no message. The must-not-pass case first: a
# workflow that uses one action the allowlist does not name is never reported
# as fine, and the WARN names it with the call that allows it.
rel="$good/.github/workflows/release.yml"; cp "$rel" "$work/release.yml.keep"
uses_pypi="printf 'jobs:\n  publish:\n    steps:\n      - uses: actions/checkout@%040d\n      - uses: pypa/gh-action-pypi-publish@%040d # v1\n' 0 0 > \"$rel\""
allow() { printf "printf '%%s' '{\"github_owned_allowed\":true,\"verified_allowed\":false,\"patterns_allowed\":%s}' > \"%s\"" "$1" "$api/repos/o/r/actions/permissions/selected-actions.json"; }
allowlist() { wall "$@"; cp "$work/release.yml.keep" "$rel"; }
allowlist "the door's allowlist lets the template's actions start" "FC-E27 pass"
out="$(eval "$uses_pypi"; FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --expect-checks "ci / a, ci / b" 2>&1)"; cp "$work/release.yml.keep" "$rel"
if ! grep -q "PASS  the Actions allowlist" <<<"$out" && is "$out" FC-E27 warn
then ok "must not pass: an allowlist missing one action is never reported as fine, and the action is named"
else bad "an allowlist missing one action was reported as fine, or the action was not named"; grep 'Actions allowlist' <<<"$out" | sed 's/^/        /'; fi
allowlist "the refusal carries the one call that allows it, keeping what is allowed, and says it needs administration" \
  "FC-E27 info" "$uses_pypi"
allowlist "a refused action never fails the floor" "-- 0 failed, 1 not verified" "$uses_pypi"
allowlist "an allowlist naming the action lets it start" "FC-E27 pass" "$uses_pypi; $(allow '["coolbress/plinth/*","pypa/gh-action-pypi-publish@*"]')"
allowlist "a pattern naming another action does not cover it" "FC-E27 warn" "$uses_pypi; $(allow '["coolbress/plinth/*","pypa/other@*"]')"
allowlist "a pattern pinned to another ref does not cover it" "FC-E27 warn" "$uses_pypi; $(allow '["coolbress/plinth/*","pypa/gh-action-pypi-publish@v1"]')"
allowlist "GitHub-owned actions are refused when github_owned_allowed is off" "FC-E27 warn" "$uses_pypi; printf '%s' '{\"github_owned_allowed\":false,\"patterns_allowed\":[\"coolbress/plinth/*\",\"pypa/gh-action-pypi-publish@*\"]}' > \"$api/repos/o/r/actions/permissions/selected-actions.json\""
allowlist "a patterns list that is not a list allows nothing" "FC-E27 warn" "$(allow '"coolbress/plinth/*"')"
allowlist "allowed_actions all lets everything start" "FC-E27 pass" "$uses_pypi; printf '{\"enabled\":true,\"allowed_actions\":\"all\"}' > \"$api/repos/o/r/actions/permissions.json\""
allowlist "allowed_actions local_only refuses every action from elsewhere" "FC-E27 warn" "printf '{\"enabled\":true,\"allowed_actions\":\"local_only\"}' > \"$api/repos/o/r/actions/permissions.json\""
allowlist "Actions turned off is a WARN" "FC-E27 warn" "printf '{\"enabled\":false,\"allowed_actions\":\"selected\"}' > \"$api/repos/o/r/actions/permissions.json\""
allowlist "Actions permissions the token does not read are a SKIP, not a pass" "FC-E27 unknown" "rm \"$api/repos/o/r/actions/permissions.json\""
allowlist "an allowlist the token does not read is a SKIP, counted" "-- 0 failed, 2 not verified" "rm \"$api/repos/o/r/actions/permissions/selected-actions.json\""
# A `!` pattern blocks what it matches (#756). GitHub's page gives examples
# but no order against the allowing patterns or github_owned_allowed, so a
# policy that carries one is not verified, never a PASS.
out="$(eval "$uses_pypi; $(allow '["coolbress/plinth/*","pypa/*","!pypa/gh-action-pypi-publish@*"]')"; FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --expect-checks "ci / a, ci / b" 2>&1)"; cp "$work/release.yml.keep" "$rel"; printf '%s' "$good_allow" > "$api/repos/o/r/actions/permissions/selected-actions.json"
if ! grep -q "PASS  the Actions allowlist" <<<"$out" && is "$out" FC-E27 unknown
then ok "must not pass: an allowlist whose ! pattern blocks a used action is never reported as fine, and the pattern is named"
else bad "an allowlist with a ! pattern was reported as fine, or the pattern was not named"; grep 'Actions allowlist' <<<"$out" | sed 's/^/        /'; fi
# Counted: the fixture's labels SKIP and the blocking pattern's.
allowlist "a ! pattern is counted as not verified, never failed" "-- 0 failed, 2 not verified" "$uses_pypi; $(allow '["coolbress/plinth/*","pypa/*","!pypa/gh-action-pypi-publish@*"]')"
allowlist "an action no pattern allows is still refused beside a ! pattern" "FC-E27 warn" "$uses_pypi; $(allow '["coolbress/plinth/*","!octo/x@*"]')"
allowlist "a docker image is not judged, a SKIP" "FC-E27 unknown" "printf 'jobs:\n  a:\n    steps:\n      - uses: docker://alpine@sha256:%064d\n' 0 > \"$rel\""
# A `uses` the line pattern does not read (flow style) could name a refused
# action: a SKIP naming the line, and never the all-actions PASS beside it.
uses_flow="printf 'jobs:\n  publish:\n    steps:\n      - uses: actions/checkout@%040d\n      - {uses: pypa/gh-action-pypi-publish@%040d}\n' 0 0 > \"$rel\""
out="$(eval "$uses_flow"; FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --expect-checks "ci / a, ci / b" 2>&1)"; cp "$work/release.yml.keep" "$rel"
if ! grep -q "PASS  the Actions allowlist" <<<"$out" && is "$out" FC-E27 unknown
then ok "must not pass: a uses the checker does not read is a SKIP naming its line, never the all-actions PASS"
else bad "a uses the checker does not read was passed over, or its line was not named"; grep 'Actions allowlist' <<<"$out" | sed 's/^/        /'; fi
# Counted: the allowlist's SKIP beside the pin check's and the plinth-pin lookup's on the same line, and the fixture's labels SKIP.
allowlist "a uses the checker does not read is counted as not verified" "-- 0 failed, 4 not verified" "$uses_flow"
allowlist "a readable refused action beside an unread one is still refused" "FC-E27 warn" "printf 'jobs:\n  publish:\n    steps:\n      - {uses: actions/checkout@%040d}\n      - uses: pypa/gh-action-pypi-publish@%040d\n' 0 0 > \"$rel\""
out="$(rm "$api/repos/o/r/actions/permissions.json"; FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --expect-checks "ci / a, ci / b" --actions-token 2>&1)"
printf '%s' "$good_perms" > "$api/repos/o/r/actions/permissions.json"
if is "$out" FC-E27 review && ! grep -qE "(PASS|SKIP)  the Actions allowlist" <<<"$out"; then ok "--actions-token: an unread allowlist is an INFO left to the skill"
else bad "--actions-token: an unread allowlist was not left to the skill"; grep 'Actions allowlist' <<<"$out" | sed 's/^/        /'; fi
# `ci / floor-check` runs on the Actions token, which never gets the security
# settings: a SKIP there is one no consumer can clear, in every run. The step
# passes --actions-token, and only the read that token cannot make changes: an
# INFO that says who reads it, outside the not-verified count. What the token
# does read is judged as ever, and so is every run without the flag: the
# skill, and the e2e runner, which reads the door's own work with it.
in_ci() { # <description> <expected substring> [json for security_and_analysis]
  security ${3+"$3"}
  local out; out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" --actions-token 2>&1)"
  local n want; n="$(grep -c '^  SKIP ' <<<"$out")"; want="${2##*failed, }"; want="${want%% *}"
  if sees "$out" "$2" -- "$2" && { [[ "$2" != "-- "*"not verified"* ]] || [ "$n" = "$want" ]; }; then ok "$1"
  else bad "$1 (expected '$2', SKIP lines=$n)"; grep -E 'push protection|failed' <<<"$out" | sed 's/^/        /'; fi
  printf '%s' "$good_meta" > "$api/repos/o/r.json"
}
in_ci "--actions-token: security settings the token does not get are an INFO naming who reads them" \
  "FC-E09 review"
in_ci "--actions-token: that INFO is not counted as not verified" "-- 0 failed, 1 not verified"
in_ci "--actions-token: null is the same unread answer" "FC-E09 review" null
in_ci "--actions-token: off is still a WARN when the token does read it" "FC-E09 warn" "$pp_off"
in_ci "--actions-token: on is still a PASS when the token does read it" "FC-E09 pass" '{"secret_scanning_push_protection":{"status":"enabled"}}'
in_ci "--actions-token: settings read but with no status are still a SKIP" "FC-E09 unknown" '{"secret_scanning":{"status":"enabled"}}'
in_ci "--actions-token: that SKIP is still counted" "-- 0 failed, 2 not verified" '{"secret_scanning":{"status":"enabled"}}'
security; out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" --actions-token 2>&1)"
printf '%s' "$good_meta" > "$api/repos/o/r.json"
if ! grep -qE '^  (PASS|SKIP) +push protection' <<<"$out"; then ok "--actions-token: the unread setting is neither a PASS nor a SKIP"
else bad "--actions-token: the unread setting printed a PASS or a SKIP"; grep 'push protection' <<<"$out" | sed 's/^/        /'; fi
# Who passes the flag is the whole of it: the CI step and nobody else. Each
# call is read out of the file that makes it, not copied here.
ci_call="$(awk '/python3 "\$RUNNER_TEMP\/plinth\/floor-check.py"/{f=1} f{print} f&&!/\\$/{exit}' "$root/.github/workflows/python-ci.yml")"
e2e_call="$(grep -E '^python3 "\$here/floor-check.py"' "$root/scripts/e2e.sh")"
skill_call="$(awk '/^python3 "\$\{CLAUDE_PLUGIN_ROOT\}\/scripts\/floor-check.py"/{f=1} f{print} f&&!/\\$/{exit}' "$root/skills/floor-check/SKILL.md")"
if [ -n "$ci_call" ] && grep -q -- '--actions-token' <<<"$ci_call"; then ok "python-ci.yml's floor-check step passes --actions-token"
else bad "python-ci.yml's floor-check step does not pass --actions-token (or its call was not found)"; fi
if [ -n "$e2e_call" ] && ! grep -q -- '--actions-token' <<<"$e2e_call"; then ok "scripts/e2e.sh calls the checker without --actions-token: its token administers the repository the door made, and the item is judged"
else bad "scripts/e2e.sh passes --actions-token, or its checker call was not found"; fi
if [ -n "$skill_call" ] && ! grep -q -- '--actions-token' <<<"$skill_call"; then ok "the skill's Run block calls the checker without --actions-token"
else bad "the skill's Run block passes --actions-token, or its call was not found"; fi

# Dependabot alerts, Dependabot security updates, secret scanning and registry
# token names (#1118): admin reads, each a WARN at most, left to the skill
# under --actions-token. The base fixture has all three on and nothing open.
va="$api/repos/o/r/vulnerability-alerts.json"; da="$api/repos/o/r/dependabot/alerts?state=open&per_page=100.json"
asf="$api/repos/o/r/automated-security-fixes.json"; ssa="$api/repos/o/r/secret-scanning/alerts?state=open&per_page=100&hide_secret=true.json"
admin_meta="{$repo_meta,\"permissions\":{\"admin\":true},\"security_and_analysis\":{\"secret_scanning\":{\"status\":\"enabled\"},\"secret_scanning_push_protection\":{\"status\":\"enabled\"}}}"
sec_reset() { printf '{}' > "$va"; printf '[]' > "$da"; printf '{"enabled":true,"paused":false}' > "$asf"; printf '[]' > "$ssa"; }
sr() { wall "$@"; sec_reset; }
sr "Dependabot alerts on with none open is a PASS" "FC-E31 pass"
sr "Dependabot alerts off, read by a login that administers the repository, is a WARN" "FC-E31 warn" \
  "rm \"$va\"; printf '%s' '$admin_meta' > \"$api/repos/o/r.json\""
sr "Dependabot alerts off carries the call that turns them on" "gh api -X PUT repos/o/r/vulnerability-alerts" \
  "rm \"$va\"; printf '%s' '$admin_meta' > \"$api/repos/o/r.json\""
sr "a 404 to a login not shown to administer the repository is not read as off" "FC-E31 unknown" "rm \"$va\""
sr "Dependabot alerts open are a WARN counted by severity" "2 open Dependabot alert(s) (1 critical, 1 high)" \
  "printf '[{\"state\":\"open\",\"security_advisory\":{\"severity\":\"high\"}},{\"state\":\"open\",\"security_vulnerability\":{\"severity\":\"critical\"}}]' > \"$da\""
sr "open Dependabot alerts are the row, not on" "FC-E31 warn" \
  "printf '[{\"state\":\"open\",\"security_advisory\":{\"severity\":\"low\"}}]' > \"$da\""
sr "open Dependabot alerts not read are a SKIP" "FC-E31 unknown" "printf 'x' > \"$da\""
sr "Dependabot security updates on is a PASS" "FC-E32 pass"
sr "Dependabot security updates off is a WARN" "FC-E32 warn" "printf '{\"enabled\":false,\"paused\":false}' > \"$asf\""
sr "Dependabot security updates off carries the call" "gh api -X PUT repos/o/r/automated-security-fixes" \
  "printf '{\"enabled\":false,\"paused\":false}' > \"$asf\""
sr "Dependabot security updates paused is a WARN" "FC-E32 warn" "printf '{\"enabled\":true,\"paused\":true}' > \"$asf\""
sr "Dependabot security updates not answered is a SKIP" "FC-E32 unknown" "rm \"$asf\""
sr "secret scanning on with no open alert is a PASS" "FC-E33 pass"
ss_open='[{"number":3,"state":"open","secret_type":"github_personal_access_token","secret_type_display_name":"GitHub Personal Access Token","secret":"ghp_THISVALUEMUSTNOTPRINT"},{"number":4,"state":"open","secret_type":"slack_api_token","secret":"xoxb-THISVALUEMUSTNOTPRINT"}]'
mkdir -p "$api/repos/o/r/secret-scanning/alerts/3" "$api/repos/o/r/secret-scanning/alerts/4"
printf '[{"type":"commit","details":{"path":"config/settings.py","start_line":3}}]' > "$api/repos/o/r/secret-scanning/alerts/3/locations.json"
printf '[{"type":"issue_comment","details":{"issue_comment_url":"https://api.github.com/x"}}]' > "$api/repos/o/r/secret-scanning/alerts/4/locations.json"
sr "open secret scanning alerts are the row, not on" "FC-E33 warn" "printf '%s' '$ss_open' > \"$ssa\""
sr "an open secret scanning alert is named by type and path" "GitHub Personal Access Token in config/settings.py" \
  "printf '%s' '$ss_open' > \"$ssa\""
sr "an alert found outside a file is named by where" "slack_api_token in an issue comment" "printf '%s' '$ss_open' > \"$ssa\""
printf '%s' "$ss_open" > "$ssa"
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" 2>&1)"
out_json="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" --format json 2>&1)"
sec_reset
if ! grep -q "THISVALUEMUSTNOTPRINT" <<<"$out$out_json"; then ok "an open secret scanning alert's value is printed nowhere, text or JSON"
else bad "an open secret scanning alert's value was printed"; fi
sr "open secret scanning alerts not read are a SKIP" "FC-E33 unknown" "printf 'x' > \"$ssa\""
sr "secret scanning off on a public repository is a WARN" "FC-E33 warn" \
  "security '{\"secret_scanning\":{\"status\":\"disabled\"},\"secret_scanning_push_protection\":{\"status\":\"disabled\"}}'"
sr "secret scanning off carries the call that turns it on" '"secret_scanning": {"status": "enabled"}' \
  "security '{\"secret_scanning\":{\"status\":\"disabled\"},\"secret_scanning_push_protection\":{\"status\":\"disabled\"}}'"
sr "secret scanning with no status in the settings is a SKIP" "FC-E33 unknown" "security '{\"secret_scanning_push_protection\":{\"status\":\"enabled\"}}'"
private_off="{$repo_meta,\"private\":true,\"security_and_analysis\":{\"secret_scanning\":{\"status\":\"disabled\"},\"secret_scanning_push_protection\":{\"status\":\"disabled\"}}}"
sr "secret scanning off on a private repository says the plan, not off" "FC-E33 info" \
  "printf '%s' '$private_off' > \"$api/repos/o/r.json\""
out="$(printf '%s' "$private_off" > "$api/repos/o/r.json"; FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" 2>&1)"
printf '%s' "$good_meta" > "$api/repos/o/r.json"
if ! is "$out" FC-E33 warn && grep -q "secret scanning is not on this private repository: it needs GitHub Secret Protection" <<<"$out"
then ok "secret scanning on a private repository without Secret Protection is no WARN, and names the product"
else bad "secret scanning on a private repository without Secret Protection"; grep -i "secret scanning" <<<"$out" | sed 's/^/        /'; fi
hidden_meta="{$repo_meta,\"private\":true,\"permissions\":{\"admin\":true}}"
for m in "$hidden_meta" "{$repo_meta}"; do
  out="$(printf '%s' "$m" > "$api/repos/o/r.json"; FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" 2>&1)"
  printf '%s' "$good_meta" > "$api/repos/o/r.json"
  if ! states "$out" | grep -q '^FC-E33 ' && states "$out" | grep -q '^FC-E09 unknown$'
  then ok "security settings not answered: push protection's SKIP says so once, and secret scanning adds no second line"
  else bad "security settings not answered: secret scanning"; grep -iE "secret scanning|push protection" <<<"$out" | sed 's/^/        /'; fi
done
# In ci / floor-check: unread, each is an INFO left to the skill, and the FAIL
# and SKIP counts are the ones a run without the new reads prints.
ci_run() { FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" --actions-token 2>&1; }
security; rm -f "$va" "$asf"
out="$(ci_run)"
sec_reset; printf '%s' "$good_meta" > "$api/repos/o/r.json"
if is "$out" FC-E31 review && is "$out" FC-E32 review && is "$out" FC-E09 review && ! states "$out" | grep -q '^FC-E33 '
then ok "--actions-token: Dependabot alerts and security updates unread are left to /plinth:floor-check; the security settings once, on push protection's line"
else bad "--actions-token: the settings unread"; grep -iE "dependabot|secret scanning|push protection" <<<"$out" | sed 's/^/        /'; fi
printf 'x' > "$ssa"; out_ss="$(ci_run)"; sec_reset
if is "$out_ss" FC-E33 review; then ok "--actions-token: secret scanning on with its open alerts unread is left to /plinth:floor-check"
else bad "--actions-token: open alerts unread"; grep -i "secret scanning" <<<"$out_ss" | sed 's/^/        /'; fi
# Their only lines there are those INFOs: no FAIL, WARN or SKIP of theirs, so
# the summary's failed and not-verified counts are as before (the golden test
# compares every recorded CI-form run line for line).
if ! states "$out" | grep -qE '^FC-E3[1-4] (fail|warn|unknown)$'; then ok "--actions-token: unread, the new reads print no FAIL, WARN or SKIP"
else bad "--actions-token: a new read printed a FAIL, WARN or SKIP"; states "$out" | grep '^FC-E3[1-4]' | sed 's/^/        /'; fi
# Registry token names beside OIDC (experimental): only when release.yml
# publishes through OIDC; names only.
oidc_rel='name: Release
on:
  push:
    tags: ["v*"]
permissions: {}
jobs:
  publish:
    permissions:
      id-token: write
    steps:
      - uses: pypa/gh-action-pypi-publish@7245906fb61fa33a13554f9d5fb856fe61758086 # v1.14.3
'
sec_api="$api/repos/o/r/actions/secrets?per_page=100.json"; env_api="$api/repos/o/r/environments?per_page=100.json"
mkdir -p "$api/repos/o/r/environments/pypi"
env_sec="$api/repos/o/r/environments/pypi/secrets?per_page=100.json"
cp "$rel" "$work/release.yml.keep2"
tok() { # <description> <expected> <repository secrets json> [environments json] [pypi environment secrets json] [flags]
  printf '%s' "$oidc_rel" > "$rel"; printf '%s' "$3" > "$sec_api"
  local no_envs='{"environments":[]}' no_secrets='{"secrets":[]}'
  printf '%s' "${4:-$no_envs}" > "$env_api"; printf '%s' "${5:-$no_secrets}" > "$env_sec"
  local out; out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" ${6:-} 2>&1)"
  if sees "$out" "$2" -F -- "$2"; then ok "$1"; else bad "$1"; grep -iE "secret|registry" <<<"$out" | sed 's/^/        /'; fi
  cp "$work/release.yml.keep2" "$rel"; rm -f "$sec_api" "$env_api" "$env_sec"
}
tok "OIDC publishing with no token-like secret is a PASS" "FC-E34 pass" '{"secrets":[{"name":"SLACK_WEBHOOK"}]}'
tok "OIDC publishing with a PyPI token secret is a WARN" "FC-E34 warn" '{"secrets":[{"name":"PYPI_API_TOKEN"}]}'
tok "the WARN names the secret and where" "PYPI_API_TOKEN (repository), TWINE_PASSWORD (environment pypi)" \
  '{"secrets":[{"name":"PYPI_API_TOKEN"}]}' '{"environments":[{"name":"pypi"}]}' '{"secrets":[{"name":"TWINE_PASSWORD"}]}'
tok "each named secret has its delete line" "gh secret delete TWINE_PASSWORD --repo o/r --env pypi" \
  '{"secrets":[]}' '{"environments":[{"name":"pypi"}]}' '{"secrets":[{"name":"TWINE_PASSWORD"}]}'
tok "a token for another registry than the one OIDC publishes to is not named" "FC-E34 pass" \
  '{"secrets":[{"name":"DOCKER_REGISTRY_TOKEN"},{"name":"NPM_TOKEN"}]}'
tok "a list longer than the page read is a SKIP, not a pass" "FC-E34 unknown" \
  '{"total_count":120,"secrets":[{"name":"SLACK_WEBHOOK"}]}'
tok "more environments than the page read is a SKIP, not a pass" "FC-E34 unknown" \
  '{"secrets":[]}' '{"total_count":101,"environments":[{"name":"pypi"}]}'
tok "secret names not listed are a SKIP naming the permission" "FC-E34 unknown" 'x'
tok "an environment's secrets not listed are a SKIP" "FC-E34 unknown" '{"secrets":[]}' '{"environments":[{"name":"pypi"}]}' 'x'
tok "--actions-token: secret names not listed are left to the skill" "FC-E34 review" 'x' "" "" --actions-token
printf '%s' '{"secrets":[{"name":"PYPI_API_TOKEN"}]}' > "$sec_api"
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" 2>&1)"
rm -f "$sec_api"
if ! grep -q "registry token" <<<"$out"; then ok "a release.yml that does not publish through OIDC: no registry token line"
else bad "registry token line without OIDC"; fi

# A private repository's wall is read against what its licences allow (#351,
# decided in #320): the code_scanning rule is expected only where GitHub Code
# Security is enabled on the repository, push protection only where GitHub
# Secret Protection is. A product that is off is an INFO naming the gap and
# what stands in its place, neither a FAIL nor a PASS; a licence state the API
# does not answer is not verified. Only `"private": true` changes anything: a
# repository whose answer carries no such key is read as before.
private() { # <json for security_and_analysis, or nothing to leave the key out> <rules json> [checker args...] -- sets out, rc
  local settings="${1:-}" rules="$2"; shift 2
  printf '{%s,"private":true%s}' "$repo_meta" "${settings:+,\"security_and_analysis\":$settings}" > "$api/repos/o/r.json"
  printf '%s' "$rules" > "$api/repos/o/r/rules/branches/main.json"
  out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" "$@" 2>&1)"; rc=$?
  printf '%s' "$good_meta" > "$api/repos/o/r.json"; printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"
}
has()  { if sees "$out" "$2" -E -- "$2"; then ok "$1"; else bad "$1 (expected a line matching '$2')"; grep -E 'CodeQL|push protection|failed' <<<"$out" | sed 's/^/        /'; fi; }
lacks() { if ! grep -qE -- "$2" <<<"$out"; then ok "$1"; else bad "$1 (a line matches '$2')"; grep -E -- "$2" <<<"$out" | sed 's/^/        /'; fi; }
counted() { # <description> <fails> <not verified> <exit code>
  if [ "$rc" = "$4" ] && grep -q -- "^-- $2 failed, $3 not verified" <<<"$out" && [ "$(grep -c '^  SKIP ' <<<"$out")" = "$3" ] && [ "$(grep -c '^  FAIL ' <<<"$out")" = "$2" ]; then ok "$1"
  else bad "$1 (rc=$rc, expected exit $4 and '-- $2 failed, $3 not verified')"; grep -E 'FAIL|SKIP|failed' <<<"$out" | sed 's/^/        /'; fi
}
sec() { # <code security status|-> <secret scanning status|-> <push protection status|-> [key for the first: code_security]
  jq -cn --arg c "$1" --arg s "$2" --arg p "$3" --arg k "${4:-code_security}" \
    '[{key: $k, value: $c}, {key: "secret_scanning", value: $s}, {key: "secret_scanning_push_protection", value: $p}]
     | map(select(.value != "-") | .value = {status: .value}) | from_entries'
}
# Without either product, and without the rule: the gaps are named, nothing fails.
private "$(sec disabled disabled disabled)" "$rules_neither"
has   "private, no Code Security, no rule: an INFO names the gap" "FC-E21 info"
has   "private, no Code Security: the INFO names what stands in its place" "FC-E21 info"
lacks "private, no Code Security, no rule: CodeQL gets neither a FAIL nor a PASS nor a SKIP" '^  (FAIL|PASS|SKIP|WARN) .*(CodeQL|code_scanning)'
has   "private, no Secret Protection: an INFO names the gap and what stands in its place" "FC-E09 info"
lacks "private, no Secret Protection: push protection gets neither a WARN nor a PASS nor a SKIP" '^  (FAIL|PASS|SKIP|WARN) +push protection'
lacks "private, no Secret Protection: no call that would turn on a product that is not there" 'gh api -X PATCH repos/o/r --input'
counted "private without either product: nothing fails, and the two gaps are not counted as not verified" 0 1 0
has   "private: the required check names are expected as on a public repository" "FC-E19 pass"
has   "private: the other rules are expected as on a public repository" "FC-E15 pass"
rm "$api/repos/o/r/code-scanning/default-setup.json"
private "$(sec disabled disabled disabled)" "$rules_neither"
printf '%s' "$good_setup" > "$api/repos/o/r/code-scanning/default-setup.json"
counted "private, no Code Security: default setup, which cannot exist there, is not read and not counted" 0 1 0
# The rest of the wall is still a FAIL on a private repository.
private "$(sec disabled disabled disabled)" "$(jq -c 'map(if .type=="required_status_checks" then .parameters.required_status_checks |= map(select(.context!="ci / a")) else . end)' <<<"$rules_neither")"
has   "private: a dropped required check is still a FAIL" "FC-E19 fail"
counted "private: a dropped required check still fails the run" 1 1 1
# A private repository on a plan without GitHub Secret Protection answers no
# security settings at all, even to a login that administers it (measured on
# a private test repository of a personal account, #811). That is not the
# token's fault: its own SKIP, never a PASS, and not the token line.
admin_null() { # <admin: true|false>
  printf '{%s,"private":true,"permissions":{"admin":%s}}' "$repo_meta" "$1" > "$api/repos/o/r.json"
  out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" 2>&1)"; rc=$?
  printf '%s' "$good_meta" > "$api/repos/o/r.json"
}
admin_null true
has   "private, no settings answered to an administrator: a SKIP naming the plan, not the token" "FC-E09 unknown"
lacks "private, no settings answered to an administrator: not blamed on the token" 'push protection not verified \(this token does not read'
lacks "private, no settings answered to an administrator: never a PASS" '^  PASS +push protection'
admin_null false
has   "private, no settings answered to a login that does not administer it: the token line" "FC-E09 unknown"
# A token that does not get the settings is one the person can change: plain
# not verified, never marked as not readable here (#1002).
lacks "private, settings not got by a non-admin token: not marked as not readable here" 'cannot be read here'
admin_null true
has   "private, no settings answered to an administrator: push protection is marked as not readable here" "FC-E09 unknown"
has   "private, no settings answered to an administrator: the last line counts it apart" '^-- 0 failed, [0-9]+ not verified \(1 cannot be read here\)$'
# The same plan without the rule and without a readable default setup: the
# CodeQL rule and its languages are GitHub statuses that plan does not expose.
printf '{%s,"private":true,"permissions":{"admin":true}}' "$repo_meta" > "$api/repos/o/r.json"
printf '%s' "$rules_neither" > "$api/repos/o/r/rules/branches/main.json"; rm "$api/repos/o/r/code-scanning/default-setup.json"
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" 2>&1)"; rc=$?
printf '%s' "$good_meta" > "$api/repos/o/r.json"; printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"
printf '%s' "$good_setup" > "$api/repos/o/r/code-scanning/default-setup.json"
has   "private, no settings answered to an administrator, no rule: CodeQL is marked as not readable here" "FC-E21 unknown"
has   "private, no settings answered to an administrator, no rule: its place is named" "FC-E21 unknown"
has   "private, no settings answered to an administrator: the default setup languages are marked as not readable here" "FC-E23 unknown"
has   "private, no settings answered to an administrator, no rule: three counted apart" '^-- 0 failed, [0-9]+ not verified \(3 cannot be read here\)$'
if [ "$rc" = 0 ]; then ok "private, no settings answered to an administrator, no rule: the run does not fail"; else bad "the run failed (rc=$rc)"; fi
# With the rule in place Code Security is there, so a default setup read that
# failed is one a re-run can clear: plain not verified (#1002 review).
printf '{%s,"private":true,"permissions":{"admin":true}}' "$repo_meta" > "$api/repos/o/r.json"
printf 'not json' > "$api/repos/o/r/code-scanning/default-setup.json"
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" 2>&1)"; rc=$?
printf '%s' "$good_meta" > "$api/repos/o/r.json"; printf '%s' "$good_setup" > "$api/repos/o/r/code-scanning/default-setup.json"
has   "private, no settings answered to an administrator, rule in place: a failed default setup read is plain not verified" "FC-E23 unknown"
has   "private, no settings answered to an administrator, rule in place: only push protection counted apart" '^-- 0 failed, [0-9]+ not verified \(1 cannot be read here\)$'
# A fine-grained token without the Administration permission gets the same
# empty answer from GitHub as a plan without the products, and plinth has the
# agent work with such a token after the first merge (#1002 review). Unless
# the token is shown to read an admin-only setting (actions/permissions), the
# SKIPs stay plain not verified and the fix line names a token with it.
printf '{%s,"private":true,"permissions":{"admin":true}}' "$repo_meta" > "$api/repos/o/r.json"
printf '%s' "$rules_neither" > "$api/repos/o/r/rules/branches/main.json"
rm "$api/repos/o/r/code-scanning/default-setup.json" "$api/repos/o/r/actions/permissions.json"
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" 2>&1)"; rc=$?
printf '%s' "$good_meta" > "$api/repos/o/r.json"; printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"
printf '%s' "$good_setup" > "$api/repos/o/r/code-scanning/default-setup.json"; printf '%s' "$good_perms" > "$api/repos/o/r/actions/permissions.json"
lacks "fine-grained token without Administration: nothing is marked as not readable here" 'cannot be read here'
has   "fine-grained token without Administration: push protection is plain not verified, naming the token" "FC-E09 unknown"
has   "fine-grained token without Administration: CodeQL is plain not verified, naming the token" "FC-E21 unknown"
has   "fine-grained token without Administration: the default setup languages are plain not verified" "FC-E23 unknown"
has   "fine-grained token without Administration: the fix line names a token with it" '^  INFO    run /plinth:floor-check again with a token that has the Administration permission'
if [ "$rc" = 0 ]; then ok "fine-grained token without Administration: the run does not fail"; else bad "the run failed (rc=$rc)"; fi
# With the licence, a missing rule is the defect it is on a public repository.
for key in code_security advanced_security; do
  private "$(sec enabled enabled enabled "$key")" "$rules_neither"
  has     "private, $key enabled, no rule: FAIL, as for a public repository" "FC-E21 fail"
  counted "private, $key enabled, no rule: the run fails" 1 1 1
done
private '{"code_security":{"status":"disabled"},"advanced_security":{"status":"enabled"}}' "$rules_neither"
has   "private, one licence off and the other on: on is what counts, the missing rule is a FAIL" "FC-E21 fail"
private "$(sec enabled enabled enabled)" "$rules_other_tool"
has   "private with Code Security: a code_scanning rule for another tool is still a FAIL" "FC-E21 fail"
private "$(sec enabled enabled enabled)" "$good_rules"
has   "private with Code Security and the rule: PASS" "FC-E21 pass"
has   "private with Secret Protection and push protection on: PASS" "FC-E09 pass"
counted "private with both products and the whole wall: as an intact public wall" 0 1 0
# A licence state the API does not answer is not verified, never a pass and
# never the gap line: the gap is said only where GitHub said `disabled`.
unread_codeql() { # <description> <json for security_and_analysis, or nothing> <reason in the SKIP>
  private "$2" "$rules_neither"
  has   "$1: CodeQL is not verified" "FC-E21 unknown"
  lacks "$1: no PASS, no FAIL and no gap line for CodeQL" '^  (PASS|FAIL) .*CodeQL (enforced|not enforced)|CodeQL is not expected here'
  if [ "$rc" = 0 ]; then ok "$1: the run does not fail"; else bad "$1: the run failed (rc=$rc)"; fi
}
unread_codeql "private, security settings the token does not get" "" "this token does not read the repository's security settings"
counted "private, unread security settings, no rule: CodeQL and push protection are both counted as not verified" 0 3 0
unread_codeql "private, security settings answered as null" null "this token does not read the repository's security settings"
unread_codeql "private, security settings with no Code Security entry" "$(sec - enabled enabled)" "GitHub reports no Code Security status for this repository"
unread_codeql "private, a Code Security status that is neither enabled nor disabled" "$(sec pending enabled enabled)" "GitHub reports no Code Security status"
unread_codeql "private, security settings that are not an object" '[]' "GitHub reports no Code Security status"
unread_codeql "private, a Code Security entry that is not an object" '{"code_security":"disabled"}' "GitHub reports no Code Security status"
# The rule itself is read from the rules, whatever the licence read says.
private "" "$good_rules"
has   "private, unread security settings, the rule present: PASS from the rule" "FC-E21 pass"
# `ci / floor-check` reads a private repository with the Actions token, which
# never gets the licence state. A SKIP there is one no consumer can clear, in
# every run of every private repository without the rule, and it buys
# nothing: with or without the licence the run cannot fail the item. So with
# --actions-token the unread settings are an INFO outside the count, naming
# the run that does judge it, as for push protection (#351's Decisions). It
# does not fail the run, so a private repository made without the rule can
# merge. Only the read that token cannot make changes: settings it did read
# are judged as ever, and so is every run without the flag.
private "" "$rules_neither" --actions-token
has     "--actions-token, private, no rule: an INFO names the run that judges the licence state" "FC-E21 review"
lacks   "--actions-token, private, no rule: CodeQL gets no PASS, FAIL, SKIP or gap line" '^  (PASS|FAIL|SKIP|WARN) .*CodeQL (enforced|not enforced|not verified)|CodeQL is not expected here'
has     "--actions-token, private: push protection is still the INFO naming who reads it" "FC-E09 review"
counted "--actions-token, private, no rule: outside the not-verified count, exit 0" 0 1 0
private null "$rules_neither" --actions-token
has     "--actions-token, private, null security settings: the same unread answer" "FC-E21 review"
# Outside the not-verified count is not off the summary line (#436): a reader
# of that line alone learns that the run left those two reads unread, and
# which run reads them. Without the flag they are the two SKIPs they are, and
# the line has no third part. The exit code is the FAIL count's alone.
private "" "$rules_neither" --actions-token
has     "--actions-token, private, both settings unread: the summary counts them as left to /plinth:floor-check" '^-- 0 failed, 1 not verified, 2 left to /plinth:floor-check$'
counted "--actions-token, private, both settings unread: the not-verified count and the exit code do not move" 0 1 0
private "" "$rules_neither"
has     "private, both settings unread, no flag: no third part on the summary line" '^-- 0 failed, 3 not verified$'
counted "private, both settings unread, no flag: both are SKIPs, exit 0" 0 3 0
private "$(sec enabled enabled enabled)" "$rules_neither" --actions-token
has     "--actions-token, private, settings read: nothing left, no third part, even when the run fails" '^-- 1 failed, 1 not verified$'
# The verdict lines `ci / floor-check` opens its job summary with (#437):
# --verdicts writes one line per FAIL, per SKIP and per read left to the
# skill, in the three forms of required-checks.md, or one pass line for a
# run without a FAIL. The step adds the `::warning::` for each not yet
# confirmed; the file holds the lines alone, in the order the checker found them.
v="$work/verdicts"; rm -f "$v"
private "" "$rules_neither" --actions-token --verdicts "$v"
if [ "$(grep -c . "$v")" = 4 ] && [ "$(head -1 "$v")" = "pass: the floor, no FAIL in what this run read" ] \
  && [ "$(grep -c '^not yet confirmed: ' "$v")" = 3 ] && ! grep -qvE '^(pass|not yet confirmed): ' "$v"; then
  ok "--verdicts: a pass line, then one not yet confirmed per SKIP and per read left to /plinth:floor-check (1 + 2)"
else bad "--verdicts: expected 4 lines (1 pass, 3 not yet confirmed)"; sed 's/^/        /' "$v"; fi
in_v()  { if grep -qE -- "$2" "$v"; then ok "$1"; else bad "$1 (expected a line in --verdicts matching '$2')"; sed 's/^/        /' "$v"; fi; }
in_v    "--verdicts: the left-to-the-skill read keeps the checker's own why and judge" '^not yet confirmed: push protection is not read here: .*/plinth:floor-check reads it'
in_v    "--verdicts: a SKIP keeps its own why and says what confirms it" '^not yet confirmed: .*not verified.*; run /plinth:floor-check where it can read this: https://.*#report$'
rm -f "$v"; private "$(sec enabled enabled enabled)" "$rules_neither" --actions-token --verdicts "$v"
in_v    "--verdicts: a FAIL is a fail line" '^fail: main: CodeQL not enforced'
if ! grep -q '^pass: ' "$v"; then ok "--verdicts: no pass line beside a FAIL"; else bad "--verdicts: a pass line beside a FAIL"; fi
rm -f "$v"; private "" "$rules_neither" --actions-token
if [ ! -e "$v" ]; then ok "without --verdicts no file is written"; else bad "without --verdicts a verdict file was written"; fi
# As that token reads such a repository: no default setup either. That SKIP
# is the one a public repository's CI run carries too.
rm "$api/repos/o/r/code-scanning/default-setup.json"
private "" "$rules_neither" --actions-token
printf '%s' "$good_setup" > "$api/repos/o/r/code-scanning/default-setup.json"
counted "--actions-token, private, no rule, default setup unreadable: exit 0, nothing added to not verified" 0 1 0
has     "--actions-token, private, no rule, default setup unreadable: an INFO left to /plinth:floor-check (#441)" "FC-E23 review"
has     "--actions-token, private, no rule, default setup unreadable: three reads left to /plinth:floor-check" '^-- 0 failed, 1 not verified, 3 left to /plinth:floor-check$'
# What the token did read is judged with the flag as without it.
private "$(sec enabled enabled enabled)" "$rules_neither" --actions-token
has     "--actions-token, private, Code Security read as enabled, no rule: still a FAIL" "FC-E21 fail"
counted "--actions-token, private, Code Security read as enabled, no rule: the run fails" 1 1 1
private "$(sec disabled disabled disabled)" "$rules_neither" --actions-token
has     "--actions-token, private, Code Security read as disabled: still the gap line" "FC-E21 info"
private "$(sec - enabled enabled)" "$rules_neither" --actions-token
has     "--actions-token, private, settings read but no Code Security status: still a SKIP" "FC-E21 unknown"
counted "--actions-token, private, settings read but no Code Security status: still counted" 0 2 0
private "" "$good_rules" --actions-token
has     "--actions-token, private, the rule present: PASS from the rule" "FC-E21 pass"
# A public repository is not relaxed by the flag: the missing rule fails in CI as before.
printf '{%s}' "$repo_meta" > "$api/repos/o/r.json"; printf '%s' "$rules_neither" > "$api/repos/o/r/rules/branches/main.json"
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" --actions-token 2>&1)"; rc=$?
printf '%s' "$good_meta" > "$api/repos/o/r.json"; printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"
has     "--actions-token, not private, unread settings, no rule: FAIL, as before" "FC-E21 fail"
lacks   "--actions-token, not private: no line that defers the judgement" 'CodeQL is not judged here'
counted "--actions-token, not private, no rule: the run fails" 1 1 1
# Push protection on a private repository: expected only with Secret Protection.
private "$(sec enabled enabled disabled)" "$good_rules"
has   "private with Secret Protection, push protection off: WARN, as for a public repository" "FC-E09 warn"
has   "private with Secret Protection, push protection off: the call that turns it on" "FC-E09 info"
private "$(sec enabled disabled -)" "$good_rules"
has   "private, no Secret Protection, no push protection entry: the gap, from the licence GitHub did answer" "FC-E09 info"
counted "private, no Secret Protection, no push protection entry: not counted as not verified" 0 1 0
private "$(sec enabled - disabled)" "$good_rules"
has   "private, push protection off and no secret scanning status: not verified" "FC-E09 unknown"
lacks "private, push protection off and no secret scanning status: neither a WARN nor a PASS nor the gap line" '^  (WARN|PASS) +push protection|push protection is not expected here'
private "$(sec enabled disabled enabled)" "$good_rules"
has   "private, push protection answered on: PASS, whatever the secret scanning status says" "FC-E09 pass"
# Public repositories: read as before. `private` false, absent or not a
# boolean never relaxes anything, whatever the licence entries say.
public() { # <description> <json fragment for the private key, or nothing>
  printf '{%s%s,"security_and_analysis":%s}' "$repo_meta" "${2:+,$2}" "$(sec disabled disabled disabled)" > "$api/repos/o/r.json"
  printf '%s' "$rules_neither" > "$api/repos/o/r/rules/branches/main.json"
  out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" 2>&1)"; rc=$?
  printf '%s' "$good_meta" > "$api/repos/o/r.json"; printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"
  has     "$1, no rule: FAIL" "FC-E21 fail"
  has     "$1, push protection off: WARN" "FC-E09 warn"
  lacks   "$1: no gap line" 'is not expected here'
  counted "$1: the run fails" 1 1 1
}
public "public (\"private\": false)" '"private":false'
public "no private key in the answer" ""
public "a private key that is not a boolean" '"private":"true"'
public "a private key answered as null" '"private":null'

# The Actions token reads none of the four settings below, in any consumer's
# run (#440): push protection, the ruleset's bypass actors, the CodeQL default
# setup languages and the squash commit settings. With --actions-token each is
# an INFO left to /plinth:floor-check, outside the not-verified count, and its
# verdict line ends with a fixed phrase the CI step reads so as not to annotate
# it (#441). Without the flag they are the SKIPs they always were.
unread_four() { # [checker args...] -- a public repository whose four settings are unread; sets out, rc
  printf '{"default_branch":"main"}' > "$api/repos/o/r.json"; printf '{}' > "$api/repos/o/r/rulesets/1.json"
  rm "$api/repos/o/r/code-scanning/default-setup.json"
  # Every label the door makes, so that the labels read is no SKIP here.
  grep -vE '^[[:space:]]*(#|$)' "$root/labels.txt" | cut -d'|' -f1 | jq -R '{name: .}' | jq -s . > "$api/repos/o/r/labels?per_page=100.json"
  out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" "$@" 2>&1)"; rc=$?
  rm "$api/repos/o/r/labels?per_page=100.json"
  printf '%s' "$good_meta" > "$api/repos/o/r.json"; printf '{"bypass_actors":[]}' > "$api/repos/o/r/rulesets/1.json"
  printf '%s' "$good_setup" > "$api/repos/o/r/code-scanning/default-setup.json"
}
v="$work/verdicts"; rm -f "$v"
unread_four --actions-token --verdicts "$v"
has     "--actions-token, four settings unread: all four are left to /plinth:floor-check, none is not verified" '^-- 0 failed, 0 not verified, 4 left to /plinth:floor-check$'
counted "--actions-token, four settings unread: no SKIP, exit 0" 0 0 0
has     "--actions-token: unread bypass actors are an INFO naming who reads them" "FC-E24 review"
has     "--actions-token: unread default setup languages are an INFO naming who reads them" "FC-E23 review"
has     "--actions-token: unread squash settings are an INFO naming who reads them" "FC-E08 review"
if [ "$(grep -c '; left to /plinth:floor-check$' "$v")" = 4 ] && [ "$(grep -c '^not yet confirmed: .*; left to /plinth:floor-check$' "$v")" = 4 ]; then
  ok "--verdicts: the four reads are not yet confirmed lines ending '; left to /plinth:floor-check'"
else bad "--verdicts: expected four not yet confirmed lines ending '; left to /plinth:floor-check'"; sed 's/^/        /' "$v"; fi
rm -f "$v"; unread_four --verdicts "$v"
has     "no flag, four settings unread: four SKIPs, no third part" '^-- 0 failed, 4 not verified$'
counted "no flag, four settings unread: all four are counted as not verified, exit 0" 0 4 0
if ! grep -q 'left to /plinth:floor-check' "$v"; then ok "no flag: no verdict line ends '; left to /plinth:floor-check'"
else bad "no flag: a verdict line is marked left to /plinth:floor-check"; sed 's/^/        /' "$v"; fi

# Through gh: on the owner's machine the token is in gh's keychain, not the
# environment, and only that token sees bypass actors. A mock gh serves the
# fixture (404 for what is not there); no FLOOR_CHECK_API_DIR, so the checker
# has to go through it.
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<MOCK
#!/usr/bin/env bash
printf 'gh %s\n' "\$*" >> "$work/gh-calls.log"
f="$api/\$(printf '%s' "\$2" | sed 's/?.*//').json"
[ -f "\$f" ] && cat "\$f" || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
MOCK
chmod +x "$work/bin/gh"
printf '{"bypass_actors":[{"actor_id":5,"actor_type":"RepositoryRole"}]}' > "$api/repos/o/r/rulesets/1.json"
out="$(PATH="$work/bin:$PATH" python3 "$checker" --root "$good" --repo o/r --expect-checks "ci / a, ci / b" 2>&1)"
# The negative half is about the ruleset read, not about every SKIP in the run:
# other checks legitimately say "not verified" when their fixture is absent.
if is "$out" FC-E24 fail && ! grep -q "bypass actors not visible" <<<"$out"; then ok "the API is read through gh when it is installed (bypass actors seen, 404 is absent)"
else bad "gh path"; printf '%s\n' "$out" | grep -E 'FAIL|INFO' | sed 's/^/        /'; fi
printf '{"bypass_actors":[]}' > "$api/repos/o/r/rulesets/1.json"

# Labels: names only, never a FAIL, paginated, and silent about what it could
# not read. `ci / floor-check` passes --repo in every consumer's CI, so a FAIL
# here would block merges over a label (#84).
mkdir -p "$api/repos/o/r"
# One page of the door's own list, minus two, plus GitHub's defaults: the reply
# is deliberately larger than one API page would hold.
python3 - "$root/labels.txt" > "$api/repos/o/r/labels.json" <<'PYEOF'
import json, sys, pathlib
want = [l.split("|")[0] for l in pathlib.Path(sys.argv[1]).read_text().splitlines()
        if l.strip() and not l.lstrip().startswith("#")]
have = [n for n in want if n not in ("spec", "wayfinder:task")]
have += ["bug", "documentation", "duplicate", "enhancement", "good first issue",
         "help wanted", "invalid", "question", "accessibility"]
print(json.dumps([{"name": n} for n in have]))
PYEOF
: > "$work/gh-calls.log"
out="$(PATH="$work/bin:$PATH" python3 "$checker" --root "$good" --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" 2>&1)"; rc=$?
if grep -q "WARN  labels the door creates that are missing: spec, wayfinder:task" <<<"$out" \
  || is "$out" FC-E05 warn
then ok "the two missing labels are named, and only those"
else bad "missing labels"; printf '%s\n' "$out" | grep -i label | sed 's/^/        /'; fi
if is "$out" FC-E05 info
then ok "each missing label carries the one command that creates it"
else bad "no fix line"; printf '%s\n' "$out" | grep -i "label create" | sed 's/^/        /'; fi
if ! grep -q "FAIL.*label" <<<"$out"; then ok "a missing label is never a FAIL"
else bad "a missing label produced a FAIL"; fi
# Every read answered (wall, bypass actors, labels): nothing is counted. A count
# that includes a passed item is the defect in the other direction.
if grep -qx -- "-- 0 failed, 0 not verified" <<<"$out" && ! grep -q '^  SKIP ' <<<"$out"; then ok "a run whose every read was answered counts 0 not verified, and says so"
else bad "a fully read run still counts something as not verified"; printf '%s\n' "$out" | grep -E 'SKIP|failed' | sed 's/^/        /'; fi
# GitHub answers Dependabot alerts on with a 204 and no body: through gh, an
# empty answer is read as on, not as an error (#1118).
: > "$api/repos/o/r/vulnerability-alerts.json"
out_204="$(PATH="$work/bin:$PATH" python3 "$checker" --root "$good" --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" 2>&1)"
printf '{}' > "$api/repos/o/r/vulnerability-alerts.json"
if is "$out_204" FC-E31 pass; then ok "through gh, a 204 with no body reads Dependabot alerts as on"
else bad "through gh, a 204 with no body"; grep -i dependabot <<<"$out_204" | sed 's/^/        /'; fi
# `gh api --paginate` prints one JSON array per page, one after another
# (#1247 review): every page is read, not taken for an error.
python3 - "$api/repos/o/r" <<'PYEOF'
import json, sys
d = sys.argv[1]
page = lambda n, sev: json.dumps([{"state": "open", "security_advisory": {"severity": sev}}] * n)
open(f"{d}/dependabot/alerts.json", "w").write(page(100, "high") + "\n" + page(1, "critical") + "\n")
alerts = [{"number": 7, "state": "open", "secret_type": "slack_api_token"}]
open(f"{d}/secret-scanning/alerts.json", "w").write(json.dumps(alerts * 100) + json.dumps(alerts))
PYEOF
mkdir -p "$api/repos/o/r/secret-scanning/alerts/7"; printf '[{"type":"commit","details":{"path":"a.py"}}]' > "$api/repos/o/r/secret-scanning/alerts/7/locations.json"
out_pages="$(PATH="$work/bin:$PATH" python3 "$checker" --root "$good" --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" 2>&1)"
printf '[]' > "$api/repos/o/r/dependabot/alerts.json"; printf '[]' > "$api/repos/o/r/secret-scanning/alerts.json"
if is "$out_pages" FC-E31 warn && grep -qF "101 open Dependabot alert(s) (1 critical, 100 high)" <<<"$out_pages"
then ok "through gh, two pages of Dependabot alerts are both counted"
else bad "through gh, two pages of Dependabot alerts"; grep -i dependabot <<<"$out_pages" | sed 's/^/        /'; fi
if is "$out_pages" FC-E33 warn && grep -qF "101 open secret scanning alert(s)" <<<"$out_pages"
then ok "through gh, two pages of secret scanning alerts are both counted"
else bad "through gh, two pages of secret scanning alerts"; grep -i "secret scanning" <<<"$out_pages" | sed 's/^/        /'; fi
if grep -q -- "--paginate" "$work/gh-calls.log"; then ok "the label read is paginated (30 per page would report labels missing that are there)"
else bad "the label read is not paginated"; sed 's/^/        /' "$work/gh-calls.log"; fi
# The exit code is the property that keeps consumers merging; lock it.
rm -f "$api/repos/o/r/labels.json"
out2="$(PATH="$work/bin:$PATH" python3 "$checker" --root "$good" --no-network 2>&1)"; rc2=$?
if grep -q "SKIP.*labels not verified" <<<"$out2" || ! grep -qi "label the door\|labels the door" <<<"$out2"
then ok "offline, labels are not verified rather than reported missing"
else bad "offline labels"; printf '%s\n' "$out2" | grep -i label | sed 's/^/        /'; fi
[ "$rc2" = 0 ] || bad "the offline floor stopped passing"
[ "$rc" = 0 ] && ok "a repository missing labels still exits 0" || bad "missing labels changed the exit code (rc=$rc)"

# --sandbox reads this machine's Claude Code settings. /sandbox on Claude Code
# 2.1.278 writes no sandbox.enabled (#222), so a missing or false key cannot say
# "off": it is not verified (SKIP), never a WARN or a FAIL, and the lines under
# it carry the trade-off measured on macOS, scoped to macOS.
mkdir -p "$work/conf"; printf '{"sandbox":{"enabled":false}}' > "$work/conf/settings.json"
out="$(CLAUDE_CONFIG_DIR="$work/conf" python3 "$checker" --root "$good" --no-network --sandbox 2>&1)"; rc=$?
if [ "$rc" = 0 ] && is "$out" FC-G01 unknown && ! grep -qE "(WARN|FAIL).*sandbox" <<<"$out"
then ok "--sandbox: an unset key is not verified, not reported off, and the floor still passes"; else bad "--sandbox unset"; printf '%s\n' "$out" | grep -E 'sandbox|failed' | sed 's/^/        /'; fi
under="$(sed -n '/SKIP.*sandbox not verified/,/^--/p' <<<"$out" | grep '^  INFO    ')"
for want in 'Read(~/.config/gh/\*\*)' 'anthropics/claude-code#95135' 'anthropics/claude-code#67105' 'uvx --from copier copier' 'macOS' 'Linux, WSL2 and native Windows: not measured' '\.env'; do
  is "$under" FC-G01 info || { bad "--sandbox: the lines under the SKIP do not name $want"; printf '%s\n' "$under" | sed 's/^/        /'; }
done
is "$under" FC-G01 info && ok "--sandbox: the SKIP names the gh collision, uvx, the upstream issues and the macOS scope"
# Nothing on this machine records the sandbox's state (#1002): the SKIP stays
# listed, marked as one that cannot be read here, and the last line counts it apart.
if is "$out" FC-G01 unknown && grep -qE -- '^-- 0 failed, [0-9]+ not verified \(1 cannot be read here\)$' <<<"$out"
then ok "--sandbox: the unrecorded state is marked as not readable here and counted apart"
else bad "--sandbox not marked"; grep -E 'sandbox not|failed' <<<"$out" | sed 's/^/        /'; fi
rm -f "$work/conf/settings.json"
out="$(CLAUDE_CONFIG_DIR="$work/conf" python3 "$checker" --root "$good" --no-network --sandbox 2>&1)"; rc=$?
if [ "$rc" = 0 ] && is "$out" FC-G01 unknown; then ok "--sandbox: no settings file at all is not verified either"; else bad "--sandbox no file"; printf '%s\n' "$out" | grep sandbox | sed 's/^/        /'; fi
printf '{"sandbox":{"enabled":true}}' > "$work/conf/settings.local.json"
out="$(CLAUDE_CONFIG_DIR="$work/conf" python3 "$checker" --root "$good" --no-network --sandbox 2>&1)"
# On is a fact, not a PASS: on macOS it is the state in which gh and the door stop.
if is "$out" FC-G01 info && ! grep -qE "(PASS|SKIP|WARN).*sandbox" <<<"$out" \
   && is "$out" FC-G01 info && is "$out" FC-G01 info
then ok "--sandbox: sandbox.enabled true is an INFO, and the measured macOS lines still follow it"; else bad "--sandbox on"; printf '%s\n' "$out" | grep -iE 'sandbox|gh|uvx' | sed 's/^/        /'; fi

# --plugins compares each plugin installed from the plinth marketplace with the
# commit its entry pins (#743): `update plinth@plinth` leaves a dependency at
# its old commit (#714). The files are in the shape Claude Code 2.1.314 writes.
pin=d1478fcb140db0b93c0c8df17bcfd311844749d0; old=c55ee46073ed923f86ce59a5eb3b6d895095d1b7
tpin=30202c767cfaf325212b3921ab484f83adaec850
pc="$work/pconf"; pm="$work/pmarket"
plugins_fixture() { # <mattpocock-skills commit> [extra JSON entries]: a fresh config and marketplace copy
  rm -rf "$pc" "$pm"; mkdir -p "$pc/plugins" "$pm/.claude-plugin"
  printf '{"name":"plinth","plugins":[{"name":"plinth","source":"./"},{"name":"mattpocock-skills","source":{"source":"git-subdir","url":"u","path":"skills","sha":"%s"}},{"name":"frontend-design","source":{"source":"git-subdir","url":"u","path":"plugins/frontend-design/skills","sha":"%s"}},{"name":"last30days","source":{"source":"url","url":"u","ref":"main"}}]}\n' "$pin" "$tpin" > "$pm/.claude-plugin/marketplace.json"
  printf '{"name":"plinth","version":"2.19.1"}\n' > "$pm/.claude-plugin/plugin.json"
  printf '{"plinth":{"source":{"source":"git","url":"u"},"installLocation":"%s"}}\n' "$pm" > "$pc/plugins/known_marketplaces.json"
  printf '{"version":2,"plugins":{"plinth@plinth":[{"scope":"user","version":"2.19.1","gitCommitSha":"%040d"}],"mattpocock-skills@plinth":[{"scope":"user","version":"x","gitCommitSha":"%s"}],"frontend-design@plinth":[{"scope":"user","version":"x","gitCommitSha":"%s"}]%s}}\n' 0 "$1" "$tpin" "${2:-}" > "$pc/plugins/installed_plugins.json"
}
plugins_run() { out="$(CLAUDE_CONFIG_DIR="$pc" python3 "$checker" --root "$good" --no-network --plugins 2>&1)"; rc=$?; }
behind_line='WARN  mattpocock-skills@plinth (user) is behind its pin: installed commit c55ee46073ed, the plinth marketplace pins d1478fcb140d'
plugins_fixture "$old"; plugins_run
if [ "$rc" = 0 ] && is "$out" FC-G02 warn && is "$out" FC-G02 warn \
   && ! grep -qE 'at the plinth.*mattpocock-skills' <<<"$out" && is "$out" FC-G02 info
then ok "--plugins: a dependency at an old commit is named with its update command, the others are at their pin"
else bad "--plugins behind"; grep -E 'plugin|@plinth' <<<"$out" | sed 's/^/        /'; fi
# Must not pass: an old commit that shares the pin's first characters, a
# truncated pin, or a commit in another letter case is not the pin.
for have in "${pin:0:12}0000000000000000000000000000" "${pin:0:12}" "$(tr a-f A-F <<<"$pin")"; do
  plugins_fixture "$have"; plugins_run
  if grep -qE 'at the plinth.*mattpocock-skills' <<<"$out"; then bad "--plugins: $have was reported at the pin $pin"
  elif grep -qE "(WARN|SKIP)  mattpocock-skills@plinth" <<<"$out"; then ok "--plugins: $have is not reported at the pin"
  else bad "--plugins: $have is neither behind nor not checked"; grep -E 'plugin|@plinth' <<<"$out" | sed 's/^/        /'; fi
done
plugins_fixture "$pin"; plugins_run
if [ "$rc" = 0 ] && ! grep -qE '(WARN|SKIP|FAIL).*@plinth' <<<"$out" && ! grep -q 'plugins not checked' <<<"$out" \
   && grep -qF 'at the plinth marketplace'"'"'s pin: frontend-design@plinth (user), mattpocock-skills@plinth (user), plinth@plinth (user)' <<<"$out"
then ok "--plugins: every plugin at its pin reports nothing to do"
else bad "--plugins up to date"; grep -E 'plugin|@plinth' <<<"$out" | sed 's/^/        /'; fi
# A project or local install is updated with its scope, from its project folder:
# before Claude Code 2.1.281 `update` without --scope updated the user install only.
plugins_fixture "$pin"
python3 - "$pc/plugins/installed_plugins.json" "$old" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["plugins"]["mattpocock-skills@plinth"] += [
    {"scope": "project", "projectPath": "/w/my app", "gitCommitSha": sys.argv[2]},
    {"scope": "local", "gitCommitSha": sys.argv[2]}]
json.dump(d, open(p, "w"))
PY
plugins_run
if is "$out" FC-G02 warn \
   && is "$out" FC-G02 warn \
   && is "$out" FC-G02 warn \
   && is "$out" FC-G02 info
then ok "--plugins: a project or local install behind its pin gets its scope and folder in the command, the user one stays at its pin"
else bad "--plugins scoped"; grep -E '@plinth' <<<"$out" | sed 's/^/        /'; fi
# plinth itself is compared by version with the marketplace copy's plugin.json.
plugins_fixture "$pin"; printf '{"name":"plinth","version":"2.19.2"}\n' > "$pm/.claude-plugin/plugin.json"; plugins_run
is "$out" FC-G02 warn \
  && is "$out" FC-G02 warn \
  && ok "--plugins: plinth behind its marketplace copy is named by version" || { bad "--plugins plinth version"; grep -E '@plinth' <<<"$out" | sed 's/^/        /'; }
# Not checked, never at the pin: another marketplace, an entry with no full
# commit, an install with no commit, an entry the marketplace does not have.
plugins_fixture "$pin" ',"codex@openai-codex":[{"scope":"user","gitCommitSha":"'"$pin"'"}],"last30days@plinth":[{"scope":"project","projectPath":"/p","gitCommitSha":"'"$pin"'"}],"gone@plinth":[{"scope":"user","gitCommitSha":"'"$pin"'"}]'
python3 - "$pc/plugins/installed_plugins.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); del d["plugins"]["frontend-design@plinth"][0]["gitCommitSha"]; json.dump(d, open(p, "w"))
PY
plugins_run
for want in 'INFO  plugins from another marketplace, outside what plinth compares: codex@openai-codex' \
            'SKIP  last30days@plinth (project in /p) not checked: its entry pins no full commit' \
            'SKIP  frontend-design@plinth (user) not checked: its install records no full commit' \
            'WARN  gone@plinth (user) is not in the plinth marketplace; Claude Code reports it "not found in marketplace" until it is uninstalled. fix: claude plugin uninstall gone@plinth --scope user'; do
  grep -qF -- "$want" <<<"$out" || { bad "--plugins: expected '$want'"; grep -E 'plugin|@' <<<"$out" | sed 's/^/        /'; }
done
grep -qE 'at the plinth.*(codex|last30days|frontend-design|gone)' <<<"$out" && bad "--plugins: a plugin not compared was reported at the pin" \
  || ok "--plugins: another marketplace, no pinned commit, no installed commit are not checked and an entry the marketplace no longer has is FC-G12, never at the pin"
# An entry the marketplace no longer lists (#1229): a retired one names the
# release it left in and its replacement, from the marketplace copy's Retired
# entries table, and its uninstall command with the install's scope; one not in
# the table is named all the same; another marketplace's plugin has no line.
plugins_fixture "$pin" ',"taste-skill@plinth":[{"scope":"user","gitCommitSha":"'"$pin"'"},{"scope":"project","projectPath":"/w/my app","gitCommitSha":"'"$pin"'"}],"taste-skill@other":[{"scope":"user","gitCommitSha":"'"$pin"'"}],"gone@plinth":[{"scope":"local","gitCommitSha":"'"$pin"'"}]'
mkdir -p "$pm/docs/reference"
printf '## Retired entries\n\n| Name | Kind | Left in | Replaced by | Issue | An installed user runs |\n| --- | --- | --- | --- | --- | --- |\n| `taste-skill` | entry removed | v2.46.0 | `frontend-design` | #1082 | `claude plugin uninstall taste-skill@plinth` |\n' > "$pm/docs/reference/dependency-entries.md"
plugins_run
for want in 'WARN  taste-skill@plinth (user) left the plinth marketplace in v2.46.0, replaced by frontend-design; Claude Code reports it "not found in marketplace" until it is uninstalled. fix: claude plugin uninstall taste-skill@plinth --scope user' \
            "WARN  taste-skill@plinth (project in /w/my app) left the plinth marketplace in v2.46.0, replaced by frontend-design; Claude Code reports it \"not found in marketplace\" until it is uninstalled. fix: cd '/w/my app' && claude plugin uninstall taste-skill@plinth --scope project" \
            'WARN  gone@plinth (local) is not in the plinth marketplace; Claude Code reports it "not found in marketplace" until it is uninstalled. fix: claude plugin uninstall gone@plinth --scope local, run from the project folder it was installed for'; do
  grep -qF -- "$want" <<<"$out" || { bad "--plugins: expected '$want'"; grep -E '@' <<<"$out" | sed 's/^/        /'; }
done
if [ "$rc" = 0 ] && is "$out" FC-G12 warn && ! grep -qE '(WARN|SKIP).*taste-skill@other' <<<"$out" \
   && grep -qF 'outside what plinth compares: taste-skill@other' <<<"$out" && ! grep -qE 'SKIP .*(taste-skill|gone)@plinth' <<<"$out"
then ok "--plugins: a retired entry names its release, its replacement and its scoped uninstall; one not in the table is named too; another marketplace's has no FC-G12 line"
else bad "--plugins retired"; grep -E '@' <<<"$out" | sed 's/^/        /'; fi
# Another marketplace's plugin is outside what floor-check compares, not a read
# that failed (#1002): an INFO, out of the not-verified count.
plugins_fixture "$pin"; plugins_run; without="$(grep -- '^-- ' <<<"$out")"
plugins_fixture "$pin" ',"codex@openai-codex":[{"scope":"user","gitCommitSha":"'"$pin"'"}]'; plugins_run
if [ "$rc" = 0 ] && ! grep -qE '^  SKIP .*codex' <<<"$out" && [ "$(grep -- '^-- ' <<<"$out")" = "$without" ]
then ok "--plugins: a plugin from another marketplace is not counted as not verified"
else bad "--plugins other marketplace counted"; grep -E 'codex|failed' <<<"$out" | sed 's/^/        /'; fi
# A state it cannot read is one SKIP and no plugin at its pin.
for broken in installed shape known market name; do
  plugins_fixture "$pin"
  case $broken in
    installed) rm "$pc/plugins/installed_plugins.json" ;;
    shape) printf '{"version":1,"plugins":{}}\n' > "$pc/plugins/installed_plugins.json" ;;
    known) printf '{}\n' > "$pc/plugins/known_marketplaces.json" ;;
    market) rm "$pm/.claude-plugin/marketplace.json" ;;
    name) sed -i.bak 's/"name":"plinth","plugins"/"name":"fork","plugins"/' "$pm/.claude-plugin/marketplace.json" ;;
  esac
  plugins_run
  if [ "$rc" = 0 ] && [ "$(grep -c 'SKIP  plugins not checked' <<<"$out")" = 1 ] && ! grep -q 'at the plinth' <<<"$out"
  then ok "--plugins: an unreadable state ($broken) is not checked, and nothing is at its pin"
  else bad "--plugins unreadable $broken"; grep -E 'plugin|@' <<<"$out" | sed 's/^/        /'; fi
done

# --credentials lists what else on this machine can push to github.com (#336):
# stored gh accounts, git helpers besides gh's, an Authorization header, ~/.netrc,
# GH_TOKEN/GITHUB_TOKEN. Presence only, never a value; what it cannot read is a
# SKIP. A fake gh prints $FAKE_GH (or fails when it is unset) and records
# whether it saw GH_TOKEN; git reads only $work/cred/gitconfig.
cred="$work/cred"; mkdir -p "$cred/bin" "$cred/home"
cat > "$cred/bin/gh" <<'SH'
#!/usr/bin/env bash
[ -n "${GH_TOKEN:-}" ] && : > "$FAKE_GH_SAW"
[ -n "${FAKE_GH:-}" ] || { echo "not logged in" >&2; exit 1; }
printf '%s\n' "$FAKE_GH"
SH
chmod +x "$cred/bin/gh"
one='{"hosts":{"github.com":[{"login":"me","active":true,"state":"success"}]}}'
two='{"hosts":{"github.com":[{"login":"me","active":true,"state":"success"},{"login":"other","active":false,"state":"success"}]}}'
# git reads the fixture as ~/.gitconfig: GIT_CONFIG_GLOBAL would be reported as
# masking it. GIT_CONFIG_NOSYSTEM keeps this machine's system config out, and
# is reported as a SKIP, which no case below asserts is absent.
ln -s ../gitconfig "$cred/home/.gitconfig"
credrun() {   # extra env assignments as arguments; prints the checker's output
  env -u GH_TOKEN -u GITHUB_TOKEN -u GIT_CONFIG -u GH_CONFIG_DIR -u XDG_CONFIG_HOME -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_SYSTEM \
    -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS PATH="$cred/bin:$PATH" HOME="$cred/home" GIT_CONFIG_NOSYSTEM=1 \
    FAKE_GH_SAW="$cred/saw" "$@" python3 "$checker" --root "$good" --no-network --credentials 2>&1
}
printf '[credential]\n\thelper = osxkeychain\n[credential "https://github.com"]\n\thelper =\n\thelper = !/opt/homebrew/bin/gh auth git-credential\n' > "$cred/gitconfig"
out="$(credrun FAKE_GH="$one")"; rc=$?
if [ "$rc" = 0 ] && is "$out" FC-G06 info && is "$out" FC-G07 info \
   && is "$out" FC-G09 info && is "$out" FC-G10 unknown && ! grep -q WARN <<<"$out" \
   && [ "$(grep -c "no other credential found by these rules; best effort, see the guide's list" <<<"$out")" = 3 ] \
   && ! grep -qE "PASS  (gh stores|git asks|no github.com login)" <<<"$out"
then ok "--credentials: nothing found is an INFO with the best-effort note, never a PASS; SSH still not verified"; else bad "--credentials clean"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# Only the account's settings say which SSH keys push (#1002): the SKIP is
# marked as not readable here and counted apart from the readable ones.
if is "$out" FC-G10 unknown \
   && grep -qE -- '^-- 0 failed, [0-9]+ not verified \(1 cannot be read here\)$' <<<"$out"
then ok "--credentials: the SSH keys SKIP is marked as not readable here and counted apart"
else bad "--credentials SSH not marked"; grep -E 'SSH|failed' <<<"$out" | sed 's/^/        /'; fi
# A variable that points gh or git elsewhere hides the default configuration,
# and the agent can unset it: not verified, named, never read as clean.
for var in GH_CONFIG_DIR XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS; do
  out="$(credrun "$var=$cred/elsewhere" FAKE_GH="$one")"
  is "$out" FC-G05 unknown || { bad "--credentials: $var set is not reported"; printf '%s\n' "$out" | sed 's/^/        /'; }
done
# Exported but empty still hides the default file: `GIT_CONFIG_GLOBAL=` reads no global config.
for var in GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GH_CONFIG_DIR; do
  out="$(credrun "$var=" FAKE_GH="$one")"
  is "$out" FC-G05 unknown || { bad "--credentials: $var set but empty is not reported"; printf '%s\n' "$out" | grep SKIP | sed 's/^/        /'; }
done
out="$(credrun FAKE_GH="$one")"
is "$out" FC-G05 unknown && ! grep -qE "SKIP  (GH_CONFIG_DIR|GIT_CONFIG_GLOBAL) is set" <<<"$out" \
  && ok "--credentials: GH_CONFIG_DIR, XDG_CONFIG_HOME and the GIT_CONFIG_* overrides are each not verified; unset, not named" \
  || { bad "--credentials masking variables"; printf '%s\n' "$out" | grep SKIP | sed 's/^/        /'; }
out="$(credrun FAKE_GH="$two")"
# The checker cannot tell which account holds the agent's token, active or
# not: the repair names every account and leaves the choice to the person.
if is "$out" FC-G06 warn && is "$out" FC-G06 info \
   && is "$out" FC-G06 info && is "$out" FC-G06 info
then ok "--credentials: a second stored gh account is a WARN, with a logout line for every account and the choice left to the person"; else bad "--credentials two accounts"; printf '%s\n' "$out" | grep -i gh | sed 's/^/        /'; fi
rm -f "$cred/saw"
out="$(credrun GH_TOKEN=secret-value-1 FAKE_GH="$one")"
if is "$out" FC-G04 warn && ! grep -q "secret-value-1" <<<"$out" && [ ! -e "$cred/saw" ] && is "$out" FC-G06 warn
then ok "--credentials: GH_TOKEN is named, not printed, and the stored accounts are read without it"; else bad "--credentials GH_TOKEN"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# With an environment token, even one stored account is another credential:
# the agent can unset the variable, and the stored login answers.
out="$(credrun GH_TOKEN=secret-value-9 FAKE_GH="$one")"
is "$out" FC-G06 warn && ! grep -q "INFO  gh stores" <<<"$out" \
  && ok "--credentials: one stored account beside GH_TOKEN is a WARN" || { bad "--credentials env token plus one stored"; printf '%s\n' "$out" | grep -i gh | sed 's/^/        /'; }
out="$(credrun GH_TOKEN=secret-value-9 FAKE_GH='{"hosts":{}}')"
is "$out" FC-G06 info && ok "--credentials: GH_TOKEN with nothing stored leaves the stored item an INFO" || { bad "--credentials env token, none stored"; printf '%s\n' "$out" | grep -i gh | sed 's/^/        /'; }
out="$(credrun GITHUB_TOKEN=secret-value-5 FAKE_GH="$one")"
is "$out" FC-G04 warn && ! grep -q "secret-value-5" <<<"$out" \
  && ok "--credentials: GITHUB_TOKEN is named, not printed" || { bad "--credentials GITHUB_TOKEN"; printf '%s\n' "$out" | sed 's/^/        /'; }
skipped=0
for bad_gh in "" "not json" '{"nohosts":1}'; do
  out="$(credrun FAKE_GH="$bad_gh")"
  if is "$out" FC-G06 unknown && ! grep -q "INFO  gh stores" <<<"$out"; then skipped=$((skipped+1))
  else bad "--credentials: gh answering '${bad_gh:-(failure)}' is not a SKIP"; printf '%s\n' "$out" | grep gh | sed 's/^/        /'; fi
done
[ "$skipped" = 3 ] && ok "--credentials: gh failing, or answering what is not its JSON, is not verified"
# The active account's scopes, as gh 2.103.3 lists them (#986): `workflow` lets
# the agent push a change to .github/workflows/, the checks included. A WARN
# with the how-to; scopes without it an INFO; none listed (a fine-grained
# token), or an answer not read, a SKIP, never a PASS.
wf='{"hosts":{"github.com":[{"login":"me","active":true,"state":"success","scopes":"gist, read:org, read:packages, repo, workflow"}]}}'
nowf='{"hosts":{"github.com":[{"login":"me","active":true,"state":"success","scopes":"gist, read:org, repo"}]}}'
noscope='{"hosts":{"github.com":[{"login":"me","active":true,"state":"success","scopes":""}]}}'
out="$(credrun FAKE_GH="$wf")"; rc=$?
if [ "$rc" = 0 ] && is "$out" FC-G03 warn \
   && is "$out" FC-G03 info && ! grep -q "PASS  .*\`workflow\`" <<<"$out"
then ok "--credentials: an active gh login holding \`workflow\` is a WARN naming the login and the how-to, and does not fail the run"
else bad "--credentials workflow scope (rc=$rc)"; printf '%s\n' "$out" | grep -iE 'workflow|scope|gh' | sed 's/^/        /'; fi
# The inactive account's scopes are not the agent's: only the active one counts.
out="$(credrun FAKE_GH='{"hosts":{"github.com":[{"login":"me","active":true,"state":"success","scopes":"repo"},{"login":"other","active":false,"state":"success","scopes":"repo, workflow"}]}}')"
is "$out" FC-G03 info && ! grep -q "holds \`workflow\`" <<<"$out" \
  && ok "--credentials: only the active account's scopes are read" || { bad "--credentials inactive account's workflow"; printf '%s\n' "$out" | grep -iE 'workflow|scope' | sed 's/^/        /'; }
out="$(credrun FAKE_GH="$nowf")"
is "$out" FC-G03 info && ! grep -qE "(WARN|SKIP|PASS)  .*\`workflow\`" <<<"$out" \
  && ok "--credentials: scopes listed without \`workflow\` are an INFO" || { bad "--credentials scopes without workflow"; printf '%s\n' "$out" | grep -iE 'workflow|scope' | sed 's/^/        /'; }
skipped=0
for case_gh in "$noscope" "$one" '{"hosts":{"github.com":[{"login":"me","active":true,"scopes":" , "}]}}'; do
  out="$(credrun FAKE_GH="$case_gh")"
  if is "$out" FC-G03 unknown \
    && ! grep -qE "(WARN|INFO|PASS)  .*\`workflow\`" <<<"$out"; then skipped=$((skipped+1))
  else bad "--credentials: no scopes in '$case_gh' is not a SKIP"; printf '%s\n' "$out" | grep -iE 'workflow|scope' | sed 's/^/        /'; fi
done
[ "$skipped" = 3 ] && ok "--credentials: no scopes listed, empty or absent, is a SKIP saying a fine-grained token lists none, never a PASS"
skipped=0
for case_gh in '{"hosts":{"github.com":[{"login":"me","active":true,"scopes":7}]}}' '{"hosts":{"github.com":[{"login":"me","active":true,"scopes":["repo",{}]}]}}'; do
  out="$(credrun FAKE_GH="$case_gh")"
  if is "$out" FC-G03 unknown \
    && ! grep -qE "(WARN|INFO|PASS)  .*\`workflow\`" <<<"$out"; then skipped=$((skipped+1))
  else bad "--credentials: unreadable scopes in '$case_gh' are not a SKIP"; printf '%s\n' "$out" | grep -iE 'workflow|scope' | sed 's/^/        /'; fi
done
[ "$skipped" = 2 ] && ok "--credentials: scopes in a form not read are a SKIP saying so, never a PASS"
out="$(credrun FAKE_GH='{"hosts":{"github.com":[{"login":"me","active":true,"scopes":["repo","workflow"]}]}}')"
is "$out" FC-G03 warn && ok "--credentials: scopes listed as a JSON list are read too" \
  || { bad "--credentials: scopes as a list"; printf '%s\n' "$out" | grep -iE 'workflow|scope' | sed 's/^/        /'; }
out="$(credrun GH_TOKEN=secret-value-4 FAKE_GH="$noscope")"
is "$out" FC-G03 unknown \
  && ok "--credentials: with GH_TOKEN set, the SKIP also says the stored login's scopes may not be in use" \
  || { bad "--credentials: GH_TOKEN beside no scopes"; printf '%s\n' "$out" | grep -iE 'scope' | sed 's/^/        /'; }
skipped=0
for bad_gh in "" "not json" '{"hosts":{}}' '{"hosts":{"github.com":[{"login":"me","active":false,"scopes":"workflow"}]}}'; do
  out="$(credrun FAKE_GH="$bad_gh")"
  if is "$out" FC-G03 unknown && ! grep -qE "(WARN|INFO|PASS)  .*\`workflow\`" <<<"$out"; then skipped=$((skipped+1))
  else bad "--credentials: '${bad_gh:-(failure)}' leaves the login's permissions other than a SKIP"; printf '%s\n' "$out" | grep -iE 'workflow|scope|permission' | sed 's/^/        /'; fi
done
[ "$skipped" = 4 ] && ok "--credentials: an unread answer, or no active login, leaves the login's permissions not verified"
# An environment token is used before the stored login: the scopes read are
# the stored login's, and the line says they may not be the ones in use.
seen=0
for var in GH_TOKEN GITHUB_TOKEN; do
  out="$(credrun "$var=secret-value-3" FAKE_GH="$wf")"
  if is "$out" FC-G03 warn \
    && is "$out" FC-G04 warn && ! grep -q secret-value-3 <<<"$out"; then seen=$((seen+1))
  else bad "--credentials: $var beside the scopes line"; printf '%s\n' "$out" | grep -iE 'workflow|TOKEN' | sed 's/^/        /'; fi
done
[ "$seen" = 2 ] && ok "--credentials: GH_TOKEN or GITHUB_TOKEN set keeps its WARN, and the scopes line says the stored login's may not be in use"
# Helpers: the macOS default with no empty helper before gh's; one listed after
# gh's; an inline `!` helper, named without its text; other hosts and plain
# http ignored; an empty helper for a path on github.com clears nothing.
printf '[credential]\n\thelper = osxkeychain\n[credential "https://github.com"]\n\thelper = !gh auth git-credential\n' > "$cred/gitconfig"
out="$(credrun FAKE_GH="$one")"
is "$out" FC-G07 warn \
  && ok "--credentials: osxkeychain not cleared before gh's helper is a WARN" || { bad "--credentials osxkeychain"; printf '%s\n' "$out" | grep -i helper | sed 's/^/        /'; }
printf '[credential "https://github.com"]\n\thelper =\n\thelper = !gh auth git-credential\n\thelper = store --file /x\n[credential "https://example.com"]\n\thelper = cache\n[credential "http://github.com"]\n\thelper = cache\n[credential "https://github.com/o/r"]\n\thelper =\n\thelper = !f() { echo password=tok-value-2; }; f\n' > "$cred/gitconfig"
out="$(credrun FAKE_GH="$one")"
if is "$out" FC-G07 warn && ! grep -q "tok-value-2\|cache" <<<"$out"
then ok "--credentials: a helper after gh's and one for a path on github.com are WARNs, other hosts are not, and no helper text is printed"; else bad "--credentials helpers"; printf '%s\n' "$out" | grep -i helper | sed 's/^/        /'; fi
# gh 2.101.0's `gh auth setup-git`, run from a path with a space, single-quotes it.
printf '[credential "https://github.com"]\n\thelper =\n\thelper = !'"'"'/Applications/my tools/gh'"'"' auth git-credential\n' > "$cred/gitconfig"
out="$(credrun FAKE_GH="$one")"
is "$out" FC-G07 info && ok "--credentials: gh's helper under a quoted path with a space is gh's" \
  || { bad "--credentials quoted gh path"; printf '%s\n' "$out" | grep -i helper | sed 's/^/        /'; }
# Without `!`, git runs `git credential-gh auth git-credential`, not gh.
printf '[credential "https://github.com"]\n\thelper =\n\thelper = gh auth git-credential\n' > "$cred/gitconfig"
out="$(credrun FAKE_GH="$one")"
is "$out" FC-G07 warn && ! grep -q "INFO  git asks" <<<"$out" \
  && ok "--credentials: gh auth git-credential without \`!\` is another helper (git-credential-gh)" || { bad "--credentials helper without !"; printf '%s\n' "$out" | grep -i helper | sed 's/^/        /'; }
# A shell command glued before gh's path runs first: not gh's helper either.
for h in '!/tmp/steal;/usr/bin/gh auth git-credential' '!/tmp/steal&&/usr/bin/gh auth git-credential' '!$(/tmp/steal)/gh auth git-credential' '!/a|/usr/bin/gh auth git-credential'; do
  printf '[credential "https://github.com"]\n\thelper =\n\thelper = "%s"\n' "$h" > "$cred/gitconfig"
  out="$(credrun FAKE_GH="$one")"
  is "$out" FC-G07 warn && ! grep -q "INFO  git asks" <<<"$out" \
    || { bad "--credentials: '$h' passed as gh's helper"; printf '%s\n' "$out" | grep -i helper | sed 's/^/        /'; }
done
is "$out" FC-G07 warn && ok "--credentials: a shell command before gh's path (; && \$() |) is another helper"
# A newline is a command separator to the shell: `!/usr/bin/gh` then `auth ...` runs two commands.
printf '[credential "https://github.com"]\n\thelper =\n\thelper = "!/usr/bin/gh\\nauth git-credential"\n' > "$cred/gitconfig"
out="$(credrun FAKE_GH="$one")"
is "$out" FC-G07 warn && ! grep -q "INFO  git asks" <<<"$out" \
  && ok "--credentials: a newline inside gh's helper line makes it another helper" || { bad "--credentials newline in helper"; printf '%s\n' "$out" | grep -i helper | sed 's/^/        /'; }
# A `!` helper that calls gh after answering itself is not gh's helper.
printf '[credential "https://github.com"]\n\thelper =\n\thelper = !f() { echo password=tok-value-6; gh auth git-credential "$@"; }; f\n' > "$cred/gitconfig"
out="$(credrun FAKE_GH="$one")"
is "$out" FC-G07 warn && ! grep -q "INFO  git asks" <<<"$out" \
  && ok "--credentials: a shell helper that merely calls gh's is still another helper" || { bad "--credentials wrapped gh helper"; printf '%s\n' "$out" | grep -i helper | sed 's/^/        /'; }
printf '[http "https://github.com/"]\n\textraHeader = Authorization: basic tok-value-3\n' > "$cred/gitconfig"
out="$(credrun FAKE_GH="$one")"
is "$out" FC-G08 warn && ! grep -q "tok-value-3" <<<"$out" \
  && ok "--credentials: an Authorization extraHeader for github.com is a WARN, its value unprinted" || { bad "--credentials extraHeader"; printf '%s\n' "$out" | sed 's/^/        /'; }
printf 'machine github.com login me password tok-value-4\n' > "$cred/home/.netrc"
out="$(credrun FAKE_GH="$one")"
is "$out" FC-G09 warn && ! grep -q "tok-value-4" <<<"$out" \
  && ok "--credentials: a github.com login in ~/.netrc is a WARN, its value unprinted" || { bad "--credentials netrc"; printf '%s\n' "$out" | grep netrc | sed 's/^/        /'; }
# curl reads a quoted token (8.5.0 sent a quoted github.com entry's login):
# the quotes are not part of the name. One it cannot tokenise is not verified.
printf 'machine "github.com" login me password "tok value-8"\n' > "$cred/home/.netrc"
out="$(credrun FAKE_GH="$one")"
is "$out" FC-G09 warn && ! grep -q "tok value-8" <<<"$out" \
  && ok "--credentials: a quoted github.com in ~/.netrc is a WARN" || { bad "--credentials netrc quoted"; printf '%s\n' "$out" | grep netrc | sed 's/^/        /'; }
printf 'machine GitHub.COM login me password x\n' > "$cred/home/.netrc"
out="$(credrun FAKE_GH="$one")"
is "$out" FC-G09 warn \
  && ok "--credentials: github.com in ~/.netrc in any case is a WARN" || { bad "--credentials netrc case"; printf '%s\n' "$out" | grep netrc | sed 's/^/        /'; }
printf 'machine "github.com login me password x\n' > "$cred/home/.netrc"
out="$(credrun FAKE_GH="$one")"
is "$out" FC-G09 unknown && ! grep -q "INFO  no github.com login" <<<"$out" \
  && ok "--credentials: an unterminated quote in ~/.netrc is not verified" || { bad "--credentials netrc unterminated"; printf '%s\n' "$out" | grep netrc | sed 's/^/        /'; }
printf '# machine github.com login old password tok-value-7\nmachine example.com login me password x\n' > "$cred/home/.netrc"
out="$(credrun FAKE_GH="$one")"
is "$out" FC-G09 info && ok "--credentials: a .netrc for another host, and a commented github.com line, are not a WARN" || bad "--credentials netrc other host or comment"
if [ "$(id -u)" != 0 ]; then
  chmod 000 "$cred/home/.netrc"; out="$(credrun FAKE_GH="$one")"; chmod 600 "$cred/home/.netrc"
  is "$out" FC-G09 unknown && ok "--credentials: an unreadable .netrc is not verified" || { bad "--credentials netrc unreadable"; printf '%s\n' "$out" | grep netrc | sed 's/^/        /'; }
fi
printf '#!/bin/sh\nexit 128\n' > "$cred/bin/git"; chmod +x "$cred/bin/git"
out="$(credrun FAKE_GH="$one")"; rm -f "$cred/bin/git"
is "$out" FC-G07 unknown && ! grep -q "INFO  git asks" <<<"$out" \
  && ok "--credentials: git config failing is not verified" || { bad "--credentials git failing"; printf '%s\n' "$out" | grep -i git | sed 's/^/        /'; }
# git matches a credential.<url> entry on username and port too (#349): one
# scoped to either does not apply to a plain https://github.com push, so its
# empty value clears nothing; one naming a helper is still counted. :443 is
# the default port and applies.
for scope in 'https://restricted@github.com' 'https://github.com:8443'; do
  printf '[credential]\n\thelper = store\n[credential "%s"]\n\thelper =\n[credential "https://github.com"]\n\thelper = !gh auth git-credential\n' "$scope" > "$cred/gitconfig"
  out="$(credrun FAKE_GH="$one")"
  is "$out" FC-G07 warn && ! grep -q "INFO  git asks" <<<"$out" \
    || { bad "--credentials: an empty helper under $scope cleared the list"; printf '%s\n' "$out" | grep -i helper | sed 's/^/        /'; }
done
is "$out" FC-G07 warn && ok "--credentials: an empty helper scoped by a username or a port does not clear the list"
printf '[credential]\n\thelper = store\n[credential "https://github.com:443"]\n\thelper =\n\thelper = !gh auth git-credential\n[credential "https://me@github.com"]\n\thelper = cache\n' > "$cred/gitconfig"
out="$(credrun FAKE_GH="$one")"
is "$out" FC-G07 warn \
  && ok "--credentials: an empty helper at :443 clears the list, and a username-scoped helper is counted" || { bad "--credentials :443 and username helper"; printf '%s\n' "$out" | grep -i helper | sed 's/^/        /'; }
# A subsection URL urlsplit rejects is named (userinfo hidden) and not
# verified; the rest of the report and the summary still print.
printf '[credential "https://u:tok-value-10@[bad"]\n\thelper = cache\n[credential "https://github.com"]\n\thelper =\n\thelper = !gh auth git-credential\n' > "$cred/gitconfig"
out="$(credrun FAKE_GH="$one")"; rc=$?
if [ "$rc" = 0 ] && is "$out" FC-G07 unknown && ! grep -q "tok-value-10\|Traceback" <<<"$out" \
   && is "$out" FC-G09 info && is "$out" FC-G10 unknown && grep -q "^-- [0-9]* failed, [0-9]* not verified" <<<"$out"
then ok "--credentials: a credential subsection URL that cannot be parsed is a SKIP naming it, and the run goes on"; else bad "--credentials unparseable subsection"; printf '%s\n' "$out" | tail -n 12 | sed 's/^/        /'; fi
for sub in 'user:tok-value-12@[bad' 'https://u:tok-value-13@github.com:abc' 'https://github.com:abc'; do
  printf '[credential "%s"]\n\thelper = cache\n' "$sub" > "$cred/gitconfig"
  out="$(credrun FAKE_GH="$one")"; rc=$?
  [ "$rc" = 0 ] && is "$out" FC-G07 unknown \
    && ! grep -q "tok-value-1[23]" <<<"$out" && grep -q "^-- [0-9]* failed" <<<"$out" \
    || { bad "--credentials: unparseable '$sub'"; printf '%s\n' "$out" | grep -v PASS | tail -n 8 | sed 's/^/        /'; }
done
is "$out" FC-G07 unknown && ok "--credentials: an unparseable subsection, with or without a scheme or a user, is a SKIP that prints no user or password"
# The same reading, checked against git itself: `git credential fill` for a
# push to https://github.com/o/r, with a harmless `!echo` helper, shows which
# entries git applies. Wherever git runs a helper, the checker must count one:
# a helper under the entry, or one read before an empty helper under it that
# git did not take as clearing the list.
askgit() { printf 'protocol=https\nhost=github.com\npath=o/r\n\n' | env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS \
  HOME="$cred/home" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 GIT_ASKPASS= SSH_ASKPASS= git -C "$good" credential fill 2>&1 | grep -c RAN-349; }
disagree=0 ran=0
for scope in 'https://github.com' 'https://GitHub.com/' 'https://github.com:443' 'https://github.com:8443' 'https://restricted@github.com' \
             'https://github.com/o' 'https://github.com/o/r' 'https://github.com/other' 'https://*.github.com' 'github.com' 'https://[bad' \
             'http://github.com' 'https://github.com.evil' 'https://@github.com' 'https://github.com?x' 'https://github.com#f' \
             'https://github.com:abc'; do
  printf '[credential "%s"]\n\thelper = %s\n' "$scope" '!echo RAN-349 >&2' > "$cred/gitconfig"
  n="$(askgit)"; ran=$((ran + n))
  if [ "$n" != 0 ] && ! grep -q "WARN  git has 1 credential helper" <<<"$(credrun FAKE_GH="$one")"; then
    bad "--credentials: git applies a helper under $scope and the checker does not count it"; disagree=1; fi
  printf '[credential]\n\thelper = %s\n[credential "%s"]\n\thelper =\n' '!echo RAN-349 >&2' "$scope" > "$cred/gitconfig"
  n="$(askgit)"; ran=$((ran + n))
  if [ "$n" != 0 ] && ! grep -q "WARN  git has 1 credential helper" <<<"$(credrun FAKE_GH="$one")"; then
    bad "--credentials: git keeps a helper past an empty one under $scope and the checker takes it as cleared"; disagree=1; fi
done
[ "$ran" -gt 0 ] || { bad "--credentials: git credential fill never ran a helper, so the comparison with git proves nothing"; disagree=1; }
[ "$disagree" = 0 ] && ok "--credentials: every helper git itself applies to a push to github.com/o/r is counted (17 subsection URLs)"
printf '[credential "https://github.com"]\n\thelper =\n\thelper = !gh auth git-credential\n' > "$cred/gitconfig"
# `default` opens a .netrc entry only where a keyword stands; as a value it is
# a value. A sequence the reader cannot place is not verified.
printf 'machine example.com login default password x\n' > "$cred/home/.netrc"
out="$(credrun FAKE_GH="$one")"
is "$out" FC-G09 info && ok "--credentials: \`default\` as a .netrc value is not a default entry" \
  || { bad "--credentials netrc default as value"; printf '%s\n' "$out" | grep netrc | sed 's/^/        /'; }
printf 'machine example.com login me password x\ndefault\n  login me password tok-value-11\n' > "$cred/home/.netrc"
out="$(credrun FAKE_GH="$one")"
is "$out" FC-G09 warn && ! grep -q "tok-value-11" <<<"$out" \
  && ok "--credentials: \`default\` where a keyword stands is a default entry" || { bad "--credentials netrc default entry"; printf '%s\n' "$out" | grep netrc | sed 's/^/        /'; }
for n in 'machine example.com login me stray x' 'machine example.com login' 'login me machine example.com' 'machine example.com macdef m'; do
  printf '%s\n' "$n" > "$cred/home/.netrc"
  out="$(credrun FAKE_GH="$one")"
  is "$out" FC-G09 unknown && ! grep -q "INFO  no github.com login" <<<"$out" \
    || { bad "--credentials: .netrc '$n' was placed"; printf '%s\n' "$out" | grep netrc | sed 's/^/        /'; }
done
is "$out" FC-G09 unknown && ok "--credentials: a .netrc token sequence that cannot be placed is not verified"
rm -f "$cred/home/.netrc"
# GIT_CONFIG makes git read that file instead of the repository's .git/config.
for v in "$cred/elsewhere" ''; do
  out="$(credrun GIT_CONFIG="$v" FAKE_GH="$one")"
  is "$out" FC-G05 unknown || { bad "--credentials: GIT_CONFIG='$v' is not named"; printf '%s\n' "$out" | grep SKIP | sed 's/^/        /'; }
done
is "$out" FC-G05 unknown && ok "--credentials: GIT_CONFIG, set or empty, is named as hiding a configuration"

# --credentials also names a production database URL within the agent's reach
# (#648): this environment, .env* files under --root (tracked or not), and the
# env of .claude/settings*.json, the repository's and the user's. Every value
# below is fake; `FAKE648` (a password) and `acme648` (a host) must never be
# printed. Each run gets an empty environment besides what the case sets, and
# a PATH whose gh fails at once (the gh item is not this block's question).
dbr="$work/dbroot"; dbu="$work/dbuser"
dbreset() { rm -rf "$dbr" "$dbu"; cp -R "$good" "$dbr"; mkdir -p "$dbu"; }
dbrun() {   # extra env assignments as arguments; prints the checker's output
  env -i PATH="$cred/bin:$PATH" HOME="$cred/home" GIT_CONFIG_NOSYSTEM=1 CLAUDE_CONFIG_DIR="$dbu" FAKE_GH_SAW="$cred/saw" FLOOR_CHECK_TRACE="$FLOOR_CHECK_TRACE" "$@" \
    python3 "$checker" --root "$dbr" --no-network --credentials 2>&1
}
db_lines() { grep -i "database" <<<"$out"; }
leaks() { grep -qE "FAKE648|acme648" <<<"$out"; }
prod='postgres://app:FAKE648@db.acme648.net:5432/app'
dbquiet() { # <description>: no database WARN or SKIP, its INFO (the limit), no PASS, no value
  if ! grep -qE "(WARN|SKIP|PASS)  .*database" <<<"$out" && is "$out" FC-G11 info && ! leaks
  then ok "$1"; else bad "$1"; db_lines | sed 's/^/        /'; fi
}
dbwarn() { # <description>: the WARN, its fix line, no limit INFO, no value
  if is "$out" FC-G11 warn && is "$out" FC-G11 info && ! grep -q "INFO  no production database URL found" <<<"$out" && ! leaks
  then ok "$1"; else bad "$1"; db_lines | sed 's/^/        /'; fi
}

# What must not warn, first.
dbreset; out="$(dbrun)"
dbquiet "--credentials, database: nothing found is an INFO naming what is not read, never a PASS"
warned=0
for url in 'postgres://app:FAKE648@localhost:5432/app' 'postgresql://app:FAKE648@127.0.0.1/app' 'postgresql://app:FAKE648@[::1]:5432/app' \
           'postgresql:///app' 'postgresql://app@/app?host=/var/run/postgresql' 'postgres://app:FAKE648@db.localhost/app' \
           'postgres://user:password@db.example.com/app' 'postgres://${PGUSER}:${PGPASSWORD}@${PGHOST}/app' 'postgres://u:p@<host>/db' \
           'postgresql://app:FAKE648@0.0.0.0/app' \
           'postgres://app:FAKE648@db.acme648.net/app_test' 'postgres://app:FAKE648@db.acme648.net/test' \
           'postgresql://app:FAKE648@db.acme648.net/app?dbname=testing' '' 'sqlite:///app.db'; do
  dbreset
  printf 'DATABASE_URL=%s\n' "$url" > "$dbr/.env"
  printf '{"env":{"DATABASE_URL":"%s"}}\n' "$url" > "$dbr/.claude/settings.local.json"
  printf '{"env":{"DATABASE_URL":"%s"}}\n' "$url" > "$dbu/settings.json"
  out="$(dbrun DATABASE_URL="$url")"
  if grep -qE "(WARN|SKIP)  .*database" <<<"$out" || leaks; then warned=1; bad "--credentials, database: '$url' warned or was printed"; db_lines | sed 's/^/        /'; fi
done
[ "$warned" = 0 ] && dbquiet "--credentials, database: local hosts, sockets, reserved placeholder names, variables, test databases, an empty value and sqlite do not warn"
dbreset
printf '# DATABASE_URL=%s\n  # %s\nDATABASE_URL=sqlite:///app.db # was %s\nOTHER=x\n' "$prod" "$prod" "$prod" > "$dbr/.env"
out="$(dbrun)"
dbquiet "--credentials, database: a commented line and a comment after an unquoted value do not warn"
dbreset; mkdir -p "$dbr/.env"; printf 'DATABASE_URL=%s\n' "$prod" > "$dbr/.env/.env"; printf 'home = /x\n' > "$dbr/.env/pyvenv.cfg"
out="$(dbrun)"
dbquiet "--credentials, database: a directory named .env (a virtualenv) is not entered"

# What warns: each place, named, the value never printed.
dbreset; out="$(dbrun DATABASE_URL="$prod")"; rc=$?
dbwarn "--credentials, database: DATABASE_URL in this environment is a WARN naming the variable"
[ "$rc" = 0 ] && is "$out" FC-G11 info \
  && ok "--credentials, database: a WARN does not fail the run, and the fix says where to remove it" || bad "--credentials, database: exit $rc or the environment fix line"
dbreset; out="$(dbrun REPORTING_DB='POSTGRESQL+psycopg://app:FAKE648@db.acme648.net/app')"
dbwarn "--credentials, database: any variable holding a postgresql+driver URL, in any case, is a WARN"
dbreset; out="$(dbrun DATABASE_URL='postgresql://app:FAKE648@localhost,db.acme648.net:5433/app')"
dbwarn "--credentials, database: a local host beside a remote one is a WARN"
dbreset; out="$(dbrun DATABASE_URL='postgresql://app:FAKE648@127.acme648.net/app')"
dbwarn "--credentials, database: a host name that starts with 127. is not loopback"
dbreset; out="$(dbrun DATABASE_URL='postgresql://app:FAKE648@localhost/app?host=db.acme648.net')"
dbwarn "--credentials, database: a remote host= in the query warns beside a local authority"
dbreset; out="$(dbrun DATABASE_URL='postgresql:///app?host=/var/run/postgresql,db.acme648.net')"
dbwarn "--credentials, database: every host of a comma-separated host= list is judged"
dbreset; out="$(dbrun DATABASE_URL='postgresql://app:FAKE648@/app?hostaddr=203.0.113.5')"
dbwarn "--credentials, database: a remote hostaddr= is a destination, whatever host says"
dbreset; out="$(dbrun DATABASE_URL='postgresql://app:FAKE648@db.acme648.net/app?dbname=test&dbname=production')"
dbwarn "--credentials, database: the last dbname= is the database, as libpq reads it"
dbreset; out="$(dbrun DATABASE_URL='postgresql://app:FAKE648@db.acme648.net/app_test?dbname=prod')"
dbwarn "--credentials, database: a test path beside a dbname= that is not one warns"
dbreset; out="$(dbrun DATABASE_URL='postgresql:///app?service=main')"
dbwarn "--credentials, database: service= takes its host from a file not read, so it warns"
dbreset; out="$(dbrun DATABASE_URL='postgresql://app:FAKE648@db.acme648.net/app?dbname=app_test')"
dbquiet "--credentials, database: a dbname= naming a test database replaces the path"
dbreset; out="$(dbrun DATABASE_URL='postgresql://app:FAKE648@localhost/app?host=localhost&hostaddr=127.0.0.1')"
dbquiet "--credentials, database: a local hostaddr= beside a local host does not warn"
dbreset; out="$(dbrun DATABASE_URL='postgresql://app:FAKE648@[db.acme648.net/app')"
dbwarn "--credentials, database: a URL that cannot be parsed is a WARN, not passed over"
dbreset; printf 'APP_PORT=8000\nDATABASE_URL=%s\n' "$prod" > "$dbr/.env.production"; git -C "$dbr" add .env.production; out="$(dbrun)"
dbwarn "--credentials, database: a tracked .env.production names its file, line and variable"
is "$out" FC-G11 info \
  && ok "--credentials, database: the file's fix line" || bad "--credentials, database: the file's fix line"
dbreset; printf '.env\n' >> "$dbr/.gitignore"; printf 'export DATABASE_URL="%s"\n' "$prod" > "$dbr/.env"; out="$(dbrun)"
dbwarn "--credentials, database: an ignored, untracked .env with export and quotes is a WARN"
dbreset; mkdir -p "$dbr/apps/web"; printf "DB='%s'\n" "$prod" > "$dbr/apps/web/.env.local"; out="$(dbrun)"
dbwarn "--credentials, database: a .env.local in a subdirectory is a WARN"
dbreset; printf '%s/db=x\n' "$prod" > "$dbr/.env"; out="$(dbrun)"
dbwarn "--credentials, database: a line with no variable name prints only its file and line"
dbreset; printf '{"env":{"DATABASE_URL":"%s"}}\n' "$prod" > "$dbr/.claude/settings.local.json"; out="$(dbrun)"
dbwarn "--credentials, database: the env of the repository's .claude/settings.local.json is a WARN"
dbreset; python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["env"]={"DATABASE_URL":sys.argv[2]}; json.dump(d,open(p,"w"))' "$dbr/.claude/settings.json" "$prod"; out="$(dbrun)"
dbwarn "--credentials, database: the env of the repository's .claude/settings.json is a WARN"
dbreset; printf '{"env":{"DATABASE_URL":"%s"}}\n' "$prod" > "$dbu/settings.json"; out="$(dbrun)"
dbwarn "--credentials, database: the env of the user's settings.json is a WARN"
dbreset; printf '{"env":{"DATABASE_URL":"%s"}}\n' "$prod" > "$dbu/settings.local.json"; out="$(dbrun)"
dbwarn "--credentials, database: the env of the user's settings.local.json is a WARN"
dbreset; printf '{"env":{"postgres://x:FAKE648@acme648.net/a":"%s"}}\n' "$prod" > "$dbu/settings.json"; out="$(dbrun)"
dbwarn "--credentials, database: an env key that is not a name is not printed"
dbreset; printf 'DATABASE_URL=%s\n' "$prod" > "$dbr/.env"; printf '{"env":{"DATABASE_URL":"%s"}}\n' "$prod" > "$dbu/settings.json"; out="$(dbrun DATABASE_URL="$prod")"
[ "$(grep -c "WARN  a production database URL is within the agent's reach" <<<"$out")" = 3 ] && ! leaks \
  && ok "--credentials, database: three places hold it, three WARNs" || { bad "--credentials, database: three places"; db_lines | sed 's/^/        /'; }

# What cannot be read is a SKIP naming it.
dbreset; printf '{"env":' > "$dbu/settings.json"; out="$(dbrun)"
is "$out" FC-G11 unknown \
  && ok "--credentials, database: unreadable settings JSON is a SKIP" || { bad "--credentials, database: bad JSON"; db_lines | sed 's/^/        /'; }
dbreset; printf '{"env":["%s"]}\n' "$prod" > "$dbu/settings.json"; out="$(dbrun)"
is "$out" FC-G11 unknown && ! leaks \
  && ok "--credentials, database: an env that is not an object is a SKIP" || { bad "--credentials, database: env list"; db_lines | sed 's/^/        /'; }
if [ "$(id -u)" != 0 ]; then
  dbreset; printf 'DATABASE_URL=%s\n' "$prod" > "$dbr/.env"; chmod 000 "$dbr/.env"; out="$(dbrun)"; chmod 600 "$dbr/.env"
  is "$out" FC-G11 unknown && ! leaks \
    && ok "--credentials, database: an unreadable .env is a SKIP" || { bad "--credentials, database: unreadable .env"; db_lines | sed 's/^/        /'; }
fi
# ci / floor-check never passes --credentials: its own service URLs are not this item's question.
dbreset; out="$(env -i PATH="$PATH" HOME="$cred/home" CLAUDE_CONFIG_DIR="$dbu" DATABASE_URL="$prod" python3 "$checker" --root "$dbr" --no-network 2>&1)"
! grep -qi "database" <<<"$out" && ! leaks && ok "--credentials, database: without --credentials the item does not run" || bad "--credentials, database: ran without --credentials"

# The source of each required check is part of the wall: a required
# `ci / test` with no integration_id is satisfied by a commit status anyone
# with write access can post. The shipped ruleset pins GitHub Actions (15368);
# a live rule that lost or changed that pin is a weakened wall.
wall "a required check with its source pin removed is a FAIL" "FC-E20 fail" \
  "printf '%s' '$(printf '%s' "$good_rules" | sed 's/{"context":"ci \/ a","integration_id":15368}/{"context":"ci \/ a"}/')' > \"\$api/repos/o/r/rules/branches/main.json\""
wall "a required check pinned to another app is a FAIL" "FC-E20 fail" \
  "printf '%s' '$(printf '%s' "$good_rules" | sed 's/"context":"ci \/ b","integration_id":15368/"context":"ci \/ b","integration_id":999/')' > \"\$api/repos/o/r/rules/branches/main.json\""
printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"
wall "the source pins as shipped pass" "FC-E20 pass"
# Two active rulesets: GitHub enforces both, so a check is required when
# either requires it and pinned when either pins it.
wall "a check carried by a second ruleset is not dropped" "FC-E19 pass" \
  "printf '%s' '$(printf '%s' "$good_rules" | python3 -c 'import json,sys; r=json.load(sys.stdin); rsc=[x for x in r if x["type"]=="required_status_checks"][0]; a=json.loads(json.dumps(rsc)); a["parameters"]["required_status_checks"]=[{"context":"ci / a","integration_id":15368}]; a["ruleset_id"]=2; b=json.loads(json.dumps(rsc)); b["parameters"]["required_status_checks"]=[c for c in b["parameters"]["required_status_checks"] if c["context"]!="ci / a"]; print(json.dumps([x for x in r if x["type"]!="required_status_checks"]+[b,a]))')' > \"\$api/repos/o/r/rules/branches/main.json\""
wall "an unpinned duplicate beside a pinned one is not a source FAIL" "FC-E20 pass" \
  "printf '%s' '$(printf '%s' "$good_rules" | python3 -c 'import json,sys; r=json.load(sys.stdin); rsc=[x for x in r if x["type"]=="required_status_checks"][0]; a=json.loads(json.dumps(rsc)); a["parameters"]["required_status_checks"]=[{"context":"ci / a"}]; a["ruleset_id"]=2; print(json.dumps(r+[a]))')' > \"\$api/repos/o/r/rules/branches/main.json\""
wall "a strict rule beside a loose one is still strict" "FC-E18 pass" \
  "printf '%s' '$(printf '%s' "$good_rules" | python3 -c 'import json,sys; r=json.load(sys.stdin); rsc=[x for x in r if x["type"]=="required_status_checks"][0]; a=json.loads(json.dumps(rsc)); a["parameters"]["strict_required_status_checks_policy"]=False; a["ruleset_id"]=2; print(json.dumps(r+[a]))')' > \"\$api/repos/o/r/rules/branches/main.json\""
# Each rule of the wall missing, and a required-checks rule that is not
# strict, each once (#1103: every state a check declares is reached).
for t in non_fast_forward:FC-E14 pull_request:FC-E15 required_status_checks:FC-E16; do
  id="${t#*:}"; t="${t%%:*}"
  wall "a missing $t rule is caught" "$id fail" \
    "jq -c 'map(select(.type != \"$t\"))' <<<\"\$good_rules\" > \"\$api/repos/o/r/rules/branches/main.json\""
done
wall "a required-checks rule that is not strict is caught" "FC-E18 fail" \
  "jq -c 'map(if .type == \"required_status_checks\" then .parameters.strict_required_status_checks_policy = false else . end)' <<<\"\$good_rules\" > \"\$api/repos/o/r/rules/branches/main.json\""
# A ruleset that pins its checks to different apps is compared check by
# check; it does not switch the comparison off.
mixed="$work/mixed-ruleset.json"
python3 - "$root/ruleset.json" "$mixed" <<'MIXED'
import json, sys
d = json.load(open(sys.argv[1]))
for r in d["rules"]:
    if r["type"] == "required_status_checks":
        r["parameters"]["required_status_checks"] = [
            {"context": "ci / a", "integration_id": 15368}, {"context": "ci / b", "integration_id": 999}]
json.dump(d, open(sys.argv[2], "w"))
MIXED
mixed_out() { FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$mixed" --expect-checks "ci / a, ci / b" 2>&1; }
printf '%s' "$good_rules" | sed 's/"integration_id":15368//g; s/,}/}/g' > "$api/repos/o/r/rules/branches/main.json"
out="$(mixed_out)"
if [ "$(grep -c 'accepts a status from any source' <<<"$out")" = 2 ]; then ok "mixed-app ruleset: both unpinned checks FAIL, each against its own app"
else bad "mixed-app ruleset: unpinned checks not both caught"; grep -E 'FAIL|INFO|SKIP|PASS  main: required' <<<"$out" | sed 's/^/        /'; fi
printf '%s' "$good_rules" | sed 's/"context":"ci \/ b","integration_id":15368/"context":"ci \/ b","integration_id":999/' > "$api/repos/o/r/rules/branches/main.json"
out="$(mixed_out)"
if is "$out" FC-E20 pass; then ok "mixed-app ruleset: each check on its own app passes"
else bad "mixed-app ruleset: correct pins not passed"; grep -E 'FAIL|INFO|PASS  main: required' <<<"$out" | sed 's/^/        /'; fi
# A dropped check withholds the aggregate PASS too.
printf '%s' "$good_rules" | sed 's/,{"context":"ci \/ b","integration_id":15368}//' > "$api/repos/o/r/rules/branches/main.json"
out="$(mixed_out)"
if is "$out" FC-E19 fail && ! grep -q "required checks come from the expected apps" <<<"$out"; then
  ok "a dropped check withholds the aggregate source PASS"
else bad "a dropped check still produced the aggregate source PASS"; grep -E 'FAIL|PASS  main: required' <<<"$out" | sed 's/^/        /'; fi
printf '%s' "$good_rules" | sed 's/"context":"ci \/ b","integration_id":15368/"context":"ci \/ b","integration_id":999/' > "$api/repos/o/r/rules/branches/main.json"
# A check only --expect-checks names, with no shared app to assume, is not
# compared; the aggregate PASS must not claim it.
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$mixed" --expect-checks "ci / a, ci / b, CodeQL" 2>&1)"
if is "$out" FC-E20 unknown && ! grep -q "required checks come from the expected apps" <<<"$out"; then
  ok "an uncompared check (SKIP) withholds the aggregate source PASS"
else bad "an uncompared check still produced the aggregate source PASS"; grep -E 'SKIP|PASS  main: required' <<<"$out" | sed 's/^/        /'; fi
printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"

# --project separate from --root, expectations from --ruleset
sub="$work/sub"; rm -rf "$sub"; cp -R "$good" "$sub"; mkdir -p "$sub/app"; mv "$sub/pyproject.toml" "$sub/uv.lock" "$sub/.copier-answers.yml" "$sub/Dockerfile" "$sub/.dockerignore" "$sub/.env.example" "$sub/app/"; mv "$sub/src" "$sub/app/src"
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$sub" --project app --no-network --repo o/r --ruleset "$root/ruleset.json" 2>&1)"
if is "$out" FC-E19 fail && is "$out" FC-C02 pass; then ok "--project and --ruleset are honoured (ruleset's nine checks expected, project files found under app/)"
else bad "--project/--ruleset path"; printf '%s\n' "$out" | grep -E 'FAIL|INFO' | sed 's/^/        /'; fi

# The web archetype (#615), as plinth-template v1.20.0 renders it: a service
# archetype, so the image, .env.example and JSON logs items apply, and its
# render.yaml is an item of its own. Its ruleset adds ci / migrations and
# ci / deploy-check, and a wall without one is a FAIL with the command that
# puts it back.
web="$work/web"; rm -rf "$web"; cp -R "$good" "$web"
sed -i.bak 's/^archetype: backend$/archetype: web/' "$web/.copier-answers.yml"; rm "$web/.copier-answers.yml.bak"
printf 'services: []\n' > "$web/render.yaml"
printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%040d\n    with:\n      web: true\n  image:\n    steps:\n      - run: docker build -t t .\n      - run: docker run --rm t\n' 0 > "$web/.github/workflows/ci.yml"
git -C "$web" add -A
out="$(python3 "$checker" --root "$web" --no-network 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q -- '-- 0 failed' <<<"$out" && is "$out" FC-C12 pass && is "$out" FC-D06 pass \
   && is "$out" FC-C27 pass; then ok "a complete web instance passes offline, render.yaml, the image job and .env.example read"
else bad "a complete web instance should pass"; printf '%s\n' "$out" | grep -E 'FAIL|render|image' | sed 's/^/        /'; fi
rm "$web/render.yaml"; git -C "$web" add -A
out="$(python3 "$checker" --root "$web" --no-network 2>&1)"
if is "$out" FC-C12 fail && is "$out" FC-C12 info \
   && grep -q -- '-- 1 failed' <<<"$out"; then ok "a web instance without render.yaml: one FAIL, with its fix"
else bad "a web instance without render.yaml is not one FAIL with its fix"; printf '%s\n' "$out" | grep -E 'FAIL|INFO.*render' | sed 's/^/        /'; fi
printf 'services: []\n' > "$web/render.yaml"; git -C "$web" add -A
rm -rf "$web.empty"; cp -R "$web" "$web.empty"; sed -i.bak 's/^archetype: web$/archetype: cli/' "$web.empty/.copier-answers.yml"; rm "$web.empty/render.yaml"
git -C "$web.empty" add -A; out="$(python3 "$checker" --root "$web.empty" --no-network 2>&1)"
if is "$out" FC-C03 info && grep -q -- '-- 0 failed' <<<"$out" && ! grep -q 'render.yaml' <<<"$out"; then ok "another archetype is not asked for render.yaml"
else bad "a cli instance was asked for render.yaml"; fi
# A dashboard (#1069): plain, no image, and asked for render.yaml only when
# its answers say hosting: render; on its own computer, nothing is asked.
dash="$work/dash"; rm -rf "$dash"; cp -R "$web.empty" "$dash"
sed -i.bak 's/^archetype: cli$/archetype: dashboard/' "$dash/.copier-answers.yml"; rm "$dash/.copier-answers.yml.bak"
printf 'hosting: local\n' >> "$dash/.copier-answers.yml"; git -C "$dash" add -A
out="$(python3 "$checker" --root "$dash" --no-network 2>&1)"
if is "$out" FC-C03 info && grep -q -- '-- 0 failed' <<<"$out" && ! grep -q 'render.yaml' <<<"$out"; then ok "a dashboard on its own computer is not asked for render.yaml"
else bad "a dashboard with hosting: local"; printf '%s\n' "$out" | grep -E 'FAIL|render' | sed 's/^/        /'; fi
sed -i.bak 's/^hosting: local$/hosting: render/' "$dash/.copier-answers.yml"; rm "$dash/.copier-answers.yml.bak"; git -C "$dash" add -A
out="$(python3 "$checker" --root "$dash" --no-network 2>&1)"
if is "$out" FC-C12 fail && is "$out" FC-C12 info && grep -q 'render.yaml missing: a dashboard with hosting: render deploys from it' <<<"$out" \
   && grep -q -- '-- 1 failed' <<<"$out"; then ok "a dashboard on Render without render.yaml: one FAIL, in a dashboard's words, with its fix"
else bad "a dashboard on Render without render.yaml"; printf '%s\n' "$out" | grep -E 'FAIL|render' | sed 's/^/        /'; fi
printf 'services: []\n' > "$dash/render.yaml"; git -C "$dash" add -A
out="$(python3 "$checker" --root "$dash" --no-network 2>&1)"
if is "$out" FC-C12 pass && grep -q -- '-- 0 failed' <<<"$out"; then ok "a dashboard on Render with render.yaml passes, and no image is asked"
else bad "a dashboard on Render with render.yaml"; printf '%s\n' "$out" | grep -E 'FAIL|render' | sed 's/^/        /'; fi
# A cli that runs on GitHub on a schedule (#1070, coolbress/plinth-template#363)
# is a cli: its answer, its workflow and its data/ folder change nothing in
# the report, which is the same, line for line, as the cli's without them,
# but for the counts of files read; the new workflow's actions are read as
# pinned.
sched="$work/sched"; rm -rf "$sched"; cp -R "$web.empty" "$sched"
printf 'scheduled_run: true\n' >> "$sched/.copier-answers.yml"
mkdir -p "$sched/data"; printf '*\n!.gitignore\n!README.md\n' > "$sched/data/.gitignore"; printf '# Data\n' > "$sched/data/README.md"
cat > "$sched/.github/workflows/schedule.yml" <<'YAML'
name: Scheduled run
on:
  schedule:
    - cron: "17 6 * * *"
  workflow_dispatch:
permissions: {}
concurrency:
  group: scheduled-run
  cancel-in-progress: false
jobs:
  run:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - run: uv sync --locked --no-dev
      - run: |
          mkdir -p data/processed
          uv run --no-sync python -m app > data/processed/result.txt
      - uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
        with:
          name: results
          path: data/processed/
          if-no-files-found: error
YAML
git -C "$sched" add -A
plain_out="$(python3 "$checker" --root "$web.empty" --no-network 2>&1)"; sched_out="$(python3 "$checker" --root "$sched" --no-network 2>&1)"
uncount() { sed -E 's/[0-9]+/N/g'; }
if [ "$(printf '%s\n' "${sched_out//$sched/<root>}" | uncount)" = "$(printf '%s\n' "${plain_out//$web.empty/<root>}" | uncount)" ] \
   && grep -q -- '-- 0 failed' <<<"$sched_out" && grep -qF 'PASS  every action in 3 workflow files is pinned to a commit (3 uses)' <<<"$sched_out"
then ok "a cli with the scheduled run gets the same report as one without, its workflow's actions read as pinned"
else bad "a cli with the scheduled run is reported differently"; diff <(printf '%s\n' "${plain_out//$web.empty/<root>}") <(printf '%s\n' "${sched_out//$sched/<root>}") | sed 's/^/        /'; fi
# What render.yaml says (#811), read when the file is there: each web
# service's healthCheckPath and autoDeployTrigger: checksPass, a database plan
# other than free, and secret-named envVars set without a literal value. Each
# gap is a WARN with one fix line; a file this checker cannot read is a SKIP.
rb="$work/render-blueprint"; rm -rf "$rb"; cp -R "$web" "$rb"
cat > "$work/render-complete.yaml" <<'YAML'
# Render Blueprint: one web service and one Postgres.
services:
  - type: web
    name: "app"
    runtime: docker
    plan: 0.5c-512mb
    # Deploy a commit only after its checks pass.
    autoDeployTrigger: checksPass
    healthCheckPath: /healthz
    envVars:
      - key: DJANGO_SETTINGS_MODULE
        value: app.settings
      - key: DJANGO_SECRET_KEY
        generateValue: true
      - key: DJANGO_ALLOWED_HOSTS
        sync: false
      - key: DATABASE_URL
        fromDatabase:
          name: "app-db"
          property: connectionString
databases:
  - name: "app-db"
    plan: 0.1c-256mb
    diskSizeGB: 1
    ipAllowList: []
YAML
cp "$work/render-complete.yaml" "$rb/render.yaml"
blueprint_out() { git -C "$rb" add -A; python3 "$checker" --root "$rb" --no-network 2>&1; }
out="$(blueprint_out)"; rc=$?
if [ "$rc" = 0 ] && grep -q -- '-- 0 failed' <<<"$out" && ! grep -qE '^  (WARN|SKIP) +render.yaml' <<<"$out" \
   && is "$out" FC-C14 pass \
   && is "$out" FC-C15 pass \
   && is "$out" FC-C16 pass \
   && is "$out" FC-C17 pass; then
  ok "a render.yaml with all four settings: four PASS lines, no WARN"
else bad "a render.yaml with all four settings"; grep -E 'render|failed' <<<"$out" | sed 's/^/        /'; fi
gap() { # <name> <sed expression on the complete file> <id of the WARN and its fix line>
  sed -e "$2" "$work/render-complete.yaml" > "$rb/render.yaml"
  out="$(blueprint_out)"; rc=$?
  if [ "$rc" = 0 ] && grep -q -- '-- 0 failed' <<<"$out" && is "$out" "$3" warn && is "$out" "$3" info \
     && [ "$(grep -c '^  WARN  render.yaml' <<<"$out")" = 1 ]; then ok "render.yaml $1: one WARN with its fix, no FAIL"
  else bad "render.yaml $1"; grep -E 'render|failed' <<<"$out" | sed 's/^/        /'; fi
}
gap "without healthCheckPath" '/healthCheckPath/d' FC-C14
gap "deploying on every commit" 's/autoDeployTrigger: checksPass/autoDeployTrigger: commit/' FC-C15
gap "without autoDeployTrigger" '/autoDeployTrigger/d' FC-C15
gap "with a free database" 's/plan: 0.1c-256mb/plan: free/' FC-C16
gap "with a database naming no plan" '/plan: 0.1c-256mb/d' FC-C16
gap "with a free database behind a comment holding a quote" "s/plan: 0.1c-256mb/plan: free # don't/" FC-C16
gap "with a free database spelled Free" 's/plan: 0.1c-256mb/plan: Free/' FC-C16
gap "with its web service behind a comment holding a quote" "s/  - type: web/  - type: web # it's the app/;/healthCheckPath/d" FC-C14
gap "with a secret as a literal value" 's/generateValue: true/value: "not-so-secret"/' FC-C17
# A literal value for a name that holds no secret stays a PASS (the settings
# module), and so does a secret-named one set another way.
awk '{print} /DJANGO_ALLOWED_HOSTS/{getline; print; print "      - key: SENTRY_DSN"; print "        sync: false"}' \
  "$work/render-complete.yaml" > "$rb/render.yaml"
out="$(blueprint_out)"
if is "$out" FC-C17 pass && ! grep -q '^  WARN  render.yaml' <<<"$out" \
   && grep -q 'SENTRY_DSN' "$rb/render.yaml"; then
  ok "render.yaml: plain values and secrets set another way are not a WARN"
else bad "render.yaml: plain values or non-literal secrets were a WARN"; grep -E 'render' <<<"$out" | sed 's/^/        /'; fi
# All four gaps at once: four WARN lines, no PASS for them, still 0 failed.
sed -e '/healthCheckPath/d' -e '/autoDeployTrigger/d' -e 's/plan: 0.1c-256mb/plan: free/' -e 's/generateValue: true/value: x/' \
  "$work/render-complete.yaml" > "$rb/render.yaml"
out="$(blueprint_out)"; rc=$?
if [ "$rc" = 0 ] && grep -q -- '-- 0 failed' <<<"$out" && [ "$(grep -c '^  WARN  render.yaml' <<<"$out")" = 4 ] \
   && ! grep -q '^  PASS  render.yaml:' <<<"$out"; then ok "render.yaml with all four gaps: four WARN lines, no PASS for them, 0 failed"
else bad "render.yaml with all four gaps"; grep -E 'render|failed' <<<"$out" | sed 's/^/        /'; fi
# A form the reader does not read is a SKIP, counted (one more than the
# complete file gives), and never a PASS.
cp "$work/render-complete.yaml" "$rb/render.yaml"
read_count="$(blueprint_out | sed -nE 's/^-- 0 failed, ([0-9]+) not verified.*/\1/p')"
for form in 'services: [{type: web, name: app}]' $'databases:\n  - name: db\n    plan: "fr\\u0065e"' $'services:\n  - &web\n    type: web' $'services:\n  - type: web\n    name: app\n    buildCommand: |\n      make'; do
  printf '%s\n' "$form" > "$rb/render.yaml"
  out="$(blueprint_out)"
  if is "$out" FC-C13 unknown && ! grep -qE '^  (PASS|WARN)  render.yaml:' <<<"$out" \
     && grep -q -- "-- 0 failed, $((read_count + 1)) not verified" <<<"$out"; then ok "render.yaml in a form not read ($(head -1 <<<"$form" | cut -c1-30)...): one SKIP, no PASS"
  else bad "render.yaml in a form not read ($(head -1 <<<"$form"))"; grep -E 'render|failed' <<<"$out" | sed 's/^/        /'; fi
done
# Resources nested under projects[].environments[] or ungrouped are not
# read: the file is one SKIP, never a PASS for what sits there (#817 review).
for form in $'envVarGroups:\n  - name: shared\n    envVars:\n      - key: LOG_LEVEL\n        value: info\nprojects:\n  - name: p\n    environments:\n      - name: prod\n        databases:\n          - name: db\n            plan: free' \
            $'ungrouped:\n  - type: web\n    name: app'; do
  printf '%s\n' "$form" > "$rb/render.yaml"
  out="$(blueprint_out)"
  if is "$out" FC-C13 unknown && ! grep -qE '^  (PASS|WARN)  render.yaml:' <<<"$out"; then ok "render.yaml with $(grep -oE '^(projects|ungrouped)' <<<"$form"): a SKIP, no PASS"
  else bad "render.yaml with $(grep -oE '^(projects|ungrouped)' <<<"$form")"; grep -E 'render' <<<"$out" | sed 's/^/        /'; fi
done
# A backslash escape in double quotes, in a key as in a value, is a SKIP;
# the SKIP line names the line, never what it holds, since ci / floor-check
# publishes it as an annotation (#817 review).
for form in $'services:\n  - type: web\n    name: app\n    envVars:\n      - key: DATABASE_URL\n        "val\\u0075e": postgres://u:hunter2secret@h/db' \
            $'services:\n  - type: web\n    name: app\n    envVars:\n      - key: DATABASE_URL\n        value: "postgres://u:hunter2secret@h/db?x=\\u0061"' \
            $'services:\n  - type: web\n    name: app: hunter2secret'; do
  printf '%s\n' "$form" > "$rb/render.yaml"
  out="$(blueprint_out)"
  if is "$out" FC-C13 unknown && ! grep -qE '^  (PASS|WARN)  render.yaml:' <<<"$out" \
     && ! grep -q 'hunter2secret' <<<"$out"; then ok "render.yaml line $(tail -1 <<<"$form" | sed 's/^ *//' | cut -c1-24)...: a SKIP naming the line, not its content"
  else bad "render.yaml line $(tail -1 <<<"$form" | cut -c1-40)"; grep -E 'render' <<<"$out" | sed 's/^/        /'; fi
done
# An empty file, or one with no envVars at all, reads nothing to pass.
printf '# nothing here yet\n' > "$rb/render.yaml"
out="$(blueprint_out)"
if ! grep -q '^  PASS  render.yaml:' <<<"$out" && is "$out" FC-C17 info; then ok "an empty render.yaml gets no PASS for what it does not say"
else bad "an empty render.yaml"; grep -E 'render' <<<"$out" | sed 's/^/        /'; fi
# A nested list or a plain value holding ': ' is not read as a string.
for form in $'services:\n  - - type: web' $'services:\n  - type: web\n    name: a: b'; do
  printf '%s\n' "$form" > "$rb/render.yaml"
  out="$(blueprint_out)"
  if is "$out" FC-C13 unknown && ! grep -qE '^  (PASS|WARN)  render.yaml:' <<<"$out"; then ok "render.yaml with $(tail -1 <<<"$form" | sed 's/^ *//'): a SKIP"
  else bad "render.yaml with $(tail -1 <<<"$form")"; grep -E 'render' <<<"$out" | sed 's/^/        /'; fi
done
# A repository not made as a web instance still has its render.yaml read;
# without one, nothing is said (the cli case above).
sed 's/plan: 0.1c-256mb/plan: free/' "$work/render-complete.yaml" > "$web.empty/render.yaml"
git -C "$web.empty" add -A; out="$(python3 "$checker" --root "$web.empty" --no-network 2>&1)"
if is "$out" FC-C16 warn && ! grep -q 'render.yaml present' <<<"$out" \
   && grep -q -- '-- 0 failed' <<<"$out"; then ok "a cli instance carrying render.yaml has it read, as a WARN, not asked for it"
else bad "a cli instance carrying render.yaml"; grep -E 'render|failed' <<<"$out" | sed 's/^/        /'; fi
rm -f "$web.empty/render.yaml"; git -C "$web.empty" add -A
rm -rf "$rb"
# The hosting answer (#678, plinth-template#128): `render`, the default, or
# `elsewhere` with a hosting_elsewhere place. A web instance rendered before
# the question has no hosting key and is a Render one; `hosting: render` and
# no key read the same, with or without render.yaml, and so does a cli
# instance carrying answers the template never records for it.
web_hosted="$work/web.hosted"
hosted_out() { # <dir> <archetype> <answer lines> <render.yaml: keep|drop>
  rm -rf "$web_hosted"; cp -R "$1" "$web_hosted"
  sed -i.bak "s/^archetype: .*/archetype: $2/" "$web_hosted/.copier-answers.yml"; rm "$web_hosted/.copier-answers.yml.bak"
  [ -z "$3" ] || printf '%b' "$3" >> "$web_hosted/.copier-answers.yml"
  [ "$4" = keep ] || rm -f "$web_hosted/render.yaml"
  git -C "$web_hosted" add -A; python3 "$checker" --root "$web_hosted" --no-network 2>&1
}
for keep in keep drop; do
  if [ "$(hosted_out "$web" web 'hosting: render\n' "$keep")" = "$(hosted_out "$web" web '' "$keep")" ]; then
    ok "web with hosting: render reads as one with no hosting key (render.yaml: $keep)"
  else bad "web with hosting: render differs from no hosting key (render.yaml: $keep)"
    diff <(hosted_out "$web" web 'hosting: render\n' "$keep") <(hosted_out "$web" web '' "$keep") | sed 's/^/        /'; fi
done
if [ "$(hosted_out "$web" cli 'hosting: elsewhere\nhosting_elsewhere: home\n' drop)" = "$(hosted_out "$web" cli '' drop)" ]; then
  ok "a cli instance's output does not move with a hosting answer"
else bad "a cli instance's output moved with a hosting answer"; fi
# `elsewhere`: no render.yaml item, one INFO naming the place. vps and home
# leave HTTPS, backups and closed ports to a person, which no item here reads:
# an INFO that says so, never a PASS.
for place in railway digitalocean fly vps home; do
  out="$(hosted_out "$web" web "hosting: elsewhere\nhosting_elsewhere: $place\n" drop)"; rc=$?
  if [ "$rc" = 0 ] && grep -q -- '-- 0 failed' <<<"$out" && ! grep -q '^  FAIL  render.yaml' <<<"$out" \
     && ! grep -q '^  PASS .*render.yaml' <<<"$out" \
     && is "$out" FC-C18 info; then
    ok "web with hosting: elsewhere ($place) and no render.yaml: no FAIL, one INFO naming $place"
  else bad "web with hosting: elsewhere ($place) and no render.yaml"; printf '%s\n' "$out" | grep -E 'FAIL|render|elsewhere' | sed 's/^/        /'; fi
  case "$place" in
    vps|home)
      if is "$out" FC-C18 info \
         && ! grep -qE '^  PASS .*(HTTPS|backup|port)' <<<"$out"; then ok "hosting_elsewhere: $place says what plinth does not check, as an INFO"
      else bad "hosting_elsewhere: $place does not say what plinth does not check"; printf '%s\n' "$out" | grep -E 'HTTPS|not checked' | sed 's/^/        /'; fi ;;
    *)
      if ! grep -q 'not checked by plinth' <<<"$out"; then ok "hosting_elsewhere: $place carries no line meant for vps and home"
      else bad "hosting_elsewhere: $place carries the vps/home line"; fi ;;
  esac
done
out="$(hosted_out "$web" web 'hosting: elsewhere\n' drop)"
if grep -q -- '-- 0 failed' <<<"$out" && is "$out" FC-C18 info; then
  ok "hosting: elsewhere with no hosting_elsewhere answer says that none is recorded"
else bad "hosting: elsewhere with no hosting_elsewhere answer"; printf '%s\n' "$out" | grep -E 'FAIL|render' | sed 's/^/        /'; fi
rm -rf "$web_hosted"
# A cli or library publishes on a version tag through release.yml
# (plinth-template 1.29.0, #703). Each finding is a WARN: an instance rendered
# before the file existed still has 0 failed. GitLab renders none.
pkg="$work/pkg"; rm -rf "$pkg"; cp -R "$web.empty" "$pkg"; rm -f "$pkg/.github/workflows/release.yml"
release_out() { git -C "$pkg" add -A; python3 "$checker" --root "$pkg" --no-network 2>&1; }
rel=.github/workflows/release.yml
out="$(release_out)"
if is "$out" FC-C08 warn \
   && is "$out" FC-C08 info \
   && grep -q -- '-- 0 failed' <<<"$out"; then ok "a cli instance without release.yml: a WARN with its fix, 0 failed"
else bad "a cli instance without release.yml"; printf '%s\n' "$out" | grep -E 'FAIL|release' | sed 's/^/        /'; fi
printf '# on: pull_request in a comment is not a trigger\nname: Release\non:\n  push:\n    tags: ["v*"]  # a version tag\npermissions: {}\njobs:\n  publish:\n    environment: pypi\n    permissions:\n      id-token: write\n    steps:\n      - uses: pypa/gh-action-pypi-publish@%040d\n      - run: gh release create "$GITHUB_REF_NAME"\n        env:\n          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}\n' 0 > "$pkg/$rel"
for a in cli library; do
  sed -i.bak "s/^archetype: .*/archetype: $a/" "$pkg/.copier-answers.yml"; rm "$pkg/.copier-answers.yml.bak"
  out="$(release_out)"
  if is "$out" FC-C08 pass && is "$out" FC-C09 pass \
     && is "$out" FC-C10 pass && ! grep -q "WARN  $rel" <<<"$out"; then ok "$a: the template's shape of release.yml passes its three items"
  else bad "$a: the template's shape of release.yml"; printf '%s\n' "$out" | grep -E 'release' | sed 's/^/        /'; fi
done
cp "$pkg/$rel" "$pkg/release.good"
for case in "pull_request|  pull_request:" "branches|    branches: [main]" "workflow_dispatch|  workflow_dispatch:" \
            "a quoted branches|    \"branches\": [main]" "a quoted workflow_dispatch|  \"workflow_dispatch\":"; do
  what="${case%%|*}"; line="${case#*|}"
  awk -v add="$line" '{print} /^    tags:/ {print add}' "$pkg/release.good" > "$pkg/$rel"
  out="$(release_out)"
  if grep -qF "WARN  $rel is not read as tag-only (first line not read: ${line#"${line%%[! ]*}"})" <<<"$out" \
     && ! grep -qF "PASS  $rel runs on a pushed tag only" <<<"$out" && grep -q -- '-- 0 failed' <<<"$out"; then ok "release.yml started by $what as well as a tag: a WARN naming the line"
  else bad "release.yml started by $what was not warned"; printf '%s\n' "$out" | grep -E 'release' | sed 's/^/        /'; fi
done
sed 's/^      - run: gh release create.*/      - uses: pypa\/gh-action-pypi-publish@0000000000000000000000000000000000000000\n        with:\n          password: ${{ secrets.PYPI_API_TOKEN }}/' "$pkg/release.good" > "$pkg/$rel"
out="$(release_out)"
if is "$out" FC-C10 warn && grep -q -- '-- 0 failed' <<<"$out"; then ok "release.yml with a stored PyPI token: a WARN naming it"
else bad "release.yml with a stored PyPI token was not warned"; printf '%s\n' "$out" | grep -E 'release' | sed 's/^/        /'; fi
# --project: the project one directory down, the workflow at the root,
# where GitHub reads it (#720 review).
cp "$pkg/release.good" "$pkg/$rel"
sub_pkg="$work/pkg-sub"; rm -rf "$sub_pkg"; mkdir -p "$sub_pkg/app"; cp -R "$pkg/.github" "$sub_pkg/"
for f in pyproject.toml uv.lock .copier-answers.yml src; do cp -R "$pkg/$f" "$sub_pkg/app/"; done
git -C "$sub_pkg" init -q; git -C "$sub_pkg" add -A
out="$(python3 "$checker" --root "$sub_pkg" --project app --no-network 2>&1)"
if is "$out" FC-C08 pass && is "$out" FC-C09 pass && ! grep -q "WARN  $rel" <<<"$out"; then
  ok "--project app: release.yml read at the repository root"
else bad "--project app: release.yml not read at the root"; printf '%s\n' "$out" | grep -E 'release|FAIL' | sed 's/^/        /'; fi
rm -rf "$sub_pkg"
# --host wins over the answers, as for every other host-dependent item (#720 review).
out="$(git -C "$pkg" add -A; python3 "$checker" --root "$pkg" --no-network --host gitlab 2>&1)"
if is "$out" FC-C08 info && ! grep -q "PASS  $rel" <<<"$out"; then ok "--host gitlab over a GitHub answer: release.yml not asked"
else bad "--host gitlab did not reach the release item"; printf '%s\n' "$out" | grep -E 'release' | sed 's/^/        /'; fi
rm "$pkg/$rel"; printf 'host: gitlab\n' >> "$pkg/.copier-answers.yml"
out="$(release_out)"
if is "$out" FC-C08 info && ! grep -q "WARN  $rel" <<<"$out"; then ok "a GitLab library is not asked for release.yml"
else bad "a GitLab library was asked for release.yml"; fi
cp "$pkg/release.good" "$pkg/$rel"
out="$(git -C "$pkg" add -A; python3 "$checker" --root "$pkg" --no-network --host github 2>&1)"
if is "$out" FC-C09 pass && ! grep -q "not required: on GitLab" <<<"$out"; then ok "--host github over a GitLab answer: release.yml read"
else bad "--host github did not reach the release item"; printf '%s\n' "$out" | grep -E 'release' | sed 's/^/        /'; fi
rm "$pkg/$rel"
rm -rf "$pkg"
# A backend publishes its image to GHCR on a version tag through the same
# file (plinth-template 1.30.0, #706): the same three items, each a WARN.
img="$work/img"; rm -rf "$img"; cp -R "$good" "$img"; rm "$img/$rel"
img_out() { git -C "$img" add -A; python3 "$checker" --root "$img" --no-network 2>&1; }
out="$(img_out)"
if is "$out" FC-C08 warn \
   && is "$out" FC-C08 info \
   && grep -q -- '-- 0 failed' <<<"$out"; then ok "a backend instance without release.yml: a WARN with its fix, 0 failed"
else bad "a backend instance without release.yml"; printf '%s\n' "$out" | grep -E 'FAIL|release' | sed 's/^/        /'; fi
printf 'name: Release\non:\n  push:\n    tags: ["v*"]\npermissions: {}\njobs:\n  image:\n    permissions:\n      packages: write\n    steps:\n      - name: Log in to GHCR with this run'"'"'s token\n        env:\n          GH_TOKEN: ${{ github.token }}\n        run: printf '"'"'%%s\\n'"'"' "$GH_TOKEN" | docker login ghcr.io --username "$GITHUB_ACTOR" --password-stdin\n      - uses: docker/build-push-action@%040d\n        with:\n          push: true\n' 0 > "$img/$rel"
out="$(img_out)"
if is "$out" FC-C08 pass && is "$out" FC-C09 pass \
   && is "$out" FC-C10 pass && ! grep -q "WARN  $rel" <<<"$out"; then ok "backend: the template's shape of release.yml passes its three items"
else bad "backend: the template's shape of release.yml"; printf '%s\n' "$out" | grep -E 'release' | sed 's/^/        /'; fi
cp "$img/$rel" "$img/release.good"
awk '{print} /^    tags:/ {print "  pull_request:"}' "$img/release.good" > "$img/$rel"
out="$(img_out)"
if is "$out" FC-C09 warn && grep -q -- '-- 0 failed' <<<"$out"; then ok "backend release.yml started by a pull request as well: a WARN naming the line"
else bad "backend release.yml started by a pull request was not warned"; printf '%s\n' "$out" | grep -E 'release' | sed 's/^/        /'; fi
sed 's/\${{ github.token }}/${{ secrets.GHCR_TOKEN }}/' "$img/release.good" > "$img/$rel"
out="$(img_out)"
if is "$out" FC-C10 warn && grep -q -- '-- 0 failed' <<<"$out"; then ok "backend release.yml with a stored registry token: a WARN naming it"
else bad "backend release.yml with a stored registry token was not warned"; printf '%s\n' "$out" | grep -E 'release' | sed 's/^/        /'; fi
rm "$img/$rel"; printf 'host: gitlab\n' >> "$img/.copier-answers.yml"
out="$(img_out)"
if is "$out" FC-C08 info && ! grep -q "WARN  $rel" <<<"$out"; then ok "a GitLab backend is not asked for release.yml"
else bad "a GitLab backend was asked for release.yml"; printf '%s\n' "$out" | grep -E 'release' | sed 's/^/        /'; fi
rm -rf "$img"
# A data-ml project publishes its model, metrics and card to a GitHub Release
# through the same file (plinth-template 1.31.0, #716): the same three items,
# no pickle among its ASSETS, and the card beside it. Each a WARN.
ml="$work/ml"; rm -rf "$ml"; cp -R "$good" "$ml"; rm "$ml/$rel"
sed -i.bak "s/^archetype: .*/archetype: data-ml/" "$ml/.copier-answers.yml"; rm "$ml/.copier-answers.yml.bak"
ml_out() { git -C "$ml" add -A; python3 "$checker" --root "$ml" --no-network 2>&1; }
out="$(ml_out)"
if is "$out" FC-C08 warn \
   && is "$out" FC-C08 info \
   && is "$out" FC-C07 warn \
   && is "$out" FC-C07 info \
   && grep -q -- '-- 0 failed' <<<"$out"; then ok "a data-ml instance from before 1.31.0: two WARNs with their fixes, 0 failed"
else bad "a data-ml instance from before 1.31.0"; printf '%s\n' "$out" | grep -E 'FAIL|release|MODEL_CARD' | sed 's/^/        /'; fi
printf '# Model card\n' > "$ml/MODEL_CARD.md"
printf 'name: Release\non:\n  push:\n    tags: ["v*"]\npermissions: {}\n# Never a pickle (`.pkl`, `.pickle`, `.joblib`, `.pt`).\nenv:\n  ASSETS: model.skops metrics.json MODEL_CARD.md\njobs:\n  publish:\n    permissions:\n      contents: write\n    steps:\n      - run: |\n          case "$f" in *.pkl | *.pickle | *.joblib | *.pt) exit 1 ;; esac\n      - env:\n          GH_TOKEN: ${{ github.token }}\n        run: gh release create "$GITHUB_REF_NAME" --verify-tag $ASSETS SHA256SUMS\n' > "$ml/$rel"
out="$(ml_out)"
if is "$out" FC-C08 pass && is "$out" FC-C09 pass \
   && is "$out" FC-C10 pass \
   && is "$out" FC-C11 pass \
   && is "$out" FC-C07 pass && ! grep -q "WARN  $rel" <<<"$out"; then ok "data-ml: the template's shape of release.yml and the card pass"
else bad "data-ml: the template's shape of release.yml and the card"; printf '%s\n' "$out" | grep -E 'release|MODEL_CARD' | sed 's/^/        /'; fi
cp "$ml/$rel" "$ml/release.good"
sed 's/ASSETS: model.skops/ASSETS: model.pkl/' "$ml/release.good" > "$ml/$rel"
out="$(ml_out)"
if is "$out" FC-C11 warn && grep -q -- '-- 0 failed' <<<"$out"; then ok "data-ml release.yml that uploads a pickle: a WARN naming it"
else bad "data-ml release.yml that uploads a pickle was not warned"; printf '%s\n' "$out" | grep -E 'release' | sed 's/^/        /'; fi
sed 's/ASSETS: model.skops metrics.json/ASSETS: "model.skops weights.PT/' "$ml/release.good" | sed 's/MODEL_CARD.md$/MODEL_CARD.md"/' > "$ml/$rel"
out="$(ml_out)"
if is "$out" FC-C11 warn; then ok "a quoted ASSETS line with an upper-case .PT: still a pickle"
else bad "a quoted ASSETS line with an upper-case .PT was not warned"; printf '%s\n' "$out" | grep -E 'release' | sed 's/^/        /'; fi
for value in '>-\n    model.pkl' 'model.skops\n    model.pkl' '${{ vars.ASSETS }}' 'model.skops (and a second ASSETS: model.pkl)'; do
  case "$value" in
    *second*) sed 's/^  publish:$/  publish:\n    env:\n      ASSETS: model.pkl/' "$ml/release.good" > "$ml/$rel" ;;
    *) sed "s/ASSETS: .*/ASSETS: $value/" "$ml/release.good" > "$ml/$rel" ;;
  esac
  out="$(ml_out)"
  if is "$out" FC-C11 unknown && ! grep -q "PASS  $rel uploads no pickle" <<<"$out"; then ok "ASSETS: $value: not verified, not passed"
  else bad "ASSETS: $value was passed or not reported"; printf '%s\n' "$out" | grep -E 'release' | sed 's/^/        /'; fi
done
grep -v 'ASSETS:' "$ml/release.good" > "$ml/$rel"
out="$(ml_out)"
if is "$out" FC-C11 unknown; then ok "data-ml release.yml without an ASSETS line: not verified, not passed"
else bad "data-ml release.yml without an ASSETS line"; printf '%s\n' "$out" | grep -E 'release' | sed 's/^/        /'; fi
rm "$ml/$rel"; printf 'host: gitlab\n' >> "$ml/.copier-answers.yml"
out="$(ml_out)"
if is "$out" FC-C08 info \
   && is "$out" FC-C07 pass && ! grep -q "WARN  $rel" <<<"$out"; then ok "a GitLab data-ml: no release.yml asked, the card still read"
else bad "a GitLab data-ml"; printf '%s\n' "$out" | grep -E 'release|MODEL_CARD' | sed 's/^/        /'; fi
rm -rf "$ml"
# web deploys on green and publishes nothing on a tag: not asked.
other="$work/other-web"; rm -rf "$other"; cp -R "$good" "$other"
sed -i.bak "s/^archetype: .*/archetype: web/" "$other/.copier-answers.yml"; rm "$other/.copier-answers.yml.bak"
git -C "$other" add -A
out="$(python3 "$checker" --root "$other" --no-network 2>&1)"
if ! grep -q "release.yml\|MODEL_CARD" <<<"$out"; then ok "a web instance is not asked for release.yml or a model card"
else bad "a web instance was asked for release.yml or a model card"; fi
rm -rf "$other"
web_rules="$(python3 "$checker" --print-ruleset --ruleset "$root/ruleset.json" --archetype web | jq -c '[.rules[] | . + {ruleset_source_type: "Repository", ruleset_id: 1}]')"
for drop in "ci / migrations" "ci / deploy-check"; do
  jq -c --arg d "$drop" 'map(if .type == "required_status_checks" then .parameters.required_status_checks |= map(select(.context != $d)) else . end)' <<<"$web_rules" > "$api/repos/o/r/rules/branches/main.json"
  out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$web" --no-network --repo o/r --ruleset "$root/ruleset.json" 2>&1)"
  if is "$out" FC-E19 fail \
     && is "$out" FC-E19 info \
     && [ "$(grep -c '^  FAIL ' <<<"$out")" = 1 ]; then ok "a web wall without $drop: one FAIL, with the command that requires it again"
  else bad "a web wall without $drop is not one FAIL with its fix"; printf '%s\n' "$out" | grep -E 'FAIL|INFO.*upgrade' | sed 's/^/        /'; fi
done
jq -c . <<<"$web_rules" > "$api/repos/o/r/rules/branches/main.json"
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$web" --no-network --repo o/r --ruleset "$root/ruleset.json" 2>&1)"
if is "$out" FC-E19 pass && ! grep -q '^  FAIL ' <<<"$out"; then ok "a web wall with the image and both web checks passes (12 checks)"
else bad "the full web wall does not pass"; printf '%s\n' "$out" | grep -E 'FAIL|expected checks' | sed 's/^/        /'; fi
printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"

# An archetype move that adds a check (#1017): the move's own pull request
# records backend while main still records cli and requires cli's nine, and
# `image` cannot be required before it has run on main. A SKIP that names the
# command, only while main's recorded archetype lacks the check and this
# checkout's has it; once main records it too, the FAIL is back.
cli_rules="$(python3 "$checker" --print-ruleset --ruleset "$root/ruleset.json" --archetype cli | jq -c '[.rules[] | . + {ruleset_source_type: "Repository", ruleset_id: 1}]')"
on_main="$api/repos/o/r/contents/.copier-answers.yml?ref=main.json"
main_records() { printf '{"encoding":"base64","content":"%s"}' "$(printf '_commit: %s\narchetype: %s\n' "$target_ref" "$1" | base64 | tr -d '\n')" > "$on_main"; }
move_wall() { FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" 2>&1; }
printf '%s' "$cli_rules" > "$api/repos/o/r/rules/branches/main.json"
rm -f "$on_main"; out="$(move_wall)"
if is "$out" FC-E19 fail; then ok "a move's wall seen failing: main's archetype not read, image not required, a FAIL (#1017)"
else bad "no answers on main: not the FAIL"; printf '%s\n' "$out" | grep -E 'FAIL|SKIP.*image' | sed 's/^/        /'; fi
main_records cli; out="$(move_wall)"
if is "$out" FC-E19 unknown \
   && ! grep -q "required checks dropped" <<<"$out" && ! grep -q "PASS  main: all .* expected checks are required" <<<"$out"
then ok "main records cli, the checkout backend: image is a SKIP naming the command, not a FAIL (#1017)"
else bad "a move to backend: not the SKIP"; printf '%s\n' "$out" | grep -E 'FAIL|SKIP.*image|expected checks' | sed 's/^/        /'; fi
main_records backend; out="$(move_wall)"
if is "$out" FC-E19 fail && ! grep -q "not required yet" <<<"$out"
then ok "once main records backend too, image not required is a FAIL again (#1017)"
else bad "main at backend: not the FAIL"; printf '%s\n' "$out" | grep -E 'FAIL|SKIP.*image' | sed 's/^/        /'; fi
main_records data-ml; out="$(move_wall)"
if is "$out" FC-E19 fail; then ok "main records data-ml, which runs image too: a FAIL, not a move's SKIP"
else bad "main at data-ml: not the FAIL"; printf '%s\n' "$out" | grep -E 'FAIL|SKIP.*image' | sed 's/^/        /'; fi
printf 'not json' > "$on_main"; out="$(move_wall)"
if is "$out" FC-E19 fail; then ok "main's answers unreadable: a FAIL, never a SKIP read from nothing"
else bad "unreadable answers on main: not the FAIL"; printf '%s\n' "$out" | grep -E 'FAIL|SKIP.*image' | sed 's/^/        /'; fi
main_records cli
jq -c 'map(if .type == "required_status_checks" then .parameters.required_status_checks |= map(select(.context != "ci / lint")) else . end)' <<<"$cli_rules" > "$api/repos/o/r/rules/branches/main.json"
out="$(move_wall)"
if is "$out" FC-E19 fail && is "$out" FC-E19 unknown \
   && is "$out" FC-E19 info && ! grep -qF "'image:15368'" <<<"$out"
then ok "a move that also drops another check: that one is a FAIL, image alone the SKIP"
else bad "a move with another check dropped"; printf '%s\n' "$out" | grep -E 'FAIL|SKIP.*image|upgrade' | sed 's/^/        /'; fi
rm -f "$on_main"; printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"
# The move's plan asks whether the plinth a project calls has this rule by
# this line in its floor-check.py; the line must stay what it looks for.
grep -q '^def archetype_gained(' "$checker" && ok "floor-check.py still carries the line a move's plan looks for (#1017)" \
  || bad "floor-check.py lost the def archetype_gained( line the move's plan reads"
# Likewise python-ci.yml's line opening the rule that leaves release.yml out
# of a move's diff-size count (#1044), read with floor-check.py's own pattern.
python3 - "$checker" "$root/.github/workflows/python-ci.yml" <<'PY' && ok "python-ci.yml still carries the line a move's plan looks for (#1044)" \
  || bad "python-ci.yml lost the line SIZE_RULE looks for (#1044)"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("fc", sys.argv[1]); fc = importlib.util.module_from_spec(spec); spec.loader.exec_module(fc)
sys.exit(0 if len(fc.SIZE_RULE.findall(open(sys.argv[2], encoding="utf-8").read())) == 1 else 1)
PY

# #221: run at the root of a repository whose project is one directory down,
# the checker reports two files missing that do exist. The answer is --project,
# so the FAIL line names it when exactly one directory below --root holds a
# pyproject.toml. Which project is meant stays the user's to say: the checker
# neither guesses nor re-runs itself.
out="$(python3 "$checker" --root "$sub" --no-network 2>&1)"; rc=$?
if is "$out" FC-C01 fail \
&& is "$out" FC-C02 fail
then ok "one pyproject.toml one level down: both FAIL lines name the directory and the flag"
else bad "the --project hint"; printf '%s\n' "$out" | grep -E 'FAIL|INFO' | sed 's/^/        /'; fi
# The hint replaces the wording of two FAILs and adds no line of its own. The
# baseline is the same tree with the candidate behind a name the search skips,
# so a check added elsewhere later moves both summaries together and this case
# keeps testing the hint rather than the fixture's totals.
phid0="$work/proj-baseline"; rm -rf "$phid0"; cp -R "$sub" "$phid0"; mv "$phid0/app" "$phid0/.app"
base="$(python3 "$checker" --root "$phid0" --no-network 2>&1 | grep -- '^-- ')"
hint="$(grep -- '^-- ' <<<"$out")"
if [ "$rc" = 1 ] && [ -n "$base" ] && [ "$hint" = "$base" ]
then ok "the hint leaves the exit code and the summary line alone (same summary as with no candidate)"
else bad "the hint changed the exit code or the summary (rc=$rc, hint='$hint', baseline='$base')"; fi
# The line is actionable as printed: run it again that way and both items pass.
out="$(python3 "$checker" --root "$sub" --project app --no-network 2>&1)"
if is "$out" FC-C01 pass && is "$out" FC-C02 pass
then ok "the hinted --project turns both project items to PASS"
else bad "the hinted --project"; printf '%s\n' "$out" | grep -E 'FAIL|PASS  (pyproject|uv)' | sed 's/^/        /'; fi

pnone="$work/proj-none"; rm -rf "$pnone"; cp -R "$good" "$pnone"; rm "$pnone/pyproject.toml"
out="$(python3 "$checker" --root "$pnone" --no-network 2>&1)"
if is "$out" FC-C01 fail && ! grep -q -- "--project" <<<"$out"
then ok "no pyproject.toml below the root: the line stays as it was, with no hint"
else bad "no candidate below the root"; printf '%s\n' "$out" | grep -E 'FAIL|INFO' | sed 's/^/        /'; fi

ptwo="$work/proj-two"; rm -rf "$ptwo"; cp -R "$sub" "$ptwo"; mkdir -p "$ptwo/svc"; cp "$ptwo/app/pyproject.toml" "$ptwo/svc/pyproject.toml"
out="$(python3 "$checker" --root "$ptwo" --no-network 2>&1)"; rc=$?
if is "$out" FC-C01 fail && is "$out" FC-C01 info && [ "$rc" = 1 ] && grep -q -- '-- 2 failed, 3 not verified' <<<"$out"
then ok "two candidates: today's line, both paths listed, and no choice made for the user"
else bad "two candidates below the root (rc=$rc)"; printf '%s\n' "$out" | grep -E 'FAIL|INFO|failed' | sed 's/^/        /'; fi

# The search is the first thing in the run to list the root's entries, so a
# --root that is not there reaches it: it reports, it does not traceback.
out="$(python3 "$checker" --root "$work/not-a-checkout" --no-network 2>&1)"; rc=$?
if [ "$rc" = 1 ] && is "$out" FC-C01 fail && ! grep -q "Traceback" <<<"$out"
then ok "a --root that does not exist is reported, not a traceback"
else bad "a --root that does not exist (rc=$rc)"; printf '%s\n' "$out" | tail -5 | sed 's/^/        /'; fi

# A caller that named a --project chose it. Sending them to a different
# project below the root is sending them away from the one they meant to
# repair, so the search runs only when this run is checking the root itself.
psel="$work/proj-selected"; rm -rf "$psel"; cp -R "$sub" "$psel"; mkdir -p "$psel/svc"
out="$(python3 "$checker" --root "$psel" --project svc --no-network 2>&1)"
if is "$out" FC-C01 fail && is "$out" FC-C02 fail \
&& ! grep -q -- "--project=" <<<"$out"
then ok "a --project the caller named is not redirected to another project below the root"
else bad "a named --project was redirected"; printf '%s\n' "$out" | grep -E 'FAIL|INFO' | sed 's/^/        /'; fi
# ...and the same tree checked at the root still gets the hint, so the guard
# narrows the search rather than switching it off.
out="$(python3 "$checker" --root "$psel" --no-network 2>&1)"
if grep -q "run again with --project=app" <<<"$out"
then ok "the same tree checked at the root still names app/"
else bad "the root run lost its hint"; printf '%s\n' "$out" | grep -E 'FAIL' | sed 's/^/        /'; fi

# Once a project has been found below the root, both items speak about it: a
# project directory with no uv.lock is named as the one that needs one.
pnl="$work/proj-nolock"; rm -rf "$pnl"; cp -R "$sub" "$pnl"; rm "$pnl/app/uv.lock"
out="$(python3 "$checker" --root "$pnl" --no-network 2>&1)"
if is "$out" FC-C01 fail \
&& is "$out" FC-C02 fail && ! grep -q "found app/uv.lock" <<<"$out"
then ok "no uv.lock in the named directory: that directory is named as the one needing it"
else bad "the uv.lock line without a lockfile below"; printf '%s\n' "$out" | grep -E 'FAIL' | sed 's/^/        /'; fi

# A uv.lock at a root that holds no pyproject.toml belongs to no project this
# run checks. Passing the item for it sent the reader to a project where
# `--project=` reports the lockfile missing straight away.
pstray="$work/proj-stray-lock"; rm -rf "$pstray"; cp -R "$sub" "$pstray"; rm "$pstray/app/uv.lock"; : > "$pstray/uv.lock"
out="$(python3 "$checker" --root "$pstray" --no-network 2>&1)"
if is "$out" FC-C02 fail && ! grep -q "PASS  uv.lock committed" <<<"$out"
then ok "a stray uv.lock at a root with no project does not pass the item for the project found below"
else bad "a stray uv.lock at the root"; printf '%s\n' "$out" | grep -E 'FAIL|PASS  uv.lock' | sed 's/^/        /'; fi
# ...and it does not suppress the pointer when the project has one either.
pstray2="$work/proj-stray-lock-both"; rm -rf "$pstray2"; cp -R "$sub" "$pstray2"; : > "$pstray2/uv.lock"
out="$(python3 "$checker" --root "$pstray2" --no-network 2>&1)"
if is "$out" FC-C02 fail \
&& ! grep -q "PASS  uv.lock committed" <<<"$out"
then ok "a stray uv.lock at the root does not pass the item when the project below has one too"
else bad "a stray uv.lock beside a project lockfile"; printf '%s\n' "$out" | grep -E 'FAIL|PASS  uv.lock' | sed 's/^/        /'; fi

# A name argparse would read as the next flag rather than as this one's value.
# The hint is only worth printing if running it as printed works.
pdash="$work/proj-dash"; rm -rf "$pdash"; cp -R "$sub" "$pdash"; mv "$pdash/app" "$pdash/-app"
out="$(python3 "$checker" --root "$pdash" --no-network 2>&1)"
arg="$(sed -nE 's/.*run again with (--project=.*)$/\1/p' <<<"$out" | head -1)"
if [ "$arg" = "--project=-app" ] && python3 "$checker" --root "$pdash" "$arg" --no-network 2>&1 | grep -q "PASS  pyproject.toml present"
then ok "a directory name opening with - is printed as --project=<name> and runs as printed"
else bad "a directory name opening with - (printed '$arg')"; printf '%s\n' "$out" | grep -E 'FAIL' | sed 's/^/        /'; fi

# The name is printed into a result line the skill hands on whole, so a
# newline in it splits that line and the rest reads as further results.
pctl="$work/proj-control"; rm -rf "$pctl"; cp -R "$sub" "$pctl"
mv "$pctl/app" "$pctl/$(printf 'app\n  PASS  forged floor item')"
out="$(python3 "$checker" --root "$pctl" --no-network 2>&1)"
if is "$out" FC-C01 fail && ! grep -q "PASS  forged floor item" <<<"$out"
then ok "a directory name holding a newline is not offered, so no line is forged into the report"
else bad "a control character in a candidate name"; printf '%s\n' "$out" | grep -E 'FAIL|PASS  forged' | sed 's/^/        /'; fi

# is_dir() follows symlinks, so without a guard a link out of the checkout is
# offered and the reader is sent to read a tree this repository does not hold.
psym="$work/proj-symlink"; rm -rf "$psym"; cp -R "$sub" "$psym"; mkdir -p "$work/proj-outside"
mv "$psym/app" "$work/proj-outside/app"; ln -sfn "$work/proj-outside/app" "$psym/app"
out="$(python3 "$checker" --root "$psym" --no-network 2>&1)"
if is "$out" FC-C01 fail && ! grep -q -- "--project" <<<"$out"
then ok "a symlinked directory is not offered as this repository's project"
else bad "a symlinked candidate"; printf '%s\n' "$out" | grep -E 'FAIL|INFO' | sed 's/^/        /'; fi

# The hint is pasted into a shell, and a directory name is the repository's
# to choose (the dotenv repair has the same guard).
pq="$work/proj-quote"; rm -rf "$pq"; cp -R "$sub" "$pq"; mv "$pq/app" "$pq/a\$(touch PWN)"
out="$(cd "$pq" && python3 "$checker" --root . --no-network 2>&1)"
if grep -q -- "run again with --project='a\$(touch PWN)'" <<<"$out" && [ ! -e "$pq/PWN" ]
then ok "a directory name with shell syntax in it is quoted in the hint"
else bad "the hint did not quote the directory"; printf '%s\n' "$out" | grep -E 'FAIL' | sed 's/^/        /'; fi

# A pyproject.toml the search must not offer: it is not a project of this
# repository, and running with --project .venv would be worse than no hint.
for d in .venv node_modules .tools; do
  phid="$work/proj-hidden"; rm -rf "$phid"; cp -R "$sub" "$phid"; mv "$phid/app" "$phid/$d"
  out="$(python3 "$checker" --root "$phid" --no-network 2>&1)"
  if is "$out" FC-C01 fail && ! grep -q -- "--project" <<<"$out"
  then ok "a pyproject.toml inside $d is not offered"
  else bad "$d was offered as a project"; printf '%s\n' "$out" | grep -E 'FAIL|INFO' | sed 's/^/        /'; fi
done

# The ruleset the door applies, per archetype: ruleset.json as it is for cli and
# library, plus the `image` check for a service archetype, from the Actions app
# and nothing else; and the checker expects the same name of the wall (#127).
python3 "$checker" --print-ruleset --ruleset "$root/ruleset.json" --archetype cli > "$work/cli-ruleset.json"
if "$root/scripts/check-ruleset.sh" "$work/cli-ruleset.json" >/dev/null 2>&1 && cmp -s <(jq -S . "$work/cli-ruleset.json") <(jq -S . "$root/ruleset.json")
then ok "--print-ruleset for cli is ruleset.json, unchanged"; else bad "--print-ruleset for cli changed the wall"; fi
for arch in backend data-ml; do
  python3 "$checker" --print-ruleset --ruleset "$root/ruleset.json" --archetype "$arch" > "$work/$arch-ruleset.json"
  if "$root/scripts/check-ruleset.sh" "$work/$arch-ruleset.json" image >/dev/null 2>&1
  then ok "--print-ruleset for $arch is the wall plus image, from one app (check-ruleset.sh passes with image)"
  else bad "--print-ruleset for $arch fails the wall's invariants:"; "$root/scripts/check-ruleset.sh" "$work/$arch-ruleset.json" image | grep FAIL -A2 | sed 's/^/        /'; fi
done
# A dashboard ships no container (#1069): its wall is ruleset.json's, no image.
python3 "$checker" --print-ruleset --ruleset "$root/ruleset.json" --archetype dashboard > "$work/dashboard-ruleset.json"
if cmp -s <(jq -S . "$work/dashboard-ruleset.json") <(jq -S . "$root/ruleset.json")
then ok "--print-ruleset for dashboard is ruleset.json, unchanged: no image check"; else bad "--print-ruleset for dashboard changed the wall"; fi
python3 "$checker" --print-ruleset --ruleset "$root/ruleset.json" --archetype web > "$work/web-ruleset.json"
if "$root/scripts/check-ruleset.sh" "$work/web-ruleset.json" "image,ci / migrations,ci / deploy-check" >/dev/null 2>&1
then ok "--print-ruleset for web is the wall plus image and the two web checks, from one app (#615)"
else bad "--print-ruleset for web fails the wall's invariants:"; "$root/scripts/check-ruleset.sh" "$work/web-ruleset.json" "image,ci / migrations,ci / deploy-check" | grep FAIL -A2 | sed 's/^/        /'; fi
# A private repository without GitHub Code Security gets the wall without the
# code_scanning rule and with nothing else changed (#350): the same check
# names, per archetype. Each form of check-ruleset.sh refuses the other's file,
# so neither variant can pass as the other.
for arch in cli backend; do
  extra=""; [ "$arch" = cli ] || extra=image
  python3 "$checker" --print-ruleset --without-code-scanning --ruleset "$root/ruleset.json" --archetype "$arch" > "$work/$arch-noscan.json"
  if "$root/scripts/check-ruleset.sh" --without-code-scanning "$work/$arch-noscan.json" $extra >/dev/null 2>&1 \
     && cmp -s <(jq -S . "$work/$arch-noscan.json") <(jq -S 'del(.rules[] | select(.type == "code_scanning"))' "$work/$arch-ruleset.json")
  then ok "--print-ruleset --without-code-scanning for $arch is the same wall minus the code_scanning rule"
  else bad "--print-ruleset --without-code-scanning for $arch is not the wall minus one rule"; fi
  if "$root/scripts/check-ruleset.sh" "$work/$arch-noscan.json" $extra >/dev/null 2>&1
  then bad "check-ruleset.sh passes a ruleset without code_scanning as the public wall ($arch)"
  else ok "check-ruleset.sh without the flag refuses a ruleset that lost code_scanning ($arch)"; fi
  if "$root/scripts/check-ruleset.sh" --without-code-scanning "$work/$arch-ruleset.json" $extra >/dev/null 2>&1
  then bad "check-ruleset.sh --without-code-scanning passes a ruleset that carries the rule ($arch)"
  else ok "check-ruleset.sh --without-code-scanning refuses a ruleset that carries the rule ($arch)"; fi
done
if python3 "$checker" --without-code-scanning --root "$work" --no-network >/dev/null 2>&1
then bad "--without-code-scanning was accepted outside --print-ruleset"
else ok "--without-code-scanning is refused outside --print-ruleset"; fi
plant "a buildx build in the image job is a build" "sed -i.bak 's/docker build/docker buildx build/' .github/workflows/ci.yml" "__none__" || true
plant "docker words outside the image job do not count" "printf 'jobs:\n  ci:\n    uses: x\n  image:\n    steps:\n      - run: echo\n  other:\n    steps:\n      - run: docker build . \&\& docker run t\n' > .github/workflows/ci.yml" "FC-D06 fail"
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" 2>&1)"
if is "$out" FC-E06 info; then ok "a backend instance expects the image check of the wall, from --ruleset"
else bad "a backend instance's expectation lacks image"; printf '%s\n' "$out" | grep -E 'wall expectation' | sed 's/^/        /'; fi
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --archetype cli --no-network --repo o/r --ruleset "$root/ruleset.json" 2>&1)"
if is "$out" FC-E06 info && ! grep -q "'image'" <<<"$out"; then ok "a cli instance expects the nine, not image"
else bad "a cli instance's expectation carries image"; printf '%s\n' "$out" | grep -E 'wall expectation' | sed 's/^/        /'; fi

# #219: is the template plinth is tested with today ahead of the tag this
# repository was rendered from? The target is read from the real
# scripts/new-project.sh beside the real checker (not a fixture, #219), so the
# good fixture (recorded at $target_ref) always PASSes and every other case
# below sets _commit far enough from $target_ref to stay true across a pin raise.
says "the good fixture's recorded template tag matches the target" ":" \
  "FC-F01 pass"

drift() { # <description> <_commit value> <`<id> <state>` expected>; never a FAIL
  local copy="$work/drift"; rm -rf "$copy"; cp -R "$good" "$copy"
  printf 'archetype: backend\n_src_path: gh:coolbress/plinth-template\n_commit: %s\n' "$2" > "$copy/.copier-answers.yml"
  local out; out="$(python3 "$checker" --root "$copy" --no-network 2>&1)"; local rc=$?
  if [ "$rc" != 0 ] || grep -q "FAIL.*template" <<<"$out"; then bad "$1 (never a FAIL, rc=$rc)"; printf '%s\n' "$out" | grep -E 'FAIL' | sed 's/^/        /'; return; fi
  if reports "$out" "$3"; then ok "$1"; else bad "$1 (expected $3)"; printf '%s\n' "$out" | grep -E 'template' | sed 's/^/        /'; fi
}
drift "a recorded tag behind the target is named, with both tags" "v1.0.0" \
  "FC-F01 warn"
drift "offline, the changed files could not be read, and it says so rather than staying silent" "v1.0.0" \
  "FC-F01 warn"
# The update line needs the owner's answers (#726), read with --repo; an
# owner with no .github repository (every fixture directory below answers
# 404 unless a case writes one) gives both as false.
no_shared=" --data owner_has_pr_template=false --data owner_has_issue_forms=false"
dcopy="$work/drift-line"; rm -rf "$dcopy"; cp -R "$good" "$dcopy"
printf 'archetype: backend\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0\n' > "$dcopy/.copier-answers.yml"
tag_names "$work/api-tag-only" "$target_sha"
out="$(FLOOR_CHECK_API_DIR="$work/api-tag-only" python3 "$checker" --root "$dcopy" --repo o/r --print-update-command 2>&1)"
if grep -q "copier update --defaults --vcs-ref $target_sha --data plinth_sha=$sha40$no_shared\$" <<<"$out"
then ok "the update command carries the pin this repository's own CI calls today, then the owner's two answers"
else bad "the update command's pin and answers"; printf '%s\n' "$out" | sed 's/^/        /'; fi
drift "without --repo the owner's answers are not read: no update command, and it says why" "v1.0.0" \
  "FC-F01 info"
drift "a recorded tag ahead of the target is a plain statement, not a not-verified count" "v99.0.0" \
  "FC-F01 info"
quiet "an ahead tag is not counted as not verified" \
  "printf 'archetype: backend\n_src_path: gh:coolbress/plinth-template\n_commit: v99.0.0\n' > .copier-answers.yml" \
  "template drift not verified"
plant "no .copier-answers.yml: the item never fails, it says not verified" "rm .copier-answers.yml" "__none__" || true
says "no .copier-answers.yml is named as the reason" "rm .copier-answers.yml" \
  "FC-F01 unknown"
says "an answers file without _commit is not verified" \
  "printf 'archetype: backend\n_src_path: gh:coolbress/plinth-template\n' > .copier-answers.yml" \
  "FC-F01 unknown"
says "a _src_path that is not the plinth template is not verified" \
  "printf 'archetype: backend\n_src_path: gh:example/other-template\n_commit: v1.0.0\n' > .copier-answers.yml" \
  "FC-F01 unknown"
# A foreign source containing the template's name as a substring must not
# pass a bare `in` check: copier update pulls from _src_path, and passing
# that through would run against whatever that foreign source is (#233 review).
says "a foreign _src_path that merely contains the template's name is not the door's own form" \
  "printf 'archetype: backend\n_src_path: /tmp/coolbress/plinth-template\n_commit: v1.0.0\n' > .copier-answers.yml" \
  "FC-F01 unknown"
says "a git describe value is not verified, quoted as recorded, and no command is printed" \
  "printf 'archetype: backend\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0-3-gabc1234\n' > .copier-answers.yml" \
  "FC-F01 unknown"
quiet "a git describe value prints no update command" \
  "printf 'archetype: backend\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0-3-gabc1234\n' > .copier-answers.yml" \
  "copier update"

# The plinth pin: read from this repository's own workflow uses: lines, the
# live truth Dependabot moves and .copier-answers.yml never does. Unknown
# withholds the command and names why, but the tags and file list still print.
says "no plinth workflow pin at all: the command is withheld, with the reason" \
  "printf 'archetype: cli\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0\n' > .copier-answers.yml && rm -r .github/workflows" \
  "FC-F01 info"
says "two workflow files pinned to different plinth commits: the command is withheld, both named" \
  "printf 'archetype: cli\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0\n' > .copier-answers.yml && mkdir -p .github/workflows && printf 'jobs:\n  a:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%040d\n' 0 > .github/workflows/one.yml && printf 'jobs:\n  b:\n    uses: coolbress/plinth/.github/workflows/label.yml@%040d\n' 1 > .github/workflows/two.yml" \
  "FC-F01 info"
says "a commented uses: line is not counted as a plinth pin" \
  "printf 'archetype: cli\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0\n' > .copier-answers.yml && rm -r .github/workflows && mkdir -p .github/workflows && printf 'jobs:\n  a:\n    # uses: coolbress/plinth/.github/workflows/python-ci.yml@%040d\n    uses: ./local\n' 0 > .github/workflows/one.yml" \
  "FC-F01 info"
# One workflow pinned to a full SHA and another tracking a tag must not let
# the tag be silently dropped: today's pin is not established while any
# plinth uses: could be moving (#233 review) -- printing a command from the
# one SHA that happens to be pinned would rewrite the other file too.
says "one plinth pin on a full SHA and another on a tag: the command is withheld, not printed from the one SHA" \
  "printf 'archetype: cli\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0\n' > .copier-answers.yml && rm -r .github/workflows && mkdir -p .github/workflows && printf 'jobs:\n  a:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%040d\n' 0 > .github/workflows/one.yml && printf 'jobs:\n  b:\n    uses: coolbress/plinth/.github/workflows/label.yml@main\n' > .github/workflows/two.yml" \
  "FC-F01 info"
loosecopy="$work/loose-pin"; rm -rf "$loosecopy"; cp -R "$good" "$loosecopy"
printf 'archetype: cli\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0\n' > "$loosecopy/.copier-answers.yml"
rm -r "$loosecopy/.github/workflows"; mkdir -p "$loosecopy/.github/workflows"
printf 'jobs:\n  a:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%040d\n' 0 > "$loosecopy/.github/workflows/one.yml"
printf 'jobs:\n  b:\n    uses: coolbress/plinth/.github/workflows/label.yml@main\n' > "$loosecopy/.github/workflows/two.yml"
out="$(python3 "$checker" --root "$loosecopy" --no-network 2>&1)"
if grep -q "plinth_sha=$sha40" <<<"$out"; then bad "the loose-pin case printed the lone SHA as if it were established"; printf '%s\n' "$out" | grep -E 'template|plinth_sha' | sed 's/^/        /'
else ok "the loose-pin case never prints the lone SHA as if it were established"; fi

# One plinth pin in the ordinary block form (readable) and another in valid
# flow-style YAML this checker cannot parse: the unreadable one's value is
# unknown, so it cannot be ruled out as a second, disagreeing plinth pin
# either (#233 review, round 2).
says "one plinth pin readable and another in a form this checker cannot parse: the command is withheld" \
  "printf 'archetype: cli\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0\n' > .copier-answers.yml && rm -r .github/workflows && mkdir -p .github/workflows && printf 'jobs:\n  a:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%040d\n' 0 > .github/workflows/one.yml && printf 'jobs:\n  b:\n    steps:\n      - {uses: coolbress/plinth/.github/workflows/label.yml@%040d}\n' 1 > .github/workflows/two.yml" \
  "FC-F01 info"
unreadcopy="$work/unread-pin"; rm -rf "$unreadcopy"; cp -R "$good" "$unreadcopy"
printf 'archetype: cli\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0\n' > "$unreadcopy/.copier-answers.yml"
rm -r "$unreadcopy/.github/workflows"; mkdir -p "$unreadcopy/.github/workflows"
printf 'jobs:\n  a:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%040d\n' 0 > "$unreadcopy/.github/workflows/one.yml"
printf 'jobs:\n  b:\n    steps:\n      - {uses: coolbress/plinth/.github/workflows/label.yml@%040d}\n' 1 > "$unreadcopy/.github/workflows/two.yml"
out="$(python3 "$checker" --root "$unreadcopy" --no-network 2>&1)"
if grep -q "plinth_sha=$sha40" <<<"$out"; then bad "an unreadable second plinth uses: line still let the lone parsed SHA print"; printf '%s\n' "$out" | grep -E 'template|plinth_sha' | sed 's/^/        /'
else ok "an unreadable second plinth uses: line withholds the command too, not just a lone parsed SHA"; fi

# The plinth pins agree (#447): ci.yml and label.yml are rendered at one
# commit, and a hand edit that moves one leaves them apart. A WARN of its own,
# whatever the template state: the fixture's recorded tag is the target, so
# the drift item above prints no reason here.
pins() { # <label.yml uses: line> -- the good copy plus a label.yml; sets out, rc
  local copy="$work/pins"; rm -rf "$copy"; cp -R "$good" "$copy"
  printf 'jobs:\n  label:\n%b\n' "$1" > "$copy/.github/workflows/label.yml"
  out="$(python3 "$checker" --root "$copy" --no-network 2>&1)"; rc=$?
}
sha1="$(printf '%040d' 1)"
pins "    uses: coolbress/plinth/.github/workflows/pr-label.yml@$sha1"
has "ci.yml and label.yml at different plinth SHAs: a WARN names each file with its SHA" \
  "FC-F06 warn"
has "the INFO under it is a sed line for label.yml's plinth pin" \
  "FC-F06 info"
fixed() { # <description> <ERE label.yml must match after the fix> -- runs the printed sed lines in $work/pins
  ( cd "$work/pins" && sed -n 's/^  INFO    \(sed .*\.bak\)   (moves.*/\1/p' <<<"$out" | while IFS= read -r l; do eval "$l"; done )
  if grep -qE -- "$2" "$work/pins/.github/workflows/label.yml" && [ -z "$(find "$work/pins/.github/workflows" -name '*.bak')" ]; then ok "$1"
  else bad "$1"; sed 's/^/        /' "$work/pins/.github/workflows/label.yml"; fi
}
fixed "run as printed, it moves label.yml to the SHA the ci job calls and leaves no .bak" "pr-label\.yml@$sha40\$"
lacks "the fix line does not touch ci.yml" "sed .*ci\.yml"
if [ "$rc" = 0 ] && grep -q -- '-- 0 failed' <<<"$out"; then ok "the disagreement alone exits 0 and fails nothing"; else bad "the disagreement alone should exit 0 (rc=$rc)"; fi
lacks "the recorded tag equals the target: the drift item prints no update reason, the WARN stands on its own" "no update command"
pins "    uses: coolbress/plinth/.github/workflows/pr-label.yml@$sha40"
lacks "ci.yml and label.yml at the same plinth SHA: the item prints nothing" "pins disagree|pins not compared"
out="$(python3 "$checker" --root "$good" --no-network 2>&1)"
lacks "only the ci job calls plinth: the item prints nothing" "pins disagree|pins not compared"
pins "    steps:\n      - {uses: coolbress/plinth/.github/workflows/pr-label.yml@$sha1}"
has "an unreadable uses: line is a SKIP naming the file" \
  "FC-F06 unknown"
pins "    uses: coolbress/plinth/.github/workflows/pr-label.yml@main"
lacks "a plinth uses: on a tag is the action-pins WARN, not repeated here" "pins disagree|pins not compared"
# A SHA is one Git object however it is spelled: compared in lower case, and
# the fix line names the lagging one as written, since sed matches case.
lower_a="$(printf 'a%.0s' $(seq 40))"; upper_a="$(printf 'A%.0s' $(seq 40))"; upper_b="$(printf 'B%.0s' $(seq 40))"
pins "    uses: coolbress/plinth/.github/workflows/pr-label.yml@$upper_a"
sed -i.bak "s/$sha40/$lower_a/" "$work/pins/.github/workflows/ci.yml" && rm "$work/pins/.github/workflows/ci.yml.bak"
out="$(python3 "$checker" --root "$work/pins" --no-network 2>&1)"
lacks "the same SHA in upper case in label.yml and lower case in ci.yml: the item prints nothing" "pins disagree|pins not compared"
printf 'jobs:\n  label:\n    uses: coolbress/plinth/.github/workflows/pr-label.yml@%s\n' "$upper_b" > "$work/pins/.github/workflows/label.yml"
out="$(python3 "$checker" --root "$work/pins" --no-network 2>&1)"
has "an upper-case SHA that differs is named in lower case in the WARN" \
  "FC-F06 warn"
has "and as written in the sed line, which matches case" "FC-F06 info"
pins "    uses: coolbress/plinth/.github/workflows/pr-label.yml@$sha1\n  other:\n    uses: coolbress/plinth/.github/workflows/pr-label.yml@$sha40"
has "two SHAs inside one file are both named" "FC-F06 warn"
has "and only the lagging one gets a sed line" "FC-F06 info"
lacks "the matching one gets none" "sed -i\.bak 's\|coolbress/plinth/[^|]*@$sha40\|"
# GitHub reads the owner and repository in any case, as the caller item does:
# a ci job calling CoolBress/Plinth is still plinth's pin.
pins "    uses: coolbress/plinth/.github/workflows/pr-label.yml@$sha1"
sed -i.bak "s|coolbress/plinth/|CoolBress/Plinth/|" "$work/pins/.github/workflows/ci.yml" && rm "$work/pins/.github/workflows/ci.yml.bak"
out="$(python3 "$checker" --root "$work/pins" --no-network 2>&1)"
has "CoolBress/Plinth in ci.yml and coolbress/plinth in label.yml at different SHAs: the WARN names both" \
  "FC-F06 warn"
fixed "and the fix still moves label.yml to the ci job's SHA" "pr-label\.yml@$sha40\$"
# The fix rewrites plinth references only: the same SHA on another action stays.
pins "    uses: coolbress/plinth/.github/workflows/pr-label.yml@$sha1\n  other:\n    steps:\n      - uses: someone/fork@$sha1"
fixed "the same SHA on another action in label.yml is left as it was" "someone/fork@$sha1\$"
fixed "while the plinth reference moves" "pr-label\.yml@$sha40\$"

# --print-diff-size (#795): what ci / diff-size counts against, from the ci
# job's with: or plinth's defaults, for template-update.sh to count its own
# diff before it pushes. The defaults are python-ci.yml's own.
wf_default() { # <input name>: its default in python-ci.yml
  awk -v n="      $1:" '$0 == n { f = 1; next } f && /^        default:/ { sub(/^        default: */, ""); gsub(/^"|"$/, ""); print; exit }' "$root/.github/workflows/python-ci.yml"
}
dsz="$(python3 "$checker" --root "$good" --print-diff-size 2>&1)"; rc=$?
if [ "$rc" = 0 ] && [ "$dsz" = "$(printf 'max=%s\nexclude=%s\nroot=.' "$(wf_default max-diff-lines)" "$(wf_default diff-size-exclude)")" ]
then ok "no with: inputs: --print-diff-size prints python-ci.yml's own defaults"
else bad "--print-diff-size defaults (rc=$rc): '$dsz' vs max $(wf_default max-diff-lines), exclude $(wf_default diff-size-exclude)"; fi
dcopy="$work/diff-size"
dsize() { # <with: lines> -- sets dsz, rc
  rm -rf "$dcopy"; cp -R "$good" "$dcopy"
  printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n    with:\n%b\n' "$sha40" "$1" > "$dcopy/.github/workflows/ci.yml"
  dsz="$(python3 "$checker" --root "$dcopy" --print-diff-size 2>&1)"; rc=$?
}
dsize '      max-diff-lines: 250\n      diff-size-exclude: "*.md docs/**"\n      working-directory: app'
if [ "$rc" = 0 ] && [ "$dsz" = "$(printf 'max=250\nexclude=*.md docs/**\nroot=app')" ]; then ok "the ci job's own three inputs are the ones printed"
else bad "own inputs (rc=$rc): $dsz"; fi
dsize '      diff-size-exclude: ${{ vars.EXCLUDE }}'
if [ "$rc" = 1 ] && grep -q "passes diff-size-exclude in a form not read" <<<"$dsz"; then ok "an expression is not read: exit 1, named"
else bad "expression (rc=$rc): $dsz"; fi
dsize '      max-diff-lines: lots'
if [ "$rc" = 1 ] && grep -q "not read as a whole number" <<<"$dsz"; then ok "a max-diff-lines that is no whole number: exit 1"
else bad "not a number (rc=$rc): $dsz"; fi
rm -rf "$dcopy"; cp -R "$good" "$dcopy"; printf 'jobs:\n  ci:\n    uses: someone/else/.github/workflows/python-ci.yml@%s\n' "$sha40" > "$dcopy/.github/workflows/ci.yml"
dsz="$(python3 "$checker" --root "$dcopy" --print-diff-size 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -q "does not call plinth's workflow" <<<"$dsz"; then ok "a ci job that does not call plinth: exit 1, nothing printed as if read"
else bad "not plinth (rc=$rc): $dsz"; fi

# The template-update skill (#232) runs the command stage 1 prints, not a
# second construction of it: --print-update-command prints that same line
# and nothing else, or a reason on stderr and exit 1. `--defaults` is in it
# because without a terminal copier update stops at "Interactive session
# required" (measured, copier 9.18.2), and the skill has no terminal.
pcopy="$work/print-cmd"; rm -rf "$pcopy"; cp -R "$good" "$pcopy"
printf 'archetype: backend\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0\n' > "$pcopy/.copier-answers.yml"
pinned_api="$work/api-pinned"; tag_names "$pinned_api" "$target_sha"
warned="$(FLOOR_CHECK_API_DIR="$pinned_api" python3 "$checker" --root "$pcopy" --repo o/r 2>&1 | sed -n 's/^  INFO    \(uvx .*copier update.*\)$/\1/p')"
printed="$(FLOOR_CHECK_API_DIR="$pinned_api" python3 "$checker" --root "$pcopy" --repo o/r --print-update-command 2>/dev/null)"; rc=$?
if [ "$rc" = 0 ] && [ -n "$warned" ] && [ "$printed" = "$warned" ]; then ok "--print-update-command prints exactly the line the drift WARN prints"
else bad "--print-update-command (rc=$rc): printed '$printed', WARN printed '$warned'"; fi
case "$printed" in *"copier update --defaults "*) ok "the update command runs without a terminal (--defaults)" ;;
  *) bad "the update command has no --defaults: '$printed'" ;; esac
# The target tag must still name the commit plinth was tested with (#519):
# the doors check the same pair before rendering, and so does the line.
moved="$(printf '%040d' 5)"
moved_api="$work/api-moved"; tag_names "$moved_api" "$moved"
out="$(FLOOR_CHECK_API_DIR="$moved_api" python3 "$checker" --root "$pcopy" --repo o/r 2>&1 | grep -E 'template|copier')"
if is "$out" FC-F01 warn \
   && ! grep -q "copier update" <<<"$out"
then ok "a moved target tag: a WARN naming both commits, and no update command"
else bad "moved tag, drift item"; printf '%s\n' "$out" | grep -E 'template|copier' | sed 's/^/        /'; fi
printed="$(FLOOR_CHECK_API_DIR="$moved_api" python3 "$checker" --root "$pcopy" --repo o/r --print-update-command 2>"$work/print-err")"; rc=$?
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -q "now names commit $moved, not $target_sha" "$work/print-err"; then ok "a moved target tag: --print-update-command prints no line, exit 1, names both commits"
else bad "--print-update-command, moved tag (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi
out="$(FLOOR_CHECK_API_DIR="$moved_api" python3 "$checker" --root "$good" 2>&1)"
if is "$out" FC-F01 warn \
   && ! grep -q "PASS  template:" <<<"$out"
then ok "a repository already on the target tag, and the tag moved since: a WARN, not a PASS"
else bad "current tag moved"; printf '%s\n' "$out" | grep -E 'template' | sed 's/^/        /'; fi
out="$(FLOOR_CHECK_API_DIR="$pinned_api" python3 "$checker" --root "$good" 2>&1)"
if is "$out" FC-F01 pass; then ok "a repository on the target tag, the tag still on its commit: PASS"
else bad "current tag pinned"; printf '%s\n' "$out" | grep -E 'template' | sed 's/^/        /'; fi
out="$(python3 "$checker" --root "$good" --no-network 2>&1)"
if is "$out" FC-F01 pass \
   && is "$out" FC-F01 info
then ok "a repository on the target tag, the tag's commit not read: the PASS says the tags only, and a line says the commit was not verified"
else bad "current tag unread"; printf '%s\n' "$out" | grep -E 'template|verified' | sed 's/^/        /'; fi
# The tag's read fails (unparseable, as an API failure reads); the owner's
# .github answers 404, so the line itself can be built.
tag_err="$work/api-tag-error"; mkdir -p "$tag_err/repos/coolbress/plinth-template/commits"
printf 'not json\n' > "$tag_err/repos/coolbress/plinth-template/commits/$target_ref.json"
out="$(FLOOR_CHECK_API_DIR="$tag_err" python3 "$checker" --root "$pcopy" --repo o/r 2>&1 | grep -E 'template|copier|verified')"
if is "$out" FC-F01 info \
   && is "$out" FC-F01 info
then ok "the target tag's commit not read: the drift item still shows the line, and says it was not verified"
else bad "unread tag, drift item"; printf '%s\n' "$out" | grep -E 'template|copier|verified' | sed 's/^/        /'; fi
printed="$(FLOOR_CHECK_API_DIR="$work/api-none-at-all" python3 "$checker" --root "$pcopy" --repo o/r --print-update-command 2>"$work/print-err")"; rc=$?
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -q "not verified that $target_ref still names $target_sha, the commit plinth was tested with (the tag was not found)" "$work/print-err"
then ok "the target tag's commit not read: --print-update-command, the line that runs, prints none (fail closed)"
else bad "--print-update-command, tag unread (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi
printed="$(python3 "$checker" --root "$good" --print-update-command 2>"$work/print-err")"; rc=$?
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -q "the recorded tag is the target tag" "$work/print-err"; then ok "--print-update-command at the target tag prints no command, says why, exit 1"
else bad "--print-update-command at the target (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi
printed="$(python3 "$checker" --root "$loosecopy" --print-update-command 2>"$work/print-err")"; rc=$?
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -q "not pinned to a full commit SHA" "$work/print-err"; then ok "--print-update-command with no established pin prints no command, names the reason, exit 1"
else bad "--print-update-command, loose pin (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi
# --move-archetype (#1004): at the target tag, the same-tag line with the new
# archetype, which copier update re-renders (measured, copier 9.18.2 and
# 9.19.1, data-ml to cli); on stderr the required checks the move drops or adds.
move() { # <root> <api dir> <args...>: sets printed, rc; stderr in $work/print-err
  local r="$1" api="$2"; shift 2
  printed="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$r" --repo o/r --print-update-command "$@" 2>"$work/print-err")"; rc=$?
}
move "$good" "$pinned_api" --move-archetype cli
case "$printed" in
  "uvx --from copier=="*" copier update --defaults --vcs-ref $target_sha --data plinth_sha=$sha40$no_shared --data archetype=cli")
    [ "$rc" = 0 ] && ok "--move-archetype cli at the target tag: the same-tag line with --data archetype=cli last" \
      || bad "--move-archetype cli: exit $rc" ;;
  *) bad "--move-archetype cli (rc=$rc): '$printed'"; sed 's/^/        /' "$work/print-err" ;;
esac
if grep -qx "check-drop: image" "$work/print-err" && ! grep -q "^check-add: " "$work/print-err"; then ok "backend to cli names the image check it drops, and none it adds"
else bad "backend to cli, check lines"; sed 's/^/        /' "$work/print-err"; fi
mcopy="$work/move-cli"; rm -rf "$mcopy"; cp -R "$good" "$mcopy"; sed -i.bak 's/^archetype: backend/archetype: cli/' "$mcopy/.copier-answers.yml" && rm "$mcopy/.copier-answers.yml.bak"
move "$mcopy" "$pinned_api" --move-archetype data-ml
if [ "$rc" = 0 ] && grep -qx "check-add: image" "$work/print-err" && ! grep -q "^check-drop: " "$work/print-err"; then ok "cli to data-ml names the image check it adds, and none it drops"
else bad "cli to data-ml (rc=$rc)"; sed 's/^/        /' "$work/print-err"; fi
move "$mcopy" "$pinned_api" --move-archetype library
if [ "$rc" = 0 ] && ! grep -qE "^check-(add|drop): " "$work/print-err"; then ok "cli to library: no required check changes"
else bad "cli to library (rc=$rc)"; sed 's/^/        /' "$work/print-err"; fi
for why in "backend|the recorded archetype is already backend" "web|web is not moved to or from here" \
           "dashboard|dashboard is not moved to or from here: its hosting answer (local or render)" \
           "cli --x|'cli --x' is not an archetype's name" "CLI|'CLI' is not an archetype's name"; do
  move "$good" "$pinned_api" --move-archetype "${why%%|*}"
  if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -qF "no move command: ${why#*|}" "$work/print-err"; then ok "--move-archetype ${why%%|*}: no line, exit 1, says why"
  else bad "--move-archetype ${why%%|*} (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi
done
# Which names are archetypes is the template's copier.yml's to say: a name of
# the right shape that this checker does not know gets its line, for copier.
move "$good" "$pinned_api" --move-archetype nope
case "$printed" in
  *" --data archetype=nope") [ "$rc" = 0 ] && ok "--move-archetype nope: the line, for copier to judge the value" || bad "--move-archetype nope: exit $rc" ;;
  *) bad "--move-archetype nope (rc=$rc): '$printed'"; sed 's/^/        /' "$work/print-err" ;;
esac
xcopy="$work/move-no-archetype"; rm -rf "$xcopy"; cp -R "$good" "$xcopy"; sed -i.bak '/^archetype: /d' "$xcopy/.copier-answers.yml" && rm "$xcopy/.copier-answers.yml.bak"
move "$xcopy" "$pinned_api" --move-archetype cli
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -qF "no move command: .copier-answers.yml records no archetype to move from" "$work/print-err"; then ok "--move-archetype with no recorded archetype: no line"
else bad "--move-archetype, no recorded archetype (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi
wcopy="$work/move-from-web"; rm -rf "$wcopy"; cp -R "$good" "$wcopy"; sed -i.bak 's/^archetype: backend/archetype: web/' "$wcopy/.copier-answers.yml" && rm "$wcopy/.copier-answers.yml.bak"
move "$wcopy" "$pinned_api" --move-archetype cli
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -qF "no move command: web is not moved to or from here" "$work/print-err"; then ok "--move-archetype from web: no line"
else bad "--move-archetype from web (rc=$rc)"; sed 's/^/        /' "$work/print-err"; fi
dcopy="$work/move-from-dashboard"; rm -rf "$dcopy"; cp -R "$good" "$dcopy"; sed -i.bak 's/^archetype: backend/archetype: dashboard/' "$dcopy/.copier-answers.yml" && rm "$dcopy/.copier-answers.yml.bak"
move "$dcopy" "$pinned_api" --move-archetype cli
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -qF "no move command: dashboard is not moved to or from here" "$work/print-err"; then ok "--move-archetype from dashboard: no line (#1069)"
else bad "--move-archetype from dashboard (rc=$rc)"; sed 's/^/        /' "$work/print-err"; fi
move "$pcopy" "$pinned_api" --move-archetype cli
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -qF "no move command: the recorded tag v1.0.0 is not $target_ref, the tag plinth targets; update the template first (/plinth:template-update), then move" "$work/print-err"
then ok "--move-archetype behind the target tag: no line, update first"
else bad "--move-archetype behind (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi
acopy="$work/move-ahead"; rm -rf "$acopy"; cp -R "$good" "$acopy"; sed -i.bak 's/^_commit: .*/_commit: v99.0.0/' "$acopy/.copier-answers.yml" && rm "$acopy/.copier-answers.yml.bak"
move "$acopy" "$pinned_api" --move-archetype cli
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -qF "no move command: the recorded tag v99.0.0 is newer than $target_ref, the tag plinth targets" "$work/print-err"
then ok "--move-archetype ahead of the target tag: no line, says the tag is newer"
else bad "--move-archetype ahead (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi
ncopy="$work/move-no-answers"; rm -rf "$ncopy"; cp -R "$good" "$ncopy"; rm "$ncopy/.copier-answers.yml"
move "$ncopy" "$pinned_api" --move-archetype cli
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -qF "no move command: no .copier-answers.yml" "$work/print-err"; then ok "--move-archetype with no answers file: no line, names the file"
else bad "--move-archetype, no answers file (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi
move "$good" "$moved_api" --move-archetype cli
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -q "now names commit $moved, not $target_sha" "$work/print-err"; then ok "--move-archetype, the target tag moved: no line (fail closed)"
else bad "--move-archetype, moved tag (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi
FLOOR_CHECK_API_DIR="$pinned_api" python3 "$checker" --root "$good" --repo o/r --print-update-command --move-archetype >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "--print-update-command --move-archetype: a usage error" || bad "--print-update-command --move-archetype: exit $rc, expected 2"
python3 "$checker" --root "$good" --move-archetype cli >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "--move-archetype without --print-update-command: a usage error" || bad "--move-archetype alone: exit $rc, expected 2"
# ci.yml raised by hand and label.yml left where the template rendered it
# (#793). When label.yml's commit is an ancestor of the ci job's, the update
# carries the ci job's and says which file moves from which commit to which.
# Otherwise it still stops, since it cannot pick one of two pins, and the stop
# names each file with its commit, which is the newer when GitHub's compare
# says so, and the same fix line the pin-agreement item prints.
two="$work/two-pins"; rm -rf "$two"; cp -R "$pcopy" "$two"
printf 'jobs:\n  label:\n    uses: coolbress/plinth/.github/workflows/pr-label.yml@%s\n' "$sha1" > "$two/.github/workflows/label.yml"
stop() { # <api dir> -- runs --print-update-command on $two; sets printed, rc, err
  local api="$1"; shift
  printed="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$two" --repo o/r --print-update-command "$@" 2>"$work/print-err")"; rc=$?
  err="$(cat "$work/print-err")"
}
in_err() { # <description> <ERE one stderr line must match>
  if grep -qE -- "$2" <<<"$err"; then ok "$1"; else bad "$1 (expected a line matching '$2')"; sed 's/^/        /' <<<"$err"; fi
}
cmp_api() { # <dir> <status>: a compare of the ci job's SHA against label.yml's
  rm -rf "$1"; cp -R "$pinned_api" "$1"; mkdir -p "$1/repos/coolbress/plinth/compare"
  printf '{"status":"%s"}\n' "$2" > "$1/repos/coolbress/plinth/compare/$sha40...$sha1.json"
}
one_pin="$(FLOOR_CHECK_API_DIR="$pinned_api" python3 "$checker" --root "$pcopy" --repo o/r --print-update-command 2>/dev/null)"
cmp_api "$work/api-label-behind" behind; stop "$work/api-label-behind"
if [ "$rc" = 0 ] && [ -n "$one_pin" ] && [ "$printed" = "$one_pin" ]
then ok "label.yml at an ancestor of the ci job's commit: the update carries the ci job's commit, the line ci.yml alone gives"
else bad "ancestor: rc=$rc, stdout '$printed', want '$one_pin'"; sed 's/^/        /' <<<"$err"; fi
in_err "and it says label.yml moves from its commit to the ci job's" \
  "^moves: label\.yml from $sha1 to $sha40, the commit the ci job calls \($sha1 is an ancestor of it\)\$"
if grep -qE "disagree|sed -i" <<<"$err"; then bad "the ancestor case prints the stop too"; else ok "and prints nothing of the stop"; fi
out="$(FLOOR_CHECK_API_DIR="$work/api-label-behind" python3 "$checker" --root "$two" --repo o/r 2>&1)"
if is "$out" FC-F01 info && is "$out" FC-F01 info
then ok "floor-check's drift item prints the same line and the same move"
else bad "drift item, ancestor"; printf '%s\n' "$out" | grep -E 'template|copier|moves' | sed 's/^/        /'; fi

cmp_api "$work/api-label-ahead" ahead; stop "$work/api-label-ahead"
if [ "$rc" = 1 ] && [ -z "$printed" ]; then ok "label.yml newer than ci.yml: the update prints no command, exit 1"
else bad "label newer: rc=$rc, stdout '$printed'"; fi
in_err "the stop still gives the reason it gave" "^no update command: v1\.0\.0 is behind $target_ref, but there is no update command: workflow pins disagree: $sha40, $sha1\$"
in_err "the stop names ci.yml with its commit" "^  ci\.yml: coolbress/plinth at $sha40\$"
in_err "the stop names label.yml with its commit" "^  label\.yml: coolbress/plinth at $sha1\$"
in_err "the stop says label.yml's is the newer, and that raising the ci job keeps it" \
  "^newer: $sha1; the ci job's $sha40 is behind it, so the line below moves $sha1 back: to keep the newer one, raise the ci job's uses: to $sha1 instead\$"
pins "    uses: coolbress/plinth/.github/workflows/pr-label.yml@$sha1"   # floor-check's own item, on the same two pins
fix_line="$(sed -n 's/^  INFO    \(sed .*\.bak\)   (moves.*/\1/p' <<<"$out")"
if [ -n "$fix_line" ] && grep -qxF -- "  $fix_line" <<<"$err"; then ok "the stop prints the same fix line the pin-agreement item prints"
else bad "the stop's fix line is not floor-check's ('$fix_line')"; sed 's/^/        /' <<<"$err"; fi
cmp_api "$work/api-label-diverged" diverged; stop "$work/api-label-diverged"
if [ "$rc" = 1 ] && [ -z "$printed" ]; then ok "two commits neither of which is behind the other: the update prints no command, exit 1"
else bad "diverged: rc=$rc, stdout '$printed'"; fi
in_err "diverged: the stop names ci.yml with its commit" "^  ci\.yml: coolbress/plinth at $sha40\$"
in_err "diverged: the stop names label.yml with its commit" "^  label\.yml: coolbress/plinth at $sha1\$"
in_err "diverged: neither is called the newer" "^newer: not known for $sha40 and $sha1 \(the two have diverged\)\$"
if grep -qxF -- "  $fix_line" <<<"$err"; then ok "diverged: the stop prints the fix line"; else bad "diverged: no fix line"; sed 's/^/        /' <<<"$err"; fi
stop "$pinned_api"
if [ "$rc" = 1 ] && [ -z "$printed" ]; then ok "the compare not read: the update stops, never guesses an ancestor"
else bad "compare unread: rc=$rc, stdout '$printed'"; fi
in_err "the compare not read: the stop says so" "^newer: not known for $sha40 and $sha1 \(offline or API error\)\$"
if grep -qxF -- "  $fix_line" <<<"$err"; then ok "and the fix line stands without the compare"; else bad "no fix line without the compare"; fi
# Three commits, one behind the ci job's and one ahead: still a stop.
three_api="$work/api-three"; cmp_api "$three_api" behind; sha2="$(printf '%040d' 2)"
printf '{"status":"ahead"}\n' > "$three_api/repos/coolbress/plinth/compare/$sha40...$sha2.json"
printf 'jobs:\n  r:\n    uses: coolbress/plinth/.github/workflows/pr-review.yml@%s\n' "$sha2" > "$two/.github/workflows/review.yml"
stop "$three_api"
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -q "^newer: $sha2; the ci job's" <<<"$err"; then ok "one file behind the ci job's commit and another ahead of it: a stop, the newer named"
else bad "three pins: rc=$rc, stdout '$printed'"; sed 's/^/        /' <<<"$err"; fi
rm "$two/.github/workflows/review.yml"
( cd "$two" && eval "$fix_line" )
stop "$pinned_api"
if [ "$rc" = 0 ] && [ "$printed" = "$one_pin" ] && ! grep -q "^moves:" <<<"$err"
then ok "run as printed, the fix line makes the pins one, and the update prints the command it prints with one pin"
else bad "after the fix line: rc=$rc, stdout '$printed'"; sed 's/^/        /' <<<"$err"; fi
# The pins agree: nothing of the stop is added, and the line is the one
# printed with ci.yml alone.
agree="$work/agree-pins"; rm -rf "$agree"; cp -R "$pcopy" "$agree"
printf 'jobs:\n  label:\n    uses: coolbress/plinth/.github/workflows/pr-label.yml@%s\n' "$sha40" > "$agree/.github/workflows/label.yml"
printed="$(FLOOR_CHECK_API_DIR="$pinned_api" python3 "$checker" --root "$agree" --repo o/r --print-update-command 2>"$work/print-err")"; rc=$?
if [ "$rc" = 0 ] && [ "$printed" = "$warned" ] && ! grep -qE "disagree|newer:|sed -i|moves:" "$work/print-err"
then ok "ci.yml and label.yml at one commit: the same command as ci.yml alone, nothing of the stop"
else bad "pins agree: rc=$rc, stdout '$printed'"; sed 's/^/        /' "$work/print-err"; fi
# floor-check's own drift item points to the pin-agreement WARN under it.
rm -rf "$two"; cp -R "$pcopy" "$two"
printf 'jobs:\n  label:\n    uses: coolbress/plinth/.github/workflows/pr-label.yml@%s\n' "$sha1" > "$two/.github/workflows/label.yml"
out="$(FLOOR_CHECK_API_DIR="$pinned_api" python3 "$checker" --root "$two" --repo o/r 2>&1)"
if is "$out" FC-F01 info \
   && is "$out" FC-F06 warn
then ok "floor-check: the drift item's reason points to the pin-agreement WARN, which follows it"
else bad "floor-check two pins"; printf '%s\n' "$out" | grep -E 'disagree|update' | sed 's/^/        /'; fi
printed="$(python3 "$checker" --root "$noarch" --print-update-command 2>"$work/print-err")"; rc=$?
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -q "no .copier-answers.yml" "$work/print-err"; then ok "--print-update-command outside a door-made repository prints no command, exit 1"
else bad "--print-update-command, no answers file (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi

# The changed-files list and diff: one call to the template's compare API,
# made only when behind, filtered to template/ (the door's own tests, docs
# and copier.yml are not rendered into a consumer repository).
tmpl_api="$work/api-template"; mkdir -p "$tmpl_api/repos/coolbress/plinth-template/compare"
# The short list's sources as the template names them at the pin (#969): a
# fixture that fed a plain AGENTS.md matched no real file. Each name is found
# as its source with or without .jinja in the pinned checkout; none is a FAIL.
short_list="$(sed -nE 's/^TEMPLATE_DRIFT_DIFF_FILES = \((.*)\)$/\1/p' "$checker" | sed 's/[",]/ /g')"
[ -n "$short_list" ] || bad "no TEMPLATE_DRIFT_DIFF_FILES read from $checker"
src_agents="" src_contributing="" src_gitignore=""
if ! template_checkout "$work"; then bad "the pinned template checkout: $template_error"
else
  for name in $short_list; do
    src=""
    for cand in "$name" "$name.jinja"; do
      [ -f "$template_dir/template/$cand" ] && { src="template/$cand"; break; }
    done
    if [ -n "$src" ]; then ok "the short list's $name is $src at $template_at"
    else bad "the short list's $name has no source template/$name or template/$name.jinja at $template_at"; fi
    case "$name" in
      AGENTS.md) src_agents="$src" ;;
      CONTRIBUTING.md) src_contributing="$src" ;;
      .gitignore) src_gitignore="$src" ;;
      *) bad "the short list's $name has no fixture here; add one" ;;
    esac
  done
fi
src_agents="${src_agents:-template/AGENTS.md}"
src_contributing="${src_contributing:-template/CONTRIBUTING.md}"
src_gitignore="${src_gitignore:-template/.gitignore}"
patch_agents=$'@@ -1,2 +1,3 @@\n # Agents\n+one more line\n'
patch_contrib=$'@@ -1,2 +1,3 @@\n # Contributing\n+one more rule\n'
patch_ignore=$'@@ -1,1 +1,2 @@\n .venv/\n+.cache/\n'
jq -n --arg patch "$patch_agents" --arg cpatch "$patch_contrib" \
      --arg a "$src_agents" --arg c "$src_contributing" --arg g "$src_gitignore" '{files: [
    {filename: $a, status: "modified", patch: $patch},
    {filename: $c, status: "modified", patch: $cpatch},
    {filename: $g, status: "modified"},
    {filename: "docs/README.md", status: "modified"}
  ]}' > "$tmpl_api/repos/coolbress/plinth-template/compare/v1.0.0...${target_ref}.json"
tag_names "$tmpl_api" "$target_sha"
tcopy="$work/tmpl-drift"; rm -rf "$tcopy"; cp -R "$good" "$tcopy"
printf 'archetype: backend\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0\n' > "$tcopy/.copier-answers.yml"
out="$(FLOOR_CHECK_API_DIR="$tmpl_api" python3 "$checker" --root "$tcopy" 2>&1)"
want_list="$(printf '%s\n' "$src_agents" "$src_contributing" "$src_gitignore" | sed 's|^template/||' | LC_ALL=C sort | paste -sd, - | sed 's/,/, /g')"
if is "$out" FC-F01 warn; then ok "the changed-files list is scoped to template/ and strips the prefix"
else bad "changed-files list, want '$want_list'"; printf '%s\n' "$out" | grep -E 'changed in the template' | sed 's/^/        /'; fi
if grep -q "docs/README.md" <<<"$out"; then bad "a file outside template/ leaked into the changed-files list"
else ok "a file outside template/ (the door never renders it) is left out"; fi
if is "$out" FC-F01 info && is "$out" FC-F01 info \
   && is "$out" FC-F01 info && is "$out" FC-F01 info
then ok "the short list's diff is shown for AGENTS.md and CONTRIBUTING.md from their pinned sources, under the rendered names"
else bad "AGENTS.md / CONTRIBUTING.md diff"; printf '%s\n' "$out" | grep -E 'AGENTS|CONTRIBUTING|one more' | sed 's/^/        /'; fi
if grep -q "  \.gitignore:" <<<"$out"; then bad ".gitignore has no patch in the fixture; it should print no diff header"
else ok "a short-list file with no patch in the compare response prints no diff block"; fi
# The .jinja spelling whatever the pin says (#969; plinth-template#260 renames
# .gitignore): AGENTS.md.jinja and .gitignore.jinja are each shown under the
# rendered name, and a plain CONTRIBUTING.md still is.
jinja_api="$work/api-template-jinja"; mkdir -p "$jinja_api/repos/coolbress/plinth-template/compare"
jq -n --arg patch "$patch_agents" --arg cpatch "$patch_contrib" --arg gpatch "$patch_ignore" '{files: [
    {filename: "template/AGENTS.md.jinja", status: "modified", patch: $patch},
    {filename: "template/CONTRIBUTING.md", status: "modified", patch: $cpatch},
    {filename: "template/.gitignore.jinja", status: "renamed", previous_filename: "template/.gitignore", patch: $gpatch}
  ]}' > "$jinja_api/repos/coolbress/plinth-template/compare/v1.0.0...${target_ref}.json"
tag_names "$jinja_api" "$target_sha"
jout="$(FLOOR_CHECK_API_DIR="$jinja_api" python3 "$checker" --root "$tcopy" 2>&1)"
if is "$jout" FC-F01 info && is "$jout" FC-F01 info \
   && is "$jout" FC-F01 info && is "$jout" FC-F01 info \
   && is "$jout" FC-F01 info && is "$jout" FC-F01 info
then ok "template/AGENTS.md.jinja and template/.gitignore.jinja are shown as AGENTS.md and .gitignore, a plain CONTRIBUTING.md too"
else bad ".jinja sources' diff"; printf '%s\n' "$jout" | grep -E 'AGENTS|CONTRIBUTING|gitignore|one more|cache' | sed 's/^/        /'; fi
if grep -q "\.jinja:$" <<<"$jout"; then bad "a diff label kept .jinja; the label is the rendered name"
else ok "no diff label carries .jinja"; fi
# A rename git did not pair: the plain source removed, the .jinja one added.
# The diff shown is the added one's, not the deletion (fresh-context review).
jq -n --arg gpatch "$patch_ignore" '{files: [
    {filename: "template/.gitignore", status: "removed", patch: "@@ -1,1 +0,0 @@\n-.venv/"},
    {filename: "template/.gitignore.jinja", status: "added", patch: $gpatch}
  ]}' > "$jinja_api/repos/coolbress/plinth-template/compare/v1.0.0...${target_ref}.json"
jout="$(FLOOR_CHECK_API_DIR="$jinja_api" python3 "$checker" --root "$tcopy" 2>&1)"
if [ "$(grep -c "^  INFO    \.gitignore:$" <<<"$jout")" = 1 ] && is "$jout" FC-F01 info && ! grep -q "^  INFO      -\.venv/$" <<<"$jout"
then ok "a plain source removed beside its .jinja added: the added one's diff, once"
else bad "unpaired rename"; printf '%s\n' "$jout" | grep -E 'gitignore|venv|cache' | sed 's/^/        /'; fi
if grep -q "PASS  template:" <<<"$out" || grep -q "SKIP.*template drift" <<<"$out"; then bad "a behind repository must not read as passed or not verified"
else ok "a behind repository is a WARN, and only a WARN"; fi

# A compare call that fails (offline is covered above; here the fixture
# directory exists but has no entry for this path -- a 404) behaves the same:
# the WARN stands, the command still prints, the file list says it could not be read.
empty_api="$work/api-template-empty"; mkdir -p "$empty_api/repos/coolbress/plinth-template"
tcopy2="$work/tmpl-drift-404"; rm -rf "$tcopy2"; cp -R "$good" "$tcopy2"
printf 'archetype: backend\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0\n' > "$tcopy2/.copier-answers.yml"
out="$(FLOOR_CHECK_API_DIR="$empty_api" python3 "$checker" --root "$tcopy2" --repo o/r 2>&1 | grep -E 'template|copier')"
if is "$out" FC-F01 warn && is "$out" FC-F01 info; then
  ok "a compare call that 404s still prints the update command, and names the file list as unread"
else bad "a 404 on the compare call"; printf '%s\n' "$out" | grep -E 'template|copier update' | sed 's/^/        /'; fi

# The tested pin (#511): the target tag's copier.yml names the plinth commit
# it was tested with. When that is newer than the pin the workflows call,
# there is no update line until the pin is raised, in a pull request of its
# own (#1183); a live pin newer is kept; a comparison not read is said, and
# --print-update-command gives no line past it.
tested="$(printf '%040d' 3)"
pin_api() { # <copier.yml plinth_sha default or "-" for none> <compare status or "-" for none> → sets $pin_dir
  pin_dir="$work/api-pin"; rm -rf "$pin_dir"
  mkdir -p "$pin_dir/repos/coolbress/plinth-template/contents" "$pin_dir/repos/coolbress/plinth/compare"
  if [ "$1" != - ]; then
    printf 'plinth_sha:\n  type: str\n  help: |\n    Commit of coolbress/plinth.\n  default: "%s"\n\nowner_github_defaults:\n  default: "0000000000000000000000000000000000000009"\n' "$1" \
      | base64 | tr -d '\n' | jq -R '{encoding: "base64", content: .}' > "$pin_dir/repos/coolbress/plinth-template/contents/copier.yml?ref=$target_sha.json"
  else
    printf 'not json\n' > "$pin_dir/repos/coolbress/plinth-template/contents/copier.yml?ref=$target_sha.json"
  fi
  [ "$2" = - ] || jq -n --arg s "$2" '{status: $s, ahead_by: 4, behind_by: 0}' > "$pin_dir/repos/coolbress/plinth/compare/$sha40...$tested.json"
  jq -n --arg t "$tested" '[{name: "v9.0.0", commit: {sha: $t}}]' > "$pin_dir/repos/coolbress/plinth/tags?per_page=100.json"
  tag_names "$pin_dir" "$target_sha"
}
pcopy2="$work/pin-choice"; rm -rf "$pcopy2"; cp -R "$good" "$pcopy2"
printf 'archetype: backend\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0\n' > "$pcopy2/.copier-answers.yml"
printf 'jobs:\n  label:\n    uses: coolbress/plinth/.github/workflows/pr-label.yml@%s\n' "$sha40" > "$pcopy2/.github/workflows/label.yml"
pin_out() { out="$(FLOOR_CHECK_API_DIR="$pin_dir" python3 "$checker" --root "$pcopy2" --repo o/r 2>&1 | grep -E 'template|plinth|copier|pin|raise')"; lines="$(grep -c '^  INFO    uvx .*copier update' <<<"$out")"; }
pin_print() { printed="$(FLOOR_CHECK_API_DIR="$pin_dir" python3 "$checker" --root "$pcopy2" --repo o/r --print-update-command 2>"$work/print-err")"; rc=$?; }
live_line="copier update --defaults --vcs-ref $target_sha --data plinth_sha=$sha40"
pin_api "$tested" ahead; pin_out
if [ "$lines" = 0 ] && ! grep -qF "plinth_sha=$tested" <<<"$out" \
   && grep -q "INFO    no update command until the plinth pin is raised to the one the target tag was tested with:" <<<"$out"
then ok "tested pin ahead of the live one: floor-check prints no update line, and says to raise the pin first (#1183)"
else bad "tested ahead ($lines lines)"; printf '%s\n' "$out" | grep -E 'plinth|copier' | sed 's/^/        /'; fi
has "the comparison names both SHAs, the tested pin's tag and the compare URL" \
  "INFO    plinth pin: the workflows call $sha40; $target_ref was tested with $tested \(v9\.0\.0\), 4 commit\(s\) newer: https://github\.com/coolbress/plinth/compare/$sha40\.\.\.$tested\$"
has "the raise names every workflow that calls plinth, at the one tested SHA" \
  "INFO    raise it first in one pull request of its own: every coolbress/plinth uses: line in \.github/workflows/ci\.yml, \.github/workflows/label\.yml to $tested \(v9\.0\.0\), all at that one SHA; merge it, then plan the update again\$"
# --print-update-command, as the skill and the monthly reminder run it: no
# line, exit 1, the reason on stderr. The reminder reads exit 1 without its
# own "nothing to update" as "no reminder" and leaves an open issue as it is.
pin_print
if [ "$rc" = 1 ] && [ -z "$printed" ] \
   && grep -q "^no update command: the plinth pin is behind; the workflows call $sha40; $target_ref was tested with $tested (v9.0.0), 4 commit(s) newer: https://github.com/coolbress/plinth/compare/$sha40...$tested\$" "$work/print-err" \
   && grep -q "^the open pull requests were not read (offline or API error)\$" "$work/print-err" \
   && grep -q "^raise it first in one pull request of its own: every coolbress/plinth uses: line in .github/workflows/ci.yml, .github/workflows/label.yml to $tested" "$work/print-err" \
   && ! grep -qx "no update command: the recorded tag is the target tag ($target_ref): nothing to update" "$work/print-err"
then ok "--print-update-command with the pin behind: no line, exit 1, the comparison and the change on stderr, never the reminder's 'nothing to update'"
else bad "--print-update-command, pin behind (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi
# With an open pull request that raises the pin: it is named by number.
mkdir -p "$pin_dir/repos/o/r/pulls/21" "$pin_dir/repos/o/r/pulls/22"
printf '[{"number":22,"title":"fix: a bug"},{"number":21,"title":"chore(deps): bump coolbress/plinth"}]\n' > "$pin_dir/repos/o/r/pulls?state=open&per_page=100.json"
printf '[{"filename":"src/app/x.py","patch":"+uses: coolbress/plinth/x@y"}]\n' > "$pin_dir/repos/o/r/pulls/22/files?per_page=100.json"
jq -n --arg b "$tested" '[{filename: ".github/workflows/label.yml", patch: ("-    uses: coolbress/plinth/.github/workflows/pr-label.yml@old\n+    uses: \"coolbress/plinth/.github/workflows/pr-label.yml@" + $b + "\"")}]' \
  > "$pin_dir/repos/o/r/pulls/21/files?per_page=100.json"
pin_print
if [ "$rc" = 1 ] && grep -q "^merge first: #21 chore(deps): bump coolbress/plinth (https://github.com/o/r/pull/21), which changes the coolbress/plinth uses: lines" "$work/print-err" \
   && ! grep -q "#22" "$work/print-err" && grep -q "^then plan the update again\$" "$work/print-err" && ! grep -q "^raise it first" "$work/print-err"
then ok "--print-update-command names the open pull request whose workflow patch adds a plinth uses: line, and no other"
else bad "pin pull request named (rc=$rc)"; sed 's/^/        /' "$work/print-err"; fi
printf 'not json\n' > "$pin_dir/repos/o/r/pulls/21/files?per_page=100.json"; pin_print
if [ "$rc" = 1 ] && grep -q "^the open pull requests were not read (the files of #21: offline or API error)" "$work/print-err" && grep -q "^raise it first" "$work/print-err"
then ok "a pull request's files not read: the lookup is said as not read, never as none, and the change printed"
else bad "pin pull request files unread (rc=$rc)"; sed 's/^/        /' "$work/print-err"; fi

rm "$pin_dir/repos/coolbress/plinth/tags?per_page=100.json"; pin_out
if [ "$lines" = 0 ] && grep -q "INFO    plinth pin: the workflows call $sha40; $target_ref was tested with $tested, 4 commit(s) newer (release tags not read): https://" <<<"$out"
then ok "the tag list unread: the comparison says so, rather than reading as an untagged commit"
else bad "tags unread ($lines lines)"; printf '%s\n' "$out" | grep -E 'plinth pin' | sed 's/^/        /'; fi

pin_api "$tested" behind; pin_out
if [ "$lines" = 1 ] && grep -qF "$live_line" <<<"$out" \
   && grep -q "INFO    plinth pin: the workflows call $sha40, newer than $tested (v9.0.0) that $target_ref was tested with; the update keeps it" <<<"$out"
then ok "live pin ahead of the tested one: one line, kept because it is newer"
else bad "live ahead ($lines lines)"; printf '%s\n' "$out" | grep -E 'plinth|copier' | sed 's/^/        /'; fi
pin_print
if [ "$rc" = 0 ] && case "$printed" in *"$live_line$no_shared") true ;; *) false ;; esac && grep -q "newer than $tested" "$work/print-err"
then ok "--print-update-command with the live pin newer: the live line, the comparison on stderr"
else bad "--print-update-command, live ahead (rc=$rc, stdout '$printed')"; fi

pin_api "$sha40" -; pin_out
if [ "$lines" = 1 ] && grep -qF "$live_line" <<<"$out" && ! grep -q "plinth pin:" <<<"$out"
then ok "live pin equal to the tested one: one line, no comparison"
else bad "equal ($lines lines)"; printf '%s\n' "$out" | grep -E 'plinth|copier' | sed 's/^/        /'; fi

pin_api "$tested" -; pin_out
if [ "$lines" = 1 ] && grep -qF "$live_line" <<<"$out" \
   && grep -q "INFO    plinth pin: the workflows call $sha40; $target_ref was tested with $tested, but the two were not compared (offline or API error)\$" <<<"$out" \
   && grep -q "INFO    the template-update skill stops before it runs this line until the two are compared" <<<"$out"
then ok "the compare unreadable: floor-check shows the line, names the comparison as not read and says the skill stops"
else bad "compare unread ($lines lines)"; printf '%s\n' "$out" | grep -E 'plinth|copier' | sed 's/^/        /'; fi
pin_print
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -q "^no update command: whether the plinth pin is older than the one $target_ref was tested with was not read; the workflows call $sha40; $target_ref was tested with $tested, but the two were not compared (offline or API error)" "$work/print-err"
then ok "--print-update-command past an unread comparison prints no line, exit 1, and says what was not read"
else bad "--print-update-command, compare unread (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi

pin_api "$tested" diverged; pin_out
if [ "$lines" = 1 ] && is "$out" FC-F01 info
then ok "diverged commits: one line, no direction claimed"
else bad "diverged ($lines lines)"; printf '%s\n' "$out" | grep -E 'plinth|copier' | sed 's/^/        /'; fi

pin_api - ahead; pin_out
if [ "$lines" = 1 ] && grep -qF "$live_line" <<<"$out" \
   && grep -q "INFO    plinth pin: the one $target_ref was tested with was not read (coolbress/plinth-template copier.yml at $target_ref: offline or API error), so whether $sha40 is older was not read" <<<"$out"
then ok "the tested pin unreadable: one line, named as not read"
else bad "tested unread ($lines lines)"; printf '%s\n' "$out" | grep -E 'plinth|copier' | sed 's/^/        /'; fi
pin_print
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -q "^no update command: whether the plinth pin is older than the one $target_ref was tested with was not read" "$work/print-err"
then ok "--print-update-command with the tested pin unreadable: no line, exit 1"
else bad "--print-update-command, tested unread (rc=$rc, stdout '$printed')"; fi
pin_api "not-a-sha" ahead; pin_out
if [ "$lines" = 1 ] && is "$out" FC-F01 info; then ok "a plinth_sha default that is not a full SHA is not read, not offered"
else bad "malformed default ($lines lines)"; printf '%s\n' "$out" | grep -E 'plinth pin' | sed 's/^/        /'; fi

# The owner's shared templates (#726). The update carries whether
# `<owner>/.github` publishes a pull-request template and issue forms, as
# /plinth:new-project's render did, read the same way and decided by the
# same functions (scripts/lib/shared-github.sh). Without them the update
# reads both as false and can write one local form that hides every shared
# one. A read that fails is not an answer: no line. An answer is true only
# while the repository has none of its own: its own already replace the
# owner's, and true would have copier delete them. $ocopy has no local
# issue forms; the good fixture ($pcopy) has three.
ocopy="$work/owner-copy"; rm -rf "$ocopy"; cp -R "$pcopy" "$ocopy"; rm -r "$ocopy/.github/ISSUE_TEMPLATE"
owner_api() { # <name>: a copy of the pinned fixture, o/.github public, in $oa
  oa="$work/api-owner-$1"; rm -rf "$oa"; cp -R "$pinned_api" "$oa"
  mkdir -p "$oa/repos/o/.github/contents/.github/ISSUE_TEMPLATE" "$oa/repos/o/.github/contents/docs"
  printf '{"visibility":"public"}\n' > "$oa/repos/o/.github.json"
}
form_file() { # <name> <text>: a form in o/.github's shared folder, as the contents API gives it
  printf '%s' "$2" | base64 | tr -d '\n' | jq -R '{content: .}' > "$oa/repos/o/.github/contents/.github/ISSUE_TEMPLATE/$1.json"
}
listing() { jq -n '[$ARGS.positional[] | {name: .}]' --args "$@" > "$oa/repos/o/.github/contents/.github/ISSUE_TEMPLATE.json"; }
owner_line() { # <description> <ERE for the printed line's end, or "-" for none> [ERE on stderr] [root]
  local printed rc
  printed="$(FLOOR_CHECK_API_DIR="$oa" python3 "$checker" --root "${4:-$ocopy}" --repo o/r --print-update-command 2>"$work/print-err")"; rc=$?
  if [ "$2" = - ]; then
    if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -qE -- "$3" "$work/print-err"; then ok "$1"
    else bad "$1 (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi
  elif [ "$rc" = 0 ] && grep -qE -- "$2\$" <<<"$printed" && { [ -z "${3:-}" ] || grep -qE -- "$3" "$work/print-err"; }; then ok "$1"
  else bad "$1 (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi
}
owner_api forms; listing bug.yml config.yml
form_file bug.yml $'name: Bug\ndescription: d\nbody:\n  - type: textarea\n'
owner_line "an owner whose public .github shares issue forms: owner_has_issue_forms=true" \
  "plinth_sha=$sha40 --data owner_has_pr_template=false --data owner_has_issue_forms=true"
out="$(FLOOR_CHECK_API_DIR="$oa" python3 "$checker" --root "$ocopy" --repo o/r 2>&1 | sed -n 's/^  INFO    \(uvx .*copier update.*\)$/\1/p')"
if [ "$out" = "$(FLOOR_CHECK_API_DIR="$oa" python3 "$checker" --root "$ocopy" --repo o/r --print-update-command 2>/dev/null)" ]
then ok "the drift item prints the same line, answers and all"; else bad "drift item line with the owner's answers: '$out'"; fi
owner_line "the repository's own forms replace the owner's already: false, kept, and said so" "$no_shared" \
  "^o/\.github shares issue forms, but this repository's own \.github/ISSUE_TEMPLATE replaces them; the update keeps those" "$pcopy"
printf '{}\n' > "$oa/repos/o/.github/contents/docs/PULL_REQUEST_TEMPLATE.md.json"
owner_line "a pull-request template in the owner's docs/ counts, as the door counts it: owner_has_pr_template=true" \
  "--data owner_has_pr_template=true --data owner_has_issue_forms=true"
own_pr="$work/owner-own-pr"; rm -rf "$own_pr"; cp -R "$ocopy" "$own_pr"; mkdir -p "$own_pr/docs"; printf '## What\n' > "$own_pr/docs/PULL_REQUEST_TEMPLATE.md"
owner_line "the repository's own pull-request template, in docs/: false, kept, and said so" \
  "--data owner_has_pr_template=false --data owner_has_issue_forms=true" \
  "^o/\.github shares a pull-request template, but this repository has its own; the update keeps it" "$own_pr"
both_own="$work/owner-both-own"; rm -rf "$both_own"; cp -R "$pcopy" "$both_own"; printf '## What\n' > "$both_own/.github/PULL_REQUEST_TEMPLATE.md"
owner_api empty-form; listing bug.yml; printf '{"content":""}\n' > "$oa/repos/o/.github/contents/.github/ISSUE_TEMPLATE/bug.yml.json"
owner_line "a shared form that is empty is not a form GitHub offers: false" "$no_shared"
owner_api config; listing config.yml
owner_line "a shared folder with only a config: false, and the line says that config will not apply" "$no_shared" \
  "^o/\.github publishes an issue-template config but no form; the update writes the template's forms and config"
owner_api private; printf '{"visibility":"private"}\n' > "$oa/repos/o/.github.json"; listing bug.yml
form_file bug.yml $'name: Bug\ndescription: d\nbody:\n  - type: textarea\n'
owner_line "a private .github is never inherited from: both false, whatever it holds" "$no_shared"
owner_api vis-unread; printf 'not json\n' > "$oa/repos/o/.github.json"
owner_line "the .github repository's visibility not read: no line, and it says what was not read" - \
  "cannot read whether o/\.github is public \(offline or API error\); a failed lookup is not an answer"
owner_line "a repository with its own forms and pull-request template needs no read: both false, even then" "$no_shared" "" "$both_own"
owner_api list-unread; printf 'not json\n' > "$oa/repos/o/.github/contents/.github/ISSUE_TEMPLATE.json"
owner_line "the shared folder's listing not read: no line" - \
  "cannot read whether o/\.github publishes shared templates \(\.github/ISSUE_TEMPLATE: offline or API error\)"
owner_api form-unread; listing bug.yml
printf 'not json\n' > "$oa/repos/o/.github/contents/.github/ISSUE_TEMPLATE/bug.yml.json"
owner_line "one shared form not read: no line, naming it" - \
  "cannot read whether o/\.github publishes shared templates \(\.github/ISSUE_TEMPLATE/bug\.yml: offline or API error\)"
owner_api pr-unread; printf 'not json\n' > "$oa/repos/o/.github/contents/PULL_REQUEST_TEMPLATE.md.json"
owner_line "the pull-request template's read failing: no line" - \
  "cannot read whether o/\.github publishes shared templates \(PULL_REQUEST_TEMPLATE\.md: offline or API error\)"
out="$(FLOOR_CHECK_API_DIR="$oa" python3 "$checker" --root "$ocopy" --repo o/r 2>&1)"
if is "$out" FC-F01 info && ! grep -q "INFO    uvx" <<<"$out"
then ok "and the drift item prints no line either, with the same reason"
else bad "drift item, owner unread"; printf '%s\n' "$out" | grep -E 'template|copier' | sed 's/^/        /'; fi
printed="$(FLOOR_CHECK_API_DIR="$pinned_api" python3 "$checker" --root "$ocopy" --print-update-command 2>"$work/print-err")"; rc=$?
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -q "no --repo, so whether the owner's .github publishes" "$work/print-err"
then ok "--print-update-command without --repo prints no line: the owner's answers were not read"
else bad "--print-update-command without --repo (rc=$rc, stdout '$printed')"; fi
# The decisions are new-project.sh's own: the checker finds them beside it.
libless="$work/libless"; mkdir -p "$libless"; cp "$checker" "$root/scripts/new-project.sh" "$libless/"
printed="$(FLOOR_CHECK_API_DIR="$pinned_api" python3 "$libless/floor-check.py" --root "$ocopy" --repo o/r --print-update-command 2>"$work/print-err")"; rc=$?
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -q "lib/shared-github.sh not found beside the checker" "$work/print-err"
then ok "no scripts/lib/shared-github.sh beside the checker: no line, rather than a guess"
else bad "missing shared-github.sh (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi
# `ci / floor-check` downloads the checker into $RUNNER_TEMP/plinth: the
# layout rebuilt from that step's own curl lines must give the line too.
cilayout="$work/ci-layout"; mkdir -p "$cilayout/lib"
fetch="$(sed -n '/name: Fetch the checker from the same plinth commit/,/name: Floor check/p' "$root/.github/workflows/python-ci.yml")"
for f in $(sed -nE 's/^ *for f in (.*); do$/\1/p' <<<"$fetch"); do cp "$root/$f" "$cilayout/$(basename "$f")"; done
grep -q 'curl .*-o "\$d/lib/shared-github.sh"' <<<"$fetch" && cp "$root/scripts/lib/shared-github.sh" "$cilayout/lib/"
printed="$(FLOOR_CHECK_API_DIR="$pinned_api" python3 "$cilayout/floor-check.py" --root "$ocopy" --repo o/r --print-update-command 2>"$work/print-err")"; rc=$?
if [ "$rc" = 0 ] && grep -q -- "$no_shared\$" <<<"$printed"
then ok "the files ci / floor-check downloads include the shared-template decisions: the update line prints there"
else bad "ci / floor-check's downloaded layout (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi

# Single-sourced: the target comes from scripts/new-project.sh beside the
# checker, never a copy inside floor-check.py itself.
selfdir="$work/selfcheck"; mkdir -p "$selfdir"
cp "$checker" "$selfdir/floor-check.py"
sed "s/^template_ref=\"$target_ref\"\$/template_ref=\"v9.9.9\"/" "$root/scripts/new-project.sh" > "$selfdir/new-project.sh"
if ! grep -q 'template_ref="v9.9.9"' "$selfdir/new-project.sh"; then
  bad "test setup: could not rewrite template_ref in the copied new-project.sh"
else
  scopy="$work/self-repo"; rm -rf "$scopy"; cp -R "$good" "$scopy"
  printf 'archetype: backend\n_src_path: gh:coolbress/plinth-template\n_commit: v9.9.9\n' > "$scopy/.copier-answers.yml"
  out="$(python3 "$selfdir/floor-check.py" --root "$scopy" --no-network 2>&1)"
  if is "$out" FC-F01 pass
  then ok "the target tag is read from scripts/new-project.sh beside the checker, not a copy inside it (a fake v9.9.9 pin is honoured)"
  else bad "the checker did not honour a rewritten new-project.sh beside it"; printf '%s\n' "$out" | grep template | sed 's/^/        /'; fi
fi
selfdir2="$work/selfcheck-missing"; mkdir -p "$selfdir2"
cp "$checker" "$selfdir2/floor-check.py"
out="$(python3 "$selfdir2/floor-check.py" --root "$good" --no-network 2>&1)"
if is "$out" FC-F01 unknown
then ok "no new-project.sh beside the checker: not verified, not passed"
else bad "a missing new-project.sh"; printf '%s\n' "$out" | grep template | sed 's/^/        /'; fi

# --project outside --root is a usage error, not a traceback (#464): every
# item reads one repository, so the pair is refused before any item runs.
out="$(python3 "$checker" --root "$good" --project "$work" --no-network 2>&1)"; rc=$?
if [ "$rc" = 2 ] && grep -q -- "--project must be inside --root" <<<"$out" && ! grep -qE '^  (PASS|FAIL|WARN|SKIP)  ' <<<"$out" && ! grep -q Traceback <<<"$out"; then
  ok "--project outside --root exits 2 with one message and runs no item"
else bad "--project outside --root should exit 2 with the message and no item (rc=$rc)"; printf '%s\n' "$out" | head -5 | sed 's/^/        /'; fi
out="$(python3 "$checker" --root "$good" --project "$good" --no-network 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q '^floor check: root=.* project=\.$' <<<"$out"; then ok "--project equal to --root runs as today"
else bad "--project equal to --root should run as today (rc=$rc)"; printf '%s\n' "$out" | head -3 | sed 's/^/        /'; fi
out="$(python3 "$checker" --root "$good" --project docs --no-network 2>&1)"; rc=$?
if [ "$rc" != 2 ] && grep -q '^floor check: root=.* project=docs$' <<<"$out"; then ok "--project under --root runs as today"
else bad "--project under --root should run as today (rc=$rc)"; printf '%s\n' "$out" | head -3 | sed 's/^/        /'; fi

# The caller (#325): the `ci` job in ci.yml calls plinth's python-ci.yml at a
# full commit SHA. A pull request that swaps that call for plain jobs of the
# same check names turns every required check green; this item sees it from
# outside the pull request, on the default branch.
echo "-- the ci job calls plinth's workflow (#325)"
caller() { # <description> <ci.yml content> <expected line regex> [<checker args>...]
  local desc="$1" body="$2" want="$3"; shift 3
  local copy="$work/caller"; rm -rf "$copy"; cp -R "$good" "$copy"
  printf '%s' "$body" > "$copy/.github/workflows/ci.yml"
  local out; out="$(python3 "$checker" --root "$copy" --archetype cli --no-network "$@" 2>&1)"
  if sees "$out" "$want" -E "$want"; then ok "$desc"; else bad "$desc (expected /$want/)"; printf '%s\n' "$out" | grep -iE 'ci job|ci\.yml|failed' | sed 's/^/        /'; fi
}
tmpl_ci="$(printf 'name: CI\non:\n  pull_request:\njobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s # v1.0.0\n    permissions:\n      contents: read\n' "$sha40")"
caller "the template's ci.yml passes, read from the checkout offline and saying so" "$tmpl_ci" \
  "FC-D02 pass"
caller "the ci job replaced by plain jobs of the same check names is a FAIL" \
  "$(printf 'jobs:\n  install:\n    name: ci / install\n    runs-on: ubuntu-latest\n    steps:\n      - run: "true"\n  tools:\n    name: ci / tools\n    runs-on: ubuntu-latest\n    steps:\n      - run: "true"\n')" \
  "FC-D02 fail"
caller "a ci job that runs its own steps is a FAIL" \
  "$(printf 'jobs:\n  ci:\n    runs-on: ubuntu-latest\n    steps:\n      - run: |\n          echo uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n' "$sha40")" \
  "FC-D02 fail"
caller "another repository's python-ci.yml is a FAIL" \
  "$(printf 'jobs:\n  ci:\n    uses: coolbress/other/.github/workflows/python-ci.yml@%s\n' "$sha40")" \
  "FC-D02 fail"
caller "a fork's python-ci.yml is a FAIL" \
  "$(printf 'jobs:\n  ci:\n    uses: someone/plinth/.github/workflows/python-ci.yml@%s\n' "$sha40")" \
  "FC-D02 fail"
caller "a local workflow is a FAIL outside coolbress/plinth" \
  "$(printf 'jobs:\n  ci:\n    uses: ./.github/workflows/python-ci.yml\n')" \
  "FC-D02 fail"
caller "plinth's workflow pinned to a tag is a FAIL" \
  "$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@v1.0.0\n')" \
  "FC-D02 fail"
caller "a tag pin's fix line looks up that tag's commit" \
  "$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@v1.0.0\n')" \
  "FC-D02 info"
caller "a missing call's fix line looks up plinth's latest release" \
  "$(printf 'jobs:\n  install:\n    name: ci / install\n    steps:\n      - run: "true"\n')" \
  "FC-D02 info"
caller "plinth's workflow pinned to a branch is a FAIL" \
  "$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@main\n')" \
  "FC-D02 fail"
caller "a ci job with an if: condition is a FAIL: it can be skipped" \
  "$(printf "jobs:\n  ci:\n    if: github.head_ref == 'bootstrap'\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n" "$sha40")" \
  "FAIL  .*ci job.*if:.*skipped"
caller "a ci job with needs: is a FAIL: it is skipped with what it needs" \
  "$(printf 'jobs:\n  gate:\n    if: false\n    runs-on: x\n    steps:\n      - run: "true"\n  ci:\n    needs: gate\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n' "$sha40")" \
  "FC-D02 fail"
for key in 'name: decoy' 'strategy:' 'concurrency: x' 'timeout-minutes: 1'; do
  caller "  a ci job with '$key' is a FAIL: only uses, with, secrets and permissions are allowed" \
    "$(printf 'jobs:\n  ci:\n    %s\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n' "$key" "$sha40")" \
    "FC-D02 fail"
done
caller "a continuation line under uses: (YAML folds it into the value) is a SKIP, not a pass" \
  "$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n      extra\n' "$sha40")" \
  "FC-D02 unknown"
caller "with:, secrets: and permissions: on the ci job still pass" \
  "$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n    with:\n      if: x\n    secrets: inherit\n    permissions:\n      contents: read\n' "$sha40")" \
  "FC-D02 pass"
caller "another of plinth's workflows is a FAIL" \
  "$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/third-party.yml@%s\n' "$sha40")" \
  "FC-D02 fail"
caller "a quoted ci key and a quoted value are read" \
  "$(printf 'jobs:\n  "ci":\n    uses: "coolbress/plinth/.github/workflows/python-ci.yml@%s"\n' "$sha40")" \
  "FC-D02 pass"
caller "a flow-style jobs mapping is a SKIP, not a pass" \
  "$(printf 'jobs: {ci: {uses: coolbress/plinth/.github/workflows/python-ci.yml@%s}}\n' "$sha40")" \
  "FC-D02 unknown"
caller "a ci job that is an alias is a SKIP, not a pass" \
  "$(printf 'x: &c\n  uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\njobs:\n  ci: *c\n' "$sha40")" \
  "FC-D02 unknown"
caller "a merge key inside the ci job is a SKIP, not a pass" \
  "$(printf 'x: &c\n  uses: coolbress/other/.github/workflows/python-ci.yml@%s\njobs:\n  ci:\n    <<: *c\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n' "$sha40" "$sha40")" \
  "FC-D02 unknown"
caller "an escaped quoted key (a second jobs YAML decodes) is a SKIP, not a pass" \
  "$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n"jo\\u0062s":\n  install:\n    runs-on: x\n' "$sha40")" \
  "FC-D02 unknown"
caller "an escaped quoted ci key is a SKIP, not a pass" \
  "$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n  "c\\x69":\n    runs-on: x\n' "$sha40")" \
  "FC-D02 unknown"
caller "an alias as a top-level key (a second jobs) is a SKIP, not a pass" \
  "$(printf 'name: x\nrun-name:\n  - &j jobs\njobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n*j :\n  ci:\n    uses: someone/else/.github/workflows/x.yml@%s\n' "$sha40" "$sha40")" \
  "FC-D02 unknown"
for top in '!!str jobs:' '? jobs' '<<: *base' '---'; do
  caller "  a top-level line written as '$top' is a SKIP" \
    "$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n%s\n' "$sha40" "$top")" \
    "FC-D02 unknown"
done
# A document marker opening the file is what yamllint's document-start rule
# asks for (#334); a second one starts another document and is still unread.
caller "a ci.yml opening with --- reads like the same file without it" "$(printf -- '---\n%s\n' "$tmpl_ci")" \
  "FC-D02 pass"
caller "a --- with a comment, after a comment, also opens it" "$(printf -- '# c\n--- # start\n%s\n' "$tmpl_ci")" \
  "FC-D02 pass"
caller "a leading --- and a second one (two documents) is a SKIP, not a pass" \
  "$(printf -- '---\n%s\n---\njobs:\n  ci:\n    runs-on: x\n' "$tmpl_ci")" \
  "FC-D02 unknown"
caller "a --- carrying content on its line is a SKIP, not a pass" "$(printf -- '--- !!map\n%s\n' "$tmpl_ci")" \
  "FC-D02 unknown"
# A `: |` in a trailing comment opens no block scalar (#334); a real one still does.
for c in '# note: |' '# note: >' '# a: |-'; do
  caller "  a jobs: line whose comment ends '$c' still shows the jobs" \
    "$(printf 'jobs:  %s\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n' "$c" "$sha40")" \
    "FC-D02 pass"
done
caller "a run: | with a trailing comment is still a block scalar" \
  "$(printf 'jobs:\n  ci:\n    runs-on: ubuntu-latest\n    steps:\n      - run: |  # note\n          uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n' "$sha40")" \
  "FC-D02 fail"
caller "a flow value on a top-level key (on: [push, pull_request]) still reads" \
  "$(printf 'on: [push, pull_request]\njobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n' "$sha40")" \
  "FC-D02 pass"
caller "two ci keys are a SKIP, not a pass" \
  "$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n  ci:\n    runs-on: x\n' "$sha40")" \
  "FC-D02 unknown"
# Two inputs set how much a check holds (#435): a `with:` that loosens one
# past plinth's default (max-diff-lines 0 or above 400, deps-fail-on-severity
# critical) is a WARN every run, naming the input, its value and
# the default; a stricter value or none prints nothing; an expression is a
# SKIP. Neither changes the exit code.
echo "-- the ci job's with: loosens a check past its default (#435)"
with_ci() { # <with: lines, each indented six spaces>
  printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n    with:\n%s\n' "$sha40" "$1"
}
loosened() { # <description> <with: lines or ""> <expected: none|WARN|SKIP> [<regex the line matches>]
  local desc="$1" body="$2" want="$3" re="${4:-}"
  local copy="$work/caller"; rm -rf "$copy"; cp -R "$good" "$copy"
  if [ -n "$body" ]; then with_ci "$body" > "$copy/.github/workflows/ci.yml"; else printf '%s' "$tmpl_ci" > "$copy/.github/workflows/ci.yml"; fi
  local out rc; out="$(python3 "$checker" --root "$copy" --archetype cli --no-network 2>&1)"; rc=$?
  local lines; lines="$(grep -E '^  (WARN|SKIP|FAIL) .*(max-diff-lines|deps-fail-on-severity)' <<<"$out")"
  local n; n="$(grep -c . <<<"$lines")"
  if [ "$rc" != "$base_rc" ]; then bad "$desc (exit $rc, the same ci.yml without it exits $base_rc)"
  elif [ "$want" = none ] && [ "$n" = 0 ]; then ok "$desc"
  elif [ "$want" != none ] && [ "$n" = 1 ] && grep -qE "^  $want  .*${re}" <<<"$lines"; then ok "$desc"
  else bad "$desc (expected $want${re:+ /$re/})"; printf '%s\n' "$out" | grep -iE 'ci job|max-diff|severity' | sed 's/^/        /'; fi
}
copy="$work/caller"; rm -rf "$copy"; cp -R "$good" "$copy"; printf '%s' "$tmpl_ci" > "$copy/.github/workflows/ci.yml"
python3 "$checker" --root "$copy" --archetype cli --no-network >/dev/null 2>&1; base_rc=$?
loosened "max-diff-lines left absent: nothing" "" none
loosened "max-diff-lines: 0 is a WARN naming the input, its value and the default" "      max-diff-lines: 0" WARN \
  "max-diff-lines: 0.*default.*400"
loosened "max-diff-lines: -1 (the workflow treats it as 0) is a WARN" "      max-diff-lines: -1" WARN "max-diff-lines: -1.*never fails"
loosened "max-diff-lines: 200 (a smaller limit, stricter): nothing" "      max-diff-lines: 200" none
loosened "max-diff-lines: 400 (the default): nothing" "      max-diff-lines: 400" none
loosened "max-diff-lines: 1000 (a larger limit lets a larger diff pass) is a WARN" "      max-diff-lines: 1000" WARN \
  "max-diff-lines: 1000.*above.*400"
loosened "max-diff-lines quoted and with a comment is read: '0'" "      max-diff-lines: '0'   # measure only" WARN "max-diff-lines: 0"
for v in nan inf -inf; do
  loosened "  max-diff-lines: $v is a SKIP, not a pass" "      max-diff-lines: $v" SKIP "not read as a whole number"
done
loosened "  max-diff-lines: 0.5 is a SKIP (the workflow's integer test errors on it)" "      max-diff-lines: 0.5" SKIP "not read as a whole number"
loosened "an explicit ? key in with: is a SKIP, not a pass" "$(printf '      ? max-diff-lines\n      : 0')" SKIP "with: line this checker does not read"
loosened "a merge key in with: is a SKIP, not a pass" "      <<: *defaults" SKIP "with: line this checker does not read"
loosened "an upper-case input name is read" "      MAX-DIFF-LINES: 0" WARN "max-diff-lines: 0"
loosened "max-diff-lines as an expression is a SKIP" '      max-diff-lines: ${{ vars.MAX }}' SKIP "max-diff-lines.*not read"
loosened "deps-fail-on-severity: critical is a WARN naming the default" "      deps-fail-on-severity: critical" WARN \
  "deps-fail-on-severity: critical.*default.*high"
loosened "deps-fail-on-severity: high (the default): nothing" "      deps-fail-on-severity: high" none
loosened "deps-fail-on-severity: moderate (stricter): nothing" "      deps-fail-on-severity: moderate" none
loosened "deps-fail-on-severity as an expression is a SKIP" '      deps-fail-on-severity: ${{ inputs.sev }}' SKIP "deps-fail-on-severity.*not read"
loosened "deps-fail-on-severity: \"critical\" quoted is read" '      deps-fail-on-severity: "critical"' WARN "deps-fail-on-severity: critical"
loosened "deps-fail-on-severity: CRITICAL, not a value the action lists, is a SKIP" '      deps-fail-on-severity: CRITICAL' SKIP "not read as a severity"
loosened "an input that continues on the next line is a SKIP" "$(printf '      max-diff-lines:\n        0')" SKIP "max-diff-lines.*not read"
loosened "other inputs are not judged" "$(printf '      working-directory: x\n      extra-python-versions: "3.12"\n      diff-size-exclude: "*"')" none
copy="$work/caller"; rm -rf "$copy"; cp -R "$good" "$copy"
with_ci "$(printf '      max-diff-lines: 0\n      deps-fail-on-severity: critical')" > "$copy/.github/workflows/ci.yml"
out="$(python3 "$checker" --root "$copy" --archetype cli --no-network 2>&1)"; rc=$?
if [ "$rc" = "$base_rc" ] && [ "$(grep -cE '^  WARN  .*(max-diff-lines|deps-fail-on-severity)' <<<"$out")" = 2 ]; then
  ok "both loosened: two WARNs, the exit code unchanged ($rc)"
else bad "both loosened: expected two WARNs and exit $base_rc, got exit $rc"; printf '%s\n' "$out" | grep -iE 'max-diff|severity' | sed 's/^/        /'; fi
# The web archetype's caller passes `web: true` (#614). Without it the two
# web-only checks pass as "does not apply" while the ruleset requires them,
# so only a literal true passes and anything else is a FAIL.
echo "-- the web archetype's ci job passes web: true (#614)"
web_input() { # <description> <archetype> <with: lines or ""> <expected: PASS|FAIL|none> [<regex>]
  local desc="$1" arch="$2" body="$3" want="$4" re="${5:-}"
  local copy="$work/caller"; rm -rf "$copy"; cp -R "$good" "$copy"
  if [ -n "$body" ]; then with_ci "$body" > "$copy/.github/workflows/ci.yml"; else printf '%s' "$tmpl_ci" > "$copy/.github/workflows/ci.yml"; fi
  local out rc; out="$(python3 "$checker" --root "$copy" --archetype "$arch" --no-network 2>&1)"; rc=$?
  local lines; lines="$(grep -E '^  (PASS|FAIL) .*(web: |web:$|no web: line)' <<<"$out")"
  if [ "$want" = none ] && [ -z "$lines" ]; then ok "$desc"
  elif [ "$want" = FAIL ] && [ "$rc" = 1 ] && grep -qE "^  FAIL  .*${re}" <<<"$lines"; then ok "$desc"
  elif [ "$want" = PASS ] && grep -qE "^  PASS  .*${re}" <<<"$lines" && ! grep -q '^  FAIL  .*web' <<<"$lines"; then ok "$desc"
  else bad "$desc (expected $want${re:+ /$re/}, exit $rc)"; printf '%s\n' "$out" | grep -iE 'ci job|web' | sed 's/^/        /'; fi
}
web_input "web: true on the web archetype passes" web "      web: true" PASS "passes web: true"
web_input "web: 'true' quoted passes" web "      web: 'true'" PASS "passes web: true"
web_input "no web: line on the web archetype is a FAIL" web "      max-diff-lines: 400" FAIL "no web: line"
web_input "web: false on the web archetype is a FAIL" web "      web: false" FAIL "web: false"
web_input "web: an expression on the web archetype is a FAIL" web '      web: ${{ inputs.x }}' FAIL "web: "
web_input "another archetype without web: says nothing about it" cli "      max-diff-lines: 400" none
caller "two with: keys on the ci job are a SKIP, not a pass" \
  "$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n    with:\n      max-diff-lines: 0\n    with:\n      max-diff-lines: 200\n' "$sha40")" \
  "FC-D02 unknown"
caller "a loosened input on a workflow that is not plinth's is not judged (the call is the FAIL)" \
  "$(printf 'jobs:\n  ci:\n    uses: someone/else/.github/workflows/python-ci.yml@%s\n    with:\n      max-diff-lines: 0\n' "$sha40")" \
  "FC-D02 fail"
copy="$work/caller"; rm -rf "$copy"; cp -R "$good" "$copy"
printf 'jobs:\n  ci:\n    uses: someone/else/.github/workflows/python-ci.yml@%s\n    with:\n      max-diff-lines: 0\n' "$sha40" > "$copy/.github/workflows/ci.yml"
if python3 "$checker" --root "$copy" --archetype cli --no-network 2>&1 | grep -q 'max-diff-lines'; then bad "  and no max-diff-lines line"
else ok "  and no max-diff-lines line"; fi

# Counted: a SKIP here is one more "not verified" in the summary.
# The baseline offline run without --repo has one: the unchecked wall.
skipcount() { # <description> <expected not-verified count> <shell to change the copy>
  local copy="$work/caller"; rm -rf "$copy"; cp -R "$good" "$copy"; ( cd "$copy" && eval "$3" )
  local out; out="$(python3 "$checker" --root "$copy" --archetype cli --no-network 2>&1)"
  if grep -q -- "-- 0 failed, $2 not verified" <<<"$out" && is "$out" FC-D02 unknown; then ok "$1"
  else bad "$1"; printf '%s\n' "$out" | grep -E 'SKIP|failed' | sed 's/^/        /'; fi
}
skipcount "an unreadable ci.yml is counted as not verified (with the action-pin and plinth-pin items' own SKIPs)" 4 \
  "printf 'jobs: {ci: {uses: coolbress/plinth/.github/workflows/python-ci.yml@%s}}\n' '$sha40' > .github/workflows/ci.yml"
skipcount "no ci.yml in the checkout under --no-network is a SKIP counted as not verified" 2 \
  "rm .github/workflows/ci.yml"

# With --repo and the network, the file comes from the default branch through
# the API, whatever the checkout holds.
capi="$work/api-caller"; mkdir -p "$capi/repos/o/r/contents/.github/workflows" "$capi/repos/coolbress/plinth/contents/.github/workflows"
printf '{"default_branch":"main"}' > "$capi/repos/o/r.json"
contents() { jq -n --arg c "$(printf '%s' "$1" | base64 | tr -d '\n')" '{type: "file", encoding: "base64", content: $c}'; }
from_api() { # <description> <default-branch ci.yml or __404__ or raw JSON after "json:"> <checkout ci.yml> <`<id> <state>` expected> [<repo>]
  local desc="$1" remote="$2" local_ci="$3" want="$4" repo="${5:-o/r}"
  local f="$capi/repos/$repo/contents/.github/workflows/ci.yml.json"; rm -f "$f"
  case "$remote" in __404__) ;; json:*) printf '%s' "${remote#json:}" > "$f" ;; *) contents "$remote" > "$f" ;; esac
  local copy="$work/caller"; rm -rf "$copy"; cp -R "$good" "$copy"
  printf '%s' "$local_ci" > "$copy/.github/workflows/ci.yml"
  local out; out="$(FLOOR_CHECK_API_DIR="$capi" python3 "$checker" --root "$copy" --archetype cli --repo "$repo" 2>&1)"
  if reports "$out" "$want"; then ok "$desc"; else bad "$desc (expected $want)"; printf '%s\n' "$out" | grep -iE 'ci job|ci\.yml' | sed 's/^/        /'; fi
}
plain_ci="$(printf 'jobs:\n  install:\n    name: ci / install\n    steps:\n      - run: "true"\n')"
from_api "a default branch without the call is a FAIL, though the checkout has it" "$plain_ci" "$tmpl_ci" \
  "FC-D02 fail"
from_api "a default branch with the call passes, though the checkout lost it" "$tmpl_ci" "$plain_ci" \
  "FC-D02 pass"
from_api "no ci.yml on the default branch is a FAIL" "__404__" "$tmpl_ci" \
  "FC-D02 fail"
from_api "a repository the API cannot see at all is a SKIP, not a missing ci.yml" "__404__" "$tmpl_ci" \
  "FC-D02 unknown" x/gone
from_api "an API answer that is not a file is a SKIP, not a pass" "json:[]" "$tmpl_ci" \
  "FC-D02 unknown"
# ci / floor-check passes --caller-from-checkout: it reads the pull request's
# own ci.yml, so a pull request that repairs a broken default branch can merge,
# and one that keeps the call but weakens it fails before the merge.
from_checkout() { # <description> <default-branch ci.yml> <checkout ci.yml> <`<id> <state>` expected>
  local f="$capi/repos/o/r/contents/.github/workflows/ci.yml.json"; contents "$2" > "$f"
  local copy="$work/caller"; rm -rf "$copy"; cp -R "$good" "$copy"; printf '%s' "$3" > "$copy/.github/workflows/ci.yml"
  local out; out="$(FLOOR_CHECK_API_DIR="$capi" python3 "$checker" --root "$copy" --archetype cli --repo o/r --caller-from-checkout 2>&1)"
  if reports "$out" "$4"; then ok "$1"; else bad "$1 (expected $4)"; printf '%s\n' "$out" | grep -iE 'ci job|ci\.yml' | sed 's/^/        /'; fi
}
tag_ci="$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@v1.0.0\n')"
from_checkout "--caller-from-checkout: a pull request repairing a broken default branch passes (no deadlock)" "$tag_ci" "$tmpl_ci" \
  "FC-D02 pass"
from_checkout "--caller-from-checkout: a pull request weakening the call fails before the merge" "$tmpl_ci" "$tag_ci" \
  "FC-D02 fail"
own="$(cat "$root/.github/workflows/ci.yml")"
from_api "coolbress/plinth's own ci.yml passes for coolbress/plinth" "$own" "$own" \
  "FC-D02 pass" coolbress/plinth
from_api "another local workflow is a FAIL even for coolbress/plinth" \
  "$(printf 'jobs:\n  ci:\n    uses: ./.github/workflows/no-checks.yml\n')" "$own" \
  "FC-D02 fail" coolbress/plinth
from_api "the same file under any other --repo is a FAIL" "$own" "$own" \
  "FC-D02 fail"

echo "-- a GitLab checkout is read as one (#543)"
# The good backend fixture as plinth-template v1.13.0 renders it for
# host: gitlab: no .github/, glab's denies, .gitlab/ templates, the include.
glgood="$work/glgood"; rm -rf "$glgood"; cp -R "$good" "$glgood"; rm -rf "$glgood/.git" "$glgood/.github"
mkdir -p "$glgood/.gitlab/issue_templates" "$glgood/.gitlab/merge_request_templates"
for f in Bug:bug Feature:enhancement Task:task; do printf '## What\n\n/label ~%s\n' "${f#*:}" > "$glgood/.gitlab/issue_templates/${f%%:*}.md"; done
printf '## What and why\n' > "$glgood/.gitlab/merge_request_templates/Default.md"
cat > "$glgood/.claude/settings.json" <<'JSON'
{"permissions":{"deny":["Bash(git push --force:*)","Bash(git push -f:*)","Bash(git push *--force*)","Bash(git push * -f)","Bash(git push * -f *)","Bash(git push *+*)","Bash(git * push *--force*)","Bash(git * push -f)","Bash(git * push -f *)","Bash(git * push * -f)","Bash(git * push * -f *)","Bash(git * push *+*)","Bash(rm -rf:*)","Bash(glab auth status --show-token*)","Bash(glab auth status -t*)","Bash(glab config get token*)","Read(./.env)","Bash(. *.env*)","Bash(source *.env*)","Bash(cat *.env)","Bash(grep *.env)","Read(~/.config/glab-cli/**)"]}}
JSON
printf 'archetype: backend\nhost: gitlab\n_src_path: gh:coolbress/plinth-template\n_commit: %s\n' "$target_ref" > "$glgood/.copier-answers.yml"
glsha=0123456789abcdef0123456789abcdef01234567
glurl="https://raw.githubusercontent.com/coolbress/plinth/$glsha/gitlab/python-ci.yml"
glci() { # <include lines> -- a .gitlab-ci.yml with these include lines and the docker-image job
  printf '%s\n' "$1"
  printf '\ndocker-image:\n  stage: test\n  script:\n    - |\n      docker build -t image-under-test .\n      out="$(docker run --rm image-under-test)"\n'
}
glci "$(printf 'include:\n  - remote: %s\n    integrity: sha256-L3/GAoKaw0Arw6hDCKeKQlV1QPEgHYxGBHsH4zG1IY8=' "$glurl")" > "$glgood/.gitlab-ci.yml"
git -C "$glgood" init -q 2>/dev/null && git -C "$glgood" add -A
mkdir -p "$work/noapi"; tag_names "$work/noapi" "$target_sha"
gl() { # <description> <shell to change the copy> <ERE one output line must match> [checker args...]
  local desc="$1" edit="$2" want="$3"; shift 3
  local copy="$work/glcase"; rm -rf "$copy"; cp -R "$glgood" "$copy"
  ( cd "$copy" && eval "$edit" )
  out="$(FLOOR_CHECK_API_DIR="$work/noapi" python3 "$checker" --root "$copy" "$@" 2>&1)"; rc=$?
  if sees "$out" "$want" -E -- "$want"; then ok "$desc"; else bad "$desc (expected a line matching '$want')"; printf '%s\n' "$out" | grep -E 'FAIL|WARN|SKIP|gitlab' | sed 's/^/        /'; fi
}
# host: github is today's reading, line for line.
hgh="$work/hostgithub"; rm -rf "$hgh"; cp -R "$good" "$hgh"; printf 'host: github\n' >> "$hgh/.copier-answers.yml"
if [ "$(python3 "$checker" --root "$good" --no-network 2>&1 | sed 1d)" = "$(python3 "$checker" --root "$hgh" --no-network 2>&1 | sed 1d)" ]
then ok "host: github reports exactly what no host reports"
else bad "host: github changed the report"; diff <(python3 "$checker" --root "$good" --no-network 2>&1 | sed 1d) <(python3 "$checker" --root "$hgh" --no-network 2>&1 | sed 1d) | sed 's/^/        /'; fi
gl "a complete GitLab backend checkout has no FAIL offline" ":" "^-- 0 failed, [12] not verified$" --no-network
for gone in 'gh auth token' 'gh config reads' '\.github/dependabot\.yml' 'issue forms' 'the ci job'; do
  grep -qE -- "$gone" <<<"$out" && bad "GitHub-only item not read on GitLab: $gone" || ok "GitHub-only item not read on GitLab: $gone"
done
gl "Dependabot's absence is an INFO, not a FAIL" ":" "FC-A19 info" --no-network
# Offline, the rule runs only with a PyYAML already here; without one, nothing is installed.
if python3 -c 'import yaml' 2>/dev/null; then
  gl "--no-network with PyYAML here: the include is read" ":" "PASS  \.gitlab-ci\.yml includes plinth's GitLab pipeline at a full commit SHA" --no-network
else
  gl "--no-network without PyYAML: the include is a SKIP, not a pass" ":" "FC-D08 unknown" --no-network
fi
gl "the host comes from .copier-answers.yml" ":" "host=gitlab" --no-network
gl "--host gitlab reads it without the answer" "sed -i.bak '/^host:/d' .copier-answers.yml" "^-- 0 failed" --no-network --host gitlab
gl "--host github overrides the answer" ":" "FC-A18 fail" --no-network --host github
gl "an unknown host in the answers is a SKIP, read as github" "sed -i.bak 's/^host: gitlab/host: bitbucket/' .copier-answers.yml" "FC-F07 unknown" --no-network
for d in 'glab auth status --show-token' 'glab auth status -t' 'glab config get token' 'glab-cli'; do
  case "$d" in glab-cli) what="glab config reads" ;; *) what="$d" ;; esac
  case "$d" in *show-token) id=FC-B12 ;; *-t) id=FC-B13 ;; *get\ token) id=FC-B14 ;; *) id=FC-B15 ;; esac
  gl "a deny list without $what fails" "python3 -c 'import json,sys; p=\".claude/settings.json\"; j=json.load(open(p)); j[\"permissions\"][\"deny\"]=[x for x in j[\"permissions\"][\"deny\"] if sys.argv[1] not in x]; json.dump(j,open(p,\"w\"))' '$d'" \
    "$id fail" --no-network
done
gl "no SECURITY.md fails on GitLab, with no inheritance to look for" "rm SECURITY.md" "FC-A09 fail" --no-network
gl "no issue template fails" "rm -r .gitlab/issue_templates" "FC-A20 fail" --no-network
gl "no merge request template fails" "rm -r .gitlab/merge_request_templates" "FC-A21 fail" --no-network
gl "an issue template without /label is a WARN" "printf '## What\n' > .gitlab/issue_templates/Bug.md" "FC-A22 warn" --no-network
gl "a backend without the docker-image job fails" "printf 'include: []\n' > .gitlab-ci.yml" "FC-D07 fail" --no-network
# The include rule is gitlab/python-ci.yml's own; these read it through the
# checker. With no PyYAML here, the job's pinned PyYAML is installed from
# PyPI, so these need the network, as tests/gitlab-ci-cases.sh does. A
# python3 with neither PyYAML nor a version those wheels cover gets a SKIP
# that says so, and the rule's cases cannot run on it.
if ! python3 -c 'import yaml' 2>/dev/null && ! python3 -c 'import sys; sys.exit(not (3, 11) <= sys.version_info[:2] <= (3, 14))'; then
  gl "no PyYAML on a python3 outside 3.11 to 3.14: a SKIP naming the range" ":" "SKIP  .*pinned for CPython 3\.11 to 3\.14 only"
  echo "  NOTE  the include rule's cases need a python3 with PyYAML, or 3.11 to 3.14: $(python3 --version 2>&1)"
else
gl "an include at a full SHA with a checksum passes" ":" "FC-D08 pass"
is "$out" FC-D08 pass && ok "the checksum is a PASS" || bad "the checksum is a PASS"
gl "no checksum is a SKIP, not a pass" "glci 'include:
  - remote: $glurl' > .gitlab-ci.yml" "FC-D08 unknown"
gl "an include at a tag fails" "glci 'include:
  - remote: https://raw.githubusercontent.com/coolbress/plinth/v1.16.0/gitlab/python-ci.yml' > .gitlab-ci.yml" \
  "FC-D08 fail"
gl "plinth by another URL fails" "glci 'include:
  - remote: https://github.com/coolbress/plinth/raw/$glsha/gitlab/python-ci.yml' > .gitlab-ci.yml" \
  "FC-D08 fail"
gl "no include fails" "glci 'include: []' > .gitlab-ci.yml" "FC-D08 fail"
gl "a yaml.py in the checkout is not imported in place of PyYAML" "printf 'print(\"pass: PLANTED\")\n' > yaml.py" \
  "FC-D08 pass"
grep -q PLANTED <<<"$out" && bad "the planted yaml.py ran" || ok "the planted yaml.py did not run"
fi

echo "-- --credentials on a GitLab checkout reads gitlab.com (#547 review)"
glc="$work/glcred"; mkdir -p "$glc/bin" "$glc/home"; ln -s ../gitconfig "$glc/home/.gitconfig"
glcred() { # extra env assignments as arguments; sets out
  out="$(env -u GITLAB_TOKEN -u GITLAB_ACCESS_TOKEN -u OAUTH_TOKEN -u GLAB_CONFIG_DIR -u GH_TOKEN -u GITHUB_TOKEN -u GIT_CONFIG \
    -u GH_CONFIG_DIR -u XDG_CONFIG_HOME -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_SYSTEM -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS \
    HOME="$glc/home" GIT_CONFIG_NOSYSTEM=1 "$@" python3 "$checker" --root "$glgood" --no-network --credentials 2>&1)"
}
printf '[credential "https://gitlab.com"]\n\thelper =\n\thelper = !glab auth git-credential\n[credential "https://github.com"]\n\thelper = osxkeychain\n' > "$glc/gitconfig"
printf 'machine github.com login me password x\n' > "$glc/home/.netrc"
glcred
has "only glab's helper for gitlab.com: an INFO, not a PASS" "FC-G07 info"
has "a github.com login in ~/.netrc is not gitlab.com's" "FC-G09 info"
has "the login glab stores is a SKIP" "FC-G06 unknown"
has "glab's token scopes are a SKIP (#986)" "FC-G03 unknown"
lacks "no gh scopes line on GitLab" "gh login"
has "SSH points at GitLab's keys" "FC-G10 unknown"
lacks "a helper for github.com alone is not reported on GitLab" "WARN"
lacks "gh is not asked about on GitLab" "gh stores|accounts stored in gh"
glcred GITLAB_TOKEN=x
has "GITLAB_TOKEN set is a WARN" "FC-G04 warn"
glcred GLAB_CONFIG_DIR=/elsewhere
has "GLAB_CONFIG_DIR set is a SKIP" "FC-G05 unknown"
printf '[credential]\n\thelper = osxkeychain\n[credential "https://gitlab.com"]\n\thelper = !glab auth git-credential\n' > "$glc/gitconfig"
glcred
has "another helper that applies to gitlab.com is a WARN" "FC-G07 warn"
printf 'machine gitlab.com login me password x\n' > "$glc/home/.netrc"
glcred
has "a gitlab.com login in ~/.netrc is a WARN" "FC-G09 warn"

echo "-- the update line on GitLab carries the include's checksum (#547 review)"
# The include's pin is the one the target tag was tested with: no hold (#1183).
glapi="$work/noapi-gl"; rm -rf "$glapi"; cp -R "$work/noapi" "$glapi"; tested_is "$glapi" "$glsha"
glold="$work/glold"; rm -rf "$glold"; cp -R "$glgood" "$glold"
sed -i.bak 's/^_commit: .*/_commit: v1.0.0/' "$glold/.copier-answers.yml"
glint="L3/GAoKaw0Arw6hDCKeKQlV1QPEgHYxGBHsH4zG1IY8="
printed="$(FLOOR_CHECK_API_DIR="$glapi" python3 "$checker" --root "$glold" --print-update-command 2>&1)"; rc=$?
case "$printed" in *"--data plinth_sha=$glsha --data plinth_gitlab_integrity=$glint") [ "$rc" = 0 ] && ok "the live pin and its checksum from .gitlab-ci.yml" || bad "update line rc=$rc" ;;
  *) bad "the GitLab update line: '$printed'" ;; esac
glci "include:
  - remote: $glurl" > "$glold/.gitlab-ci.yml"
printed="$(FLOOR_CHECK_API_DIR="$glapi" python3 "$checker" --root "$glold" --print-update-command 2>&1)"; rc=$?
[ "$rc" = 1 ] && grep -q "not one \`remote:\` line followed by its \`integrity:\` line" <<<"$printed" \
  && ok "an include without a checksum gives no update line, saying why" || bad "no checksum: rc=$rc '$printed'"
glci "include:
  - remote: https://raw.githubusercontent.com/coolbress/plinth/v1.16.0/gitlab/python-ci.yml
    integrity: sha256-$glint" > "$glold/.gitlab-ci.yml"
printed="$(FLOOR_CHECK_API_DIR="$glapi" python3 "$checker" --root "$glold" --print-update-command 2>&1)"; rc=$?
[ "$rc" = 1 ] && grep -q "is at v1.16.0, not a full commit SHA" <<<"$printed" && ok "an include at a tag gives no update line" || bad "tag: rc=$rc '$printed'"
cp "$glgood/.gitlab-ci.yml" "$glold/.gitlab-ci.yml"
sed -i.bak '/^host:/d' "$glold/.copier-answers.yml"
printed="$(FLOOR_CHECK_API_DIR="$glapi" python3 "$checker" --root "$glold" --host gitlab --print-update-command 2>&1)"; rc=$?
case "$printed" in *"--data plinth_gitlab_integrity=$glint") [ "$rc" = 0 ] && ok "--host gitlab without the answer: the update line reads the include" || bad "--host gitlab update rc=$rc" ;;
  *) bad "--host gitlab without the answer: '$printed'" ;; esac
out="$(FLOOR_CHECK_API_DIR="$glapi" python3 "$checker" --root "$glold" --host gitlab --no-network 2>&1)"
has "--host gitlab without the answer: the drift item carries the GitLab line" "INFO    uvx .*--data plinth_gitlab_integrity=$glint"
printf 'host: gitlab\n' >> "$glold/.copier-answers.yml"
glpin_api() { # <plinth_gitlab_integrity default or "-"> → $work/api-glpin, the tested pin ahead of the live one
  local d="$work/api-glpin"; rm -rf "$d"; mkdir -p "$d/repos/coolbress/plinth-template/contents" "$d/repos/coolbress/plinth/compare"
  { printf 'plinth_sha:\n  type: str\n  default: "%s"\n' "$tested"
    [ "$1" = - ] || printf 'plinth_gitlab_integrity:\n  type: str\n  default: "%s"\n' "$1"; } \
    | base64 | tr -d '\n' | jq -R '{encoding: "base64", content: .}' > "$d/repos/coolbress/plinth-template/contents/copier.yml?ref=$target_sha.json"
  jq -n '{status: "ahead", ahead_by: 2, behind_by: 0}' > "$d/repos/coolbress/plinth/compare/$glsha...$tested.json"
  printf '[]' > "$d/repos/coolbress/plinth/tags?per_page=100.json"
  tag_names "$d" "$target_sha"
}
newint="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
glpin_api "$newint"
printed="$(FLOOR_CHECK_API_DIR="$work/api-glpin" python3 "$checker" --root "$glold" --print-update-command 2>"$work/glpin-err")"; rc=$?
[ "$rc" = 1 ] && [ -z "$printed" ] \
  && grep -q "^raise it first in one merge request of its own: .gitlab-ci.yml's coolbress/plinth include to ref $tested and integrity $newint; merge it, then plan the update again\$" "$work/glpin-err" \
  && ! grep -q "open pull requests" "$work/glpin-err" \
  && ok "the include behind the tested pin: no line, and the change names the ref and the checksum that tag was tested with (#1183)" \
  || { bad "the GitLab raise: rc=$rc '$printed'"; sed 's/^/        /' "$work/glpin-err"; }
grep -q "the plinth pin is behind; the include is at $glsha" "$work/glpin-err" && ok "the note says the include, not the workflows" || { bad "the GitLab note"; sed 's/^/        /' "$work/glpin-err"; }
glpin_api -
printed="$(FLOOR_CHECK_API_DIR="$work/api-glpin" python3 "$checker" --root "$glold" --print-update-command 2>"$work/glpin-err")"; rc=$?
[ "$rc" = 1 ] && [ -z "$printed" ] && grep -q "its checksum was not read" "$work/glpin-err" && grep -q "integrity (the checksum the tag was tested with, not read)" "$work/glpin-err" \
  && ok "no tested checksum: still no line, and the change says the checksum was not read" || { bad "tested without checksum: rc=$rc '$printed'"; sed 's/^/        /' "$work/glpin-err"; }

echo "-- a GitLab project's wall, read through glab (#544)"
# Fixtures laid out like gitlab.com/api/v4 paths, as the probe project
# answered them (measured 2026-10-15): o/r is protected and merges as the door set it.
glwall_api() { # -- writes the passing set to $work/glapi
  local d="$work/glapi" p="projects/o%2Fr"; rm -rf "$d"; mkdir -p "$d/$p/protected_branches" "$d/$p/repository/files/.gitlab-ci.yml"
  printf '{"default_branch":"main","only_allow_merge_if_pipeline_succeeds":true,"allow_merge_on_skipped_pipeline":false,"squash_option":"always","merge_method":"ff","ci_config_path":""}' > "$d/$p.json"
  printf '[{"name":"main","push_access_levels":[{"access_level":0,"access_level_description":"No one","deploy_key_id":null,"user_id":null,"group_id":null}],"merge_access_levels":[{"access_level":40,"access_level_description":"Maintainers","user_id":null,"group_id":null}],"allow_force_push":false}]' > "$d/$p/protected_branches?per_page=100.json"
  cp "$glgood/.gitlab-ci.yml" "$d/$p/repository/files/.gitlab-ci.yml/raw?ref=main"
  python3 -c 'import json,sys; print(json.dumps([{"name": l.split("|")[0]} for l in open(sys.argv[1]) if l.strip() and not l.lstrip().startswith("#")]))' "$root/labels.txt" > "$d/$p/labels?per_page=100.json"
}
glw() { # <description> <shell run in $work/glapi/projects/o%2Fr> <ERE one output line must match>
  glwall_api; ( cd "$work/glapi/projects/o%2Fr" && eval "$2" )
  out="$(FLOOR_CHECK_API_DIR="$work/noapi" FLOOR_CHECK_GITLAB_API_DIR="$work/glapi" python3 "$checker" --root "$glgood" --repo o/r 2>&1)"; rc=$?
  if sees "$out" "$3" -E -- "$3"; then ok "$1"; else bad "$1 (expected a line matching '$3')"; printf '%s\n' "$out" | grep -vE '^  PASS  ' | sed 's/^/        /'; fi
}
setp() { python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); (d[0] if isinstance(d, list) else d).update(json.loads(sys.argv[2])); json.dump(d,open(p,"w"))' "$@"; }
addrule() { python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d.append(json.loads(sys.argv[2])); json.dump(d,open(p,"w"))' "$@"; }
pb="protected_branches?per_page=100.json"
glw "the door's wall passes, with nothing unverified" ":" "^-- 0 failed, 0 not verified$"
# main protected, merge on a green pipeline, squash and fast-forward, the include's pin, the labels
for line in "FC-E01 pass" "FC-E02 pass" "FC-E03 pass" "FC-D08 pass" "FC-E05 pass"; do
  reports "$out" "$line" && ok "the passing wall: $line" || bad "the passing wall: missing $line"
done
glw "an unprotected default branch fails, with the call that protects it" "printf [] > 'protected_branches?per_page=100.json'" "FC-E01 fail"
is "$out" FC-E01 info \
  && ok "the unprotected branch names the POST" || bad "the unprotected branch names the POST"
glw "Developers allowed to push fails" "setp \"\$pb\" '{\"push_access_levels\":[{\"access_level\":30,\"access_level_description\":\"Developers + Maintainers\"}]}'" "FC-E01 fail"
glw "a user allowed to push fails" "setp \"\$pb\" '{\"push_access_levels\":[{\"access_level\":0},{\"access_level\":40,\"user_id\":7}]}'" "FC-E01 fail"
glw "Developers allowed to merge fails" "setp \"\$pb\" '{\"merge_access_levels\":[{\"access_level\":30,\"access_level_description\":\"Developers + Maintainers\"}]}'" "FC-E01 fail"
glw "a wildcard rule that lets Developers push opens main: FAIL" "addrule \"\$pb\" '{\"name\":\"*\",\"push_access_levels\":[{\"access_level\":30,\"access_level_description\":\"Developers + Maintainers\"}],\"merge_access_levels\":[{\"access_level\":40}],\"allow_force_push\":false}'" \
  "FC-E01 fail"
glw "a wildcard rule with force push opens main: FAIL" "addrule \"\$pb\" '{\"name\":\"ma*\",\"push_access_levels\":[{\"access_level\":0}],\"merge_access_levels\":[{\"access_level\":40}],\"allow_force_push\":true}'" \
  "FC-E01 fail"
glw "a rule for other branches does not apply" "addrule \"\$pb\" '{\"name\":\"release/*\",\"push_access_levels\":[{\"access_level\":30}],\"merge_access_levels\":[{\"access_level\":30}],\"allow_force_push\":true}'" \
  "FC-E01 pass"
glw "a wildcard rule alone protects main" "printf '[{\"name\":\"*\",\"push_access_levels\":[{\"access_level\":0}],\"merge_access_levels\":[{\"access_level\":40}],\"allow_force_push\":false}]' > \"\$pb\"" \
  "FC-E01 pass"
glw "force push allowed fails" "setp \"\$pb\" '{\"allow_force_push\":true}'" "FC-E01 fail"
glw "an unreadable protection is a SKIP" "rm \"\$pb\"; : > 'protected_branches?per_page=100.error'" "FC-E01 unknown"
glw "pipelines need not succeed: FAIL" "setp ../o%2Fr.json '{\"only_allow_merge_if_pipeline_succeeds\":false}'" "FC-E02 fail"
glw "skipped pipelines counted: FAIL" "setp ../o%2Fr.json '{\"allow_merge_on_skipped_pipeline\":true}'" "FC-E02 fail"
glw "squash not required: FAIL" "setp ../o%2Fr.json '{\"squash_option\":\"default_on\"}'" "FC-E03 fail"
glw "a merge commit method: FAIL" "setp ../o%2Fr.json '{\"merge_method\":\"merge\"}'" "FC-E03 fail"
glw "merge settings not returned are a SKIP" "python3 -c 'import json; p=\"../o%2Fr.json\"; d=json.load(open(p)); [d.pop(k) for k in (\"squash_option\",\"merge_method\")]; json.dump(d,open(p,\"w\"))'" "FC-E03 unknown"
is "$out" FC-E02 pass && ok "the merge checks returned are still judged" || bad "the merge checks returned are still judged"
glw "pipeline settings not returned are a SKIP" "python3 -c 'import json; p=\"../o%2Fr.json\"; d=json.load(open(p)); [d.pop(k) for k in (\"only_allow_merge_if_pipeline_succeeds\",\"allow_merge_on_skipped_pipeline\")]; json.dump(d,open(p,\"w\"))'" "FC-E02 unknown"
glw "a readable mismatch fails beside a missing field" "python3 -c 'import json; p=\"../o%2Fr.json\"; d=json.load(open(p)); d.pop(\"squash_option\"); d[\"only_allow_merge_if_pipeline_succeeds\"]=False; d[\"merge_method\"]=\"merge\"; json.dump(d,open(p,\"w\"))'" \
  "FC-E02 fail"
is "$out" FC-E03 fail && is "$out" FC-E03 unknown \
  && ok "the readable merge method fails and only the missing squash option is a SKIP" || { bad "partial merge shape"; printf '%s\n' "$out" | grep -E 'FAIL|SKIP' | sed 's/^/        /'; }
glw "an unreadable project is a SKIP, and the checkout's include is read" "rm ../o%2Fr.json" "FC-E01 unknown"
is "$out" FC-D08 pass && ok "the checkout's include stands in" || bad "the checkout's include stands in"
glw "the include on the default branch is read, not the checkout's" "glci 'include:
  - remote: https://raw.githubusercontent.com/coolbress/plinth/main/gitlab/python-ci.yml' > 'repository/files/.gitlab-ci.yml/raw?ref=main'" \
  "FC-D08 fail"
glw "no definition on the default branch fails" "rm 'repository/files/.gitlab-ci.yml/raw?ref=main'" "FC-E04 fail"
glw "ci_config_path is the definition read" "setp ../o%2Fr.json '{\"ci_config_path\":\"ci/main.yml\"}'; mkdir -p repository/files/ci%2Fmain.yml; cp 'repository/files/.gitlab-ci.yml/raw?ref=main' 'repository/files/ci%2Fmain.yml/raw?ref=main'" \
  "FC-D08 pass"
glw "a definition in another project is a SKIP" "setp ../o%2Fr.json '{\"ci_config_path\":\".gitlab-ci.yml@g/other\"}'" "FC-E04 unknown"
glw "a missing label is a WARN with glab's command" "printf '[]' > 'labels?per_page=100.json'" "FC-E05 warn"
is "$out" FC-E05 info && ok "the missing label names glab label create" || bad "the missing label names glab label create"
glw "unreadable labels are a SKIP" "rm 'labels?per_page=100.json'; : > 'labels?per_page=100.error'" "FC-E05 unknown"
out="$(FLOOR_CHECK_API_DIR="$work/noapi" FLOOR_CHECK_GITLAB_API_DIR="$work/glapi" python3 "$checker" --root "$glgood" --repo o/r --no-network 2>&1)"
is "$out" FC-E01 unknown && ok "--no-network with --repo: the wall is a SKIP" || bad "--no-network with --repo: the wall is a SKIP"

echo "-- a JavaScript or TypeScript repository (#681)"
# What must not change comes first: a repository with pyproject.toml, with or
# without package.json beside it, or with neither, reads exactly as before.
# Each run's own path is the only difference allowed between two outputs.
js_run() { # <dir> [checker args...] -- sets out, rc; the dir's path replaced by ROOT
  local d="$1"; shift
  out="$(python3 "$checker" --root "$d" "$@" 2>&1)"; rc=$?
  out="${out//"$(cd "$d" && pwd -P)"/ROOT}"
}
js_new='N/A|does not apply|do not apply|JavaScript|TypeScript|bun\.lock|dependency review'
py="$work/js-py"; rm -rf "$py"; cp -R "$good" "$py"
js_run "$py" --no-network; py_out="$out"; py_rc=$rc
lacks "Python only: no line of #681's" "$js_new"
both="$work/js-both"; rm -rf "$both"; cp -R "$good" "$both"
# Left untracked: the dotenv item counts tracked files, and these are read from disk.
printf '{"name":"web","private":true}\n' > "$both/package.json"; printf '{}\n' > "$both/package-lock.json"; : > "$both/bun.lock"
js_run "$both" --no-network
if [ "$out" = "$py_out" ] && [ "$rc" = "$py_rc" ]; then ok "pyproject.toml and package.json: the same output as Python only"
else bad "pyproject.toml and package.json changed the output"; diff <(printf '%s\n' "$py_out") <(printf '%s\n' "$out") | sed 's/^/        /'; fi
neither="$work/js-neither"; rm -rf "$neither"; cp -R "$good" "$neither"; rm "$neither/pyproject.toml" "$neither/uv.lock"
js_run "$neither" --no-network
lacks "neither file: no line of #681's" "$js_new"
is "$out" FC-C01 fail && is "$out" FC-C02 fail \
  && ok "neither file: pyproject.toml and uv.lock still fail" || bad "neither file: pyproject.toml and uv.lock still fail"
# A Python project one level down is the case --project names (#221), even
# with a package.json at the root: that hint stands, nothing does not apply.
below="$work/js-below"; rm -rf "$below"; cp -R "$neither" "$below"; mkdir "$below/api"
printf '[project]\nname = "api"\n' > "$below/api/pyproject.toml"; printf '{}\n' > "$below/package.json"
js_run "$below" --no-network
lacks "package.json at the root, pyproject.toml one level down: no line of #681's" "$js_new"
is "$out" FC-C01 fail \
  && ok "package.json at the root, pyproject.toml one level down: the --project hint stands" || bad "the --project hint stands"
# A GitLab checkout is read as before: #681 covers GitHub only.
gljs="$work/js-gitlab"; rm -rf "$gljs"; cp -R "$neither" "$gljs"; printf '{}\n' > "$gljs/package.json"
js_run "$gljs" --no-network --host gitlab
lacks "package.json on a GitLab checkout: no line of #681's" "$js_new"
# The wall of a Python repository with package.json beside it: the same lines.
js_wall() { # <dir> [extra args] -- the fixture API's wall, with the door's ruleset
  local d="$1"; shift
  out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$d" --no-network --repo o/r --ruleset "$root/ruleset.json" "$@" 2>&1)"; rc=$?
  out="${out//"$(cd "$d" && pwd -P)"/ROOT}"
}
js_wall "$py"; pyw_out="$out"
js_wall "$both"
[ "$out" = "$pyw_out" ] && ok "pyproject.toml and package.json: the wall reads as for Python only" \
  || { bad "pyproject.toml and package.json changed the wall"; diff <(printf '%s\n' "$pyw_out") <(printf '%s\n' "$out") | sed 's/^/        /'; }
is "$out" FC-E19 fail && ok "Python with package.json: the ruleset's Python checks are still expected" \
  || bad "Python with package.json: the ruleset's Python checks are still expected"

# Now what is shown: package.json and no pyproject.toml.
js="$work/js"; rm -rf "$js"; cp -R "$neither" "$js"
rm -f "$js/.copier-answers.yml" "$js/Dockerfile" "$js/.dockerignore" "$js/.env.example"; rm -rf "$js/src"
printf '{"name":"web","private":true}\n' > "$js/package.json"; printf '{}\n' > "$js/package-lock.json"
printf '* text=auto eol=lf\n' > "$js/.gitattributes"
git -C "$js" add -A
js_run "$js" --no-network
[ "$(sed -n 2p <<<"$out")" = "  INFO  read as a JavaScript or TypeScript project (package.json here, no pyproject.toml): plinth has no checks for its language, so no lint, typecheck, test or build check; the checks that do not depend on the language still apply: the documents, .claude/settings.json, .gitattributes, Dependabot, tracked .env files, action pins and, with a repository name, the ruleset, push protection and CodeQL" ] \
  && ok "JavaScript only: one plain INFO line right under the header" || { bad "JavaScript only: the INFO line under the header"; sed -n 1,3p <<<"$out" | sed 's/^/        /'; }
# render.yaml does not depend on the language (#811): read here too.
printf 'databases:\n  - name: db\n    plan: free\n' > "$js/render.yaml"; git -C "$js" add -A
js_run "$js" --no-network
is "$out" FC-C16 warn && ok "JavaScript only: render.yaml is read" \
  || { bad "JavaScript only: render.yaml is read"; grep -E 'render' <<<"$out" | sed 's/^/        /'; }
rm "$js/render.yaml"; git -C "$js" add -A; js_run "$js" --no-network
for want in '^  N/A   pyproject.toml does not apply: ' '^  N/A   uv.lock does not apply: ' \
            '^  N/A   the ci job.s call to coolbress/plinth/.github/workflows/python-ci.yml does not apply: ' \
            '^  N/A   the container image, .env.example and JSON logs items: does not apply: '; do
  [ "$(grep -cE -- "$want" <<<"$out")" = 1 ] && ok "JavaScript only: one line matches $want" || bad "JavaScript only: one line matches $want"
done
lacks "JavaScript only: no FAIL, WARN or SKIP names pyproject.toml, uv.lock, python-ci.yml or the archetype" \
  '^  (FAIL|WARN|SKIP) .*(pyproject|uv\.lock|python-ci|archetype)'
grep -q -- '^-- 0 failed, 2 not verified, 4 do not apply$' <<<"$out" && [ "$rc" = 0 ] \
  && ok "JavaScript only: the summary counts the four apart from failures and not-verified items" \
  || { bad "JavaScript only: summary"; grep -E '^  (FAIL|SKIP)|^--' <<<"$out" | sed 's/^/        /'; }
lacks "JavaScript only with package-lock.json: no Bun line" 'bun\.lock|dependency review'
# Items that do not depend on the language keep their verdicts.
# README.md, the gh auth token deny, .gitattributes, dependabot.yml, no tracked dotenv file, relative links
for want in 'FC-A02 pass' 'FC-B05 pass' 'FC-A24 pass' 'FC-A18 pass' 'FC-A28 pass' 'FC-A27 pass'; do
  reports "$out" "$want" && ok "JavaScript only: $want" || bad "JavaScript only: expected '$want'"
done
jsb="$work/js-broken"; rm -rf "$jsb"; cp -R "$js" "$jsb"; rm "$jsb/AGENTS.md" "$jsb/.claude/settings.json"; printf '' > "$jsb/.gitattributes"
printf 'jobs:\n  t:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v4\n' > "$jsb/.github/workflows/build.yml"
printf 'X=1\n' > "$jsb/.env"; git -C "$jsb" add -A; git -C "$jsb" add -f .env
js_run "$jsb" --no-network
# AGENTS.md, .claude/settings.json, .gitattributes, the tracked .env, the unpinned actions/checkout@v4
for want in 'FC-A04 fail' 'FC-B01 fail' 'FC-A24 fail' 'FC-A28 warn' 'FC-D01 warn'; do
  reports "$out" "$want" && ok "JavaScript only, broken: $want" || bad "JavaScript only, broken: expected '$want'"
done
grep -q -- '^-- 3 failed, 2 not verified, 4 do not apply$' <<<"$out" && [ "$rc" = 1 ] \
  && ok "JavaScript only, broken: the failures still fail the run" || { bad "JavaScript only, broken: summary"; grep -E '^  FAIL|^--' <<<"$out" | sed 's/^/        /'; }
# Bun's lockfile is the only one: GitHub's dependency review does not read it.
for lock in bun.lock bun.lockb; do
  bun="$work/js-bun"; rm -rf "$bun"; cp -R "$js" "$bun"; rm "$bun/package-lock.json"; : > "$bun/$lock"
  js_run "$bun" --no-network
  [ "$(grep -cE "^  INFO  $lock is the only lockfile here: GitHub's dependency review does not read it, so a vulnerable dependency is not reported before a merge" <<<"$out")" = 1 ] \
    && ok "only $lock: one INFO line on dependency review" || bad "only $lock: one INFO line on dependency review"
  grep -q -- '^-- 0 failed, 2 not verified, 4 do not apply$' <<<"$out" && ok "only $lock: the counts do not move" || bad "only $lock: the counts do not move"
done
for other in package-lock.json yarn.lock pnpm-lock.yaml npm-shrinkwrap.json; do
  bun="$work/js-bun"; rm -rf "$bun"; cp -R "$js" "$bun"; rm "$bun/package-lock.json"; : > "$bun/bun.lock"; : > "$bun/$other"
  js_run "$bun" --no-network
  lacks "bun.lock beside $other: no Bun line" 'dependency review'
done
# A JavaScript project one directory down is read as one with --project, and
# the root without it holds neither file, as before.
mono="$work/js-mono"; rm -rf "$mono"; cp -R "$js" "$mono"; mkdir "$mono/web"; mv "$mono/package.json" "$mono/package-lock.json" "$mono/web/"
js_run "$mono" --no-network --project web
is "$out" FC-C05 not_applicable && grep -q -- ', 4 do not apply$' <<<"$out" \
  && ok "package.json one directory down, --project names it: read as JavaScript" || bad "--project web: read as JavaScript"
js_run "$mono" --no-network
is "$out" FC-C01 fail && ! grep -qE "$js_new" <<<"$out" \
  && ok "package.json one directory down, no --project: the root reads as before" || bad "no --project: the root reads as before"
# The wall: the ruleset's Python-only required checks do not apply; every
# other rule, push protection and CodeQL are judged as before.
js_wall "$js"
is "$out" FC-E19 not_applicable \
  && ok "JavaScript only, wall: the Python-only required checks do not apply, named" || bad "JavaScript only, wall: the required checks line"
lacks "JavaScript only, wall: no required-checks verdict" 'required checks (dropped|are|come)|required_status_checks rule|expected checks'
is "$out" FC-D02 not_applicable \
  && ok "JavaScript only, wall: the ci job is not read from the default branch either" || bad "JavaScript only, wall: the ci job line"
# the deletion rule, merge methods, no bypass actors, push protection, CodeQL enforced, squash commit messages
for want in 'FC-E13 pass' 'FC-E17 pass' 'FC-E24 pass' 'FC-E09 pass' 'FC-E21 pass' 'FC-E08 pass'; do
  reports "$out" "$want" && ok "JavaScript only, wall: $want" || bad "JavaScript only, wall: expected '$want'"
done
grep -qE -- '^-- 0 failed, [0-9]+ not verified, 5 do not apply$' <<<"$out" && ok "JavaScript only, wall: five items do not apply" \
  || { bad "JavaScript only, wall: summary"; grep -E '^  (FAIL|N/A)|^--' <<<"$out" | sed 's/^/        /'; }
# CodeQL's default setup is asked for the repository's language (#681 review):
# Python alone leaves the JavaScript unscanned, and the fix names its language.
is "$out" FC-E23 warn \
  && is "$out" FC-E23 info \
  && ok "JavaScript only, wall: CodeQL analysing Python alone is a WARN with the JavaScript fix" || bad "JavaScript only, wall: CodeQL languages WARN"
for l in javascript-typescript javascript typescript; do
  printf '{"state":"configured","languages":["actions","%s"],"query_suite":"default"}' "$l" > "$api/repos/o/r/code-scanning/default-setup.json"
  js_wall "$js"
  is "$out" FC-E23 pass && ok "JavaScript only, wall: CodeQL analysing $l passes" || bad "JavaScript only, wall: CodeQL analysing $l passes"
done
js_wall "$py"
is "$out" FC-E23 warn \
  && ok "Python only, wall: CodeQL analysing TypeScript alone still warns about the Python" || bad "Python only, wall: CodeQL languages WARN"
printf '%s' "$good_setup" > "$api/repos/o/r/code-scanning/default-setup.json"
# A rule the wall needs whatever the language still fails when it is gone.
printf '%s' "$good_rules" | jq -c 'map(select(.type != "deletion" and .type != "required_status_checks"))' > "$api/repos/o/r/rules/branches/main.json"
js_wall "$js"
is "$out" FC-E13 fail && ok "JavaScript only, wall: a missing deletion rule still fails" || bad "JavaScript only, wall: deletion rule"
lacks "JavaScript only, wall: no required-checks rule is not a finding" 'required_status_checks'
printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"
# --expect-checks names checks the door's ruleset does not; those are still judged.
js_wall "$js" --expect-checks "ci / lint, CodeQL"
is "$out" FC-E19 not_applicable && is "$out" FC-E19 pass \
  && ok "JavaScript only, wall: a non-Python expected check is still judged" || { bad "JavaScript only, wall: --expect-checks"; grep -E 'N/A|expected checks' <<<"$out" | sed 's/^/        /'; }

echo "-- what the door sets beside the wall, and the project's own answers (#772)"
# The tag ruleset, for a releasing archetype (the fixture is a backend). The
# must-not-pass cases first: a tag ruleset that lets a v* tag move, a
# disabled one, one for other tags, and none.
tagrs="$api/repos/o/r/rulesets/3.json"
wall "must not pass: a tag ruleset with non_fast_forward in place of update is a WARN" \
  "FC-E29 warn" "jq -c '.rules = [{type:\"deletion\"},{type:\"non_fast_forward\"}]' <<<\"\$good_tags\" > \"$tagrs\""
wall "must not pass: a tag ruleset in evaluate mode is a WARN" \
  "FC-E29 warn" "jq -c '.enforcement = \"evaluate\"' <<<\"\$good_tags\" > \"$tagrs\""
wall "must not pass: a tag ruleset for other tags is a WARN" \
  "FC-E29 warn" "jq -c '.conditions.ref_name.include = [\"refs/tags/release-*\"]' <<<\"\$good_tags\" > \"$tagrs\""
wall "must not pass: no tag ruleset is a WARN naming why it matters" \
  "FC-E29 warn" \
  "printf '[{\"id\":1,\"target\":\"branch\"}]' > \"$api/repos/o/r/rulesets?per_page=100.json\""
wall "...with the call that adds the door's one, which needs administration" \
  "FC-E29 info" \
  "printf '[]' > \"$api/repos/o/r/rulesets?per_page=100.json\""
wall "a missing tag ruleset never fails the floor" "-- 0 failed, 1 not verified" "printf '[]' > \"$api/repos/o/r/rulesets?per_page=100.json\""
wall "the door's tag ruleset is a PASS" "FC-E29 pass"
# Codex review on #779: one sample tag is not the namespace, and a bypass
# actor is a way round it. Must-not-pass cases, each a WARN naming the gap.
wall "must not pass: v* with v2* excluded is a WARN" \
  "FC-E29 warn" \
  "jq -c '.conditions.ref_name.exclude = [\"refs/tags/v2*\"]' <<<\"\$good_tags\" > \"$tagrs\""
wall "must not pass: a ruleset for v1.0.0 alone is a WARN" \
  "FC-E29 warn" \
  "jq -c '.conditions.ref_name.include = [\"refs/tags/v1.0.0\"]' <<<\"\$good_tags\" > \"$tagrs\""
wall "must not pass: a write role that always bypasses it is a WARN" \
  "FC-E29 warn" \
  "jq -c '.bypass_actors = [{actor_id: 4, actor_type: \"RepositoryRole\", bypass_mode: \"always\"}]' <<<\"\$good_tags\" > \"$tagrs\""
wall "an exclude that cannot match a v* tag is not a gap" "FC-E29 pass" \
  "jq -c '.conditions.ref_name.exclude = [\"refs/tags/nightly\"]' <<<\"\$good_tags\" > \"$tagrs\""
wall "bypass actors the token does not get are a SKIP, never a PASS" \
  "FC-E29 unknown" "jq -c 'del(.bypass_actors)' <<<\"\$good_tags\" > \"$tagrs\""
wall "...counted as not verified" "-- 0 failed, 2 not verified" "jq -c 'del(.bypass_actors)' <<<\"\$good_tags\" > \"$tagrs\""
out="$(jq -c 'del(.bypass_actors)' <<<"$good_tags" > "$tagrs"; FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --actions-token --expect-checks "ci / a, ci / b" 2>&1)"; printf '%s' "$good_tags" > "$tagrs"
if is "$out" FC-E29 review && ! grep -q "PASS  the tag ruleset" <<<"$out"
then ok "--actions-token: unread tag bypass actors are left to /plinth:floor-check, not passed"; else bad "--actions-token: unread tag bypass actors"; grep 'tag ruleset' <<<"$out" | sed 's/^/        /'; fi
wall "~ALL with deletion and update is a PASS too" "FC-E29 pass" "jq -c '.conditions.ref_name.include = [\"~ALL\"]' <<<\"\$good_tags\" > \"$tagrs\""
wall "a listing that cannot be read is a SKIP, counted" "-- 0 failed, 2 not verified" "printf 'not json' > \"$api/repos/o/r/rulesets?per_page=100.json\""
wall "a listed tag ruleset that cannot be read is a SKIP" "FC-E29 unknown" "rm \"$tagrs\""
# A uv workspace member released on its own tags (#931): each prefix that
# pyproject.toml lists under [tool.plinth.release] own-tags is one more item.
# The door's ruleset covers *-v*; one made before covers v* only.
cp "$good/pyproject.toml" "$work/pyproject.saved"
printf '\n[tool.plinth.release]\nown-tags = { "checker" = "checker-" }\n' >> "$good/pyproject.toml"
wall "the door's tag ruleset covers a listed member's own tags" \
  "FC-E29 pass"
old_tags="jq -c '.conditions.ref_name.include = [\"refs/tags/v*\"]' <<<\"\$good_tags\" > \"$tagrs\""
wall "must not pass: a v*-only tag ruleset leaves a listed prefix open, a WARN" \
  "FC-E29 warn" "$old_tags"
wall "...and its fix adds a ruleset for that prefix alone" \
  "FC-E29 info" "$old_tags"
wall "...while the v* item still passes" "FC-E29 pass" "$old_tags"
wall "...and never fails the floor" "-- 0 failed" "$old_tags"
wall "must not pass: an exclude that can match a listed prefix's tag is a WARN" \
  "FC-E29 warn" \
  "jq -c '.conditions.ref_name.exclude = [\"refs/tags/checker-v0*\"]' <<<\"\$good_tags\" > \"$tagrs\""
wall "must not pass: a sample tag of the prefix is not the prefix" \
  "FC-E29 warn" \
  "jq -c '.conditions.ref_name.include = [\"refs/tags/v*\", \"refs/tags/checker-v1.0.0\"]' <<<\"\$good_tags\" > \"$tagrs\""
wall "an exclude for another prefix is not a gap" "FC-E29 pass" \
  "jq -c '.conditions.ref_name.exclude = [\"refs/tags/other-v*\"]' <<<\"\$good_tags\" > \"$tagrs\""
wall "a second tag ruleset for the prefix alone is a PASS beside the v* one" \
  "FC-E29 pass" \
  "$old_tags; jq -c '.id = 4 | .conditions.ref_name.include = [\"refs/tags/checker-v*\"]' <<<\"\$good_tags\" > \"$api/repos/o/r/rulesets/4.json\"; printf '%s' '[{\"id\":1,\"target\":\"branch\",\"source_type\":\"Repository\"},{\"id\":3,\"target\":\"tag\",\"source_type\":\"Repository\"},{\"id\":4,\"target\":\"tag\",\"source_type\":\"Repository\"}]' > \"$api/repos/o/r/rulesets?per_page=100.json\""
rm -f "$api/repos/o/r/rulesets/4.json"
cp "$work/pyproject.saved" "$good/pyproject.toml"
printf '\n[tool.plinth.release]\nown-tags = { "validator" = "validator-" }\n' >> "$good/pyproject.toml"
wall "a prefix that starts with v is covered by v* alone" "FC-E29 pass" "$old_tags"
cp "$work/pyproject.saved" "$good/pyproject.toml"
printf '\n[tool.plinth]\nrelease.own-tags = { "checker" = "checker-" }\n' >> "$good/pyproject.toml"
wall "must not pass: the list spelled as a dotted key is read too, and a v*-only ruleset leaves it open" \
  "FC-E29 warn" "$old_tags"
cp "$work/pyproject.saved" "$good/pyproject.toml"
printf '\n[tool.plinth.release]\nown-tags = "checker-"\n' >> "$good/pyproject.toml"
wall "an own-tags list that cannot be read is a SKIP, counted" "-- 0 failed, 2 not verified"
wall "...that says what it could not read" "FC-E29 unknown"
cp "$work/pyproject.saved" "$good/pyproject.toml"
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --expect-checks "ci / a, ci / b" 2>&1)"
if [ "$(grep -c 'tag ruleset' <<<"$out")" = 1 ]; then ok "without own-tags, the tag ruleset is one item, as before"
else bad "without own-tags, the tag ruleset is not one item"; grep 'tag ruleset' <<<"$out" | sed 's/^/        /'; fi

# floor-check.py has no file beside it in consumer CI, so the ruleset it
# offers is its own copy: it must be the door's file.
if python3 - "$root" <<'PY'
import json, sys, importlib.util as u
root = sys.argv[1]
s = u.spec_from_file_location("fc", f"{root}/scripts/floor-check.py"); m = u.module_from_spec(s); s.loader.exec_module(m)
sys.exit(0 if m.TAG_RULESET == json.load(open(f"{root}/ruleset-tags.json")) else 1)
PY
then ok "the tag ruleset floor-check offers is ruleset-tags.json"; else bad "floor-check.py's TAG_RULESET differs from ruleset-tags.json"; fi
out="$(printf '[]' > "$api/repos/o/r/rulesets?per_page=100.json"; FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --archetype data-ml --expect-checks "ci / a, ci / b" 2>&1)"; printf '%s' "$good_listing" > "$api/repos/o/r/rulesets?per_page=100.json"
if is "$out" FC-E29 warn; then ok "data-ml, which releases its model from a tag, is held to the tag ruleset"; else bad "data-ml was not judged on a tag ruleset"; fi
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --archetype web --expect-checks "ci / a, ci / b" 2>&1)"
if ! grep -q "tag ruleset" <<<"$out"; then ok "web, which deploys on green, is not held to a tag ruleset"; else bad "web was judged on a tag ruleset"; fi
# The merge ruleset's search for one not in effect skips a tag ruleset, which
# carries update too: before #772's fix this was a false FAIL.
merge_wall "a tag ruleset is not taken for a merge ruleset out of effect" \
  "FC-E25 warn" \
  "printf '%s' \"\$good_rules\" > \"$mapi/repos/o/r/rules/branches/main.json\"; printf '%s' \"\$good_listing\" > \"$mapi/repos/o/r/rulesets?per_page=100.json\"; printf '%s' \"\$good_tags\" > \"$mapi/repos/o/r/rulesets/3.json\"" "${M[@]}"
# The Actions token settings.
wperms="$api/repos/o/r/actions/permissions/workflow.json"
wall "must not pass: a token that writes by default is a WARN" \
  "FC-E28 warn" \
  "printf '{\"default_workflow_permissions\":\"write\",\"can_approve_pull_request_reviews\":false}' > \"$wperms\""
wall "must not pass: a workflow that can approve is a WARN" \
  "FC-E28 warn" \
  "printf '{\"default_workflow_permissions\":\"read\",\"can_approve_pull_request_reviews\":true}' > \"$wperms\""
wall "...with the call that sets both" \
  "FC-E28 info" \
  "printf '{\"default_workflow_permissions\":\"write\",\"can_approve_pull_request_reviews\":true}' > \"$wperms\""
wall "the settings the door sets are a PASS" "FC-E28 pass"
wall "settings the token does not read are a SKIP, counted" "-- 0 failed, 2 not verified" "rm \"$wperms\""
out="$(rm -f "$wperms"; FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --actions-token --expect-checks "ci / a, ci / b" 2>&1)"; printf '%s' "$good_wperms" > "$wperms"
if is "$out" FC-E28 review && ! grep -q "SKIP  the Actions token" <<<"$out"
then ok "--actions-token: unread settings are left to /plinth:floor-check, not a SKIP"; else bad "--actions-token: unread settings"; fi
# The description: said, never a miss.
wall "a description is a PASS" "FC-E30 pass" "jq -c '. + {description: \"x\"}' <<<\"\$good_meta\" > \"$api/repos/o/r.json\""
wall "no description is an INFO with the command" "FC-E30 info" \
  "jq -c '. + {description: null}' <<<\"\$good_meta\" > \"$api/repos/o/r.json\""
wall "no description fails nothing and is not counted" "-- 0 failed, 1 not verified" "jq -c '. + {description: \"\"}' <<<\"\$good_meta\" > \"$api/repos/o/r.json\""

# The project's answers: each one that turns something on, against the file.
answers() { # <description> <`<id> <state>` expected, or !regex for absent> <answers lines> [shell in the copy] [api dir]
  local copy="$work/ans"; rm -rf "$copy"; cp -R "$good" "$copy"; printf '%b' "$3" >> "$copy/.copier-answers.yml"
  [ -n "${4:-}" ] && ( cd "$copy" && eval "$4" )
  local out want="$2" neg=0; [ "${want#!}" != "$want" ] && { neg=1; want="${want#!}"; }
  out="$(FLOOR_CHECK_API_DIR="${5:-$work/ans-none}" python3 "$checker" --root "$copy" --repo o/r 2>&1)"
  if { [ "$neg" = 0 ] && reports "$out" "$want"; } || { [ "$neg" = 1 ] && ! grep -qE -- "$want" <<<"$out"; }; then ok "$1"
  else bad "$1 (expected ${2})"; grep -E 'third_party|code_of_conduct|CODE_OF' <<<"$out" | sed 's/^/        /'; fi
}
mkdir -p "$work/ans-none"
answers "must not pass: third_party_review: true without its caller is a WARN" \
  "FC-F03 warn" 'third_party_review: true\n'
answers "...with how to bring it back or record false" "FC-F03 info" 'third_party_review: true\n'
answers "third_party_review: true with its caller is a PASS" "FC-F03 pass" \
  'third_party_review: true\n' "printf 'name: third-party\\n' > .github/workflows/third-party.yml"
answers "third_party_review: false is not a miss" '!third_party_review' 'third_party_review: false\n'
answers "must not pass: code_of_conduct: true without the file is a WARN" "FC-F04 warn" \
  'code_of_conduct: true\ncode_of_conduct_contact: a@b.c\n'
answers "code_of_conduct: true with the file is a PASS" "FC-F04 pass" \
  'code_of_conduct: true\n' ": > CODE_OF_CONDUCT.md"
answers "code_of_conduct: false is not a miss" '!CODE_OF_CONDUCT|code_of_conduct' 'code_of_conduct: false\n'
coc_api="$work/ans-owner"; mkdir -p "$coc_api/repos/o/.github/contents/docs"
printf '{"visibility":"public"}' > "$coc_api/repos/o/.github.json"
jq -n --arg c "$(printf '# Code\n' | base64)" '{content: $c}' > "$coc_api/repos/o/.github/contents/docs/CODE_OF_CONDUCT.md.json"
answers "owner_has_code_of_conduct: true and the owner publishes one (in docs/) is a PASS" \
  "FC-F05 pass" 'owner_has_code_of_conduct: true\n' "" "$coc_api"
answers "must not pass: owner_has_code_of_conduct: true and the owner's .github gone is a WARN" \
  "FC-F05 warn" 'owner_has_code_of_conduct: true\n'
gone_api="$work/ans-gone"; mkdir -p "$gone_api/repos/o"; printf '{"visibility":"public"}' > "$gone_api/repos/o/.github.json"
answers "must not pass: owner_has_code_of_conduct: true, a public .github without the file, is a WARN" \
  "FC-F05 warn" 'owner_has_code_of_conduct: true\n' "" "$gone_api"
# Codex review on #779, round 2: GitHub inherits from a public .github only,
# and an administrator's token still reads a private one's files.
priv_api="$work/ans-private"; rm -rf "$priv_api"; cp -R "$coc_api" "$priv_api"; printf '{"visibility":"private"}' > "$priv_api/repos/o/.github.json"
answers "must not pass: the owner's file readable in a private .github is a WARN, not a PASS" \
  "FC-F05 warn" \
  'owner_has_code_of_conduct: true\n' "" "$priv_api"
answers "...and it is never passed" "!PASS  owner_has_code_of_conduct" 'owner_has_code_of_conduct: true\n' "" "$priv_api"
unvis_api="$work/ans-unvis"; rm -rf "$unvis_api"; cp -R "$coc_api" "$unvis_api"; printf 'not json' > "$unvis_api/repos/o/.github.json"
answers "the .github's visibility unread is a SKIP, not a PASS" \
  "FC-F05 unknown" 'owner_has_code_of_conduct: true\n' "" "$unvis_api"
answers "...and code_of_conduct: true beside it is not asked of the repository" '!WARN  code_of_conduct: true' \
  'owner_has_code_of_conduct: true\ncode_of_conduct: true\n' "" "$coc_api"
bad_api="$work/ans-bad"; mkdir -p "$bad_api/repos/o/.github/contents"; printf 'not json' > "$bad_api/repos/o/.github/contents/CODE_OF_CONDUCT.md.json"; printf '{"visibility":"public"}' > "$bad_api/repos/o/.github.json"
answers "an owner's file that cannot be read is a SKIP, not a WARN" "FC-F05 unknown" \
  'owner_has_code_of_conduct: true\n' "" "$bad_api"
pr_api="$work/ans-owner-pr"; mkdir -p "$pr_api/repos/o/.github/contents/.github"; printf '{"visibility":"public"}' > "$pr_api/repos/o/.github.json"
jq -n --arg c "$(printf '## What\n' | base64)" '{content: $c}' > "$pr_api/repos/o/.github/contents/.github/PULL_REQUEST_TEMPLATE.md.json"
answers "owner_has_pr_template: true and the owner publishes one (in .github/) is a PASS" \
  "FC-F08 pass" 'owner_has_pr_template: true\n' "rm -f .github/PULL_REQUEST_TEMPLATE.md" "$pr_api"
answers "must not pass: owner_has_pr_template: true and the owner's is gone is a WARN" \
  "FC-F08 warn" \
  'owner_has_pr_template: true\n' "rm -f .github/PULL_REQUEST_TEMPLATE.md" "$gone_api"
answers "owner_has_pr_template: false is not read" '!owner_has_pr_template' 'owner_has_pr_template: false\n'
# Each owner copy is its own check (#1103): the pull-request template's
# unreadable file is a SKIP too.
bad_pr_api="$work/ans-bad-pr"; mkdir -p "$bad_pr_api/repos/o/.github/contents"; printf 'not json' > "$bad_pr_api/repos/o/.github/contents/PULL_REQUEST_TEMPLATE.md.json"; printf '{"visibility":"public"}' > "$bad_pr_api/repos/o/.github.json"
answers "an owner's pull-request template that cannot be read is a SKIP, not a WARN" "FC-F08 unknown" \
  'owner_has_pr_template: true\n' "rm -f .github/PULL_REQUEST_TEMPLATE.md" "$bad_pr_api"
# The archetypes that get the tag ruleset: one list in the door, one in the checker.
door_list="$(sed -n 's/^case "\$arch" in \([a-z|-]*\)) tag_ruleset=0.*/\1/p' "$root/scripts/new-project.sh")"
checker_list="$(python3 -c "import importlib.util as u; s=u.spec_from_file_location('fc','$root/scripts/floor-check.py'); m=u.module_from_spec(s); s.loader.exec_module(m); print('|'.join(m.TAG_NOT_RELEASING))")"
if [ -n "$door_list" ] && [ "$door_list" = "$checker_list" ]; then ok "the door and the checker leave out the same archetypes from the tag ruleset ($door_list)"
else bad "the door leaves out '$door_list' from the tag ruleset, the checker '$checker_list'"; fi
answers "a repository's own code of conduct applies in place of the owner's" "FC-F05 pass" \
  'owner_has_code_of_conduct: true\n' ": > CODE_OF_CONDUCT.md"

# ── the installed plinth against the newest template tag (#843) ─────────
skew_api="$work/api-plugin-skew"; tag_names "$skew_api" "$target_sha"
mkdir -p "$skew_api/repos/coolbress/plinth/releases" "$skew_api/repos/coolbress/plinth/contents/scripts"
printf '{"tag_name":"v98.0.0"}\n' > "$skew_api/repos/coolbress/plinth/releases/latest.json"
printf '{"content":"%s"}\n' "$(printf 'template_ref="v99.0.0"\n' | base64 | tr -d '\n')" \
  > "$skew_api/repos/coolbress/plinth/contents/scripts/new-project.sh?ref=v98.0.0.json"
skew_head="WARN  template: this plinth targets template $target_ref, but v99.0.0 is out (the latest plinth release, v98.0.0): update the plugin first. Type these yourself, in order:"
skew_steps='  INFO    claude plugin marketplace update plinth
  INFO    claude plugin update plinth@plinth
  INFO    /reload-plugins (or start a new session)
  INFO    /plinth:template-update'
out="$(FLOOR_CHECK_API_DIR="$skew_api" python3 "$checker" --root "$pcopy" --repo o/r 2>&1)"
if grep -qF "$skew_head" <<<"$out" && grep -qF -- "$skew_steps" <<<"$out" && is "$out" FC-F01 warn
then ok "a behind repository with an older plinth: the drift line stays, and the skew is named with the commands in order"
else bad "skew, behind"; printf '%s\n' "$out" | grep -E 'template|plugin' | sed 's/^/        /'; fi
out="$(FLOOR_CHECK_API_DIR="$skew_api" python3 "$checker" --root "$good" 2>&1)"
if grep -qF "$skew_head" <<<"$out" && grep -qF -- "$skew_steps" <<<"$out" && is "$out" FC-F01 pass
then ok "a repository on the installed target: the PASS stays, and the skew is named beside it"
else bad "skew, current"; printf '%s\n' "$out" | grep -E 'template|plugin' | sed 's/^/        /'; fi
out="$(FLOOR_CHECK_API_DIR="$skew_api" python3 "$checker" --root "$good" --actions-token 2>&1)"
if ! grep -qE "claude plugin|latest plinth release" <<<"$out"
then ok "ci / floor-check (--actions-token) says nothing: its checker is the pin's, not an installed plugin"
else bad "skew under --actions-token"; printf '%s\n' "$out" | grep -E 'plugin|plinth release' | sed 's/^/        /'; fi
out="$(FLOOR_CHECK_API_DIR="$skew_api" python3 "$checker" --root "$good" 2>&1)"
if ! grep -q "FAIL.*plugin" <<<"$out"; then ok "the skew is never a FAIL"; else bad "skew failed the run"; fi
same_skew="$work/api-plugin-same"; tag_names "$same_skew" "$target_sha"
mkdir -p "$same_skew/repos/coolbress/plinth/releases" "$same_skew/repos/coolbress/plinth/contents/scripts"
printf '{"tag_name":"v98.0.0"}\n' > "$same_skew/repos/coolbress/plinth/releases/latest.json"
printf '{"content":"%s"}\n' "$(printf 'template_ref="%s"\n' "$target_ref" | base64 | tr -d '\n')" \
  > "$same_skew/repos/coolbress/plinth/contents/scripts/new-project.sh?ref=v98.0.0.json"
printf '{"content":"%s"}\n' "$(printf 'template_ref="%s"\n' "$target_ref" | base64 | tr -d '\n')" \
  > "$same_skew/repos/coolbress/plinth/contents/scripts/new-project.sh?ref=$sha40.json"
out="$(FLOOR_CHECK_API_DIR="$same_skew" python3 "$checker" --root "$good" 2>&1)"
if ! grep -qE "claude plugin|plinth release|plinth pin $sha40 was tested" <<<"$out"; then ok "an installed target equal to the latest release's: no line"
else bad "skew, equal"; printf '%s\n' "$out" | grep -E 'plugin|plinth release' | sed 's/^/        /'; fi
out="$(python3 "$checker" --root "$good" --no-network 2>&1)"
if is "$out" FC-F02 info
then ok "the release not read: said beside the drift item, naming the installed target"
else bad "skew, unread"; printf '%s\n' "$out" | grep -E 'template|plinth release' | sed 's/^/        /'; fi
nocopy="$work/skew-foreign"; rm -rf "$nocopy"; cp -R "$good" "$nocopy"; rm "$nocopy/.copier-answers.yml"
out="$(FLOOR_CHECK_API_DIR="$skew_api" python3 "$checker" --root "$nocopy" 2>&1)"
if ! grep -q "claude plugin" <<<"$out"; then ok "a repository the door did not make: no skew line, the drift item's SKIP stands"
else bad "skew, not door-made"; fi
# GitLab: template-update.sh serves it (#1012), so the last step is the skill,
# as on GitHub; the pin read is the include's.
out="$(FLOOR_CHECK_API_DIR="$skew_api" python3 "$checker" --root "$glgood" --host gitlab 2>&1)"
if grep -qF "$skew_head" <<<"$out" && is "$out" FC-F02 info && ! grep -qF "  INFO    /plinth:floor-check" <<<"$out"
then ok "GitLab: the skew's last step is /plinth:template-update, as on GitHub"
else bad "skew, GitLab steps"; printf '%s\n' "$out" | grep -E 'plugin|/plinth:' | sed 's/^/        /'; fi
gl_pin="$(sed -nE 's|.*coolbress/plinth/([0-9a-f]{40})/gitlab/python-ci\.yml.*|\1|p' "$glgood/.gitlab-ci.yml")"
printf '{"content":"%s"}\n' "$(printf 'template_ref="v99.0.0"\n' | base64 | tr -d '\n')" \
  > "$same_skew/repos/coolbress/plinth/contents/scripts/new-project.sh?ref=$gl_pin.json"
out="$(FLOOR_CHECK_API_DIR="$same_skew" python3 "$checker" --root "$glgood" --host gitlab 2>&1)"
if [ -n "$gl_pin" ] && is "$out" FC-F02 warn
then ok "GitLab: the include's pin is the one compared"
else bad "skew, GitLab pin '$gl_pin'"; printf '%s\n' "$out" | grep -E 'plugin|plinth pin' | sed 's/^/        /'; fi

# --- The adoption record (#1112): .plinth-adoption.yml at the root, written by
# the adopt pull request. A run with no file is byte for byte the golden one
# (tests/floor-check-golden.sh); the cases below each write one.
adopt="$work/adopt"
mkdir -p "$work/adopt-records"; n_records=0
adoption() { # <file body, or "" for none>: a copy of the good fixture with that record, kept for the schema check below
  rm -rf "$adopt"; cp -R "$good" "$adopt"; [ -z "$1" ] && return
  printf '%s\n' "$1" > "$adopt/.plinth-adoption.yml"
  n_records=$((n_records + 1)); cp "$adopt/.plinth-adoption.yml" "$work/adopt-records/$n_records.yml"
}
record_head='schema: 1
plinth: v2.45.0
origin: none
archetype: backend
started: 2026-11-01
step: ci
wall_due: 2026-11-20'
a_run() { # <TODAY> [checker args...]: sets out and rc for the copy
  local d="$1"; shift
  out="$(FLOOR_CHECK_TODAY="$d" python3 "$checker" --root "$adopt" --no-network "$@" 2>&1)"; rc=$?
}
a_wall() { # <TODAY> [checker args...]: the copy against the wall fixture with no rules on main
  local d="$1"; shift
  printf '[]' > "$api/repos/o/r/rules/branches/main.json"
  out="$(FLOOR_CHECK_TODAY="$d" FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$adopt" --no-network --repo o/r \
    --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" "$@" 2>&1)"; rc=$?
  printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"
}
expect() { # <description> <condition>
  if eval "$2"; then ok "$1"; else bad "$1"; printf '%s\n' "$out" | grep -E 'FAIL|WARN|INFO|SKIP|failed' | sed 's/^/        /'; fi
}
unpin="sed -i.bak 's/@sha256:[0-9a-f]*//' \"\$adopt/Dockerfile\""   # FC-C20 alone fails

adoption "$record_head"
a_run 2026-11-10
expect "a valid record is read and said once, with its step and what it keeps" \
  'is "$out" FC-F09 info && [ "$rc" = 0 ] && grep -qF ".plinth-adoption.yml read: step ci, 0 kept by choice; the wall due by 2026-11-20" <<<"$out"'

adoption "$record_head
kept:
  - id: FC-C20
    path: Dockerfile
    reason: deliberately-different
    why: \"the base image is pinned by the registry we mirror\""
eval "$unpin"
a_run 2026-11-10
expect "a kept FAIL prints as kept by choice, is not counted, and the run exits 0" \
  'is "$out" FC-C20 kept && grep -qE "^  INFO  kept by choice \(deliberately-different\): " <<<"$out" && grep -q -- "^-- 0 failed" <<<"$out" && [ "$rc" = 0 ]'
a_run 2026-11-10 --actions-token --verdicts "$work/adopt.verdicts"
expect "in the CI form the kept finding leaves the verdicts file a pass" \
  '[ "$rc" = 0 ] && head -1 "$work/adopt.verdicts" | grep -q "^pass: " && ! grep -q "base image" "$work/adopt.verdicts"'
out="$(FLOOR_CHECK_TODAY=2026-11-10 python3 "$checker" --root "$adopt" --no-network --format json 2>&1)"; rc=$?
expect "--format json: the kept result is an info carrying what kept it and what it was" \
  '[ "$rc" = 0 ] && jq -e '"'"'[.results[] | select(.id == "FC-C20")][0] | .state == "info" and .kept.reason == "deliberately-different" and .kept.was == "fail" and .kept.path == "Dockerfile"'"'"' <<<"$out" >/dev/null && jq -e '"'"'[.results[] | select(.id != "FC-C20") | .kept] | all(. == null)'"'"' <<<"$out" >/dev/null'

adoption "$record_head
kept:
  - id: FC-C20
    path: Dockerfile
    reason: later
    why: rewrite after the release
    until: 2026-11-05"
eval "$unpin"
a_run 2026-11-10
expect "a kept entry whose until has passed FAILs, and the finding is counted again" \
  'is "$out" FC-F09 fail && is "$out" FC-C20 fail && grep -qF "kept FC-C20 until 2026-11-05, which has passed" <<<"$out" && [ "$rc" = 1 ]'
a_run 2026-11-05
expect "on its until date the entry still applies" 'is "$out" FC-C20 kept && [ "$rc" = 0 ]'

adoption "$record_head
kept:
  - id: FC-C20
    path: Dockerfile
    reason: later
    why: rewrite after the release"
eval "$unpin"
a_run 2026-11-10
expect "reason later with no until: the file is invalid, a FAIL naming it, and nothing in it applies" \
  'is "$out" FC-F09 fail && grep -qF ".plinth-adoption.yml is not valid: kept entry 1: reason later with no until" <<<"$out" && is "$out" FC-C20 fail'

adoption "$record_head
kept:
  - id: FC-A28
    path: .env
    reason: deliberately-different
    why: it holds no secret"
a_run 2026-11-10
expect "an id marked not keepable is not applied, and a FAIL says it cannot be kept and why" \
  'is "$out" FC-F09 fail && grep -qF "keeps FC-A28, which cannot be kept (a tracked secret reaches everyone" <<<"$out" && [ "$rc" = 1 ]'

adoption "$record_head
kept:
  - id: FC-Z99
    path: x
    reason: not-applicable
    why: x"
a_run 2026-11-10
expect "a kept id that names no check is a FAIL, never a silent pass" \
  'is "$out" FC-F09 fail && grep -qF "keeps FC-Z99, which names no check" <<<"$out"'

# A comment after a quoted value is taken off outside the quotes; a `#`
# inside them stays (#1236 review).
adoption 'schema: 1
plinth: "v2.45.0"   # the release that wrote it
origin: none
archetype: backend
started: 2026-11-01
step: ci
wall_due: "2026-11-20" # finish the wall
kept:
  - id: FC-C20
    path: Dockerfile
    reason: deliberately-different
    why: "pinned by the mirror, see #12" # the decision'
eval "$unpin"
a_run 2026-11-10
expect "quoted values with a comment after them are read, and a # inside the quotes stays" \
  'is "$out" FC-F09 info && is "$out" FC-C20 kept && grep -qF "the wall due by 2026-11-20" <<<"$out" && [ "$rc" = 0 ]'
out="$(FLOOR_CHECK_TODAY=2026-11-10 python3 "$checker" --root "$adopt" --no-network --format json 2>&1)"
expect "the # inside the quotes is in the kept reason given, not taken for a comment" \
  'jq -e '"'"'[.results[] | select(.id == "FC-C20")][0].kept.why == "pinned by the mirror, see #12"'"'"' <<<"$out" >/dev/null'
# The kept list's header with a comment after it (#1236 review, round 2):
# `kept: # …` opens the list, `kept: [] # …` is the empty one.
adoption "$record_head
kept: # what the adopt pull request left as it was
  - id: FC-C20 # the base image
    path: Dockerfile
    reason: deliberately-different
    why: pinned by the mirror"
eval "$unpin"
a_run 2026-11-10
expect "kept: with a comment after it opens the list, and its entry applies" \
  'is "$out" FC-F09 info && is "$out" FC-C20 kept && [ "$rc" = 0 ]'
adoption "$record_head
kept: [] # nothing kept"
a_run 2026-11-10
expect "kept: [] with a comment after it is the empty list" \
  'is "$out" FC-F09 info && grep -qF "0 kept by choice" <<<"$out"'
adoption "$(sed 's/^wall_due: .*$/wall_due: # later/' <<<"$record_head")"
a_run 2026-11-10
expect "a value that is only a comment is empty, not the comment's text" \
  'is "$out" FC-F09 fail && grep -qF "wall_due (empty) is not a date" <<<"$out" && ! grep -qF "# later" <<<"$out"'
adoption "$(sed 's/^step: ci$/step: "ci" then more/' <<<"$record_head")"
a_run 2026-11-10
expect "a quoted value followed by more than a comment is a FAIL naming the line, not a value with its quotes" \
  'is "$out" FC-F09 fail && grep -qF ".plinth-adoption.yml is not valid: line 6: a quoted value with more than a comment after it" <<<"$out"'

adoption "$record_head
kept: [FC-C20]
step: wall"
a_run 2026-11-10
expect "a field given twice is a FAIL naming the file and the line" \
  'is "$out" FC-F09 fail && grep -qF ".plinth-adoption.yml is not valid: line 9: step given twice" <<<"$out"'
adoption "$record_head
  stray: indented"
a_run 2026-11-10
expect "a line in a form this checker does not read is a FAIL naming the line" \
  'is "$out" FC-F09 fail && grep -qF ".plinth-adoption.yml is not valid: line 8 is not in the form this checker reads" <<<"$out"'
adoption "$record_head
colour: blue"
a_run 2026-11-10
expect "an unknown field makes the file invalid" 'is "$out" FC-F09 fail && grep -qF "unknown field colour" <<<"$out"'
adoption ""; mkdir "$adopt/.plinth-adoption.yml"
a_run 2026-11-10
expect "a record that cannot be read is a FAIL naming it, not a silent pass" \
  'is "$out" FC-F09 fail && grep -qF ".plinth-adoption.yml cannot be read (" <<<"$out" && [ "$rc" = 1 ]'

# The wall, with no rules on main: later until wall_due, the FAIL after it.
adoption "$record_head"
a_wall 2026-11-20
expect "no ruleset, on wall_due: the wall prints as later and is not counted" \
  'is "$out" FC-E12 info && grep -qF "the wall: later, after the first green run on main (until 2026-11-20" <<<"$out" && ! is "$out" FC-E12 fail'
a_wall 2026-11-21
expect "no ruleset, the day after wall_due: the wall is down again, a FAIL" 'is "$out" FC-E12 fail && ! is "$out" FC-E12 info'
a_wall 2026-11-20 --actions-token --verdicts "$work/adopt.verdicts"
expect "in the CI form, before wall_due, the wall is no fail line in the verdicts file" \
  '! grep -q "the wall is down" "$work/adopt.verdicts" && is "$out" FC-E12 info'
adoption "${record_head/step: ci/step: done}"
a_wall 2026-11-10
expect "at step done wall_due holds nothing off: no rules is a FAIL" 'is "$out" FC-E12 fail'
adoption "${record_head/wall_due: 2026-11-20/wall_due: 2027-01-15}"
a_wall 2026-12-05
expect "wall_due more than 30 days after started is read as 30 days: said, and the wall FAILs after it" \
  'is "$out" FC-F09 info && grep -qF "wall_due 2027-01-15 is more than 30 days after started 2026-11-01; read as 2026-12-01" <<<"$out" && is "$out" FC-E12 fail'
a_wall 2026-12-01
expect "on the 30th day the capped wall_due still holds the wall off" 'is "$out" FC-E12 info'
adoption "${record_head/started: 2026-11-01/started: 2099-01-01}"
a_wall 2026-11-10
expect "a started after today makes the record invalid, so the 30 days cannot be moved forward: the wall FAILs" \
  'is "$out" FC-F09 fail && grep -qF "started 2099-01-01 is after today (2026-11-10)" <<<"$out" && is "$out" FC-E12 fail'
adoption "$record_head"
out="$(FLOOR_CHECK_TODAY=2026-11-10 FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$adopt" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" 2>&1)"; rc=$?
expect "with a ruleset in place the record changes no wall line: the intact wall passes as without it" \
  'grep -q -- "^-- 0 failed" <<<"$out" && ! grep -q "the wall: later" <<<"$out"'
printf '[{"type":"deletion","ruleset_source_type":"Repository","ruleset_id":1}]' > "$api/repos/o/r/rules/branches/main.json"
out="$(FLOOR_CHECK_TODAY=2026-11-10 FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$adopt" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" 2>&1)"; rc=$?
printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"
expect "a ruleset with rules missing, before wall_due: the missing rules still FAIL" \
  'is "$out" FC-E15 fail && [ "$rc" = 1 ]'

# The schema: every record above, printed as the checker reads it, against
# scripts/plinth-adoption.schema.json. The valid ones pass it; the invalid
# ones the checker refuses fail it too.
schema_ok() { # <description> <0 valid | 1 invalid> <file body>
  adoption "$3"
  local doc; doc="$(python3 "$checker" --root "$adopt" --print-adoption 2>/dev/null)" || { bad "$1 (not printed)"; return; }
  printf '%s\n' "$doc" > "$work/adopt.json"
  python3 "$root/tests/lib/json-schema-check.py" "$root/scripts/plinth-adoption.schema.json" "$work/adopt.json" > "$work/adopt.schema" 2>&1
  local got=$?
  if [ "$got" = "$2" ]; then ok "$1"; else bad "$1 (schema check exit $got)"; sed 's/^/        /' "$work/adopt.schema"; fi
}
schema_ok "schema: the plain record is valid" 0 "$record_head"
schema_ok "schema: a record with a kept entry is valid" 0 "$record_head
kept:
  - id: FC-A06
    path: CONTRIBUTING.md
    reason: later
    why: rewrite after the release
    until: 2026-11-05"
schema_ok "schema: later with no until is invalid, as the checker says" 1 "$record_head
kept:
  - id: FC-A06
    path: CONTRIBUTING.md
    reason: later
    why: rewrite after the release"
schema_ok "schema: an unknown field is invalid, as the checker says" 1 "$record_head
colour: blue"
schema_ok "schema: a step outside files, ci, wall and done is invalid" 1 "${record_head/step: ci/step: halfway}"
schema_ok "schema: an origin other than none or other-template:<source> is invalid" 1 "${record_head/origin: none/origin: somewhere}"
# Every record the cases above wrote, read as the checker reads it: where the
# checker finds no schema error, the schema finds none; where it finds one, so
# does the schema. A record not in the form the checker reads has no document
# to give the schema, and is counted apart. The checker is loaded as a module,
# so these reads are no checker runs for the golden file.
agree="$(python3 - "$checker" "$root/tests/lib/json-schema-check.py" "$root/scripts/plinth-adoption.schema.json" "$work/adopt-records" <<'PY'
import importlib.util, json, subprocess, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("floor_check", sys.argv[1])
fc = importlib.util.module_from_spec(spec); spec.loader.exec_module(fc)
both = form = 0
for f in sorted(Path(sys.argv[4]).glob("*.yml"), key=lambda p: int(p.stem)):
    try:
        d = fc.read_adoption(f.read_text(encoding="utf-8"))
    except ValueError:
        form += 1
        continue
    doc = f.with_suffix(".json"); doc.write_text(json.dumps(fc.adoption_json(d)), encoding="utf-8")
    schema_ok = subprocess.run([sys.executable, sys.argv[2], sys.argv[3], str(doc)], capture_output=True).returncode == 0
    if schema_ok != (not fc.adoption_errors(d)):
        print(f"disagree {f.name}: checker {fc.adoption_errors(d) or 'valid'}, schema {'valid' if schema_ok else 'invalid'}")
    both += 1
print(f"read {both} form {form}")
PY
)"
if grep -qE '^read [1-9][0-9]+ form [1-9]' <<<"$agree" && ! grep -q '^disagree' <<<"$agree"
then ok "every record the cases wrote: the checker and the schema agree on each ($(tail -1 <<<"$agree"))"
else bad "the checker and the schema disagree on a record the cases wrote"; sed 's/^/        /' <<<"$agree"; fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
