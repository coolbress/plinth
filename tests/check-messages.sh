#!/usr/bin/env bash
# What a beginner and their agent read first after a red or warning check
# (#837): every ::error:: and ::warning:: of `ci / pr-title`, `ci / diff-size`,
# `ci / floor-check` and closing-references.sh says what failed, gives one next
# action and links to the page that explains, in at most 300 characters.
# The steps are extracted from python-ci.yml and run on failing fixtures, so the
# messages read are the ones shipped; each case also pins the step's exit code,
# so a change of words that changes a verdict fails here. The same literals are
# read from the source too, so a message no fixture reaches is still held to a
# link. Not read: the count `N more not yet confirmed lines are in the job
# summary`, a helper every job shares (weakened-checks-cases.sh holds them
# equal), and the checks #837 does not name.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="$root/.github/workflows/python-ci.yml"
command -v jq >/dev/null || { echo "  FAIL  jq is needed to build the fixtures"; exit 1; }
python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))' \
  || { echo "  FAIL  needs python3 3.11 or later, as the runner has; got $(python3 --version 2>&1)"; exit 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/check-messages.XXXXXX")"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        | /'; }

# step <job> <step name> <out>: the step's `run: |` block, dedented.
step() {
  python3 - "$wf" "$1" "$2" > "$3" <<'PY' || { echo "  FAIL  step '$2' not found in python-ci.yml's $1"; exit 1; }
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
start = lines.index(f"  {sys.argv[2]}:")
end = next((i for i in range(start + 1, len(lines)) if re.match(r"^  [a-z]", lines[i])), len(lines))
at = next(i for i in range(start, end) if lines[i].strip() == f"- name: {sys.argv[3]}")
r = next(i for i in range(at, end) if lines[i].strip() == "run: |")
indent = None
for l in lines[r + 1:end]:
    if l.strip() and indent is None:
        indent = len(l) - len(l.lstrip())
    if l.strip() and len(l) - len(l.lstrip()) < indent:
        break
    print(l[indent:] if l.strip() else "")
PY
}
step pr-title "Check the title" "$work/title.sh"
step pr-title "The description closes no issue outside its closing line" "$work/description.sh"
step diff-size "Measure the reviewable diff" "$work/measure.sh"
step diff-size "Name changes to the checks the description does not" "$work/names.py"
step diff-size "Ask an admin to approve a change to the checks" "$work/ask.py"
step floor-check "Floor check" "$work/floor.sh"

# case <label> <want exit> <file with the step's output>: the exit code is the
# verdict, and at least one annotation must come out: a fixture that stopped
# emitting would otherwise pass here with nothing read.
annotations="$work/annotations"; : > "$annotations"
seen() {
  local label="$1" want="$2" got="$3" file="$4" lines
  lines="$(grep -E '^::(error|warning)::' "$file" | grep -vE '^::warning::[0-9]+ more not yet confirmed lines are in the job summary$')"
  if [ "$got" != "$want" ]; then bad "$label: exit $got, want $want" "$(cat "$file")"; return; fi
  if [ -z "$lines" ]; then bad "$label: no annotation came out" "$(cat "$file")"; return; fi
  ok "$label: exit $got, $(wc -l <<<"$lines" | tr -d ' ') annotation(s) read"
  while IFS= read -r l; do printf '%s\t%s\n' "$label" "$l" >> "$annotations"; done <<<"$lines"
}

echo "-- ci / pr-title: the title"
long="$(printf 'x%.0s' $(seq 1 256))"
run_title() {
  : > "$work/sum"
  env GITHUB_STEP_SUMMARY="$work/sum" TITLE="$2" bash -e "$work/title.sh" > "$work/out" 2>&1
  seen "$1" 1 "$?" "$work/out"
}
run_title "a title that is not Conventional Commits" "Add a thing"
run_title "a 256-character title that is not" "$long"
run_title "a title ending in a number" "fix: a thing (#12)"
run_title "a 256-character title ending in a number" "fix: $long (#12)"
run_title "a revert of a title that is not" 'Revert "Add a thing"'
run_title "a 256-character revert of a title that is not" "Revert \"$long\""
run_title "a revert of a title ending in a number" 'Revert "fix: a thing (#12)"'
run_title "a 256-character revert of a title ending in a number" "Revert \"fix: $long (#12)\""

echo "-- ci / pr-title and ci / docs: the description"
cat > "$work/bin/gh" <<'SH'
#!/usr/bin/env bash
case "$1 $2" in
  "api graphql")
    if [[ "$*" == *"pullRequests(first: 1"* ]]; then cat "$FX/highest.json"; exit 0; fi
    cat "$FX/response.json"; exit "$(cat "$FX/gh_rc" 2>/dev/null || echo 0)" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
SH
chmod +x "$work/bin/gh"
n=0
fx() { # <description> [issues the merge closes]
  n=$((n + 1)); FX="$work/d$n"; export FX; mkdir -p "$FX/temp/plinth-closing"; : > "$FX/summary"
  cp "$root/scripts/closing-references.sh" "$root/scripts/closing-references.py" "$root/scripts/description-fields.py" "$FX/temp/plinth-closing/"
  local refs='[]' r
  for r in ${2:-}; do refs="$(jq -c --argjson num "$r" '. + [{number: $num, repository: {nameWithOwner: "o/r"}}]' <<<"$refs")"; done
  jq -n --arg body "$1" --argjson refs "$refs" \
    '{data: {repository: {pullRequest: {body: $body, closingIssuesReferences: {nodes: $refs, pageInfo: {hasNextPage: false}}}}}}' > "$FX/response.json"
  echo '{"data":{"repository":{"issues":{"nodes":[{"number":40}]},"pullRequests":{"nodes":[{"number":41}]}}}}' > "$FX/highest.json"
}
run_description() { # <label> <want exit>
  PATH="$work/bin:$PATH" RUNNER_TEMP="$FX/temp" GITHUB_STEP_SUMMARY="$FX/summary" REPO=o/r GH_TOKEN=x \
    EVENT_NAME=pull_request PR=7 FETCH=success bash "$work/description.sh" > "$FX/out" 2>&1
  seen "$1" "$2" "$?" "$FX/out"
}
checked=$'## What I checked myself\n\nRan it and saw it pass.'
review='Review: fresh-context'
fx "nothing filled in";                                        run_description "neither field" 0
fx $'## What I checked myself\n\ndone\n\n'"$review";           run_description "the checked section says only done" 0
fx $'## What I checked myself\n\n'"$review";                   run_description "the checked section is empty" 0
fx $'## What I checked myself\n\n- [x] . . . . . . . . . . . . . . . . . . . . . done\n\n'"$review"; run_description "a long bare checked section" 0
fx "$checked"$'\n\nReview: done';                              run_description "the Review line says done" 0
fx "$checked"$'\n\nReview: '"$long";                           run_description "a 256-character Review line" 0
fx "$checked"$'\n\nReview:';                                   run_description "the Review line is empty" 0
fx "$checked"$'\n\n'"$review"$'\n\nSee #457.';                 run_description "a bare number above the highest" 0
fx "$checked"$'\n\n'"$review"; echo 'raise SystemExit("boom")' > "$FX/temp/plinth-closing/description-fields.py"
run_description "the fields script crashes" 0
fx $'not json' ; printf 'not json' > "$FX/response.json"
FX_OUT="$FX/out"; PATH="$work/bin:$PATH" RUNNER_TEMP="$FX/temp" GITHUB_STEP_SUMMARY="$FX/summary" REPO=o/r GH_TOKEN=x \
  EVENT_NAME=pull_request PR=7 FETCH=success bash "$work/description.sh" > "$FX_OUT" 2>&1
seen "GitHub's answer cannot be parsed" 1 "$?" "$FX_OUT"
fx "$checked"$'\n\nThe two fixes #65 decided.\n\n'"$review" "65"; run_description "a closing keyword in a sentence" 1
fx "$checked"$'\n\n'"$review"; echo 1 > "$FX/gh_rc";           run_description "GitHub cannot be read" 1
run_closing() { # <label> <PR>
  PATH="$work/bin:$PATH" REPO=o/r EVENT=pull_request PR="$2" GITHUB_STEP_SUMMARY="$FX/summary" bash "$root/scripts/closing-references.sh" > "$FX/out" 2>&1
  seen "$1" 1 "$?" "$FX/out"
}
fx "x" "65";       run_closing "closing-references.sh alone: an issue outside the closing line" 7
fx "x" "65"; jq '.data.repository.pullRequest.closingIssuesReferences.nodes[0].repository.nameWithOwner = "an-organisation-with-a-long-name/a-repository-with-a-long-name-too"' "$FX/response.json" > "$FX/r.json"; mv "$FX/r.json" "$FX/response.json"
run_closing "closing-references.sh alone: a long name from another repository" 7
fx "x";            run_closing "closing-references.sh alone: the number is not a number" abc
fx "x"; echo 1 > "$FX/gh_rc"; run_closing "closing-references.sh alone: GitHub cannot be read" 7
python3 - "$work/many.json" <<'PY'
import json, sys
json.dump({"data": {"repository": {"pullRequest": {"body": "x", "closingIssuesReferences": {"nodes": [], "pageInfo": {"hasNextPage": True}}}}}}, open(sys.argv[1], "w"))
PY
fx "x"; cp "$work/many.json" "$FX/response.json"; run_closing "closing-references.sh alone: more than 100 issues" 7

echo "-- ci / diff-size"
r="$work/repo"; mkdir -p "$r/tests" "$r/src"
git -C "$r" init -q -b main; git -C "$r" config user.email t@example.com; git -C "$r" config user.name t; git -C "$r" config commit.gpgsign false
printf 'def test_a():\n    assert 1\n' > "$r/tests/test_a.py"; printf 'x = 1\n' > "$r/src/m.py"
long_path="$(printf 'a%.0s' $(seq 1 120))/$(printf 'b%.0s' $(seq 1 120))/test_c.py"
mkdir -p "$r/tests/$(dirname "$long_path")"; printf 'def test_c():\n    assert 1\n' > "$r/tests/$long_path"
git -C "$r" add -A; git -C "$r" commit -qm base; base="$(git -C "$r" rev-parse HEAD)"
seq 1 500 > "$r/src/big.txt"; git -C "$r" rm -q tests/test_a.py "tests/$long_path"
git -C "$r" add -A; git -C "$r" commit -qm big; head="$(git -C "$r" rev-parse HEAD)"
measure() { # <label> <base> <head>
  (cd "$r" && env GITHUB_STEP_SUMMARY="$work/sum" MAX_LINES=400 EXCLUDE="" WORKDIR=. BASE_SHA="$2" HEAD_SHA="$3" bash -e "$work/measure.sh") > "$work/out" 2>&1
  seen "$1" 1 "$?" "$work/out"
}
measure "over the limit" "$base" "$head"
measure "the diff cannot be computed" 0000000000000000000000000000000000000000 "$head"
names() { # <label> <want exit> <base> <head>
  (cd "$r" && env GITHUB_STEP_SUMMARY="$work/sum" BODY="" BASE_SHA="$3" HEAD_SHA="$4" CHANGES_FILE="$work/changes.json" WEB=false python3 "$work/names.py") > "$work/out" 2>&1
  seen "$1" "$2" "$?" "$work/out"
}
names "a test deleted and a long path, neither named" 0 "$base" "$head"
names "git cannot compare" 1 0000000000000000000000000000000000000000 "$head"

cat > "$work/bin/fakegh.py" <<'PY'
#!/usr/bin/env python3
import json, os, sys
d = os.environ["FAKE_GH"]
args = sys.argv[1:]
path = next(a for a in reversed(args) if not a.startswith("-") and a not in (".[] | tojson", "POST"))
key = os.path.join(d, path.split("?", 1)[0].replace("/", "_"))
if os.path.exists(key + ".err"):
    sys.stderr.write(open(key + ".err").read()); sys.exit(1)
if not os.path.exists(key + ".json"):
    sys.stderr.write("gh: Not Found (HTTP 404)\n"); sys.exit(1)
data = json.load(open(key + ".json"))
if "--jq" in args:
    for item in data:
        print(json.dumps(item))
else:
    print(json.dumps(data))
PY
mkdir -p "$work/askbin"; cp "$work/bin/fakegh.py" "$work/askbin/gh"; chmod +x "$work/askbin/gh"
H=1111111111111111111111111111111111111111
ask_fx() { # <pusher login> <pusher id> <permission>
  n=$((n + 1)); FX="$work/a$n"; mkdir -p "$FX"
  printf '[{"path": "tests/test_b.py", "why": "a test file deleted"}]\n' > "$FX/changes.json"
  printf '[{"after": "%s", "actor": {"login": "%s", "id": %s}}]\n' "$H" "$1" "$2" > "$FX/repos_o_r_activity.json"
  printf '{"permission": "%s"}\n' "$3" > "$FX/repos_o_r_collaborators_$1_permission.json"
  printf '[]\n' > "$FX/repos_o_r_pulls_7_reviews.json"
}
ask() { # <label> <want exit>
  PATH="$work/askbin:$PATH" FAKE_GH="$FX" EVENT=pull_request REPO=o/r RUN_ID=99 NUMBER=7 HEAD_SHA=$H HEAD_REF=agent/x HEAD_REPO="${HEAD_REPO:-o/r}" \
    CHANGES_FILE="$FX/changes.json" GITHUB_STEP_SUMMARY="$FX/summary" python3 "$work/ask.py" > "$FX/out" 2>&1
  seen "$1" "$2" "$?" "$FX/out"
}
ask_fx agent 2 write; ask "no admin's approval" 1
wide="$(python3 -c 'import json; print(json.dumps([{"path": "tests/test_%d.py" % i, "why": "a test file deleted"} for i in range(7)]))')"
ask_fx "$(printf 'a%.0s' $(seq 1 39))" 2 write; printf '%s\n' "$wide" > "$FX/changes.json"; ask "seven rows and the longest login" 1
ask_fx boss 3 admin; ask "an admin pushed the head" 0
ask_fx "dependabot[bot]" 49699333 none; ask "Dependabot pushed the head" 0
ask_fx agent 2 write; rm "$FX/changes.json"; ask "the list of changes is missing" 1
ask_fx agent 2 write; printf 'gh: Server Error (HTTP 502) %s\n' "$long" > "$FX/repos_o_r_activity.err"; ask "the pusher cannot be read" 1

echo "-- ci / floor-check, the real checker"
rt="$work/rt"; mkdir -p "$rt/plinth/lib"
cp "$root/scripts/floor-check.py" "$root/ruleset.json" "$root/ruleset-merge.json" "$root/labels.txt" "$root/scripts/new-project.sh" "$rt/plinth/"
cp "$root/scripts/lib/shared-github.sh" "$rt/plinth/lib/"
empty="$work/empty"; mkdir -p "$empty"; git -C "$empty" init -q -b main
printf 'services:\n  - type: web\n    name: x\n    startCommand: |\n      run\n' > "$empty/render.yaml"
printf 'TOKEN=x\n' > "$empty/.env"; git -C "$empty" add -A
mkdir -p "$work/api"
floor() { # <label> <want exit>
  rm -f "$rt/floor.verdicts" "$rt/floor.txt"; : > "$work/sum"
  (cd "$empty" && env GITHUB_STEP_SUMMARY="$work/sum" RUNNER_TEMP="$rt" GH_TOKEN=x WORKDIR=. EXPECT="" GITHUB_REPOSITORY=o/r FLOOR_CHECK_API_DIR="$work/api" bash -e "$work/floor.sh") > "$work/out" 2>&1
  seen "$1" "$2" "$?" "$work/out"
}
floor "an empty repository: many FAILs" 1
report="$(grep -E '^  (FAIL|WARN) ' "$work/out")"
nfail="$(grep -c '^  FAIL ' <<<"$report")"
tail='run /plinth:floor-check, which writes the fix for each item: https://github.com/coolbress/plinth/blob/main/skills/floor-check/SKILL.md#report'
if [ "$nfail" -gt 1 ] && grep -q '^  WARN ' <<<"$report" && ! grep -vF -- "; $tail" <<<"$report" | grep -q .; then ok "every FAIL and WARN line of the report ($(wc -l <<<"$report" | tr -d ' ')) ends in the one next action and link"
else bad "a FAIL or WARN line lacks the next action and link, or the fixture has no WARN" "$(grep -vF -- "; $tail" <<<"$report")"; fi
nerr="$(grep -c '^::error::' "$work/out")"
if [ "$nerr" = 1 ] && grep -qE "^::error::floor-check: $nfail FAIL, first: " "$work/out"; then ok "several FAILs, one ::error::, with the count ($nfail)"
else bad "expected one ::error:: counting $nfail FAILs" "$(grep '^::' "$work/out")"; fi
if [ "$(grep -n '^::' "$work/out" | head -1 | cut -d: -f3)" = "" ] && grep -m1 '^::' "$work/out" | grep -q '^::error::'; then ok "the ::error:: is the step's first annotation"
else bad "the first annotation is not the ::error::" "$(grep '^::' "$work/out")"; fi
if grep -m1 '^- fail: ' "$work/sum" | grep -qF -- "; $tail"; then ok "the summary's fail line carries the next action and link"; else bad "the summary's fail line has no next action" "$(head -3 "$work/sum")"; fi
if grep -qE '^::warning::not yet confirmed: .*render\.yaml' "$work/out"; then ok "the SKIP this fixture plants is annotated"; else bad "no annotated SKIP for render.yaml" "$(grep '^::' "$work/out")"; fi
plain="$(cd "$empty" && FLOOR_CHECK_API_DIR="$work/api" python3 "$rt/plinth/floor-check.py" --root . --repo o/r --no-network 2>&1)"
if grep -E '^  (FAIL|WARN) ' <<<"$plain" | grep -q . && ! grep -qF '/plinth:floor-check, which writes' <<<"$plain"; then ok "a person's run, without --verdicts, is not told to run itself"
else bad "a run without --verdicts carries the tail" "$plain"; fi

cp "$rt/plinth/floor-check.py" "$work/real-checker.py"
fake_checker() { # the verdict lines it writes, as one Python string; exit 1
  printf 'import sys\nout = sys.argv[sys.argv.index("--verdicts") + 1]\nopen(out, "w").write(%s)\nprint("  FAIL  x")\nsys.exit(%s)\n' "$1" "$2" > "$rt/plinth/floor-check.py"
}
fake_checker "'fail: ' + 'y' * 900 + '; $tail\n' + 'fail: second; $tail\n'" 1; floor "a 900-character first FAIL" 1
if grep -qE '^::error::floor-check: 2 FAIL, first: y+\.\.\.; run /plinth' "$work/out"; then ok "a long first FAIL is cut, and the action and link survive"; else bad "the long FAIL was not cut as expected" "$(grep '^::error' "$work/out")"; fi
fake_checker "'fail: 100% of it; $tail\n'" 1; floor "a FAIL with a percent sign" 1
if grep -qF '100%25 of it' "$work/out"; then ok "% is escaped in the ::error::"; else bad "% not escaped" "$(grep '^::error' "$work/out")"; fi
fake_checker "'pass: the floor\n'" 0
rm -f "$rt/floor.verdicts"; (cd "$empty" && env GITHUB_STEP_SUMMARY="$work/sum" RUNNER_TEMP="$rt" GH_TOKEN=x WORKDIR=. EXPECT="" GITHUB_REPOSITORY=o/r bash -e "$work/floor.sh") > "$work/out" 2>&1; rc=$?
if [ "$rc" = 0 ] && ! grep -q '^::error::' "$work/out"; then ok "no FAIL: no ::error::, the step passes"; else bad "no FAIL: exit $rc or an ::error::" "$(cat "$work/out")"; fi
printf 'import sys\nsys.exit(3)\n' > "$rt/plinth/floor-check.py"; floor "a checker that wrote no verdicts: its exit stands" 3
cp "$work/real-checker.py" "$rt/plinth/floor-check.py"
long_skip="$(python3 - "$rt/plinth/floor-check.py" <<'PY'
import importlib.util, io, contextlib, sys
s = importlib.util.spec_from_file_location("fc", sys.argv[1]); m = importlib.util.module_from_spec(s)
sys.modules["fc"] = m; s.loader.exec_module(m)
with contextlib.redirect_stdout(io.StringIO()):
    m.result("SKIP", "z" * 900)
print(m.verdicts[-1])
PY
)"
printf '%s\t::warning::%s\n' "a 900-character SKIP" "$long_skip" >> "$annotations"

echo "-- every annotation read: what failed, one next action, a link that exists, at most 300 characters"
python3 - "$root" "$annotations" <<'PY'
import re, sys
root, path = sys.argv[1:3]
sys.path.insert(0, root)
ACTION = re.compile(r"[.;:,]\s+(?:remove|rewrite|reword|split|re-run|run|name|edit|write|ask|update|read)\b", re.IGNORECASE)
LINK = re.compile(r"https://github\.com/coolbress/plinth/blob/main/([^\s#]+)#([\w-]+)")
def anchors(file):
    out = set()
    for line in open(f"{root}/{file}", encoding="utf-8"):
        m = re.match(r"#{1,6}\s+(.*?)\s*$", line)
        if m:
            s = re.sub(r"[^\w\- ]", "", m.group(1).lower())
            out.add(s.replace(" ", "-"))
    return out
bad = n = 0
for row in open(path, encoding="utf-8"):
    label, line = row.rstrip("\n").split("\t", 1)
    n += 1
    msg = re.sub(r"^::(error|warning)::", "", line).replace("%25", "%")
    why = []
    links = LINK.findall(msg)
    if len(msg) > 300:
        why.append(f"{len(msg)} characters")
    if not links:
        why.append("no link to a page with an anchor")
    else:
        for file, a in links:
            try:
                if a not in anchors(file):
                    why.append(f"no heading for #{a} in {file}")
            except OSError:
                why.append(f"no file {file}")
    if not ACTION.search(msg):
        why.append("no next action")
    if why:
        bad += 1
        print(f"  FAIL  {label}: {', '.join(why)}\n        | {msg[:400]}")
print(f"  {'PASS' if not bad else 'FAIL'}  {n - bad} of {n} annotations hold")
sys.exit(1 if bad or not n else 0)
PY
[ $? = 0 ] && pass=$((pass+1)) || fail=$((fail+1))

echo "-- the literals, for what no fixture reaches: each ::error:: and ::warning:: in the source carries a link"
python3 - "$wf" "$root/scripts/closing-references.sh" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
got = []
for job in ("pr-title", "diff-size", "floor-check"):
    start = lines.index(f"  {job}:")
    end = next((i for i in range(start + 1, len(lines)) if re.match(r"^  [a-z]", lines[i])), len(lines))
    got += [(f"python-ci.yml:{i + 1}", lines[i]) for i in range(start, end)]
got += [(f"closing-references.sh:{i + 1}", l) for i, l in enumerate(open(sys.argv[2], encoding="utf-8").read().split("\n"))]
bad = n = 0
for where, l in got:
    if l.lstrip().startswith("#") or not re.search(r"::(error|warning)::", l):
        continue
    if "more not yet confirmed lines" in l or "say()" in l or '"::error::$e"' in l or '"::error::$lead$first$tail"' in l:  # built above: the fixtures read them
        continue
    n += 1
    if "https://github.com/coolbress/plinth/blob/main/" not in l and "{HOW}" not in l and "$HOW" not in l:
        bad += 1
        print(f"  FAIL  {where}: no link\n        | {l.strip()[:200]}")
print(f"  {'PASS' if not bad else 'FAIL'}  {n - bad} of {n} literal annotations carry a link")
sys.exit(1 if bad or not n else 0)
PY
[ $? = 0 ] && pass=$((pass+1)) || fail=$((fail+1))

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
