#!/usr/bin/env bash
# An interrupted install-smoke leaves nothing writing into the config dir it
# removes, and Ctrl-C stops it (#345). A stub `claude` on PATH stands in for the
# marketplace clone: on `marketplace add` it starts a child that names the
# config dir and recreates it every 0.1 s, ignoring INT and TERM, so only a
# cleanup that finds it and escalates to KILL keeps the dir removed. No network.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
floor="$(sed -nE 's/^claude_floor="([^"]+)"$/\1/p' "$root/scripts/new-project.sh")"
work="$(mktemp -d)"
# A failing run leaves its clone behind: stop it, whatever dir it names.
cleanup() {
  local d
  for d in "$work"/*/dir; do [ -s "$d" ] && pkill -KILL -f -- "$(cat "$d")"; done
  pkill -KILL -f -- "$work"; rm -rf "$work"
} 2>/dev/null
trap cleanup EXIT
fails=0
pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
alive() { kill -0 "$1" 2>/dev/null; }
naming() { pgrep -f -- "$1" >/dev/null; }

mkdir "$work/bin"
cat >"$work/bin/claude" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$STUB_LOG"
case "$*" in
  --version) echo "$STUB_VERSION (Claude Code)" ;;
  "plugin marketplace add "*)
    # Only the first add clones; a later one returns, so a script that goes
    # on after Ctrl-C reaches the end instead of hanging here.
    [ -e "$STUB_READY" ] && exit 0
    # The clone: its arguments name the config dir, as git clone's do.
    bash -c 'trap "" INT TERM; while :; do mkdir -p "$1"; sleep 0.1; done' \
      clone "$CLAUDE_CONFIG_DIR/plugins/marketplaces/x..clone" &
    # Not this run's: a directory whose name starts with the config dir's.
    perl -e 'setpgrp(0,0); sleep 600' "${CLAUDE_CONFIG_DIR}x" &
    echo "$!" >"$STUB_DECOY"
    : >"$STUB_READY"
    # Like claude, a Ctrl-C ends the add without a signal exit status, and
    # the clone is not waited for.
    trap 'exit 0' INT
    wait ;;
esac
exit 0
STUB
chmod +x "$work/bin/claude"

# run <case> <signal> <target: pid|group> [CLAUDE_CONFIG_DIR]
# Starts install-smoke in its own process group with default signal
# dispositions (a `&` job inherits SIGINT ignored), waits for the clone,
# sends the signal, and leaves: rc, dir, decoy pid, log in $work/<case>.
run() {
  local c="$1" sig="$2" target="$3" d="$work/$1" pid
  mkdir "$d"
  STUB_LOG="$d/log" STUB_READY="$d/ready" STUB_DECOY="$d/decoy" STUB_VERSION="$floor" \
    PATH="$work/bin:$PATH" env -u CLAUDE_CONFIG_DIR ${4:+"CLAUDE_CONFIG_DIR=$4"} \
    perl -e '$SIG{$_}="DEFAULT" for qw(INT TERM HUP); setpgrp(0,0); exec @ARGV' \
    bash "$root/tests/install-smoke.sh" >"$d/out" 2>&1 &
  pid=$!
  for _ in $(seq 100); do [ -e "$d/ready" ] && break; sleep 0.1; done
  [ -e "$d/ready" ] || { fail "$c: the stub clone never started"; cat "$d/out"; return 1; }
  sed -n 's/^config dir: //p' "$d/out" >"$d/dir"
  sleep 0.3
  if [ "$target" = group ]; then kill "-$sig" -- "-$pid"; else kill "-$sig" "$pid"; fi
  for _ in $(seq 100); do alive "$pid" || break; sleep 0.1; done
  if alive "$pid"; then
    fail "$c: still running 10 s after $sig"; kill -KILL -- "-$pid"; wait "$pid"; return 1
  fi
  { wait "$pid"; } 2>/dev/null; echo "$?" >"$d/rc"
  sleep 1
}

# A signal to the script alone: claude and its clone are not signalled. TERM
# and HUP (a closed terminal) take the same path.
for sig in TERM HUP; do
  c="$(tr '[:upper:]' '[:lower:]' <<<"$sig")"
  run "$c" "$sig" pid 2>/dev/null || continue
  dir="$(cat "$work/$c/dir")"; decoy="$(cat "$work/$c/decoy")"
  [ "$(cat "$work/$c/rc")" != 0 ] && pass "$sig: exits $(cat "$work/$c/rc")" || fail "$sig: exit 0"
  naming "$dir/" && fail "$sig: a process still names $dir" || pass "$sig: nothing names the dir"
  [ -e "$dir" ] && fail "$sig: $dir exists again" || pass "$sig: the dir stays removed"
  alive "$decoy" && pass "$sig: a process naming ${dir}x survives" || fail "$sig: the trap killed a process naming ${dir}x"
  kill "$decoy" 2>/dev/null
done

# Ctrl-C: INT to the whole group. claude ends the add with status 0, as the
# real one did; the script must stop rather than run the next README line.
if run int INT group 2>/dev/null; then
  dir="$(cat "$work/int/dir")"; decoy="$(cat "$work/int/decoy")"; rc="$(cat "$work/int/rc")"
  [ "$rc" = 130 ] && pass "INT: exits 130" || fail "INT: exit $rc, want 130"
  n="$(grep -cE '^plugin (marketplace add|install) ' "$work/int/log")"
  [ "$n" = 1 ] && pass "INT: no README line after the interrupted one ran" \
    || fail "INT: $n README lines ran: $(grep -E '^plugin (marketplace add|install) ' "$work/int/log" | tr '\n' ';')"
  naming "$dir/" && fail "INT: a process still names $dir" || pass "INT: nothing names the dir"
  [ -e "$dir" ] && fail "INT: $dir exists again" || pass "INT: the dir stays removed"
  alive "$decoy" && pass "INT: a process naming ${dir}x survives" || fail "INT: the trap killed a process naming ${dir}x"
  kill "$decoy" 2>/dev/null
fi

# A config dir the caller set is theirs: nothing that names it is stopped and
# it is not removed.
mkdir "$work/callers"
if run kept TERM pid "$work/callers" 2>/dev/null; then
  naming "$work/callers/plugins" && pass "kept: the caller's dir is left to the caller" \
    || fail "kept: the trap stopped a process naming the caller's dir"
  [ -d "$work/callers" ] && pass "kept: the caller's dir is not removed" || fail "kept: the caller's dir was removed"
  kill "$(cat "$work/kept/decoy")" 2>/dev/null
fi

[ "$fails" = 0 ] || { echo "  $fails failed"; exit 1; }
