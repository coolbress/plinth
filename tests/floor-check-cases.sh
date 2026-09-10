#!/usr/bin/env bash
# The floor checker's verdicts on fixtures, offline: a complete backend
# instance passes, and each planted defect is named. A checker that cannot
# fail is not a check.
# shellcheck disable=SC2034  # the rules_* fixtures are used inside wall() command strings
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root/scripts/floor-check.py"
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
{"permissions":{"deny":["Bash(git push --force:*)","Bash(rm -rf:*)","Bash(gh auth token*)","Read(./.env)","Read(~/.config/gh/**)"]}}
JSON
printf '[project]\nname = "app"\n' > "$good/pyproject.toml"; : > "$good/uv.lock"
printf 'archetype: backend\n' > "$good/.copier-answers.yml"
printf 'import os\nos.environ["APP_PORT"]\n' > "$good/src/app/__main__.py"
printf 'APP_PORT=8000\n' > "$good/.env.example"
printf 'FROM python:3.12-slim@sha256:%064d\nRUN uv sync --locked\nUSER app\nCMD ["python", "-m", "app"]\n' 0 > "$good/Dockerfile"
printf '.git\n.env\n.venv\n' > "$good/.dockerignore"

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
skips "no archetype: the skipped conditional items are counted" \
  "2 not verified" --root "$noarch" --no-network

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
plant "broken doc link is caught" "printf '[x](nope.md)\n' >> README.md" "do not exist"
plant "unlabelled issue form is caught" "printf 'name: t\ndescription: \"x\"\nbody: []\n' > .github/ISSUE_TEMPLATE/task.yml" "no labels"
plant "missing lockfile is caught" "rm uv.lock" "uv.lock missing"
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
good_rules='[{"type":"deletion","ruleset_source_type":"Repository","ruleset_id":1},{"type":"non_fast_forward","ruleset_source_type":"Repository","ruleset_id":1},{"type":"pull_request","parameters":{"allowed_merge_methods":["squash"]},"ruleset_source_type":"Repository","ruleset_id":1},{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"ci / a"},{"context":"ci / b"},{"context":"CodeQL"}]},"ruleset_source_type":"Repository","ruleset_id":1}]'
printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"
printf '{"bypass_actors":[]}' > "$api/repos/o/r/rulesets/1.json"
wall() { # <description> <expected substring in output> [shell that edits the fixture first]
  local out; [ -n "${3:-}" ] && eval "$3"
  out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --expect-checks "ci / a, ci / b" 2>&1)"
  # A summary naming N not verified must sit above exactly N SKIP lines.
  local n want; n="$(grep -c '^  SKIP ' <<<"$out")"; want="${2##*failed, }"; want="${want%% *}"
  if grep -q -- "$2" <<<"$out" && { [[ "$2" != "-- "*"not verified"* ]] || [ "$n" = "$want" ]; }; then ok "$1"
  else bad "$1 (expected '$2', SKIP lines=$n)"; printf '%s\n' "$out" | grep -E 'FAIL|SKIP|failed' | sed 's/^/        /'; fi
  printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"; printf '{"bypass_actors":[]}' > "$api/repos/o/r/rulesets/1.json"
  printf '{"default_branch":"main","squash_merge_commit_title":"PR_TITLE","squash_merge_commit_message":"PR_BODY"}' > "$api/repos/o/r.json"
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
# passes; neither is the wall missing a stone.
strip_name='map(if .type=="required_status_checks" then .parameters.required_status_checks |= map(select(.context!="CodeQL")) else . end)'
rule_for() { printf '{"type":"code_scanning","parameters":{"code_scanning_tools":[{"tool":"%s","alerts_threshold":"errors","security_alerts_threshold":"high_or_higher"}]},"ruleset_source_type":"Repository","ruleset_id":1}' "$1"; }
rules_rule_only="$(jq -c "$strip_name + [\$r]" --argjson r "$(rule_for CodeQL)" <<<"$good_rules")"
rules_neither="$(jq -c "$strip_name" <<<"$good_rules")"
rules_other_tool="$(jq -c "$strip_name + [\$r]" --argjson r "$(rule_for Semgrep)" <<<"$good_rules")"
wall "CodeQL as a rule, not a name, passes" "CodeQL enforced (rule)" "printf '%s' \"\$rules_rule_only\" > \"$api/repos/o/r/rules/branches/main.json\""
wall "CodeQL as a legacy check name passes" "CodeQL enforced (check name)"
wall "CodeQL neither rule nor name is caught" "CodeQL not enforced" "printf '%s' \"\$rules_neither\" > \"$api/repos/o/r/rules/branches/main.json\""
wall "a code_scanning rule for another tool is caught" "CodeQL not enforced" "printf '%s' \"\$rules_other_tool\" > \"$api/repos/o/r/rules/branches/main.json\""

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
out="$(PATH="$work/bin:$PATH" python3 "$checker" --root "$good" --repo o/r --expect-checks "ci / a, ci / b" 2>&1)"; rc=$?
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

# --sandbox reads this machine's Claude Code settings; off is WARN, never FAIL.
mkdir -p "$work/conf"; printf '{"sandbox":{"enabled":false}}' > "$work/conf/settings.json"
out="$(CLAUDE_CONFIG_DIR="$work/conf" python3 "$checker" --root "$good" --no-network --sandbox 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q "WARN.*sandbox off" <<<"$out"; then ok "--sandbox: off is a WARN and the floor still passes"; else bad "--sandbox off"; printf '%s\n' "$out" | grep -E 'sandbox|failed' | sed 's/^/        /'; fi
printf '{"sandbox":{"enabled":true}}' > "$work/conf/settings.local.json"
out="$(CLAUDE_CONFIG_DIR="$work/conf" python3 "$checker" --root "$good" --no-network --sandbox 2>&1)"
if grep -q "PASS.*sandbox on" <<<"$out"; then ok "--sandbox: settings.local.json can turn it on"; else bad "--sandbox on"; printf '%s\n' "$out" | grep sandbox | sed 's/^/        /'; fi

# --project separate from --root, expectations from --ruleset
sub="$work/sub"; rm -rf "$sub"; cp -R "$good" "$sub"; mkdir -p "$sub/app"; mv "$sub/pyproject.toml" "$sub/uv.lock" "$sub/.copier-answers.yml" "$sub/Dockerfile" "$sub/.dockerignore" "$sub/.env.example" "$sub/app/"; mv "$sub/src" "$sub/app/src"
out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$sub" --project app --no-network --repo o/r --ruleset "$root/ruleset.json" 2>&1)"
if grep -q "required checks dropped" <<<"$out" && grep -q "uv.lock committed" <<<"$out"; then ok "--project and --ruleset are honoured (ruleset's nine checks expected, project files found under app/)"
else bad "--project/--ruleset path"; printf '%s\n' "$out" | grep -E 'FAIL|INFO' | sed 's/^/        /'; fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
