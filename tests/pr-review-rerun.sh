#!/usr/bin/env bash
# When the scheduled review-rerun.yml asks a failed `third-party / review`
# again, and when it must not (#363).
#
# The decision is scripts/review-rerun.py, a pure function of the files the
# workflow fetches, so it is run here against fixtures. The shapes are the
# API's as measured on #362 (2026-09-30): the reviewer's zero-finding verdict
# was a `+1` reaction on the pull request, created 17:37:32, after the run
# that started 17:21:24 had given up its 900-second wait. Both directions are
# tested: a re-run nobody needed costs a 20-minute wait, and a re-run that
# never comes leaves the check red until a person acts.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rerun="$root/scripts/review-rerun.py"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

BOT='chatgpt-codex-connector[bot]'
END='2026-09-30T17:36:40Z'      # the failed attempt's end (`updated_at`)
LATE='2026-09-30T17:37:32Z'     # after it
EARLY='2026-09-30T17:30:00Z'    # during it

# One run of third-party.yml: id, status, conclusion, attempt, updated_at.
run_obj() {
  printf '{"id":%s,"status":"%s","conclusion":%s,"run_attempt":%s,"updated_at":"%s"}' \
    "$1" "$2" "$3" "$4" "$5"
}
failed() { run_obj "${1:-36750787489}" completed '"failure"' "${2:-1}" "${3:-$END}"; }
reaction() { printf '[{"user":{"login":"%s"},"content":"+1","created_at":"%s"}]' "$1" "$2"; }
review()   { printf '[{"user":{"login":"%s"},"state":"COMMENTED","submitted_at":"%s"}]' "$1" "$2"; }
comment()  { printf '[{"user":{"login":"%s"},"created_at":"%s","updated_at":"%s"}]' "$1" "$2" "$3"; }

fails=0
check() {  # name, runs JSON, expected exit, [reviews], [issue comments], [reactions], [expected text]
  printf '%s' "$2" > "$tmp/runs.json"
  printf '%s' "${4:-[]}" > "$tmp/r.json"
  printf '%s' "${5:-[]}" > "$tmp/i.json"
  printf '%s' "${6:-[]}" > "$tmp/x.json"
  python3 "$rerun" "$BOT" "$tmp/runs.json" "$tmp/r.json" "$tmp/i.json" "$tmp/x.json" >"$tmp/log" 2>&1
  got=$?
  if [ "$got" -ne "$3" ]; then
    echo "  FAIL  $1: expected exit $3, got $got" >&2; sed 's/^/        /' "$tmp/log" >&2; fails=$((fails + 1))
  elif [ -n "${7:-}" ] && ! grep -qF -- "$7" "$tmp/log"; then
    echo "  FAIL  $1: the log does not say '$7'" >&2; sed 's/^/        /' "$tmp/log" >&2; fails=$((fails + 1))
  else
    echo "  PASS  $1"
  fi
}

echo "-- re-runs"
check "the measured case: a +1 reaction after the failed run" "[$(failed)]" 0 '[]' '[]' "$(reaction "$BOT" "$LATE")" \
  "36750787489"
check "a review submitted after the failed run"               "[$(failed)]" 0 "$(review "$BOT" "$LATE")"
check "a completion comment created after the failed run"     "[$(failed)]" 0 '[]' "$(comment "$BOT" "$LATE" "$LATE")"
check "the summary comment edited after the failed run"       "[$(failed)]" 0 '[]' "$(comment "$BOT" "$EARLY" "$LATE")"
check "login differs in case"                                 "[$(failed)]" 0 '[]' '[]' "$(reaction 'ChatGPT-Codex-Connector[bot]' "$LATE")"
check "second attempt failed, a newer signal: one more"       "[$(failed 1 2)]" 0 '[]' '[]' "$(reaction "$BOT" "$LATE")" \
  "attempt 2"
check "the newest run decides, not the order listed"          "[$(run_obj 9 completed '"success"' 1 "$EARLY"),$(failed 10)]" 0 '[]' '[]' "$(reaction "$BOT" "$LATE")" \
  "re-run 10"

echo "-- does not re-run"
check "no run on this head"                                    '[]' 1 '[]' '[]' "$(reaction "$BOT" "$LATE")" "no run"
check "runs payload is not a list (the call failed)"           'null' 1 '[]' '[]' "$(reaction "$BOT" "$LATE")"
check "the newest run passed"                                  "[$(run_obj 1 completed '"success"' 1 "$END")]" 1 '[]' '[]' "$(reaction "$BOT" "$LATE")" "success"
check "the newest run is still going"                          "[$(run_obj 1 in_progress null 2 "$END")]" 1 '[]' '[]' "$(reaction "$BOT" "$LATE")" "in_progress"
check "a newer run passed after an older one failed"           "[$(failed 10),$(run_obj 11 completed '"success"' 1 "$LATE")]" 1 '[]' '[]' "$(reaction "$BOT" "$LATE")"
check "the newest run was cancelled, not failed"               "[$(run_obj 1 completed '"cancelled"' 1 "$END")]" 1 '[]' '[]' "$(reaction "$BOT" "$LATE")" "cancelled"
check "no signal at all: a reviewer that never started"        "[$(failed)]" 1 '[]' '[]' '[]' "nothing from an accepted reviewer"
check "the signal came before the run ended"                   "[$(failed)]" 1 "$(review "$BOT" "$EARLY")" "$(comment "$BOT" "$EARLY" "$EARLY")" "$(reaction "$BOT" "$EARLY")"
check "the signal at the same second as the end"               "[$(failed)]" 1 '[]' '[]' "$(reaction "$BOT" "$END")"
check "someone else's reaction"                                "[$(failed)]" 1 '[]' '[]' "$(reaction 'someone' "$LATE")"
check "someone else's review and comment"                      "[$(failed)]" 1 "$(review 'someone' "$LATE")" "$(comment 'someone' "$LATE" "$LATE")"
check "a re-run already failed after this signal (once per signal)" "[$(failed 1 2 "$LATE")]" 1 '[]' '[]' "$(reaction "$BOT" "$LATE")"
check "the third attempt failed: a person decides"             "[$(failed 1 3)]" 1 '[]' '[]' "$(reaction "$BOT" "$LATE")" "a person decides"
check "an end time that cannot be read"                        "[$(run_obj 1 completed '"failure"' 1 'yesterday')]" 1 '[]' '[]' "$(reaction "$BOT" "$LATE")"
check "signal files that are not lists"                        "[$(failed)]" 1 'null' '{"message":"Not Found"}' 'null'
check "a signal time that cannot be read"                      "[$(failed)]" 1 '[]' '[]' "$(reaction "$BOT" 'soon')"

if [ "$fails" -gt 0 ]; then
  echo "$fails case(s) failed"; exit 1
fi
echo "all cases passed"
