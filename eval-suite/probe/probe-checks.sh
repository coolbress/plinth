#!/bin/bash
# What blocker (c) is about: the commands a task's checks start with, run in
# the session's sandbox. One line each: PROBE <name> exit=<status> last=<line>.
run() {
  local name="$1" out rc
  shift
  out="$("$@" 2>&1)"; rc=$?
  printf 'PROBE %s exit=%s last=%s\n' "$name" "$rc" "$(printf '%s\n' "$out" | tail -1)"
}
run git-status git status -sb
run git-log git log --oneline -1
run uv-pytest uv run --offline pytest -q
run uv-ruff uv run --offline ruff check .
