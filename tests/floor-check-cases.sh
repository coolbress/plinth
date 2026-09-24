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
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
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
printf '{"default_branch":"main","squash_merge_commit_title":"PR_TITLE","squash_merge_commit_message":"PR_BODY"}' > "$api/repos/o/r.json"
good_rules='[{"type":"deletion","ruleset_source_type":"Repository","ruleset_id":1},{"type":"non_fast_forward","ruleset_source_type":"Repository","ruleset_id":1},{"type":"pull_request","parameters":{"allowed_merge_methods":["squash"]},"ruleset_source_type":"Repository","ruleset_id":1},{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"ci / a"},{"context":"ci / b"},{"context":"CodeQL"}]},"ruleset_source_type":"Repository","ruleset_id":1},{"type":"code_scanning","parameters":{"code_scanning_tools":[{"tool":"CodeQL","alerts_threshold":"errors","security_alerts_threshold":"high_or_higher"}]},"ruleset_source_type":"Repository","ruleset_id":1}]'
printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"
printf '{"bypass_actors":[]}' > "$api/repos/o/r/rulesets/1.json"
mkdir -p "$api/repos/o/r/code-scanning"
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
  printf '{"default_branch":"main","squash_merge_commit_title":"PR_TITLE","squash_merge_commit_message":"PR_BODY"}' > "$api/repos/o/r.json"
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
printf '{"default_branch":"main","squash_merge_commit_title":"PR_TITLE","squash_merge_commit_message":"PR_BODY"}' > "$api/repos/o/r.json"
rm -f "$api/repos/o/r/rules/branches/__push-probe.json"
# The default branch is read from the repository, so a token or an API that does
# not report it must not be read as "main, fine": not verified, like every other
# API-backed check here.
wall "a default branch the API does not report is not verified rather than passed" \
  "SKIP  default branch not verified" \
  "printf '{\"squash_merge_commit_title\":\"PR_TITLE\",\"squash_merge_commit_message\":\"PR_BODY\"}' > \"$api/repos/o/r.json\""
wall "a repository whose default branch is main is unchanged: no warning, no new noise" "-- 0 failed"
wall "a healthy repository still says which branch the wall was checked on" "the wall is checked on main, the repository's default branch"
wall "dropped required check is caught" "required checks dropped: \['ci / b'\]" "sed -i.bak 's/,{\"context\":\"ci \/ b\"}//' \"$api/repos/o/r/rules/branches/main.json\""
wall "widened merge methods are caught" "merge methods widened" "sed -i.bak 's/\[\"squash\"\]/[\"squash\",\"merge\"]/' \"$api/repos/o/r/rules/branches/main.json\""
wall "bypass actor is caught" "bypass actors present" "printf '{\"bypass_actors\":[{\"actor_id\":5,\"actor_type\":\"RepositoryRole\"}]}' > \"$api/repos/o/r/rulesets/1.json\""
wall "no rules at all is caught" "the wall is down" "printf '[]' > \"$api/repos/o/r/rules/branches/main.json\""
wall "invisible bypass actors are SKIP, not a pass" "bypass actors not visible" "printf '{}' > \"$api/repos/o/r/rulesets/1.json\""
# Labels have no fixture yet at this point, so that read is the one SKIP of an
# intact wall; the invisible bypass actors are the second.
wall "an intact wall against the fixture counts only the label read as not verified" "-- 0 failed, 1 not verified"
wall "invisible bypass actors are counted as not verified" "-- 0 failed, 2 not verified" "printf '{}' > \"$api/repos/o/r/rulesets/1.json\""
wall "an unreadable repository is counted, not passed" "-- 0 failed, 2 not verified" "printf '[]' > \"$api/repos/o/r.json\""
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
if grep -q -- "-- 0 failed, 0 not verified" <<<"$out" && ! grep -q '^  SKIP ' <<<"$out"; then ok "a run whose every read was answered counts 0 not verified, and says so"
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

# --project separate from --root, expectations from --ruleset
sub="$work/sub"; rm -rf "$sub"; cp -R "$good" "$sub"; mkdir -p "$sub/app"; mv "$sub/pyproject.toml" "$sub/uv.lock" "$sub/.copier-answers.yml" "$sub/Dockerfile" "$sub/.dockerignore" "$sub/.env.example" "$sub/app/"; mv "$sub/src" "$sub/app/src"
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$sub" --project app --no-network --repo o/r --ruleset "$root/ruleset.json" 2>&1)"
if grep -q "required checks dropped" <<<"$out" && grep -q "uv.lock committed" <<<"$out"; then ok "--project and --ruleset are honoured (ruleset's nine checks expected, project files found under app/)"
else bad "--project/--ruleset path"; printf '%s\n' "$out" | grep -E 'FAIL|INFO' | sed 's/^/        /'; fi

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
  "copier update --vcs-ref $target_ref --data plinth_sha=$sha40"
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
if grep -q "the changed files could not be read" <<<"$out" && grep -q "copier update --vcs-ref $target_ref --data plinth_sha=$sha40" <<<"$out"; then
  ok "a compare call that 404s still prints the update command, and names the file list as unread"
else bad "a 404 on the compare call"; printf '%s\n' "$out" | grep -E 'template|copier update' | sed 's/^/        /'; fi

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

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
