#!/usr/bin/env bash
# `scripts/set-security-setting.sh`. No network: `gh` is mocked.
#
# One property: written, then read back and compared.
# Measured 2026-08-30: a PATCH without verification got a 200 and changed
# nothing. `-f "a[b][c]=v"` sends a form field; this endpoint takes nested JSON
# and the server ignores unknown fields in silence. A 200 is not proof.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

# Mock: a server that accepts the PATCH and keeps its state, exactly what happened.
cat > "$work/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -u
case "$*" in
  # stdin must be drained: an unread pipe kills the upstream `jq` with SIGPIPE
  # and `pipefail` ends the script before its message (measured, flaky).
  # The real `gh` reads `--input -`.
  *"-X PATCH"*) cat >/dev/null; exit 0 ;;   # 200, and nothing changes
  *) echo "${MOCK_STATUS:-disabled}" ;;    # reading it back still says disabled
esac
MOCK
chmod +x "$work/bin/gh"; export PATH="$work/bin:$PATH"

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

"$root/scripts/set-security-setting.sh" non-provider-patterns r/r >"$work/out" 2>&1
rc=$?
if [ "$rc" != 0 ]; then ok "a 200 that changed nothing fails"; else bad "a silent no-op passed as success"; fi
if grep -q "did not take effect" "$work/out"; then ok "it says what did not take effect"; else bad "no reason given"; fi

MOCK_STATUS=enabled "$root/scripts/set-security-setting.sh" non-provider-patterns r/r >"$work/out" 2>&1
rc=$?
if [ "$rc" = 0 ]; then ok "a setting that took passes"; else bad "it took, and the tool failed"; fi

if ! "$root/scripts/set-security-setting.sh" unknown-setting r/r >/dev/null 2>&1
then ok "an unknown setting is refused"; else bad "an unknown setting passed"; fi

if ! "$root/scripts/set-security-setting.sh" non-provider-patterns >/dev/null 2>&1
then ok "no repository is refused"; else bad "an empty call passed"; fi

# The form-field shape must not come back; it caused the incident. Comments are
# excluded: the script quotes that syntax as the thing not to do.
if grep -v '^\s*#' "$root/scripts/set-security-setting.sh" | grep -q 'security_and_analysis\['
then bad "form-field bracket syntax is back; the server ignores it in silence"
else ok "sends nested JSON (no form-field syntax)"; fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
