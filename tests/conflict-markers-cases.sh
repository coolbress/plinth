#!/usr/bin/env bash
# What scripts/conflict-markers.py, a step of `ci / diff-size` in python-ci.yml
# and of plinth's own `ci / docs`, says about a pull request's diff (#936): a
# line the diff adds that is a merge conflict marker fails, naming the file and
# the line; a marker the base already has does not.
#
# Each case is a throwaway git repository: a base commit on main, then a branch
# commit, and the script run on main...branch as the workflow runs it.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/conflict-markers.py"

work="$(mktemp -d "${TMPDIR:-/tmp}/conflict-markers.XXXXXX")" || { echo "conflict-markers-cases: could not make a temp folder" >&2; exit 1; }; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        | /'; }

g() { git -C "$repo" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@" >/dev/null 2>&1; }

# The markers are built here, so this file carries none at the start of a line.
lt="$(printf '<%.0s' 1 2 3 4 5 6 7)"; eq="$(printf '=%.0s' 1 2 3 4 5 6 7)"
gt="$(printf '>%.0s' 1 2 3 4 5 6 7)"; bar="$(printf '|%.0s' 1 2 3 4 5 6 7)"

# fresh <file> <base content>: a repository whose main holds <file>, and a
# branch `pr` checked out on it.
n=0
fresh() {
  n=$((n + 1)); repo="$work/$n"; mkdir -p "$repo"; g init -q -b main
  mkdir -p "$repo/$(dirname "$1")"; printf '%s' "$2" >"$repo/$1"
  g add -A; g commit -qm base; g checkout -qb pr
}
# commit <file> <content> on the branch.
commit() { mkdir -p "$repo/$(dirname "$1")"; printf '%s' "$2" >"$repo/$1"; g add -A; g commit -qm change; }
run() { out="$(cd "$repo" && python3 "$script" main...pr 2>&1)"; rc=$?; }

# The three markers a two-way merge leaves, kept in CHANGELOG.md as #237 did.
fresh CHANGELOG.md $'# Changelog\n\n## [Unreleased]\n\n- one.\n'
commit CHANGELOG.md "# Changelog

## [Unreleased]

$lt HEAD
- mine.
$eq
- theirs.
$gt origin/main
- one.
"
run
if [ "$rc" = 1 ] && grep -q "CHANGELOG.md:5: $lt HEAD" <<<"$out" && grep -q "CHANGELOG.md:7: $eq" <<<"$out" \
  && grep -q "CHANGELOG.md:9: $gt origin/main" <<<"$out" && grep -q '::error file=CHANGELOG.md,line=5::' <<<"$out"; then
  ok "three markers kept in CHANGELOG.md fail, each named with its file and line"
else bad "three markers kept in CHANGELOG.md fail, each named with its file and line" "rc=$rc"$'\n'"$out"; fi

# A marker the base already has: the pull request changes another line of the
# same file and adds none, so it passes.
fresh notes.md "# Notes

$lt HEAD
old
$eq
older
$gt main
"
commit notes.md "# Notes, edited

$lt HEAD
old
$eq
older
$gt main
"
run
if [ "$rc" = 0 ] && grep -q '^OK: ' <<<"$out"; then ok "a marker already in the base passes; only added lines are read"
else bad "a marker already in the base passes; only added lines are read" "rc=$rc"$'\n'"$out"; fi

# A fenced code block a document adds is still read: the fences say nothing
# about whether a conflict left the marker there.
fresh docs/a.md $'# A\n'
commit docs/a.md "# A

\`\`\`text
$lt HEAD
x
$eq
y
$gt topic
\`\`\`
"
run
if [ "$rc" = 1 ] && grep -q "docs/a.md:4: $lt HEAD" <<<"$out" && grep -q "docs/a.md:6: $eq" <<<"$out"; then
  ok "a marker inside an added fenced code block fails too"
else bad "a marker inside an added fenced code block fails too" "rc=$rc"$'\n'"$out"; fi

# Seven equals signs alone are a Markdown heading's underline: with no opening
# or closing marker added to the same file, they pass. Indented or inside a
# code span, a marker is text.
fresh README.md $'# R\n'
commit README.md "Title
$eq

Shown as \`$lt HEAD\`, or indented:

    $gt main
"
run
if [ "$rc" = 0 ]; then ok "a heading underline, a code span and an indented marker pass"
else bad "a heading underline, a code span and an indented marker pass" "rc=$rc"$'\n'"$out"; fi

# diff3's base marker, a bare marker with no label, a carriage return, and a
# path with a space; one file's markers do not make another file's
# underline fail.
fresh 'src/my file.py' $'x = 1\n'
cr=$'\r'
commit 'src/my file.py' "x = 1
$lt
y = 2
$bar base
y = 1
$eq$cr
y = 3
$gt theirs$cr
"
printf 'Title\n%s\n' "$eq" >"$repo/other.md"; g add -A; g commit -qm other
run
if [ "$rc" = 1 ] && grep -q "src/my file.py:2: $lt\$" <<<"$out" && grep -q "src/my file.py:4: $bar base" <<<"$out" \
  && grep -q "src/my file.py:6: $eq\$" <<<"$out" && grep -q "src/my file.py:8: $gt theirs\$" <<<"$out" \
  && ! grep -q 'other.md' <<<"$out" && grep -q '::error file=src/my file.py,line=2::' <<<"$out"; then
  ok "diff3's marker, a bare marker, CRLF and a path with a space; another file's underline passes"
else bad "diff3's marker, a bare marker, CRLF and a path with a space; another file's underline passes" "rc=$rc"$'\n'"$out"; fi

# An added line that starts with `++ ` is a line, not a file header: the
# marker after it is still named in the right file.
fresh a.txt $'a\n'
commit a.txt "a
++ b/elsewhere
$gt main
"
run
if [ "$rc" = 1 ] && grep -q "^a.txt:3: $gt main" <<<"$out"; then ok "an added line starting with ++ does not change the file"
else bad "an added line starting with ++ does not change the file" "rc=$rc"$'\n'"$out"; fi

# More than nine: nine annotations, then one with the count; every line logged.
fresh many.txt $'a\n'
body=""; for _ in 1 2 3 4 5 6; do body="$body$lt HEAD"$'\n'"$gt main"$'\n'; done
commit many.txt "$body"
run
if [ "$rc" = 1 ] && [ "$(grep -c '^many.txt:' <<<"$out")" = 12 ] && [ "$(grep -c '^::error file=' <<<"$out")" = 9 ] \
  && grep -q '^::error::3 more conflict marker lines are in the log' <<<"$out"; then
  ok "twelve markers: twelve log lines, nine annotations and one count"
else bad "twelve markers: twelve log lines, nine annotations and one count" "rc=$rc"$'\n'"$out"; fi

# A path git still quotes under core.quotePath=false (it holds a double quote)
# and that also holds non-ASCII text, which stays raw inside the quotes.
fresh 'docs/한"x.md' $'# x\n'
commit 'docs/한"x.md' "# x
$lt HEAD
$gt main
"
run
if [ "$rc" = 1 ] && grep -q "^docs/한\"x.md:2: $lt HEAD" <<<"$out"; then ok "a quoted path with non-ASCII text is named as it is"
else bad "a quoted path with non-ASCII text is named as it is" "rc=$rc"$'\n'"$out"; fi

# A deleted file and a revision git does not know.
fresh gone.txt "$lt HEAD"$'\n'
g rm -q gone.txt; g commit -qm gone
run
if [ "$rc" = 0 ]; then ok "a deleted file adds no line"; else bad "a deleted file adds no line" "rc=$rc"$'\n'"$out"; fi
out="$(cd "$repo" && python3 "$script" main...no-such-branch 2>&1)"; rc=$?
if [ "$rc" = 2 ] && grep -q '::error::git could not produce the diff' <<<"$out"; then ok "an unknown revision exits 2, not a pass"
else bad "an unknown revision exits 2, not a pass" "rc=$rc"$'\n'"$out"; fi

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
