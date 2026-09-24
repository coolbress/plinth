#!/usr/bin/env bash
# Whether to post the summons at all, and as whom. Run by the second step of
# .github/workflows/pr-review.yml with SUMMONS_TOKEN, ASK, OWNER, FORK and
# LOGIN_JSON, the answer of `gh api user` made with the token. It prints
# `post` when the summons is to be posted, prints why not otherwise, and
# exits 1 when a token is set but cannot be used, so a broken token fails
# there and not after the wait. tests/pr-review-summon.sh runs this file.
set -euo pipefail
if [ -z "${SUMMONS_TOKEN:-}" ]; then
  if [ "${FORK:-false}" = "true" ]; then
    # GitHub withholds secrets from a pull request opened from a fork,
    # so a configured token is empty here; say so, or the caller reads
    # it as "not configured".
    echo "no summons-token (a fork's pull request gets no secrets): nothing is posted; waiting for the reviewer's own trigger, or for a person to comment the summons"
  else
    echo "no summons-token: nothing is posted; waiting for the reviewer's own trigger"
  fi
  exit 0
fi
if [ -z "${ASK:-}" ]; then
  echo "ask-comment is empty: nothing is posted"
  exit 0
fi
login="$(python3 - "${LOGIN_JSON:-/dev/null}" <<'PYLOGIN'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print((d.get("login") or "") if isinstance(d, dict) else "")
except Exception:
    print("")
PYLOGIN
)"
if [ -z "$login" ]; then
  echo "::error::summons-token is set but no login could be read with it; fix or remove the secret." >&2
  exit 1
fi
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
if [ "$(lower "$login")" != "$(lower "${OWNER:-}")" ]; then
  echo "::error::summons-token belongs to '$login', not to the repository owner '${OWNER:-}'; the summons is posted only as the owner." >&2
  exit 1
fi
echo "post"
