#!/usr/bin/env bash
# Verdicts of scripts/merge-when-green.sh against a fake `gh`. The fake answers
# with JSON fixtures and runs the script's own --jq filters through jq, so the
# filters are tested, not copied. Each case says whether a merge must happen;
# the fake records the `gh pr merge` call, so "no merge" is checked, not assumed.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/merge-when-green.sh"
command -v jq >/dev/null || { echo "  FAIL  jq is needed to run the fake gh's filters"; exit 1; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Fake gh: fixtures in $FX. `--jq F` is applied with jq to the fixture's JSON.
fx="$FX"; jqf=""; args=("$@")
for ((i=0; i<${#args[@]}; i++)); do [ "${args[$i]}" = --jq ] && jqf="${args[$((i+1))]}"; done
out() { if [ -n "$jqf" ]; then jq -r "$jqf" "$1"; else cat "$1"; fi; }
case "$1 $2" in
  "repo view") echo "o/r" ;;
  "pr view")
    case "$*" in
      *"state,mergeCommit"*) out "$fx/after.json" ;;
      *) out "$fx/pr.json" ;;
    esac ;;
  "pr checks") case "$*" in *--watch*) exit 0 ;; *) out "$fx/checks.json" ;; esac ;;
  "pr merge") printf '%s\n' "$*" >"$fx/merged"; exit "$(cat "$fx/merge_rc" 2>/dev/null || echo 0)" ;;
  api*)
    case "$*" in
      *"/commits/"*) out "$fx/commit.json" ;;
      *"/reviews"*) out "$fx/reviews.json" ;;
      *"/reactions"*) out "$fx/reactions.json" ;;
      *"/comments"*) out "$fx/comments.json" ;;
      *) echo "fake gh: unexpected api $*" >&2; exit 1 ;;
    esac ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$work/bin/gh"

H=1111111111111111111111111111111111111111
OLD=2222222222222222222222222222222222222222
BOT='chatgpt-codex-connector[bot]'
green='[{"name":"ci / install","state":"SUCCESS"},{"name":"third-party / review","state":"SUCCESS"}]'

# setup <case-dir>: a pull request that should merge; each case then breaks one thing.
setup() {
  FX="$work/$1"; export FX; mkdir -p "$FX"
  printf '{"state":"OPEN","headRefOid":"%s","body":"## What and why\\n\\nx"}' "$H" >"$FX/pr.json"
  printf '{"state":"MERGED","mergeCommit":{"oid":"abc"}}' >"$FX/after.json"
  printf '%s' "$green" >"$FX/checks.json"
  printf '{"commit":{"committer":{"date":"2026-09-29T00:00:00Z"}}}' >"$FX/commit.json"
  printf '[{"user":{"login":"%s"},"commit_id":"%s"}]' "$BOT" "$H" >"$FX/reviews.json"
  printf '[]' >"$FX/reactions.json"
  printf '[]' >"$FX/comments.json"
}

pass=0; fail=0
run() { # <merge|stop> <label> [script args...]
  local want="$1" label="$2"; shift 2
  local got rc
  PATH="$work/bin:$PATH" MERGE_POLL=0 MERGE_REVIEW_WAIT=0 bash "$script" 7 --repo o/r "$@" >"$FX/out" 2>&1; rc=$?
  if [ -f "$FX/merged" ]; then got=merge; else got=stop; fi
  # A merge exits 0; a stop exits non-zero and leaves no merge call behind.
  local ok=no
  if [ "$want" = merge ]; then [ "$got" = merge ] && [ "$rc" = 0 ] && ok=yes
  else [ "$got" = stop ] && [ "$rc" != 0 ] && ok=yes; fi
  if [ "$ok" = yes ]; then
    pass=$((pass+1)); printf '  PASS  %-5s %s\n' "$want" "$label"
  else
    fail=$((fail+1)); printf '  FAIL  %-5s %s  (got %s, exit %s)\n' "$want" "$label" "$got" "$rc"; sed 's/^/        /' "$FX/out"
  fi
}

echo "-- merges"
setup ok; run merge "green, a review on the head, no comments"
if grep -q -- "--match-head-commit $H" "$FX/merged" && grep -q -- "--squash" "$FX/merged"; then
  pass=$((pass+1)); echo "  PASS  merge  pins the head and squashes"
else
  fail=$((fail+1)); echo "  FAIL  merge  pins the head and squashes: $(cat "$FX/merged")"
fi
setup up; printf '[]' >"$FX/reviews.json"
printf '[{"user":{"login":"%s"},"content":"+1","created_at":"2026-09-29T00:01:00Z"}]' "$BOT" >"$FX/reactions.json"
run merge "a +1 after the push counts as the verdict"
setup answered
printf '[{"id":1,"in_reply_to_id":null,"path":"a","line":3,"body":"P2 x"},{"id":2,"in_reply_to_id":1,"path":"a","line":3,"body":"Fixed"}]' >"$FX/comments.json"
run merge "an inline comment with a reply"
setup norev; printf '[{"name":"ci / install","state":"SUCCESS"}]' >"$FX/checks.json"
run merge "no reviewer check, --no-reviewer given" --no-reviewer

echo "-- stops"
setup red; printf '[{"name":"ci / install","state":"FAILURE"},{"name":"third-party / review","state":"SUCCESS"}]' >"$FX/checks.json"
run stop "a failed check"
setup pending; printf '[{"name":"ci / install","state":"PENDING"},{"name":"third-party / review","state":"SUCCESS"}]' >"$FX/checks.json"
run stop "a check still pending"
setup none; printf '[]' >"$FX/checks.json"
run stop "no checks at all"
setup open
printf '[{"id":1,"in_reply_to_id":null,"path":"a","line":3,"body":"P1 x"}]' >"$FX/comments.json"
run stop "an inline comment with no reply"
setup oldopen
printf '[{"id":1,"in_reply_to_id":null,"path":"a","line":3,"body":"P1 old"},{"id":2,"in_reply_to_id":1,"path":"a","line":3,"body":"Fixed"},{"id":3,"in_reply_to_id":null,"path":"b","line":null,"original_line":9,"body":"P2 older, unanswered"}]' >"$FX/comments.json"
run stop "one answered and one unanswered comment"
setup stale; printf '[{"user":{"login":"%s"},"commit_id":"%s"}]' "$BOT" "$OLD" >"$FX/reviews.json"
run stop "a review on an older commit only"
setup oldup; printf '[]' >"$FX/reviews.json"
printf '[{"user":{"login":"%s"},"content":"+1","created_at":"2026-09-28T23:59:00Z"}]' "$BOT" >"$FX/reactions.json"
run stop "a +1 from before the push"
setup other; printf '[{"user":{"login":"someone"},"commit_id":"%s"}]' "$H" >"$FX/reviews.json"
run stop "a review on the head by someone else"
setup noflag; printf '[{"name":"ci / install","state":"SUCCESS"}]' >"$FX/checks.json"
run stop "no reviewer check and no --no-reviewer"
setup closed; printf '{"state":"MERGED","headRefOid":"%s","body":"x"}' "$H" >"$FX/pr.json"
run stop "a pull request that is not open"
setup nobody; printf '{"state":"OPEN","headRefOid":"%s","body":""}' "$H" >"$FX/pr.json"
run stop "an empty description"
setup refused; echo 1 >"$FX/merge_rc"
if PATH="$work/bin:$PATH" MERGE_POLL=0 MERGE_REVIEW_WAIT=0 bash "$script" 7 --repo o/r >"$FX/out" 2>&1; then
  fail=$((fail+1)); echo "  FAIL  stop  gh pr merge refusing (for example a newer head) exits non-zero"
else
  pass=$((pass+1)); echo "  PASS  stop  gh pr merge refusing (for example a newer head) exits non-zero"
fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
