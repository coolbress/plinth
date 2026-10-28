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
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
tag_names() { # <fixture dir> <commit>: what the target tag names on GitHub (#519)
  mkdir -p "$1/repos/coolbress/plinth-template/commits"
  printf '{"sha":"%s"}\n' "$2" > "$1/repos/coolbress/plinth-template/commits/$target_ref.json"
}
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

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
{"permissions":{"deny":["Bash(git push --force:*)","Bash(rm -rf:*)","Bash(gh auth token*)","Read(./.env)","Bash(. *.env*)","Bash(source *.env*)","Bash(cat *.env)","Bash(grep *.env)","Read(~/.config/gh/**)"]}}
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
skips "offline without --repo: the unchecked wall is counted once" \
  "1 not verified" --root "$good" --no-network
noarch="$work/noarch"; rm -rf "$noarch"; cp -R "$good" "$noarch"; rm "$noarch/.copier-answers.yml"
skips "no archetype: the skipped conditional items are counted (and template drift, which also reads .copier-answers.yml)" \
  "3 not verified" --root "$noarch" --no-network

# Planted defects, each must be named.
plant() { # <description> <shell to break the copy> <expected FAIL substring>
  local copy="$work/case"; rm -rf "$copy"; cp -R "$good" "$copy"
  ( cd "$copy" && eval "$2" )
  local out; out="$(python3 "$checker" --root "$copy" --no-network 2>&1)"
  if [ "$3" = "__none__" ]; then
    if grep -q -- '-- 0 failed' <<<"$out"; then ok "$1"; else bad "$1 (should not fail)"; printf '%s\n' "$out" | grep FAIL | sed 's/^/        /'; fi
    return
  fi
  if grep -q "FAIL.*$3" <<<"$out"; then ok "$1"; else bad "$1 (expected a FAIL mentioning '$3')"; printf '%s\n' "$out" | grep FAIL | sed 's/^/        /'; fi
}
infos() { # <description> <shell to break the copy> <expected INFO or SKIP substring>
  local copy="$work/case"; rm -rf "$copy"; cp -R "$good" "$copy"
  ( cd "$copy" && eval "$2" )
  local out; out="$(python3 "$checker" --root "$copy" --no-network 2>&1)"
  if grep -qE "(INFO|SKIP).*$3" <<<"$out"; then ok "$1"; else bad "$1 (expected an INFO or SKIP mentioning '$3')"; printf '%s\n' "$out" | grep -E 'INFO|SKIP|FAIL' | sed 's/^/        /'; fi
}
warns() { # <description> <shell to break the copy> <expected WARN substring>
  local copy="$work/case"; rm -rf "$copy"; cp -R "$good" "$copy"
  ( cd "$copy" && eval "$2" )
  local out; out="$(python3 "$checker" --root "$copy" --no-network 2>&1)"
  if grep -q "WARN.*$3" <<<"$out"; then ok "$1"; else bad "$1 (expected a WARN mentioning '$3')"; printf '%s\n' "$out" | grep -E 'WARN|FAIL' | sed 's/^/        /'; fi
}
plant "stub CONTRIBUTING is caught" "printf '# Contributing\nSee the wiki.\n' > CONTRIBUTING.md" "no build or test command"
plant "unpinned base image is caught" "sed -i.bak 's/@sha256:[0-9a-f]*//' Dockerfile" "not pinned by digest"
plant "root user is caught" "sed -i.bak 's/^USER app/USER root/' Dockerfile" "runs as root"
plant "undocumented env var is caught" "printf 'x\n' > .env.example" "missing variables"
plant "missing token deny is caught" "printf '{\"permissions\":{\"deny\":[]}}' > .claude/settings.json" "does not deny gh auth token"
plant "a Read-only .env deny is caught" "sed -i.bak 's/\"Bash(\. \*\.env\*)\",\"Bash(source \*\.env\*)\",//' .claude/settings.json" "does not deny \`. ./.env\`"
plant "a sourcing deny without its closing parenthesis is caught" "sed -i.bak 's/\"Bash(source \*\.env\*)\"/\"Bash(source .env*\"/' .claude/settings.json" "does not deny \`source .env\`"
plant "a sourcing deny spelt with a ? is caught: only * is a wildcard" "sed -i.bak 's/\"Bash(source \*\.env\*)\"/\"Bash(source .en?)\"/' .claude/settings.json" "does not deny \`source .env\`"
plant "a settings without the cat rule is caught" "sed -i.bak 's/\"Bash(cat \*\.env)\",//' .claude/settings.json" "does not deny \`cat .env\`"
plant "a grep rule that names only .env.example is caught" "sed -i.bak 's/\"Bash(grep \*\.env)\"/\"Bash(grep *.env.example)\"/' .claude/settings.json" "does not deny \`grep KEY .env\`"
plant "a sourcing deny that names only .env.local is caught" "sed -i.bak 's/\"Bash(source \*\.env\*)\"/\"Bash(source *.env.local*)\"/' .claude/settings.json" "does not deny \`source .env\`"
plant "broken doc link is caught" "printf '[x](nope.md)\n' >> README.md" "do not exist"
# A *.md symbolic link whose target is missing was read like a file and
# crashed the checker before any verdict (#525). It is a FAIL naming the link
# and its target, every other item is still reported, and a link to a file
# that exists is read through it.
plant "a dangling *.md link is a FAIL naming the link and its target (#525)" "ln -s MISSING.md CLAUDE.md" "CLAUDE.md -> MISSING.md"
plant "a *.md link to an existing file is read through it" "ln -s README.md NOTES.md" "__none__"
dl="$work/dangling"; rm -rf "$dl"; cp -R "$good" "$dl"; ln -s MISSING.md "$dl/CLAUDE.md"
out="$(python3 "$checker" --root "$dl" --no-network --verdicts "$dl.verdicts" 2>&1)"; rc=$?
if [ "$rc" = 1 ] && [ -s "$dl.verdicts" ] && ! grep -q Traceback <<<"$out" && grep -q '^  PASS  LICENSE present' <<<"$out" \
  && grep -q -- '-- 1 failed' <<<"$out"; then ok "a dangling *.md link still writes the verdicts and reports the other items"
else bad "a dangling *.md link stops the checker (rc=$rc, verdicts $( [ -s "$dl.verdicts" ] && echo written || echo missing ))"; printf '%s\n' "$out" | grep -E 'Traceback|Error|FAIL|failed' | sed 's/^/        /'; fi
plant "unlabelled issue form is caught" "printf 'name: t\ndescription: \"x\"\nbody: []\n' > .github/ISSUE_TEMPLATE/task.yml" "no labels"
plant "missing lockfile is caught" "rm uv.lock" "uv.lock missing"
# The image check is the service archetypes' own required check (#127): the job
# has to exist in the caller, and a cli instance is not asked for it.
plant "a service instance whose ci.yml has no image job is caught" "rm .github/workflows/ci.yml" "no \`image\` job"
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
  "rm .github/ISSUE_TEMPLATE/*.yml && printf 'blank_issues_enabled: false\n' > .github/ISSUE_TEMPLATE/config.yml" "no issue template"
# An empty folder is not a local template set: GitHub falls back to the owner's
# shared forms, and offline that cannot be checked. Absence is not concluded here.
infos "an empty folder falls through to inheritance, not to a verdict" \
  "rm .github/ISSUE_TEMPLATE/*.yml" "inheritance not verified"
plant "an empty folder alone is not called a missing form" "rm .github/ISSUE_TEMPLATE/*.yml" "__none__" || true
warns "front matter with an empty name is named as unusable" \
  "printf -- '---\nname:\n---\n' > .github/ISSUE_TEMPLATE/bug.md" "no front matter"
plant "a defect inside a renamed form is still caught" \
  "cd .github/ISSUE_TEMPLATE && mv task.yml work_item.yml && printf 'name: t\ndescription: \"x\"\nbody: []\n' > work_item.yml" "no labels"
# Widening the net must not fail a repository that passed yesterday: `.yml` keeps
# its severity, and a defect found only because `.yaml` and `.md` are now read is
# a WARN. `labels:` is plinth policy, not GitHub's syntax (#85).
plant "an unlabelled .yaml next to good forms warns, it does not fail" \
  "printf 'name: e\ndescription: \"x\"\nbody: []\n' > .github/ISSUE_TEMPLATE/extra.yaml" "__none__" || true
plant "an unlabelled .yml still fails" \
  "printf 'name: e\ndescription: \"x\"\nbody: []\n' > .github/ISSUE_TEMPLATE/extra.yml" "no labels"
# An invalid extra warns, because the repository passed without that file being
# read. A repository whose *every* template is invalid never passed the old
# filename check either, so it fails: leaving it green would be a loosening.
warns "an empty Markdown template beside good forms only warns" \
  ": > .github/ISSUE_TEMPLATE/bug.md" "no front matter"
plant "an empty Markdown template beside good forms does not fail" \
  ": > .github/ISSUE_TEMPLATE/bug.md" "__none__" || true
plant "an empty Markdown template as the only one fails" \
  "rm .github/ISSUE_TEMPLATE/*.yml && : > .github/ISSUE_TEMPLATE/bug.md" "no usable issue template"
plant "a bare name: as the only template fails" \
  "rm .github/ISSUE_TEMPLATE/*.yml && printf -- '---\nname:\n---\n' > .github/ISSUE_TEMPLATE/bug.md" "no usable issue template"
plant "a quoted empty name as the only template fails" \
  "rm .github/ISSUE_TEMPLATE/*.yml && printf -- '---\nname: \"\"\n---\n' > .github/ISSUE_TEMPLATE/bug.md" "no usable issue template"
# GitHub rejects a form whose `body` is not a sequence. The check is new ground,
# so it never fails on its own; it decides usability only for the extensions this
# checker did not read before.
plant "a .yaml whose body is not a list is not a usable template" \
  "rm .github/ISSUE_TEMPLATE/*.yml && printf 'name: x\ndescription: x\nlabels: [x]\nbody: nope\n' > .github/ISSUE_TEMPLATE/custom.yaml" "no usable issue template"
plant "the same defect in .yml, which passed before, only warns" \
  "cd .github/ISSUE_TEMPLATE && for f in bug feature task; do printf 'name: %s\ndescription: x\nlabels: [\"%s\"]\nbody: nope\n' \$f \$f > \$f.yml; done" "__none__" || true
warns "the .yml body defect is still named" \
  "printf 'name: bug\ndescription: x\nlabels: [\"bug\"]\nbody: nope\n' > .github/ISSUE_TEMPLATE/bug.yml" "body is not a list"
plant "block-list labels are accepted" "printf 'name: t\ndescription: \"x\"\nlabels:\n  - task\nbody: []\n' > .github/ISSUE_TEMPLATE/task.yml" "__none__" || true
plant "multi-stage and --platform FROM are understood" "printf 'FROM --platform=linux/amd64 python:3.12-slim@sha256:%064d AS base\nFROM base\nRUN uv sync --locked\nUSER app\nCMD [\"python\", \"-m\", \"app\"]\n' 0 > Dockerfile" "__none__" || true

# The three predicates #42 deferred (#95): a tracked dotenv file, an action not
# pinned to a commit, a service with no JSON logs. Each is new ground, so each
# is a WARN and never a FAIL; each names the path and carries its repair; and
# what the checker cannot read is a SKIP, never a PASS.
says() { # <description> <shell to change the copy> <expected ERE on one output line>
  local copy="$work/case"; rm -rf "$copy"; cp -R "$good" "$copy"
  ( cd "$copy" && eval "$2" )
  local out; out="$(python3 "$checker" --root "$copy" --no-network 2>&1)"
  if grep -qE -- "$3" <<<"$out"; then ok "$1"; else bad "$1 (expected a line matching '$3')"; printf '%s\n' "$out" | grep -E 'WARN|FAIL|SKIP' | sed 's/^/        /'; fi
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
says  "the good fixture says no dotenv file is tracked" ":" "PASS  no dotenv file is tracked"
warns "a tracked .env is named" "printf 'AUDIT_DUMMY=not-a-secret\n' > .env && git add -f .env" "tracked dotenv file: \.env$"
says  "a tracked .env carries its repair" "printf 'A=b\n' > .env && git add -f .env" "INFO    git rm --cached -- \.env"
warns "a tracked dotenv in a subdirectory is named by its path" "mkdir -p deploy && printf 'A=b\n' > deploy/.env.production && git add -f deploy/.env.production" "tracked dotenv file: deploy/\.env\.production$"
# The repair line is pasted into a shell, and the path is the repository's to choose.
says  "a path with shell syntax in it is quoted in the repair" "mkdir 'a\$(touch PWN)' && printf 'A=b\n' > 'a\$(touch PWN)/.env' && git add -f ." "INFO    git rm --cached -- 'a\\\$\(touch PWN\)/\.env'"
# A file name is any bytes, and macOS refuses to create one that is not UTF-8,
# so git is a shim here: the listing must be decoded without a traceback.
mkdir -p "$work/gitshim"; printf '#!/bin/sh\nprintf "caf\\351.txt\\0README.md\\0"\n' > "$work/gitshim/git"; chmod +x "$work/gitshim/git"
out="$(PATH="$work/gitshim:$PATH" python3 "$checker" --root "$good" --no-network 2>&1)"
if grep -q "PASS  no dotenv file is tracked (2 tracked files" <<<"$out" && ! grep -q Traceback <<<"$out"; then ok "a file name that is not UTF-8 does not abort the check"
else bad "a non-UTF-8 file name"; printf '%s\n' "$out" | grep -E 'dotenv|Error|Traceback' | sed 's/^/        /'; fi
quiet "an untracked local .env is not the defect" "printf 'A=b\n' > .env" "dotenv"
quiet "tracked placeholders are allowed" "printf 'A=\n' | tee .env.sample > .env.template && git add -f .env.example .env.sample .env.template" "dotenv"
quiet "a tracked directory named .env is not a dotenv file" "mkdir .env && printf 'x\n' > .env/pyvenv.cfg && git add -f .env/pyvenv.cfg" "dotenv"
says  "outside a git work tree the dotenv check is not verified, not passed" "rm -rf .git" "SKIP  tracked dotenv files not verified"

# Actions: every `uses:` in .github/workflows, read as workflow syntax.
says  "the good fixture's SHA-pinned reusable workflow passes" ":" "PASS  every action in 1 workflow file is pinned to a commit \(1 uses\)"
warns "an action pinned to a tag is named with its file and line" "wf '- uses: actions/checkout@v4' > .github/workflows/t.yml" "\.github/workflows/t\.yml: not pinned to a full commit SHA: line 5 actions/checkout@v4$"
says  "a tag-pinned action carries the command that finds its SHA" "wf '- uses: actions/checkout@v4' > .github/workflows/t.yml" "INFO    gh api repos/actions/checkout/commits/v4 --jq \.sha"
says  "a ref with shell syntax in it is quoted in the repair" "wf '- uses: a/b@\$(id)' > .github/workflows/t.yml" "INFO    gh api 'repos/a/b/commits/\\\$\(id\)' --jq"
warns "a branch ref, a short SHA and a quoted value are all unpinned" "wf '- uses: a/b@main' '- uses: c/d@3d3c42e' '- uses: \"e/f/sub@v1\"' > .github/workflows/t.yaml" "line 5 a/b@main, line 6 c/d@3d3c42e, line 7 e/f/sub@v1$"
warns "a docker action pinned to a tag is unpinned" "wf '- uses: docker://alpine:3.20' > .github/workflows/t.yml" "line 5 docker://alpine:3.20"
quiet "SHA pins, a local action, a docker digest, a comment and a run block are not findings" \
  "wf '- uses: actions/checkout@$sha40 # v4' '- uses: ./.github/actions/x' '- uses: docker://alpine@sha256:$sha64' '# - uses: old/one@v1' '- run: |' '    uses: not/yaml@v1' '  env:' '    A: b' > .github/workflows/t.yml" "pinned|workflow"
quiet "the word uses inside a run line is not a uses key" "wf '- run: grep -rn \"uses:\" .github/workflows' > .github/workflows/t.yml" "pins not verified"
# A `: |` inside a trailing comment is not a block scalar (#334); one ending the key's value is.
warns "a comment ending in ': |' does not hide the uses below it" "printf 'jobs:  # note: |\n  t:\n    steps:\n      - uses: actions/checkout@v4\n' > .github/workflows/t.yml" "line 4 actions/checkout@v4$"
warns "a comment ending in ': >' does not hide it either" "printf 'jobs:\n  t:  # a: >-\n    steps:\n      - uses: actions/checkout@v4\n' > .github/workflows/t.yml" "line 4 actions/checkout@v4$"
quiet "an explicit-key run block (? run, then : |) is still a block" "wf '- ? run' '  : |' '    uses: not/yaml@v1' > .github/workflows/t.yml" "pinned|workflow"
quiet "a run block with a trailing comment is still a block" "wf '- run: |  # note: |' '    uses: not/yaml@v1' '- \"a # b\": |' '    uses: not/yaml@v1' > .github/workflows/t.yml" "pinned|workflow"
says  "a uses this checker cannot read is not verified, not passed" "wf '- {uses: actions/checkout@v4}' > .github/workflows/t.yml" "SKIP  \.github/workflows/t\.yml: action pins not verified: line 5"
says  "an explicit-key uses is not verified either" "wf '- ? uses' '  : actions/checkout@v4' > .github/workflows/t.yml" "SKIP  \.github/workflows/t\.yml: action pins not verified: line 5"
says  "an anchored uses key is not verified either" "wf '- &step uses: actions/checkout@v4' > .github/workflows/t.yml" "SKIP  \.github/workflows/t\.yml: action pins not verified: line 5"
says  "a uses later in a flow mapping is not verified either" "wf '- {name: a, uses: actions/checkout@v4}' > .github/workflows/t.yml" "SKIP  \.github/workflows/t\.yml: action pins not verified: line 5"
says  "a repository with no workflow says so rather than pass" "sed -i.bak 's/backend/cli/' .copier-answers.yml && rm -r .github/workflows" "INFO  no workflow file under \.github/workflows"

# JSON logs: a service archetype's source, read statically. A hint is a hint:
# the PASS line says it is not proof of what the process prints.
says  "the good fixture's formatter is a static hint, and is called one" ":" "PASS  JSON logs: static hint in src/app/__main__\.py .*not proof"
warns "a service that only prints is named with its entry point" "printf 'print(\"plain text startup\")\n' > src/app/__main__.py" "JSON logs: no logging found under src/ (entry point src/app/__main__\.py)"
warns "a hint that is only a comment is not a hint" "printf '# TODO: add pythonjsonlogger\nprint(1)\n' > src/app/__main__.py" "JSON logs: no logging found"
says  "structlog's JSONRenderer is a hint" "printf 'import structlog\nstructlog.configure(processors=[structlog.processors.JSONRenderer()])\n' > src/app/__main__.py" "PASS  JSON logs: static hint in src/app/__main__\.py"
says  "python-json-logger in another module is a hint, named by its path" "printf 'print(1)\n' > src/app/__main__.py && printf 'from pythonjsonlogger import jsonlogger\n' > src/app/log.py" "PASS  JSON logs: static hint in src/app/log\.py"
says  "logging this checker does not recognise is not verified, not passed" "printf 'import logging\nlogging.basicConfig()\n' > src/app/__main__.py" "SKIP  JSON logs not verified: src/app/__main__\.py"
says  "logging imported beside other modules is still logging" "printf 'import json, logging, sys\nlogging.basicConfig(stream=sys.stdout)\n' > src/app/__main__.py" "SKIP  JSON logs not verified"
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
inherit() { # <description> <expected substring> <local ISSUE_TEMPLATE shell, or ""> [api dir]
  local copy="$work/inh"; rm -rf "$copy"; cp -R "$good" "$copy"
  rm -rf "$copy/.github/ISSUE_TEMPLATE"; [ -n "$3" ] && ( cd "$copy" && eval "$3" )
  local out; out="$(FLOOR_CHECK_API_DIR="${4:-$inh}" python3 "$checker" --root "$copy" --repo o/r 2>&1)"
  if grep -q -- "$2" <<<"$out"; then ok "$1"; else bad "$1 (expected '$2')"; printf '%s\n' "$out" | grep -E 'issue form|inherited' | sed 's/^/        /'; fi
}
inherit "the owner's shared forms are read when the repository has none" "PASS  issue templates found (inherited): bug.yml, feature.yml" ""
inherit "a local .gitkeep is not a template: the shared set still applies" "PASS  issue templates found (inherited)" "mkdir -p .github/ISSUE_TEMPLATE && : > .github/ISSUE_TEMPLATE/.gitkeep"
inherit "a local form suppresses the shared set, and says so" "INFO  a local ISSUE_TEMPLATE replaces the owner" "mkdir -p .github/ISSUE_TEMPLATE && printf 'name: t\ndescription: \"x\"\nlabels: [\"t\"]\nbody: []\n' > .github/ISSUE_TEMPLATE/t.yml"
# A file listed but unreadable is an API failure, not an absent template.
bad_api="$work/inh-bad"; mkdir -p "$bad_api/repos/o/.github/contents/.github"
printf '[{"name":"bug.md"}]' > "$bad_api/repos/o/.github/contents/.github/ISSUE_TEMPLATE.json"
inherit "an unreadable inherited file is not verified, not absent" "SKIP  inherited forms not verified" "" "$bad_api"
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
grep -q "SKIP  inherited forms not verified" <<<"$out_mix" && ok "the unreadable form is named" || bad "the unreadable form is not named"

# A listing holding only a config proves no form is there: configuration is never
# fetched, so a failed read of it cannot hide that.
cfg_api="$work/inh-cfg"; mkdir -p "$cfg_api/repos/o/.github/contents/.github"
printf '[{"name":"config.yml"}]' > "$cfg_api/repos/o/.github/contents/.github/ISSUE_TEMPLATE.json"
inherit "a shared listing of only a config is a real absence, not an unread file" "FAIL  no issue template (inherited)" "" "$cfg_api"

# Nothing local and nothing shared: a 404 on the listing is a real absence.
none_api="$work/inh-none"; mkdir -p "$none_api/repos/o"
inherit "no templates anywhere is still caught" "FAIL  issue forms neither local nor in the owner" "" "$none_api"

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
wall() { # <description> <expected substring in output> [shell that edits the fixture first]
  local out; [ -n "${3:-}" ] && eval "$3"
  out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" 2>&1)"
  # A summary naming N not verified must sit above exactly N SKIP lines.
  local n want; n="$(grep -c '^  SKIP ' <<<"$out")"; want="${2##*failed, }"; want="${want%% *}"
  if grep -q -- "$2" <<<"$out" && { [[ "$2" != "-- "*"not verified"* ]] || [ "$n" = "$want" ]; }; then ok "$1"
  else bad "$1 (expected '$2', SKIP lines=$n)"; printf '%s\n' "$out" | grep -E 'FAIL|SKIP|failed' | sed 's/^/        /'; fi
  printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"; printf '{"bypass_actors":[]}' > "$api/repos/o/r/rulesets/1.json"
  printf '%s' "$good_meta" > "$api/repos/o/r.json"
  printf '%s' "$good_setup" > "$api/repos/o/r/code-scanning/default-setup.json"
}
wall "intact wall passes" "-- 0 failed"
wall "squash commits are the pull request title and description" "PASS  squash commits carry"
wall "drifted squash settings are caught" "squash commit settings drifted: title=COMMIT_OR_PR_TITLE" "printf '{\"default_branch\":\"main\",\"squash_merge_commit_title\":\"COMMIT_OR_PR_TITLE\",\"squash_merge_commit_message\":\"COMMIT_MESSAGES\"}' > \"$api/repos/o/r.json\""
wall "invisible squash settings are SKIP, not a pass" "squash commit settings not visible" "printf '{\"default_branch\":\"main\"}' > \"$api/repos/o/r.json\""
# A repository the door damaged before #105: the default branch is the throwaway
# probe, the whole wall stands on that branch, and `main` has no rules at all.
# Following the default branch reports it as a wall standing -- the checker
# telling someone `main` is guarded while anyone can force-push it (#107).
damaged="mv \"$api/repos/o/r/rules/branches/main.json\" \"$api/repos/o/r/rules/branches/__push-probe.json\"; printf '{\"default_branch\":\"__push-probe\",\"squash_merge_commit_title\":\"PR_TITLE\",\"squash_merge_commit_message\":\"PR_BODY\"}' > \"$api/repos/o/r.json\""
wall "a default branch that is not main is reported, not passed over" "WARN  the default branch is __push-probe, not main" "$damaged"
wall "the finding says main is the branch left unprotected" "main is unprotected" "$damaged"
wall "the fix carries the one command that repairs it" "gh api repos/o/r -X PATCH -f default_branch=main" "$damaged"
# Never a FAIL. `ci / floor-check` runs with --repo in every consumer's CI, so a
# FAIL blocks their merges -- and a repository whose default is deliberately
# `master` or `trunk` is not broken, it just is not what the door builds (#106).
eval "$damaged"
out_db="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --expect-checks "ci / a, ci / b" 2>&1)"; rc_db=$?
if [ "$rc_db" = 0 ] && ! grep -q "FAIL.*default branch" <<<"$out_db"; then ok "a default branch that is not main never fails the floor (consumer CI keeps merging)"
else bad "a wrong default branch changed the exit code (rc=$rc_db) or produced a FAIL"; printf '%s
' "$out_db" | grep -E 'FAIL' | sed 's/^/        /'; fi
# Said once and plainly, not only as the prefix on each rule line.
if grep -q "the wall is checked on __push-probe, the repository's default branch" <<<"$out_db"; then ok "the branch the wall was checked on is stated once, not only as a prefix"
else bad "the output never states which branch the wall was checked on"; fi
printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"
printf '%s' "$good_meta" > "$api/repos/o/r.json"
rm -f "$api/repos/o/r/rules/branches/__push-probe.json"
# The default branch is read from the repository, so a token or an API that does
# not report it must not be read as "main, fine": not verified, like every other
# API-backed check here.
wall "a default branch the API does not report is not verified rather than passed" \
  "SKIP  default branch not verified" \
  "printf '{\"squash_merge_commit_title\":\"PR_TITLE\",\"squash_merge_commit_message\":\"PR_BODY\"}' > \"$api/repos/o/r.json\""
wall "a repository whose default branch is main is unchanged: no warning, no new noise" "-- 0 failed"
wall "a healthy repository still says which branch the wall was checked on" "the wall is checked on main, the repository's default branch"
wall "dropped required check is caught" "required checks dropped: \['ci / b'\]" "sed -i.bak 's/,{\"context\":\"ci \/ b\",\"integration_id\":15368}//' \"$api/repos/o/r/rules/branches/main.json\""
wall "a dropped required check comes with the one command that requires it again" "INFO  .*scripts/upgrade-ruleset.sh o/r 'ci / b:15368'" "sed -i.bak 's/,{\"context\":\"ci \/ b\",\"integration_id\":15368}//' \"$api/repos/o/r/rules/branches/main.json\""
wall "widened merge methods are caught" "merge methods widened" "sed -i.bak 's/\[\"squash\"\]/[\"squash\",\"merge\"]/' \"$api/repos/o/r/rules/branches/main.json\""
wall "bypass actor is caught" "bypass actors present" "printf '{\"bypass_actors\":[{\"actor_id\":5,\"actor_type\":\"RepositoryRole\"}]}' > \"$api/repos/o/r/rulesets/1.json\""
wall "no rules at all is caught" "the wall is down" "printf '[]' > \"$api/repos/o/r/rules/branches/main.json\""
wall "invisible bypass actors are SKIP, not a pass" "bypass actors not visible" "printf '{}' > \"$api/repos/o/r/rulesets/1.json\""
# Labels have no fixture yet at this point, so that read is the one SKIP of an
# intact wall; the invisible bypass actors are the second.
wall "an intact wall against the fixture counts only the label read as not verified" "-- 0 failed, 1 not verified"
wall "invisible bypass actors are counted as not verified" "-- 0 failed, 2 not verified" "printf '{}' > \"$api/repos/o/r/rulesets/1.json\""
wall "an unreadable repository is counted, not passed" "-- 0 failed, 2 not verified" "printf '[]' > \"$api/repos/o/r.json\""
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
  if grep -qE -- "$want" <<<"$out"; then ok "$desc"
  else bad "$desc (expected /$want/)"; grep -E 'FAIL|SKIP|WARN|merge|bypass|failed' <<<"$out" | sed 's/^/        /'; fi
}
M=(--merge-ruleset "$root/ruleset-merge.json")
merge_wall "the merge ruleset in its shape passes" '^  PASS  ruleset 2: the merge is reserved to the repository admin' "" "${M[@]}"
merge_wall "the merge ruleset's admin bypass is not a bypass FAIL" '^-- 0 failed' "" "${M[@]}"
merge_wall "the first ruleset is still held to no bypass actor beside it" '^  PASS  ruleset 1: no bypass actors$' "" "${M[@]}"
merge_wall "a missing merge ruleset is a WARN with the command that adds it" \
  '^  WARN  main: no ruleset reserves the merge to an admin' "printf '%s' \"\$good_rules\" > \"$mapi/repos/o/r/rules/branches/main.json\"" "${M[@]}"
merge_wall "a missing merge ruleset names the upgrade command" \
  'scripts/with-admin-token.sh scripts/create-merge-ruleset.sh o/r' "printf '%s' \"\$good_rules\" > \"$mapi/repos/o/r/rules/branches/main.json\"" "${M[@]}"
merge_wall "a missing merge ruleset fails nothing (consumer CI keeps merging)" \
  '^-- 0 failed' "printf '%s' \"\$good_rules\" > \"$mapi/repos/o/r/rules/branches/main.json\"" "${M[@]}"
# Not in effect is not absent: GitHub leaves a disabled, evaluate-mode or
# mis-scoped ruleset out of the branch's rules, and the repository's list
# still has it.
not_in_effect() { # <jq edit of B> -> shell for merge_wall: B listed but out of the branch's rules
  printf '%s' "printf '%s' \"\$good_rules\" > \"$mapi/repos/o/r/rules/branches/main.json\"; printf '[{\"id\":1,\"source_type\":\"Repository\"},{\"id\":2,\"source_type\":\"Repository\"}]' > \"$mapi/repos/o/r/rulesets?per_page=100.json\"; jq -c '$1' <<<\"\$b_actors\" > \"$mapi/repos/o/r/rulesets/2.json\""
}
merge_wall "a disabled merge ruleset is a FAIL, not the missing WARN" '^  FAIL  main: the merge ruleset is not in effect: ruleset 2 \(disabled' "$(not_in_effect '.enforcement = "disabled"')" "${M[@]}"
merge_wall "a merge ruleset in evaluate mode is a FAIL" '^  FAIL  main: the merge ruleset is not in effect: ruleset 2 \(evaluate' "$(not_in_effect '.enforcement = "evaluate"')" "${M[@]}"
merge_wall "a merge ruleset scoped off the default branch is a FAIL" '^  FAIL  main: the merge ruleset is not in effect: ruleset 2 \(active, branch' "$(not_in_effect '.conditions.ref_name.include = ["refs/heads/other"]')" "${M[@]}"
rm -f "$mapi/repos/o/r/rulesets?per_page=100.json"
merge_wall "a list with no update rule anywhere is still the missing WARN" '^  WARN  main: no ruleset reserves the merge' \
  "printf '%s' \"\$good_rules\" > \"$mapi/repos/o/r/rules/branches/main.json\"; printf '[{\"id\":1,\"source_type\":\"Repository\"}]' > \"$mapi/repos/o/r/rulesets?per_page=100.json\"" "${M[@]}"
merge_wall "a list that cannot be read is not verified, not the missing WARN" '^  SKIP  main: the merge ruleset not verified: no ruleset in effect carries update' \
  "printf '%s' \"\$good_rules\" > \"$mapi/repos/o/r/rules/branches/main.json\"; printf '{}' > \"$mapi/repos/o/r/rulesets?per_page=100.json\"" "${M[@]}"
rm -f "$mapi/repos/o/r/rulesets?per_page=100.json"
merge_wall "a merge ruleset bypassed through a pull request, not exempt, is caught" "^  FAIL  ruleset 2: the merge ruleset's bypass actors are" \
  "printf '{\"bypass_actors\":[{\"actor_id\":5,\"actor_type\":\"RepositoryRole\",\"bypass_mode\":\"pull_request\"}]}' > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
merge_wall "a merge ruleset bypassed always is caught" "^  FAIL  ruleset 2: the merge ruleset's bypass actors are" \
  "printf '{\"bypass_actors\":[{\"actor_id\":5,\"actor_type\":\"RepositoryRole\",\"bypass_mode\":\"always\"}]}' > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
merge_wall "a merge ruleset bypassed by the write role is caught" "^  FAIL  ruleset 2: the merge ruleset's bypass actors are" \
  "printf '{\"bypass_actors\":[{\"actor_id\":4,\"actor_type\":\"RepositoryRole\",\"bypass_mode\":\"exempt\"}]}' > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
merge_wall "a merge ruleset with no bypass actor is caught (nobody could merge)" "^  FAIL  ruleset 2: the merge ruleset's bypass actors are \[\]" \
  "printf '{\"bypass_actors\":[]}' > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
merge_wall "update beside other rules in one ruleset is caught" '^  FAIL  main: ruleset 2 carries \[.deletion., .update.\]' \
  "jq -c '. + [{\"type\":\"deletion\",\"ruleset_source_type\":\"Repository\",\"ruleset_id\":2}]' \"$mapi/repos/o/r/rules/branches/main.json\" > \"$mapi/x\" && mv \"$mapi/x\" \"$mapi/repos/o/r/rules/branches/main.json\"" "${M[@]}"
merge_wall "...and its bypass actor is then a bypass FAIL as well" '^  FAIL  ruleset 2: bypass actors present' \
  "jq -c '. + [{\"type\":\"deletion\",\"ruleset_source_type\":\"Repository\",\"ruleset_id\":2}]' \"$mapi/repos/o/r/rules/branches/main.json\" > \"$mapi/x\" && mv \"$mapi/x\" \"$mapi/repos/o/r/rules/branches/main.json\"" "${M[@]}"
merge_wall "a merge ruleset widened to every branch is caught (it would stop every branch push but the admin's)" "^  FAIL  ruleset 2: the merge ruleset applies to" \
  "jq -c '.conditions.ref_name.include = [\"~ALL\"]' <<<\"\$b_actors\" > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
merge_wall "a merge ruleset with its actor right and its scope unread is not verified, not passed" "^  SKIP  ruleset 2: the merge ruleset's scope \(target, enforcement, conditions\) not read" \
  "jq -c '{bypass_actors}' <<<\"\$b_actors\" > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
merge_wall "...and then no PASS for it" '^-- 0 failed, 2 not verified' \
  "jq -c '{bypass_actors}' <<<\"\$b_actors\" > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
merge_wall "a bypass actor on the first ruleset still fails beside a good merge ruleset" '^  FAIL  ruleset 1: bypass actors present' \
  "printf '%s' \"\$b_actors\" > \"$mapi/repos/o/r/rulesets/1.json\"" "${M[@]}"
merge_wall "unreadable merge bypass actors are SKIP, never PASS" "^  SKIP  ruleset 2: the merge ruleset's bypass actors not visible" \
  "printf '{}' > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
merge_wall "unreadable merge bypass actors are counted as not verified" '^-- 0 failed, 2 not verified' \
  "printf '{}' > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
merge_wall "with the Actions token they are left to /plinth:floor-check" \
  "^  INFO  ruleset 2: the merge ruleset's bypass actors not visible with this token; /plinth:floor-check reads them" \
  "printf '{}' > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}" --actions-token
merge_wall "an update rule from an organization ruleset is not verified, not passed" '^  SKIP  main: the merge ruleset not verified: the update rule comes from a ruleset outside' \
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
merge_wall "an admin login is guidance" '^  INFO  the merge: guidance\. This login is the repository.s admin' "$(as_login true)" "${M[@]}"
merge_wall "an admin login is guidance with the merge ruleset missing too" '^  INFO  the merge: guidance\. This login is the repository.s admin' "$(as_login true); $no_b" "${M[@]}"
merge_wall "a non-admin login with the merge ruleset standing is a boundary" '^  PASS  the merge: boundary\. This login is not the repository.s admin' "$(as_login false)" "${M[@]}"
merge_wall "...and the boundary fails nothing" '^-- 0 failed, 1 not verified$' "$(as_login false)" "${M[@]}"
merge_wall "a non-admin login with no merge ruleset is guidance, not a boundary" '^  INFO  the merge: guidance\. This login is not the repository.s admin, but no ruleset' "$(as_login false); $no_b" "${M[@]}"
merge_wall "a non-admin login with an unreadable merge ruleset is not verified, never a boundary" '^  SKIP  the merge: not verified: this login is not the repository.s admin' \
  "$(as_login false); printf '{}' > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
# As a collaborator's token reads it (#569's run): scope, no actors, and GitHub's answer for this login.
collab_b() { printf '%s' "jq -c 'del(.bypass_actors) + {current_user_can_bypass: \"$1\"}' <<<\"\$b_actors\" > \"$mapi/repos/o/r/rulesets/2.json\""; }
merge_wall "a collaborator that can never bypass the merge ruleset is a boundary, its actors unread" \
  '^  PASS  the merge: boundary\. This login is not the repository.s admin, and GitHub says it can never bypass' "$(as_login false); $(collab_b never)" "${M[@]}"
merge_wall "...while the unread actors stay not verified" "^  SKIP  ruleset 2: the merge ruleset's bypass actors not visible" "$(as_login false); $(collab_b never)" "${M[@]}"
merge_wall "a collaborator GitHub says can bypass it is not a boundary" '^  SKIP  the merge: not verified: this login is not the repository.s admin' "$(as_login false); $(collab_b exempt)" "${M[@]}"
merge_wall "no answer for this login is not a boundary" '^  SKIP  the merge: not verified: this login is not the repository.s admin' \
  "$(as_login false); printf '%s' \"\$(jq -c 'del(.bypass_actors)' <<<\"\$b_actors\")\" > \"$mapi/repos/o/r/rulesets/2.json\"" "${M[@]}"
merge_wall "a read-only login with no merge ruleset is a boundary, not guidance (it cannot merge at all)" \
  '^  PASS  the merge: boundary\. This login cannot write to the repository' "$(as_login false); jq -c '.permissions.push = false' \"$mapi/repos/o/r.json\" > \"$mapi/x\" && mv \"$mapi/x\" \"$mapi/repos/o/r.json\"; $no_b" "${M[@]}"
merge_wall "a non-admin login whose write access cannot be read is not verified" \
  '^  SKIP  the merge: not verified: whether this login can write' "$(as_login false); jq -c 'del(.permissions.push)' \"$mapi/repos/o/r.json\" > \"$mapi/x\" && mv \"$mapi/x\" \"$mapi/repos/o/r.json\"; $no_b" "${M[@]}"
merge_wall "a role that cannot be read is not verified" '^  SKIP  the merge: not verified: whether this login is the repository.s admin could not be read' "$(as_login absent)" "${M[@]}"
merge_wall "...and counted as not verified, not passed" '^-- 0 failed, 2 not verified$' "$(as_login absent)" "${M[@]}"
# Without the branch's rules (#583): the wall's own SKIP or FAIL stands, and
# the line is still printed, from the role alone.
no_rules="printf '[]' > \"$mapi/repos/o/r/rules/branches/main.json\""
bad_rules="printf 'not json' > \"$mapi/repos/o/r/rules/branches/main.json\""
push_false="jq -c '.permissions.push = false' \"$mapi/repos/o/r.json\" > \"$mapi/x\" && mv \"$mapi/x\" \"$mapi/repos/o/r.json\""
merge_wall "no rules: the wall's FAIL stands" '^  FAIL  no rules govern main: the wall is down' "$(as_login false); $no_rules" "${M[@]}"
merge_wall "no rules: an admin login is guidance" '^  INFO  the merge: guidance\. This login is the repository.s admin' "$(as_login true); $no_rules" "${M[@]}"
merge_wall "no rules: a login with write access is guidance" '^  INFO  the merge: guidance\. This login is not the repository.s admin, but no rules govern main' "$(as_login false); $no_rules" "${M[@]}"
merge_wall "no rules: a login without write access is a boundary" '^  PASS  the merge: boundary\. This login cannot write to the repository' "$(as_login false); $push_false; $no_rules" "${M[@]}"
merge_wall "no rules: an unread role is not verified" '^  SKIP  the merge: not verified: whether this login is the repository.s admin could not be read' "$(as_login absent); $no_rules" "${M[@]}"
merge_wall "unreadable rules: the wall's SKIP stands" '^  SKIP  could not read the rules of main \(API error\)' "$(as_login false); $bad_rules" "${M[@]}"
merge_wall "unreadable rules: a login with write access is not verified, never a boundary" '^  SKIP  the merge: not verified: this login is not the repository.s admin, and the rules of main could not be read' "$(as_login false); $bad_rules" "${M[@]}"
merge_wall "unreadable rules: an admin login is guidance" '^  INFO  the merge: guidance\. This login is the repository.s admin' "$(as_login true); $bad_rules" "${M[@]}"
merge_wall "unreadable rules: a login without write access is a boundary" '^  PASS  the merge: boundary\. This login cannot write to the repository' "$(as_login false); $push_false; $bad_rules" "${M[@]}"
merge_wall "unreadable rules: an unread role is not verified" '^  SKIP  the merge: not verified: whether this login is the repository.s admin could not be read' "$(as_login absent); $bad_rules" "${M[@]}"
merge_wall "no rules, with the Actions token: not decided" "^  INFO  the merge: not verified here: the Actions token is not the agent's login" "$(as_login false); $no_rules" "${M[@]}" --actions-token
merge_wall "unreadable rules, with the Actions token: not decided" "^  INFO  the merge: not verified here: the Actions token is not the agent's login" "$(as_login false); $bad_rules" "${M[@]}" --actions-token
merge_wall "with the Actions token it is not decided" "^  INFO  the merge: not verified here: the Actions token is not the agent's login" "$(as_login false)" "${M[@]}" --actions-token
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
merge_wall "without --merge-ruleset the shape is said not compared" '^  INFO  main: the ruleset that reserves the merge to an admin is not compared \(no --merge-ruleset\)$'
merge_wall "without --merge-ruleset its bypass actor is not let through" '^  FAIL  ruleset 2: bypass actors present'
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
wall "CodeQL as a rule, not a name, passes" "CodeQL enforced (rule)" "printf '%s' \"\$rules_rule_only\" > \"$api/repos/o/r/rules/branches/main.json\""
wall "CodeQL as a legacy check name passes" "CodeQL enforced (check name)" "printf '%s' \"\$rules_name_only\" > \"$api/repos/o/r/rules/branches/main.json\""
wall "CodeQL neither rule nor name is caught" "CodeQL not enforced" "printf '%s' \"\$rules_neither\" > \"$api/repos/o/r/rules/branches/main.json\""
wall "a code_scanning rule for another tool is caught" "CodeQL not enforced" "printf '%s' \"\$rules_other_tool\" > \"$api/repos/o/r/rules/branches/main.json\""
# The rule's alert thresholds are the policy: `none` on both is a rule that
# blocks nothing, and it printed `CodeQL enforced (rule)` (#96). The live
# policy is compared with --ruleset; equal or stricter passes, weaker fails,
# a field that cannot be read is not verified, and a check name proves none
# of it.
policy() { # <alerts_threshold> <security_alerts_threshold> -- the fixture with the rule's thresholds replaced
  jq -c "$strip_rule + [\$r]" --argjson r "$(rule_for CodeQL "$1" "$2")" <<<"$good_rules" > "$api/repos/o/r/rules/branches/main.json"
}
wall "both thresholds weakened to none is caught" "FAIL  main: CodeQL alert thresholds weakened: alerts_threshold=none (expected errors), security_alerts_threshold=none (expected high_or_higher)" "policy none none"
wall "the security threshold alone weakened is caught, and named alone" "weakened: security_alerts_threshold=critical (expected high_or_higher)$" "policy errors critical"
wall "the alerts threshold alone weakened is caught, and named alone" "weakened: alerts_threshold=none (expected errors)$" "policy none high_or_higher"
wall "a weakened rule fails the run" "-- 1 failed" "policy none none"
wall "a weakened rule names where to repair it" "https://github.com/o/r/settings/rules/1" "policy none none"
wall "a weakened rule is caught even with the legacy check name also required" "CodeQL alert thresholds weakened" "policy none none"
wall "equal thresholds pass" "PASS  main: CodeQL alert thresholds errors / high_or_higher (expected errors / high_or_higher)" "policy errors high_or_higher"
wall "stricter thresholds pass" "PASS  main: CodeQL alert thresholds errors_and_warnings / medium_or_higher" "policy errors_and_warnings medium_or_higher"
wall "the strictest thresholds pass" "PASS  main: CodeQL alert thresholds all / all" "policy all all"
wall "a missing threshold field is not verified, not passed" "SKIP  main: CodeQL alert thresholds not verified: security_alerts_threshold unreadable" "jq -c '$strip_rule + [{\"type\":\"code_scanning\",\"parameters\":{\"code_scanning_tools\":[{\"tool\":\"CodeQL\",\"alerts_threshold\":\"errors\"}]},\"ruleset_source_type\":\"Repository\",\"ruleset_id\":1}]' <<<\"\$good_rules\" > \"$api/repos/o/r/rules/branches/main.json\""
wall "a missing threshold field is counted as not verified" "-- 0 failed, 2 not verified" "jq -c '$strip_rule + [{\"type\":\"code_scanning\",\"parameters\":{\"code_scanning_tools\":[{\"tool\":\"CodeQL\"}]},\"ruleset_source_type\":\"Repository\",\"ruleset_id\":1}]' <<<\"\$good_rules\" > \"$api/repos/o/r/rules/branches/main.json\""
wall "a threshold value GitHub does not document is not verified" "SKIP  main: CodeQL alert thresholds not verified: alerts_threshold unreadable" "policy severe high_or_higher"
wall "a legacy check name does not claim the thresholds" "SKIP  main: CodeQL alert thresholds not verified: a check name does not set them" "printf '%s' \"\$rules_name_only\" > \"$api/repos/o/r/rules/branches/main.json\""
wall "a legacy check name counts the thresholds as not verified" "-- 0 failed, 2 not verified" "printf '%s' \"\$rules_name_only\" > \"$api/repos/o/r/rules/branches/main.json\""
# Two rulesets both with a CodeQL rule: GitHub enforces every rule, so the
# strictest governs. A second, weaker ruleset is not a weakening.
# shellcheck disable=SC2016  # evaluated by wall(), where $r and $a expand
two='jq -c ". + [\$r]" --argjson r "$(rule_for CodeQL none none 2)" <<<"$good_rules" > "$api/repos/o/r/rules/branches/main.json"; printf "{\"bypass_actors\":[]}" > "$api/repos/o/r/rulesets/2.json"'
wall "a second ruleset with a weaker CodeQL rule is not a weakening" "PASS  main: CodeQL alert thresholds errors / high_or_higher" "$two"
wall "two rulesets, the strict one holds: nothing failed" "-- 0 failed, 1 not verified" "$two"
# shellcheck disable=SC2016  # evaluated by wall(), where $r and $a expand
two_weak='jq -c "$strip_rule + [\$a, \$b]" --argjson a "$(rule_for CodeQL none critical)" --argjson b "$(rule_for CodeQL errors none 2)" <<<"$good_rules" > "$api/repos/o/r/rules/branches/main.json"; printf "{\"bypass_actors\":[]}" > "$api/repos/o/r/rulesets/2.json"'
wall "two weak rulesets do not add up to the policy" "weakened: security_alerts_threshold=critical (expected high_or_higher)$" "$two_weak"
# The rule is only as wide as the languages default setup analyses: enabled
# before detection it analysed `actions` alone while the wall said enforced
# (#120 finding I). Python missing is named with its fix; an unreadable setup
# (the Actions token in CI) is not verified, never a pass.
wall "the languages default setup analyses are reported" "PASS  CodeQL default setup analyses \['actions', 'python'\]"
wall "default setup without python is caught, with the fix" "WARN  CodeQL default setup analyses \['actions'\], not the Python under src/" "printf '{\"state\":\"configured\",\"languages\":[\"actions\"]}' > \"$api/repos/o/r/code-scanning/default-setup.json\""
wall "the fix for a missing language is the one PATCH" "gh api -X PATCH repos/o/r/code-scanning/default-setup -f 'languages\[\]=actions' -f 'languages\[\]=python'" "printf '{\"state\":\"configured\",\"languages\":[\"actions\"]}' > \"$api/repos/o/r/code-scanning/default-setup.json\""
wall "unreadable default setup is SKIP, not a pass" "SKIP  CodeQL default setup languages not verified" "rm \"$api/repos/o/r/code-scanning/default-setup.json\""
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
wall "push protection on is a PASS" "PASS  push protection is on"
wall "push protection off is a WARN" "WARN  push protection is off" "security '$pp_off'"
wall "push protection off carries the call that turns it on, and says what the call needs" \
  "INFO    gh api -X PATCH repos/o/r --input - <<<'{\"security_and_analysis\": {\"secret_scanning\": {\"status\": \"enabled\"}, \"secret_scanning_push_protection\": {\"status\": \"enabled\"}}}'   (needs repository administration; on a private repository, GitHub Secret Protection too)" "security '$pp_off'"
wall "push protection off never fails the floor, and is not counted as not verified" "-- 0 failed, 1 not verified" "security '$pp_off'"
wall "security settings the token does not get are SKIP, not a pass" "SKIP  push protection not verified (this token does not read the repository's security settings" "security"
wall "security settings the token does not get are counted as not verified" "-- 0 failed, 2 not verified" "security"
wall "security settings GitHub answers as null are SKIP" "SKIP  push protection not verified (this token does not read" "security null"
wall "security settings without a push protection entry are SKIP, not read as off" "SKIP  push protection not verified (GitHub reports no push protection status for this repository)" "security '{\"secret_scanning\":{\"status\":\"enabled\"}}'"
wall "a push protection status that is neither enabled nor disabled is SKIP" "SKIP  push protection not verified (GitHub reports no push protection status" "security '{\"secret_scanning_push_protection\":{\"status\":\"paused\"}}'"
wall "security settings that are not an object are SKIP, and not blamed on the token" "SKIP  push protection not verified (GitHub reports no push protection status" "security '[]'"
wall "a push protection entry that is not an object is SKIP, not a crash" "SKIP  push protection not verified (GitHub reports no push protection status" "security '{\"secret_scanning_push_protection\":\"enabled\"}'"
for state in "$pp_off" "" null '{"secret_scanning":{"status":"enabled"}}'; do
  security "$state"
  out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" 2>&1)"
  if [ "$(grep -cE '^  (PASS|WARN|FAIL|SKIP) +push protection' <<<"$out")" = 1 ] && ! grep -qE '^  (PASS|FAIL) +push protection' <<<"$out"; then ok "push protection ${state:-left out} gets one verdict, neither a PASS nor a FAIL"
  else bad "push protection ${state:-left out} got a PASS, a FAIL, or not exactly one verdict"; grep 'push protection' <<<"$out" | sed 's/^/        /'; fi
done
printf '%s' "$good_meta" > "$api/repos/o/r.json"
# The item belongs to the repository, not to the rules: it is reported where no
# rule governs the branch too.
wall "push protection is reported when the wall is down" "PASS  push protection is on" "printf '[]' > \"$api/repos/o/r/rules/branches/main.json\""
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
  if grep -q -- "$2" <<<"$out" && { [[ "$2" != "-- "*"not verified"* ]] || [ "$n" = "$want" ]; }; then ok "$1"
  else bad "$1 (expected '$2', SKIP lines=$n)"; grep -E 'push protection|failed' <<<"$out" | sed 's/^/        /'; fi
  printf '%s' "$good_meta" > "$api/repos/o/r.json"
}
in_ci "--actions-token: security settings the token does not get are an INFO naming who reads them" \
  "INFO  push protection is not read here: the Actions token does not get the repository's security settings; /plinth:floor-check reads it with a person's login"
in_ci "--actions-token: that INFO is not counted as not verified" "-- 0 failed, 1 not verified"
in_ci "--actions-token: null is the same unread answer" "INFO  push protection is not read here" null
in_ci "--actions-token: off is still a WARN when the token does read it" "WARN  push protection is off" "$pp_off"
in_ci "--actions-token: on is still a PASS when the token does read it" "PASS  push protection is on" '{"secret_scanning_push_protection":{"status":"enabled"}}'
in_ci "--actions-token: settings read but with no status are still a SKIP" "SKIP  push protection not verified (GitHub reports no push protection status" '{"secret_scanning":{"status":"enabled"}}'
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
has()  { if grep -qE -- "$2" <<<"$out"; then ok "$1"; else bad "$1 (expected a line matching '$2')"; grep -E 'CodeQL|push protection|failed' <<<"$out" | sed 's/^/        /'; fi; }
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
has   "private, no Code Security, no rule: an INFO names the gap" '^  INFO  main: CodeQL is not expected here: GitHub Code Security is not enabled on this private repository'
has   "private, no Code Security: the INFO names what stands in its place" "^  INFO  main: CodeQL is not expected here.*In its place: \`ci / lint\`'s security rules"
lacks "private, no Code Security, no rule: CodeQL gets neither a FAIL nor a PASS nor a SKIP" '^  (FAIL|PASS|SKIP|WARN) .*(CodeQL|code_scanning)'
has   "private, no Secret Protection: an INFO names the gap and what stands in its place" '^  INFO  push protection is not expected here: GitHub Secret Protection is not enabled on this private repository.*In its place: `ci / secrets`'
lacks "private, no Secret Protection: push protection gets neither a WARN nor a PASS nor a SKIP" '^  (FAIL|PASS|SKIP|WARN) +push protection'
lacks "private, no Secret Protection: no call that would turn on a product that is not there" 'gh api -X PATCH repos/o/r --input'
counted "private without either product: nothing fails, and the two gaps are not counted as not verified" 0 1 0
has   "private: the required check names are expected as on a public repository" '^  PASS  main: all 2 expected checks are required'
has   "private: the other rules are expected as on a public repository" '^  PASS  main: pull_request rule active'
rm "$api/repos/o/r/code-scanning/default-setup.json"
private "$(sec disabled disabled disabled)" "$rules_neither"
printf '%s' "$good_setup" > "$api/repos/o/r/code-scanning/default-setup.json"
counted "private, no Code Security: default setup, which cannot exist there, is not read and not counted" 0 1 0
# The rest of the wall is still a FAIL on a private repository.
private "$(sec disabled disabled disabled)" "$(jq -c 'map(if .type=="required_status_checks" then .parameters.required_status_checks |= map(select(.context!="ci / a")) else . end)' <<<"$rules_neither")"
has   "private: a dropped required check is still a FAIL" "^  FAIL  main: required checks dropped: \['ci / a'\]"
counted "private: a dropped required check still fails the run" 1 1 1
# With the licence, a missing rule is the defect it is on a public repository.
for key in code_security advanced_security; do
  private "$(sec enabled enabled enabled "$key")" "$rules_neither"
  has     "private, $key enabled, no rule: FAIL, as for a public repository" '^  FAIL  main: CodeQL not enforced: no code_scanning rule for CodeQL and no CodeQL check name'
  counted "private, $key enabled, no rule: the run fails" 1 1 1
done
private '{"code_security":{"status":"disabled"},"advanced_security":{"status":"enabled"}}' "$rules_neither"
has   "private, one licence off and the other on: on is what counts, the missing rule is a FAIL" '^  FAIL  main: CodeQL not enforced'
private "$(sec enabled enabled enabled)" "$rules_other_tool"
has   "private with Code Security: a code_scanning rule for another tool is still a FAIL" '^  FAIL  main: CodeQL not enforced'
private "$(sec enabled enabled enabled)" "$good_rules"
has   "private with Code Security and the rule: PASS" '^  PASS  main: CodeQL enforced \(rule\)'
has   "private with Secret Protection and push protection on: PASS" '^  PASS  push protection is on'
counted "private with both products and the whole wall: as an intact public wall" 0 1 0
# A licence state the API does not answer is not verified, never a pass and
# never the gap line: the gap is said only where GitHub said `disabled`.
unread_codeql() { # <description> <json for security_and_analysis, or nothing> <reason in the SKIP>
  private "$2" "$rules_neither"
  has   "$1: CodeQL is not verified" "^  SKIP  main: CodeQL not verified: no code_scanning rule for CodeQL and no CodeQL check name.*\($3"
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
has   "private, unread security settings, the rule present: PASS from the rule" '^  PASS  main: CodeQL enforced \(rule\)'
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
has     "--actions-token, private, no rule: an INFO names the run that judges the licence state" '^  INFO  main: CodeQL is not judged here: no code_scanning rule for CodeQL and no CodeQL check name.*The licence state is judged when /plinth:floor-check is run with a login that administers the repository'
lacks   "--actions-token, private, no rule: CodeQL gets no PASS, FAIL, SKIP or gap line" '^  (PASS|FAIL|SKIP|WARN) .*CodeQL (enforced|not enforced|not verified)|CodeQL is not expected here'
has     "--actions-token, private: push protection is still the INFO naming who reads it" '^  INFO  push protection is not read here'
counted "--actions-token, private, no rule: outside the not-verified count, exit 0" 0 1 0
private null "$rules_neither" --actions-token
has     "--actions-token, private, null security settings: the same unread answer" '^  INFO  main: CodeQL is not judged here'
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
in_v    "--verdicts: a SKIP keeps its own why and says what confirms it" '^not yet confirmed: .*not verified.*; a run that can read it confirms it$'
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
has     "--actions-token, private, no rule, default setup unreadable: an INFO left to /plinth:floor-check (#441)" '^  INFO  CodeQL default setup languages not read here'
has     "--actions-token, private, no rule, default setup unreadable: three reads left to /plinth:floor-check" '^-- 0 failed, 1 not verified, 3 left to /plinth:floor-check$'
# What the token did read is judged with the flag as without it.
private "$(sec enabled enabled enabled)" "$rules_neither" --actions-token
has     "--actions-token, private, Code Security read as enabled, no rule: still a FAIL" '^  FAIL  main: CodeQL not enforced'
counted "--actions-token, private, Code Security read as enabled, no rule: the run fails" 1 1 1
private "$(sec disabled disabled disabled)" "$rules_neither" --actions-token
has     "--actions-token, private, Code Security read as disabled: still the gap line" '^  INFO  main: CodeQL is not expected here'
private "$(sec - enabled enabled)" "$rules_neither" --actions-token
has     "--actions-token, private, settings read but no Code Security status: still a SKIP" '^  SKIP  main: CodeQL not verified: no code_scanning rule.*GitHub reports no Code Security status'
counted "--actions-token, private, settings read but no Code Security status: still counted" 0 2 0
private "" "$good_rules" --actions-token
has     "--actions-token, private, the rule present: PASS from the rule" '^  PASS  main: CodeQL enforced \(rule\)'
# A public repository is not relaxed by the flag: the missing rule fails in CI as before.
printf '{%s}' "$repo_meta" > "$api/repos/o/r.json"; printf '%s' "$rules_neither" > "$api/repos/o/r/rules/branches/main.json"
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" --actions-token 2>&1)"; rc=$?
printf '%s' "$good_meta" > "$api/repos/o/r.json"; printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"
has     "--actions-token, not private, unread settings, no rule: FAIL, as before" '^  FAIL  main: CodeQL not enforced'
lacks   "--actions-token, not private: no line that defers the judgement" 'CodeQL is not judged here'
counted "--actions-token, not private, no rule: the run fails" 1 1 1
# Push protection on a private repository: expected only with Secret Protection.
private "$(sec enabled enabled disabled)" "$good_rules"
has   "private with Secret Protection, push protection off: WARN, as for a public repository" '^  WARN  push protection is off'
has   "private with Secret Protection, push protection off: the call that turns it on" "^  INFO    gh api -X PATCH repos/o/r --input - <<<'"
private "$(sec enabled disabled -)" "$good_rules"
has   "private, no Secret Protection, no push protection entry: the gap, from the licence GitHub did answer" '^  INFO  push protection is not expected here'
counted "private, no Secret Protection, no push protection entry: not counted as not verified" 0 1 0
private "$(sec enabled - disabled)" "$good_rules"
has   "private, push protection off and no secret scanning status: not verified" '^  SKIP  push protection not verified \(it is off, and GitHub reports no secret scanning status for this private repository'
lacks "private, push protection off and no secret scanning status: neither a WARN nor a PASS nor the gap line" '^  (WARN|PASS) +push protection|push protection is not expected here'
private "$(sec enabled disabled enabled)" "$good_rules"
has   "private, push protection answered on: PASS, whatever the secret scanning status says" '^  PASS  push protection is on'
# Public repositories: read as before. `private` false, absent or not a
# boolean never relaxes anything, whatever the licence entries say.
public() { # <description> <json fragment for the private key, or nothing>
  printf '{%s%s,"security_and_analysis":%s}' "$repo_meta" "${2:+,$2}" "$(sec disabled disabled disabled)" > "$api/repos/o/r.json"
  printf '%s' "$rules_neither" > "$api/repos/o/r/rules/branches/main.json"
  out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" --expect-checks "ci / a, ci / b" 2>&1)"; rc=$?
  printf '%s' "$good_meta" > "$api/repos/o/r.json"; printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"
  has     "$1, no rule: FAIL" '^  FAIL  main: CodeQL not enforced: no code_scanning rule for CodeQL and no CodeQL check name'
  has     "$1, push protection off: WARN" '^  WARN  push protection is off'
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
has     "--actions-token: unread bypass actors are an INFO naming who reads them" '^  INFO  ruleset 1: bypass actors not visible with this token; /plinth:floor-check reads them with a login that administers the repository$'
has     "--actions-token: unread default setup languages are an INFO naming who reads them" '^  INFO  CodeQL default setup languages not read here: the Actions token cannot read code-scanning/default-setup; /plinth:floor-check reads them with a login that administers the repository$'
has     "--actions-token: unread squash settings are an INFO naming who reads them" '^  INFO  squash commit settings not visible with this token; /plinth:floor-check reads them with a login that administers the repository$'
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
if grep -q "FAIL.*bypass actors present" <<<"$out" && ! grep -q "bypass actors not visible" <<<"$out"; then ok "the API is read through gh when it is installed (bypass actors seen, 404 is absent)"
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
  || grep -q "WARN  labels the door creates that are missing: wayfinder:task, spec" <<<"$out"
then ok "the two missing labels are named, and only those"
else bad "missing labels"; printf '%s\n' "$out" | grep -i label | sed 's/^/        /'; fi
if grep -q "INFO    gh label create spec --repo o/r --color 0e8a16" <<<"$out"
then ok "each missing label carries the one command that creates it"
else bad "no fix line"; printf '%s\n' "$out" | grep -i "label create" | sed 's/^/        /'; fi
if ! grep -q "FAIL.*label" <<<"$out"; then ok "a missing label is never a FAIL"
else bad "a missing label produced a FAIL"; fi
# Every read answered (wall, bypass actors, labels): nothing is counted. A count
# that includes a passed item is the defect in the other direction.
if grep -qx -- "-- 0 failed, 0 not verified" <<<"$out" && ! grep -q '^  SKIP ' <<<"$out"; then ok "a run whose every read was answered counts 0 not verified, and says so"
else bad "a fully read run still counts something as not verified"; printf '%s\n' "$out" | grep -E 'SKIP|failed' | sed 's/^/        /'; fi
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
if [ "$rc" = 0 ] && grep -q "SKIP.*sandbox not verified" <<<"$out" && ! grep -qE "(WARN|FAIL).*sandbox" <<<"$out"
then ok "--sandbox: an unset key is not verified, not reported off, and the floor still passes"; else bad "--sandbox unset"; printf '%s\n' "$out" | grep -E 'sandbox|failed' | sed 's/^/        /'; fi
under="$(sed -n '/SKIP.*sandbox not verified/,/^--/p' <<<"$out" | grep '^  INFO    ')"
for want in 'Read(~/.config/gh/\*\*)' 'anthropics/claude-code#95135' 'anthropics/claude-code#67105' 'uvx --from copier copier' 'macOS' 'Linux, WSL2 and native Windows: not measured' '\.env'; do
  grep -q -- "$want" <<<"$under" || { bad "--sandbox: the lines under the SKIP do not name $want"; printf '%s\n' "$under" | sed 's/^/        /'; }
done
grep -q 'Read(~/.config/gh' <<<"$under" && ok "--sandbox: the SKIP names the gh collision, uvx, the upstream issues and the macOS scope"
rm -f "$work/conf/settings.json"
out="$(CLAUDE_CONFIG_DIR="$work/conf" python3 "$checker" --root "$good" --no-network --sandbox 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q "SKIP.*sandbox not verified" <<<"$out"; then ok "--sandbox: no settings file at all is not verified either"; else bad "--sandbox no file"; printf '%s\n' "$out" | grep sandbox | sed 's/^/        /'; fi
printf '{"sandbox":{"enabled":true}}' > "$work/conf/settings.local.json"
out="$(CLAUDE_CONFIG_DIR="$work/conf" python3 "$checker" --root "$good" --no-network --sandbox 2>&1)"
# On is a fact, not a PASS: on macOS it is the state in which gh and the door stop.
if grep -q "^  INFO  sandbox.enabled is true in .*settings.local.json" <<<"$out" && ! grep -qE "(PASS|SKIP|WARN).*sandbox" <<<"$out" \
   && grep -q 'Read(~/.config/gh' <<<"$out" && grep -q 'uvx --from copier copier' <<<"$out"
then ok "--sandbox: sandbox.enabled true is an INFO, and the measured macOS lines still follow it"; else bad "--sandbox on"; printf '%s\n' "$out" | grep -iE 'sandbox|gh|uvx' | sed 's/^/        /'; fi

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
if [ "$rc" = 0 ] && grep -q "INFO  gh stores 1 account for github.com: me" <<<"$out" && grep -q "INFO  git asks only gh for github.com" <<<"$out" \
   && grep -q "INFO  no github.com login in" <<<"$out" && grep -q "SKIP  SSH keys not verified here" <<<"$out" && ! grep -q WARN <<<"$out" \
   && [ "$(grep -c "no other credential found by these rules; best effort, see the guide's list" <<<"$out")" = 3 ] \
   && ! grep -qE "PASS  (gh stores|git asks|no github.com login)" <<<"$out"
then ok "--credentials: nothing found is an INFO with the best-effort note, never a PASS; SSH still not verified"; else bad "--credentials clean"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# A variable that points gh or git elsewhere hides the default configuration,
# and the agent can unset it: not verified, named, never read as clean.
for var in GH_CONFIG_DIR XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS; do
  out="$(credrun "$var=$cred/elsewhere" FAKE_GH="$one")"
  grep -q "SKIP  $var is set" <<<"$out" || { bad "--credentials: $var set is not reported"; printf '%s\n' "$out" | sed 's/^/        /'; }
done
# Exported but empty still hides the default file: `GIT_CONFIG_GLOBAL=` reads no global config.
for var in GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GH_CONFIG_DIR; do
  out="$(credrun "$var=" FAKE_GH="$one")"
  grep -q "SKIP  $var is set" <<<"$out" || { bad "--credentials: $var set but empty is not reported"; printf '%s\n' "$out" | grep SKIP | sed 's/^/        /'; }
done
out="$(credrun FAKE_GH="$one")"
grep -q "SKIP  GIT_CONFIG_NOSYSTEM is set" <<<"$out" && ! grep -qE "SKIP  (GH_CONFIG_DIR|GIT_CONFIG_GLOBAL) is set" <<<"$out" \
  && ok "--credentials: GH_CONFIG_DIR, XDG_CONFIG_HOME and the GIT_CONFIG_* overrides are each not verified; unset, not named" \
  || { bad "--credentials masking variables"; printf '%s\n' "$out" | grep SKIP | sed 's/^/        /'; }
out="$(credrun FAKE_GH="$two")"
# The checker cannot tell which account holds the agent's token, active or
# not: the repair names every account and leaves the choice to the person.
if grep -q "WARN  gh stores 2 accounts for github.com (active: me)" <<<"$out" && grep -q "gh auth logout --hostname github.com --user other" <<<"$out" \
   && grep -q "gh auth logout --hostname github.com --user me" <<<"$out" && grep -q "keep only the account that holds the agent's token" <<<"$out"
then ok "--credentials: a second stored gh account is a WARN, with a logout line for every account and the choice left to the person"; else bad "--credentials two accounts"; printf '%s\n' "$out" | grep -i gh | sed 's/^/        /'; fi
rm -f "$cred/saw"
out="$(credrun GH_TOKEN=secret-value-1 FAKE_GH="$one")"
if grep -q "WARN  GH_TOKEN is set" <<<"$out" && ! grep -q "secret-value-1" <<<"$out" && [ ! -e "$cred/saw" ] && grep -q "gh stores 1 account" <<<"$out"
then ok "--credentials: GH_TOKEN is named, not printed, and the stored accounts are read without it"; else bad "--credentials GH_TOKEN"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# With an environment token, even one stored account is another credential:
# the agent can unset the variable, and the stored login answers.
out="$(credrun GH_TOKEN=secret-value-9 FAKE_GH="$one")"
grep -q "WARN  gh stores 1 account for github.com (me) besides GH_TOKEN" <<<"$out" && ! grep -q "INFO  gh stores" <<<"$out" \
  && ok "--credentials: one stored account beside GH_TOKEN is a WARN" || { bad "--credentials env token plus one stored"; printf '%s\n' "$out" | grep -i gh | sed 's/^/        /'; }
out="$(credrun GH_TOKEN=secret-value-9 FAKE_GH='{"hosts":{}}')"
grep -q "INFO  gh stores no accounts for github.com" <<<"$out" && ok "--credentials: GH_TOKEN with nothing stored leaves the stored item an INFO" || { bad "--credentials env token, none stored"; printf '%s\n' "$out" | grep -i gh | sed 's/^/        /'; }
out="$(credrun GITHUB_TOKEN=secret-value-5 FAKE_GH="$one")"
grep -q "WARN  GITHUB_TOKEN is set" <<<"$out" && ! grep -q "secret-value-5" <<<"$out" \
  && ok "--credentials: GITHUB_TOKEN is named, not printed" || { bad "--credentials GITHUB_TOKEN"; printf '%s\n' "$out" | sed 's/^/        /'; }
skipped=0
for bad_gh in "" "not json" '{"nohosts":1}'; do
  out="$(credrun FAKE_GH="$bad_gh")"
  if grep -q "SKIP  accounts stored in gh not verified" <<<"$out" && ! grep -q "INFO  gh stores" <<<"$out"; then skipped=$((skipped+1))
  else bad "--credentials: gh answering '${bad_gh:-(failure)}' is not a SKIP"; printf '%s\n' "$out" | grep gh | sed 's/^/        /'; fi
done
[ "$skipped" = 3 ] && ok "--credentials: gh failing, or answering what is not its JSON, is not verified"
# Helpers: the macOS default with no empty helper before gh's; one listed after
# gh's; an inline `!` helper, named without its text; other hosts and plain
# http ignored; an empty helper for a path on github.com clears nothing.
printf '[credential]\n\thelper = osxkeychain\n[credential "https://github.com"]\n\thelper = !gh auth git-credential\n' > "$cred/gitconfig"
out="$(credrun FAKE_GH="$one")"
grep -q "WARN  git has 1 credential helper for github.com besides gh's: osxkeychain" <<<"$out" \
  && ok "--credentials: osxkeychain not cleared before gh's helper is a WARN" || { bad "--credentials osxkeychain"; printf '%s\n' "$out" | grep -i helper | sed 's/^/        /'; }
printf '[credential "https://github.com"]\n\thelper =\n\thelper = !gh auth git-credential\n\thelper = store --file /x\n[credential "https://example.com"]\n\thelper = cache\n[credential "http://github.com"]\n\thelper = cache\n[credential "https://github.com/o/r"]\n\thelper =\n\thelper = !f() { echo password=tok-value-2; }; f\n' > "$cred/gitconfig"
out="$(credrun FAKE_GH="$one")"
if grep -q "WARN  git has 2 credential helpers for github.com besides gh's: store, a \`!\` shell command" <<<"$out" && ! grep -q "tok-value-2\|cache" <<<"$out"
then ok "--credentials: a helper after gh's and one for a path on github.com are WARNs, other hosts are not, and no helper text is printed"; else bad "--credentials helpers"; printf '%s\n' "$out" | grep -i helper | sed 's/^/        /'; fi
# gh 2.101.0's `gh auth setup-git`, run from a path with a space, single-quotes it.
printf '[credential "https://github.com"]\n\thelper =\n\thelper = !'"'"'/Applications/my tools/gh'"'"' auth git-credential\n' > "$cred/gitconfig"
out="$(credrun FAKE_GH="$one")"
grep -q "INFO  git asks only gh for github.com" <<<"$out" && ok "--credentials: gh's helper under a quoted path with a space is gh's" \
  || { bad "--credentials quoted gh path"; printf '%s\n' "$out" | grep -i helper | sed 's/^/        /'; }
# Without `!`, git runs `git credential-gh auth git-credential`, not gh.
printf '[credential "https://github.com"]\n\thelper =\n\thelper = gh auth git-credential\n' > "$cred/gitconfig"
out="$(credrun FAKE_GH="$one")"
grep -q "WARN  git has 1 credential helper for github.com besides gh's: gh" <<<"$out" && ! grep -q "INFO  git asks" <<<"$out" \
  && ok "--credentials: gh auth git-credential without \`!\` is another helper (git-credential-gh)" || { bad "--credentials helper without !"; printf '%s\n' "$out" | grep -i helper | sed 's/^/        /'; }
# A shell command glued before gh's path runs first: not gh's helper either.
for h in '!/tmp/steal;/usr/bin/gh auth git-credential' '!/tmp/steal&&/usr/bin/gh auth git-credential' '!$(/tmp/steal)/gh auth git-credential' '!/a|/usr/bin/gh auth git-credential'; do
  printf '[credential "https://github.com"]\n\thelper =\n\thelper = "%s"\n' "$h" > "$cred/gitconfig"
  out="$(credrun FAKE_GH="$one")"
  grep -q "WARN  git has 1 credential helper for github.com besides gh's" <<<"$out" && ! grep -q "INFO  git asks" <<<"$out" \
    || { bad "--credentials: '$h' passed as gh's helper"; printf '%s\n' "$out" | grep -i helper | sed 's/^/        /'; }
done
grep -q "WARN  git has 1 credential helper" <<<"$out" && ok "--credentials: a shell command before gh's path (; && \$() |) is another helper"
# A newline is a command separator to the shell: `!/usr/bin/gh` then `auth ...` runs two commands.
printf '[credential "https://github.com"]\n\thelper =\n\thelper = "!/usr/bin/gh\\nauth git-credential"\n' > "$cred/gitconfig"
out="$(credrun FAKE_GH="$one")"
grep -q "WARN  git has 1 credential helper for github.com besides gh's" <<<"$out" && ! grep -q "INFO  git asks" <<<"$out" \
  && ok "--credentials: a newline inside gh's helper line makes it another helper" || { bad "--credentials newline in helper"; printf '%s\n' "$out" | grep -i helper | sed 's/^/        /'; }
# A `!` helper that calls gh after answering itself is not gh's helper.
printf '[credential "https://github.com"]\n\thelper =\n\thelper = !f() { echo password=tok-value-6; gh auth git-credential "$@"; }; f\n' > "$cred/gitconfig"
out="$(credrun FAKE_GH="$one")"
grep -q "WARN  git has 1 credential helper for github.com besides gh's: a \`!\` shell command" <<<"$out" && ! grep -q "INFO  git asks" <<<"$out" \
  && ok "--credentials: a shell helper that merely calls gh's is still another helper" || { bad "--credentials wrapped gh helper"; printf '%s\n' "$out" | grep -i helper | sed 's/^/        /'; }
printf '[http "https://github.com/"]\n\textraHeader = Authorization: basic tok-value-3\n' > "$cred/gitconfig"
out="$(credrun FAKE_GH="$one")"
grep -q "WARN  git config sends an Authorization header to github.com" <<<"$out" && ! grep -q "tok-value-3" <<<"$out" \
  && ok "--credentials: an Authorization extraHeader for github.com is a WARN, its value unprinted" || { bad "--credentials extraHeader"; printf '%s\n' "$out" | sed 's/^/        /'; }
printf 'machine github.com login me password tok-value-4\n' > "$cred/home/.netrc"
out="$(credrun FAKE_GH="$one")"
grep -q "WARN  .*\.netrc holds a login for github.com" <<<"$out" && ! grep -q "tok-value-4" <<<"$out" \
  && ok "--credentials: a github.com login in ~/.netrc is a WARN, its value unprinted" || { bad "--credentials netrc"; printf '%s\n' "$out" | grep netrc | sed 's/^/        /'; }
# curl reads a quoted token (8.5.0 sent a quoted github.com entry's login):
# the quotes are not part of the name. One it cannot tokenise is not verified.
printf 'machine "github.com" login me password "tok value-8"\n' > "$cred/home/.netrc"
out="$(credrun FAKE_GH="$one")"
grep -q "WARN  .*\.netrc holds a login for github.com" <<<"$out" && ! grep -q "tok value-8" <<<"$out" \
  && ok "--credentials: a quoted github.com in ~/.netrc is a WARN" || { bad "--credentials netrc quoted"; printf '%s\n' "$out" | grep netrc | sed 's/^/        /'; }
printf 'machine GitHub.COM login me password x\n' > "$cred/home/.netrc"
out="$(credrun FAKE_GH="$one")"
grep -q "WARN  .*\.netrc holds a login for github.com" <<<"$out" \
  && ok "--credentials: github.com in ~/.netrc in any case is a WARN" || { bad "--credentials netrc case"; printf '%s\n' "$out" | grep netrc | sed 's/^/        /'; }
printf 'machine "github.com login me password x\n' > "$cred/home/.netrc"
out="$(credrun FAKE_GH="$one")"
grep -q "SKIP  .*\.netrc not verified" <<<"$out" && ! grep -q "INFO  no github.com login" <<<"$out" \
  && ok "--credentials: an unterminated quote in ~/.netrc is not verified" || { bad "--credentials netrc unterminated"; printf '%s\n' "$out" | grep netrc | sed 's/^/        /'; }
printf '# machine github.com login old password tok-value-7\nmachine example.com login me password x\n' > "$cred/home/.netrc"
out="$(credrun FAKE_GH="$one")"
grep -q "INFO  no github.com login in" <<<"$out" && ok "--credentials: a .netrc for another host, and a commented github.com line, are not a WARN" || bad "--credentials netrc other host or comment"
if [ "$(id -u)" != 0 ]; then
  chmod 000 "$cred/home/.netrc"; out="$(credrun FAKE_GH="$one")"; chmod 600 "$cred/home/.netrc"
  grep -q "SKIP  .*\.netrc not verified" <<<"$out" && ok "--credentials: an unreadable .netrc is not verified" || { bad "--credentials netrc unreadable"; printf '%s\n' "$out" | grep netrc | sed 's/^/        /'; }
fi
printf '#!/bin/sh\nexit 128\n' > "$cred/bin/git"; chmod +x "$cred/bin/git"
out="$(credrun FAKE_GH="$one")"; rm -f "$cred/bin/git"
grep -q "SKIP  git credential helpers not verified" <<<"$out" && ! grep -q "INFO  git asks" <<<"$out" \
  && ok "--credentials: git config failing is not verified" || { bad "--credentials git failing"; printf '%s\n' "$out" | grep -i git | sed 's/^/        /'; }
# git matches a credential.<url> entry on username and port too (#349): one
# scoped to either does not apply to a plain https://github.com push, so its
# empty value clears nothing; one naming a helper is still counted. :443 is
# the default port and applies.
for scope in 'https://restricted@github.com' 'https://github.com:8443'; do
  printf '[credential]\n\thelper = store\n[credential "%s"]\n\thelper =\n[credential "https://github.com"]\n\thelper = !gh auth git-credential\n' "$scope" > "$cred/gitconfig"
  out="$(credrun FAKE_GH="$one")"
  grep -q "WARN  git has 1 credential helper for github.com besides gh's: store" <<<"$out" && ! grep -q "INFO  git asks" <<<"$out" \
    || { bad "--credentials: an empty helper under $scope cleared the list"; printf '%s\n' "$out" | grep -i helper | sed 's/^/        /'; }
done
grep -q "WARN  git has 1 credential helper" <<<"$out" && ok "--credentials: an empty helper scoped by a username or a port does not clear the list"
printf '[credential]\n\thelper = store\n[credential "https://github.com:443"]\n\thelper =\n\thelper = !gh auth git-credential\n[credential "https://me@github.com"]\n\thelper = cache\n' > "$cred/gitconfig"
out="$(credrun FAKE_GH="$one")"
grep -q "WARN  git has 1 credential helper for github.com besides gh's: cache" <<<"$out" \
  && ok "--credentials: an empty helper at :443 clears the list, and a username-scoped helper is counted" || { bad "--credentials :443 and username helper"; printf '%s\n' "$out" | grep -i helper | sed 's/^/        /'; }
# A subsection URL urlsplit rejects is named (userinfo hidden) and not
# verified; the rest of the report and the summary still print.
printf '[credential "https://u:tok-value-10@[bad"]\n\thelper = cache\n[credential "https://github.com"]\n\thelper =\n\thelper = !gh auth git-credential\n' > "$cred/gitconfig"
out="$(credrun FAKE_GH="$one")"; rc=$?
if [ "$rc" = 0 ] && grep -q 'SKIP  git config \[credential "…@\[bad"\] not verified' <<<"$out" && ! grep -q "tok-value-10\|Traceback" <<<"$out" \
   && grep -q "INFO  no github.com login in" <<<"$out" && grep -q "SKIP  SSH keys not verified here" <<<"$out" && grep -q "^-- [0-9]* failed, [0-9]* not verified" <<<"$out"
then ok "--credentials: a credential subsection URL that cannot be parsed is a SKIP naming it, and the run goes on"; else bad "--credentials unparseable subsection"; printf '%s\n' "$out" | tail -n 12 | sed 's/^/        /'; fi
for sub in 'user:tok-value-12@[bad' 'https://u:tok-value-13@github.com:abc' 'https://github.com:abc'; do
  printf '[credential "%s"]\n\thelper = cache\n' "$sub" > "$cred/gitconfig"
  out="$(credrun FAKE_GH="$one")"; rc=$?
  [ "$rc" = 0 ] && grep -q "SKIP  git config \[credential \"\(…@\[bad\|…@github.com:abc\|https://github.com:abc\)\"\] not verified" <<<"$out" \
    && ! grep -q "tok-value-1[23]" <<<"$out" && grep -q "^-- [0-9]* failed" <<<"$out" \
    || { bad "--credentials: unparseable '$sub'"; printf '%s\n' "$out" | grep -v PASS | tail -n 8 | sed 's/^/        /'; }
done
grep -q "SKIP  git config" <<<"$out" && ok "--credentials: an unparseable subsection, with or without a scheme or a user, is a SKIP that prints no user or password"
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
grep -q "INFO  no github.com login in" <<<"$out" && ok "--credentials: \`default\` as a .netrc value is not a default entry" \
  || { bad "--credentials netrc default as value"; printf '%s\n' "$out" | grep netrc | sed 's/^/        /'; }
printf 'machine example.com login me password x\ndefault\n  login me password tok-value-11\n' > "$cred/home/.netrc"
out="$(credrun FAKE_GH="$one")"
grep -q "WARN  .*\.netrc holds a login for github.com" <<<"$out" && ! grep -q "tok-value-11" <<<"$out" \
  && ok "--credentials: \`default\` where a keyword stands is a default entry" || { bad "--credentials netrc default entry"; printf '%s\n' "$out" | grep netrc | sed 's/^/        /'; }
for n in 'machine example.com login me stray x' 'machine example.com login' 'login me machine example.com' 'machine example.com macdef m'; do
  printf '%s\n' "$n" > "$cred/home/.netrc"
  out="$(credrun FAKE_GH="$one")"
  grep -q "SKIP  .*\.netrc not verified" <<<"$out" && ! grep -q "INFO  no github.com login" <<<"$out" \
    || { bad "--credentials: .netrc '$n' was placed"; printf '%s\n' "$out" | grep netrc | sed 's/^/        /'; }
done
grep -q "SKIP  .*\.netrc not verified" <<<"$out" && ok "--credentials: a .netrc token sequence that cannot be placed is not verified"
rm -f "$cred/home/.netrc"
# GIT_CONFIG makes git read that file instead of the repository's .git/config.
for v in "$cred/elsewhere" ''; do
  out="$(credrun GIT_CONFIG="$v" FAKE_GH="$one")"
  grep -q "SKIP  GIT_CONFIG is set" <<<"$out" || { bad "--credentials: GIT_CONFIG='$v' is not named"; printf '%s\n' "$out" | grep SKIP | sed 's/^/        /'; }
done
grep -q "SKIP  GIT_CONFIG is set" <<<"$out" && ok "--credentials: GIT_CONFIG, set or empty, is named as hiding a configuration"

# --credentials also names a production database URL within the agent's reach
# (#648): this environment, .env* files under --root (tracked or not), and the
# env of .claude/settings*.json, the repository's and the user's. Every value
# below is fake; `FAKE648` (a password) and `acme648` (a host) must never be
# printed. Each run gets an empty environment besides what the case sets, and
# a PATH whose gh fails at once (the gh item is not this block's question).
dbr="$work/dbroot"; dbu="$work/dbuser"
dbreset() { rm -rf "$dbr" "$dbu"; cp -R "$good" "$dbr"; mkdir -p "$dbu"; }
dbrun() {   # extra env assignments as arguments; prints the checker's output
  env -i PATH="$cred/bin:$PATH" HOME="$cred/home" GIT_CONFIG_NOSYSTEM=1 CLAUDE_CONFIG_DIR="$dbu" FAKE_GH_SAW="$cred/saw" "$@" \
    python3 "$checker" --root "$dbr" --no-network --credentials 2>&1
}
db_lines() { grep -i "database" <<<"$out"; }
leaks() { grep -qE "FAKE648|acme648" <<<"$out"; }
prod='postgres://app:FAKE648@db.acme648.net:5432/app'
dbquiet() { # <description>: no database WARN or SKIP, the limit INFO, no PASS, no value
  if ! grep -qE "(WARN|SKIP|PASS)  .*database" <<<"$out" && grep -q "INFO  no production database URL found in this environment" <<<"$out" \
     && grep -q "best effort: shell profile files, other files and schemes other than postgres:// and postgresql:// are not read" <<<"$out" && ! leaks
  then ok "$1"; else bad "$1"; db_lines | sed 's/^/        /'; fi
}
dbwarn() { # <description> <ERE for the WARN's place>: a WARN naming the place, its fix line, no limit INFO, no value
  if grep -qE "WARN  a production database URL is within the agent's reach: $2" <<<"$out" \
     && grep -q "the template's SQLite default" <<<"$out" && ! grep -q "INFO  no production database URL found" <<<"$out" && ! leaks
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
dbwarn "--credentials, database: DATABASE_URL in this environment is a WARN naming the variable" "DATABASE_URL in this environment$"
[ "$rc" = 0 ] && grep -q "INFO    remove it where it is set (a shell startup file), then restart Claude Code" <<<"$out" \
  && ok "--credentials, database: a WARN does not fail the run, and the fix says where to remove it" || bad "--credentials, database: exit $rc or the environment fix line"
dbreset; out="$(dbrun REPORTING_DB='POSTGRESQL+psycopg://app:FAKE648@db.acme648.net/app')"
dbwarn "--credentials, database: any variable holding a postgresql+driver URL, in any case, is a WARN" "REPORTING_DB in this environment$"
dbreset; out="$(dbrun DATABASE_URL='postgresql://app:FAKE648@localhost,db.acme648.net:5433/app')"
dbwarn "--credentials, database: a local host beside a remote one is a WARN" "DATABASE_URL in this environment$"
dbreset; out="$(dbrun DATABASE_URL='postgresql://app:FAKE648@127.acme648.net/app')"
dbwarn "--credentials, database: a host name that starts with 127. is not loopback" "DATABASE_URL in this environment$"
dbreset; out="$(dbrun DATABASE_URL='postgresql://app:FAKE648@localhost/app?host=db.acme648.net')"
dbwarn "--credentials, database: a remote host= in the query warns beside a local authority" "DATABASE_URL in this environment$"
dbreset; out="$(dbrun DATABASE_URL='postgresql:///app?host=/var/run/postgresql,db.acme648.net')"
dbwarn "--credentials, database: every host of a comma-separated host= list is judged" "DATABASE_URL in this environment$"
dbreset; out="$(dbrun DATABASE_URL='postgresql://app:FAKE648@/app?hostaddr=203.0.113.5')"
dbwarn "--credentials, database: a remote hostaddr= is a destination, whatever host says" "DATABASE_URL in this environment$"
dbreset; out="$(dbrun DATABASE_URL='postgresql://app:FAKE648@db.acme648.net/app?dbname=test&dbname=production')"
dbwarn "--credentials, database: the last dbname= is the database, as libpq reads it" "DATABASE_URL in this environment$"
dbreset; out="$(dbrun DATABASE_URL='postgresql://app:FAKE648@db.acme648.net/app_test?dbname=prod')"
dbwarn "--credentials, database: a test path beside a dbname= that is not one warns" "DATABASE_URL in this environment$"
dbreset; out="$(dbrun DATABASE_URL='postgresql:///app?service=main')"
dbwarn "--credentials, database: service= takes its host from a file not read, so it warns" "DATABASE_URL in this environment$"
dbreset; out="$(dbrun DATABASE_URL='postgresql://app:FAKE648@db.acme648.net/app?dbname=app_test')"
dbquiet "--credentials, database: a dbname= naming a test database replaces the path"
dbreset; out="$(dbrun DATABASE_URL='postgresql://app:FAKE648@localhost/app?host=localhost&hostaddr=127.0.0.1')"
dbquiet "--credentials, database: a local hostaddr= beside a local host does not warn"
dbreset; out="$(dbrun DATABASE_URL='postgresql://app:FAKE648@[db.acme648.net/app')"
dbwarn "--credentials, database: a URL that cannot be parsed is a WARN, not passed over" "DATABASE_URL in this environment$"
dbreset; printf 'APP_PORT=8000\nDATABASE_URL=%s\n' "$prod" > "$dbr/.env.production"; git -C "$dbr" add .env.production; out="$(dbrun)"
dbwarn "--credentials, database: a tracked .env.production names its file, line and variable" "\.env\.production line 2 \(DATABASE_URL\)$"
grep -q "INFO    delete the line; keep the production URL only in the host's settings" <<<"$out" \
  && ok "--credentials, database: the file's fix line" || bad "--credentials, database: the file's fix line"
dbreset; printf '.env\n' >> "$dbr/.gitignore"; printf 'export DATABASE_URL="%s"\n' "$prod" > "$dbr/.env"; out="$(dbrun)"
dbwarn "--credentials, database: an ignored, untracked .env with export and quotes is a WARN" "\.env line 1 \(DATABASE_URL\)$"
dbreset; mkdir -p "$dbr/apps/web"; printf "DB='%s'\n" "$prod" > "$dbr/apps/web/.env.local"; out="$(dbrun)"
dbwarn "--credentials, database: a .env.local in a subdirectory is a WARN" "apps/web/\.env\.local line 1 \(DB\)$"
dbreset; printf '%s/db=x\n' "$prod" > "$dbr/.env"; out="$(dbrun)"
dbwarn "--credentials, database: a line with no variable name prints only its file and line" "\.env line 1$"
dbreset; printf '{"env":{"DATABASE_URL":"%s"}}\n' "$prod" > "$dbr/.claude/settings.local.json"; out="$(dbrun)"
dbwarn "--credentials, database: the env of the repository's .claude/settings.local.json is a WARN" "DATABASE_URL in the env of \.claude/settings\.local\.json$"
dbreset; python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["env"]={"DATABASE_URL":sys.argv[2]}; json.dump(d,open(p,"w"))' "$dbr/.claude/settings.json" "$prod"; out="$(dbrun)"
dbwarn "--credentials, database: the env of the repository's .claude/settings.json is a WARN" "DATABASE_URL in the env of \.claude/settings\.json$"
dbreset; printf '{"env":{"DATABASE_URL":"%s"}}\n' "$prod" > "$dbu/settings.json"; out="$(dbrun)"
dbwarn "--credentials, database: the env of the user's settings.json is a WARN" "DATABASE_URL in the env of .*/dbuser/settings\.json$"
dbreset; printf '{"env":{"DATABASE_URL":"%s"}}\n' "$prod" > "$dbu/settings.local.json"; out="$(dbrun)"
dbwarn "--credentials, database: the env of the user's settings.local.json is a WARN" "DATABASE_URL in the env of .*/dbuser/settings\.local\.json$"
dbreset; printf '{"env":{"postgres://x:FAKE648@acme648.net/a":"%s"}}\n' "$prod" > "$dbu/settings.json"; out="$(dbrun)"
dbwarn "--credentials, database: an env key that is not a name is not printed" "an entry in the env of .*/dbuser/settings\.json$"
dbreset; printf 'DATABASE_URL=%s\n' "$prod" > "$dbr/.env"; printf '{"env":{"DATABASE_URL":"%s"}}\n' "$prod" > "$dbu/settings.json"; out="$(dbrun DATABASE_URL="$prod")"
[ "$(grep -c "WARN  a production database URL is within the agent's reach" <<<"$out")" = 3 ] && ! leaks \
  && ok "--credentials, database: three places hold it, three WARNs" || { bad "--credentials, database: three places"; db_lines | sed 's/^/        /'; }

# What cannot be read is a SKIP naming it.
dbreset; printf '{"env":' > "$dbu/settings.json"; out="$(dbrun)"
grep -qE "SKIP  .*/dbuser/settings\.json not verified: it could not be read as JSON" <<<"$out" \
  && ok "--credentials, database: unreadable settings JSON is a SKIP" || { bad "--credentials, database: bad JSON"; db_lines | sed 's/^/        /'; }
dbreset; printf '{"env":["%s"]}\n' "$prod" > "$dbu/settings.json"; out="$(dbrun)"
grep -qE "SKIP  .*/dbuser/settings\.json not verified: its env is not an object" <<<"$out" && ! leaks \
  && ok "--credentials, database: an env that is not an object is a SKIP" || { bad "--credentials, database: env list"; db_lines | sed 's/^/        /'; }
if [ "$(id -u)" != 0 ]; then
  dbreset; printf 'DATABASE_URL=%s\n' "$prod" > "$dbr/.env"; chmod 000 "$dbr/.env"; out="$(dbrun)"; chmod 600 "$dbr/.env"
  grep -q "SKIP  .env not verified: it could not be read" <<<"$out" && ! leaks \
    && ok "--credentials, database: an unreadable .env is a SKIP" || { bad "--credentials, database: unreadable .env"; db_lines | sed 's/^/        /'; }
fi
# ci / floor-check never passes --credentials: its own service URLs are not this item's question.
dbreset; out="$(env -i PATH="$PATH" HOME="$cred/home" CLAUDE_CONFIG_DIR="$dbu" DATABASE_URL="$prod" python3 "$checker" --root "$dbr" --no-network 2>&1)"
! grep -qi "database" <<<"$out" && ! leaks && ok "--credentials, database: without --credentials the item does not run" || bad "--credentials, database: ran without --credentials"

# The source of each required check is part of the wall: a required
# `ci / test` with no integration_id is satisfied by a commit status anyone
# with write access can post. The shipped ruleset pins GitHub Actions (15368);
# a live rule that lost or changed that pin is a weakened wall.
wall "a required check with its source pin removed is a FAIL" "accepts a status from any source" \
  "printf '%s' '$(printf '%s' "$good_rules" | sed 's/{"context":"ci \/ a","integration_id":15368}/{"context":"ci \/ a"}/')' > \"\$api/repos/o/r/rules/branches/main.json\""
wall "a required check pinned to another app is a FAIL" "comes from app 999, not 15368" \
  "printf '%s' '$(printf '%s' "$good_rules" | sed 's/"context":"ci \/ b","integration_id":15368/"context":"ci \/ b","integration_id":999/')' > \"\$api/repos/o/r/rules/branches/main.json\""
printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"
wall "the source pins as shipped pass" "required checks come from the expected app (15368)"
# Two active rulesets: GitHub enforces both, so a check is required when
# either requires it and pinned when either pins it.
wall "a check carried by a second ruleset is not dropped" "all 2 expected checks are required" \
  "printf '%s' '$(printf '%s' "$good_rules" | python3 -c 'import json,sys; r=json.load(sys.stdin); rsc=[x for x in r if x["type"]=="required_status_checks"][0]; a=json.loads(json.dumps(rsc)); a["parameters"]["required_status_checks"]=[{"context":"ci / a","integration_id":15368}]; a["ruleset_id"]=2; b=json.loads(json.dumps(rsc)); b["parameters"]["required_status_checks"]=[c for c in b["parameters"]["required_status_checks"] if c["context"]!="ci / a"]; print(json.dumps([x for x in r if x["type"]!="required_status_checks"]+[b,a]))')' > \"\$api/repos/o/r/rules/branches/main.json\""
wall "an unpinned duplicate beside a pinned one is not a source FAIL" "required checks come from the expected app (15368)" \
  "printf '%s' '$(printf '%s' "$good_rules" | python3 -c 'import json,sys; r=json.load(sys.stdin); rsc=[x for x in r if x["type"]=="required_status_checks"][0]; a=json.loads(json.dumps(rsc)); a["parameters"]["required_status_checks"]=[{"context":"ci / a"}]; a["ruleset_id"]=2; print(json.dumps(r+[a]))')' > \"\$api/repos/o/r/rules/branches/main.json\""
wall "a strict rule beside a loose one is still strict" "required checks are strict" \
  "printf '%s' '$(printf '%s' "$good_rules" | python3 -c 'import json,sys; r=json.load(sys.stdin); rsc=[x for x in r if x["type"]=="required_status_checks"][0]; a=json.loads(json.dumps(rsc)); a["parameters"]["strict_required_status_checks_policy"]=False; a["ruleset_id"]=2; print(json.dumps(r+[a]))')' > \"\$api/repos/o/r/rules/branches/main.json\""
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
if grep -qF "required checks come from the expected apps (999, 15368)" <<<"$out"; then ok "mixed-app ruleset: each check on its own app passes"
else bad "mixed-app ruleset: correct pins not passed"; grep -E 'FAIL|INFO|PASS  main: required' <<<"$out" | sed 's/^/        /'; fi
# A dropped check withholds the aggregate PASS too.
printf '%s' "$good_rules" | sed 's/,{"context":"ci \/ b","integration_id":15368}//' > "$api/repos/o/r/rules/branches/main.json"
out="$(mixed_out)"
if grep -q "required checks dropped" <<<"$out" && ! grep -q "required checks come from the expected apps" <<<"$out"; then
  ok "a dropped check withholds the aggregate source PASS"
else bad "a dropped check still produced the aggregate source PASS"; grep -E 'FAIL|PASS  main: required' <<<"$out" | sed 's/^/        /'; fi
printf '%s' "$good_rules" | sed 's/"context":"ci \/ b","integration_id":15368/"context":"ci \/ b","integration_id":999/' > "$api/repos/o/r/rules/branches/main.json"
# A check only --expect-checks names, with no shared app to assume, is not
# compared; the aggregate PASS must not claim it.
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$mixed" --expect-checks "ci / a, ci / b, CodeQL" 2>&1)"
if grep -q "expected app for required check CodeQL is not known" <<<"$out" && ! grep -q "required checks come from the expected apps" <<<"$out"; then
  ok "an uncompared check (SKIP) withholds the aggregate source PASS"
else bad "an uncompared check still produced the aggregate source PASS"; grep -E 'SKIP|PASS  main: required' <<<"$out" | sed 's/^/        /'; fi
printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"

# --project separate from --root, expectations from --ruleset
sub="$work/sub"; rm -rf "$sub"; cp -R "$good" "$sub"; mkdir -p "$sub/app"; mv "$sub/pyproject.toml" "$sub/uv.lock" "$sub/.copier-answers.yml" "$sub/Dockerfile" "$sub/.dockerignore" "$sub/.env.example" "$sub/app/"; mv "$sub/src" "$sub/app/src"
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$sub" --project app --no-network --repo o/r --ruleset "$root/ruleset.json" 2>&1)"
if grep -q "required checks dropped" <<<"$out" && grep -q "uv.lock committed" <<<"$out"; then ok "--project and --ruleset are honoured (ruleset's nine checks expected, project files found under app/)"
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
if [ "$rc" = 0 ] && grep -q -- '-- 0 failed' <<<"$out" && grep -q '^  PASS  render.yaml present$' <<<"$out" && grep -q '^  PASS  ci.yml carries the image job' <<<"$out" \
   && grep -q '^  PASS  .env.example present$' <<<"$out"; then ok "a complete web instance passes offline, render.yaml, the image job and .env.example read"
else bad "a complete web instance should pass"; printf '%s\n' "$out" | grep -E 'FAIL|render|image' | sed 's/^/        /'; fi
rm "$web/render.yaml"; git -C "$web" add -A
out="$(python3 "$checker" --root "$web" --no-network 2>&1)"
if grep -q '^  FAIL  render.yaml missing' <<<"$out" && grep -qF 'INFO    restore it from the default branch: git restore --source=origin/main -- render.yaml' <<<"$out" \
   && grep -q -- '-- 1 failed' <<<"$out"; then ok "a web instance without render.yaml: one FAIL, with its fix"
else bad "a web instance without render.yaml is not one FAIL with its fix"; printf '%s\n' "$out" | grep -E 'FAIL|INFO.*render' | sed 's/^/        /'; fi
printf 'services: []\n' > "$web/render.yaml"; git -C "$web" add -A
rm -rf "$web.empty"; cp -R "$web" "$web.empty"; sed -i.bak 's/^archetype: web$/archetype: cli/' "$web.empty/.copier-answers.yml"; rm "$web.empty/render.yaml"
git -C "$web.empty" add -A; out="$(python3 "$checker" --root "$web.empty" --no-network 2>&1)"
if grep -q '^  INFO  archetype cli: ' <<<"$out" && grep -q -- '-- 0 failed' <<<"$out" && ! grep -q 'render.yaml' <<<"$out"; then ok "another archetype is not asked for render.yaml"
else bad "a cli instance was asked for render.yaml"; fi
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
     && grep -qF "INFO  render.yaml not required: hosting is elsewhere ($place), and only Render reads that file" <<<"$out"; then
    ok "web with hosting: elsewhere ($place) and no render.yaml: no FAIL, one INFO naming $place"
  else bad "web with hosting: elsewhere ($place) and no render.yaml"; printf '%s\n' "$out" | grep -E 'FAIL|render|elsewhere' | sed 's/^/        /'; fi
  case "$place" in
    vps|home)
      if grep -qF "INFO  not checked by plinth: on $place, HTTPS, backups and keeping the app's and the database's ports closed are a person's to set up" <<<"$out" \
         && ! grep -qE '^  PASS .*(HTTPS|backup|port)' <<<"$out"; then ok "hosting_elsewhere: $place says what plinth does not check, as an INFO"
      else bad "hosting_elsewhere: $place does not say what plinth does not check"; printf '%s\n' "$out" | grep -E 'HTTPS|not checked' | sed 's/^/        /'; fi ;;
    *)
      if ! grep -q 'not checked by plinth' <<<"$out"; then ok "hosting_elsewhere: $place carries no line meant for vps and home"
      else bad "hosting_elsewhere: $place carries the vps/home line"; fi ;;
  esac
done
out="$(hosted_out "$web" web 'hosting: elsewhere\n' drop)"
if grep -q -- '-- 0 failed' <<<"$out" && grep -qF 'INFO  render.yaml not required: hosting is elsewhere (no hosting_elsewhere answer), and only Render reads that file' <<<"$out"; then
  ok "hosting: elsewhere with no hosting_elsewhere answer says that none is recorded"
else bad "hosting: elsewhere with no hosting_elsewhere answer"; printf '%s\n' "$out" | grep -E 'FAIL|render' | sed 's/^/        /'; fi
rm -rf "$web_hosted"
# A cli or library publishes on a version tag through release.yml
# (plinth-template 1.29.0, #703). Each finding is a WARN: an instance rendered
# before the file existed still has 0 failed. GitLab renders none.
pkg="$work/pkg"; rm -rf "$pkg"; cp -R "$web.empty" "$pkg"
release_out() { git -C "$pkg" add -A; python3 "$checker" --root "$pkg" --no-network 2>&1; }
rel=.github/workflows/release.yml
out="$(release_out)"
if grep -qF "WARN  $rel missing: a version tag does not publish this package to PyPI" <<<"$out" \
   && grep -qF 'INFO    plinth-template 1.29.0 adds it, with its steps in docs/how-to/publish-a-release.md' <<<"$out" \
   && grep -q -- '-- 0 failed' <<<"$out"; then ok "a cli instance without release.yml: a WARN with its fix, 0 failed"
else bad "a cli instance without release.yml"; printf '%s\n' "$out" | grep -E 'FAIL|release' | sed 's/^/        /'; fi
printf '# on: pull_request in a comment is not a trigger\nname: Release\non:\n  push:\n    tags: ["v*"]  # a version tag\npermissions: {}\njobs:\n  publish:\n    environment: pypi\n    permissions:\n      id-token: write\n    steps:\n      - uses: pypa/gh-action-pypi-publish@%040d\n      - run: gh release create "$GITHUB_REF_NAME"\n        env:\n          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}\n' 0 > "$pkg/$rel"
for a in cli library; do
  sed -i.bak "s/^archetype: .*/archetype: $a/" "$pkg/.copier-answers.yml"; rm "$pkg/.copier-answers.yml.bak"
  out="$(release_out)"
  if grep -qF "PASS  $rel present" <<<"$out" && grep -qF "PASS  $rel runs on a pushed tag only" <<<"$out" \
     && grep -qF "PASS  $rel reads no stored secret" <<<"$out" && ! grep -q "WARN  $rel" <<<"$out"; then ok "$a: the template's shape of release.yml passes its three items"
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
if grep -qF "WARN  $rel reads a stored secret (password:, secrets.PYPI_API_TOKEN)" <<<"$out" && grep -q -- '-- 0 failed' <<<"$out"; then ok "release.yml with a stored PyPI token: a WARN naming it"
else bad "release.yml with a stored PyPI token was not warned"; printf '%s\n' "$out" | grep -E 'release' | sed 's/^/        /'; fi
# --project: the project one directory down, the workflow at the root,
# where GitHub reads it (#720 review).
cp "$pkg/release.good" "$pkg/$rel"
sub_pkg="$work/pkg-sub"; rm -rf "$sub_pkg"; mkdir -p "$sub_pkg/app"; cp -R "$pkg/.github" "$sub_pkg/"
for f in pyproject.toml uv.lock .copier-answers.yml src; do cp -R "$pkg/$f" "$sub_pkg/app/"; done
git -C "$sub_pkg" init -q; git -C "$sub_pkg" add -A
out="$(python3 "$checker" --root "$sub_pkg" --project app --no-network 2>&1)"
if grep -qF "PASS  $rel present" <<<"$out" && grep -qF "PASS  $rel runs on a pushed tag only" <<<"$out" && ! grep -q "WARN  $rel" <<<"$out"; then
  ok "--project app: release.yml read at the repository root"
else bad "--project app: release.yml not read at the root"; printf '%s\n' "$out" | grep -E 'release|FAIL' | sed 's/^/        /'; fi
rm -rf "$sub_pkg"
# --host wins over the answers, as for every other host-dependent item (#720 review).
out="$(git -C "$pkg" add -A; python3 "$checker" --root "$pkg" --no-network --host gitlab 2>&1)"
if grep -qF "INFO  $rel not required: on GitLab" <<<"$out" && ! grep -q "PASS  $rel" <<<"$out"; then ok "--host gitlab over a GitHub answer: release.yml not asked"
else bad "--host gitlab did not reach the release item"; printf '%s\n' "$out" | grep -E 'release' | sed 's/^/        /'; fi
rm "$pkg/$rel"; printf 'host: gitlab\n' >> "$pkg/.copier-answers.yml"
out="$(release_out)"
if grep -qF "INFO  $rel not required: on GitLab the template renders no release workflow" <<<"$out" && ! grep -q "WARN  $rel" <<<"$out"; then ok "a GitLab library is not asked for release.yml"
else bad "a GitLab library was asked for release.yml"; fi
cp "$pkg/release.good" "$pkg/$rel"
out="$(git -C "$pkg" add -A; python3 "$checker" --root "$pkg" --no-network --host github 2>&1)"
if grep -qF "PASS  $rel runs on a pushed tag only" <<<"$out" && ! grep -q "not required: on GitLab" <<<"$out"; then ok "--host github over a GitLab answer: release.yml read"
else bad "--host github did not reach the release item"; printf '%s\n' "$out" | grep -E 'release' | sed 's/^/        /'; fi
rm "$pkg/$rel"
out="$(python3 "$checker" --root "$good" --no-network 2>&1)"
if ! grep -q "release.yml" <<<"$out"; then ok "a backend instance is not asked for release.yml"
else bad "a backend instance was asked for release.yml"; fi
rm -rf "$pkg"
web_rules="$(python3 "$checker" --print-ruleset --ruleset "$root/ruleset.json" --archetype web | jq -c '[.rules[] | . + {ruleset_source_type: "Repository", ruleset_id: 1}]')"
for drop in "ci / migrations" "ci / deploy-check"; do
  jq -c --arg d "$drop" 'map(if .type == "required_status_checks" then .parameters.required_status_checks |= map(select(.context != $d)) else . end)' <<<"$web_rules" > "$api/repos/o/r/rules/branches/main.json"
  out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$web" --no-network --repo o/r --ruleset "$root/ruleset.json" 2>&1)"
  if grep -qF "FAIL  main: required checks dropped: ['$drop']" <<<"$out" \
     && grep -qF "INFO    require them again (repository administration): scripts/with-admin-token.sh scripts/upgrade-ruleset.sh o/r '$drop:15368'" <<<"$out" \
     && [ "$(grep -c '^  FAIL ' <<<"$out")" = 1 ]; then ok "a web wall without $drop: one FAIL, with the command that requires it again"
  else bad "a web wall without $drop is not one FAIL with its fix"; printf '%s\n' "$out" | grep -E 'FAIL|INFO.*upgrade' | sed 's/^/        /'; fi
done
jq -c . <<<"$web_rules" > "$api/repos/o/r/rules/branches/main.json"
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$web" --no-network --repo o/r --ruleset "$root/ruleset.json" 2>&1)"
if grep -qE "PASS  main: all 12 expected checks are required" <<<"$out" && ! grep -q '^  FAIL ' <<<"$out"; then ok "a web wall with the image and both web checks passes (12 checks)"
else bad "the full web wall does not pass"; printf '%s\n' "$out" | grep -E 'FAIL|expected checks' | sed 's/^/        /'; fi
printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"

# #221: run at the root of a repository whose project is one directory down,
# the checker reports two files missing that do exist. The answer is --project,
# so the FAIL line names it when exactly one directory below --root holds a
# pyproject.toml. Which project is meant stays the user's to say: the checker
# neither guesses nor re-runs itself.
out="$(python3 "$checker" --root "$sub" --no-network 2>&1)"; rc=$?
if grep -q "FAIL  pyproject.toml missing here; found app/pyproject.toml: run again with --project=app" <<<"$out" \
&& grep -q "FAIL  uv.lock missing here; found app/uv.lock: run again with --project=app" <<<"$out"
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
if grep -q "PASS  pyproject.toml present" <<<"$out" && grep -q "PASS  uv.lock committed" <<<"$out"
then ok "the hinted --project turns both project items to PASS"
else bad "the hinted --project"; printf '%s\n' "$out" | grep -E 'FAIL|PASS  (pyproject|uv)' | sed 's/^/        /'; fi

pnone="$work/proj-none"; rm -rf "$pnone"; cp -R "$good" "$pnone"; rm "$pnone/pyproject.toml"
out="$(python3 "$checker" --root "$pnone" --no-network 2>&1)"
if grep -q "FAIL  pyproject.toml missing$" <<<"$out" && ! grep -q -- "--project" <<<"$out"
then ok "no pyproject.toml below the root: the line stays as it was, with no hint"
else bad "no candidate below the root"; printf '%s\n' "$out" | grep -E 'FAIL|INFO' | sed 's/^/        /'; fi

ptwo="$work/proj-two"; rm -rf "$ptwo"; cp -R "$sub" "$ptwo"; mkdir -p "$ptwo/svc"; cp "$ptwo/app/pyproject.toml" "$ptwo/svc/pyproject.toml"
out="$(python3 "$checker" --root "$ptwo" --no-network 2>&1)"; rc=$?
if grep -q "FAIL  pyproject.toml missing$" <<<"$out" && grep -q "INFO.*app/.*svc/" <<<"$out" && [ "$rc" = 1 ] && grep -q -- '-- 2 failed, 3 not verified' <<<"$out"
then ok "two candidates: today's line, both paths listed, and no choice made for the user"
else bad "two candidates below the root (rc=$rc)"; printf '%s\n' "$out" | grep -E 'FAIL|INFO|failed' | sed 's/^/        /'; fi

# The search is the first thing in the run to list the root's entries, so a
# --root that is not there reaches it: it reports, it does not traceback.
out="$(python3 "$checker" --root "$work/not-a-checkout" --no-network 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -q "FAIL  pyproject.toml missing$" <<<"$out" && ! grep -q "Traceback" <<<"$out"
then ok "a --root that does not exist is reported, not a traceback"
else bad "a --root that does not exist (rc=$rc)"; printf '%s\n' "$out" | tail -5 | sed 's/^/        /'; fi

# A caller that named a --project chose it. Sending them to a different
# project below the root is sending them away from the one they meant to
# repair, so the search runs only when this run is checking the root itself.
psel="$work/proj-selected"; rm -rf "$psel"; cp -R "$sub" "$psel"; mkdir -p "$psel/svc"
out="$(python3 "$checker" --root "$psel" --project svc --no-network 2>&1)"
if grep -q "FAIL  pyproject.toml missing$" <<<"$out" && grep -q "FAIL  uv.lock missing: CI runs" <<<"$out" \
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
if grep -q "FAIL  pyproject.toml missing here; found app/pyproject.toml" <<<"$out" \
&& grep -q "FAIL  app/uv.lock missing: CI runs" <<<"$out" && ! grep -q "found app/uv.lock" <<<"$out"
then ok "no uv.lock in the named directory: that directory is named as the one needing it"
else bad "the uv.lock line without a lockfile below"; printf '%s\n' "$out" | grep -E 'FAIL' | sed 's/^/        /'; fi

# A uv.lock at a root that holds no pyproject.toml belongs to no project this
# run checks. Passing the item for it sent the reader to a project where
# `--project=` reports the lockfile missing straight away.
pstray="$work/proj-stray-lock"; rm -rf "$pstray"; cp -R "$sub" "$pstray"; rm "$pstray/app/uv.lock"; : > "$pstray/uv.lock"
out="$(python3 "$checker" --root "$pstray" --no-network 2>&1)"
if grep -q "FAIL  app/uv.lock missing: CI runs" <<<"$out" && ! grep -q "PASS  uv.lock committed" <<<"$out"
then ok "a stray uv.lock at a root with no project does not pass the item for the project found below"
else bad "a stray uv.lock at the root"; printf '%s\n' "$out" | grep -E 'FAIL|PASS  uv.lock' | sed 's/^/        /'; fi
# ...and it does not suppress the pointer when the project has one either.
pstray2="$work/proj-stray-lock-both"; rm -rf "$pstray2"; cp -R "$sub" "$pstray2"; : > "$pstray2/uv.lock"
out="$(python3 "$checker" --root "$pstray2" --no-network 2>&1)"
if grep -q "FAIL  uv.lock missing here; found app/uv.lock: run again with --project=app" <<<"$out" \
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
if grep -q "FAIL  pyproject.toml missing$" <<<"$out" && ! grep -q "PASS  forged floor item" <<<"$out"
then ok "a directory name holding a newline is not offered, so no line is forged into the report"
else bad "a control character in a candidate name"; printf '%s\n' "$out" | grep -E 'FAIL|PASS  forged' | sed 's/^/        /'; fi

# is_dir() follows symlinks, so without a guard a link out of the checkout is
# offered and the reader is sent to read a tree this repository does not hold.
psym="$work/proj-symlink"; rm -rf "$psym"; cp -R "$sub" "$psym"; mkdir -p "$work/proj-outside"
mv "$psym/app" "$work/proj-outside/app"; ln -sfn "$work/proj-outside/app" "$psym/app"
out="$(python3 "$checker" --root "$psym" --no-network 2>&1)"
if grep -q "FAIL  pyproject.toml missing$" <<<"$out" && ! grep -q -- "--project" <<<"$out"
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
  if grep -q "FAIL  pyproject.toml missing$" <<<"$out" && ! grep -q -- "--project" <<<"$out"
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
plant "docker words outside the image job do not count" "printf 'jobs:\n  ci:\n    uses: x\n  image:\n    steps:\n      - run: echo\n  other:\n    steps:\n      - run: docker build . \&\& docker run t\n' > .github/workflows/ci.yml" "no \`image\` job"
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --ruleset "$root/ruleset.json" 2>&1)"
if grep -q "wall expectation: checks \[.*'image'\]" <<<"$out"; then ok "a backend instance expects the image check of the wall, from --ruleset"
else bad "a backend instance's expectation lacks image"; printf '%s\n' "$out" | grep -E 'wall expectation' | sed 's/^/        /'; fi
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --archetype cli --no-network --repo o/r --ruleset "$root/ruleset.json" 2>&1)"
if grep -q "wall expectation: checks \[.*'ci / floor-check'\]," <<<"$out" && ! grep -q "'image'" <<<"$out"; then ok "a cli instance expects the nine, not image"
else bad "a cli instance's expectation carries image"; printf '%s\n' "$out" | grep -E 'wall expectation' | sed 's/^/        /'; fi

# #219: is the template plinth is tested with today ahead of the tag this
# repository was rendered from? The target is read from the real
# scripts/new-project.sh beside the real checker (not a fixture, #219), so the
# good fixture (recorded at $target_ref) always PASSes and every other case
# below sets _commit far enough from $target_ref to stay true across a pin raise.
says "the good fixture's recorded template tag matches the target" ":" \
  "PASS  template: the recorded tag is the target tag \($target_ref\)"

drift() { # <description> <_commit value> <expected ERE in the output>; never a FAIL
  local copy="$work/drift"; rm -rf "$copy"; cp -R "$good" "$copy"
  printf 'archetype: backend\n_src_path: gh:coolbress/plinth-template\n_commit: %s\n' "$2" > "$copy/.copier-answers.yml"
  local out; out="$(python3 "$checker" --root "$copy" --no-network 2>&1)"; local rc=$?
  if [ "$rc" != 0 ] || grep -q "FAIL.*template" <<<"$out"; then bad "$1 (never a FAIL, rc=$rc)"; printf '%s\n' "$out" | grep -E 'FAIL' | sed 's/^/        /'; return; fi
  if grep -qE -- "$3" <<<"$out"; then ok "$1"; else bad "$1 (expected a line matching '$3')"; printf '%s\n' "$out" | grep -E 'template' | sed 's/^/        /'; fi
}
drift "a recorded tag behind the target is named, with both tags" "v1.0.0" \
  "WARN  template: v1\.0\.0 is behind $target_ref, the tag plinth is tested with"
drift "offline, the changed files could not be read, and it says so rather than staying silent" "v1.0.0" \
  "the changed files could not be read \(offline or API error\)"
drift "offline, the update command still carries the pin this repository's own CI calls today" "v1.0.0" \
  "copier update --defaults --vcs-ref $target_sha --data plinth_sha=$sha40"
drift "a recorded tag ahead of the target is a plain statement, not a not-verified count" "v99.0.0" \
  "INFO  template: the recorded tag v99\.0\.0 is ahead of $target_ref, the tag plinth is tested with"
quiet "an ahead tag is not counted as not verified" \
  "printf 'archetype: backend\n_src_path: gh:coolbress/plinth-template\n_commit: v99.0.0\n' > .copier-answers.yml" \
  "template drift not verified"
plant "no .copier-answers.yml: the item never fails, it says not verified" "rm .copier-answers.yml" "__none__" || true
says "no .copier-answers.yml is named as the reason" "rm .copier-answers.yml" \
  "SKIP  template drift not verified \(no \.copier-answers\.yml: not made by the door\)"
says "an answers file without _commit is not verified" \
  "printf 'archetype: backend\n_src_path: gh:coolbress/plinth-template\n' > .copier-answers.yml" \
  "SKIP  template drift not verified \(\.copier-answers\.yml has no _commit\)"
says "a _src_path that is not the plinth template is not verified" \
  "printf 'archetype: backend\n_src_path: gh:example/other-template\n_commit: v1.0.0\n' > .copier-answers.yml" \
  "SKIP  template drift not verified \(_src_path"
# A foreign source containing the template's name as a substring must not
# pass a bare `in` check: copier update pulls from _src_path, and passing
# that through would run against whatever that foreign source is (#233 review).
says "a foreign _src_path that merely contains the template's name is not the door's own form" \
  "printf 'archetype: backend\n_src_path: /tmp/coolbress/plinth-template\n_commit: v1.0.0\n' > .copier-answers.yml" \
  "SKIP  template drift not verified \(_src_path '/tmp/coolbress/plinth-template' is not gh:coolbress/plinth-template"
says "a git describe value is not verified, quoted as recorded, and no command is printed" \
  "printf 'archetype: backend\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0-3-gabc1234\n' > .copier-answers.yml" \
  "SKIP  template drift not verified \(recorded tag 'v1\.0\.0-3-gabc1234' is not an exact release tag\)"
quiet "a git describe value prints no update command" \
  "printf 'archetype: backend\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0-3-gabc1234\n' > .copier-answers.yml" \
  "copier update"

# The plinth pin: read from this repository's own workflow uses: lines, the
# live truth Dependabot moves and .copier-answers.yml never does. Unknown
# withholds the command and names why, but the tags and file list still print.
says "no plinth workflow pin at all: the command is withheld, with the reason" \
  "printf 'archetype: cli\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0\n' > .copier-answers.yml && rm -r .github/workflows" \
  "no update command: no coolbress/plinth workflow uses: line found"
says "two workflow files pinned to different plinth commits: the command is withheld, both named" \
  "printf 'archetype: cli\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0\n' > .copier-answers.yml && mkdir -p .github/workflows && printf 'jobs:\n  a:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%040d\n' 0 > .github/workflows/one.yml && printf 'jobs:\n  b:\n    uses: coolbress/plinth/.github/workflows/label.yml@%040d\n' 1 > .github/workflows/two.yml" \
  "no update command: workflow pins disagree: 0000000000000000000000000000000000000000, 0000000000000000000000000000000000000001"
says "a commented uses: line is not counted as a plinth pin" \
  "printf 'archetype: cli\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0\n' > .copier-answers.yml && rm -r .github/workflows && mkdir -p .github/workflows && printf 'jobs:\n  a:\n    # uses: coolbress/plinth/.github/workflows/python-ci.yml@%040d\n    uses: ./local\n' 0 > .github/workflows/one.yml" \
  "no update command: no coolbress/plinth workflow uses: line found"
# One workflow pinned to a full SHA and another tracking a tag must not let
# the tag be silently dropped: today's pin is not established while any
# plinth uses: could be moving (#233 review) -- printing a command from the
# one SHA that happens to be pinned would rewrite the other file too.
says "one plinth pin on a full SHA and another on a tag: the command is withheld, not printed from the one SHA" \
  "printf 'archetype: cli\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0\n' > .copier-answers.yml && rm -r .github/workflows && mkdir -p .github/workflows && printf 'jobs:\n  a:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%040d\n' 0 > .github/workflows/one.yml && printf 'jobs:\n  b:\n    uses: coolbress/plinth/.github/workflows/label.yml@main\n' > .github/workflows/two.yml" \
  "no update command: a coolbress/plinth workflow uses: line is not pinned to a full commit SHA"
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
  "no update command: a workflow uses: line could not be read; it may or may not pin coolbress/plinth"
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
  "^  WARN  workflow pins disagree: ci\.yml calls plinth at $sha40, label\.yml at $sha1\$"
has "the INFO under it is a sed line for label.yml's plinth pin" \
  "^  INFO    sed -i\.bak 's\|coolbress/plinth/[^|]*@$sha1\|.*' \.github/workflows/label\.yml && rm \.github/workflows/label\.yml\.bak"
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
  "^  SKIP  plinth workflow pins not compared: label\.yml line 4 mentions uses"
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
  "^  WARN  workflow pins disagree: ci\.yml calls plinth at $lower_a, label\.yml at $(tr B b <<<"$upper_b")\$"
has "and as written in the sed line, which matches case" "^  INFO    sed -i\.bak 's\|coolbress/plinth/[^|]*@$upper_b\|.*@$lower_a\|g' \.github/workflows/label\.yml"
pins "    uses: coolbress/plinth/.github/workflows/pr-label.yml@$sha1\n  other:\n    uses: coolbress/plinth/.github/workflows/pr-label.yml@$sha40"
has "two SHAs inside one file are both named" "^  WARN  workflow pins disagree: ci\.yml calls plinth at $sha40, label\.yml at $sha1 and $sha40\$"
has "and only the lagging one gets a sed line" "^  INFO    sed -i\.bak 's\|coolbress/plinth/[^|]*@$sha1\|"
lacks "the matching one gets none" "sed -i\.bak 's\|coolbress/plinth/[^|]*@$sha40\|"
# GitHub reads the owner and repository in any case, as the caller item does:
# a ci job calling CoolBress/Plinth is still plinth's pin.
pins "    uses: coolbress/plinth/.github/workflows/pr-label.yml@$sha1"
sed -i.bak "s|coolbress/plinth/|CoolBress/Plinth/|" "$work/pins/.github/workflows/ci.yml" && rm "$work/pins/.github/workflows/ci.yml.bak"
out="$(python3 "$checker" --root "$work/pins" --no-network 2>&1)"
has "CoolBress/Plinth in ci.yml and coolbress/plinth in label.yml at different SHAs: the WARN names both" \
  "^  WARN  workflow pins disagree: ci\.yml calls plinth at $sha40, label\.yml at $sha1\$"
fixed "and the fix still moves label.yml to the ci job's SHA" "pr-label\.yml@$sha40\$"
# The fix rewrites plinth references only: the same SHA on another action stays.
pins "    uses: coolbress/plinth/.github/workflows/pr-label.yml@$sha1\n  other:\n    steps:\n      - uses: someone/fork@$sha1"
fixed "the same SHA on another action in label.yml is left as it was" "someone/fork@$sha1\$"
fixed "while the plinth reference moves" "pr-label\.yml@$sha40\$"

# The template-update skill (#232) runs the command stage 1 prints, not a
# second construction of it: --print-update-command prints that same line
# and nothing else, or a reason on stderr and exit 1. `--defaults` is in it
# because without a terminal copier update stops at "Interactive session
# required" (measured, copier 9.18.2), and the skill has no terminal.
pcopy="$work/print-cmd"; rm -rf "$pcopy"; cp -R "$good" "$pcopy"
printf 'archetype: backend\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0\n' > "$pcopy/.copier-answers.yml"
warned="$(python3 "$checker" --root "$pcopy" --no-network 2>&1 | sed -n 's/^  INFO    \(uvx .*copier update.*\)$/\1/p')"
pinned_api="$work/api-pinned"; tag_names "$pinned_api" "$target_sha"
printed="$(FLOOR_CHECK_API_DIR="$pinned_api" python3 "$checker" --root "$pcopy" --print-update-command 2>/dev/null)"; rc=$?
if [ "$rc" = 0 ] && [ -n "$warned" ] && [ "$printed" = "$warned" ]; then ok "--print-update-command prints exactly the line the drift WARN prints"
else bad "--print-update-command (rc=$rc): printed '$printed', WARN printed '$warned'"; fi
case "$printed" in *"copier update --defaults "*) ok "the update command runs without a terminal (--defaults)" ;;
  *) bad "the update command has no --defaults: '$printed'" ;; esac
# The target tag must still name the commit plinth was tested with (#519):
# the doors check the same pair before rendering, and so does the line.
moved="$(printf '%040d' 5)"
moved_api="$work/api-moved"; tag_names "$moved_api" "$moved"
out="$(FLOOR_CHECK_API_DIR="$moved_api" python3 "$checker" --root "$pcopy" 2>&1)"
if grep -q "WARN  template: $target_ref now names commit $moved, not $target_sha, the commit plinth was tested with; no update command" <<<"$out" \
   && ! grep -q "copier update" <<<"$out"
then ok "a moved target tag: a WARN naming both commits, and no update command"
else bad "moved tag, drift item"; printf '%s\n' "$out" | grep -E 'template|copier' | sed 's/^/        /'; fi
printed="$(FLOOR_CHECK_API_DIR="$moved_api" python3 "$checker" --root "$pcopy" --print-update-command 2>"$work/print-err")"; rc=$?
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -q "now names commit $moved, not $target_sha" "$work/print-err"; then ok "a moved target tag: --print-update-command prints no line, exit 1, names both commits"
else bad "--print-update-command, moved tag (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi
printed="$(FLOOR_CHECK_API_DIR="$moved_api" python3 "$checker" --root "$pcopy" --print-update-command --plinth-pin tested 2>"$work/print-err")"; rc=$?
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -q "now names commit $moved" "$work/print-err"; then ok "a moved target tag: --plinth-pin tested prints no line either"
else bad "--plinth-pin tested, moved tag (rc=$rc, stdout '$printed')"; fi
out="$(FLOOR_CHECK_API_DIR="$moved_api" python3 "$checker" --root "$good" 2>&1)"
if grep -q "WARN  template: the recorded tag is the target tag ($target_ref), but $target_ref now names commit $moved, not $target_sha" <<<"$out" \
   && ! grep -q "PASS  template:" <<<"$out"
then ok "a repository already on the target tag, and the tag moved since: a WARN, not a PASS"
else bad "current tag moved"; printf '%s\n' "$out" | grep -E 'template' | sed 's/^/        /'; fi
out="$(FLOOR_CHECK_API_DIR="$pinned_api" python3 "$checker" --root "$good" 2>&1)"
if grep -q "PASS  template: the recorded tag is the target tag ($target_ref)" <<<"$out"; then ok "a repository on the target tag, the tag still on its commit: PASS"
else bad "current tag pinned"; printf '%s\n' "$out" | grep -E 'template' | sed 's/^/        /'; fi
out="$(python3 "$checker" --root "$good" --no-network 2>&1)"
if grep -q "PASS  template: the recorded tag is the target tag ($target_ref)" <<<"$out" \
   && grep -q "INFO    not verified that $target_ref still names $target_sha, the commit plinth was tested with (offline or API error)" <<<"$out"
then ok "a repository on the target tag, the tag's commit not read: the PASS says the tags only, and a line says the commit was not verified"
else bad "current tag unread"; printf '%s\n' "$out" | grep -E 'template|verified' | sed 's/^/        /'; fi
out="$(python3 "$checker" --root "$pcopy" --no-network 2>&1)"
if grep -q "INFO    not verified that $target_ref still names $target_sha, the commit plinth was tested with (offline or API error); the template-update skill checks it before it runs this line:" <<<"$out" \
   && grep -q "INFO    uvx .*copier update" <<<"$out"
then ok "the target tag's commit not read: the drift item still shows the line, and says it was not verified"
else bad "unread tag, drift item"; printf '%s\n' "$out" | grep -E 'template|copier|verified' | sed 's/^/        /'; fi
printed="$(FLOOR_CHECK_API_DIR="$work/api-none-at-all" python3 "$checker" --root "$pcopy" --print-update-command 2>"$work/print-err")"; rc=$?
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -q "not verified that $target_ref still names $target_sha, the commit plinth was tested with (the tag was not found)" "$work/print-err"
then ok "the target tag's commit not read: --print-update-command, the line that runs, prints none (fail closed)"
else bad "--print-update-command, tag unread (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi
printed="$(python3 "$checker" --root "$good" --print-update-command 2>"$work/print-err")"; rc=$?
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -q "the recorded tag is the target tag" "$work/print-err"; then ok "--print-update-command at the target tag prints no command, says why, exit 1"
else bad "--print-update-command at the target (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi
printed="$(python3 "$checker" --root "$loosecopy" --print-update-command 2>"$work/print-err")"; rc=$?
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -q "not pinned to a full commit SHA" "$work/print-err"; then ok "--print-update-command with no established pin prints no command, names the reason, exit 1"
else bad "--print-update-command, loose pin (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi
printed="$(python3 "$checker" --root "$noarch" --print-update-command 2>"$work/print-err")"; rc=$?
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -q "no .copier-answers.yml" "$work/print-err"; then ok "--print-update-command outside a door-made repository prints no command, exit 1"
else bad "--print-update-command, no answers file (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi

# The changed-files list and diff: one call to the template's compare API,
# made only when behind, filtered to template/ (the door's own tests, docs
# and copier.yml are not rendered into a consumer repository).
tmpl_api="$work/api-template"; mkdir -p "$tmpl_api/repos/coolbress/plinth-template/compare"
patch_agents=$'@@ -1,2 +1,3 @@\n # Agents\n+one more line\n'
jq -n --arg patch "$patch_agents" '{files: [
    {filename: "template/AGENTS.md", status: "modified", patch: $patch},
    {filename: "template/.gitignore", status: "modified"},
    {filename: "docs/README.md", status: "modified"}
  ]}' > "$tmpl_api/repos/coolbress/plinth-template/compare/v1.0.0...${target_ref}.json"
tag_names "$tmpl_api" "$target_sha"
tcopy="$work/tmpl-drift"; rm -rf "$tcopy"; cp -R "$good" "$tcopy"
printf 'archetype: backend\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0\n' > "$tcopy/.copier-answers.yml"
out="$(FLOOR_CHECK_API_DIR="$tmpl_api" python3 "$checker" --root "$tcopy" 2>&1)"
if grep -q "changed in the template: \.gitignore, AGENTS\.md" <<<"$out"; then ok "the changed-files list is scoped to template/ and strips the prefix"
else bad "changed-files list"; printf '%s\n' "$out" | grep -E 'changed in the template' | sed 's/^/        /'; fi
if grep -q "docs/README.md" <<<"$out"; then bad "a file outside template/ leaked into the changed-files list"
else ok "a file outside template/ (the door never renders it) is left out"; fi
if grep -q "  AGENTS.md:" <<<"$out" && grep -q "+one more line" <<<"$out"; then ok "the short list's diff is shown for AGENTS.md, from the same compare call"
else bad "AGENTS.md diff"; printf '%s\n' "$out" | grep -E 'AGENTS|one more line' | sed 's/^/        /'; fi
if grep -q "  \.gitignore:" <<<"$out"; then bad ".gitignore has no patch in the fixture; it should print no diff header"
else ok "a short-list file with no patch in the compare response prints no diff block"; fi
if grep -q "PASS  template:" <<<"$out" || grep -q "SKIP.*template drift" <<<"$out"; then bad "a behind repository must not read as passed or not verified"
else ok "a behind repository is a WARN, and only a WARN"; fi

# A compare call that fails (offline is covered above; here the fixture
# directory exists but has no entry for this path -- a 404) behaves the same:
# the WARN stands, the command still prints, the file list says it could not be read.
empty_api="$work/api-template-empty"; mkdir -p "$empty_api/repos/coolbress/plinth-template"
tcopy2="$work/tmpl-drift-404"; rm -rf "$tcopy2"; cp -R "$good" "$tcopy2"
printf 'archetype: backend\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0\n' > "$tcopy2/.copier-answers.yml"
out="$(FLOOR_CHECK_API_DIR="$empty_api" python3 "$checker" --root "$tcopy2" 2>&1)"
if grep -q "the changed files could not be read" <<<"$out" && grep -q "copier update --defaults --vcs-ref $target_sha --data plinth_sha=$sha40" <<<"$out"; then
  ok "a compare call that 404s still prints the update command, and names the file list as unread"
else bad "a 404 on the compare call"; printf '%s\n' "$out" | grep -E 'template|copier update' | sed 's/^/        /'; fi

# The tested pin (#511): the target tag's copier.yml names the plinth commit
# it was tested with. When that is newer than the pin the workflows call, a
# second line carries it, for a person to choose; never one that moves the
# pin backwards, and never past a comparison that was not read.
tested="$(printf '%040d' 3)"
pin_api() { # <copier.yml plinth_sha default or "-" for none> <compare status or "-" for none> → sets $pin_dir
  pin_dir="$work/api-pin"; rm -rf "$pin_dir"
  mkdir -p "$pin_dir/repos/coolbress/plinth-template/contents" "$pin_dir/repos/coolbress/plinth/compare"
  if [ "$1" != - ]; then
    printf 'plinth_sha:\n  type: str\n  help: |\n    Commit of coolbress/plinth.\n  default: "%s"\n\nowner_github_defaults:\n  default: "0000000000000000000000000000000000000009"\n' "$1" \
      | base64 | tr -d '\n' | jq -R '{encoding: "base64", content: .}' > "$pin_dir/repos/coolbress/plinth-template/contents/copier.yml?ref=$target_sha.json"
  fi
  [ "$2" = - ] || jq -n --arg s "$2" '{status: $s, ahead_by: 4, behind_by: 0}' > "$pin_dir/repos/coolbress/plinth/compare/$sha40...$tested.json"
  jq -n --arg t "$tested" '[{name: "v9.0.0", commit: {sha: $t}}]' > "$pin_dir/repos/coolbress/plinth/tags?per_page=100.json"
  tag_names "$pin_dir" "$target_sha"
}
pcopy2="$work/pin-choice"; rm -rf "$pcopy2"; cp -R "$good" "$pcopy2"
printf 'archetype: backend\n_src_path: gh:coolbress/plinth-template\n_commit: v1.0.0\n' > "$pcopy2/.copier-answers.yml"
pin_out() { out="$(FLOOR_CHECK_API_DIR="$pin_dir" python3 "$checker" --root "$pcopy2" 2>&1)"; lines="$(grep -c '^  INFO    uvx .*copier update' <<<"$out")"; }
live_line="copier update --defaults --vcs-ref $target_sha --data plinth_sha=$sha40"
tested_line="copier update --defaults --vcs-ref $target_sha --data plinth_sha=$tested"
pin_api "$tested" ahead; pin_out
if [ "$lines" = 2 ] && grep -qF "$live_line" <<<"$out" && grep -qF "$tested_line" <<<"$out"
then ok "tested pin ahead of the live one: both update lines are printed, the live one first"
else bad "tested ahead ($lines lines)"; printf '%s\n' "$out" | grep -E 'plinth|copier' | sed 's/^/        /'; fi
has "the comparison names both SHAs, the tested pin's tag and the compare URL" \
  "INFO    plinth pin: the workflows call $sha40; $target_ref was tested with $tested \(v9\.0\.0\), 4 commit\(s\) newer: https://github\.com/coolbress/plinth/compare/$sha40\.\.\.$tested\$"
has "the second line is offered, not chosen" "the line above keeps the live pin; this one moves it to the tested pin, if you choose it:"
printed="$(FLOOR_CHECK_API_DIR="$pin_dir" python3 "$checker" --root "$pcopy2" --print-update-command --plinth-pin tested 2>"$work/print-err")"; rc=$?
if [ "$rc" = 0 ] && [ "$printed" = "$(sed -n 's/^  INFO    \(uvx .*plinth_sha='"$tested"'\)$/\1/p' <<<"$out")" ] && grep -q "4 commit(s) newer" "$work/print-err" \
   && grep -q "^recommended: move the plinth pin to $tested (v9.0.0): this repository's checks then run the plinth commit $target_ref was tested with, 4 commit(s) newer than the one they run now" "$work/print-err"
then ok "--print-update-command --plinth-pin tested prints exactly the second line, the comparison and the recommendation on stderr"
else bad "--plinth-pin tested, ahead (rc=$rc, stdout '$printed')"; sed 's/^/        /' "$work/print-err"; fi
printed="$(FLOOR_CHECK_API_DIR="$pin_dir" python3 "$checker" --root "$pcopy2" --print-update-command 2>/dev/null)"
case "$printed" in *"$live_line") ok "--print-update-command without --plinth-pin still prints the live line" ;;
  *) bad "--print-update-command default: '$printed'" ;; esac

rm "$pin_dir/repos/coolbress/plinth/tags?per_page=100.json"; pin_out
if [ "$lines" = 2 ] && grep -q "INFO    plinth pin: the workflows call $sha40; $target_ref was tested with $tested, 4 commit(s) newer (release tags not read): https://" <<<"$out"
then ok "the tag list unread: the comparison says so, rather than reading as an untagged commit"
else bad "tags unread ($lines lines)"; printf '%s\n' "$out" | grep -E 'plinth pin' | sed 's/^/        /'; fi

pin_api "$tested" behind; pin_out
if [ "$lines" = 1 ] && grep -qF "$live_line" <<<"$out" \
   && grep -q "INFO    plinth pin: the workflows call $sha40, newer than $tested (v9.0.0) that $target_ref was tested with; the live pin is kept, never moved backwards" <<<"$out"
then ok "live pin ahead of the tested one: one line, kept because it is newer"
else bad "live ahead ($lines lines)"; printf '%s\n' "$out" | grep -E 'plinth|copier' | sed 's/^/        /'; fi
printed="$(FLOOR_CHECK_API_DIR="$pin_dir" python3 "$checker" --root "$pcopy2" --print-update-command --plinth-pin tested 2>"$work/print-err")"; rc=$?
if [ "$rc" = 1 ] && [ -z "$printed" ] && grep -q "never moved backwards" "$work/print-err" && ! grep -q "^recommended:" "$work/print-err"; then ok "--plinth-pin tested never prints a line that moves the pin backwards, nor recommends one: exit 1, says why"
else bad "--plinth-pin tested, live ahead (rc=$rc, stdout '$printed')"; fi

pin_api "$sha40" -; pin_out
if [ "$lines" = 1 ] && grep -qF "$live_line" <<<"$out" && ! grep -q "plinth pin:" <<<"$out"
then ok "live pin equal to the tested one: one line, no comparison"
else bad "equal ($lines lines)"; printf '%s\n' "$out" | grep -E 'plinth|copier' | sed 's/^/        /'; fi

pin_api "$tested" -; pin_out
if [ "$lines" = 1 ] && grep -qF "$live_line" <<<"$out" \
   && grep -q "INFO    plinth pin: the workflows call $sha40; $target_ref was tested with $tested, but the two were not compared (offline or API error); the live pin is kept" <<<"$out"
then ok "the compare unreadable: one line, the comparison named as not read"
else bad "compare unread ($lines lines)"; printf '%s\n' "$out" | grep -E 'plinth|copier' | sed 's/^/        /'; fi
printed="$(FLOOR_CHECK_API_DIR="$pin_dir" python3 "$checker" --root "$pcopy2" --print-update-command --plinth-pin tested 2>/dev/null)"; rc=$?
if [ "$rc" = 1 ] && [ -z "$printed" ]; then ok "--plinth-pin tested past an unread comparison prints no line, exit 1"
else bad "--plinth-pin tested, compare unread (rc=$rc, stdout '$printed')"; fi

pin_api "$tested" diverged; pin_out
if [ "$lines" = 1 ] && grep -q "were not compared (the two commits have diverged)" <<<"$out"
then ok "diverged commits: one line, no direction claimed"
else bad "diverged ($lines lines)"; printf '%s\n' "$out" | grep -E 'plinth|copier' | sed 's/^/        /'; fi

pin_api - ahead; pin_out
if [ "$lines" = 1 ] && grep -qF "$live_line" <<<"$out" \
   && grep -q "INFO    plinth pin: the one $target_ref was tested with was not read (coolbress/plinth-template copier.yml at $target_ref: offline or API error); the live pin $sha40 is kept" <<<"$out"
then ok "the tested pin unreadable: one line, named as not read"
else bad "tested unread ($lines lines)"; printf '%s\n' "$out" | grep -E 'plinth|copier' | sed 's/^/        /'; fi
out="$(python3 "$checker" --root "$pcopy2" --no-network 2>&1)"; lines="$(grep -c '^  INFO    uvx .*copier update' <<<"$out")"
if [ "$lines" = 1 ] && grep -q "plinth pin: the one $target_ref was tested with was not read" <<<"$out"; then ok "offline: one line, the tested pin not read"
else bad "offline ($lines lines)"; fi
pin_api "not-a-sha" ahead; pin_out
if [ "$lines" = 1 ] && grep -q "has no plinth_sha default that is a full commit SHA" <<<"$out"; then ok "a plinth_sha default that is not a full SHA is not read, not offered"
else bad "malformed default ($lines lines)"; printf '%s\n' "$out" | grep -E 'plinth pin' | sed 's/^/        /'; fi
python3 "$checker" --root "$pcopy2" --no-network --plinth-pin tested >/dev/null 2>&1; rc=$?
if [ "$rc" = 2 ]; then ok "--plinth-pin without --print-update-command is a usage error"; else bad "--plinth-pin alone (rc=$rc)"; fi
python3 "$checker" --root "$pcopy2" --print-update-command --plinth-pin newest >/dev/null 2>&1; rc=$?
if [ "$rc" = 2 ]; then ok "an unknown --plinth-pin value is a usage error"; else bad "--plinth-pin newest (rc=$rc)"; fi

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
  if grep -q "PASS  template: the recorded tag is the target tag (v9.9.9)" <<<"$out"
  then ok "the target tag is read from scripts/new-project.sh beside the checker, not a copy inside it (a fake v9.9.9 pin is honoured)"
  else bad "the checker did not honour a rewritten new-project.sh beside it"; printf '%s\n' "$out" | grep template | sed 's/^/        /'; fi
fi
selfdir2="$work/selfcheck-missing"; mkdir -p "$selfdir2"
cp "$checker" "$selfdir2/floor-check.py"
out="$(python3 "$selfdir2/floor-check.py" --root "$good" --no-network 2>&1)"
if grep -q "SKIP  template drift not verified (scripts/new-project.sh not found beside the checker" <<<"$out"
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
  if grep -qE "$want" <<<"$out"; then ok "$desc"; else bad "$desc (expected /$want/)"; printf '%s\n' "$out" | grep -iE 'ci job|ci\.yml|failed' | sed 's/^/        /'; fi
}
tmpl_ci="$(printf 'name: CI\non:\n  pull_request:\njobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s # v1.0.0\n    permissions:\n      contents: read\n' "$sha40")"
caller "the template's ci.yml passes, read from the checkout offline and saying so" "$tmpl_ci" \
  "PASS  the ci job in the checkout, not the default branch \(--no-network\) calls coolbress/plinth/\.github/workflows/python-ci\.yml@$sha40"
caller "the ci job replaced by plain jobs of the same check names is a FAIL" \
  "$(printf 'jobs:\n  install:\n    name: ci / install\n    runs-on: ubuntu-latest\n    steps:\n      - run: "true"\n  tools:\n    name: ci / tools\n    runs-on: ubuntu-latest\n    steps:\n      - run: "true"\n')" \
  "FAIL  .*no \`ci\` job"
caller "a ci job that runs its own steps is a FAIL" \
  "$(printf 'jobs:\n  ci:\n    runs-on: ubuntu-latest\n    steps:\n      - run: |\n          echo uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n' "$sha40")" \
  "FAIL  .*ci\` job.*calls no reusable workflow"
caller "another repository's python-ci.yml is a FAIL" \
  "$(printf 'jobs:\n  ci:\n    uses: coolbress/other/.github/workflows/python-ci.yml@%s\n' "$sha40")" \
  "FAIL  .*calls coolbress/other/"
caller "a fork's python-ci.yml is a FAIL" \
  "$(printf 'jobs:\n  ci:\n    uses: someone/plinth/.github/workflows/python-ci.yml@%s\n' "$sha40")" \
  "FAIL  .*calls someone/plinth/"
caller "a local workflow is a FAIL outside coolbress/plinth" \
  "$(printf 'jobs:\n  ci:\n    uses: ./.github/workflows/python-ci.yml\n')" \
  "FAIL  .*calls \./\.github/workflows/python-ci\.yml"
caller "plinth's workflow pinned to a tag is a FAIL" \
  "$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@v1.0.0\n')" \
  "FAIL  .*python-ci\.yml@v1\.0\.0.*full commit SHA"
caller "a tag pin's fix line looks up that tag's commit" \
  "$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@v1.0.0\n')" \
  "INFO    gh api repos/coolbress/plinth/commits/v1\.0\.0 --jq \.sha   \(then set the ci job's uses: to"
caller "a missing call's fix line looks up plinth's latest release" \
  "$(printf 'jobs:\n  install:\n    name: ci / install\n    steps:\n      - run: "true"\n')" \
  "INFO    gh api \"repos/coolbress/plinth/commits/\\\$\(gh api repos/coolbress/plinth/releases/latest --jq \.tag_name\)\" --jq \.sha   \(plinth's latest release; then set the ci job's uses: to"
caller "plinth's workflow pinned to a branch is a FAIL" \
  "$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@main\n')" \
  "FAIL  .*python-ci\.yml@main.*full commit SHA"
caller "a ci job with an if: condition is a FAIL: it can be skipped" \
  "$(printf "jobs:\n  ci:\n    if: github.head_ref == 'bootstrap'\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n" "$sha40")" \
  "FAIL  .*ci job.*if:.*skipped"
caller "a ci job with needs: is a FAIL: it is skipped with what it needs" \
  "$(printf 'jobs:\n  gate:\n    if: false\n    runs-on: x\n    steps:\n      - run: "true"\n  ci:\n    needs: gate\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n' "$sha40")" \
  "FAIL  .*ci job.*needs:.*skipped"
for key in 'name: decoy' 'strategy:' 'concurrency: x' 'timeout-minutes: 1'; do
  caller "  a ci job with '$key' is a FAIL: only uses, with, secrets and permissions are allowed" \
    "$(printf 'jobs:\n  ci:\n    %s\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n' "$key" "$sha40")" \
    "FAIL  .*ci job.*has ${key%%:*}:"
done
caller "a continuation line under uses: (YAML folds it into the value) is a SKIP, not a pass" \
  "$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n      extra\n' "$sha40")" \
  "SKIP  .*ci job.*not verified.*continues"
caller "with:, secrets: and permissions: on the ci job still pass" \
  "$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n    with:\n      if: x\n    secrets: inherit\n    permissions:\n      contents: read\n' "$sha40")" \
  "PASS  .*ci job"
caller "another of plinth's workflows is a FAIL" \
  "$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/third-party.yml@%s\n' "$sha40")" \
  "FAIL  .*calls coolbress/plinth/\.github/workflows/third-party\.yml"
caller "a quoted ci key and a quoted value are read" \
  "$(printf 'jobs:\n  "ci":\n    uses: "coolbress/plinth/.github/workflows/python-ci.yml@%s"\n' "$sha40")" \
  "PASS  .*ci job"
caller "a flow-style jobs mapping is a SKIP, not a pass" \
  "$(printf 'jobs: {ci: {uses: coolbress/plinth/.github/workflows/python-ci.yml@%s}}\n' "$sha40")" \
  "SKIP  .*ci job.*not verified"
caller "a ci job that is an alias is a SKIP, not a pass" \
  "$(printf 'x: &c\n  uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\njobs:\n  ci: *c\n' "$sha40")" \
  "SKIP  .*ci job.*not verified"
caller "a merge key inside the ci job is a SKIP, not a pass" \
  "$(printf 'x: &c\n  uses: coolbress/other/.github/workflows/python-ci.yml@%s\njobs:\n  ci:\n    <<: *c\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n' "$sha40" "$sha40")" \
  "SKIP  .*ci job.*not verified"
caller "an escaped quoted key (a second jobs YAML decodes) is a SKIP, not a pass" \
  "$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n"jo\\u0062s":\n  install:\n    runs-on: x\n' "$sha40")" \
  "SKIP  .*ci job.*not verified.*escape"
caller "an escaped quoted ci key is a SKIP, not a pass" \
  "$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n  "c\\x69":\n    runs-on: x\n' "$sha40")" \
  "SKIP  .*ci job.*not verified.*escape"
caller "an alias as a top-level key (a second jobs) is a SKIP, not a pass" \
  "$(printf 'name: x\nrun-name:\n  - &j jobs\njobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n*j :\n  ci:\n    uses: someone/else/.github/workflows/x.yml@%s\n' "$sha40" "$sha40")" \
  "SKIP  .*ci job.*not verified.*top-level"
for top in '!!str jobs:' '? jobs' '<<: *base' '---'; do
  caller "  a top-level line written as '$top' is a SKIP" \
    "$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n%s\n' "$sha40" "$top")" \
    "SKIP  .*ci job.*not verified.*top-level"
done
# A document marker opening the file is what yamllint's document-start rule
# asks for (#334); a second one starts another document and is still unread.
caller "a ci.yml opening with --- reads like the same file without it" "$(printf -- '---\n%s\n' "$tmpl_ci")" \
  "PASS  .*ci job.*calls coolbress/plinth/\.github/workflows/python-ci\.yml@$sha40"
caller "a --- with a comment, after a comment, also opens it" "$(printf -- '# c\n--- # start\n%s\n' "$tmpl_ci")" \
  "PASS  .*ci job"
caller "a leading --- and a second one (two documents) is a SKIP, not a pass" \
  "$(printf -- '---\n%s\n---\njobs:\n  ci:\n    runs-on: x\n' "$tmpl_ci")" \
  "SKIP  .*ci job.*not verified.*top-level.*---"
caller "a --- carrying content on its line is a SKIP, not a pass" "$(printf -- '--- !!map\n%s\n' "$tmpl_ci")" \
  "SKIP  .*ci job.*not verified.*top-level"
# A `: |` in a trailing comment opens no block scalar (#334); a real one still does.
for c in '# note: |' '# note: >' '# a: |-'; do
  caller "  a jobs: line whose comment ends '$c' still shows the jobs" \
    "$(printf 'jobs:  %s\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n' "$c" "$sha40")" \
    "PASS  .*ci job"
done
caller "a run: | with a trailing comment is still a block scalar" \
  "$(printf 'jobs:\n  ci:\n    runs-on: ubuntu-latest\n    steps:\n      - run: |  # note\n          uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n' "$sha40")" \
  "FAIL  .*ci\` job.*calls no reusable workflow"
caller "a flow value on a top-level key (on: [push, pull_request]) still reads" \
  "$(printf 'on: [push, pull_request]\njobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n' "$sha40")" \
  "PASS  .*ci job"
caller "two ci keys are a SKIP, not a pass" \
  "$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n  ci:\n    runs-on: x\n' "$sha40")" \
  "SKIP  .*ci job.*not verified"
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
  "SKIP  .*ci job.*not verified.*more than one with"
caller "a loosened input on a workflow that is not plinth's is not judged (the call is the FAIL)" \
  "$(printf 'jobs:\n  ci:\n    uses: someone/else/.github/workflows/python-ci.yml@%s\n    with:\n      max-diff-lines: 0\n' "$sha40")" \
  "FAIL  .*calls someone/else"
copy="$work/caller"; rm -rf "$copy"; cp -R "$good" "$copy"
printf 'jobs:\n  ci:\n    uses: someone/else/.github/workflows/python-ci.yml@%s\n    with:\n      max-diff-lines: 0\n' "$sha40" > "$copy/.github/workflows/ci.yml"
if python3 "$checker" --root "$copy" --archetype cli --no-network 2>&1 | grep -q 'max-diff-lines'; then bad "  and no max-diff-lines line"
else ok "  and no max-diff-lines line"; fi

# Counted: a SKIP here is one more "not verified" in the summary.
# The baseline offline run without --repo has one: the unchecked wall.
skipcount() { # <description> <expected not-verified count> <shell to change the copy>
  local copy="$work/caller"; rm -rf "$copy"; cp -R "$good" "$copy"; ( cd "$copy" && eval "$3" )
  local out; out="$(python3 "$checker" --root "$copy" --archetype cli --no-network 2>&1)"
  if grep -q -- "-- 0 failed, $2 not verified" <<<"$out" && grep -q 'SKIP  .*ci job' <<<"$out"; then ok "$1"
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
from_api() { # <description> <default-branch ci.yml or __404__ or raw JSON after "json:"> <checkout ci.yml> <expected regex> [<repo>]
  local desc="$1" remote="$2" local_ci="$3" want="$4" repo="${5:-o/r}"
  local f="$capi/repos/$repo/contents/.github/workflows/ci.yml.json"; rm -f "$f"
  case "$remote" in __404__) ;; json:*) printf '%s' "${remote#json:}" > "$f" ;; *) contents "$remote" > "$f" ;; esac
  local copy="$work/caller"; rm -rf "$copy"; cp -R "$good" "$copy"
  printf '%s' "$local_ci" > "$copy/.github/workflows/ci.yml"
  local out; out="$(FLOOR_CHECK_API_DIR="$capi" python3 "$checker" --root "$copy" --archetype cli --repo "$repo" 2>&1)"
  if grep -qE "$want" <<<"$out"; then ok "$desc"; else bad "$desc (expected /$want/)"; printf '%s\n' "$out" | grep -iE 'ci job|ci\.yml' | sed 's/^/        /'; fi
}
plain_ci="$(printf 'jobs:\n  install:\n    name: ci / install\n    steps:\n      - run: "true"\n')"
from_api "a default branch without the call is a FAIL, though the checkout has it" "$plain_ci" "$tmpl_ci" \
  "FAIL  .*default branch.*no \`ci\` job"
from_api "a default branch with the call passes, though the checkout lost it" "$tmpl_ci" "$plain_ci" \
  "PASS  .*ci job.*default branch"
from_api "no ci.yml on the default branch is a FAIL" "__404__" "$tmpl_ci" \
  "FAIL  .*no \.github/workflows/ci\.yml on the default branch"
from_api "a repository the API cannot see at all is a SKIP, not a missing ci.yml" "__404__" "$tmpl_ci" \
  "SKIP  .*ci job.*not verified.*repos/x/gone" x/gone
from_api "an API answer that is not a file is a SKIP, not a pass" "json:[]" "$tmpl_ci" \
  "SKIP  .*ci job.*not verified"
# ci / floor-check passes --caller-from-checkout: it reads the pull request's
# own ci.yml, so a pull request that repairs a broken default branch can merge,
# and one that keeps the call but weakens it fails before the merge.
from_checkout() { # <description> <default-branch ci.yml> <checkout ci.yml> <expected regex>
  local f="$capi/repos/o/r/contents/.github/workflows/ci.yml.json"; contents "$2" > "$f"
  local copy="$work/caller"; rm -rf "$copy"; cp -R "$good" "$copy"; printf '%s' "$3" > "$copy/.github/workflows/ci.yml"
  local out; out="$(FLOOR_CHECK_API_DIR="$capi" python3 "$checker" --root "$copy" --archetype cli --repo o/r --caller-from-checkout 2>&1)"
  if grep -qE "$4" <<<"$out"; then ok "$1"; else bad "$1 (expected /$4/)"; printf '%s\n' "$out" | grep -iE 'ci job|ci\.yml' | sed 's/^/        /'; fi
}
tag_ci="$(printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@v1.0.0\n')"
from_checkout "--caller-from-checkout: a pull request repairing a broken default branch passes (no deadlock)" "$tag_ci" "$tmpl_ci" \
  "PASS  the ci job in the checkout \(--caller-from-checkout\) calls coolbress/plinth/"
from_checkout "--caller-from-checkout: a pull request weakening the call fails before the merge" "$tmpl_ci" "$tag_ci" \
  "FAIL  the ci job in the checkout \(--caller-from-checkout\) calls .*@v1\.0\.0"
own="$(cat "$root/.github/workflows/ci.yml")"
from_api "coolbress/plinth's own ci.yml passes for coolbress/plinth" "$own" "$own" \
  "PASS  .*ci job.*\./\.github/workflows/plinth-ci\.yml" coolbress/plinth
from_api "another local workflow is a FAIL even for coolbress/plinth" \
  "$(printf 'jobs:\n  ci:\n    uses: ./.github/workflows/no-checks.yml\n')" "$own" \
  "FAIL  .*calls \./\.github/workflows/no-checks\.yml" coolbress/plinth
from_api "the same file under any other --repo is a FAIL" "$own" "$own" \
  "FAIL  .*calls \./\.github/workflows/plinth-ci\.yml"

echo "-- a GitLab checkout is read as one (#543)"
# The good backend fixture as plinth-template v1.13.0 renders it for
# host: gitlab: no .github/, glab's denies, .gitlab/ templates, the include.
glgood="$work/glgood"; rm -rf "$glgood"; cp -R "$good" "$glgood"; rm -rf "$glgood/.git" "$glgood/.github"
mkdir -p "$glgood/.gitlab/issue_templates" "$glgood/.gitlab/merge_request_templates"
for f in Bug:bug Feature:enhancement Task:task; do printf '## What\n\n/label ~%s\n' "${f#*:}" > "$glgood/.gitlab/issue_templates/${f%%:*}.md"; done
printf '## What and why\n' > "$glgood/.gitlab/merge_request_templates/Default.md"
cat > "$glgood/.claude/settings.json" <<'JSON'
{"permissions":{"deny":["Bash(git push --force:*)","Bash(rm -rf:*)","Bash(glab auth status --show-token*)","Bash(glab auth status -t*)","Bash(glab config get token*)","Read(./.env)","Bash(. *.env*)","Bash(source *.env*)","Bash(cat *.env)","Bash(grep *.env)","Read(~/.config/glab-cli/**)"]}}
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
  if grep -qE -- "$want" <<<"$out"; then ok "$desc"; else bad "$desc (expected a line matching '$want')"; printf '%s\n' "$out" | grep -E 'FAIL|WARN|SKIP|gitlab' | sed 's/^/        /'; fi
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
gl "Dependabot's absence is an INFO, not a FAIL" ":" "INFO  Dependabot does not run on GitLab" --no-network
# Offline, the rule runs only with a PyYAML already here; without one, nothing is installed.
if python3 -c 'import yaml' 2>/dev/null; then
  gl "--no-network with PyYAML here: the include is read" ":" "PASS  \.gitlab-ci\.yml includes plinth's GitLab pipeline at a full commit SHA" --no-network
else
  gl "--no-network without PyYAML: the include is a SKIP, not a pass" ":" "SKIP  \.gitlab-ci\.yml includes plinth's GitLab pipeline at a full commit SHA not verified: .*--no-network" --no-network
fi
gl "the host comes from .copier-answers.yml" ":" "host=gitlab" --no-network
gl "--host gitlab reads it without the answer" "sed -i.bak '/^host:/d' .copier-answers.yml" "^-- 0 failed" --no-network --host gitlab
gl "--host github overrides the answer" ":" "FAIL  \.github/dependabot\.yml missing" --no-network --host github
gl "an unknown host in the answers is a SKIP, read as github" "sed -i.bak 's/^host: gitlab/host: bitbucket/' .copier-answers.yml" "SKIP  \.copier-answers\.yml says host: bitbucket" --no-network
for d in 'glab auth status --show-token' 'glab auth status -t' 'glab config get token' 'glab-cli'; do
  case "$d" in glab-cli) what="glab config reads" ;; *) what="$d" ;; esac
  gl "a deny list without $what fails" "python3 -c 'import json,sys; p=\".claude/settings.json\"; j=json.load(open(p)); j[\"permissions\"][\"deny\"]=[x for x in j[\"permissions\"][\"deny\"] if sys.argv[1] not in x]; json.dump(j,open(p,\"w\"))' '$d'" \
    "FAIL  \.claude/settings\.json does not deny $what" --no-network
done
gl "no SECURITY.md fails on GitLab, with no inheritance to look for" "rm SECURITY.md" "FAIL  SECURITY\.md missing: on GitLab nothing is inherited" --no-network
gl "no issue template fails" "rm -r .gitlab/issue_templates" "FAIL  no issue template under \.gitlab/issue_templates/" --no-network
gl "no merge request template fails" "rm -r .gitlab/merge_request_templates" "FAIL  no merge request template under \.gitlab/merge_request_templates/" --no-network
gl "an issue template without /label is a WARN" "printf '## What\n' > .gitlab/issue_templates/Bug.md" "WARN  Bug\.md has no \`/label ~name\` line" --no-network
gl "a backend without the docker-image job fails" "printf 'include: []\n' > .gitlab-ci.yml" "FAIL  \.gitlab-ci\.yml has no \`docker-image\` job" --no-network
# The include rule is gitlab/python-ci.yml's own; these read it through the
# checker. With no PyYAML here, the job's pinned PyYAML is installed from
# PyPI, so these need the network, as tests/gitlab-ci-cases.sh does. A
# python3 with neither PyYAML nor a version those wheels cover gets a SKIP
# that says so, and the rule's cases cannot run on it.
if ! python3 -c 'import yaml' 2>/dev/null && ! python3 -c 'import sys; sys.exit(not (3, 11) <= sys.version_info[:2] <= (3, 14))'; then
  gl "no PyYAML on a python3 outside 3.11 to 3.14: a SKIP naming the range" ":" "SKIP  .*pinned for CPython 3\.11 to 3\.14 only"
  echo "  NOTE  the include rule's cases need a python3 with PyYAML, or 3.11 to 3.14: $(python3 --version 2>&1)"
else
gl "an include at a full SHA with a checksum passes" ":" "PASS  \.gitlab-ci\.yml includes plinth's GitLab pipeline at a full commit SHA \($glsha\)"
grep -q "PASS  the include names a checksum" <<<"$out" && ok "the checksum is a PASS" || bad "the checksum is a PASS"
gl "no checksum is a SKIP, not a pass" "glci 'include:
  - remote: $glurl' > .gitlab-ci.yml" "SKIP  the bytes GitLab fetched are plinth's file, the include names no checksum"
gl "an include at a tag fails" "glci 'include:
  - remote: https://raw.githubusercontent.com/coolbress/plinth/v1.16.0/gitlab/python-ci.yml' > .gitlab-ci.yml" \
  "FAIL  \.gitlab-ci\.yml includes plinth's GitLab pipeline at a full commit SHA, it includes it at v1\.16\.0"
gl "plinth by another URL fails" "glci 'include:
  - remote: https://github.com/coolbress/plinth/raw/$glsha/gitlab/python-ci.yml' > .gitlab-ci.yml" \
  "FAIL  .*it includes plinth by a URL that is not"
gl "no include fails" "glci 'include: []' > .gitlab-ci.yml" "FAIL  .*no include of https://raw\.githubusercontent\.com/coolbress/plinth/<commit-sha>/gitlab/python-ci\.yml was found"
gl "a yaml.py in the checkout is not imported in place of PyYAML" "printf 'print(\"pass: PLANTED\")\n' > yaml.py" \
  "PASS  \.gitlab-ci\.yml includes plinth's GitLab pipeline at a full commit SHA"
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
has "only glab's helper for gitlab.com: an INFO, not a PASS" "INFO  git asks only glab for gitlab\.com; no other credential found"
has "a github.com login in ~/.netrc is not gitlab.com's" "INFO  no gitlab\.com login in "
has "the login glab stores is a SKIP" "SKIP  the login glab stores for gitlab\.com not verified"
has "SSH points at GitLab's keys" "SKIP  SSH keys not verified here: GitLab's Preferences"
lacks "a helper for github.com alone is not reported on GitLab" "WARN"
lacks "gh is not asked about on GitLab" "gh stores|accounts stored in gh"
glcred GITLAB_TOKEN=x
has "GITLAB_TOKEN set is a WARN" "WARN  GITLAB_TOKEN is set in this environment: glab"
glcred GLAB_CONFIG_DIR=/elsewhere
has "GLAB_CONFIG_DIR set is a SKIP" "SKIP  GLAB_CONFIG_DIR is set"
printf '[credential]\n\thelper = osxkeychain\n[credential "https://gitlab.com"]\n\thelper = !glab auth git-credential\n' > "$glc/gitconfig"
glcred
has "another helper that applies to gitlab.com is a WARN" "WARN  git has 1 credential helper for gitlab\.com besides glab's: osxkeychain"
printf 'machine gitlab.com login me password x\n' > "$glc/home/.netrc"
glcred
has "a gitlab.com login in ~/.netrc is a WARN" "WARN  .*\.netrc holds a login for gitlab\.com"

echo "-- the update line on GitLab carries the include's checksum (#547 review)"
glold="$work/glold"; rm -rf "$glold"; cp -R "$glgood" "$glold"
sed -i.bak 's/^_commit: .*/_commit: v1.0.0/' "$glold/.copier-answers.yml"
glint="L3/GAoKaw0Arw6hDCKeKQlV1QPEgHYxGBHsH4zG1IY8="
printed="$(FLOOR_CHECK_API_DIR="$work/noapi" python3 "$checker" --root "$glold" --print-update-command 2>&1)"; rc=$?
case "$printed" in *"--data plinth_sha=$glsha --data plinth_gitlab_integrity=$glint") [ "$rc" = 0 ] && ok "the live pin and its checksum from .gitlab-ci.yml" || bad "update line rc=$rc" ;;
  *) bad "the GitLab update line: '$printed'" ;; esac
glci "include:
  - remote: $glurl" > "$glold/.gitlab-ci.yml"
printed="$(FLOOR_CHECK_API_DIR="$work/noapi" python3 "$checker" --root "$glold" --print-update-command 2>&1)"; rc=$?
[ "$rc" = 1 ] && grep -q "not one \`remote:\` line followed by its \`integrity:\` line" <<<"$printed" \
  && ok "an include without a checksum gives no update line, saying why" || bad "no checksum: rc=$rc '$printed'"
glci "include:
  - remote: https://raw.githubusercontent.com/coolbress/plinth/v1.16.0/gitlab/python-ci.yml
    integrity: sha256-$glint" > "$glold/.gitlab-ci.yml"
printed="$(FLOOR_CHECK_API_DIR="$work/noapi" python3 "$checker" --root "$glold" --print-update-command 2>&1)"; rc=$?
[ "$rc" = 1 ] && grep -q "is at v1.16.0, not a full commit SHA" <<<"$printed" && ok "an include at a tag gives no update line" || bad "tag: rc=$rc '$printed'"
cp "$glgood/.gitlab-ci.yml" "$glold/.gitlab-ci.yml"
sed -i.bak '/^host:/d' "$glold/.copier-answers.yml"
printed="$(FLOOR_CHECK_API_DIR="$work/noapi" python3 "$checker" --root "$glold" --host gitlab --print-update-command 2>&1)"; rc=$?
case "$printed" in *"--data plinth_gitlab_integrity=$glint") [ "$rc" = 0 ] && ok "--host gitlab without the answer: the update line reads the include" || bad "--host gitlab update rc=$rc" ;;
  *) bad "--host gitlab without the answer: '$printed'" ;; esac
out="$(FLOOR_CHECK_API_DIR="$work/noapi" python3 "$checker" --root "$glold" --host gitlab --no-network 2>&1)"
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
printed="$(FLOOR_CHECK_API_DIR="$work/api-glpin" python3 "$checker" --root "$glold" --print-update-command --plinth-pin tested 2>"$work/glpin-err")"; rc=$?
case "$printed" in *"--data plinth_sha=$tested --data plinth_gitlab_integrity=$newint") [ "$rc" = 0 ] && ok "the tested pin moves with the checksum that tag was tested with" || bad "tested rc=$rc" ;;
  *) bad "the tested GitLab line: '$printed'"; sed 's/^/        /' "$work/glpin-err" ;; esac
grep -q "plinth pin: the include is at $glsha" "$work/glpin-err" && ok "the note says the include, not the workflows" || { bad "the GitLab note"; sed 's/^/        /' "$work/glpin-err"; }
glpin_api -
printed="$(FLOOR_CHECK_API_DIR="$work/api-glpin" python3 "$checker" --root "$glold" --print-update-command --plinth-pin tested 2>"$work/glpin-err")"; rc=$?
[ "$rc" = 1 ] && [ -z "$printed" ] && grep -q "its checksum was not read" "$work/glpin-err" \
  && ok "no tested checksum: no tested line, the live pin kept" || { bad "tested without checksum: rc=$rc '$printed'"; sed 's/^/        /' "$work/glpin-err"; }

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
  if grep -qE -- "$3" <<<"$out"; then ok "$1"; else bad "$1 (expected a line matching '$3')"; printf '%s\n' "$out" | grep -vE '^  PASS  ' | sed 's/^/        /'; fi
}
setp() { python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); (d[0] if isinstance(d, list) else d).update(json.loads(sys.argv[2])); json.dump(d,open(p,"w"))' "$@"; }
addrule() { python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d.append(json.loads(sys.argv[2])); json.dump(d,open(p,"w"))' "$@"; }
pb="protected_branches?per_page=100.json"
glw "the door's wall passes, with nothing unverified" ":" "^-- 0 failed, 0 not verified$"
for line in "PASS  main is protected on o/r: no one pushes, Maintainers merge, no force push" \
  "PASS  o/r merges only on a green pipeline" "PASS  o/r squashes every merge request and fast-forwards" \
  "PASS  \.gitlab-ci\.yml on main includes plinth's GitLab pipeline at a full commit SHA" "PASS  every label the door creates is present"; do
  grep -qE -- "$line" <<<"$out" && ok "the passing wall: $line" || bad "the passing wall: missing $line"
done
glw "an unprotected default branch fails, with the call that protects it" "printf [] > 'protected_branches?per_page=100.json'" "FAIL  main is not a protected branch on o/r"
grep -q 'INFO    glab api --hostname gitlab.com -X POST projects/o%2Fr/protected_branches -f name=main -F push_access_level=0' <<<"$out" \
  && ok "the unprotected branch names the POST" || bad "the unprotected branch names the POST"
glw "Developers allowed to push fails" "setp \"\$pb\" '{\"push_access_levels\":[{\"access_level\":30,\"access_level_description\":\"Developers + Maintainers\"}]}'" "FAIL  main's protection on o/r is weaker than the door's \(rules that apply: main\): push allowed"
glw "a user allowed to push fails" "setp \"\$pb\" '{\"push_access_levels\":[{\"access_level\":0},{\"access_level\":40,\"user_id\":7}]}'" "FAIL  .*push allowed"
glw "Developers allowed to merge fails" "setp \"\$pb\" '{\"merge_access_levels\":[{\"access_level\":30,\"access_level_description\":\"Developers + Maintainers\"}]}'" "FAIL  .*merge allowed to \['Developers \+ Maintainers'\]"
glw "a wildcard rule that lets Developers push opens main: FAIL" "addrule \"\$pb\" '{\"name\":\"*\",\"push_access_levels\":[{\"access_level\":30,\"access_level_description\":\"Developers + Maintainers\"}],\"merge_access_levels\":[{\"access_level\":40}],\"allow_force_push\":false}'" \
  "FAIL  main's protection on o/r is weaker than the door's \(rules that apply: main, \*\): push allowed"
glw "a wildcard rule with force push opens main: FAIL" "addrule \"\$pb\" '{\"name\":\"ma*\",\"push_access_levels\":[{\"access_level\":0}],\"merge_access_levels\":[{\"access_level\":40}],\"allow_force_push\":true}'" \
  "FAIL  .*rules that apply: main, ma\*.*force push True"
glw "a rule for other branches does not apply" "addrule \"\$pb\" '{\"name\":\"release/*\",\"push_access_levels\":[{\"access_level\":30}],\"merge_access_levels\":[{\"access_level\":30}],\"allow_force_push\":true}'" \
  "PASS  main is protected on o/r: .*\(rules that apply: main\)"
glw "a wildcard rule alone protects main" "printf '[{\"name\":\"*\",\"push_access_levels\":[{\"access_level\":0}],\"merge_access_levels\":[{\"access_level\":40}],\"allow_force_push\":false}]' > \"\$pb\"" \
  "PASS  main is protected on o/r: .*\(rules that apply: \*\)"
glw "force push allowed fails" "setp \"\$pb\" '{\"allow_force_push\":true}'" "FAIL  .*force push True, want false"
glw "an unreadable protection is a SKIP" "rm \"\$pb\"; : > 'protected_branches?per_page=100.error'" "SKIP  the protection of main not verified"
glw "pipelines need not succeed: FAIL" "setp ../o%2Fr.json '{\"only_allow_merge_if_pipeline_succeeds\":false}'" "FAIL  the merge checks of o/r let a merge request merge without a green pipeline: only_allow_merge_if_pipeline_succeeds=False"
glw "skipped pipelines counted: FAIL" "setp ../o%2Fr.json '{\"allow_merge_on_skipped_pipeline\":true}'" "FAIL  .*allow_merge_on_skipped_pipeline=True"
glw "squash not required: FAIL" "setp ../o%2Fr.json '{\"squash_option\":\"default_on\"}'" "FAIL  o/r merges other than squash and fast-forward: squash_option='default_on'"
glw "a merge commit method: FAIL" "setp ../o%2Fr.json '{\"merge_method\":\"merge\"}'" "FAIL  .*merge_method='merge'"
glw "merge settings not returned are a SKIP" "python3 -c 'import json; p=\"../o%2Fr.json\"; d=json.load(open(p)); [d.pop(k) for k in (\"squash_option\",\"merge_method\")]; json.dump(d,open(p,\"w\"))'" "SKIP  squash_option, merge_method of o/r not verified: GitLab did not return them"
grep -q "PASS  o/r merges only on a green pipeline" <<<"$out" && ok "the merge checks returned are still judged" || bad "the merge checks returned are still judged"
glw "a readable mismatch fails beside a missing field" "python3 -c 'import json; p=\"../o%2Fr.json\"; d=json.load(open(p)); d.pop(\"squash_option\"); d[\"only_allow_merge_if_pipeline_succeeds\"]=False; d[\"merge_method\"]=\"merge\"; json.dump(d,open(p,\"w\"))'" \
  "FAIL  the merge checks of o/r let a merge request merge without a green pipeline: only_allow_merge_if_pipeline_succeeds=False"
grep -q "FAIL  o/r merges other than squash and fast-forward: merge_method='merge'" <<<"$out" && grep -q "SKIP  squash_option of o/r not verified: GitLab did not return it" <<<"$out" \
  && ok "the readable merge method fails and only the missing squash option is a SKIP" || { bad "partial merge shape"; printf '%s\n' "$out" | grep -E 'FAIL|SKIP' | sed 's/^/        /'; }
glw "an unreadable project is a SKIP, and the checkout's include is read" "rm ../o%2Fr.json" "SKIP  the GitLab wall of o/r not verified: it was not found"
grep -q "PASS  \.gitlab-ci\.yml includes plinth's GitLab pipeline" <<<"$out" && ok "the checkout's include stands in" || bad "the checkout's include stands in"
glw "the include on the default branch is read, not the checkout's" "glci 'include:
  - remote: https://raw.githubusercontent.com/coolbress/plinth/main/gitlab/python-ci.yml' > 'repository/files/.gitlab-ci.yml/raw?ref=main'" \
  "FAIL  \.gitlab-ci\.yml on main includes plinth's GitLab pipeline at a full commit SHA, it includes it at main"
glw "no definition on the default branch fails" "rm 'repository/files/.gitlab-ci.yml/raw?ref=main'" "FAIL  no \.gitlab-ci\.yml on main of o/r"
glw "ci_config_path is the definition read" "setp ../o%2Fr.json '{\"ci_config_path\":\"ci/main.yml\"}'; mkdir -p repository/files/ci%2Fmain.yml; cp 'repository/files/.gitlab-ci.yml/raw?ref=main' 'repository/files/ci%2Fmain.yml/raw?ref=main'" \
  "PASS  ci/main\.yml on main includes plinth's GitLab pipeline"
glw "a definition in another project is a SKIP" "setp ../o%2Fr.json '{\"ci_config_path\":\".gitlab-ci.yml@g/other\"}'" "SKIP  the include on main not verified: the pipeline definition is \.gitlab-ci\.yml@g/other"
glw "a missing label is a WARN with glab's command" "printf '[]' > 'labels?per_page=100.json'" "WARN  labels the door creates that are missing: feat, "
grep -q "INFO    glab label create --name feat --color '#ededed' --repo o/r" <<<"$out" && ok "the missing label names glab label create" || bad "the missing label names glab label create"
glw "unreadable labels are a SKIP" "rm 'labels?per_page=100.json'; : > 'labels?per_page=100.error'" "SKIP  labels not verified"
out="$(FLOOR_CHECK_API_DIR="$work/noapi" FLOOR_CHECK_GITLAB_API_DIR="$work/glapi" python3 "$checker" --root "$glgood" --repo o/r --no-network 2>&1)"
grep -q "SKIP  --no-network: the GitLab wall not checked" <<<"$out" && ok "--no-network with --repo: the wall is a SKIP" || bad "--no-network with --repo: the wall is a SKIP"

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
grep -q '^  FAIL  pyproject.toml missing$' <<<"$out" && grep -q '^  FAIL  uv.lock missing: CI runs `uv sync --locked`$' <<<"$out" \
  && ok "neither file: pyproject.toml and uv.lock still fail" || bad "neither file: pyproject.toml and uv.lock still fail"
# A Python project one level down is the case --project names (#221), even
# with a package.json at the root: that hint stands, nothing does not apply.
below="$work/js-below"; rm -rf "$below"; cp -R "$neither" "$below"; mkdir "$below/api"
printf '[project]\nname = "api"\n' > "$below/api/pyproject.toml"; printf '{}\n' > "$below/package.json"
js_run "$below" --no-network
lacks "package.json at the root, pyproject.toml one level down: no line of #681's" "$js_new"
grep -q "FAIL  pyproject.toml missing here; found api/pyproject.toml: run again with --project=api" <<<"$out" \
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
grep -q "FAIL  main: required checks dropped:" <<<"$out" && ok "Python with package.json: the ruleset's Python checks are still expected" \
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
for want in 'PASS  README.md present' 'PASS  .claude/settings.json denies gh auth token' 'PASS  .gitattributes normalises line endings' \
            'PASS  .github/dependabot.yml' 'PASS  no dotenv file is tracked' 'PASS  relative links in'; do
  grep -qF -- "$want" <<<"$out" && ok "JavaScript only: $want" || bad "JavaScript only: expected '$want'"
done
jsb="$work/js-broken"; rm -rf "$jsb"; cp -R "$js" "$jsb"; rm "$jsb/AGENTS.md" "$jsb/.claude/settings.json"; printf '' > "$jsb/.gitattributes"
printf 'jobs:\n  t:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v4\n' > "$jsb/.github/workflows/build.yml"
printf 'X=1\n' > "$jsb/.env"; git -C "$jsb" add -A; git -C "$jsb" add -f .env
js_run "$jsb" --no-network
for want in 'FAIL  AGENTS.md missing or empty' 'FAIL  .claude/settings.json missing' 'FAIL  .gitattributes does not normalise' \
            'WARN  .*\.env' 'WARN  .*actions/checkout@v4'; do
  grep -qE -- "$want" <<<"$out" && ok "JavaScript only, broken: $want" || bad "JavaScript only, broken: expected '$want'"
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
grep -q -- '^  N/A   pyproject.toml does not apply: ' <<<"$out" && grep -q -- ', 4 do not apply$' <<<"$out" \
  && ok "package.json one directory down, --project names it: read as JavaScript" || bad "--project web: read as JavaScript"
js_run "$mono" --no-network
grep -q '^  FAIL  pyproject.toml missing$' <<<"$out" && ! grep -qE "$js_new" <<<"$out" \
  && ok "package.json one directory down, no --project: the root reads as before" || bad "no --project: the root reads as before"
# The wall: the ruleset's Python-only required checks do not apply; every
# other rule, push protection and CodeQL are judged as before.
js_wall "$js"
grep -qE "^  N/A   main: requiring ci / pr-title, ci / lint, ci / typecheck, ci / test, ci / build, ci / secrets, ci / deps, ci / diff-size, ci / floor-check does not apply: " <<<"$out" \
  && ok "JavaScript only, wall: the Python-only required checks do not apply, named" || bad "JavaScript only, wall: the required checks line"
lacks "JavaScript only, wall: no required-checks verdict" 'required checks (dropped|are|come)|required_status_checks rule|expected checks'
grep -qF "N/A   the ci job's call to coolbress/plinth/.github/workflows/python-ci.yml does not apply" <<<"$out" \
  && ok "JavaScript only, wall: the ci job is not read from the default branch either" || bad "JavaScript only, wall: the ci job line"
for want in 'PASS  main: deletion rule active' 'PASS  main: merge methods within' 'PASS  ruleset 1: no bypass actors' \
            'PASS  push protection' 'PASS  main: CodeQL enforced (rule)' 'PASS  squash commits carry'; do
  grep -qF -- "$want" <<<"$out" && ok "JavaScript only, wall: $want" || bad "JavaScript only, wall: expected '$want'"
done
grep -qE -- '^-- 0 failed, [0-9]+ not verified, 5 do not apply$' <<<"$out" && ok "JavaScript only, wall: five items do not apply" \
  || { bad "JavaScript only, wall: summary"; grep -E '^  (FAIL|N/A)|^--' <<<"$out" | sed 's/^/        /'; }
# CodeQL's default setup is asked for the repository's language (#681 review):
# Python alone leaves the JavaScript unscanned, and the fix names its language.
grep -q "WARN  CodeQL default setup analyses \['actions', 'python'\], not the JavaScript or TypeScript code" <<<"$out" \
  && grep -q "INFO    gh api -X PATCH repos/o/r/code-scanning/default-setup -f 'languages\[\]=actions' -f 'languages\[\]=javascript-typescript'" <<<"$out" \
  && ok "JavaScript only, wall: CodeQL analysing Python alone is a WARN with the JavaScript fix" || bad "JavaScript only, wall: CodeQL languages WARN"
for l in javascript-typescript javascript typescript; do
  printf '{"state":"configured","languages":["actions","%s"],"query_suite":"default"}' "$l" > "$api/repos/o/r/code-scanning/default-setup.json"
  js_wall "$js"
  grep -q "PASS  CodeQL default setup analyses \['actions', '$l'\]" <<<"$out" && ok "JavaScript only, wall: CodeQL analysing $l passes" || bad "JavaScript only, wall: CodeQL analysing $l passes"
done
js_wall "$py"
grep -q "WARN  CodeQL default setup analyses \['actions', 'typescript'\], not the Python under src/" <<<"$out" \
  && ok "Python only, wall: CodeQL analysing TypeScript alone still warns about the Python" || bad "Python only, wall: CodeQL languages WARN"
printf '%s' "$good_setup" > "$api/repos/o/r/code-scanning/default-setup.json"
# A rule the wall needs whatever the language still fails when it is gone.
printf '%s' "$good_rules" | jq -c 'map(select(.type != "deletion" and .type != "required_status_checks"))' > "$api/repos/o/r/rules/branches/main.json"
js_wall "$js"
grep -q "FAIL  main: deletion rule missing" <<<"$out" && ok "JavaScript only, wall: a missing deletion rule still fails" || bad "JavaScript only, wall: deletion rule"
lacks "JavaScript only, wall: no required-checks rule is not a finding" 'required_status_checks'
printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"
# --expect-checks names checks the door's ruleset does not; those are still judged.
js_wall "$js" --expect-checks "ci / lint, CodeQL"
grep -q "N/A   main: requiring ci / lint does not apply" <<<"$out" && grep -q "PASS  main: all 1 expected checks are required" <<<"$out" \
  && ok "JavaScript only, wall: a non-Python expected check is still judged" || { bad "JavaScript only, wall: --expect-checks"; grep -E 'N/A|expected checks' <<<"$out" | sed 's/^/        /'; }

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
