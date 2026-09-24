# shellcheck shell=bash disable=SC2154  # $root is set by the script that sources this file
# The Python tools of `ci / tools` (zizmor, ruff, mypy), installed from
# tests/lint-tools.txt with every artifact checked against its hash (#264).
# Sourced by tests/workflow-lint.sh and tests/python-lint.sh, which set $root.
#
# pipx and uvx pin a version but check no hash, so this uses a venv and
# `pip install --require-hashes --only-binary=:all:`: a wheel whose hash is not
# in the file stops the install, and nothing is built from source. The venv is
# kept per lock file, interpreter and cache path (lint_tools_key) under the
# user's cache directory, so a second local run does not download again; CI
# starts empty every time. Each run builds in a directory of its own
# (`<key>.<random>`) and uses any finished one, so two runs at once never
# delete each other's; a venv cannot be moved once made, its paths are absolute.
#
# PLINTH_LINT_TOOLS_BIN, when set, is used as the tools' directory instead:
# tests/lint-wrappers-cases.sh puts stubs there. The wrappers say so, and in CI
# (GITHUB_ACTIONS) it is a FAIL: there the tools are the hash-checked ones.

lint_tool_version() { # <package> -> its pinned version in tests/lint-tools.txt
  sed -n "s/^$1==\([^ ;]*\).*/\1/p" "$root/tests/lint-tools.txt"
}

# The key covers the lock file's bytes; the interpreter's version, real path,
# platform and ABI; and the cache directory's real path, because a venv's
# console scripts name its Python by absolute path and lint_tools_bin builds
# under that real path. The same cache volume mounted at two paths therefore
# gives two keys. Nothing else is in it: two
# machines or containers that match on all of these share one venv.
lint_tools_key() { # <python> <lock file> <cache dir> -> the cache key on stdout
  "$1" -c 'import hashlib, os, sys, sysconfig
who = [sys.version, os.path.realpath(sys.executable), sysconfig.get_platform(), sys.implementation.cache_tag or "", os.path.realpath(sys.argv[2])]
print(hashlib.sha256(open(sys.argv[1], "rb").read() + "\0".join(who).encode()).hexdigest()[:16])' "$2" "$3"
}

lint_tools_bin() { # -> the tools' bin directory on stdout; on failure a FAIL line there, and 1
  local req="$root/tests/lint-tools.txt" py key cache real dir mark
  if [ -n "${PLINTH_LINT_TOOLS_BIN:-}" ]; then
    [ -z "${GITHUB_ACTIONS:-}" ] || { echo "  FAIL  PLINTH_LINT_TOOLS_BIN is set in CI, where the tools must be the hash-checked ones"; return 1; }
    printf '%s' "$PLINTH_LINT_TOOLS_BIN"; return 0
  fi
  py="$(command -v python3)" || { echo "  FAIL  python3 not found: install Python 3.10 or later (https://www.python.org/downloads/)"; return 1; }
  "$py" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null \
    || { echo "  FAIL  $("$py" --version 2>&1) is older than 3.10, which the pinned tools need"; return 1; }
  # Debian and Ubuntu package venv's pip bootstrap separately from python3.
  "$py" -c 'import ensurepip, venv' 2>/dev/null \
    || { echo "  FAIL  python3 cannot make a venv with pip: install python3-venv (Debian, Ubuntu: sudo apt-get install python3-venv)"; return 1; }
  cache="${XDG_CACHE_HOME:-$HOME/.cache}/plinth/lint-tools"
  # Built and keyed under the resolved path, so the path in the venv's scripts
  # is the one in the key, however the cache was reached.
  real="$(mkdir -p "$cache" && cd -P "$cache" && pwd -P)" || { echo "  FAIL  cannot make $cache"; return 1; }
  cache="$real"
  key="$(lint_tools_key "$py" "$req" "$cache")" || { echo "  FAIL  cannot read $req"; return 1; }
  # A finished venv for this key; one without the marker
  # (an interrupted run, or one still installing) is never used.
  for mark in "$cache/$key".*/.installed; do
    [ -f "$mark" ] && { printf '%s' "${mark%/.installed}/bin"; return 0; }
  done
  # A random name, not the PID: two containers sharing this cache can have the same PID.
  dir="$(mktemp -d "$cache/$key.XXXXXX")" \
    || { echo "  FAIL  cannot make a directory under $cache"; return 1; }
  if ! { "$py" -m venv "$dir" && "$dir/bin/python" -m pip install --quiet \
          --disable-pip-version-check --no-input --require-hashes --only-binary=:all: -r "$req"; } >&2; then
    rm -rf "${dir:?}"
    echo "  FAIL  installing tests/lint-tools.txt, hash-checked, into a venv (needs network the first time)"; return 1
  fi
  touch "$dir/.installed"
  printf '%s' "$dir/bin"
}
