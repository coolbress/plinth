#!/usr/bin/env bash
# with-admin-token.sh reads the token from the terminal, not from stdin. Offline.
#
# The property: stdin is not consumed. When several admin commands are pasted at
# once the shell holds the remaining lines and hands them to the script's
# `read`; read from stdin, the next command line becomes the token and that
# command silently never runs (measured 2026-08-30, three pasted ruleset
# updates). A real pty is needed to see it, so python drives one; with no
# terminal at all (a CI step) the token must come from stdin instead.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

# drive <pty|notty> <typed at the terminal> <stdin content> <command...>
# Prints the child's output, then a last line `exit=<code>`.
drive() {
  python3 - "$root/scripts/with-admin-token.sh" "$@" <<'PY' 2>&1
import os, pty, sys, select, time
script, mode, typed, stdin_text = sys.argv[1:5]
cmd = sys.argv[5:]
r, w = os.pipe()
os.write(w, stdin_text.encode()); os.close(w)
if mode == "pty":
    pid, master = pty.fork()          # the slave becomes the child's controlling terminal
    if pid == 0:
        os.dup2(r, 0)                 # only stdin is the pipe; /dev/tty is still the pty
        os.execv(script, [script] + cmd)
        os._exit(127)
    # Type only after the prompt: before `read -s` runs, the pty would echo the input.
    buf, until = b"", time.time() + 10
    while b"admin token" not in buf and time.time() < until:
        if select.select([master], [], [], 0.5)[0]:
            buf += os.read(master, 4096)
    time.sleep(0.3)                   # let `read -s` switch echo off, as it has when a person types
    os.write(master, typed.encode())
else:
    master, slave = os.pipe()
    pid = os.fork()
    if pid == 0:
        os.setsid()                   # no controlling terminal: /dev/tty cannot be opened
        os.dup2(r, 0); os.dup2(slave, 1); os.dup2(slave, 2)
        os.execv(script, [script] + cmd)
        os._exit(127)
    os.close(slave)
buf, status, deadline = b"", None, time.time() + 15   # the prompt already read is not part of the verdict
while time.time() < deadline:
    if not select.select([master], [], [], 0.5)[0]:
        done, st = os.waitpid(pid, os.WNOHANG)
        if done:
            status = st; break
        continue
    try:
        chunk = os.read(master, 4096)
    except OSError:
        break
    if not chunk: break
    buf += chunk
if status is None:
    _, status = os.waitpid(pid, 0)
sys.stdout.write(buf.decode("utf-8", "replace"))
print("exit=%d" % (os.WEXITSTATUS(status) if os.WIFEXITED(status) else -1))
PY
}

export GITHUB_TOKEN=an-everyday-token   # must not reach the command

# 1. A pty as the controlling terminal, a pasted next line on stdin.
out="$(drive pty "ghp_$(printf 'x%.0s' $(seq 36))"$'\n' $'LINE_FROM_PASTE\n' /bin/sh -c 'cat; echo "source=$PLINTH_TOKEN_SOURCE github_token=${GITHUB_TOKEN:-unset}"')"
case "$out" in
  *LINE_FROM_PASTE*) ok "the pasted next line is still on stdin (not swallowed)" ;;
  *) bad "stdin was consumed: the next command line would vanish as the token"; printf '%s\n' "$out" | sed 's/^/        /' ;;
esac
case "$out" in
  *"prefix ghp_ length 40"*) ok "the token was read from the terminal (the shape line, never the value)" ;;
  *) bad "no terminal input was read"; printf '%s\n' "$out" | sed 's/^/        /' ;;
esac
case "$out" in
  *xxxxxxxx*) bad "the token value was printed" ;;
  *) ok "the token value is not printed" ;;
esac
case "$out" in
  *"source=prompt github_token=unset"*) ok "the command sees PLINTH_TOKEN_SOURCE=prompt and no GITHUB_TOKEN" ;;
  *) bad "expected source=prompt github_token=unset"; printf '%s\n' "$out" | sed 's/^/        /' ;;
esac

# 2. An empty token is refused, before running anything.
out="$(drive pty $'   \n' "" /bin/sh -c 'echo RAN')"
case "$out" in
  *RAN*) bad "the command ran with an empty token" ;;
  *"empty token"*"exit=2"*) ok "an empty (whitespace) token is refused with exit 2" ;;
  *) bad "unexpected result for an empty token"; printf '%s\n' "$out" | sed 's/^/        /' ;;
esac

# 3. No terminal at all: the token comes from stdin, so automation is possible.
out="$(drive notty "" "github_pat_$(printf 'y%.0s' $(seq 30))"$'\n' /bin/sh -c 'echo "len=${#GH_TOKEN}"')"
case "$out" in
  *"len=41"*"exit=0"*) ok "without a terminal the token is read from stdin" ;;
  *) bad "the stdin fallback did not work"; printf '%s\n' "$out" | sed 's/^/        /' ;;
esac

# 4. A pasted value without an underscore (the paste-accident shape) shows four characters, never the whole.
out="$(drive notty "" "$(printf 'z%.0s' $(seq 40))"$'\n' /bin/sh -c 'exit 0')"
case "$out" in
  *zzzzzzzz*) bad "a token without an underscore was printed in full" ;;
  *"prefix zzzz length 40"*) ok "an unfamiliar token shows four characters and its length" ;;
  *) bad "unexpected shape line"; printf '%s\n' "$out" | sed 's/^/        /' ;;
esac

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
