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
plant "stub CONTRIBUTING is caught" "printf '# Contributing\nSee the wiki.\n' > CONTRIBUTING.md" "no build or test command"
plant "unpinned base image is caught" "sed -i.bak 's/@sha256:[0-9a-f]*//' Dockerfile" "not pinned by digest"
plant "root user is caught" "sed -i.bak 's/^USER app/USER root/' Dockerfile" "runs as root"
plant "undocumented env var is caught" "printf 'x\n' > .env.example" "missing variables"
plant "missing token deny is caught" "printf '{\"permissions\":{\"deny\":[]}}' > .claude/settings.json" "does not deny gh auth token"
plant "broken doc link is caught" "printf '[x](nope.md)\n' >> README.md" "do not exist"
plant "unlabelled issue form is caught" "printf 'name: t\ndescription: \"x\"\nbody: []\n' > .github/ISSUE_TEMPLATE/task.yml" "no labels"
plant "missing lockfile is caught" "rm uv.lock" "uv.lock missing"
plant "block-list labels are accepted" "printf 'name: t\ndescription: \"x\"\nlabels:\n  - task\nbody: []\n' > .github/ISSUE_TEMPLATE/task.yml" "__none__" || true
plant "multi-stage and --platform FROM are understood" "printf 'FROM --platform=linux/amd64 python:3.12-slim@sha256:%064d AS base\nFROM base\nRUN uv sync --locked\nUSER app\nCMD [\"python\", \"-m\", \"app\"]\n' 0 > Dockerfile" "__none__" || true

# The wall, against a fixture API laid out like api.github.com paths.
api="$work/api"; mkdir -p "$api/repos/o/r/rules/branches" "$api/repos/o/r/rulesets"
printf '{"default_branch":"main"}' > "$api/repos/o/r.json"
good_rules='[{"type":"deletion","ruleset_source_type":"Repository","ruleset_id":1},{"type":"non_fast_forward","ruleset_source_type":"Repository","ruleset_id":1},{"type":"pull_request","parameters":{"allowed_merge_methods":["squash"]},"ruleset_source_type":"Repository","ruleset_id":1},{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"ci / a"},{"context":"ci / b"},{"context":"CodeQL"}]},"ruleset_source_type":"Repository","ruleset_id":1}]'
printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"
printf '{"bypass_actors":[]}' > "$api/repos/o/r/rulesets/1.json"
wall() { # <description> <expected substring in output> [shell that edits the fixture first]
  local out; [ -n "${3:-}" ] && eval "$3"
  out="$(FLOOR_CHECK_API_DIR="$api" python3 "$checker" --root "$good" --no-network --repo o/r --expect-checks "ci / a, ci / b" 2>&1)"
  if grep -q -- "$2" <<<"$out"; then ok "$1"; else bad "$1 (expected '$2')"; printf '%s\n' "$out" | grep -E 'FAIL|INFO|failed' | sed 's/^/        /'; fi
  printf '%s' "$good_rules" > "$api/repos/o/r/rules/branches/main.json"; printf '{"bypass_actors":[]}' > "$api/repos/o/r/rulesets/1.json"
}
wall "intact wall passes" "-- 0 failed"
wall "dropped required check is caught" "required checks dropped: \['ci / b'\]" "sed -i.bak 's/,{\"context\":\"ci \/ b\"}//' \"$api/repos/o/r/rules/branches/main.json\""
wall "widened merge methods are caught" "merge methods widened" "sed -i.bak 's/\[\"squash\"\]/[\"squash\",\"merge\"]/' \"$api/repos/o/r/rules/branches/main.json\""
wall "bypass actor is caught" "bypass actors present" "printf '{\"bypass_actors\":[{\"actor_id\":5,\"actor_type\":\"RepositoryRole\"}]}' > \"$api/repos/o/r/rulesets/1.json\""
wall "no rules at all is caught" "the wall is down" "printf '[]' > \"$api/repos/o/r/rules/branches/main.json\""
wall "invisible bypass actors are INFO, not a pass" "bypass actors not visible" "printf '{}' > \"$api/repos/o/r/rulesets/1.json\""
# CodeQL: enforced by the code_scanning rule (the door since workflows#109) or by
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
f="$api/\$2.json"
[ -f "\$f" ] && cat "\$f" || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
MOCK
chmod +x "$work/bin/gh"
printf '{"bypass_actors":[{"actor_id":5,"actor_type":"RepositoryRole"}]}' > "$api/repos/o/r/rulesets/1.json"
out="$(PATH="$work/bin:$PATH" python3 "$checker" --root "$good" --repo o/r --expect-checks "ci / a, ci / b" 2>&1)"
if grep -q "FAIL.*bypass actors present" <<<"$out" && ! grep -q "not verified" <<<"$out"; then ok "the API is read through gh when it is installed (bypass actors seen, 404 is absent)"
else bad "gh path"; printf '%s\n' "$out" | grep -E 'FAIL|INFO' | sed 's/^/        /'; fi
printf '{"bypass_actors":[]}' > "$api/repos/o/r/rulesets/1.json"

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
