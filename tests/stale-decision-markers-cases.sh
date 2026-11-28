#!/usr/bin/env bash
# scripts/stale-decision-markers.sh on a fixture page, with gh stubbed (#1221):
# a marker whose issue is closed as completed fails (exit 1) and is named; an
# open one stands; one closed as not planned is named for a person and does
# not fail; an issue gh cannot read fails (exit 2); the page's own `#N`
# example is no marker; an issue named twice is read once.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/stale-decision-markers.sh"
tmp="$(mktemp -d)" || { echo "stale-decision-markers-cases: could not make a temp folder" >&2; exit 1; }; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/        /'; }

# gh issue view <n> --repo <repo> ...: the state of <repo>#<n> from $STATES
# (`<repo>#<n> <STATE>:<REASON>` lines); absent there, the read fails.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'MOCK'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$GH_LOG"
[ "$1 $2" = "issue view" ] || exit 1
n="$3"; repo=""; prev=""
for a in "$@"; do [ "$prev" = --repo ] && repo="$a"; prev="$a"; done
s="$(awk -v k="$repo#$n" '$1 == k { print $2; exit }' <<<"$STATES")"
[ -n "$s" ] || { echo "GraphQL: Could not resolve to an issue" >&2; exit 1; }
printf '%s\n' "$s"
MOCK
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" GH_LOG="$tmp/gh.log"

page="$tmp/decisions.md"
cat > "$page" <<'PAGE'
- **A decision not built yet** ends in `(decided; not built yet: #N)`, naming the open issue.
- A decision being built. 2026-11-24, #2 (decided; not built yet: #2)
- A decision whose issue closed completed. 2026-11-24, #1 (decided; not built yet: #1)
- One the template builds. 2026-11-25, #4 (decided; not built yet: coolbress/plinth-template#5)
- Two carriers, one done. 2026-11-25, #6 (decided; not built yet: #2, coolbress/plinth-template#7)
- A decision whose issue closed not planned. 2026-11-25, #3 (decided; not built yet: #3)
- A built decision, no marker. 2026-11-25, #8
PAGE
run() { out="$(STATES="$1" "$script" "$page" 2>&1)"; rc=$?; }

all_open="coolbress/plinth#1 OPEN:
coolbress/plinth#2 OPEN:
coolbress/plinth#3 OPEN:
coolbress/plinth-template#5 OPEN:
coolbress/plinth-template#7 OPEN:"
: > "$GH_LOG"; run "$all_open"
[ "$rc" = 0 ] && grep -q "6 marker reference(s), 5 issue(s) read: none closed as completed$" <<<"$out" \
  && ok "every marker's issue open: exit 0, and it says how many were read" || bad "all open (rc=$rc)" "$out"
[ "$(grep -c 'issue view 2 ' "$GH_LOG")" = 1 ] && ok "an issue two markers name is read once" || bad "#2 was read $(grep -c 'issue view 2 ' "$GH_LOG") times"
! grep -q 'issue view N ' "$GH_LOG" && ! grep -q 'issue view 8 ' "$GH_LOG" \
  && ok "the page's own #N example and a line with no marker are not read" || bad "read something that is no marker" "$(cat "$GH_LOG")"

stale="${all_open/coolbress\/plinth#1 OPEN:/coolbress/plinth#1 CLOSED:COMPLETED}"
stale="${stale/coolbress\/plinth-template#7 OPEN:/coolbress/plinth-template#7 CLOSED:COMPLETED}"
run "$stale"
[ "$rc" = 1 ] && ok "a marker whose issue is closed as completed fails: exit 1" || bad "stale marker (rc=$rc)" "$out"
grep -q '^stale: line 3: #1 is closed as completed' <<<"$out" && ok "  named with its line and reference" || bad "the stale #1 is not named" "$out"
grep -q '^stale: line 5: coolbress/plinth-template#7 is closed as completed' <<<"$out" \
  && ok "  and a template reference, one of two in a marker" || bad "the stale template#7 is not named" "$out"
! grep -q 'line 2: #2\|line 4:' <<<"$out" && ok "  the open ones are not named" || bad "an open marker was named" "$out"

planned="${all_open/coolbress\/plinth#3 OPEN:/coolbress/plinth#3 CLOSED:NOT_PLANNED}"
run "$planned"
[ "$rc" = 0 ] && grep -q '^for a person: line 6: #3 is closed (NOT_PLANNED), not completed' <<<"$out" \
  && grep -q ', 1 for a person (above)$' <<<"$out" \
  && ok "closed as not planned: named for a person, not a failure (exit 0)" || bad "not planned (rc=$rc)" "$out"

unread="$(grep -v 'plinth-template#5' <<<"$all_open")"
run "$unread"
[ "$rc" = 2 ] && grep -q '^not read: line 4: coolbress/plinth-template#5' <<<"$out" \
  && ok "an issue gh cannot read fails (exit 2), named: not passed" || bad "unread (rc=$rc)" "$out"

cp "$page" "$tmp/odd.md"
printf -- '- Written another way. 2026-11-26, #9 (decided; not built yet: #1 and #2)\n- Wrapped. 2026-11-26, #10 (decided; not built yet\n' >> "$tmp/odd.md"
out="$(STATES="$all_open" "$script" "$tmp/odd.md" 2>&1)"; rc=$?
[ "$rc" = 2 ] && grep -q "^not read: line 8: .*#1 and #2" <<<"$out" && grep -q "^not read: line 9: .*not followed by" <<<"$out" \
  && ok "a marker written another way, or wrapped, is not read and fails (exit 2), named" || bad "odd markers (rc=$rc)" "$out"

out="$("$script" "$tmp/none.md" 2>&1)"; rc=$?
[ "$rc" = 2 ] && ok "no page: exit 2, not a pass" || bad "no page (rc=$rc)" "$out"

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
