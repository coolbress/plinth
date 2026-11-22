#!/usr/bin/env bash
# scripts/heavy.sh (#989): plinth's copy of plinth-template's queue, so that
# plinth's own heavy commands share the machine's slots with projects made
# with plinth. These are the template's own cases for it, run with /bin/bash
# (bash 3.2 on macOS) and a TMPDIR of the test's own, so the queue is the
# test's alone. tests/template-render.sh holds the copy to the pinned
# template's.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
heavy="$root/scripts/heavy.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/heavy-cases.XXXXXX")"
pids=()
# Whatever is still running when the test ends, failed or not, is killed.
cleanup() {
  local p
  { for p in ${pids[@]+"${pids[@]}"}; do kill -9 "$p"; wait "$p"; done; } 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; [ -z "${2:-}" ] || sed 's/^/        | /' <<<"$2"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }
# appears <path>: waits up to 10 seconds for it.
appears() { local _; for _ in $(seq 1 200); do [ -e "$1" ] && return 0; sleep 0.05; done; return 1; }
# start <case> <command> [<setting>...]: heavy.sh sh -c <command> in the
# background, with the case's TMPDIR; its pid is in $started.
start() {
  mkdir -p "$tmp/$1/tmp"
  env TMPDIR="$tmp/$1/tmp" "${@:3}" /bin/bash "$heavy" sh -c "$2" >>"$tmp/$1/background.out" 2>&1 &
  started=$!; pids+=("$started")
}

[ -x "$heavy" ] || { bad "scripts/heavy.sh is not an executable file"; echo "  $pass passed, $fail failed"; exit 1; }
ok "scripts/heavy.sh is executable"

# ---- one slot: a second call waits until the first ends, and says so
c="wait"; mkdir -p "$tmp/$c"
start $c "touch $tmp/$c/started; sleep 2; echo first >> $tmp/$c/log" PLINTH_HEAVY_SLOTS=1
first=$started
appears "$tmp/$c/started"
TMPDIR="$tmp/$c/tmp" PLINTH_HEAVY_SLOTS=1 /bin/bash "$heavy" sh -c "echo second >> $tmp/$c/log" 2>"$tmp/$c/err"
rc=$?
wait "$first"
check "with one slot, a second call waits until the first ends, then runs" \
  '[ "$rc" = 0 ] && [ "$(tr "\n" " " <"$tmp/$c/log")" = "first second " ]' "rc=$rc; log: $(cat "$tmp/$c/log"); $(cat "$tmp/$c/err")"
check "its wait line names its place, what runs and for how long" \
  'grep -q "waiting for a slot: 0 ahead, 1 running (pid $first for 0 min)" "$tmp/$c/err"' "$(cat "$tmp/$c/err")"

# ---- a slot whose pid is gone is taken back
c="dead"; mkdir -p "$tmp/$c"
start $c "touch $tmp/$c/started; exec sleep 60" PLINTH_HEAVY_SLOTS=1
holder=$started
appears "$tmp/$c/started"
kill -9 "$holder"; wait "$holder" 2>/dev/null
TMPDIR="$tmp/$c/tmp" PLINTH_HEAVY_SLOTS=1 PLINTH_HEAVY_WAIT=0 /bin/bash "$heavy" sh -c "touch $tmp/$c/ran" 2>"$tmp/$c/err"
rc=$?
check "a killed holder's slot is taken back: the next call runs" '[ "$rc" = 0 ] && [ -e "$tmp/$c/ran" ]' "rc=$rc; $(cat "$tmp/$c/err")"

# ---- a wait limit of 0 gives up on a busy slot, with its own status
c="busy"; mkdir -p "$tmp/$c"
start $c "touch $tmp/$c/started; exec sleep 60" PLINTH_HEAVY_SLOTS=1
appears "$tmp/$c/started"
TMPDIR="$tmp/$c/tmp" PLINTH_HEAVY_SLOTS=1 PLINTH_HEAVY_WAIT=0 /bin/bash "$heavy" sh -c "touch $tmp/$c/ran" 2>"$tmp/$c/err"
rc=$?
check "a wait limit of 0 on a busy slot: exit 75, \"did not run\", and the command did not run" \
  '[ "$rc" = 75 ] && grep -q "did not run" "$tmp/$c/err" && [ ! -e "$tmp/$c/ran" ]' "rc=$rc; $(cat "$tmp/$c/err")"

echo "  $pass passed, $fail failed"
[ "$fail" = 0 ]
