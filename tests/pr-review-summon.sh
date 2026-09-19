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
#
# When it asks (#206): nothing at the start, a third and two thirds of the way
# into the wait, each only if no accepted reviewer has started. That test is a
# Python snippet, lifted and run against fixtures like the one above; the
# schedule is checked by running the whole step on a clock the test moves.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="$root/.github/workflows/pr-review.yml"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

python3 - "$wf" "$tmp" <<'PY'
import sys, pathlib, textwrap
lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
def lift(tag, out, must):
    start = next(i for i, ln in enumerate(lines) if ln.rstrip().endswith(f"<<'{tag}'"))
    end = next(i for i in range(start + 1, len(lines)) if lines[i].strip() == tag)
    body = textwrap.dedent("\n".join(lines[start + 1:end]))
    assert must in body, f"{tag} snippet not found; the workflow changed shape"
    pathlib.Path(sys.argv[2], out).write_text(body + "\n")
lift("SUMMON", "summon.sh", 'echo "post"')
lift("PYSTART", "started.py", "sys.exit")
# The whole second step, to run it on a clock the test moves (below).
start = next(i for i, ln in enumerate(lines) if "name: A third-party review is attached to this commit" in ln)
start = next(i for i in range(start, len(lines)) if lines[i].strip() == "run: |") + 1
end = next((i for i in range(start, len(lines)) if lines[i].strip() and len(lines[i]) - len(lines[i].lstrip()) < 10), len(lines))
pathlib.Path(sys.argv[2], "step.sh").write_text(textwrap.dedent("\n".join(lines[start:end])) + "\n")
PY
[ -s "$tmp/summon.sh" ] && [ -s "$tmp/started.py" ] && [ -s "$tmp/step.sh" ] \
  || { echo "  FAIL  could not extract the snippets" >&2; exit 1; }

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

HEAD=71a704cdca35f00de6e110a3d77a165d895d882a
OTHER=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
BOT='chatgpt-codex-connector[bot]'
LOG="[{\"after\":\"$HEAD\",\"before\":\"$OTHER\",\"timestamp\":\"2026-09-18T10:20:00Z\"}]"   # the head pushed at 10:20:00
FULL="$(python3 -c 'import json,sys; print(json.dumps([{"after":sys.argv[1],"timestamp":"2026-09-18T10:20:00Z"}]*100))' "$HEAD")"
said() {  # login, created_at, updated_at: one issue comment
  printf '[{"user":{"login":"%s"},"created_at":"%s","updated_at":"%s","body":"<!-- codex-pull-request-review-summary -->"}]' "$1" "$2" "$3"
}
started() {  # name, issue comments, activity log (or "missing"), first ask point ('' at the first), expected exit, expected text
  printf '%s' "$2" > "$tmp/ic.json"
  if [ "$3" = "missing" ]; then rm -f "$tmp/act.json"; else printf '%s' "$3" > "$tmp/act.json"; fi
  python3 "$tmp/started.py" "$HEAD" "$BOT" "$tmp/ic.json" "$tmp/act.json" "$4" >"$tmp/out" 2>"$tmp/err"
  got=$?
  if [ "$got" -ne "$5" ] || ! grep -qF "$6" "$tmp/out"; then
    echo "  FAIL  $1: expected exit $5 with '$6', got exit $got" >&2
    sed 's/^/        out: /' "$tmp/out" >&2; sed 's/^/        err: /' "$tmp/err" >&2
    fails=$((fails + 1))
  else
    echo "  PASS  $1"
  fi
}
AFTER="$(said "$BOT" 2026-09-18T10:20:05Z 2026-09-18T10:20:05Z)"   # the reviewer's summary, five seconds after the push

echo "-- has an accepted reviewer started? exit 0 = yes, do not ask (#206)"
started "first ask point: comment created after the push"          "$AFTER" "$LOG" "" 0 "reviewer active since the push (2026-09-18T10:20:00Z): $BOT, comment updated 2026-09-18T10:20:05Z"
started "created before the push, updated after it"                "$(said "$BOT" 2026-09-18T10:10:00Z 2026-09-18T10:21:00Z)" "$LOG" "" 0 "comment updated 2026-09-18T10:21:00Z"
started "accepted login in another letter case"                    "$(said 'ChatGPT-Codex-Connector[bot]' 2026-09-18T10:21:00Z 2026-09-18T10:21:00Z)" "$LOG" "" 0 "reviewer active"
started "second ask point: updated after the first ask point"      "$(said "$BOT" 2026-09-18T10:21:00Z 2026-09-18T10:26:00Z)" "$LOG" 2026-09-18T10:25:00Z 0 "reviewer active since the first ask point (2026-09-18T10:25:00Z)"

echo "-- nobody has: exit 1, ask"
started "nothing from an accepted reviewer"                        "[]" "$LOG" "" 1 "nothing from an accepted reviewer since the push (2026-09-18T10:20:00Z)"
started "the comments call failed (null)"                          "null" "$LOG" "" 1 "nothing from an accepted reviewer"
started "activity only before the push"                            "$(said "$BOT" 2026-09-18T10:10:00Z 2026-09-18T10:15:00Z)" "$LOG" "" 1 "nothing from an accepted reviewer"
started "a comment updated at the push's second"                   "$(said "$BOT" 2026-09-18T10:10:00Z 2026-09-18T10:20:00Z)" "$LOG" "" 1 "nothing from an accepted reviewer"
started "activity only from other accounts"                        "$(said coolbress 2026-09-18T10:21:00Z 2026-09-18T10:21:00Z)" "$LOG" "" 1 "nothing from an accepted reviewer"
started "push unreadable: no log"                                  "$AFTER" missing "" 1 "the push of this head could not be read"
started "push unreadable: null"                                    "$AFTER" null    "" 1 "the push of this head could not be read"
started "push unreadable: the head is not in the log"              "$AFTER" "[{\"after\":\"$OTHER\",\"timestamp\":\"2026-09-18T10:00:00Z\"}]" "" 1 "the push of this head could not be read"
started "push unreadable: a full page of 100"                      "$AFTER" "$FULL" "" 1 "the push of this head could not be read"
started "push unreadable: the head's push has no time"             "$AFTER" "[{\"after\":\"$HEAD\"}]" "" 1 "the push of this head could not be read"
started "second ask point: active after the push, none since"      "$(said "$BOT" 2026-09-18T10:21:00Z 2026-09-18T10:22:00Z)" "$LOG" 2026-09-18T10:25:00Z 1 "nothing from an accepted reviewer since the first ask point (2026-09-18T10:25:00Z)"

# The whole step, on a clock that only `sleep` moves, with `gh` answering from
# files: when it posts, not only whether. A 30 s wait, a look every 10 s. The
# mocks are sh where they can be: a Python start is slow on some laptops.
mkdir -p "$tmp/bin" "$tmp/rt"
cat > "$tmp/bin/gh" <<'SH'
#!/bin/sh
case "$*" in
  "pr comment"*|*--jq*) exec python3 "$MOCK/../gh.py" "$@" ;;
  "api user") touch "$MOCK/user-called"; echo '{"login":"coolbress"}' ;;
  */activity*) cat "$MOCK/activity.json" ;;
  */issues/7/comments*) cat "$MOCK/icomments.json" ;;
  *) echo '[]' ;;
esac
SH
cat > "$tmp/gh.py" <<'PY'
import json, os, sys, pathlib
m = pathlib.Path(os.environ["MOCK"]); a = sys.argv[1:]
ic = json.loads((m / "icomments.json").read_text())
if a[:2] == ["pr", "comment"]:   # a post: an issue comment by the owner, stamped with the clock
    body = pathlib.Path(a[a.index("--body-file") + 1]).read_text()
    ic.append({"user": {"login": "coolbress"}, "body": body, "at": int((m / "clock").read_text())})
    (m / "icomments.json").write_text(json.dumps(ic))
else:                            # --jq '.[].body'
    print("\n".join(c["body"] for c in ic))
PY
printf '#!/bin/sh\necho $(( $(cat "$MOCK/clock") + $1 )) > "$MOCK/clock"\n' > "$tmp/bin/sleep"
cat > "$tmp/bin/date" <<'SH'
#!/bin/sh
c="$(cat "$MOCK/clock")"; for f; do :; done   # f: the format, the last argument
if [ "$f" = "+%s" ]; then echo "$c"; else /bin/date -u -r "$c" "$f" 2>/dev/null || /bin/date -u -d "@$c" "$f"; fi
SH
chmod +x "$tmp/bin/"*
T0=1789726800   # 2026-09-18T10:20:00Z, the push in $LOG; the run starts then
step() {  # name, token, issue comments before the run, expected posts (seconds into the wait, space separated)
  rm -rf "$tmp/m"; mkdir -p "$tmp/m"
  echo "$T0" > "$tmp/m/clock"
  printf '%s' "$LOG" > "$tmp/m/activity.json"; printf '%s' "${3:-[]}" > "$tmp/m/icomments.json"
  PATH="$tmp/bin:$PATH" MOCK="$tmp/m" RUNNER_TEMP="$tmp/rt" REPO=o/r NUMBER=7 HEAD_SHA="$HEAD" HEAD_REF=b \
    AUTHOR_LOGIN=coolbress TITLE=t LOGINS="$BOT" ASK="@codex review" SUMMONS_TOKEN="$2" OWNER=coolbress \
    WAIT=30 POLL=10 bash "$tmp/step.sh" >"$tmp/out" 2>&1
  got=$?
  at="$(python3 -c 'import json,sys; print(" ".join(str(p["at"] - int(sys.argv[2])) for p in json.load(open(sys.argv[1])) if "at" in p))' "$tmp/m/icomments.json" "$T0")"
  if [ "$got" -ne 1 ] || [ "$at" != "$4" ] || ! grep -qF "configure-the-third-party-reviewer.md#summoning-the-reviewer" "$tmp/out"; then
    echo "  FAIL  $1: expected posts at '$4' s and the red log with the how-to, got posts at '$at' s, exit $got" >&2
    sed 's/^/        /' "$tmp/out" | grep -v '^        \(   \.\.\.\|not yet\)' >&2
    fails=$((fails + 1))
  else
    echo "  PASS  $1"
  fi
}
PRIOR="[{\"user\":{\"login\":\"coolbress\"},\"body\":\"@codex review\n\n<!-- third-party-review: $HEAD -->\"}]"

echo "-- the whole step on a moved clock: when it asks"
step "token, no reviewer: nothing at the start, then at 1/3 and 2/3"  tok ""  "10 20"
grep -qF "nothing from an accepted reviewer since the first ask point (2026-09-18T10:20:10Z): asking (2/2)" "$tmp/out" \
  || { echo "  FAIL  the second ask's log does not say why" >&2; fails=$((fails + 1)); }
step "token, reviewer started after the push: only the second ask"     tok "$AFTER" "20"
grep -qF "reviewer active since the push (2026-09-18T10:20:00Z): $BOT, comment updated 2026-09-18T10:20:05Z: not asking" "$tmp/out" \
  || { echo "  FAIL  the first ask point's log does not say why it did not ask" >&2; fails=$((fails + 1)); }
step "token, one ask by an earlier run: one more, never a third"       tok "$PRIOR" "10"
grep -qF "asked twice already for this commit" "$tmp/out" \
  || { echo "  FAIL  the cap is not in the log" >&2; fails=$((fails + 1)); }
step "no token (an empty secret): nothing posted, login never read"   ""  ""  ""
if [ -e "$tmp/m/user-called" ]; then echo "  FAIL  no token, but the login was read" >&2; fails=$((fails + 1)); fi

echo "-- the workflow itself: read permission only, and the post goes out with the token"
if grep -q 'pull-requests: write' "$wf"; then
  echo "  FAIL  pr-review.yml still asks for pull-requests: write" >&2; fails=$((fails + 1))
else
  echo "  PASS  pr-review.yml asks for pull-requests: read"
fi
url='https://github.com/coolbress/plinth/blob/main/docs/how-to/configure-the-third-party-reviewer.md#summoning-the-reviewer'
if grep -qF "$url" "$wf" && grep -qx '### Summoning the reviewer' "$root/docs/how-to/configure-the-third-party-reviewer.md"; then
  echo "  PASS  the red log names the how-to's summons section, and the section is there"
else
  echo "  FAIL  the failure no longer says where the summons is written down, or the section was renamed" >&2; fails=$((fails + 1))
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
