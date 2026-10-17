#!/usr/bin/env bash
# The merge ruleset (ruleset-merge.json, #568): `scripts/check-ruleset.sh`
# refuses every other shape of it and a bypass actor on the first ruleset,
# and `scripts/create-merge-ruleset.sh` writes it once and reads it back. No
# network: `gh` is mocked.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

cd "$root" || exit 1
if ./scripts/check-ruleset.sh >"$work/out" 2>&1 && grep -q "merge ruleset invariants: ruleset-merge.json" "$work/out"
then ok "check-ruleset.sh without arguments checks both rulesets, and both pass"
else bad "check-ruleset.sh without arguments did not pass both rulesets"; sed 's/^/        /' "$work/out"; fi

# Every other shape of B fails. Each is the file with one edit.
refuse() { # <description> <jq edit>
  jq "$2" ruleset-merge.json > "$work/b.json"
  if ./scripts/check-ruleset.sh --merge "$work/b.json" >"$work/out" 2>&1; then bad "B $1 passed"
  else ok "B $1 fails"; fi
}
refuse "with a second rule"                  '.rules += [{"type":"deletion"}]'
refuse "with another rule in place of update" '.rules = [{"type":"non_fast_forward"}]'
refuse "with no rule"                        '.rules = []'
refuse "with update carrying a parameter"    '.rules = [{"type":"update","parameters":{"update_allows_fetch_and_merge":true}}]'
refuse "with no bypass actor"                '.bypass_actors = []'
refuse "bypassed always, not through a pull request" '.bypass_actors[0].bypass_mode = "always"'
refuse "bypassed by the write role"          '.bypass_actors[0].actor_id = 4'
refuse "bypassed by an app"                  '.bypass_actors[0].actor_type = "Integration"'
refuse "with a second bypass actor"          '.bypass_actors += [{"actor_id":1,"actor_type":"Integration","bypass_mode":"pull_request"}]'
refuse "in evaluate mode"                    '.enforcement = "evaluate"'
refuse "on tags"                             '.target = "tag"'
refuse "on every branch"                     '.conditions.ref_name.include = ["~ALL"]'
refuse "with an excluded branch"             '.conditions.ref_name.exclude = ["refs/heads/main"]'
printf 'not json' > "$work/b.json"
if ./scripts/check-ruleset.sh --merge "$work/b.json" >/dev/null 2>&1; then bad "B that is not JSON passed"; else ok "B that is not JSON fails"; fi

# The first ruleset still has no bypass actor, whatever B has.
jq '.bypass_actors = [{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"pull_request"}]' ruleset.json > "$work/a.json"
if ./scripts/check-ruleset.sh "$work/a.json" >/dev/null 2>&1; then bad "the first ruleset with B's bypass actor passed"
else ok "the first ruleset with a bypass actor fails"; fi

# create-merge-ruleset.sh against a mock gh.
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -u
echo "$*" >> "$CALLS"
case "$*" in
  *"-X POST"*)        [ "${REFUSE:-0}" = 1 ] && { echo "HTTP 403" >&2; exit 1; }; echo 9 ;;
  *"/rulesets/9"*)    if [ -n "${READBACK:-}" ]; then echo "$READBACK"; else
                        jq '. + {id: 9, created_at: "x", rules: [{type: "update", parameters: {update_allows_fetch_and_merge: false}}],
                                 bypass_actors: [.bypass_actors[] | . + {extra: 1}]}' "$FILE"; fi ;;
  *"/rulesets --jq"*) [ "${ALREADY:-0}" = 1 ] && echo 7; true ;;
esac
exit 0
MOCK
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH" CALLS="$work/calls" FILE="$root/ruleset-merge.json"
run() { : > "$CALLS"; "$root/scripts/create-merge-ruleset.sh" "$@" >"$work/out" 2>&1; }

if run o/r && grep -q "applied (ruleset 9)" "$work/out" && grep -q -- "-X POST" "$CALLS"
then ok "creates the ruleset and reads it back (server fields and parameters aside)"
else bad "a clean create did not apply"; sed 's/^/        /' "$work/out"; fi
if grep -q -- "--input $root/scripts/../ruleset-merge.json" "$CALLS"
then ok "posts ruleset-merge.json itself, the door's file"
else bad "posted something other than ruleset-merge.json"; sed 's/^/        /' "$CALLS"; fi
if ALREADY=1 run o/r && grep -q "already exists; skipped" "$work/out" && ! grep -q -- "-X POST" "$CALLS"
then ok "an existing ruleset of that name is left alone, never a second one"
else bad "created a second ruleset of that name"; fi
if READBACK='{"name":"main: merged by an admin","target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"rules":[{"type":"update"}],"bypass_actors":[]}' run o/r
then bad "a read-back without the bypass actor passed"
elif grep -q "not applied as written" "$work/out"; then ok "a read-back that differs fails and says so"
else bad "failed without saying why"; sed 's/^/        /' "$work/out"; fi
if REFUSE=1 run o/r; then bad "a refused write passed"
elif grep -q "GitHub refused the ruleset" "$work/out"; then ok "a refused write fails and says so"
else bad "a refused write failed without saying why"; fi
if run --dry-run o/r && grep -q "nothing written" "$work/out" && ! grep -q -- "-X POST" "$CALLS"
then ok "--dry-run writes nothing"
else bad "--dry-run wrote"; fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
