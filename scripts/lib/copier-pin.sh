# shellcheck shell=bash
# copier's pin, from its one source (#1220): tools/copier/pyproject.toml names
# copier's version, tools/copier/uv.lock every dependency's version with its
# hashes. Dependabot (uv) raises both in one pull request. Sourced by the
# doors, template-update.sh, the eval suite and the tests that render.

# <plinth root> -> the pinned copier version on stdout; empty when unread.
copier_pin_version() {
  sed -n 's/^ *"copier==\([^"]*\)",\{0,1\}$/\1/p' "$1/tools/copier/pyproject.toml" 2>/dev/null
}

# <plinth root> <command...>: runs the command with the lock, as a constraints
# file, in UV_CONSTRAINT: `uvx --from copier==<version>` then resolves every
# dependency at the version locked, never one published later. The file is
# written to a temporary path and removed after; the command's status is
# returned. The lock is read as it is (--frozen): nothing is resolved here.
copier_pinned() {
  local root="$1" pins rc=0; shift
  pins="$(mktemp "${TMPDIR:-/tmp}/plinth-copier-pins.XXXXXX")" || { echo "could not make a temp file for copier's pins" >&2; return 1; }
  if ! uv export --quiet --frozen --no-emit-project --no-header --no-annotate \
      --project "$root/tools/copier" -o "$pins" 2>/dev/null || ! grep -q '^copier==' "$pins"; then
    rm -f "$pins"
    echo "could not read copier's pins from $root/tools/copier/uv.lock (uv export)" >&2
    return 1
  fi
  UV_CONSTRAINT="$pins" "$@" || rc=$?
  rm -f "$pins"
  return "$rc"
}
