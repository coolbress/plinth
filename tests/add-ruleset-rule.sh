#!/usr/bin/env bash
# `scripts/add-ruleset-rule.sh`. No network: `gh` is mocked.
#
# Two properties:
#   1 it only adds: existing rules, `bypass_actors` and `enforcement` survive.
#     Pasting JSON by hand drops other fields and the wall gets weaker in
#     silence; that is the whole reason the tool exists.
#   2 unknown presets are refused: free-form JSON would void property 1.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

cat > "$work/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -u
# The tag ruleset (7) comes first, then the merge ruleset (2, a branch ruleset
# too, carrying `update` alone), then the first ruleset (1). `.[0]` lands on 7,
# the first branch ruleset on 2; a renamed merge ruleset must not matter.
# TWO_WALLS=1: the merge ruleset carries pull_request as well, and nothing may
# be picked.
case "$*" in
  *"/rulesets/1"*) out='{"id":1,"created_at":"x","_links":{},"name":"r","target":"branch","enforcement":"active","bypass_actors":[],"conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"rules":[{"type":"deletion"},{"type":"pull_request","parameters":{"required_approving_review_count":0}}]}' ;;
  *"/rulesets/2"*) out='{"id":2,"name":"renamed by hand","target":"branch","enforcement":"active","bypass_actors":[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"exempt"}],"conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"rules":[{"type":"update"}]}'
                   [ "${TWO_WALLS:-0}" = 0 ] || out="$(jq -c '.rules += [{"type":"pull_request"}]' <<<"$out")" ;;
  *"/rulesets"*)   out='[{"id":7,"name":"tags","target":"tag"},{"id":2,"name":"renamed by hand","target":"branch"},{"id":1,"name":"r","target":"branch"}]' ;;
  *) exit 0 ;;
esac
case "$*" in *" --jq "*) jq -r "${@: -1}" <<<"$out" ;; *) echo "$out" ;; esac
exit 0
MOCK
chmod +x "$work/bin/gh"; export PATH="$work/bin:$PATH"

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
run() { "$root/scripts/add-ruleset-rule.sh" "$@" >"$work/out" 2>&1; echo $?; }

rc=$(run --dry-run r/r linear-history)
if [ "$rc" = 0 ]; then ok "a known preset passes"; else bad "exit $rc"; fi
if grep -q "required_linear_history" "$work/out"; then ok "the rule is added"; else bad "the rule was not added"; fi
if grep -q "deletion" "$work/out"; then ok "existing rules survive"; else bad "an existing rule disappeared"; fi
if grep -q "pull_request" "$work/out"; then ok "existing rules survive (second)"; else bad "an existing rule disappeared"; fi
if grep -q "bypass actors: 0, enforcement: active" "$work/out"; then ok "bypass actors and enforcement are untouched"; else bad "the wall got weaker"; fi
if grep -q "^-- r/r (ruleset 1)$" "$work/out"; then ok "the first ruleset is edited, not the tag or the merge ruleset"; else bad "another ruleset was picked: $(head -1 "$work/out")"; fi
rc=$(TWO_WALLS=1 run --dry-run r/r linear-history)
if [ "$rc" != 0 ] && grep -q "no single branch ruleset" "$work/out"; then ok "two branch rulesets carrying pull_request: nothing is picked"
else bad "picked one of two candidates (exit $rc)"; fi

rc=$(run --dry-run r/r no-such-preset)
if [ "$rc" != 0 ]; then ok "an unknown preset is refused"; else bad "an unknown preset passed"; fi

rc=$(run --dry-run r/r)
if [ "$rc" != 0 ]; then ok "no preset is refused"; else bad "an empty call passed"; fi

# 3 the same kind twice is still one rule; the server rejects duplicates.
rc=$(run --dry-run r/r linear-history linear-history)
n=$(grep -o "required_linear_history" "$work/out" | wc -l | tr -d ' ')
if [ "$n" = 1 ]; then ok "duplicates fold into one"; else bad "$n duplicates left"; fi

# 4 what is hard to undo asks first; without a terminal it must not proceed.
rc=$("$root/scripts/add-ruleset-rule.sh" --dry-run r/r signed-commits </dev/null >"$work/out" 2>&1; echo $?)
if [ "$rc" != 0 ] || grep -q "agents can no longer push anything" "$work/out"
then ok "signed-commits warns and asks for confirmation"
else bad "something hard to undo went through silently"; fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
