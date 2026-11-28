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
work="$(mktemp -d)" || { echo "add-ruleset-rule: could not make a temp folder" >&2; exit 1; }; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

cat > "$work/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -u
# The tag ruleset (7) comes first, then the merge ruleset (2, a branch ruleset
# too, carrying `update` alone), then the first ruleset (1). `.[0]` lands on 7,
# the first branch ruleset on 2; a renamed merge ruleset must not matter.
# TWO_WALLS=1: the merge ruleset carries pull_request as well, and nothing may
# be picked. A PUT's body goes to $PUT_LOG, after the path it was sent to.
# FULL=1: ruleset 1's pull_request rule carries ruleset.json's parameters.
case "$*" in *" -X PUT "*) { echo "PUT $2"; cat; echo; } >> "${PUT_LOG:-/dev/null}"; exit 0 ;; esac
case "$*" in
  *"/rulesets/1"*) out="$RULESET1"
                   [ "${FULL:-0}" = 0 ] || out="$(jq -c --slurpfile f "$ROOT/ruleset.json" \
                     '.rules |= map(if .type == "pull_request" then .parameters = ($f[0].rules[] | select(.type == "pull_request") | .parameters) else . end)' <<<"$out")" ;;
  *"/rulesets/2"*) out='{"id":2,"name":"renamed by hand","target":"branch","enforcement":"active","bypass_actors":[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"exempt"}],"conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"rules":[{"type":"update"}]}'
                   [ "${TWO_WALLS:-0}" = 0 ] || out="$(jq -c '.rules += [{"type":"pull_request"}]' <<<"$out")" ;;
  *"/rulesets"*)   out='[{"id":7,"name":"tags","target":"tag"},{"id":2,"name":"renamed by hand","target":"branch"},{"id":1,"name":"r","target":"branch"}]' ;;
  *) exit 0 ;;
esac
case "$*" in *" --jq "*) jq -r "${@: -1}" <<<"$out" ;; *) echo "$out" ;; esac
exit 0
MOCK
chmod +x "$work/bin/gh"; export PATH="$work/bin:$PATH" ROOT="$root"
export RULESET1='{"id":1,"created_at":"x","_links":{},"name":"r","target":"branch","enforcement":"active","bypass_actors":[],"conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"rules":[{"type":"deletion"},{"type":"pull_request","parameters":{"required_approving_review_count":0}}]}'

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

# 5 the people presets (#1150): two-people sets the pull_request rule's three
# fields and nothing else; one-person puts them back; the merge ruleset (2) is
# never written. Run for real against the mock, so the PUT body is what is read.
three='.rules[] | select(.type == "pull_request") | .parameters | [.required_approving_review_count, .require_code_owner_review, .required_review_thread_resolution]'
rest='del(.rules[] | select(.type == "pull_request") | .parameters | (.required_approving_review_count, .require_code_owner_review, .required_review_thread_resolution))'
full="$(FULL=1 gh api repos/r/r/rulesets/1 | jq -c '{name, target, enforcement, bypass_actors, conditions, rules}')"
: > "$work/put"
rc=$(FULL=1 PUT_LOG="$work/put" run r/r two-people)
body="$(sed 1d "$work/put")"
if [ "$rc" = 0 ] && [ "$(grep -c '^PUT ' "$work/put")" = 1 ] && grep -qx 'PUT repos/r/r/rulesets/1' "$work/put"
then ok "two-people writes ruleset 1 once, and not the merge ruleset"; else bad "two-people wrote: $(grep '^PUT' "$work/put" | tr '\n' ' ') (exit $rc)"; fi
if [ "$(jq -c "$three" <<<"$body")" = "[1,true,true]" ]; then ok "two-people: one approval, code owners' review, conversation resolution"
else bad "two-people set $(jq -c "$three" <<<"$body" 2>&1)"; fi
if [ -n "$body" ] && [ "$(jq -cS "$rest" <<<"$body")" = "$(jq -cS "$rest" <<<"$full")" ]
then ok "two-people leaves every other field as it was, the unattributed-changes approval included"
else bad "another field changed: $(diff <(jq -S "$rest" <<<"$full") <(jq -S "$rest" <<<"$body" 2>&1) | head -5 | tr '\n' ' ')"; fi
if [ "$(jq -c '.rules[] | select(.type == "pull_request") | .parameters.require_extra_approval_for_unattributed_changes' <<<"$body")" = true ]
then ok "two-people keeps require_extra_approval_for_unattributed_changes on"; else bad "the unattributed-changes approval moved"; fi
# one-person, from the two-people result: the three are back to ruleset.json's.
: > "$work/put"
rc=$(PUT_LOG="$work/put" RULESET1="$body" run r/r one-person)
back="$(sed 1d "$work/put")"
if [ "$rc" = 0 ] && [ -n "$back" ] && [ "$(jq -cS . <<<"$back")" = "$(jq -cS . <<<"$full")" ]
then ok "one-person puts the three back: the ruleset is the one before two-people"; else bad "one-person left: $(jq -c "$three" <<<"$back" 2>&1) (exit $rc)"; fi
rc=$(FULL=1 run --dry-run r/r two-people)
if grep -q '^   before: required_approving_review_count=0 require_code_owner_review=false required_review_thread_resolution=false$' "$work/out" \
   && grep -q '^   after:  required_approving_review_count=1 require_code_owner_review=true required_review_thread_resolution=true$' "$work/out" \
   && grep -q 'nothing written' "$work/out"
then ok "--dry-run prints the three fields before and after, and writes nothing"; else bad "--dry-run said: $(tr '\n' ' ' < "$work/out")"; fi
rc=$(run --dry-run r/r two-people one-person)
if [ "$rc" != 0 ] && grep -q "name one" "$work/out"; then ok "two-people and one-person together are refused"; else bad "both presets passed (exit $rc)"; fi
rc=$(FULL=1 run --dry-run r/r two-people linear-history)
if [ "$rc" = 0 ] && grep -q "required_linear_history" "$work/out" && grep -q "after:  required_approving_review_count=1" "$work/out"
then ok "a people preset and a rule preset go together"; else bad "a people preset with a rule preset: exit $rc"; fi

# 4 what is hard to undo asks first; without a terminal it must not proceed.
rc=$("$root/scripts/add-ruleset-rule.sh" --dry-run r/r signed-commits </dev/null >"$work/out" 2>&1; echo $?)
if [ "$rc" != 0 ] || grep -q "agents can no longer push anything" "$work/out"
then ok "signed-commits warns and asks for confirmation"
else bad "something hard to undo went through silently"; fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
