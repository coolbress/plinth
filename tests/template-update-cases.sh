#!/usr/bin/env bash
# scripts/template-update.sh (#232) on fixtures, offline. `gh` and `uvx` are
# mocks; git is real, and `origin` is a bare repository on disk, so a push is
# a real push that can be read back. The mock copier acts out what copier
# 9.18.2 was measured to do: a clean update rewrites the answers file and a
# template file; a conflict leaves the file unmerged in the index (`UU`)
# with `<<<<<<< before updating` markers, and still exits 0.
#
# The verdicts: the command run is the checker's own line, word for word;
# nothing runs outside a worktree branched from the verified default branch;
# a dirty worktree stops before copier; no pull request is opened, and
# nothing pushed, while a conflict is unresolved; the default branch is
# never pushed to.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/template-update.sh"
checker="$root/scripts/floor-check.py"
target_ref="$(sed -nE 's/^template_ref="([^"]+)"$/\1/p' "$root/scripts/new-project.sh")"
work="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
mkdir -p "$work/bin"
sha40="$(printf '%040d' 7)"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# ── mock: gh ─────────────────────────────────────────────────────────────
# repo view names o/r with default branch main; the branch API answers the
# bare origin's own main unless MOCK_REMOTE_SHA overrides it; pr create
# records its arguments and body and prints a URL.
cat > "$work/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -u
printf 'gh %s\n' "$*" >> "$GH_LOG"
case "$*" in
  "repo view"*)         echo "o/r main" ;;
  "api repos/o/r/branches/main"*) echo "${MOCK_REMOTE_SHA:-$(git -C "$BARE" rev-parse main)}" ;;
  "pr list"*)
    # MOCK_PR_EXISTING holds the JSON GitHub would answer; the script's own
    # --jq filter is applied to it, as gh does.
    jqf="."; prev=""
    for a in "$@"; do [ "$prev" = --jq ] && jqf="$a"; prev="$a"; done
    jq -r "$jqf" "${MOCK_PR_EXISTING:-/dev/null}" ;;
  "pr create"*)
    [ -e "${MOCK_PR_FAIL:-/nonexistent}" ] && { rm "$MOCK_PR_FAIL"; echo "mock gh: pr create failing once" >&2; exit 1; }
    body=""; prev=""
    for a in "$@"; do [ "$prev" = --body-file ] && body="$a"; prev="$a"; done
    cp "$body" "$GH_LOG.body"
    echo "https://github.com/o/r/pull/9" ;;
  *) echo "mock gh: unexpected: $*" >&2; exit 1 ;;
esac
MOCK
# ── mock: uvx (standing in for copier update) ───────────────────────────
cat > "$work/bin/uvx" <<'MOCK'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" > "$UVX_LOG"
ref=""; prev=""
for a in "$@"; do [ "$prev" = --vcs-ref ] && ref="$a"; prev="$a"; done
[ "${MOCK_COPIER:-clean}" = fail ] && { echo "copier: something broke" >&2; exit 1; }
sed -i.bak "s/^_commit: .*/_commit: $ref/" .copier-answers.yml && rm .copier-answers.yml.bak
printf 'template line\n' >> AGENTS.md
case "${MOCK_COPIER:-clean}" in
  conflict)
    base="$(git hash-object -w CONTRIBUTING.md)"
    printf 'ours\n' > ours; printf 'theirs\n' > theirs
    o="$(git hash-object -w ours)"; t="$(git hash-object -w theirs)"; rm ours theirs
    git update-index --force-remove CONTRIBUTING.md
    printf '100644 %s 1\tCONTRIBUTING.md\n100644 %s 2\tCONTRIBUTING.md\n100644 %s 3\tCONTRIBUTING.md\n' "$base" "$o" "$t" \
      | git update-index --index-info
    printf '<<<<<<< before updating\nours\n=======\ntheirs\n>>>>>>> after updating\n' > CONTRIBUTING.md ;;
  rej) printf -- '--- a\n+++ b\n' > CONTRIBUTING.md.rej ;;
esac
MOCK
# ── wrapper: git, failing only `ls-remote` when MOCK_LSREMOTE_FAIL is set ─
real_git="$(command -v git)"
cat > "$work/bin/git" <<MOCK
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = ls-remote ] && [ -n "\${MOCK_LSREMOTE_FAIL:-}" ]; then echo "fatal: could not read from remote repository" >&2; exit 128; fi
done
exec "$real_git" "\$@"
MOCK
chmod +x "$work/bin/gh" "$work/bin/uvx" "$work/bin/git"

# A consumer repository at an old template tag, pushed to a bare origin.
fixture() { # <name> → sets $repo and $BARE, cleans up what an earlier case left
  repo="$work/$1"; BARE="$work/$1.git"
  git init -q -b main "$repo"
  mkdir -p "$repo/.github/workflows" "$repo/.github/ISSUE_TEMPLATE"
  printf '_commit: v1.0.0\n_src_path: gh:coolbress/plinth-template\narchetype: cli\n' > "$repo/.copier-answers.yml"
  printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n' "$sha40" > "$repo/.github/workflows/ci.yml"
  printf '# Contributing\n' > "$repo/CONTRIBUTING.md"; printf '# Agents\n' > "$repo/AGENTS.md"
  printf 'name: task\n# local\n' > "$repo/.github/ISSUE_TEMPLATE/task.yml"
  git -C "$repo" add -A && git -C "$repo" commit -q -m base
  git init -q --bare "$BARE"
  git -C "$repo" remote add origin "$BARE"
  git -C "$repo" push -q origin main
  export BARE
}
run() { # <args...>: the script from inside $repo; sets $out and $rc
  out="$(cd "$repo" && PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" "$@" 2>&1)"; rc=$?
}
reset_logs() { : > "$work/gh.log"; rm -f "$work/uvx.log" "$work/gh.log.body"; }
wt_of() { printf '%s\n' "$work/$1-template-$target_ref"; }

# ── plan: read-only ─────────────────────────────────────────────────────
fixture plan; reset_logs
want="$(python3 "$checker" --root "$repo" --print-update-command 2>/dev/null)"
run
base="$(git -C "$BARE" rev-parse main)"
if [ "$rc" = 0 ] && grep -qF "$want" <<<"$out" && grep -qF -- "--apply $base" <<<"$out"; then ok "the plan prints the checker's own command and the apply line naming the verified base"
else bad "plan (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
if [ ! -e "$(wt_of plan)" ] && ! git -C "$repo" rev-parse -q --verify "refs/heads/chore/template-$target_ref" >/dev/null && [ ! -e "$work/uvx.log" ]
then ok "the plan creates no worktree, no branch, and never runs copier"
else bad "the plan wrote something"; fi

# ── the base must be the verified default branch ────────────────────────
reset_logs
run --apply "$(printf '%040d' 1)"
if [ "$rc" != 0 ] && grep -q "base moved" <<<"$out" && [ ! -e "$(wt_of plan)" ] && [ ! -e "$work/uvx.log" ]
then ok "an --apply naming another base than origin/main today stops before anything is created"
else bad "stale --apply base (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
reset_logs
out="$(cd "$repo" && MOCK_REMOTE_SHA="$(printf '%040d' 2)" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" 2>&1)"; rc=$?
if [ "$rc" != 0 ] && grep -q "not verified" <<<"$out" && [ ! -e "$work/uvx.log" ]
then ok "origin/main that differs from GitHub's own main is not a verified base: stops"
else bad "unverified base (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# ── clean update ────────────────────────────────────────────────────────
fixture clean; reset_logs
printf 'scratch\n' > "$repo/untracked-in-the-users-checkout"
before_head="$(git -C "$repo" rev-parse HEAD)"; before_status="$(git -C "$repo" status --porcelain)"
want="$(python3 "$checker" --root "$repo" --print-update-command 2>/dev/null)"
base="$(git -C "$BARE" rev-parse main)"
run --apply "$base" --assisted-by "Claude:claude-test-1"
wt="$(wt_of clean)"
if [ "$rc" = 0 ] && [ "$(cat "$work/uvx.log" 2>/dev/null)" = "${want#uvx }" ]; then ok "copier runs with exactly the words the checker prints"
else bad "clean apply (rc=$rc), uvx got '$(cat "$work/uvx.log" 2>/dev/null)', checker printed '$want'"; printf '%s\n' "$out" | sed 's/^/        /'; fi
if [ "$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)" = "chore/template-$target_ref" ] \
   && [ "$(git -C "$wt" rev-parse HEAD~1 2>/dev/null)" = "$base" ]; then ok "the update is one commit on its own branch in a worktree beside the repository, on the verified base"
else bad "worktree/branch/base"; fi
if [ "$(git -C "$repo" rev-parse HEAD)" = "$before_head" ] && [ "$(git -C "$repo" status --porcelain)" = "$before_status" ]
then ok "the checkout it was run from is untouched (same HEAD, same status)"
else bad "the user's checkout changed"; fi
if [ "$(git -C "$BARE" rev-parse main)" = "$base" ] && git -C "$BARE" rev-parse -q --verify "refs/heads/chore/template-$target_ref" >/dev/null
then ok "the branch is pushed; main on origin is not moved"
else bad "push: main moved or the branch is missing"; fi
if grep -q -- "pr create" "$work/gh.log" && grep -q -- "--draft" "$work/gh.log" && grep -q -- "--base main" "$work/gh.log"
then ok "a draft pull request is opened against main"
else bad "pr create"; sed 's/^/        /' "$work/gh.log"; fi
body="$(cat "$work/gh.log.body" 2>/dev/null)"
if grep -q "^- AGENTS.md" <<<"$body" && grep -q "^- .copier-answers.yml" <<<"$body" && grep -qF "$want" <<<"$body"
then ok "the description lists what merged cleanly and the command that ran"
else bad "description (merged cleanly)"; printf '%s\n' "$body" | sed 's/^/        /'; fi
if grep -A2 -i "resolved by a person" <<<"$body" | grep -q "^- none"; then ok "the description says nothing was resolved by a person"
else bad "description (resolved: none)"; printf '%s\n' "$body" | sed 's/^/        /'; fi
if [ "$(tail -n 1 <<<"$body")" = "Assisted-by: Claude:claude-test-1" ]; then ok "the description ends with the Assisted-by line it was given"
else bad "Assisted-by last line: '$(tail -n 1 <<<"$body")'"; fi
if grep -q "task.yml" <<<"$body"; then bad "an untouched local issue form is listed as changed"
else ok "a local issue form copier did not touch is not in the description"; fi
if grep -qi "wait" "$work/gh.log"; then bad "something waited on checks"; else ok "nothing waits on the branch's checks"; fi
reset_logs
run --finish "$wt"
if [ "$rc" = 0 ] && ! grep -q "pr create" "$work/gh.log" && grep -q "pull/9" <<<"$out"
then ok "a second --finish names the open pull request and neither opens nor updates one"
else bad "second finish (rc=$rc)"; sed 's/^/        /' "$work/gh.log"; fi
reset_logs
run --apply "$base"
if [ "$rc" != 0 ] && [ ! -e "$work/uvx.log" ] && grep -q "already exists" <<<"$out"
then ok "an existing worktree or branch stops a second --apply before copier runs"
else bad "second apply (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# ── a conflict is left for a person ─────────────────────────────────────
fixture conflict; reset_logs
base="$(git -C "$BARE" rev-parse main)"; wt="$(wt_of conflict)"
out="$(cd "$repo" && MOCK_COPIER=conflict PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" 2>&1)"; rc=$?
if [ "$rc" = 3 ] && grep -q "CONTRIBUTING.md" <<<"$out" && grep -qF -- "--finish $wt" <<<"$out"
then ok "a conflict stops with exit 3, names the file and the --finish line"
else bad "conflict (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
if ! grep -q "pr create" "$work/gh.log" && ! git -C "$BARE" rev-parse -q --verify "refs/heads/chore/template-$target_ref" >/dev/null
then ok "with a conflict unresolved nothing is pushed and no pull request is opened"
else bad "conflict: pushed or opened"; fi
if [ -n "$(git -C "$wt" diff --name-only --diff-filter=U)" ] && grep -q '^<<<<<<< ' "$wt/CONTRIBUTING.md"
then ok "the conflict is left in the worktree as copier left it, not chosen"
else bad "the conflict was touched"; fi
reset_logs
run --finish "$wt"
if [ "$rc" = 3 ] && ! grep -q "pr create" "$work/gh.log"; then ok "--finish with the conflict still unmerged stops, opens nothing"
else bad "finish while unmerged (rc=$rc)"; fi
git -C "$wt" add CONTRIBUTING.md
reset_logs
run --finish "$wt"
if [ "$rc" = 3 ] && ! grep -q "pr create" "$work/gh.log" && grep -q "CONTRIBUTING.md" <<<"$out"
then ok "markers staged with git add are still a conflict: stops, opens nothing"
else bad "finish with staged markers (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
printf '# Contributing\nresolved by hand\n' > "$wt/CONTRIBUTING.md"; git -C "$wt" add CONTRIBUTING.md
printf '# Agents\nedited after the update\n' > "$wt/AGENTS.md"
reset_logs
run --finish "$wt"
body="$(cat "$work/gh.log.body" 2>/dev/null)"
if [ "$rc" = 0 ] && grep -q "pr create" "$work/gh.log" && grep -A2 -i "resolved by a person" <<<"$body" | grep -q "^- CONTRIBUTING.md" \
   && grep -A3 -i "resolved by a person" <<<"$body" | sed -n 4p | grep -q '^$'
then ok "once resolved, --finish opens the draft and the description names the file a person resolved, as its own list"
else bad "finish after resolving (rc=$rc)"; printf '%s\n%s\n' "$out" "$body" | sed 's/^/        /'; fi
if grep -A2 -i "edited by a person" <<<"$body" | grep -q "^- AGENTS.md"
then ok "a cleanly merged file a person changed afterwards is named as such, not as merged cleanly"
else bad "edited-after list"; printf '%s\n' "$body" | sed 's/^/        /'; fi
if [ "$(git -C "$BARE" rev-parse main)" = "$base" ]; then ok "main on origin is not moved by --finish"; else bad "main moved"; fi

# ── a failed pull request creation can be finished again ───────────────
fixture resume; reset_logs
base="$(git -C "$BARE" rev-parse main)"; wt="$(wt_of resume)"
: > "$work/pr-fail-once"
out="$(cd "$repo" && MOCK_PR_FAIL="$work/pr-fail-once" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -qF -- "--finish $wt" <<<"$out"; then ok "a pull request that could not be opened points at --finish, not at a hand-made gh pr create"
else bad "pr create failure (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
reset_logs
run --finish "$wt"
if [ "$rc" = 0 ] && grep -q "pr create" "$work/gh.log" && [ "$(git -C "$wt" rev-list --count "$base..HEAD")" = 1 ] \
   && grep -q "^- AGENTS.md" "$work/gh.log.body"
then ok "--finish after a failed pull request opens it, with the same one commit and its description"
else bad "resume (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# ── a pin Dependabot raised is the one copier is given ──────────────────
fixture raised; reset_logs
raised="$(printf '%040d' 9)"
sed -i.bak "s/@$sha40/@$raised/" "$repo/.github/workflows/ci.yml" && rm "$repo/.github/workflows/ci.yml.bak"
git -C "$repo" commit -q -am "bump plinth" && git -C "$repo" push -q origin main
run --apply "$(git -C "$BARE" rev-parse main)"
if [ "$rc" = 0 ] && grep -q -- "--data plinth_sha=$raised\$" "$work/uvx.log"; then ok "copier is given the pin the workflows carry today, not the one first rendered"
else bad "raised pin (rc=$rc): uvx got '$(cat "$work/uvx.log" 2>/dev/null)'"; fi

# ── a pull request GitHub made although gh reported failure is adopted ──
fixture adopt; reset_logs
base="$(git -C "$BARE" rev-parse main)"; wt="$(wt_of adopt)"
: > "$work/pr-fail-once"
(cd "$repo" && MOCK_PR_FAIL="$work/pr-fail-once" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" >/dev/null 2>&1)
# What gh pr list answers: an open pull request on the branch, its head
# repository and the commit at its head.
pr_json() { # <url> <owner> <repo> <head-sha>
  printf '[{"url":"%s","headRepositoryOwner":{"login":"%s"},"headRepository":{"name":"%s"},"headRefOid":"%s","isCrossRepository":%s}]\n' \
    "$1" "$2" "$3" "$4" "$([ "$2/$3" = o/r ] && echo false || echo true)"
}
pr_json "https://github.com/o/r/pull/77" o r "$(git -C "$wt" rev-parse HEAD)" > "$work/pr-existing"
reset_logs
out="$(cd "$repo" && MOCK_PR_EXISTING="$work/pr-existing" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --finish "$wt" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && ! grep -q "pr create" "$work/gh.log" && grep -q "pull/77" <<<"$out" && grep -qx "pr=https://github.com/o/r/pull/77" "$(git -C "$wt" rev-parse --absolute-git-dir)/plinth-template-update"
then ok "an open pull request already on the branch is recorded, not created twice"
else bad "adopt (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# ── a pull request on the branch that is not this update is not adopted ─
# `--head` filters by branch name only: a fork's pull request from a branch
# of the same name, or one whose head is not the commit just pushed, is
# someone else's (#274).
for who in "fork:fork r same" "stale:o r other"; do
  name="${who%%:*}"; set -- ${who#*:}
  fixture "adopt$name"; reset_logs
  base="$(git -C "$BARE" rev-parse main)"; wt="$(wt_of "adopt$name")"
  : > "$work/pr-fail-once"
  (cd "$repo" && MOCK_PR_FAIL="$work/pr-fail-once" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" >/dev/null 2>&1)
  head="$(git -C "$wt" rev-parse HEAD)"; [ "$3" = same ] || head="$(printf '%040d' 5)"
  pr_json "https://github.com/$1/$2/pull/88" "$1" "$2" "$head" > "$work/pr-existing"
  reset_logs
  out="$(cd "$repo" && MOCK_PR_EXISTING="$work/pr-existing" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --finish "$wt" 2>&1)"; rc=$?
  if [ "$rc" = 0 ] && grep -q "pr create" "$work/gh.log" && grep -q "pull/9" <<<"$out" && ! grep -q "pull/88" <<<"$out" \
     && grep -qx "pr=https://github.com/o/r/pull/9" "$(git -C "$wt" rev-parse --absolute-git-dir)/plinth-template-update"
  then ok "an open pull request on the branch name from $([ "$name" = fork ] && echo "another owner's fork" || echo "this repository at another commit") is not adopted: the draft is created"
  else bad "adopt $name (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; sed 's/^/        /' "$work/gh.log"; fi
done

# ── what the base already holds is not a conflict ───────────────────────
# A tracked .rej fixture and a document quoting a conflict marker were there
# before copier ran; only what the update changed is read (#274).
fixture fixtures
mkdir -p "$repo/docs" "$repo/tests/fixtures"
printf -- '--- a\n+++ b\n' > "$repo/tests/fixtures/sample.rej"
printf '# Merging\n\n```text\n<<<<<<< example\nours\n=======\ntheirs\n>>>>>>> example\n```\n' > "$repo/docs/merging.md"
git -C "$repo" add -A && git -C "$repo" commit -q -m fixtures && git -C "$repo" push -q origin main
reset_logs
run --apply "$(git -C "$BARE" rev-parse main)"
if [ "$rc" = 0 ] && grep -q "pr create" "$work/gh.log" && ! grep -q "sample.rej\|merging.md" <<<"$out"
then ok "a tracked .rej and a document with a marker line, both untouched by the update, do not stop it: the draft opens"
else bad "base fixtures (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# ── a staged .rej is still a conflict ───────────────────────────────────
fixture stagedrej; reset_logs
base="$(git -C "$BARE" rev-parse main)"; wt="$(wt_of stagedrej)"
(cd "$repo" && MOCK_COPIER=rej PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" >/dev/null 2>&1)
git -C "$wt" add -A
reset_logs
run --finish "$wt"
if [ "$rc" = 3 ] && grep -q "CONTRIBUTING.md.rej" <<<"$out" && ! grep -q "pr create" "$work/gh.log"
then ok "a .rej staged with git add -A is still a conflict: nothing committed, nothing opened"
else bad "staged .rej (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# ── the printed --finish line survives a path with spaces ───────────────
spaced="$work/My Projects"; mkdir -p "$spaced"
repo="$spaced/sp"; BARE="$spaced/sp.git"
git init -q -b main "$repo"; mkdir -p "$repo/.github/workflows"
cp "$work/conflict/.copier-answers.yml" "$work/conflict/CONTRIBUTING.md" "$work/conflict/AGENTS.md" "$repo/" 2>/dev/null
printf '_commit: v1.0.0\n_src_path: gh:coolbress/plinth-template\narchetype: cli\n' > "$repo/.copier-answers.yml"
printf '# Contributing\n' > "$repo/CONTRIBUTING.md"; printf '# Agents\n' > "$repo/AGENTS.md"
cp "$work/conflict/.github/workflows/ci.yml" "$repo/.github/workflows/ci.yml"
git -C "$repo" add -A && git -C "$repo" commit -q -m base
git init -q --bare "$BARE"; git -C "$repo" remote add origin "$BARE"; git -C "$repo" push -q origin main; export BARE
reset_logs
out="$(cd "$repo" && MOCK_COPIER=conflict PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$(git -C "$BARE" rev-parse main)" 2>&1)"
line="$(grep -- '--finish ' <<<"$out" | tail -n 1)"
wt="$spaced/sp-template-$target_ref"
printf '# Contributing\nresolved\n' > "$wt/CONTRIBUTING.md"; git -C "$wt" add -A
reset_logs
out="$(cd "$repo" && PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" bash -c "$line" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q "pr create" "$work/gh.log"; then ok "the printed --finish line runs as printed under a directory with a space"
else bad "spaced path (rc=$rc): '$line'"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# ── only the recorded update branch is finished ─────────────────────────
fixture other; reset_logs
base="$(git -C "$BARE" rev-parse main)"; wt="$(wt_of other)"
out="$(cd "$repo" && MOCK_COPIER=conflict PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" 2>&1)"
printf '# Contributing\nresolved\n' > "$wt/CONTRIBUTING.md"; git -C "$wt" add -A; git -C "$wt" switch -q -c unrelated-branch
reset_logs
run --finish "$wt"
if [ "$rc" = 1 ] && ! grep -q "pr create" "$work/gh.log" && ! git -C "$BARE" rev-parse -q --verify refs/heads/unrelated-branch >/dev/null \
   && grep -q "chore/template-$target_ref" <<<"$out"
then ok "a worktree switched to another branch is not finished: nothing pushed, nothing opened"
else bad "other branch (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# ── a remote branch probe that fails is a stop, not an absent branch ────
fixture probe; reset_logs
out="$(cd "$repo" && MOCK_LSREMOTE_FAIL=1 PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$(git -C "$BARE" rev-parse main)" 2>&1)"; rc=$?
if [ "$rc" = 1 ] && [ ! -e "$work/uvx.log" ] && [ ! -e "$(wt_of probe)" ]; then ok "git ls-remote failing stops before a worktree or copier"
else bad "ls-remote failure (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# ── .rej files count as conflicts ───────────────────────────────────────
fixture rej; reset_logs
base="$(git -C "$BARE" rev-parse main)"
out="$(cd "$repo" && MOCK_COPIER=rej PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" 2>&1)"; rc=$?
if [ "$rc" = 3 ] && grep -q "CONTRIBUTING.md.rej" <<<"$out" && ! grep -q "pr create" "$work/gh.log"
then ok "a .rej file is a conflict: stops, names it, opens nothing"
else bad ".rej (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# ── copier fails ────────────────────────────────────────────────────────
fixture broken; reset_logs
base="$(git -C "$BARE" rev-parse main)"
out="$(cd "$repo" && MOCK_COPIER=fail PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -q "something broke" <<<"$out" && ! grep -q "pr create" "$work/gh.log" \
   && grep -q "git worktree remove --force" <<<"$out" && grep -q "git branch -D" <<<"$out"
then ok "copier failing stops with its own words, opens nothing, and names how to discard the worktree"
else bad "copier failure (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# ── a dirty worktree stops before copier ────────────────────────────────
# A post-checkout hook in the repository writes into every new checkout,
# so the fresh worktree is not clean: copier must not run on it.
fixture dirty; reset_logs
printf '#!/bin/sh\necho stray > stray.txt\n' > "$repo/.git/hooks/post-checkout"; chmod +x "$repo/.git/hooks/post-checkout"
base="$(git -C "$BARE" rev-parse main)"
run --apply "$base"
if [ "$rc" != 0 ] && [ ! -e "$work/uvx.log" ] && grep -q "stray.txt" <<<"$out"
then ok "a worktree that is not clean stops before copier runs, naming what is dirty"
else bad "dirty worktree (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# ── nothing to update ───────────────────────────────────────────────────
fixture current; reset_logs
sed -i.bak "s/^_commit: .*/_commit: $target_ref/" "$repo/.copier-answers.yml" && rm "$repo/.copier-answers.yml.bak"
git -C "$repo" commit -q -am current && git -C "$repo" push -q origin main
run
if [ "$rc" = 1 ] && grep -q "nothing to update" <<<"$out"; then ok "at the target tag the plan says there is nothing to update"
else bad "current (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
