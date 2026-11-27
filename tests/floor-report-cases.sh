#!/usr/bin/env bash
# scripts/floor-report.py, the short report /plinth:floor-check gives (#1105),
# against runs of the real checker and against documents built here:
#   - the first line is the verdict; at most five action rows, then "N more"
#     naming every other finding; no check id; one question, last;
#   - a finding that cannot be kept (it reaches others) comes first;
#   - what could not be read is neither counted nor a row;
#   - the facts #1105 leaves to the JSON, and the sandbox's lines, are not in
#     the report and are in --all (and --area machine for the sandbox);
#   - on a checkout shaped like plinth the report is at most 12 lines;
#   - a finding that cannot be kept is its own row, with its fix lines;
#   - the re-run note: written only on the default branch with a clean
#     tree, outside the repository, and compared by id (fixed, still
#     missing, new); `git status --porcelain` is empty after it.
# Offline: the checker runs with --no-network, the note under a temporary
# XDG_CACHE_HOME.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root/scripts/floor-check.py"
report="$root/scripts/floor-report.py"
work="$(mktemp -d)" || { echo "floor-report-cases: could not make a temp folder" >&2; exit 1; }; trap 'rm -rf "$work"' EXIT
export XDG_CACHE_HOME="$work/cache"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        /'; return 0; }

# shape <description> <report text>: the rules every report keeps.
shape() {
  local what="$1" out="$2" rows last
  rows="$(grep -cE '^[0-9]+\. ' <<<"$out")"
  last="$(tail -1 <<<"$out")"
  if head -1 <<<"$out" | grep -qE '(to fix|to look at|nothing needs a look|stopped early).*Nothing was changed\.$' \
     && [ "$rows" -le 5 ] && ! grep -qE 'FC-[A-Z][0-9]' <<<"$out" \
     && [ "${last: -1}" = "?" ] && [ "$(grep -c '?$' <<<"$out")" = 1 ]
  then ok "$what: a verdict first, $rows action rows, no check id, one question last"
  else bad "$what: the report's shape is off" "$out"; fi
}

# ---- Runs of the real checker.
mkdir -p "$work/empty"
python3 "$checker" --root "$work/empty" --no-network --sandbox --plugins --credentials --format json > "$work/empty.json" 2>/dev/null
out="$(python3 "$report" --no-note "$work/empty.json")"
shape "an empty folder" "$out"
for f in CHANGELOG.md uv.lock .github/dependabot.yml; do
  if grep -qF -- "$f" <<<"$out"; then ok "an empty folder: the report names $f"; else bad "an empty folder: $f is not named" "$out"; fi
done
if grep -qE '^1\. I can do it in one pull request: ' <<<"$out" && [ "$(grep -c '^[0-9]*\.* *I can do it in one pull request' <<<"$out")" = 1 ] \
   && [ "$(grep -c 'as one pull request for you to approve?$' <<<"$out")" = 1 ]
then ok "an empty folder: every file item is one row, and the pull request is offered once"
else bad "an empty folder: the file items are not one row, or the pull request is offered more than once" "$out"; fi
# What this machine prints differs (a runner has no plugins installed): the
# real run is held only to leaving these out; a document built below holds
# every one of them, in --all and not in the report.
for s in 'sandbox not verified' 'SSH keys not verified' 'not read either' 'no other credential found' 'no production database URL found' 'from another marketplace' "at the plinth marketplace's pin" 'no archetype'; do
  if grep -qF -- "$s" <<<"$out"; then bad "an empty folder: \"$s\" is in the report; it belongs in the JSON" "$out"
  else ok "an empty folder: \"$s\" is not in the report"; fi
done
if python3 "$report" --area machine "$work/empty.json" | grep -qF '  off: '; then ok "the sandbox's lines print with --area machine"
else bad "the sandbox's lines do not print with --area machine"; fi
if python3 "$report" --all "$work/empty.json" | grep -qE '^  (FAIL|INFO|SKIP) '; then ok "--all prints the results as the checker's lines"
else bad "--all does not print the results as lines"; fi

# A checkout shaped like plinth: this one.
python3 "$checker" --root "$root" --no-network --format json > "$work/plinth.json" 2>/dev/null
out="$(python3 "$report" --no-note "$work/plinth.json")"
shape "plinth's own checkout" "$out"
n="$(wc -l <<<"$out" | tr -d ' ')"
if [ "$n" -le 12 ]; then ok "plinth's own checkout: the report is $n lines (at most 12)"
else bad "plinth's own checkout: the report is $n lines, more than 12" "$out"; fi
if python3 "$report" --all "$work/plinth.json" | grep -q '^  PASS '; then ok "--all prints the PASS lines"
else bad "--all prints no PASS line"; fi

# ---- Documents built here, from a real one's shape.
# doc <name> <python: edits to d, a document of no results>: writes $work/<name>.json
doc() {
  python3 - "$work/plinth.json" "$work/$1.json" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["results"], d["not_evaluated"], d["crashed"], d["repo"] = [], [], None, "o/r"
def r(i, state, msg, *, key="bad", handoff="person", keepable=True, ci=True, area="wall", reason=None, here=False, reader=None, name=None):
    d["results"].append({"id": i, "state": state, "shown": {"pass": "PASS", "fail": "FAIL", "warn": "WARN", "unknown": "SKIP",
                         "review": "INFO", "info": "INFO", "not_applicable": "N/A"}[state], "message": msg,
                         "reason": reason, "cannot_be_read_here": here, "reader": reader, "key": key, "area": area,
                         "name": name or f"check {i[3:]}", "handoff": handoff, "fix": "x", "keepable": keepable,
                         "lifecycle": "stable", "view": "report", "ci_visible": ci})
exec(sys.argv[3])
n = {s: sum(x["state"] == s for x in d["results"]) for s in ("pass", "fail", "warn", "unknown", "review", "not_applicable", "info")}
d["summary"] = {**n, "cannot_be_read_here": sum(x["cannot_be_read_here"] for x in d["results"])}
d["exit"] = 1 if n["fail"] else 0
json.dump(d, open(sys.argv[2], "w"))
PY
}

# One result for each fact #1105 leaves to the JSON, as the checker words it.
doc facts '
r("FC-G10", "unknown", "SSH keys not verified here: GitHub settings say which keys push", key="github", area="machine", reason="cannot be read here", here=True)
r("FC-G10", "info", "  not read either: a program named by GIT_ASKPASS", key="askpass", area="machine")
r("FC-G06", "info", "gh stores 1 account for github.com: x; no other credential found by these rules", key="none", area="machine")
r("FC-G07", "info", "git asks only gh for github.com; no other credential found by these rules", key="none", area="machine")
r("FC-G09", "info", "no github.com login in ~/.netrc; no other credential found by these rules", key="none", area="machine")
r("FC-G11", "info", "no production database URL found in this environment", key="none", area="machine")
r("FC-G02", "info", "at the plinth marketplace'"'"'s pin: plinth@plinth (user)", key="current", area="machine")
r("FC-G02", "info", "plugins from another marketplace, outside what plinth compares: x@y", key="other", area="machine")
r("FC-E06", "info", "wall expectation: checks [], merge methods [squash]", key="expect")
r("FC-E30", "pass", "the repository has a description", key="good")
r("FC-E07", "info", "the wall is checked on main, the repository'"'"'s default branch", key="where")
r("FC-C03", "unknown", "no archetype (no .copier-answers.yml, no --archetype); conditional items skipped", key="none", area="project", reason="no archetype")
r("FC-C26", "pass", "JSON logs: static hint in src/app.py (structlog)", key="good", area="project")
r("FC-A11", "info", "a local ISSUE_TEMPLATE replaces the owner'"'"'s shared set", key="info", area="files")
r("FC-A01", "fail", "LICENSE missing or empty", area="files", handoff="agent")
'
out="$(python3 "$report" --no-note "$work/facts.json")"
all="$(python3 "$report" --all "$work/facts.json")"
for s in 'SSH keys not verified' 'not read either' 'no other credential found' 'no production database URL found' "at the plinth marketplace's pin" 'from another marketplace' 'wall expectation' 'the repository has a description' 'the wall is checked on' 'no archetype' 'JSON logs: static hint' 'a local ISSUE_TEMPLATE'; do
  if grep -qF -- "$s" <<<"$out"; then bad "\"$s\" is in the report; it belongs in the JSON" "$out"
  elif grep -qF -- "$s" <<<"$all"; then ok "\"$s\" is in --all, not in the report"
  else bad "\"$s\" is in neither the report nor --all" "$all"; fi
done

# The merge line: guidance or a boundary for the agent's login, on its own line.
doc guidance '
r("FC-E26", "info", "the merge: guidance. This login is the repository'"'"'s admin, and GitHub lets the admin merge, so an agent working under it can merge too; it is asked to wait for your word", key="admin")
'
doc boundary '
r("FC-E26", "pass", "the merge: boundary. This login is not the repository'"'"'s admin and the merge ruleset stands on main, so GitHub refuses its merge; you merge", key="stands")
'
for k in guidance boundary; do
  out="$(python3 "$report" --no-note "$work/$k.json")"
  if grep -qE "^The merge: $k\. " <<<"$out" && ! grep -qE '^[0-9]+\. ' <<<"$out"; then ok "the merge as $k: said on its own line, not as an action row"
  else bad "the merge as $k is not said on its own line" "$out"; fi
  shape "the merge as $k" "$out"
done

doc many '
for k in range(1, 9):
    r(f"FC-E{k:02d}", "warn" if k % 2 else "fail", f"finding {k}")
r("FC-E20", "warn", "it reaches others", keepable=False)
'
out="$(python3 "$report" --no-note "$work/many.json")"
shape "nine findings" "$out"
if [ "$(grep -cE '^[0-9]+\. ' <<<"$out")" = 5 ] && grep -qE '^4 more: ' <<<"$out"; then ok "nine findings: five rows, then \"4 more\""
else bad "nine findings: not five rows and \"4 more\"" "$out"; fi
missing=""
for k in 1 2 3 4 5 6 7 8; do grep -qF "finding $k" <<<"$out" || grep -qF "check E0$k" <<<"$out" || missing="$missing $k"; done
if [ -z "$missing" ]; then ok "nine findings: each is in a row or named in \"more\""; else bad "nine findings: not named:$missing" "$out"; fi
if grep -qE '^1\. .*it reaches others' <<<"$out"; then ok "a finding that cannot be kept is the first row"
else bad "a finding that cannot be kept is not the first row" "$out"; fi

doc unread '
r("FC-E01", "unknown", "wall not checked (offline)", reason="--no-network")
r("FC-E09", "unknown", "push protection not verified", reason="cannot be read here", here=True)
r("FC-A01", "pass", "LICENSE present", key="good", area="files")
'
out="$(python3 "$report" --no-note "$work/unread.json")"
shape "only unread items" "$out"
if head -1 <<<"$out" | grep -qF 'No check failed' && ! grep -qE '^[0-9]+\. ' <<<"$out" && grep -qF 'these are not failures' <<<"$out"
then ok "what could not be read is not counted, is no row, and is said not to be a failure"
else bad "what could not be read was counted or made a row" "$out"; fi

doc crashed 'd["crashed"] = {"after": None, "error": "PermissionError"}'
out="$(python3 "$report" --no-note "$work/crashed.json")"
shape "a run that stopped" "$out"
if printf '' | python3 "$report" --no-note >/dev/null; [ $? = 2 ]; then ok "no document on stdin (a usage error): exit 2"
else bad "no document on stdin did not exit 2"; fi

# A tracked secret cannot be kept: its row is its own, with the line saying
# that removing the file does not undo a value that was ever real.
dot="$work/dotenv"
git init -q -b main "$dot" && printf 'KEY=x\n' > "$dot/.env" && git -C "$dot" add .env \
  && git -C "$dot" -c user.email=t@t -c user.name=t commit -q -m init
python3 "$checker" --root "$dot" --no-network --format json > "$work/dotenv.json" 2>/dev/null
out="$(python3 "$report" --no-note "$work/dotenv.json")"
if grep -A3 -E '^1\. .*tracked dotenv' <<<"$out" | grep -qF 'rotated'; then ok "a tracked .env: the first row, with its line that a real value is rotated"
else bad "a tracked .env is not the first row with its rotation line" "$out"; fi

doc review '
r("FC-E09", "review", "push protection not read with this token", reader="/plinth:floor-check with an admin login")
r("FC-E21", "unknown", "CodeQL rule not verified", reason="cannot be read here", here=True)
r("FC-E07", "info", "the wall is checked on trunk, the repository'"'"'s default branch", key="where")
r("FC-E13", "fail", "no rules govern trunk: the wall is down", keepable=False, handoff="admin")
r("FC-C05", "not_applicable", "the Python items: does not apply", key="js", area="project")
'
out="$(python3 "$report" --no-note "$work/review.json" 2>&1)"
shape "a review, a read no change clears, an N/A and a wall row" "$out"
if grep -qF 'a run of /plinth:floor-check with an admin login' <<<"$out"; then ok "a review names who reads it"; else bad "a review does not name who reads it" "$out"; fi
if grep -qF "ci / lint" <<<"$out"; then ok "a read no change here clears names what stands in for it"; else bad "no stand-in named" "$out"; fi
if grep -qE '^1\. .*\(the wall is read on trunk\)' <<<"$out"; then ok "the wall row names the branch it was read on"; else bad "the wall row does not name its branch" "$out"; fi
if grep -qF 'plinth has no checks for' <<<"$out"; then ok "N/A items: the report says plinth has no checks for the language"; else bad "N/A items are in no line" "$out"; fi

# ---- The re-run note.
repo="$work/repo"
git init -q -b main "$repo" && git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
where='r("FC-E07", "info", "the wall is checked on main, the repository'"'"'s default branch", key="where")'
doc before "$where"'
r("FC-A01", "fail", "LICENSE missing or empty", area="files", handoff="agent")
r("FC-A02", "fail", "README.md missing or empty", area="files", handoff="agent")
'
doc after "$where"'
r("FC-A02", "fail", "README.md missing or empty", area="files", handoff="agent")
r("FC-A03", "fail", "CHANGELOG.md missing or empty", area="files", handoff="agent")
'
note="$XDG_CACHE_HOME/plinth/github-o-r/floor.json"
python3 "$report" --root "$repo" "$work/before.json" > "$work/out1"
if [ -f "$note" ] && ! grep -q '^Since the last run' "$work/out1"; then ok "a first run on the default branch, clean: the note is written, nothing to compare"
else bad "a first run did not write the note, or compared with nothing" "$(cat "$work/out1")"; fi
out="$(python3 "$report" --root "$repo" "$work/after.json")"
if grep -qF '1 fixed, 1 still missing, 1 new.' <<<"$out"; then ok "the run after: 1 fixed, 1 still missing, 1 new, by id"
else bad "the run after does not count by id" "$out"; fi
if [ -z "$(git -C "$repo" status --porcelain)" ]; then ok "git status --porcelain is empty after both runs"
else bad "the runs changed the repository" "$(git -C "$repo" status --porcelain)"; fi
shape "a re-run" "$out"

# A finding the next run cannot read is neither fixed nor dropped from the note.
doc offline "$where"'
r("FC-A02", "unknown", "README.md not verified", area="files", handoff="agent", reason="--no-network")
r("FC-A03", "fail", "CHANGELOG.md missing or empty", area="files", handoff="agent")
'
out="$(python3 "$report" --root "$repo" "$work/offline.json")"
if grep -qF '0 fixed, 1 still missing, 0 new; 1 not read this time, so not counted.' <<<"$out" && grep -qF '"FC-A02"' "$note"
then ok "a finding not read this time is not counted as fixed, and the note keeps it"
else bad "a finding not read this time was counted as fixed, or the note lost it" "$out"$'\n'"$(cat "$note")"; fi
# A wall failure, then a run offline: the checker emits the wall's one SKIP
# and evaluates none of its checks, so they are in not_evaluated. They are
# not fixed, and the note keeps them.
doc wallfail "$where"'
r("FC-E13", "fail", "no rules govern main: the wall is down", keepable=False, handoff="admin")
'
python3 "$report" --root "$repo" "$work/wallfail.json" >/dev/null
python3 "$checker" --root "$repo" --no-network --repo o/r --format json > "$work/offline-real.json" 2>/dev/null
if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(not any(n["id"]=="FC-E13" for n in d["not_evaluated"]))' "$work/offline-real.json"
then ok "the real checker offline lists the wall's checks as not evaluated"
else bad "the real checker offline did not list FC-E13 as not evaluated: the next case reads nothing"; fi
out="$(python3 "$report" --root "$repo" "$work/offline-real.json")"
if grep -qE '^Since the last run .*: 0 fixed, 0 still missing, [0-9]+ new; 1 not read this time, so not counted\.$' <<<"$out"
then ok "a wall failure the next run did not evaluate is not counted as fixed"
else bad "a wall failure the next run did not evaluate was counted as fixed" "$out"; fi
doc walloff "$where"'
d["not_evaluated"] = [{"id": "FC-E13", "name": "check E13", "area": "wall"}]
'
python3 "$report" --root "$repo" "$work/wallfail.json" >/dev/null
python3 "$report" --root "$repo" "$work/walloff.json" >/dev/null
if grep -qF '"FC-E13"' "$note"; then ok "the note written after a run that did not evaluate it keeps the wall failure"
else bad "the note lost a finding its run did not evaluate" "$(cat "$note")"; fi

doc crashrun "$where"'
d["crashed"] = {"after": None, "error": "OSError"}
'
out="$(python3 "$report" --root "$repo" "$work/crashrun.json")"
if ! grep -q '^Since the last run' <<<"$out"; then ok "a run that stopped early says nothing about what changed"
else bad "a run that stopped early compared with the last one" "$out"; fi

# The note is written only from the default branch with a clean tree.
cp "$note" "$work/note.kept"
touch "$repo/new-file"
python3 "$report" --root "$repo" "$work/before.json" >/dev/null
if cmp -s "$note" "$work/note.kept"; then ok "a working tree with changes: the note is not written"
else bad "a working tree with changes wrote the note"; fi
rm "$repo/new-file"; git -C "$repo" switch -q -c other
python3 "$report" --root "$repo" "$work/before.json" >/dev/null
if cmp -s "$note" "$work/note.kept"; then ok "another branch: the note is not written"
else bad "another branch wrote the note"; fi
git -C "$repo" switch -q main
python3 "$report" --root "$repo" --no-note "$work/before.json" >/dev/null
if cmp -s "$note" "$work/note.kept"; then ok "--no-note: the note is not written"
else bad "--no-note wrote the note"; fi
python3 "$report" --root "$repo" "$work/empty.json" >/dev/null
if [ "$(find "$XDG_CACHE_HOME/plinth" -name floor.json | wc -l | tr -d ' ')" = 1 ]; then ok "a run with no repository name writes no note"
else bad "a run with no repository name wrote a note" "$(find "$XDG_CACHE_HOME/plinth" -name floor.json)"; fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
