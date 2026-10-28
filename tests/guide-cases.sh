#!/usr/bin/env bash
# /plinth:guide (#710), offline. scripts/guide-state.sh is run on fixture
# checkouts with a mock `gh` that applies the script's own --jq filter to
# JSON in GitHub's shape, as gh does; each case asserts the row it lands on
# and the command it prints. Then tests/lib/guide-names.sh: the skill names
# no slash command outside the arsenal's table, and a text that does, or
# that names a tool #711 left out, fails (the must-not-pass cases first).
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/guide-state.sh"
names="$root/tests/lib/guide-names.sh"
arsenal="$root/skills/arsenal/SKILL.md"
work="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'MOCK'
#!/usr/bin/env bash
# MOCK_DIR holds open.json, merged.json and issues.json; MOCK_GH_FAIL makes
# every call fail as an unauthenticated gh does.
set -u
[ -n "${MOCK_GH_FAIL:-}" ] && { echo "To get started with GitHub CLI, please run:  gh auth login" >&2; exit 4; }
jqf="."; prev=""
for a in "$@"; do [ "$prev" = --jq ] && jqf="$a"; prev="$a"; done
[ -n "${MOCK_FAIL_ON:-}" ] && [ "$1 $2 ${4:-}" = "$MOCK_FAIL_ON" ] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
case "$1 $2 ${4:-}" in
  "repo view"*)        echo o/r; exit 0 ;;
  "pr list open")      f=open.json ;;
  "pr list merged")    f=merged.json ;;
  "issue list open")   f=issues.json ;;
  *) echo "mock gh: unexpected $*" >&2; exit 1 ;;
esac
jq -r "$jqf" "$MOCK_DIR/$f"
MOCK
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"

# repo <name> [answers]: a git checkout, with .copier-answers.yml unless "none".
repo() {
  local d="$work/$1"; mkdir -p "$d"; git -C "$d" init -q
  [ "${2:-}" = none ] || printf '_commit: v1.28.0\n_src_path: %s\n%s\n' "${SRC:-gh:coolbress/plinth-template}" "${2:-archetype: cli}" > "$d/.copier-answers.yml"
  printf '[]' > "$d/open.json"; printf '[]' > "$d/merged.json"; printf '[]' > "$d/issues.json"
  echo "$d"
}
pr() { # <number> <title> <bot:true|false> <check conclusion or "-" for none, "run" for in progress>
  local checks='[]'
  case "$4" in
    -) ;; run) checks='[{"status":"IN_PROGRESS","conclusion":""}]' ;;
    *) checks="[{\"status\":\"COMPLETED\",\"conclusion\":\"$4\"},{\"state\":\"SUCCESS\"}]" ;;
  esac
  printf '{"number":%s,"title":"%s","isDraft":false,"author":{"login":"%s","is_bot":%s},"headRefOid":"%040d","statusCheckRollup":%s,"mergedAt":"2026-10-2%sT00:00:00Z"}' \
    "$1" "$2" "$([ "$3" = true ] && echo app/dependabot || echo someone)" "$3" "$1" "$checks" "$(( $1 % 10 ))"
}
put() { local f="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$f"; }
issue() { local l=""; [ -z "$3" ] || l="{\"name\":\"$3\"}"; printf '{"number":%s,"title":"%s","labels":[%s]}' "$1" "$2" "$l"; }

# expect <case> <dir> <where starts with> <command line> [<other expected line>]
expect() {
  local out; out="$(MOCK_DIR="$2" "$script" "$2" 2>&1)"; local rc=$?
  if [ "$rc" -eq 0 ] && grep -qF "where: $3" <<<"$out" && grep -qxF "command: $4" <<<"$out" &&
     { [ -z "${5:-}" ] || grep -qF -- "$5" <<<"$out"; } && grep -qx 'table:' <<<"$out"; then
    ok "$1"
  else
    bad "$1 (wanted where: $3 / command: $4${5:+ / $5}; exit $rc)"; sed 's/^/        /' <<<"$out" | head -14
  fi
}

d="$work/plain"; mkdir -p "$d"
expect "no git checkout: create one" "$d" "No repository yet (step 1)" "/plinth:new-project <owner>/<name>"

d="$(repo other none)"
expect "a checkout plinth did not make: floor-check" "$d" "A repository plinth did not make" "/plinth:floor-check"

d="$(SRC=gh:someone/other-template repo foreign)"
expect "another Copier template's answers file: not made by plinth" "$d" "A repository plinth did not make" "/plinth:floor-check" "not gh:coolbress/plinth-template"
d="$(SRC=/home/x/coolbress/plinth-template repo local-src)"
expect "a local copy of the template is not the door's form either" "$d" "A repository plinth did not make" "/plinth:floor-check"

d="$(repo created)"
put "$d/open.json" "$(pr 1 'chore(deps): bump actions/checkout' true SUCCESS)" "$(pr 2 'docs: first pull request through the wall' false run)"
expect "just created, Dependabot's pull request first: the door's is the one to merge" "$d" \
  "Repository made, its first pull request open (step 1)" \
  "body=\"\$(gh pr view 2 --json body --jq .body)\" && gh pr merge 2 --squash --match-head-commit $(printf '%040d' 2) --body \"\$body\"" \
  "checks pending"

d="$(repo first-merged)"
put "$d/merged.json" "$(pr 2 'docs: first pull request through the wall' false SUCCESS)"
put "$d/open.json" "$(pr 3 'chore(deps): bump x' true SUCCESS)"
expect "first pull request merged, no issue: the token, the account, four things; then step 2" "$d" \
  "First pull request merged (step 1)" "none: three pages to follow, in order (the tool cell)" "then: An idea in your own words (step 2)"

d="$(repo issue-open "archetype: web
hosting: render")"
put "$d/merged.json" "$(pr 2 'docs: first pull request through the wall' false SUCCESS)"
put "$d/issues.json" "$(issue 4 'Ask the user for their name' '')" "$(issue 5 'Show monthly totals' ready-for-agent)"
expect "an issue open: the ready-for-agent one, not the lowest number" "$d" "A ticket ready (step 4)" "/implement #5" "before: /clear"
grep -q "hosting: render" <<<"$(MOCK_DIR="$d" "$script" "$d")" && ok "a web project says where it runs" || bad "web: no hosting line"

d="$(repo pr-open)"
put "$d/merged.json" "$(pr 2 'docs: first pull request through the wall' false SUCCESS)"
put "$d/open.json" "$(pr 6 'feat: monthly totals' false run)"
put "$d/issues.json" "$(issue 5 'Show monthly totals' ready-for-agent)"
expect "a pull request open comes before the issue it closes" "$d" "A pull request with checks running (step 5)" "/run" "note: pull request #6, checks pending"
put "$d/open.json" "$(pr 6 'feat: monthly totals' false FAILURE)"
expect "a pull request with a failing check: something broke, not wait" "$d" "Something broke (step 7)" \
  "diagnose this: pull request #6 has a failing check" "#6 ready, checks fail"

d="$(repo triage)"
put "$d/merged.json" "$(pr 2 'docs: first' false SUCCESS)" "$(pr 7 'feat: x' false SUCCESS)"
put "$d/issues.json" "$(issue 8 'It crashes on an empty file' needs-triage)"
expect "only an issue someone else opened: triage" "$d" "Something broke (step 7)" "/triage" "note: issue #8"

d="$(repo unlabelled)"
put "$d/merged.json" "$(pr 2 'docs: first' false SUCCESS)"
put "$d/issues.json" "$(issue 9 'Export to CSV' '')"
expect "an unlabelled issue: build it" "$d" "A ticket ready (step 4)" "/implement #9"

d="$(repo bots-only)"
put "$d/merged.json" "$(pr 2 'docs: first' false SUCCESS)" "$(pr 7 'feat: x' false SUCCESS)"
put "$d/open.json" "$(pr 10 'chore(deps): bump y' true SUCCESS)"
expect "only Dependabot open, past the first merge: step 9" "$d" "Between pieces of work (step 9)" \
  "/plinth:floor-check (then the Dependabot pull requests, one at a time, on green)"

d="$(repo idle)"
put "$d/merged.json" "$(pr 2 'docs: first' false SUCCESS)" "$(pr 7 'feat: x' false SUCCESS)"
expect "nothing open, past the first merge: shape the next idea" "$d" "An idea in your own words (step 2)" "/grilling" \
  "last merge: #7"

d="$(repo no-login)"
out="$(MOCK_GH_FAIL=1 MOCK_DIR="$d" "$script" "$d" 2>&1)"
if grep -qx 'where: not read' <<<"$out" && grep -q 'gh auth login' <<<"$out" && ! grep -q '^command:' <<<"$out"; then
  ok "gh not logged in: not read, with gh's own line, and no step"
else bad "gh not logged in"; sed 's/^/        /' <<<"$out"; fi

# One read failing after the repository answered: its own error, named.
d="$(repo one-read-fails)"
out="$(MOCK_FAIL_ON="pr list merged" MOCK_DIR="$d" "$script" "$d" 2>&1)"
if grep -qx 'where: not read' <<<"$out" && grep -qF 'not read (merged pull requests: HTTP 502: Bad Gateway)' <<<"$out" &&
   ! grep -q 'unbound' <<<"$out"; then ok "one read failing: that read and gh's error, no step"
else bad "one read failing"; sed 's/^/        /' <<<"$out"; fi

d="$(repo gitlab "archetype: cli
host: gitlab")"
out="$(MOCK_DIR="$d" "$script" "$d" 2>&1)"
grep -qx 'where: not read' <<<"$out" && ! grep -q '^command:' <<<"$out" &&
  ok "a GitLab checkout: not read, no step" || bad "a GitLab checkout"

# A table that lost a row the guide looks for stops with exit 1, never guesses.
mkdir -p "$work/plugin/skills/arsenal" "$work/plugin/scripts"
cp "$script" "$root/scripts/new-project.sh" "$work/plugin/scripts/"
grep -v '^| An idea in your own words' "$arsenal" > "$work/plugin/skills/arsenal/SKILL.md"
d="$work/idle"
out="$(MOCK_DIR="$d" "$work/plugin/scripts/guide-state.sh" "$d" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && grep -q "no row starting 'An idea in your own words'" <<<"$out" &&
  ok "a row missing from the arsenal's table: exit 1, named" || bad "missing row: exit $rc: $out"

# ── names ────────────────────────────────────────────────────────────────
printf 'Next, type `/speckit.specify` to write the spec.\n' > "$work/n1"
printf 'Install superpowers for a better plan.\n' > "$work/n2"
printf '다음은 /compact 를 치세요.\n' > "$work/n3"
for n in n1 n2 n3; do
  "$names" "$arsenal" "$work/$n" >/dev/null && bad "names: $(cat "$work/$n") passed" || ok "names: fails on: $(cat "$work/$n")"
done
printf '다음 명령: `/clear`, 그다음 `/implement #5`. 파일은 docs/how-to/x.md, ${CLAUDE_PLUGIN_ROOT}/scripts/y.sh, `/home/runner/plinth/docs/a.md`.\n' > "$work/y1"
"$names" "$arsenal" "$work/y1" >/dev/null && ok "names: table commands and paths pass" || bad "names: a text using only table commands failed"
if out="$("$names" "$arsenal" "$root/skills/guide/SKILL.md")"; then
  ok "skills/guide/SKILL.md names only the table's commands"
else bad "skills/guide/SKILL.md:"; echo "$out"; fi
out="$("$script" "$work/plain" 2>&1)"
grep -q 'CLAUDE_PLUGIN_ROOT' <<<"$out" && bad "the printed table still carries \${CLAUDE_PLUGIN_ROOT}" ||
  ok "the printed table names the plugin's own path, not the variable"
printf '%s\n' "$out" > "$work/printed"
"$names" "$arsenal" "$work/printed" >/dev/null && ok "what the script prints names only the table's commands" || bad "the script's output names something outside the table"

echo "-- $pass passed, $fail failed"
[ "$fail" -eq 0 ]
