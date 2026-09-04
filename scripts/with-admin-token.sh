#!/usr/bin/env bash
# Ask for an admin token, then run a command with it. The token never appears
# on a command line or in shell history.
#
#   with-admin-token.sh <command> [args...]
#   with-admin-token.sh scripts/new-project.sh myorg/myapp
#
# Why: `GH_TOKEN='<paste>' ./new-project.sh` lands the token in
# ~/.zsh_history (histignorespace only helps with a leading space). Reading it
# here and passing it through the environment keeps it off every command line.
#
# The token: classic with `repo`, `workflow` and, for rollback, `delete_repo`,
# or a fine-grained one with Administration: write and access to the owner's
# repositories, including the one about to be created. Short expiry.
set -euo pipefail

[ $# -gt 0 ] || { echo "usage: with-admin-token.sh <command> [args...]" >&2; exit 2; }

# Read from the terminal, not from stdin. When several lines are pasted at
# once, the shell holds the rest in its buffer and a `read` on stdin would
# swallow the next command line as the token: that command silently never
# runs (measured 2026-08-30 with three pasted ruleset updates). Without a
# terminal (a CI step, a pipe) stdin is the only source, so it is used then.
# `read -s` silences the terminal only when stdin is that terminal; with a
# pasted stdin it is not, so echo is switched off explicitly (and back on,
# also on Ctrl-C).
if { exec 3</dev/tty; } 2>/dev/null; then
  trap 'stty echo <&3' EXIT   # Ctrl-C at the prompt must not leave echo off
  stty -echo <&3
else
  exec 3<&0
fi
printf 'admin token (input is hidden): ' >&2
IFS= read -rs -u 3 GH_TOKEN || true
{ stty echo <&3; } 2>/dev/null || true
trap - EXIT
exec 3<&-
printf '\n' >&2

# Strip whitespace a paste drags along. One invisible character passes the API
# (HTTP headers are trimmed by the server) and fails `git push` (HTTP Basic
# keeps it inside the base64). This broke a first push twice (2026-08-27).
GH_TOKEN="${GH_TOKEN#"${GH_TOKEN%%[![:space:]]*}"}"
GH_TOKEN="${GH_TOKEN%"${GH_TOKEN##*[![:space:]]}"}"

[ -n "$GH_TOKEN" ] || { echo "empty token, stopping." >&2; exit 2; }

# Show the shape, never the value, so a paste accident is visible: the known
# prefix, or the first four characters of whatever came in.
case "$GH_TOKEN" in
  ghp_*|gho_*|ghs_*|ghu_*) prefix="${GH_TOKEN:0:4}" ;;
  github_pat_*)            prefix="github_pat_" ;;
  *) prefix="${GH_TOKEN:0:4}"; echo "  warning: unfamiliar prefix; expected ghp_ (classic) or github_pat_ (fine-grained)" >&2 ;;
esac
printf '  token: prefix %s length %s\n' "$prefix" "${#GH_TOKEN}" >&2

export GH_TOKEN
# Tells the command the token was typed here, not found in the environment.
export PLINTH_TOKEN_SOURCE=prompt
# Keep a restricted everyday token out of the way. gh prefers GH_TOKEN, but be explicit.
unset GITHUB_TOKEN

# exec: this shell does not stay around holding the token.
exec "$@"
