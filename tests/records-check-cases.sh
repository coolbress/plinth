#!/usr/bin/env bash
# The records checker's verdicts on fixtures, offline (#977): each planted
# defect is named, and none of the records a by-hand audit of a real project
# wrongly called missing is reported. GraphQL and REST answers come from
# RECORDS_CHECK_API_DIR; nothing here reads the network.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root/scripts/records-check.py"
work="$(mktemp -d)" || { echo "records-check-cases: could not make a temp folder" >&2; exit 1; }; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
has()  { if grep -qF -- "$2" <<<"$out"; then ok "$1"; else bad "$1: no line with '$2'"; fi; }
hasnt() { if grep -qF -- "$2" <<<"$out"; then bad "$1: a line has '$2': $(grep -F -- "$2" <<<"$out" | head -2)"; else ok "$1"; fi; }

api="$work/api"; mkdir -p "$api/graphql" "$api/repos/o/r/issues" "$api/repos/o/.github/contents/.github"
U=https://github.com/o/r

# ---- The records: two pages of issues, one of pull requests.
python3 - "$api" <<'PY'
import json, sys
api = sys.argv[1]
U = "https://github.com/o/r"
def issue(n, labels, body, state="CLOSED", reason="COMPLETED", total=None):
    return {"number": n, "url": f"{U}/issues/{n}", "state": state, "stateReason": reason, "body": body,
            "labels": {"totalCount": total if total is not None else len(labels), "nodes": [{"name": x} for x in labels]}}
page1 = [
    issue(1, ["bug"], "## What happened\n\nit broke\n\n## Result\n\nfixed\n"),
    issue(2, ["task"], "## What to build\n\nx\n"),
    # An issue form renders its fields as level-3 headings (nexusbt's false alarm).
    issue(3, ["task"], "### What to build\n\nx\n\n### Acceptance criteria\n\n- [X] one\n- [ ] two\n\n### Outcome\n\ndone\n"),
    issue(4, ["wayfinder:research"], "## Question\n\nq\n\n## Decision\n\nd\n"),
    issue(5, ["task"], "## What to build\n\nx\n\n## Decision\n\nd\n"),
    # An ending heading with more words after it is still that heading.
    issue(14, ["task"], "## What to build\n\nx\n\n## **Outcome**: completed\n\ndone\n"),
    issue(6, ["task"], "## What to build\n\nx\n", reason="NOT_PLANNED"),
]
page2 = [
    # Labels cut at their page size: the kind is not known.
    issue(7, [f"l{i}" for i in range(20)], "no ending\n", total=25),
    issue(8, ["task"], "See #2, `#9999` and x/y#3.\n\n```\n#8888 /Users/carol/in-a-fence\n```\n"
                       "Ran in /Users/alice/work and /home/runner/work and /home/ubuntu/x and /Users/<you>/x, on github.com/home/page.\n"
                       "Also v1.2/x#3, #500, #9, #10, x/y#4, gone/repo#1, color &#39; and [link](https://github.com/o/r/pull/77#issuecomment-1).\n"
                       "GitHub staff say so in [community discussion #121836](https://github.com/orgs/community/discussions/121836).\n"
                       # Four spaces after a blank line is an indented code block; in a list, the item's next paragraph.
                       "\nExample:\n\n    See #66666\n\n- a list item\n\n    whose second paragraph names #600\n",
          state="OPEN", reason=None),
    issue(11, [], "a" * 59000, state="OPEN", reason=None),
    # Three UTF-8 bytes per character: near the limit in bytes only.
    issue(12, [], "한" * 20000, state="OPEN", reason=None),
    # Dated decisions while open are not the ending the same sentence names.
    issue(13, ["task"], "## What to build\n\nx\n\n## Decisions\n\n2026-11-19: y\n"),
]
pulls = [
    {"number": 20, "url": f"{U}/pull/20", "state": "MERGED", "merged": True,
     "body": "What\n\nAssisted-by: Claude Code:claude-opus-5-5\n", "mergeCommit": {"message": "x (#20)"}},
    {"number": 21, "url": f"{U}/pull/21", "state": "MERGED", "merged": True,
     "body": "The lock file was regenerated with uv.\n", "mergeCommit": {"message": "y (#21)\n\nAssisted-by: Claude:claude-x\n"}},
    {"number": 22, "url": f"{U}/pull/22", "state": "MERGED", "merged": True,
     "body": "\U0001F916 Generated with Claude Code\n", "mergeCommit": {"message": "z (#22)"}},
    {"number": 23, "url": f"{U}/pull/23", "state": "CLOSED", "merged": False, "body": "nothing", "mergeCommit": None},
]
def conn(field, nodes, nxt):
    return {"data": {"repository": {field: {"pageInfo": {"hasNextPage": nxt, "endCursor": "c1" if nxt else None},
                                            "nodes": nodes}}}}
w = lambda p, d: open(f"{api}/{p}", "w").write(json.dumps(d))
w("graphql/issues-1.json", conn("issues", page1, True))
w("graphql/issues-2.json", conn("issues", page2, False))
w("graphql/pulls-1.json", conn("pullRequests", pulls, False))
# A page with data and an error for one record, that record null.
part = conn("pullRequests", pulls + [None], False)
part["errors"] = [{"type": "INTERNAL", "path": ["repository", "pullRequests", "nodes", 4], "message": "Something went wrong."}]
w("pulls-partial.json", part)
# A page whose whole list of records failed: nothing to count, so not read.
whole = conn("pullRequests", None, False)
whole["errors"] = [{"type": "INTERNAL", "path": ["repository", "pullRequests", "nodes"], "message": "Something went wrong."}]
w("pulls-whole.json", whole)
nf = lambda f: {"type": "NOT_FOUND", "path": ["repository", f], "message": f"Could not resolve to a {f}."}
# Data and NOT_FOUND errors in one answer: each field read on its own.
w("graphql/refs-o-r-1.json", {"data": {"repository": {
    "i": {"nodes": [{"number": 12}]}, "p": {"nodes": [{"number": 23}]}, "dd": {"nodes": [{"number": 10}]},
    "n9": None, "d9": None, "n10": None, "d10": {"number": 10}, "n500": None, "d500": None, "n600": None, "d600": None}},
    "errors": [nf(f) for f in ("n9", "d9", "n10", "n500", "d500", "n600", "d600")]})
w("graphql/refs-x-y-1.json", {"data": {"repository": {
    "i": {"nodes": [{"number": 100}]}, "p": {"nodes": []}, "dd": {"nodes": []},
    "n3": {"__typename": "Issue"}, "d3": None, "n4": None, "d4": None}},
    "errors": [nf(f) for f in ("d3", "n4", "d4")]})
# The same answer with an error, not NOT_FOUND, for one reference's field.
err = json.loads(json.dumps(json.load(open(f"{api}/graphql/refs-x-y-1.json"))))
err["errors"] = [nf("d3"), nf("d4"), {"type": "INTERNAL", "path": ["repository", "n4"], "message": "Something went wrong."}]
w("refs-x-y-error.json", err)
w("graphql/refs-gone-repo-1.json", {"data": {"repository": None},
    "errors": [{"type": "NOT_FOUND", "path": ["repository"], "message": "Could not resolve to a Repository."}]})
w("repos/o/r/issues/9.json", {"__status": 410})
PY

# ---- Conventions: plinth's shape, another ending heading, and none.
plinthlike="$work/plinthlike"; mkdir -p "$plinthlike/.github/ISSUE_TEMPLATE" "$plinthlike/docs/agents"
cat >"$plinthlike/AGENTS.md" <<'MD'
# Agents

- Closing an issue writes its ending into the body:
  `## Outcome`, saying what was verified.
- Decisions taken while open go under `## Decisions`, dated, and the ending under `## Outcome`.
MD
cat >"$plinthlike/CONTRIBUTING.md" <<'MD'
# Contributing

A commit made with AI carries the trailer `Assisted-by: <agent>:<model>`.
MD
cat >"$plinthlike/.github/ISSUE_TEMPLATE/task.yml" <<'YML'
name: Task
body:
  - type: textarea
    attributes:
      label: Acceptance criteria
YML
other="$work/other"; mkdir -p "$other/docs/agents"
printf '# Issue tracker\n\nA finished task ends in `## Result`, which says what was verified.\n' >"$other/docs/agents/issue-tracker.md"
none="$work/none"; mkdir -p "$none"

run() { out="$(RECORDS_CHECK_API_DIR="$api" python3 "$checker" --repo o/r "$@" 2>&1)"; rc=$?; }

# ---- plinth's shape.
run --root "$plinthlike"
[ "$rc" = 0 ] && ok "a run that read everything exits 0, whatever it found" || bad "exit $rc: $out"
if grep -vE '^  (PASS|WARN|INFO|SKIP)  |^-- ' <<<"$out" | grep -q .; then
  bad "a line is not PASS, WARN, INFO or SKIP: $(grep -vE '^  (PASS|WARN|INFO|SKIP)  |^-- ' <<<"$out" | head -2)"
else ok "every line is PASS, WARN, INFO or SKIP, and the summary"; fi
hasnt "never FAIL" "FAIL"
has "both pages of issues are read" "o/r: 12 issues and 4 pull requests read"
has "a completed bug whose only ending is another heading is named" "ending: $U/issues/1 closed completed"
has "a completed task with no ending is named, with the file" "ending: $U/issues/2 closed completed with no ending section (\`outcome\`, from AGENTS.md)"
has "a heading the sentence names before the ending is not an ending" "ending: $U/issues/13 closed completed"
hasnt "an issue form's ### Outcome is an ending" "$U/issues/3 closed"
hasnt "a record ending in Decision is excepted" "$U/issues/5 "
hasnt "an ending heading with more words after it is an ending" "$U/issues/14 "
hasnt "a record with no kind label is not judged" "$U/issues/4 "
hasnt "an issue closed not planned is not judged" "$U/issues/6 "
has "labels cut at their page size are a SKIP" "SKIP  ending: $U/issues/7 not verified: its labels were cut at 20"
has "a deleted issue is named (410)" "ref: #9 was deleted (410), referenced in $U/issues/8"
has "a number above the highest is named (404)" "ref: #500 resolves to nothing (404, above o/r's highest number, 23)"
hasnt "a discussion number resolves" "#10 "
hasnt "#N in inline code is not a reference" "9999"
hasnt "#N in a code fence is not a reference" "8888"
hasnt "owner/repo#N that resolves is not named" "x/y#3"
hasnt "a path whose first part cannot be an owner is not a reference" "v1.2/x"
has "owner/repo#N not found at or below that repository's highest number is a SKIP" "SKIP  x/y#4 not verified: status 404 at or below the highest number, 100, referenced in $U/issues/8"
has "a repository that cannot be read is a SKIP for its references" "SKIP  gone/repo#1 not verified: gone/repo could not be read (NOT_FOUND), referenced in $U/issues/8"
hasnt "an HTML entity is not a reference" "#39"
hasnt "a link's anchor is not a reference" "#77"
hasnt "a link's text is not a reference" "121836"
hasnt "#N in an indented code block is not a reference" "66666"
has "an indented list paragraph is text, its #N read" "ref: #600 resolves to nothing"
has "a home path is named by line and form" "home-path: $U/issues/8 line 6: a home path (/Users/<name>)"
has "a home path in a code fence is public too" "home-path: $U/issues/8 line 4: a home path (/Users/<name>)"
hasnt "the home path line never repeats what matched" "alice"
hasnt "nor the one in a code fence" "carol"
hasnt "the runner's home, a placeholder and a URL path are not home paths" "(/home/<name>)"
has "a body near the limit in characters is named" "body-size: $U/issues/11: 59000 characters, 59000 UTF-8 bytes"
has "a body near the limit in UTF-8 bytes is named" "body-size: $U/issues/12: 20000 characters, 60000 UTF-8 bytes"
hasnt "an agent name with a space is a trailer" "pull/20"
hasnt "a trailer only in the squash commit message counts" "pull/21"
has "a merged pull request with no trailer is an INFO, not a violation" "INFO  trailer: $U/pull/22: no trailer"
hasnt "a closed unmerged pull request is not judged" "pull/23"
has "unticked criteria are for a person to read, with the file" "INFO  for a person to read: 1 completed issues leave acceptance criteria unticked (heading from .github/ISSUE_TEMPLATE/task.yml)"
has "the unticked criterion's line is listed; [X] is ticked" "INFO    $U/issues/3 line 8"
has "the last line counts per rule and not verified" "-- ref 3, home-path 2, body-size 2, ending 3, trailer 1; for a person to read: criteria 1; 0 rules not checked; 3 not verified"
hasnt "nothing says missing" "missing"

# ---- Another ending heading: judged against it, not against plinth's.
run --root "$other"
hasnt "an issue-tracker.md naming another heading reports no missing Outcome" "$U/issues/1 "
has "that heading is what the line names, with the file" "ending: $U/issues/2 closed completed with no ending section (\`result\`, from docs/agents/issue-tracker.md)"
has "no trailer convention read: not checked" "SKIP  trailer: not checked: convention not read"

# ---- No convention files.
run --root "$none"
has "the same issues with no convention files: not checked" "SKIP  ending: not checked: convention not read"
has "no criteria heading read: not checked" "SKIP  criteria: not checked: convention not read"
hasnt "nothing says missing without conventions" "missing"
hasnt "no convention item is judged without conventions" "closed completed with no ending"
has "rules not checked are counted apart from records not verified" "; 3 rules not checked; 2 not verified"
has "the facts are judged without conventions" "ref: #500 resolves to nothing"

# ---- The owner's shared issue forms, when the repository has none of its own.
form="$(printf 'name: Task\nbody:\n  - attributes:\n      label: Acceptance criteria\n' | base64 | tr -d '\n')"
printf '[{"name":"task.yml"},{"name":"config.yml"}]' >"$api/repos/o/.github/contents/.github/ISSUE_TEMPLATE.json"
mkdir -p "$api/repos/o/.github/contents/.github/ISSUE_TEMPLATE"
printf '{"content":"%s"}' "$form" >"$api/repos/o/.github/contents/.github/ISSUE_TEMPLATE/task.yml.json"
run --root "$none"
has "the owner's shared form is a convention, named as such" "(heading from o/.github: .github/ISSUE_TEMPLATE/task.yml)"
rm -r "$api/repos/o/.github/contents/.github/ISSUE_TEMPLATE" "$api/repos/o/.github/contents/.github/ISSUE_TEMPLATE.json"

# ---- GitLab: one line, nothing judged.
gl="$work/gl"; mkdir -p "$gl"; printf 'host: gitlab\n' >"$gl/.copier-answers.yml"
run --root "$gl"
[ "$rc" = 0 ] && [ "$out" = "  INFO  GitLab: not read" ] && ok "a GitLab checkout prints one line, GitLab: not read" || bad "GitLab: rc $rc: $out"

# ---- One reference's field answered with an error: not verified, and where it was read.
cp "$api/graphql/refs-x-y-1.json" "$work/refs-x-y-1.json"; cp "$api/refs-x-y-error.json" "$api/graphql/refs-x-y-1.json"
run --root "$plinthlike"
has "a reference GitHub answered an error for is a SKIP, with where it was read" "SKIP  x/y#4 not verified: GitHub answered an error for it, referenced in $U/issues/8"
cp "$work/refs-x-y-1.json" "$api/graphql/refs-x-y-1.json"

# ---- A record GitHub answered with null and an error: not verified, never dropped.
mv "$api/graphql/pulls-1.json" "$work/pulls-1.json"; cp "$api/pulls-partial.json" "$api/graphql/pulls-1.json"
run --root "$plinthlike"
[ "$rc" = 0 ] && ok "a page with one record's error still runs to the end" || bad "partial page: exit $rc: $out"
has "the four records read are counted" "o/r: 12 issues and 4 pull requests read"
has "the record with an error is a SKIP, named" "SKIP  pull request record 5 on page 1 not verified: GitHub answered an error for it (Something went wrong.)"
has "and counted as not verified" "; 0 rules not checked; 4 not verified"
cp "$api/pulls-whole.json" "$api/graphql/pulls-1.json"
run --root "$plinthlike"
[ "$rc" = 2 ] && grep -q "could not run: the pulls of o/r could not be read (page 1: Something went wrong.)" <<<"$out" \
  && ok "a page whose whole list failed: exit 2, not an empty page" || bad "whole list failed: exit $rc: $out"
mv "$work/pulls-1.json" "$api/graphql/pulls-1.json"

# ---- Could not run: non-zero, and only then.
out="$(RECORDS_CHECK_API_DIR="$api" python3 "$checker" --root "$none" 2>&1)"; rc=$?
[ "$rc" = 2 ] && ok "no repository named: exit 2" || bad "no --repo: exit $rc: $out"
mv "$api/graphql/issues-2.json" "$work/issues-2.json"
run --root "$none"
[ "$rc" = 2 ] && grep -q "could not run: the issues of o/r could not be read (page 2" <<<"$out" && ok "an unread page of issues: exit 2, not a partial count" || bad "unread page: exit $rc: $out"
mv "$work/issues-2.json" "$api/graphql/issues-2.json"

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
