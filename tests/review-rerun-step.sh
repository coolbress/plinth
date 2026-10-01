#!/usr/bin/env bash
# What scripts/review-rerun.sh, the step of review-rerun.yml, asks GitHub and
# re-runs for each event, against a fake `gh` that records every call (#363).
#
# A comment by anyone but an accepted reviewer, or on an issue, ends with no
# call at all: the comment trigger fires on every comment in the repository.
# A reviewer's comment on a pull request reads that pull request alone; the
# schedule reads every open one. Which run to re-run is review-rerun.py's
# decision, tested in tests/pr-review-rerun.sh; here it is only fed.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/review-rerun.sh"
command -v jq >/dev/null || { echo "  FAIL  jq is needed to run the fake gh's filters"; exit 1; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Fake gh: fixtures in $FX, every call appended to $FX/calls. `--jq F` is
# applied with jq to the fixture's JSON.
fx="$FX"; jqf=""; args=("$@")
printf '%s\n' "$*" >>"$fx/calls"
for ((i=0; i<${#args[@]}; i++)); do [ "${args[$i]}" = --jq ] && jqf="${args[$((i+1))]}"; done
out() { if [ -n "$jqf" ]; then jq -r "$jqf" "$1"; else cat "$1"; fi; }
case "$1 $2" in
  "run rerun") exit "$(cat "$fx/rerun_rc" 2>/dev/null || echo 0)" ;;
  "run view") out "$fx/run_now.json" ;;
  api*)
    case "$2" in
      */pulls\?state=open*)        out "$fx/open.json" ;;
      */actions/workflows/*/runs*) out "$fx/runs.json" ;;
      */pulls/*/reviews)           out "$fx/reviews.json" ;;
      */pulls/*/comments)          echo '[]' ;;
      */issues/*/comments)         out "$fx/icomments.json" ;;
      */issues/*/reactions)        echo '[]' ;;
      */pulls/[0-9]*)              out "$fx/pr.json" ;;
      *) echo "fake gh: unexpected api $*" >&2; exit 1 ;;
    esac ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$work/bin/gh"

BOT='chatgpt-codex-connector[bot]'
SHA=1111111111111111111111111111111111111111

# setup <case>: pull request #7, open, whose newest review run failed and
# whose reviewer commented after it; each case then changes one thing.
setup() {
  FX="$work/$1"; export FX; mkdir -p "$FX"; : >"$FX/calls"
  printf '{"number":7,"state":"open","head":{"sha":"%s"}}' "$SHA" >"$FX/pr.json"
  printf '[{"number":7,"head":{"sha":"%s"}}]' "$SHA" >"$FX/open.json"
  printf '{"workflow_runs":[{"id":42,"status":"completed","conclusion":"failure","run_attempt":1,"updated_at":"2026-09-30T17:36:40Z"}]}' >"$FX/runs.json"
  echo '[]' >"$FX/reviews.json"
  printf '[{"user":{"login":"%s"},"created_at":"2026-09-30T17:37:27Z","updated_at":"2026-09-30T17:37:27Z"}]' "$BOT" >"$FX/icomments.json"
  echo '{"status":"completed"}' >"$FX/run_now.json"
}

pass=0; fail=0
# check <label> <want exit> <want: rerun|none> [grep the calls for this] [refuse this in the calls]
# Event variables come from the environment of the call.
check() {
  local label="$1" want_rc="$2" want="$3" must="${4:-}" mustnot="${5:-}" rc got=none ok=yes
  mkdir -p "$FX/tmp"; PATH="$work/bin:$PATH" RUNNER_TEMP="$FX/tmp" REPO=o/r LOGINS="$BOT" bash "$script" >"$FX/out" 2>&1; rc=$?
  grep -q '^run rerun 42 --failed' "$FX/calls" && got=rerun
  [ "$rc" = "$want_rc" ] && [ "$got" = "$want" ] || ok=no
  if [ -n "$must" ] && ! grep -qF -- "$must" "$FX/calls"; then ok=no; fi
  if [ -n "$mustnot" ] && grep -qF -- "$mustnot" "$FX/calls"; then ok=no; fi
  if [ "$ok" = yes ]; then echo "  PASS  $label"; pass=$((pass + 1))
  else
    echo "  FAIL  $label: exit $rc (want $want_rc), $got (want $want)" >&2
    sed 's/^/        out: /' "$FX/out" >&2; sed 's/^/        gh: /' "$FX/calls" >&2
    fail=$((fail + 1))
  fi
}
comment() {  # <commenter> [is a pull request: url or empty]
  export EVENT=issue_comment PR=7 COMMENTER="$1" IS_PR="${2-https://api.github.com/repos/o/r/pulls/7}"
}

echo "-- a comment: nothing at all unless it is the reviewer's, on a pull request"
setup someone;   comment 'someone'
check "a person's comment: no call"                     0 none
[ -s "$FX/calls" ] && { echo "  FAIL  a person's comment made gh calls" >&2; fail=$((fail + 1)); }
grep -qF "not an accepted reviewer" "$FX/out" || { echo "  FAIL  the log does not say why nothing was done" >&2; fail=$((fail + 1)); }
setup otherbot;  comment 'github-actions[bot]'
check "another bot's comment: no call"                  0 none
[ -s "$FX/calls" ] && { echo "  FAIL  another bot's comment made gh calls" >&2; fail=$((fail + 1)); }
setup issue;     comment "$BOT" ''
check "the reviewer's comment on an issue: no call"     0 none
[ -s "$FX/calls" ] && { echo "  FAIL  a comment on an issue made gh calls" >&2; fail=$((fail + 1)); }
setup lookalike; comment "x$BOT"
check "a login that only contains the reviewer's: no call" 0 none

echo "-- the reviewer's comment on a pull request: that pull request alone"
setup reviewer;  comment "$BOT"
check "re-runs the failed run of that pull request"     0 rerun "api repos/o/r/pulls/7" "pulls?state=open"
setup case;      comment 'ChatGPT-Codex-Connector[bot]'
check "login in another letter case"                    0 rerun
setup closed;    comment "$BOT"
printf '{"number":7,"state":"closed","head":{"sha":"%s"}}' "$SHA" >"$FX/pr.json"
check "a closed pull request: no re-run"                0 none "" "workflows"
setup passed;    comment "$BOT"
printf '{"workflow_runs":[{"id":42,"status":"completed","conclusion":"success","run_attempt":1,"updated_at":"2026-09-30T17:36:40Z"}]}' >"$FX/runs.json"
check "the newest run passed: no re-run"                0 none

echo "-- the schedule: every open pull request"
unset EVENT PR COMMENTER IS_PR
setup schedule;  export EVENT=schedule
check "re-runs from the list of open pull requests"     0 rerun "pulls?state=open"
setup none;      export EVENT=schedule; echo '' >"$FX/open.json"; printf '[]' >"$FX/open.json"
check "no open pull requests: no re-run"                0 none

echo "-- a re-run that is refused"
setup race;      comment "$BOT"; echo 1 >"$FX/rerun_rc"; echo '{"status":"in_progress"}' >"$FX/run_now.json"
check "already running again (the other trigger got there first): not an error" 0 rerun
grep -qF "already" "$FX/out" || { echo "  FAIL  the log does not say the run was already going" >&2; fail=$((fail + 1)); }
setup refused;   comment "$BOT"; echo 1 >"$FX/rerun_rc"
check "refused and still finished: the job fails"       1 rerun

echo "-- $pass passed, $fail failed"
[ "$fail" -eq 0 ]
