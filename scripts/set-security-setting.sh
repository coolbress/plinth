#!/usr/bin/env bash
# Enable a security setting on a repository and verify that it took. Run by a
# person; needs repository administration.
#
#   set-security-setting.sh [--dry-run] <setting> <owner/name> ...
#   settings: non-provider-patterns, validity-checks
#
# Why a tool: without verification the change fails in silence. Measured
# 2026-08-30: `gh api -X PATCH repos/O/R -f "security_and_analysis[x][status]=enabled"`
# returned 200 and changed nothing. `-f` sends a form field; this endpoint
# takes nested JSON and the server ignores unknown fields. The response body
# still said `disabled` and was read as success. So this script writes, reads
# back, and compares.
#
# Everyday tokens get a 403 here. Run it through the wrapper:
#   scripts/with-admin-token.sh scripts/set-security-setting.sh non-provider-patterns <owner/name>
set -euo pipefail

usage="usage: set-security-setting.sh [--dry-run] <setting> <owner/name> ..."
dry=0
[ "${1:-}" = "--dry-run" ] && { dry=1; shift; }
setting="${1:?$usage}"; shift
[ $# -gt 0 ] || { echo "name at least one repository" >&2; exit 2; }

case "$setting" in
  non-provider-patterns) key=secret_scanning_non_provider_patterns ;;
  validity-checks)       key=secret_scanning_validity_checks ;;
  *) echo "unknown setting: $setting (non-provider-patterns, validity-checks)" >&2; exit 2 ;;
esac

fail=0
for repo in "$@"; do
  before="$(gh api "repos/$repo" --jq ".security_and_analysis.$key.status // \"absent\"")"
  if [ "$dry" = 1 ]; then
    echo "-- $repo: $key = $before  (--dry-run: nothing written)"
    continue
  fi

  # Nested JSON. The form field `-f a[b][c]=v` is ignored by the server in silence.
  jq -n --arg k "$key" '{security_and_analysis: {($k): {status: "enabled"}}}' \
    | gh api "repos/$repo" -X PATCH --input - >/dev/null

  after="$(gh api "repos/$repo" --jq ".security_and_analysis.$key.status // \"absent\"")"
  if [ "$after" = "enabled" ]; then
    echo "-- $repo: $key  $before -> $after"
  else
    echo "-- $repo: $key  $before -> $after  did not take effect" >&2
    fail=1
  fi
done

[ "$fail" = 0 ] || { echo "at least one setting did not take effect. A 200 is not proof." >&2; exit 1; }
