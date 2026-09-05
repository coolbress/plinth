#!/usr/bin/env bash
# `scripts/create-tag-ruleset.sh`. No network: `gh` is mocked.
#
# Four properties:
#   1 creation is not blocked; blocking it blocks releases. Only deletion and
#     moving (non-fast-forward) are.
#   2 zero bypass actors, the same discipline as the branch ruleset.
#   3 never created twice: two rulesets on one target and nobody knows which
#     one holds.
#   4 written, then read back: a 200 is not proof that it took (measured).
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

cat > "$work/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -u
case "$*" in
  *"-X POST"*)  cat >/dev/null; exit 0 ;;
  *"length"*)   echo "${AFTER_COUNT:-1}" ;;              # how many after the write
  *".id"*)      [ "${ALREADY:-0}" = 1 ] && echo 7 || true ;;  # one exists already?
esac
exit 0
MOCK
chmod +x "$work/bin/gh"; export PATH="$work/bin:$PATH"

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

# The body, extracted from the script itself and run.
BODY="$(sed -n '/^body() {/,/^}/p' "$root/scripts/create-tag-ruleset.sh" | sed '1d;$d' | bash)"
if echo "$BODY" | jq -e '.target == "tag"' >/dev/null; then ok "targets tags"; else bad "target is not tag"; fi
if echo "$BODY" | jq -e '(.bypass_actors | length) == 0' >/dev/null; then ok "zero bypass actors"; else bad "bypass actors present; the branch ruleset has none"; fi
if echo "$BODY" | jq -e '[.rules[].type] | sort == ["deletion","non_fast_forward"]' >/dev/null; then ok "blocks deletion and moving only"; else bad "rules differ"; fi
if echo "$BODY" | jq -e '[.rules[].type] | index("creation") == null' >/dev/null; then ok "creation is not blocked (blocking it blocks releases)"; else bad "creation is blocked"; fi
if echo "$BODY" | jq -e '.enforcement == "active"' >/dev/null; then ok "enforcement is active"; else bad "enforcement is not active"; fi

# Never twice.
ALREADY=1 "$root/scripts/create-tag-ruleset.sh" r/r >"$work/out" 2>&1
if grep -q "already exists" "$work/out"; then ok "an existing tag ruleset is left alone"; else bad "created twice"; fi

# Written, then read back.
if AFTER_COUNT=0 "$root/scripts/create-tag-ruleset.sh" r/r >"$work/out" 2>&1
then bad "a silent no-op passed"
elif grep -q "not applied" "$work/out"; then ok "a write that did not take fails and says so"
else bad "failed without saying why"; fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
