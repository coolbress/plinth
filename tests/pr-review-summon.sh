#!/usr/bin/env bash
# When the third-party review check posts its summons, and as whom.
#
# A mention posted by `github-actions[bot]` is not honoured by the reviewer
# (measured 2026-09-18 on #186: two drew nothing in the full wait, a person's
# identical comment started a review in sixteen seconds), so the summons goes
# out only with the `summons-token` secret, as the repository owner. The
# decision is a shell snippet inside the `run:` of pr-review.yml; lifted out
# here and run against the login the token would return. Both directions:
# nothing posted without a token, posted only as the owner with one, and a
# token that cannot be used fails at once rather than after the wait.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="$root/.github/workflows/pr-review.yml"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

python3 - "$wf" "$tmp/summon.sh" <<'PY'
import sys, pathlib, textwrap
lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
start = next(i for i, ln in enumerate(lines) if ln.rstrip().endswith("<<'SUMMON'"))
end = next(i for i in range(start + 1, len(lines)) if lines[i].strip() == "SUMMON")
body = textwrap.dedent("\n".join(lines[start + 1:end]))
assert "summons-token" in body and 'echo "post"' in body, "summon snippet not found; the workflow changed shape"
pathlib.Path(sys.argv[2]).write_text(body + "\n")
PY
[ -s "$tmp/summon.sh" ] || { echo "  FAIL  could not extract the summon snippet" >&2; exit 1; }

fails=0
run() {  # name, token, ask, owner, login-json (or "missing"), expected exit, expected stdout text
  if [ "$5" = "missing" ]; then rm -f "$tmp/login.json"; else printf '%s' "$5" > "$tmp/login.json"; fi
  SUMMONS_TOKEN="$2" ASK="$3" OWNER="$4" LOGIN_JSON="$tmp/login.json" \
    bash "$tmp/summon.sh" >"$tmp/out" 2>"$tmp/err"
  got=$?
  if [ "$got" -ne "$6" ] || ! grep -qF "$7" "$tmp/out" "$tmp/err"; then
    echo "  FAIL  $1: expected exit $6 with '$7', got exit $got" >&2
    sed 's/^/        out: /' "$tmp/out" >&2; sed 's/^/        err: /' "$tmp/err" >&2
    fails=$((fails + 1))
  else
    echo "  PASS  $1"
  fi
}
OWNER_JSON='{"login":"coolbress","id":1}'

echo "-- without a token nothing is posted, whatever the login file says"
run "no token, no file"              ""   "@codex review" coolbress missing       0 "nothing is posted"
run "no token, owner's login file"   ""   "@codex review" coolbress "$OWNER_JSON" 0 "nothing is posted"
run "no token: never 'post'"         ""   "@codex review" coolbress "$OWNER_JSON" 0 "nothing is posted"
# A fork's pull request gets no secrets, so a configured token arrives empty: the line says which case this is.
FORK=true  run "no token on a fork's pull request: says so"  "" "@codex review" coolbress missing 0 "a fork's pull request gets no secrets"
FORK=false run "no token, not a fork: plain line"            "" "@codex review" coolbress missing 0 "no summons-token: nothing"
if FORK=false SUMMONS_TOKEN="" ASK="@codex review" OWNER=coolbress LOGIN_JSON="$tmp/login.json" bash "$tmp/summon.sh" | grep -q "fork"; then
  echo "  FAIL  not a fork, but the fork line printed" >&2; fails=$((fails + 1))
fi
if SUMMONS_TOKEN="" ASK="@codex review" OWNER=coolbress LOGIN_JSON="$tmp/login.json" bash "$tmp/summon.sh" | grep -qx post; then
  echo "  FAIL  no token but 'post' printed" >&2; fails=$((fails + 1))
fi

echo "-- with a token, only the owner's login posts"
run "owner's token posts"            tok  "@codex review" coolbress "$OWNER_JSON" 0 "post"
run "login differs in case"          tok  "@codex review" CoolBress "$OWNER_JSON" 0 "post"
run "another person's token"         tok  "@codex review" coolbress '{"login":"someone"}' 1 "not to the repository owner"
run "empty ask-comment: nothing"     tok  ""              coolbress "$OWNER_JSON" 0 "nothing is posted"

echo "-- a token that is set but cannot be used fails at once, not after the wait"
run "no login file"                  tok  "@codex review" coolbress missing               1 "no login could be read"
run "null (the step's fallback)"     tok  "@codex review" coolbress null                  1 "no login could be read"
run "an API error object"            tok  "@codex review" coolbress '{"message":"Bad credentials"}' 1 "no login could be read"
run "not JSON"                       tok  "@codex review" coolbress '<html>'              1 "no login could be read"
run "a list, not an object"          tok  "@codex review" coolbress '[]'                  1 "no login could be read"
run "login empty"                    tok  "@codex review" coolbress '{"login":""}'        1 "no login could be read"

echo "-- the workflow itself: read permission only, and the post goes out with the token"
if grep -q 'pull-requests: write' "$wf"; then
  echo "  FAIL  pr-review.yml still asks for pull-requests: write" >&2; fails=$((fails + 1))
else
  echo "  PASS  pr-review.yml asks for pull-requests: read"
fi
if grep -q 'GH_TOKEN="\$SUMMONS_TOKEN" gh pr comment' "$wf" && [ "$(grep -c 'gh pr comment' "$wf")" -eq 1 ]; then
  echo "  PASS  the one comment posted goes out with summons-token"
else
  echo "  FAIL  a comment is posted without summons-token, or more than one" >&2; fails=$((fails + 1))
fi

if [ "$fails" -ne 0 ]; then
  echo "-- $fails failed" >&2
  exit 1
fi
echo "-- posts only as the owner, with a token; without one, nothing"
