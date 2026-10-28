#!/usr/bin/env bash
# The guards of `scripts/make-release.sh`. No network: the script runs in a
# throwaway clone of this repository's release files with a bare `origin`,
# and `gh` is mocked; the verdict is what changed and what `gh` was asked.
#
# One property: no release goes out without its *why*, the template tag it
# was tested with, and a green `e2e` run on the very commit being tagged. Run 1
# writes the why into the version's CHANGELOG.md section; run 2 publishes that
# section of the merged main and reads nothing else.
# Everything else (tag format, both manifests moving together, main only, no
# duplicate) is a wall around that property. One more input of run 1's why
# (#700): when the template pin moved and the move touches what a new
# project's agent reads, the eval suite's table or the reason it was not run.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

cat > "$work/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -u
printf 'gh %s\n' "$*" >> "$GH_LOG"
case "$*" in
  "release view"*)   case "${VIEW_RC:-1}" in 0) ;; 1) echo "release not found" >&2 ;; *) echo "error connecting to api.github.com" >&2 ;; esac
                     exit "${VIEW_RC:-1}" ;;   # default: no release yet, as gh reports it
  # The Release text arrives on stdin (`--notes-file -`); keep it to compare.
  "release create"*) case " $* " in *" --notes-file - "*) cat > "$GH_LOG.body" ;; esac
                     exit 0 ;;
  # The template's diff between two tags, as the script's --jq prints it: the
  # file count, then one name per line.
  "api repos/"*"/compare/"*)
    [ "${COMPARE_RC:-0}" = 0 ] || { echo "error connecting to api.github.com" >&2; exit "$COMPARE_RC"; }
    printf '%s\n' "${COMPARE_OUT:-0}"
    exit 0 ;;
  # The e2e runs on one commit. GitHub filters on head_sha server-side; the
  # mock does the same, so a green run on another commit is simply not listed.
  "api -X GET repos/"*"/actions/workflows/e2e.yml/runs "*)
    [ "${E2E_RC:-0}" = 0 ] || { echo "error connecting to api.github.com" >&2; exit "$E2E_RC"; }
    all="$*"; sha="${all#*head_sha=}"; sha="${sha%% *}"
    [ "$sha" = "${E2E_SHA:-}" ] && [ -n "${E2E_RUNS:-}" ] && printf '%s\n' "$E2E_RUNS"
    exit 0 ;;
esac
exit 0
MOCK
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"

# A repository with exactly the files the release touches or reads, and a bare
# origin so that pushes and fetches are real.
repo="$work/repo"; origin="$work/origin.git"
mkdir -p "$repo/.claude-plugin" "$repo/scripts"
cp "$root"/.claude-plugin/plugin.json "$root"/.claude-plugin/marketplace.json "$repo/.claude-plugin/"
cp "$root"/CHANGELOG.md "$repo/"
cp "$root"/scripts/make-release.sh "$root"/scripts/new-project.sh "$repo/scripts/"
# One known entry under Unreleased, whatever the real file has there today.
python3 - "$repo/CHANGELOG.md" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
p.write_text(re.sub(r"(?ms)^## \[Unreleased\]\n.*?^(?=## \[)",
                    "## [Unreleased]\n\n### Fixed\n\n- An entry waiting for the release.\n\n", p.read_text(), count=1))
PY
# The pin the release before was tested with, whatever the real pin is today:
# a pull request that raises the pin would otherwise read as a moved pin here.
tested_ref="$(sed -nE 's/^tested with plinth-template (v[^ ]+)$/\1/p' "$repo/CHANGELOG.md" | head -1)"
[ -n "$tested_ref" ] || { echo "no 'tested with plinth-template <tag>' line in CHANGELOG.md" >&2; exit 1; }
sed -i.bak -E "s/^template_ref=\"[^\"]+\"$/template_ref=\"$tested_ref\"/" "$repo/scripts/new-project.sh"; rm "$repo/scripts/new-project.sh.bak"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -C "$repo" "$@"; }
g init -q -b main; g add -A; g commit -q -m "fixture"
git clone -q --bare "$repo" "$origin"
g remote add origin "$origin"; g fetch -q origin; g branch -q -u origin/main

current="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$repo/.claude-plugin/plugin.json")"
next="${current%%.*}.$(( $(cut -d. -f2 <<<"$current") + 1 )).0"
base="$(sed -nE 's|^\[Unreleased\]: (.+)/compare/v[^.]+\.[^.]+\.[^.]+\.\.\.HEAD$|\1|p' "$repo/CHANGELOG.md")"
template="$(sed -nE 's/^template_repo="[^"]*\/([^"]+)"$/\1/p' "$repo/scripts/new-project.sh") $(sed -nE 's/^template_ref="([^"]+)"$/\1/p' "$repo/scripts/new-project.sh")"

pass=0; fail=0
check() { # <name> <expected ok|no> <actual exit code>
  if { [ "$2" = ok ] && [ "$3" = 0 ]; } || { [ "$2" = no ] && [ "$3" != 0 ]; }
  then pass=$((pass+1)); echo "  PASS  $1"
  else fail=$((fail+1)); echo "  FAIL  $1 (exit $3, expected $2)"; fi
}
is() { # <name> <condition...>
  local name="$1"; shift
  if "$@"; then pass=$((pass+1)); echo "  PASS  $name"
  else fail=$((fail+1)); echo "  FAIL  $name"; fi
}
not() { ! "$@"; }
version_in() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("version"))' "$repo/.claude-plugin/$1"; }
# The lines under a heading, to the next `## [` heading or the link references.
section_of() {
  awk -v h="## [$1]" 'index($0, h) == 1 { on = 1; next }
    on && (index($0, "## [") == 1 || index($0, "[Unreleased]: ") == 1) { exit }
    on' "$repo/CHANGELOG.md" | sed -e '/./,$!d'
}
says() { grep -qF -- "$1" "$work/out"; }
untouched() { [ -z "$(g status --porcelain --untracked-files=no)" ] && [ "$(g rev-parse --abbrev-ref HEAD)" = main ]; }

# Numbered, not $RANDOM: a reused name would hand one case another's Release text.
n=0
run_in() { local dir="$1"; shift; n=$((n+1)); export GH_LOG="$work/log.$n"; : > "$GH_LOG"; (cd "$dir" && "$dir/scripts/make-release.sh" "$@") >"$work/out" 2>&1; }
run() { run_in "$repo" "$@"; }

printf '\nA reason a person wrote.\n\ntested with %s\n\n' "$template" > "$work/why.md"
printf 'tested with %s\n' "$template" > "$work/only-tested.md"
printf -- '---\n\ntested with %s\n' "$template" > "$work/markup-only.md"
printf '## Why\n\ntested with %s\n' "$template" > "$work/heading-only.md"
printf 'A reason.\n' > "$work/no-tested.md"
printf 'A reason.\n\ntested with %s v0.0.0-not-the-pin\n' "${template%% *}" > "$work/wrong-tested.md"
printf 'A reason.\n\nnot tested with %s (failed)\n' "$template" > "$work/padded-tested.md"
printf 'A reason.\n\n## More\n\ntested with %s\n' "$template" > "$work/h2.md"
printf 'A reason.\n\n### Fixed\n\ntested with %s\n' "$template" > "$work/h3.md"
printf 'A reason.\n\n   ## More\n\ntested with %s\n' "$template" > "$work/h2-indented.md"
: > "$work/empty.md"
# What run 1 makes of why.md and the fixture's Unreleased entry, and what run 2 publishes.
expected="$(printf 'A reason a person wrote.\n\ntested with %s\n\n### Fixed\n\n- An entry waiting for the release.' "$template")"

echo "-- tag format"
run "$next" "$work/why.md";        check "a tag without the v prefix is refused"       no $?
run "v${next%.*}" "$work/why.md";  check "a tag that is not vX.Y.Z is refused"         no $?
is "nothing changed" untouched

echo "-- the why-file, run 1's input"
run "v$next";                         check "run 1 without a why-file is refused"                   no $?
run "v$next" "$work/missing.md";      check "a missing why-file is refused"                         no $?
run "v$next" "$work/empty.md";        check "an empty why-file is refused"                          no $?
run "v$next" "$work/no-tested.md";    check "a why without the tested-template line is refused"     no $?
run "v$next" "$work/wrong-tested.md"; check "a tested-template line naming another tag is refused"  no $?
run "v$next" "$work/padded-tested.md"; check "the tested-template line must be the whole line"  no $?
run "v$next" "$work/only-tested.md";  check "the tested-template line alone is not a why"           no $?
run "v$next" "$work/markup-only.md";  check "a rule over the tested line is not a why either"       no $?
run "v$next" "$work/heading-only.md"; check "a heading over the tested line is not a why either"    no $?
# The why goes under the version heading as prose; a heading in it would cut the section.
run "v$next" "$work/h2.md";           check "a why with a '## ' line is refused"                    no $?
is "  and the refusal names the heading" says "heading"
run "v$next" "$work/h3.md";           check "a why with a '### ' line is refused"                   no $?
is "  and the refusal names the heading" says "heading"
run "v$next" "$work/h2-indented.md";  check "a heading indented by three spaces is a heading too"   no $?
is "nothing changed" untouched
is "gh release create was never called" not grep -q "release create" "$work"/log.*

echo "-- where it runs"
echo x >> "$repo/CHANGELOG.md"
run "v$next" "$work/why.md";       check "an uncommitted change to a tracked file is refused" no $?
g checkout -q -- CHANGELOG.md
g branch -q "release/v$next"
run "v$next" "$work/why.md";       check "a leftover release/v$next branch is refused"  no $?
is "the manifests were not rewritten first" [ "$(version_in plugin.json)" = "$current" ]
g branch -q -D "release/v$next"
# The same leftover on origin only (a fresh clone): caught before the files change, not at the push.
git -C "$origin" branch -q "release/v$next" main
run "v$next" "$work/why.md";       check "a release/v$next branch on origin only is refused"  no $?
is "the manifests were not rewritten first (origin-only leftover)" [ "$(version_in plugin.json)" = "$current" ]
is "still on main (origin-only leftover)" [ "$(g rev-parse --abbrev-ref HEAD)" = main ]
git -C "$origin" branch -q -D "release/v$next"
# Run 1 moves the [Unreleased] compare link; without one there is nothing to move.
is "CHANGELOG.md has an [Unreleased] compare link" [ -n "$base" ]
grep -v '^\[Unreleased\]: ' "$repo/CHANGELOG.md" > "$work/changelog"; cp "$work/changelog" "$repo/CHANGELOG.md"
g commit -q -am "docs: drop the compare link"; g push -q origin main
run "v$next" "$work/why.md";       check "a CHANGELOG.md without the [Unreleased] compare link is refused" no $?
is "  before the release branch"   not g rev-parse -q --verify "refs/heads/release/v$next"
is "  and on main, unchanged"      untouched
g reset -q --hard HEAD~1; g push -q -f origin main
g remote set-url origin "$work/nowhere.git"
run "v$next" "$work/why.md";       check "an origin that cannot be reached stops it (the fetch), nothing is read as 'no tag'" no $?
g remote set-url origin "$origin"
g switch -q -c other
run "v$next" "$work/why.md";       check "a branch other than main is refused"        no $?
g switch -q main; g branch -q -D other
g commit -q --allow-empty -m "ahead"; g push -q origin main; g reset -q --hard HEAD~1
run "v$next" "$work/why.md";       check "a main behind origin/main is refused"       no $?
g merge -q --ff-only origin/main
g commit -q --allow-empty -m "local only"
run "v$next" "$work/why.md";       check "a main ahead of origin/main is refused"     no $?
g reset -q --hard origin/main
is "nothing changed" untouched

echo "-- the eval suite, when the pinned template changed what the agent reads"
# The pin moves to a tag the release before was not tested with; the mock
# answers for the template's diff between the two.
prev_ref="${template##* }"; moved_ref="v0.0.0-moved"; before_move="$(g rev-parse HEAD)"
sed -i.bak -E "s/^template_ref=\"[^\"]+\"$/template_ref=\"$moved_ref\"/" "$repo/scripts/new-project.sh"; rm "$repo/scripts/new-project.sh.bak"
g commit -q -am "chore: move the template pin"; g push -q origin main
moved="${template% *} $moved_ref"
suite_link="https://github.com/o/r/issues/647#issuecomment-123"
printf 'A reason.\n\ntested with %s\n' "$moved" > "$work/moved.md"
printf 'A reason.\n\ntested with %s\n\neval suite: <%s>\n' "$moved" "$suite_link" > "$work/moved-link.md"
printf 'A reason.\n\ntested with %s\n\neval suite not run: only the README line changed in AGENTS.md.\n' "$moved" > "$work/moved-reason.md"
printf 'A reason.\n\ntested with %s\n\neval suite: %s\n' "$moved" "$suite_link" > "$work/moved-bare-link.md"
printf 'A reason.\n\ntested with %s\n\neval suite: <https://example.com/table>\n' "$moved" > "$work/moved-other-link.md"
printf 'A reason.\n\ntested with %s\n\neval suite not run:  \n' "$moved" > "$work/moved-no-reason.md"
printf 'A reason.\n\ntested with %s\n\neval suite: <%s>\neval suite not run: both.\n' "$moved" "$suite_link" > "$work/moved-two.md"
undo_bump() { g switch -q main; g branch -q -D "release/v$next"; }
export COMPARE_OUT=$'3\nREADME.md\ntemplate/AGENTS.md.jinja\ntemplate/.claude/output-styles/new-name.md.jinja\ntemplate/.claude/output-styles/beginner-or-non-engineer.md.jinja'
run "v$next" "$work/moved.md";     check "a moved pin that changes what the agent reads, without a suite line, is refused" no $?
is "  and the refusal names the files" says "template/AGENTS.md.jinja"
is "  and the old name of a renamed one" says "beginner-or-non-engineer.md.jinja"
is "  and the two lines it takes" bash -c 'grep -qF "eval suite: <https://" "$1" && grep -qF "eval suite not run: <why>" "$1"' _ "$work/out"
is "  after asking the template's diff between the two tags" grep -qF "compare/$prev_ref...$moved_ref" "$GH_LOG"
is "  and nothing changed" untouched
run "v$next" "$work/moved-bare-link.md";  check "a bare link (markdownlint's MD034 in the section) is refused" no $?
run "v$next" "$work/moved-other-link.md"; check "a link that is not a GitHub comment is refused" no $?
run "v$next" "$work/moved-no-reason.md";  check "'eval suite not run:' with no reason is refused" no $?
run "v$next" "$work/moved-two.md";        check "two suite lines are refused" no $?
is "nothing changed" untouched
export COMPARE_RC=4
run "v$next" "$work/moved.md";     check "a template diff that cannot be read is refused, not read as 'no change'" no $?
is "  and nothing changed" untouched
run "v$next" "$work/moved-link.md"; check "  even with a suite line: the query ran first" no $?
unset COMPARE_RC
export COMPARE_OUT=300
run "v$next" "$work/moved.md";     check "a diff cut at 300 files asks, whatever it lists" no $?
export COMPARE_OUT=$'3\nREADME.md\ntemplate/AGENTS.md.jinja\ntemplate/.claude/skills/verify/SKILL.md.jinja'
run "v$next" "$work/moved-link.md"; check "with the table's link it bumps" ok $?
is "  and the section carries the link" grep -qxF "eval suite: <$suite_link>" <(section_of "$next")
undo_bump
run "v$next" "$work/moved-reason.md"; check "with a stated reason it bumps" ok $?
is "  and the section carries the reason" grep -qxF "eval suite not run: only the README line changed in AGENTS.md." <(section_of "$next")
undo_bump
export COMPARE_OUT=$'2\nREADME.md\ntemplate/README.md.jinja'
run "v$next" "$work/moved.md";     check "a moved pin that touches no file the agent reads is not asked" ok $?
is "  and says nothing of the suite" not says "eval suite"
undo_bump
unset COMPARE_OUT
grep -vxF "tested with $template" "$repo/CHANGELOG.md" > "$work/changelog"; cp "$work/changelog" "$repo/CHANGELOG.md"
g commit -q -am "docs: lose the release before's tested line"; g push -q origin main
run "v$next" "$work/moved-link.md"; check "with no tested line in the release before's section, nothing to compare with, it is refused" no $?
is "  and the refusal names that section" says "[$current] section"
g reset -q --hard "$before_move"; g push -q -f origin main
is "the pin is back where the release before tested it" grep -qxF "template_ref=\"$prev_ref\"" "$repo/scripts/new-project.sh"

echo "-- bump"
run "v${current%%.*}.0.0" "$work/why.md"; check "a version not above the current one is refused" no $?
is "nothing changed" untouched
cp "$work/why.md" "$repo/why.md"   # untracked, inside the checkout
run "v$next" "$repo/why.md";       check "a higher version bumps (why-file untracked in the checkout)" ok $?
is "plugin.json moved"             [ "$(version_in plugin.json)" = "$next" ]
is "marketplace.json moved with it" [ "$(version_in marketplace.json)" = "$next" ]
is "CHANGELOG got the section"     grep -q "^## \[$next\] - $(date +%Y-%m-%d)$" "$repo/CHANGELOG.md"
is "CHANGELOG keeps Unreleased above it" bash -c 'grep -n "^## \[" "$1" | head -2 | tr "\n" " " | grep -q "Unreleased.*\[$2\]"' _ "$repo/CHANGELOG.md" "$next"
is "committed on release/v$next"   [ "$(g rev-parse --abbrev-ref HEAD)" = "release/v$next" ]
is "the tree is clean after the commit" [ -z "$(g status --porcelain --untracked-files=no)" ]
is "the commit title is chore(release): v$next" [ "$(g log -1 --format=%s)" = "chore(release): v$next" ]
is "no tag yet"                    [ -z "$(g tag -l)" ]
is "no release yet"                not grep -q "release create" "$GH_LOG"
is "the pin did not move, so the template's diff was not asked" not grep -q "compare/" "$GH_LOG"
is "the section is the why, then what was under Unreleased" [ "$(section_of "$next")" = "$expected" ]
is "Unreleased is empty"           [ -z "$(section_of Unreleased)" ]
is "[Unreleased] compares from the new tag" grep -qxF "[Unreleased]: $base/compare/v$next...HEAD" "$repo/CHANGELOG.md"
is "  and is the only [Unreleased] link" [ "$(grep -c '^\[Unreleased\]: ' "$repo/CHANGELOG.md")" = 1 ]
is "the new version links its Release" grep -qxF "[$next]: $base/releases/tag/v$next" "$repo/CHANGELOG.md"
is "the version before keeps its link" grep -qxF "[$current]: $base/releases/tag/v$current" "$repo/CHANGELOG.md"

echo "-- tag and release, after the merge"
g switch -q main; g merge -q --ff-only "release/v$next"; g push -q origin main
release_commit="$(g rev-parse HEAD)"
rm "$repo/why.md"   # run 2 reads no file: the why is in CHANGELOG.md now
g commit -q --allow-empty -m "feat: landed after the release pull request"
python3 - "$repo/.claude-plugin/plugin.json" <<'PY'   # reorders the file (the version line is deleted and re-added unchanged) and puts the same string in a dependency
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text()); v = d.pop("version"); d["version"] = v
d["dependencies"].append({"name": "unrelated", "marketplace": "elsewhere", "version": v})
p.write_text(json.dumps(d, indent=2) + "\n")
PY
g commit -q -am "chore: reorder plugin.json and add a dependency after the release"; g push -q origin main
export VIEW_RC=0
run "v$next" "$work/why.md";       check "an existing release is refused"                 no $?
is "no second release"             not grep -q "release create" "$GH_LOG"
export VIEW_RC=4
run "v$next" "$work/why.md";       check "a failed release query is refused, not read as 'no release'" no $?
is "no release on a failed query"  not grep -q "release create" "$GH_LOG"
is "no tag on a failed query"      [ -z "$(git -C "$origin" tag -l)" ]
unset VIEW_RC
echo "-- the e2e gate: a green run on the commit being tagged, nothing else"
e2e_url="https://github.com/o/r/actions/runs/1"
run "v$next" "$work/why.md";       check "no e2e run on the release commit is refused"  no $?
is "no tag without an e2e run"     [ -z "$(git -C "$origin" tag -l)" ]
is "no release without an e2e run" not grep -q "release create" "$GH_LOG"
E2E_SHA="$(g rev-parse HEAD)"; export E2E_SHA E2E_RUNS="success $e2e_url"   # green, but on the later main
run "v$next" "$work/why.md";       check "a green run on another commit is refused"     no $?
is "no tag on another commit's run" [ -z "$(git -C "$origin" tag -l)" ]
export E2E_SHA="$release_commit"
for verdict in failure cancelled skipped in_progress; do
  export E2E_RUNS="$verdict $e2e_url"
  run "v$next" "$work/why.md";     check "a run on the commit that is $verdict is refused" no $?
done
is "no tag on a run that is not green" [ -z "$(git -C "$origin" tag -l)" ]
is "no release on a run that is not green" not grep -q "release create" "$GH_LOG"
export E2E_RUNS="success $e2e_url" E2E_RC=4
run "v$next" "$work/why.md";       check "a failed e2e query is refused, not read as 'no run'" no $?
is "no tag on a failed e2e query"  [ -z "$(git -C "$origin" tag -l)" ]
unset E2E_RC
export E2E_RUNS="failure $e2e_url"$'\n'"success $e2e_url"

echo "-- run 2 reads the section of the merged main, not a file"
# The e2e run is green from here on: only the section can refuse. Each case
# edits the section on main (the release pull request can be edited, and later
# ones can touch the file), passes a valid why-file that run 2 must not read,
# and puts main back.
merged="$(g rev-parse HEAD)"
edit() { # <python on t, the file's text; ver is the version, arg the second argument>
  python3 - "$repo/CHANGELOG.md" "$next" "$1" "${2:-}" <<'PY'
import pathlib, re, sys
p, ver, code, arg = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
t = p.read_text(); exec(code); p.write_text(t)
PY
  g commit -q -am "docs: edit the $next section"; g push -q origin main
}
# What stands between the heading and the first ###, replaced by arg.
why_is() { edit "t = re.sub(r'(?ms)^(## \[' + re.escape(ver) + r'\][^\n]*\n).*?^(?=### )', lambda m: m[1] + '\n' + arg + '\n\n', t, count=1)" "$1"; }
back() { g reset -q --hard "$merged"; g push -q -f origin main; }
edit "t = re.sub(r'(?ms)^(## \[' + re.escape(ver) + r'\][^\n]*\n).*?^(?=### )', lambda m: m[1] + '\n', t, count=1)"
run "v$next" "$work/why.md";       check "a section with no why above its first ### is refused" no $?
back
why_is "$(printf -- '---\n\ntested with %s' "$template")"
run "v$next" "$work/why.md";       check "a section whose why is only the tested line and markup is refused" no $?
back
why_is "A reason, and no tested line."
run "v$next" "$work/why.md";       check "a section without the tested line is refused" no $?
is "  and the refusal names the line it wants" says "tested with $template"
back
why_is "$(printf 'A reason.\n\ntested with %s v0.0.0-not-the-pin' "${template%% *}")"
run "v$next" "$work/why.md";       check "a section tested with another template tag is refused" no $?
back
why_is "$(printf 'A reason.\n\n## Migration\n\nMore.\n\ntested with %s' "$template")"
run "v$next" "$work/why.md";       check "a section whose why has a heading line is refused, as the why-file is" no $?
is "  and the refusal names the heading" says "heading"
back
why_is "A reason, the tested line below."
edit "t = t.replace('- An entry waiting for the release.\n', '- An entry waiting for the release.\n\ntested with ' + arg + '\n', 1)" "$template"
run "v$next" "$work/why.md";       check "a tested line under the first ### is not the why's" no $?
back
edit "t = re.sub(r'(?m)^## \[' + re.escape(ver) + r'\].*\n', '', t, count=1)"
run "v$next" "$work/why.md";       check "no section for the version at all is refused" no $?
is "  and the refusal names the section" says "## [$next]"
back
is "no tag on a refused section"   [ -z "$(git -C "$origin" tag -l)" ]
is "no release on a refused section" not grep -q "release create" "$work"/log.*

rm -f "$work/deleted.md"
run "v$next" "$work/deleted.md";   check "from the merged main, with a green e2e run on its commit, it tags and releases" ok $?
is "  with the why-file deleted, and says it did not read it" says "not read"
is "the green run is named"        grep -q "$e2e_url" "$work/out"
is "the tag is on origin"          git -C "$origin" show-ref --verify --quiet "refs/tags/v$next"
is "the tag points at the release commit" [ "$(git -C "$origin" rev-parse "v$next^{commit}")" = "$release_commit" ]
is "not at the later main"         [ "$(git -C "$origin" rev-parse "v$next^{commit}")" != "$(git -C "$origin" rev-parse main)" ]
is "gh release create --verify-tag --notes-file - --generate-notes" grep -qxF "gh release create v$next --verify-tag --notes-file - --generate-notes" "$GH_LOG"
is "the Release text is the section, heading left out; the index goes under it" [ "$(cat "$GH_LOG.body")" = "$expected" ]
is "the tree is still clean"       untouched

echo "-- a pushed tag without a release resumes"
g tag -d "v$next" >/dev/null; git -C "$origin" tag -d "v$next" >/dev/null
g tag -a -m "v$next" "v$next" main; g push -q origin "v$next"; g tag -d "v$next" >/dev/null
run "v$next";                      check "a tag on origin that is not on the release commit is refused" no $?
is "no release on a misplaced tag" not grep -q "release create" "$GH_LOG"
git -C "$origin" tag -d "v$next" >/dev/null
g tag -a -m "v$next" "v$next" "$release_commit"; g push -q origin "v$next"; g tag -d "v$next" >/dev/null   # pushed from another machine
run "v$next";                      check "an existing tag on the release commit is reused" ok $?
is "the release was created"       grep -q "release create" "$GH_LOG"

echo "-- a local tag left by a failed push"
git -C "$origin" tag -d "v$next" >/dev/null
g tag -a -m "v$next" "v$next" main                     # wrong commit
run "v$next";                      check "a local tag that points elsewhere is refused"    no $?
is "nothing pushed"                not git -C "$origin" show-ref --quiet "refs/tags/v$next"
g tag -d "v$next" >/dev/null; g tag -a -m "v$next" "v$next" "$release_commit"   # the push failed last time
run "v$next";                      check "a local tag on the release commit is pushed and reused" ok $?
is "the tag reached origin"        [ "$(git -C "$origin" rev-parse "v$next^{commit}")" = "$release_commit" ]
is "the release was created"       grep -q "release create" "$GH_LOG"

echo "-- run 2 from a fresh clone: nothing outside the merged main"
git clone -q "$origin" "$work/fresh"
run_in "$work/fresh" "v$next";     check "a fresh clone with no why-file anywhere releases" ok $?
is "  with the section as the Release text" [ "$(cat "$GH_LOG.body")" = "$expected" ]

echo "-- a shallow clone"
git clone -q --depth 1 "file://$origin" "$work/shallow"
(cd "$work/shallow" && GH_LOG="$work/log.shallow" "$work/shallow/scripts/make-release.sh" "v${next%.*}.1" "$work/why.md") >/dev/null 2>&1
check "a shallow clone is refused before anything is read" no $?

echo "-- a tag that already exists elsewhere"
git -C "$origin" tag "v${next%.*}.9" "main~1"
run "v${next%.*}.9" "$work/why.md"; check "a number whose tag exists on origin is not bumped to" no $?
is "nothing changed" untouched

echo
echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
