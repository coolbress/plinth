#!/usr/bin/env bash
# What scripts/uv-pin-reminder.sh, the step of uv-pin-reminder.yml, does for each
# state of the pin and the open issue (#841), against a fake `gh`: fixtures in
# $FX, every call appended to $FX/calls. It runs from a copy, so the python-ci.yml
# it reads is the fixture's. Offline.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v jq >/dev/null || { echo "  FAIL  jq is needed for the reminder's issue filter and the fake gh"; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

mkdir -p "$work/bin"
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FX/calls"
args=("$@"); jqf=""
for ((i=0; i<${#args[@]}; i++)); do
  [ "${args[$i]}" = --jq ] && jqf="${args[$((i+1))]}"
  [ "${args[$i]}" = --body-file ] && cp "${args[$((i+1))]}" "$FX/body"
done
out() { [ -f "$1" ] || { echo "HTTP 502" >&2; exit 1; }; if [ -n "$jqf" ]; then jq -r "$jqf" "$1"; else cat "$1"; fi; }
case "$1 $2" in
  "api repos/astral-sh/uv/releases/latest") out "$FX/latest.json" ;;
  "api repos/astral-sh/uv/releases/tags/"*) out "$FX/pinned.json" ;;
  "issue list") out "$FX/issues.json" ;;
  "issue create"|"issue edit"|"issue close") ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$work/bin/gh"
ago() { python3 -c 'import datetime,sys; print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(days=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
MARK='<!-- plinth:uv-pin-reminder -->'

# setup <case> <pinned age in days> <latest version> <latest age in days>:
# pin 1.0.0 twice in python-ci.yml, no open issue. A case then changes one thing.
setup() {
  FX="$work/r-$1"; export FX; mkdir -p "$FX/.github/workflows" "$FX/scripts"; : >"$FX/calls"
  printf '          UV_VERSION: "1.0.0"\n          UV_VERSION: "1.0.0"\n' >"$FX/.github/workflows/python-ci.yml"
  [ -f "$root/scripts/uv-pin-reminder.sh" ] && cp "$root/scripts/uv-pin-reminder.sh" "$FX/scripts/"
  printf '{"published_at":"%s"}\n' "$(ago "$2")" >"$FX/pinned.json"
  printf '{"tag_name":"%s","published_at":"%s"}\n' "$3" "$(ago "$4")" >"$FX/latest.json"
  echo '[]' >"$FX/issues.json"
}
remind() { (cd "$FX" && PATH="$work/bin:$PATH" GITHUB_REPOSITORY=o/r RUN_URL=https://run bash "$FX/scripts/uv-pin-reminder.sh" 2>&1); }
writes() { grep -cE '^issue (create|edit|close)' "$FX/calls"; }
called() { grep -qE -- "$1" "$FX/calls"; }
open_ours() { printf '[{"number":7,"body":"%s\\nbody","author":{"login":"app/github-actions"}}]\n' "$MARK" >"$FX/issues.json"; }

setup behind 100 1.1.0 2; rc=0; out="$(remind)" || rc=$?
if [ "$rc" = 0 ] && [ "$(writes)" = 1 ] && called '^issue create .*--title Raise uv from 1\.0\.0 to 1\.1\.0: the pinned release is 100 days old' \
   && called '--label task' && called '--label ready-for-agent' && head -1 "$FX/body" | grep -qxF "$MARK"; then
  ok "a pin past 90 days with a newer release opens one issue, naming both versions"
else bad "behind, no issue: rc=$rc $out; $(cat "$FX/calls")"; fi
if [ -f "$FX/body" ] && grep -qF 'tests/uv-pin.sh' "$FX/body" && grep -qF 'coolbress/plinth-template' "$FX/body" && grep -qF 'releases/tag/1.1.0' "$FX/body"; then
  ok "the issue says where the copies are, the template first, and links the release"
else bad "the issue's body lacks the test, the template or the release"; fi

setup edit 100 1.1.0 2; open_ours; rc=0; out="$(remind)" || rc=$?
if [ "$rc" = 0 ] && [ "$(writes)" = 1 ] && called '^issue edit 7 .*--title Raise uv from 1\.0\.0 to 1\.1\.0' && ! called ' --body'; then
  ok "while one is open only its title moves: a decision written in its body stays"
else bad "behind, issue open: rc=$rc $out; $(cat "$FX/calls")"; fi

setup theirs 100 1.1.0 2; printf '[{"number":9,"body":"%s\\nbody","author":{"login":"someone"}}]\n' "$MARK" >"$FX/issues.json"; rc=0; out="$(remind)" || rc=$?
if [ "$rc" = 0 ] && called '^issue create' && ! called '^issue (edit|close) 9'; then ok "a person's issue with the same text is never touched"
else bad "someone else's issue: rc=$rc $out; $(cat "$FX/calls")"; fi

setup young 89 1.1.0 2; rc=0; out="$(remind)" || rc=$?
if [ "$rc" = 0 ] && [ "$(writes)" = 0 ] && grep -qF 'no reminder' <<<"$out"; then ok "behind for under 90 days says so and writes nothing"
else bad "under the threshold: rc=$rc $out; $(cat "$FX/calls")"; fi

setup edge 90 1.1.0 2; rc=0; out="$(remind)" || rc=$?
if [ "$rc" = 0 ] && called '^issue create'; then ok "90 days is past the threshold"
else bad "at the threshold: rc=$rc $out; $(cat "$FX/calls")"; fi

setup current 400 1.0.0 400; rc=0; out="$(remind)" || rc=$?
if [ "$rc" = 0 ] && [ "$(writes)" = 0 ]; then ok "a pin on the latest release writes nothing, however old"
else bad "on latest: rc=$rc $out; $(cat "$FX/calls")"; fi

setup closes 2 1.1.0 1; open_ours; rc=0; out="$(remind)" || rc=$?
if [ "$rc" = 0 ] && [ "$(sed -n 's/^issue \([a-z]*\) 7 .*/\1/p' "$FX/calls" | tr '\n' ' ')" = "edit close " ] \
   && head -1 "$FX/body" | grep -qxF "$MARK" && grep -qx 'body' "$FX/body" && grep -qx '## Outcome' "$FX/body" \
   && grep -qF 'uv 1.0.0 is pinned' "$FX/body" && grep -qF 'not what the merge ran' "$FX/body"; then
  ok "once the pin is raised the reminder writes its ending under the body, says what it checked, then closes"
else bad "raised, issue open: rc=$rc $out; $(cat "$FX/calls")"; fi

setup ended 2 1.1.0 1; printf '[{"number":7,"body":"%s\\n## Outcome\\nmine","author":{"login":"app/github-actions"}}]\n' "$MARK" >"$FX/issues.json"; rc=0; out="$(remind)" || rc=$?
if [ "$rc" = 0 ] && [ "$(writes)" = 1 ] && called '^issue close 7 '; then ok "an ending someone already wrote is kept"
else bad "issue with an Outcome: rc=$rc $out; $(cat "$FX/calls")"; fi

setup yanked 100 0.9.0 110; rc=0; out="$(remind)" || rc=$?
if [ "$rc" = 0 ] && [ "$(writes)" = 0 ]; then ok "a latest release older than the pin is not behind"
else bad "latest older than the pin: rc=$rc $out; $(cat "$FX/calls")"; fi

setup nolatest 100 1.1.0 2; rm "$FX/latest.json"; open_ours; rc=0; out="$(remind)" || rc=$?
if [ "$rc" != 0 ] && [ "$(writes)" = 0 ]; then ok "an unreadable latest release is red and closes nothing, never read as up to date"
else bad "latest unreadable: rc=$rc $out; $(cat "$FX/calls")"; fi

setup nopin 100 1.1.0 2; rm "$FX/pinned.json"; rc=0; out="$(remind)" || rc=$?
if [ "$rc" != 0 ] && [ "$(writes)" = 0 ]; then ok "an unreadable pinned release is red and opens nothing"
else bad "pinned release unreadable: rc=$rc $out; $(cat "$FX/calls")"; fi

setup nolist 100 1.1.0 2; rm "$FX/issues.json"; rc=0; out="$(remind)" || rc=$?
if [ "$rc" != 0 ] && [ "$(writes)" = 0 ]; then ok "an unreadable issue list is red and opens no second issue"
else bad "issue list unreadable: rc=$rc $out; $(cat "$FX/calls")"; fi

setup baddate 100 1.1.0 2; echo '{"published_at":"soon"}' >"$FX/pinned.json"; rc=0; out="$(remind)" || rc=$?
if [ "$rc" != 0 ] && [ "$(writes)" = 0 ]; then ok "a date it cannot read is red and writes nothing"
else bad "bad date: rc=$rc $out; $(cat "$FX/calls")"; fi

setup twopins 100 1.1.0 2; printf '          UV_VERSION: "1.0.1"\n' >>"$FX/.github/workflows/python-ci.yml"; rc=0; out="$(remind)" || rc=$?
if [ "$rc" != 0 ] && [ ! -s "$FX/calls" ]; then ok "python-ci.yml with two pins is red before it asks anything"
else bad "two pins in python-ci.yml: rc=$rc $out; $(cat "$FX/calls")"; fi

# It reports on plinth's own repository alone: nothing a consumer runs calls it,
# and no pull request starts it.
wf="$root/.github/workflows/uv-pin-reminder.yml"
if [ -f "$wf" ] && grep -q '^  schedule:' "$wf" && ! grep -qE '^  (pull_request|pull_request_target|push|workflow_call|merge_group):' "$wf"; then
  ok "the reminder runs on a schedule, never as a check on a pull request or a consumer's workflow call"
else bad "$wf is missing, or has a trigger that would make it a check or callable"; fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
