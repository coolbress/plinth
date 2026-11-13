#!/usr/bin/env bash
# scripts/template-update.sh (#232) on fixtures. Offline but for one read, the
# template's pull-request form at the pinned tag (#856); unreadable is a FAIL.
# `gh` and `uvx` are mocks; git is real, and `origin` is a bare repository on disk, so a push is
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
target_sha="$(sed -nE 's/^template_sha="([^"]+)"$/\1/p' "$root/scripts/new-project.sh")"
export TARGET_REF="$target_ref" TARGET_SHA="$target_sha"
work="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
mkdir -p "$work/bin"
sha40="$(printf '%040d' 7)"
# What the update carries for an owner with no `.github` repository (every
# fixture directory answers 404 unless a case writes one): both answers false.
no_shared=" --data owner_has_pr_template=false --data owner_has_issue_forms=false"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
# The checker's GitHub reads come from fixtures, never the network: a
# missing file answers 404, so the tested pin is "not read" unless a case
# writes one (#511). Each directory answers that the target tag still names
# the commit plinth was tested with (#519), unless a case says otherwise.
tag_names() { # <fixture dir> <commit>: what the target tag names on GitHub
  mkdir -p "$1/repos/coolbress/plinth-template/commits"
  printf '{"sha":"%s"}\n' "$2" > "$1/repos/coolbress/plinth-template/commits/$target_ref.json"
}
export FLOOR_CHECK_API_DIR="$work/api-none"; tag_names "$FLOOR_CHECK_API_DIR" "$target_sha"

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
# copier records the tag a commit carries, not the commit (measured, 9.18.2).
[ "$ref" = "$TARGET_SHA" ] && ref="$TARGET_REF"
sed -i.bak "s/^_commit: .*/_commit: $ref/" .copier-answers.yml && rm .copier-answers.yml.bak
printf 'template line\n' >> AGENTS.md
# MOCK_BIG: an update over ci / diff-size's default limit of 400, mostly
# issue forms (#795): 380 lines of form, 40 of source, 500 of docs (excluded).
if [ "${MOCK_BIG:-}" = three ]; then
  # Three files of 350 lines: a split three ways (review on #801).
  mkdir -p src; for f in a b c; do for i in $(seq 1 350); do echo "$f$i = $i"; done > "src/$f.py"; done
elif [ -n "${MOCK_BIG:-}" ]; then
  mkdir -p .github/ISSUE_TEMPLATE src
  for i in $(seq 1 380); do echo "  - label: line $i"; done > .github/ISSUE_TEMPLATE/bug.yml
  for i in $(seq 1 40); do echo "x$i = $i"; done > src/extra.py
  for i in $(seq 1 500); do echo "doc $i"; done >> CONTRIBUTING.md
fi
# MOCK_PINS=move: every plinth uses: now names the plinth_sha the line
# carries, as the template renders it (#793); unset, the workflows are left
# as they were.
if [ "${MOCK_PINS:-}" = move ]; then
  pin=""; for a in "$@"; do case "$a" in plinth_sha=*) pin="${a#plinth_sha=}" ;; esac; done
  for f in .github/workflows/ci.yml .github/workflows/label.yml; do   # the files the template renders
    [ -f "$f" ] || continue
    sed -E -i.bak "s|^([[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*coolbress/plinth/[^@]*)@[0-9a-fA-F]{40}|\1@$pin|" "$f" && rm "$f.bak"
  done
fi
# MOCK_GLOSSARY: the template names GLOSSARY.md too, whatever MOCK_COPIER does.
[ -n "${MOCK_GLOSSARY:-}" ] && mkdir -p docs/agents && printf -- '- Root **`GLOSSARY.md`**: the glossary.\n' > docs/agents/domain.md
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
  # A template that names GLOSSARY.md, as plinth-template's domain docs do
  # from the release that follows mattpocock/skills v1.3.2 (#714).
  glossary) mkdir -p docs/agents && printf -- '- Root **`GLOSSARY.md`**: the glossary.\n' > docs/agents/domain.md ;;
esac
MOCK
# ── wrapper: git, failing only `ls-remote` when MOCK_LSREMOTE_FAIL is set, ─
# and `push` with MOCK_PUSH_FAIL's text as what the remote said (#925)
real_git="$(command -v git)"
cat > "$work/bin/git" <<MOCK
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = ls-remote ] && [ -n "\${MOCK_LSREMOTE_FAIL:-}" ]; then echo "fatal: could not read from remote repository" >&2; exit 128; fi
  if [ "\$a" = push ] && [ -n "\${MOCK_PUSH_FAIL:-}" ]; then printf '%s\\n' "\$MOCK_PUSH_FAIL" >&2; exit 1; fi
done
exec "$real_git" "\$@"
MOCK
chmod +x "$work/bin/gh" "$work/bin/uvx" "$work/bin/git"

# ── the description against the form (#856) ─────────────────────────────
# Every line of the form outside its comments is a field: a heading, or a
# `Label:` line. Each must be in the description, in the form's order. A line
# of the form that is neither, or a form with none, is a failure, not a pass.
cat > "$work/form-fields.py" <<'PY'
import re, sys
form, description = (open(p, encoding="utf-8").read() for p in sys.argv[1:3])
fields = [l.strip() for l in re.sub(r"<!--.*?-->", "", form, flags=re.S).splitlines() if l.strip()]
lines = [l.strip() for l in description.splitlines()]
failed = not fields
if failed:
    print("the form has no field")
at = -1
for field in fields:
    if re.match(r"#{1,6} ", field):
        hits = [i for i, l in enumerate(lines) if l == field]
    elif re.fullmatch(r"[A-Z][\w -]*:", field):
        hits = [i for i, l in enumerate(lines) if l.startswith(field + " ")]
    else:
        print(f"the form has a line this test does not read: {field}")
        failed = True
        continue
    later = [i for i in hits if i > at]
    if later:
        at = later[0]
    else:
        print(f"{field}: {'out of the order of the form' if hits else 'not written'}")
        failed = True
sys.exit(1 if failed else 0)
PY
form_fields() { python3 "$work/form-fields.py" "$1" "$2"; } # <form> <description>
# What ci / pr-title says about a description, by its own script at this commit.
pr_title_says() { # <description file>
  jq -n --rawfile b "$1" '{data:{repository:{pullRequest:{body:$b}}}}' > "$work/fields.json"
  python3 "$root/scripts/description-fields.py" PR "$work/fields.json" 2>&1
}
fields_pass() { # <what the fixture is> <description file>
  local says; says="$(pr_title_says "$2")"
  if [ "$(grep -c '^pass:' <<<"$says")" = 2 ] && ! grep -q 'not yet confirmed' <<<"$says"
  then ok "ci / pr-title's check warns about neither field on $1"
  else bad "ci / pr-title's check on $1"; printf '%s\n' "$says" | sed 's/^/        /'; fi
}
# The text under one heading of a description, up to the next heading.
section() { awk -v h="## $2" '$0 == h { f = 1; next } /^## / { f = 0 } f' "$1"; }

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
want="$(python3 "$checker" --root "$repo" --repo o/r --print-update-command 2>/dev/null)"
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
want="$(python3 "$checker" --root "$repo" --repo o/r --print-update-command 2>/dev/null)"
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
if grep -A2 -i "left in conflict by copier" <<<"$body" | grep -q "^- none"; then ok "the description says copier left no conflict"
else bad "description (resolved: none)"; printf '%s\n' "$body" | sed 's/^/        /'; fi
if [ "$(tail -n 1 <<<"$body")" = "Assisted-by: Claude:claude-test-1" ]; then ok "the description ends with the Assisted-by line it was given"
else bad "Assisted-by last line: '$(tail -n 1 <<<"$body")'"; fi
if grep -q "task.yml" <<<"$body"; then bad "an untouched local issue form is listed as changed"
else ok "a local issue form copier did not touch is not in the description"; fi
if grep -qi "wait" "$work/gh.log"; then bad "something waited on checks"; else ok "nothing waits on the branch's checks"; fi
# ── the description follows the form at the pinned tag (#856) ───────────
cp "$work/gh.log.body" "$work/clean.body"
fields_pass "the description of a clean update" "$work/clean.body"
checked="$(section "$work/clean.body" "What I checked myself")"
if grep -q "^Not a person's check" <<<"$checked" && ! grep -qi "no person" <<<"$checked" && tr '\n' ' ' <<<"$checked" | grep -q "conflict marker in a file the update changed" \
   && grep -q "reviewable lines" <<<"$checked" && grep -qi "plinth pin" <<<"$checked" \
   && grep -qF "own checks had not run" <<<"$checked"
then ok "What I checked myself says what the script checked (conflicts, size, pin), that it is not a person's check, and that the project's checks had not run"
else bad "What I checked myself"; printf '%s\n' "$checked" | sed 's/^/        /'; fi
if grep -qx 'Review: none (no review had run when this pull request opened)' "$work/clean.body"
then ok "the Review: line says no review has run"
else bad "the Review: line"; sed 's/^/        /' "$work/clean.body"; fi
form_url="https://raw.githubusercontent.com/coolbress/plinth-template/$target_ref/template/.github/PULL_REQUEST_TEMPLATE.md"
if curl -fsSL --retry 3 -o "$work/form.md" "$form_url" 2>/dev/null && [ -s "$work/form.md" ]; then
  if said="$(form_fields "$work/form.md" "$work/clean.body")"; then ok "the description writes every field of the form at $target_ref, in its order"
  else bad "the description against the form at $target_ref"; printf '%s\n' "$said" | sed 's/^/        /'; fi
  { cat "$work/form.md"; printf '\n## A field the form gained\n'; } > "$work/form-more.md"
  if said="$(form_fields "$work/form-more.md" "$work/clean.body")"; then bad "a form that gained a heading passes"
  else ok "a form that gained a heading the script does not write fails ($said)"; fi
  { cat "$work/form.md"; printf '\nRisk: <!-- a label -->\n'; } > "$work/form-label.md"
  if said="$(form_fields "$work/form-label.md" "$work/clean.body")"; then bad "a form that gained a label line passes"
  else ok "a form that gained a label line the script does not write fails ($said)"; fi
else
  bad "could not read the form at $form_url; cannot verify the description against it"
fi
printf '## How it was verified\n\n## What and why\n' > "$work/form-order.md"
if said="$(form_fields "$work/form-order.md" "$work/clean.body")"; then bad "a form in another order passes"
else ok "a form whose fields run in another order fails ($said)"; fi
printf '<!-- only a comment -->\n' > "$work/form-empty.md"
if form_fields "$work/form-empty.md" "$work/clean.body" >/dev/null; then bad "a form with no field passes"
else ok "a form with no field fails: nothing was compared"; fi
printf '## What and why\n\nSome prose outside a comment.\n' > "$work/form-prose.md"
if form_fields "$work/form-prose.md" "$work/clean.body" >/dev/null; then bad "a form line the test cannot read passes"
else ok "a form line that is neither a heading nor a label fails"; fi
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
# A resolution named for a file copier did not leave in conflict is refused
# before anything is committed (#556).
reset_logs
run --finish "$wt" --resolved AGENTS.md "template's side, on the person's word"
if [ "$rc" = 2 ] && ! grep -q "pr create" "$work/gh.log" && grep -q "AGENTS.md" <<<"$out" \
   && [ "$(git -C "$wt" rev-parse HEAD)" = "$base" ]
then ok "--resolved naming a file that was not in conflict is refused: nothing committed, nothing opened"
else bad "resolved for a non-conflict (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# A resolution stated while a marker is still there does not let it through:
# the refusal on anything unresolved stays the script's.
reset_logs
run --finish "$wt" --resolved CONTRIBUTING.md "template's side, on the person's word"
if [ "$rc" = 3 ] && ! grep -q "pr create" "$work/gh.log"
then ok "a stated resolution does not finish while the marker remains: exit 3, opens nothing"
else bad "resolved with markers left (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
printf '# Contributing\nresolved by hand\n' > "$wt/CONTRIBUTING.md"; git -C "$wt" add CONTRIBUTING.md
printf '# Agents\nedited after the update\n' > "$wt/AGENTS.md"
reset_logs
run --finish "$wt" --resolved CONTRIBUTING.md "repository's side, applied by the agent on the person's word"
body="$(cat "$work/gh.log.body" 2>/dev/null)"
if [ "$rc" = 0 ] && grep -q "pr create" "$work/gh.log" && grep -A2 -i "left in conflict by copier" <<<"$body" | grep -q "^- CONTRIBUTING.md" \
   && grep -A3 -i "left in conflict by copier" <<<"$body" | sed -n 4p | grep -q '^$'
then ok "once resolved, --finish opens the draft and the description names the file a person resolved, as its own list"
else bad "finish after resolving (rc=$rc)"; printf '%s\n%s\n' "$out" "$body" | sed 's/^/        /'; fi
if grep -qxF -- "- CONTRIBUTING.md: repository's side, applied by the agent on the person's word" <<<"$body"
then ok "the description says how each conflict was resolved: which side, on whose word"
else bad "resolution not in the description"; printf '%s\n' "$body" | sed 's/^/        /'; fi
fields_pass "the description of a conflict resolved through --finish" "$work/gh.log.body"
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

# ── a push refused for the workflow permission is the person's (#925) ──
# GitHub's two wordings: a classic token or OAuth app lacks the `workflow`
# scope; a fine-grained token or GitHub App lacks the `workflows` permission.
branch="chore/template-$target_ref"
for refusal in \
  "scope: ! [remote rejected] HEAD -> $branch (refusing to allow a Personal Access Token to create or update workflow \`.github/workflows/ci.yml\` without \`workflow\` scope)" \
  "permission: ! [remote rejected] HEAD -> $branch (refusing to allow a GitHub App to create or update workflow \`.github/workflows/ci.yml\` without \`workflows\` permission)"; do
  kind="${refusal%%:*}"; said="${refusal#*: }"
  fixture "wfpush$kind"; reset_logs
  base="$(git -C "$BARE" rev-parse main)"; wt="$(wt_of "wfpush$kind")"
  out="$(cd "$repo" && MOCK_PUSH_FAIL="$said" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" 2>&1)"; rc=$?
  if [ "$rc" = 5 ] && grep -qF "$said" <<<"$out" && grep -qF "separate terminal" <<<"$out" \
     && grep -qxF "  git -C $wt push origin HEAD:refs/heads/$branch" <<<"$out" \
     && grep -qxF "  $script --finish $wt" <<<"$out" && ! grep -qF "Run again" <<<"$out" \
     && ! grep -q "pr create" "$work/gh.log" && ! git -C "$BARE" rev-parse -q --verify "refs/heads/$branch" >/dev/null
  then ok "a push refused for the workflow $kind: exit 5, the branch, the push for a separate terminal and --finish after it, not the retry"
  else bad "workflow $kind refusal (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
done
# The person pushes from their own terminal; --finish under the same refused
# credential finds the branch at the commit and opens the pull request
# without pushing again (a push would be refused by the mock).
git -C "$wt" push -q origin "HEAD:refs/heads/$branch"
reset_logs
out="$(cd "$repo" && MOCK_PUSH_FAIL="$said" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --finish "$wt" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q "pr create" "$work/gh.log" && grep -qF "already on origin" <<<"$out" \
   && [ "$(git -C "$wt" rev-list --count "$base..HEAD")" = 1 ] && [ "$(git -C "$BARE" rev-parse main)" = "$base" ]
then ok "--finish after the person pushed opens the pull request without pushing again, on the same one commit"
else bad "finish after the person's push (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# Any other push failure is the generic retry.
fixture pushother; reset_logs
base="$(git -C "$BARE" rev-parse main)"; wt="$(wt_of pushother)"
out="$(cd "$repo" && MOCK_PUSH_FAIL="fatal: unable to access 'https://github.com/o/r/': Could not resolve host: github.com" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -qF "Run again: $script --finish $wt" <<<"$out" && grep -qF "Could not resolve host" <<<"$out" \
   && ! grep -qF "separate terminal" <<<"$out" && ! grep -q "pr create" "$work/gh.log"
then ok "any other push failure keeps the generic retry: exit 1, --finish again"
else bad "other push failure (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# ── a pin Dependabot raised is the one copier is given ──────────────────
fixture raised; reset_logs
raised="$(printf '%040d' 9)"
sed -i.bak "s/@$sha40/@$raised/" "$repo/.github/workflows/ci.yml" && rm "$repo/.github/workflows/ci.yml.bak"
git -C "$repo" commit -q -am "bump plinth" && git -C "$repo" push -q origin main
run --apply "$(git -C "$BARE" rev-parse main)"
if [ "$rc" = 0 ] && grep -q -- "--data plinth_sha=$raised$no_shared\$" "$work/uvx.log"; then ok "copier is given the pin the workflows carry today, not the one first rendered"
else bad "raised pin (rc=$rc): uvx got '$(cat "$work/uvx.log" 2>/dev/null)'"; fi

# ── the plinth pin: live by default, tested on a person's choice (#511) ─
tested="$(printf '%040d' 8)"
pin_api="$work/api-pin"
mkdir -p "$pin_api/repos/coolbress/plinth-template/contents" "$pin_api/repos/coolbress/plinth/compare"
printf 'plinth_sha:\n  type: str\n  default: "%s"\n' "$tested" | base64 | tr -d '\n' | jq -R '{encoding: "base64", content: .}' \
  > "$pin_api/repos/coolbress/plinth-template/contents/copier.yml?ref=$target_sha.json"
printf '{"status":"ahead","ahead_by":2}\n' > "$pin_api/repos/coolbress/plinth/compare/$sha40...$tested.json"
tag_names "$pin_api" "$target_sha"
pinrun() { # <fixture dir> <args...>: run with that API fixture
  local api="$1"; shift
  out="$(cd "$repo" && FLOOR_CHECK_API_DIR="$api" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" "$@" 2>&1)"; rc=$?
}
fixture pinplan; reset_logs
base="$(git -C "$BARE" rev-parse main)"
pinrun "$pin_api"
if [ "$rc" = 0 ] && grep -q "^Command: .*plinth_sha=$sha40$no_shared\$" <<<"$out" && grep -q "^With the tested pin: .*plinth_sha=$tested$no_shared\$" <<<"$out" \
   && grep -q "^Plinth pin: the workflows call $sha40; $target_ref was tested with $tested, 2 commit(s) newer" <<<"$out" \
   && grep -qF -- "--apply $base --plinth-pin live" <<<"$out" && grep -qF -- "--apply $base --plinth-pin tested" <<<"$out"
then ok "a tested pin newer than the live one: the plan prints the comparison, both lines and an --apply line for each choice"
else bad "plan with two pins (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# The tested pin is recommended, with what it gains, and offered first (#519).
if grep -q "^Recommended: move the plinth pin to $tested: this repository's checks then run the plinth commit $target_ref was tested with, 2 commit(s) newer than the one they run now" <<<"$out" \
   && [ "$(grep -n -- "--plinth-pin tested\$" <<<"$out" | cut -d: -f1)" -lt "$(grep -n -- "--plinth-pin live\$" <<<"$out" | cut -d: -f1)" ] \
   && grep -q "moving it to the one $target_ref was tested with (recommended):" <<<"$out"
then ok "a newer tested pin is recommended in one sentence on what it gains, and its --apply line comes first"
else bad "recommendation (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# A live pin newer than the tested one is kept: no recommendation, one line.
behind_api="$work/api-behind"; rm -rf "$behind_api"; cp -R "$pin_api" "$behind_api"
printf '{"status":"behind","behind_by":3}\n' > "$behind_api/repos/coolbress/plinth/compare/$sha40...$tested.json"
reset_logs; pinrun "$behind_api"
if [ "$rc" = 0 ] && ! grep -q "^Recommended:" <<<"$out" && ! grep -q -- "--plinth-pin" <<<"$out" && grep -q "never moved backwards" <<<"$out"
then ok "a live pin newer than the tested one: no recommendation, one --apply line, kept and said so"
else bad "plan, live ahead (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
reset_logs; pinrun "$work/api-none"
if [ "$rc" = 0 ] && ! grep -q "With the tested pin" <<<"$out" && ! grep -q -- "--plinth-pin" <<<"$out" && grep -q "^Plinth pin: .*was not read" <<<"$out"
then ok "the tested pin not read: the plan prints one line, one --apply line, and says it was not read"
else bad "plan with one pin (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

for choice in tested live default; do
  fixture "pin$choice"; reset_logs
  base="$(git -C "$BARE" rev-parse main)"
  if [ "$choice" = default ]; then pinrun "$pin_api" --apply "$base"; else pinrun "$pin_api" --apply "$base" --plinth-pin "$choice"; fi
  want_sha="$sha40"; [ "$choice" = tested ] && want_sha="$tested"
  body="$(cat "$work/gh.log.body" 2>/dev/null)"
  if [ "$rc" = 0 ] && grep -q -- "--vcs-ref $target_sha --data plinth_sha=$want_sha$no_shared\$" "$work/uvx.log"
  then ok "--apply $([ "$choice" = default ] && echo "without --plinth-pin" || echo "--plinth-pin $choice") runs copier with the $([ "$choice" = tested ] && echo tested || echo live) SHA"
  else bad "--plinth-pin $choice (rc=$rc): uvx got '$(cat "$work/uvx.log" 2>/dev/null)'"; printf '%s\n' "$out" | sed 's/^/        /'; fi
  if grep -qF -- "--plinth-pin $([ "$choice" = tested ] && echo tested || echo live)" <<<"$body" && grep -q "$sha40" <<<"$body" && grep -q "$tested" <<<"$body"
  then ok "the description says which pin was chosen ($choice) and names both SHAs"
  else bad "description for $choice"; printf '%s\n' "$body" | sed 's/^/        /'; fi
  if section "$work/gh.log.body" "What I checked myself" | grep -q "^- The plan's plinth pin line: .*$tested"
  then ok "What I checked myself carries the plan's plinth pin line ($choice)"
  else bad "the plan's pin line, $choice"; sed 's/^/        /' "$work/gh.log.body"; fi
done

# The live pin already the tested one: --plinth-pin tested runs the same
# line, and the description does not claim a move.
same_api="$work/api-same"; rm -rf "$same_api"; mkdir -p "$same_api/repos/coolbress/plinth-template/contents"
printf 'plinth_sha:\n  default: "%s"\n' "$sha40" | base64 | tr -d '\n' | jq -R '{encoding: "base64", content: .}' \
  > "$same_api/repos/coolbress/plinth-template/contents/copier.yml?ref=$target_sha.json"
tag_names "$same_api" "$target_sha"
fixture pinsame; reset_logs
pinrun "$same_api" --apply "$(git -C "$BARE" rev-parse main)" --plinth-pin tested
body="$(cat "$work/gh.log.body" 2>/dev/null)"
if [ "$rc" = 0 ] && grep -q -- "--data plinth_sha=$sha40$no_shared\$" "$work/uvx.log" && grep -q "The plinth pin: unchanged" <<<"$body" && ! grep -q "moved to" <<<"$body"
then ok "--plinth-pin tested when the live pin is the tested one: the same line runs, and the description says nothing moved"
else bad "--plinth-pin tested, equal (rc=$rc)"; printf '%s\n%s\n' "$out" "$body" | sed 's/^/        /'; fi

fixture pinunread; reset_logs
pinrun "$work/api-none" --apply "$(git -C "$BARE" rev-parse main)" --plinth-pin tested
if [ "$rc" = 1 ] && [ ! -e "$work/uvx.log" ] && grep -q "no update command with the tested pin" <<<"$out" && ! grep -q "pr create" "$work/gh.log"
then ok "--plinth-pin tested with the tested pin not read stops before copier, opens nothing"
else bad "--plinth-pin tested, unread (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
reset_logs
pinrun "$pin_api" --apply "$(git -C "$BARE" rev-parse main)" --plinth-pin newest
if [ "$rc" = 2 ] && [ ! -e "$work/uvx.log" ]; then ok "an unknown --plinth-pin value exits 2 before anything runs"
else bad "--plinth-pin newest (rc=$rc)"; fi
pinrun "$pin_api" --plinth-pin tested
if [ "$rc" = 2 ]; then ok "--plinth-pin without --apply exits 2: the choice is made where copier runs"
else bad "--plinth-pin on the plan (rc=$rc)"; fi

# ── the target tag names another commit than plinth was tested with (#519)
moved_api="$work/api-moved"; rm -rf "$moved_api"; cp -R "$pin_api" "$moved_api"
tag_names "$moved_api" "$(printf '%040d' 5)"
fixture tagmoved; reset_logs
pinrun "$moved_api"
if [ "$rc" = 1 ] && grep -q "$target_ref now names commit $(printf '%040d' 5), not $target_sha" <<<"$out" && ! grep -q -- "--apply" <<<"$out"
then ok "a moved target tag: the plan stops, names both commits, and offers no --apply line"
else bad "plan, moved tag (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
for choice in live tested; do
  reset_logs
  pinrun "$moved_api" --apply "$(git -C "$BARE" rev-parse main)" --plinth-pin "$choice"
  if [ "$rc" = 1 ] && [ ! -e "$work/uvx.log" ] && ! grep -q "pr create" "$work/gh.log" && grep -q "now names commit" <<<"$out"
  then ok "a moved target tag: --apply --plinth-pin $choice stops before copier, opens nothing"
  else bad "--apply, moved tag, $choice (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
  git -C "$repo" worktree remove --force "$(dirname "$repo")/$(basename "$repo")-template-$target_ref" 2>/dev/null
  git -C "$repo" branch -q -D "chore/template-$target_ref" 2>/dev/null
done
unread_api="$work/api-tag-unread"; rm -rf "$unread_api"; cp -R "$pin_api" "$unread_api"
rm "$unread_api/repos/coolbress/plinth-template/commits/$target_ref.json"
reset_logs
pinrun "$unread_api" --apply "$(git -C "$BARE" rev-parse main)"
if [ "$rc" = 1 ] && [ ! -e "$work/uvx.log" ] && grep -q "not verified that $target_ref still names $target_sha" <<<"$out"
then ok "the target tag's commit not read: --apply stops before copier (the line that runs is checked, fail closed)"
else bad "--apply, tag unread (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
git -C "$repo" worktree remove --force "$(dirname "$repo")/$(basename "$repo")-template-$target_ref" 2>/dev/null
git -C "$repo" branch -q -D "chore/template-$target_ref" 2>/dev/null

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
if tr '\n' ' ' < "$work/gh.log.body" | grep -q "conflict marker in a file the update changed"
then ok "the description scopes its no-.rej, no-marker claim to the files the update changed"
else bad "description claim"; sed 's/^/        /' "$work/gh.log.body"; fi

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
# Finished as printed, with no --resolved: the description claims no side
# and no one's word for it (Codex review on #558).
if grep -qxF -- "- CONTRIBUTING.md (how it was resolved was not stated)" "$work/gh.log.body" \
   && ! grep -qi "on a person's word" "$work/gh.log.body"
then ok "a conflict finished without --resolved is listed as not stated, with no claim of anyone's word"
else bad "unstated resolution"; sed 's/^/        /' "$work/gh.log.body" 2>/dev/null; fi

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
wt="$(wt_of rej)"
reset_logs
run --finish "$wt" --resolved CONTRIBUTING.md.rej "the template's side, applied by the agent on the person's word"
if [ "$rc" = 3 ] && ! grep -q "pr create" "$work/gh.log"
then ok "a stated resolution does not finish while the .rej remains: exit 3, opens nothing"
else bad ".rej resolved but present (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
rm "$wt/CONTRIBUTING.md.rej"
reset_logs
run --finish "$wt"
if [ "$rc" = 0 ] && grep -qxF -- "- CONTRIBUTING.md.rej (how it was resolved was not stated)" "$work/gh.log.body"
then ok "a resolution stated while the file was still in conflict is not kept: the side may change before it is resolved"
else bad ".rej finish (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; cat "$work/gh.log.body" 2>/dev/null | sed 's/^/        /'; fi

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

# ── the owner's shared templates (#726) ─────────────────────────────────
# The update carries what o/.github publishes, as the door's render did: an
# owner sharing issue forms gets `owner_has_issue_forms=true`, so the update
# writes no local form over them. A read that fails is not an answer: the
# plan and --apply stop before a worktree or copier.
shared_api="$work/api-shared"; rm -rf "$shared_api"; cp -R "$work/api-none" "$shared_api"
mkdir -p "$shared_api/repos/o/.github/contents/.github/ISSUE_TEMPLATE"
printf '{"visibility":"public"}\n' > "$shared_api/repos/o/.github.json"
printf '[{"name":"bug.yml"},{"name":"config.yml"}]\n' > "$shared_api/repos/o/.github/contents/.github/ISSUE_TEMPLATE.json"
printf 'name: Bug\ndescription: d\nbody:\n  - type: textarea\n' | base64 | tr -d '\n' | jq -R '{content: .}' \
  > "$shared_api/repos/o/.github/contents/.github/ISSUE_TEMPLATE/bug.yml.json"
fixture shared; reset_logs
git -C "$repo" rm -q -r .github/ISSUE_TEMPLATE && git -C "$repo" commit -q -m "no local forms" && git -C "$repo" push -q origin main
pinrun "$shared_api" --apply "$(git -C "$BARE" rev-parse main)"
if [ "$rc" = 0 ] && grep -q -- "--data plinth_sha=$sha40 --data owner_has_pr_template=false --data owner_has_issue_forms=true\$" "$work/uvx.log"
then ok "an owner whose public .github shares issue forms, a repository with none of its own: owner_has_issue_forms=true"
else bad "shared forms (rc=$rc): uvx got '$(cat "$work/uvx.log" 2>/dev/null)'"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# The repository's own form already replaces the shared set: true would have
# copier delete it. The plan reads the base's own templates as --apply does,
# so the two give the same line.
fixture ownforms; reset_logs
pinrun "$shared_api"
planned="$(sed -n 's/^Command:    uvx //p' <<<"$out")"
if [ "$rc" = 0 ] && grep -q -- "--data owner_has_issue_forms=false\$" <<<"$planned" && grep -q "this repository's own .github/ISSUE_TEMPLATE replaces them" <<<"$out"
then ok "a repository with its own forms: the plan passes false, keeping them, and says why"
else bad "plan, own forms (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
reset_logs; pinrun "$shared_api" --apply "$(git -C "$BARE" rev-parse main)"
if [ "$rc" = 0 ] && [ "$(cat "$work/uvx.log" 2>/dev/null)" = "$planned" ]
then ok "and --apply runs the very line the plan printed"
else bad "apply, own forms (rc=$rc): uvx got '$(cat "$work/uvx.log" 2>/dev/null)', plan '$planned'"; fi
unread_owner="$work/api-owner-unread"; rm -rf "$unread_owner"; cp -R "$shared_api" "$unread_owner"
printf 'not json\n' > "$unread_owner/repos/o/.github/contents/.github/ISSUE_TEMPLATE/bug.yml.json"
fixture ownerunread; reset_logs
pinrun "$unread_owner"
if [ "$rc" = 1 ] && grep -q "cannot read whether o/.github publishes shared templates" <<<"$out" && ! grep -q "^Command:" <<<"$out"
then ok "a shared form that could not be read: the plan prints no command and says what was not read"
else bad "plan, owner unread (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
reset_logs
pinrun "$unread_owner" --apply "$(git -C "$BARE" rev-parse main)"
if [ "$rc" = 1 ] && [ ! -e "$work/uvx.log" ] && ! grep -q "pr create" "$work/gh.log"
then ok "and --apply stops before copier runs, opening nothing"
else bad "apply, owner unread (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# ── the owner's shared templates are gone (#770) ────────────────────────
# Made while o/.github shared both, so the answers record true and the
# repository holds neither; o/.github has none now (api-none answers 404).
# copier 9.18.2 was measured to render both and record false on an update
# with the answers changed, at a newer tag and at the same tag, without a
# conflict; this mock copier does not act that out, so these cases check the
# line plinth gives it and what the plan says.
gone_fixture() { # <name> [recorded tag]
  fixture "$1"
  git -C "$repo" rm -q -r .github/ISSUE_TEMPLATE
  sed -i.bak "s/^_commit: .*/_commit: ${2:-$target_ref}/" "$repo/.copier-answers.yml" && rm "$repo/.copier-answers.yml.bak"
  printf 'owner_has_issue_forms: true\nowner_has_pr_template: true\n' >> "$repo/.copier-answers.yml"
  git -C "$repo" commit -q -am "made with the owner's shared templates" && git -C "$repo" push -q origin main
}
gone_fixture gonecurrent; reset_logs
run
planned="$(sed -n 's/^Command:    uvx //p' <<<"$out")"
if [ "$rc" = 0 ] && grep -q -- "--vcs-ref $target_sha .*--data owner_has_pr_template=false --data owner_has_issue_forms=false\$" <<<"$planned" \
   && grep -q "owner_has_pr_template: true, but o/.github no longer publishes a pull-request template" <<<"$out" \
   && grep -q "owner_has_issue_forms: true, but o/.github no longer publishes issue forms" <<<"$out"
then ok "at the target tag, recorded true and the owner's templates gone: the plan names the change and gives a line"
else bad "plan, owner's templates gone at the target tag (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
reset_logs; run --apply "$(git -C "$BARE" rev-parse main)"
if [ "$rc" = 0 ] && [ "$(cat "$work/uvx.log" 2>/dev/null)" = "$planned" ] && grep -q "pr create" "$work/gh.log" \
   && grep -qF -- "--title chore(template): re-render plinth-template $target_ref for the owner's templates" "$work/gh.log" \
   && grep -q "^Re-renders this repository at plinth-template $target_ref" "$work/gh.log.body"
then ok "and --apply runs that line and opens a pull request that says it re-renders, not updates"
else bad "apply, owner's templates gone at the target tag (rc=$rc): uvx got '$(cat "$work/uvx.log" 2>/dev/null)'"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# The re-render has its own branch: the update that reached the tag may have
# left chore/template-<tag> on origin.
if git -C "$BARE" rev-parse -q --verify "refs/heads/chore/template-$target_ref-owner-templates" >/dev/null
then ok "the re-render pushes its own branch, not the tag's update branch"
else bad "re-render branch: $(git -C "$BARE" branch --format='%(refname:short)' | tr '\n' ' ')"; fi
# Its own forms and pull-request template already replace the owner's: a
# recorded true changes nothing at the target tag.
gone_fixture ownboth; reset_logs
mkdir -p "$repo/.github/ISSUE_TEMPLATE"; printf 'name: task\n' > "$repo/.github/ISSUE_TEMPLATE/task.yml"
printf '## What\n' > "$repo/.github/PULL_REQUEST_TEMPLATE.md"
git -C "$repo" add -A && git -C "$repo" commit -q -m "own templates" && git -C "$repo" push -q origin main
run
if [ "$rc" = 1 ] && grep -q "nothing to update" <<<"$out" && ! grep -q "^Command:" <<<"$out"
then ok "at the target tag, recorded true and the repository holding its own: nothing to update"
else bad "plan, own templates at the target tag (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# The owner still shares both: at the target tag nothing changes.
both_api="$work/api-shared-both"; rm -rf "$both_api"; cp -R "$shared_api" "$both_api"
printf '{"content":""}\n' > "$both_api/repos/o/.github/contents/.github/PULL_REQUEST_TEMPLATE.md.json"
gone_fixture stillshared; reset_logs
pinrun "$both_api"
if [ "$rc" = 1 ] && grep -q "nothing to update" <<<"$out" && ! grep -q "^Command:" <<<"$out" && ! grep -q "no longer publishes" <<<"$out"
then ok "at the target tag, recorded true and the owner still sharing both: nothing to update"
else bad "plan, owner still shares (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
reset_logs; pinrun "$both_api" --apply "$(git -C "$BARE" rev-parse main)"
if [ "$rc" = 1 ] && [ ! -e "$work/uvx.log" ] && ! grep -q "pr create" "$work/gh.log"
then ok "and --apply runs no copier and opens nothing"
else bad "apply, owner still shares (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# Forms still shared, the pull-request template gone: only that answer moves.
gone_fixture halfgone; reset_logs
pinrun "$shared_api"
planned="$(sed -n 's/^Command:    uvx //p' <<<"$out")"
if [ "$rc" = 0 ] && grep -q -- "--data owner_has_pr_template=false --data owner_has_issue_forms=true\$" <<<"$planned" \
   && grep -q "owner_has_pr_template: true, but o/.github no longer publishes" <<<"$out" && ! grep -q "owner_has_issue_forms: true, but" <<<"$out"
then ok "the forms still shared and the pull-request template gone: only that answer turns false, and the plan names only it"
else bad "plan, half gone (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# Behind the target tag the update runs anyway; the plan still names the change.
gone_fixture gonebehind v1.0.0; reset_logs
run
if [ "$rc" = 0 ] && grep -q "Command:.*--data owner_has_pr_template=false --data owner_has_issue_forms=false\$" <<<"$out" \
   && grep -q "owner_has_issue_forms: true, but o/.github no longer publishes issue forms" <<<"$out"
then ok "behind the target tag, recorded true and the owner's templates gone: the plan names the change"
else bad "plan, owner's templates gone behind the target tag (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# ── the glossary follows the template's name (#714) ─────────────────────
# An untouched instance whose /domain-modeling wrote CONTEXT.md: an update to
# a template naming GLOSSARY.md moves it, content unchanged, and says so; one
# to a template still naming CONTEXT.md leaves it.
glossary_fixture() { # <name>
  fixture "$1"
  printf '# Glossary\n\n**Order**: what a customer asked for.\n' > "$repo/CONTEXT.md"
  git -C "$repo" add CONTEXT.md && git -C "$repo" commit -q -m glossary && git -C "$repo" push -q origin main
}
glossary_fixture glossary; reset_logs
before="$(git -C "$repo" rev-parse HEAD:CONTEXT.md)"
out="$(cd "$repo" && MOCK_COPIER=glossary PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$(git -C "$BARE" rev-parse main)" 2>&1)"; rc=$?
wt="$(wt_of glossary)"
if [ "$rc" = 0 ] && [ "$(git -C "$wt" rev-parse HEAD:GLOSSARY.md 2>/dev/null)" = "$before" ] \
   && ! git -C "$wt" cat-file -e HEAD:CONTEXT.md 2>/dev/null
then ok "CONTEXT.md is moved to GLOSSARY.md with its content unchanged, in the update's one commit"
else bad "glossary rename (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
if [ "$(git -C "$wt" diff --name-status -M HEAD~1 HEAD -- CONTEXT.md GLOSSARY.md)" = "$(printf 'R100\tCONTEXT.md\tGLOSSARY.md')" ]
then ok "git records it as a rename (R100), so the file's history follows"
else bad "not a rename: $(git -C "$wt" diff --name-status -M HEAD~1 HEAD)"; fi
body="$(cat "$work/gh.log.body" 2>/dev/null)"
if grep -qxF -- "- CONTEXT.md -> GLOSSARY.md" <<<"$body" && ! grep -q "^- GLOSSARY.md" <<<"$body" \
   && grep -A2 -i "left in conflict by copier" <<<"$body" | grep -q "^- none"
then ok "the description lists the rename apart from copier's merge, and no conflict"
else bad "glossary description"; printf '%s\n' "$body" | sed 's/^/        /'; fi
# Must not rename: the template still names CONTEXT.md (an update to an older tag).
glossary_fixture oldname; reset_logs
run --apply "$(git -C "$BARE" rev-parse main)"
if [ "$rc" = 0 ] && git -C "$(wt_of oldname)" cat-file -e HEAD:CONTEXT.md 2>/dev/null \
   && ! git -C "$(wt_of oldname)" cat-file -e HEAD:GLOSSARY.md 2>/dev/null && ! grep -q "Renamed" "$work/gh.log.body"
then ok "a template that does not name GLOSSARY.md leaves CONTEXT.md where it is"
else bad "renamed without the template's new name (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# Must not overwrite: a GLOSSARY.md the repository already has.
glossary_fixture both; reset_logs
printf 'mine\n' > "$repo/GLOSSARY.md"; git -C "$repo" add GLOSSARY.md && git -C "$repo" commit -q -m both && git -C "$repo" push -q origin main
out="$(cd "$repo" && MOCK_COPIER=glossary PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$(git -C "$BARE" rev-parse main)" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && [ "$(git -C "$(wt_of both)" show HEAD:GLOSSARY.md 2>/dev/null)" = mine ] \
   && git -C "$(wt_of both)" cat-file -e HEAD:CONTEXT.md 2>/dev/null \
   && grep -qF -- "- CONTEXT.md: GLOSSARY.md already exists" "$work/gh.log.body"
then ok "an existing GLOSSARY.md is kept, CONTEXT.md too, and the description says why it was not renamed"
else bad "both files (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; cat "$work/gh.log.body" 2>/dev/null | sed 's/^/        /'; fi

# Must stay tracked: a .gitignore that matches the new name (Codex review on #740).
glossary_fixture ignored; reset_logs
printf 'GLOSSARY.md\n' > "$repo/.gitignore"; git -C "$repo" add .gitignore && git -C "$repo" commit -q -m ignore && git -C "$repo" push -q origin main
before="$(git -C "$repo" rev-parse HEAD:CONTEXT.md)"
out="$(cd "$repo" && MOCK_COPIER=glossary PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$(git -C "$BARE" rev-parse main)" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && [ "$(git -C "$(wt_of ignored)" rev-parse HEAD:GLOSSARY.md 2>/dev/null)" = "$before" ] \
   && ! git -C "$(wt_of ignored)" cat-file -e HEAD:CONTEXT.md 2>/dev/null
then ok "a .gitignore matching GLOSSARY.md: the moved file is still committed, content unchanged"
else bad "ignored destination (rc=$rc): $(git -C "$(wt_of ignored)" show --stat --format= HEAD 2>/dev/null | tr '\n' ' ')"; fi
# Must not claim "unchanged": a person edits GLOSSARY.md while another file
# waits in conflict, then finishes (Codex review on #740).
glossary_fixture edited; reset_logs
out="$(cd "$repo" && MOCK_COPIER=conflict MOCK_GLOSSARY=1 PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$(git -C "$BARE" rev-parse main)" 2>&1)"; rc=$?
wt="$(wt_of edited)"
printf 'theirs\n' > "$wt/CONTRIBUTING.md"; git -C "$wt" add CONTRIBUTING.md
printf '**Refund**: money returned.\n' >> "$wt/GLOSSARY.md"
reset_logs; run --finish "$wt" --resolved CONTRIBUTING.md "the template's side"
body="$(cat "$work/gh.log.body" 2>/dev/null)"
if [ "$rc" = 0 ] && grep -A3 "Edited by a person" <<<"$body" | grep -qxF -- "- GLOSSARY.md" \
   && grep -qF -- "- CONTEXT.md -> GLOSSARY.md (edited after the move" <<<"$body"
then ok "a glossary edited after the move is listed as a person's edit, and the rename line says so"
else bad "edited after the move (rc=$rc)"; printf '%s\n' "$body" | sed 's/^/        /'; fi

# ── two plinth pins (#793) ──────────────────────────────────────────────
# ci.yml raised by hand, label.yml left at an ancestor of its commit: the
# plan carries the ci job's commit and says label.yml moves; the apply
# checks after copier that every plinth uses: names it, and the description
# lists the move. label.yml newer than ci.yml: the plan stops with the fix.
old_pin="$(printf '%040d' 1)"
pins_api() { # <dir> <status of label.yml's commit against the ci job's>
  rm -rf "$1"; cp -R "$FLOOR_CHECK_API_DIR" "$1"; mkdir -p "$1/repos/coolbress/plinth/compare"
  printf '{"status":"%s"}\n' "$2" > "$1/repos/coolbress/plinth/compare/$sha40...$old_pin.json"
}
two_fixture() { # <name>
  fixture "$1"
  printf 'jobs:\n  label:\n    uses: coolbress/plinth/.github/workflows/pr-label.yml@%s\n' "$old_pin" > "$repo/.github/workflows/label.yml"
  git -C "$repo" add -A && git -C "$repo" commit -q -m label && git -C "$repo" push -q origin main
}
pins_api "$work/api-behind" behind; pins_api "$work/api-ahead" ahead
two_fixture pins-behind; reset_logs
want="$(cd "$repo" && FLOOR_CHECK_API_DIR="$work/api-behind" python3 "$checker" --root "$repo" --repo o/r --print-update-command 2>/dev/null)"
out="$(cd "$repo" && FLOOR_CHECK_API_DIR="$work/api-behind" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -qF "Command:    $want" <<<"$out" && grep -qF -- "--data plinth_sha=$sha40" <<<"$want"
then ok "label.yml at an ancestor of ci.yml's commit: the plan carries ci.yml's commit"
else bad "plan, ancestor (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
if grep -qxF "Moves:      label.yml from $old_pin to $sha40, the commit the ci job calls ($old_pin is an ancestor of it)" <<<"$out" \
   && ! grep -q "^moves: " <<<"$out"
then ok "the plan says which file moves from which commit to which, once"
else bad "plan, Moves line"; printf '%s\n' "$out" | sed 's/^/        /'; fi
reset_logs
out="$(cd "$repo" && MOCK_PINS=move FLOOR_CHECK_API_DIR="$work/api-behind" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$(git -C "$BARE" rev-parse main)" 2>&1)"; rc=$?
wt="$(wt_of pins-behind)"; body="$(cat "$work/gh.log.body" 2>/dev/null)"
if [ "$rc" = 0 ] && [ "$(cat "$work/uvx.log" 2>/dev/null)" = "${want#uvx }" ] \
   && grep -q "pr-label.yml@$sha40" "$wt/.github/workflows/label.yml" && grep -q "python-ci.yml@$sha40" "$wt/.github/workflows/ci.yml"
then ok "the apply runs that line, and label.yml ends at ci.yml's commit, ci.yml unmoved"
else bad "apply, ancestor (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
if grep -qxF -- "- label.yml from $old_pin to $sha40, the commit the ci job calls ($old_pin is an ancestor of it)" <<<"$body"
then ok "the description lists the move"
else bad "description, move"; printf '%s\n' "$body" | sed 's/^/        /'; fi
two_fixture pins-stale; reset_logs
out="$(cd "$repo" && FLOOR_CHECK_API_DIR="$work/api-behind" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$(git -C "$BARE" rev-parse main)" 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -qF "  .github/workflows/label.yml calls $old_pin, not $sha40" <<<"$out" \
   && ! grep -q "pr create" "$work/gh.log" && ! git -C "$BARE" rev-parse -q --verify "refs/heads/chore/template-$target_ref" >/dev/null
then ok "copier leaving label.yml unmoved: the apply stops, names it, pushes and opens nothing"
else bad "apply, stale pin (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# A workflow whose `run: |` block writes a plinth uses: line as text (review
# on #798): not a pin, so it does not stop the apply, while a real stale pin
# beside it still does.
two_fixture pins-runblock; reset_logs
printf 'jobs:\n  t:\n    runs-on: ubuntu-latest\n    steps:\n      - run: |\n          cat > fixture.yml <<EOF\n          uses: coolbress/plinth/.github/workflows/pr-label.yml@%s\n          EOF\n' "$old_pin" > "$repo/.github/workflows/fixture.yml"
git -C "$repo" add -A && git -C "$repo" commit -q -m runblock && git -C "$repo" push -q origin main
out="$(cd "$repo" && MOCK_PINS=move FLOOR_CHECK_API_DIR="$work/api-behind" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$(git -C "$BARE" rev-parse main)" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q "pr create" "$work/gh.log" && grep -q "@$old_pin" "$(wt_of pins-runblock)/.github/workflows/fixture.yml"
then ok "a plinth uses: inside a run: | block is text, not a pin: the apply goes on"
else bad "apply, run block (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# The compare read at the plan but not at the apply (review on #798): the
# apply stops before copier, never runs with the post-copier check skipped.
two_fixture pins-unread; reset_logs
out="$(cd "$repo" && MOCK_PINS=move FLOOR_CHECK_API_DIR="$FLOOR_CHECK_API_DIR" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$(git -C "$BARE" rev-parse main)" 2>&1)"; rc=$?
if [ "$rc" = 1 ] && [ ! -e "$work/uvx.log" ] && grep -q "workflow pins disagree" <<<"$out" \
   && grep -q "more than one commit and the update cannot carry one" <<<"$out" && ! grep -q "pr create" "$work/gh.log"
then ok "two pins and the compare unread at the apply: it stops before copier, names why, opens nothing"
else bad "apply, compare unread (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
two_fixture pins-ahead; reset_logs
out="$(cd "$repo" && FLOOR_CHECK_API_DIR="$work/api-ahead" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -q "workflow pins disagree" <<<"$out" && grep -qxF "  label.yml: coolbress/plinth at $old_pin" <<<"$out" \
   && grep -qxF "  ci.yml: coolbress/plinth at $sha40" <<<"$out" && grep -q "^  sed -i.bak .*label\.yml" <<<"$out" \
   && ! grep -q "^Command:" <<<"$out"
then ok "label.yml newer than ci.yml: the plan stops, naming both files and the fix line"
else bad "plan, label newer (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# The pins agree: the plan is the one it was, with no Moves line.
fixture pins-agree; reset_logs
printf 'jobs:\n  label:\n    uses: coolbress/plinth/.github/workflows/pr-label.yml@%s\n' "$sha40" > "$repo/.github/workflows/label.yml"
git -C "$repo" add -A && git -C "$repo" commit -q -m label && git -C "$repo" push -q origin main
run
if [ "$rc" = 0 ] && ! grep -qE "^Moves:|workflow pins disagree" <<<"$out"; then ok "ci.yml and label.yml at one commit: no Moves line, no stop"
else bad "plan, pins agree (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# ── over ci / diff-size's limit (#795) ───────────────────────────────────
# The update counts its own diff before pushing, as ci / diff-size does with
# the ci job's inputs; over the limit it pushes nothing and proposes a split.
big() { # <fixture> [env...]: --apply with MOCK_BIG; sets out, rc, wt
  local name="$1"; shift
  out="$(cd "$repo" && env MOCK_BIG=1 "$@" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$(git -C "$BARE" rev-parse main)" 2>&1)"; rc=$?
  wt="$(wt_of "$name")"
}
fixture big-split; reset_logs; big big-split
# Counted as ci / diff-size counts: CONTRIBUTING.md (docs) excluded; the
# forms, the source, the answers file and AGENTS.md's one line are not.
if [ "$rc" = 4 ] && grep -q "^Over the limit: 422 reviewable lines, against the limit of 400" <<<"$out" \
   && ! git -C "$BARE" rev-parse -q --verify "refs/heads/chore/template-$target_ref" >/dev/null && ! grep -q "pr create" "$work/gh.log"
then ok "over the limit: exit 4, the count named, nothing pushed, no pull request"
else bad "over the limit (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
first="$(sed -n '/^Proposed split/,/^This update keeps/p' <<<"$out")"
rest="$(sed -n '/^This update keeps/,/^$/p' <<<"$out")"
if grep -qxF "  .github/ISSUE_TEMPLATE/bug.yml" <<<"$first" && grep -q "first a pull request with these paths (" <<<"$first" \
   && grep -qF "  .copier-answers.yml (" <<<"$rest" && ! grep -q "copier-answers" <<<"$first"
then ok "the split puts the issue forms first and keeps .copier-answers.yml in this update"
else bad "split paths"; printf '%s\n' "$out" | sed 's/^/        /'; fi
if git -C "$wt" log -1 --format=%s | grep -q "^chore(template): update plinth-template" && [ -z "$(git -C "$wt" status --porcelain)" ]
then ok "the update is a local commit, the worktree clean, so the default branch can be merged into it later"
else bad "local commit"; fi
# Run the proposal as printed: the first part, merged into main, then this one.
( set -e; while IFS= read -r l; do eval "$l"; done < <(sed -n '/^To make the first/,/^then open/p' <<<"$out" | sed -n 's/^  \(git .*\)$/\1/p') ) >/dev/null 2>&1
p1="$wt-part-1"
if [ "$(git -C "$p1" diff --name-only HEAD~1 HEAD)" = ".github/ISSUE_TEMPLATE/bug.yml" ] \
   && git -C "$BARE" rev-parse -q --verify "refs/heads/chore/template-$target_ref-part-1" >/dev/null
then ok "run as printed, the first part carries the forms alone, pushed to its own branch"
else bad "first part"; git -C "$p1" show --stat HEAD 2>&1 | sed 's/^/        /'; fi
git -C "$BARE" update-ref refs/heads/main "$(git -C "$p1" rev-parse HEAD)"   # the first part is merged
reset_logs
( while IFS= read -r l; do eval "$l"; done < <(sed -n '/^Once it is merged/,/^$/p' <<<"$out" | sed -n 's/^  \(git .*\)$/\1/p') ) >/dev/null 2>&1
out="$(cd "$repo" && PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --finish "$wt" 2>&1)"; rc=$?
body="$(cat "$work/gh.log.body" 2>/dev/null)"
if [ "$rc" = 0 ] && grep -q "pr create" "$work/gh.log" && grep -qF "counted here before pushing: 42 reviewable lines, within the limit of 400" <<<"$body" \
   && ! grep -q "bug.yml" <<<"$body"
then ok "after the first part is merged, --finish counts from the new merge base and opens the rest"
else bad "second part (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; printf '%s\n' "$body" | sed 's/^/        /'; fi

# Split three ways: each proposal names a branch and worktree not yet used.
fixture big-three; reset_logs; big big-three MOCK_BIG=three
part() { # <n>: run the printed first-part lines, merge that part into main, follow it, --finish
  ( while IFS= read -r l; do eval "$l"; done < <(sed -n '/^To make the first/,/^then open/p' <<<"$out" | sed -n 's/^  \(git .*\)$/\1/p') ) >/dev/null 2>&1
  git -C "$BARE" update-ref refs/heads/main "$(git -C "$wt-part-$1" rev-parse HEAD 2>/dev/null)" 2>/dev/null
  ( while IFS= read -r l; do eval "$l"; done < <(sed -n '/^Once it is merged/,/^$/p' <<<"$out" | sed -n 's/^  \(git .*\)$/\1/p') ) >/dev/null 2>&1
  reset_logs; out="$(cd "$repo" && PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --finish "$wt" 2>&1)"; rc=$?
}
first_cmd="$(grep -m1 'worktree add' <<<"$out")"
part 1
if [ "$rc" = 4 ] && grep -q "worktree add --no-track -b chore/template-$target_ref-part-2 " <<<"$out" && grep -q -- "-part-1 " <<<"$first_cmd"
then ok "a split three ways: after the first part, the next proposal names part-2, not the part-1 still there"
else bad "three-way split, second proposal (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
part 2
if [ "$rc" = 0 ] && grep -q "pr create" "$work/gh.log" && [ "$(git -C "$wt-part-2" diff --name-only HEAD~1 HEAD 2>/dev/null | wc -l | tr -d ' ')" = 1 ]
then ok "and run as printed, the second part is made and the rest opens"
else bad "three-way split, end (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
fixture big-anyway; reset_logs; big big-anyway
reset_logs; run --finish "$wt" --over-limit
body="$(cat "$work/gh.log.body" 2>/dev/null)"
if [ "$rc" = 0 ] && grep -q "pr create" "$work/gh.log" && grep -qF "422 reviewable lines, over the limit of 400" <<<"$body" \
   && grep -qF "Opened as it is on \`--over-limit\`" <<<"$body"
then ok "--over-limit opens it as it is, and the description says it is over"
else bad "--over-limit (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# Refused for the workflow permission on --over-limit: the printed --finish
# line carries --over-limit and --assisted-by, or run as printed it stops at
# the split again and the description loses its last line (#925).
fixture big-refused; reset_logs; big big-refused
reset_logs
out="$(cd "$repo" && MOCK_PUSH_FAIL="! [remote rejected] HEAD -> chore/template-$target_ref (refusing to allow an OAuth App to create or update workflow \`.github/workflows/ci.yml\` without \`workflow\` scope)" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --finish "$wt" --over-limit --assisted-by "Claude:claude-test-1" 2>&1)"; rc=$?
if [ "$rc" = 5 ] && grep -qxF "  $script --finish $wt --over-limit --assisted-by Claude:claude-test-1" <<<"$out"
then ok "the hand-off's --finish line keeps --over-limit and --assisted-by"
else bad "hand-off flags (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
git -C "$wt" push -q origin "HEAD:refs/heads/chore/template-$target_ref"
reset_logs; run --finish "$wt" --over-limit --assisted-by "Claude:claude-test-1"
if [ "$rc" = 0 ] && grep -q "pr create" "$work/gh.log" && tail -1 "$work/gh.log.body" | grep -qxF "Assisted-by: Claude:claude-test-1"
then ok "run as printed after the person's push, the over-limit update opens with its Assisted-by line"
else bad "hand-off run as printed (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
run --apply "$(git -C "$BARE" rev-parse main)" --over-limit
if [ "$rc" = 2 ]; then ok "--over-limit is for --finish only, after the count was read"; else bad "--over-limit with --apply (rc=$rc)"; fi

# The project's own inputs: its diff-size-exclude leaves out the forms, its
# max-diff-lines of 0 measures only, an expression is not read.
own() { # <fixture> <with: lines>
  fixture "$1"
  printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n    with:\n%b\n' "$sha40" "$2" > "$repo/.github/workflows/ci.yml"
  git -C "$repo" add -A && git -C "$repo" commit -q -m own && git -C "$repo" push -q origin main
  reset_logs; big "$1"; body="$(cat "$work/gh.log.body" 2>/dev/null)"
}
own big-exclude '      diff-size-exclude: "*.md .github/ISSUE_TEMPLATE/*"'
if [ "$rc" = 0 ] && grep -qF "42 reviewable lines, within the limit of 400 (excluded: \`*.md .github/ISSUE_TEMPLATE/*\`)" <<<"$body"
then ok "a project's own diff-size-exclude is the one counted with"
else bad "own exclude (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
own big-zero '      max-diff-lines: 0'
if [ "$rc" = 0 ] && grep -qF "422 reviewable lines; max-diff-lines is 0, so it is measured, not enforced" <<<"$body"
then ok "max-diff-lines: 0: counted, never a stop"
else bad "max 0 (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
own big-expr '      max-diff-lines: ${{ vars.MAX }}'
if [ "$rc" = 0 ] && grep -qF "was not counted here before pushing (the ci job passes max-diff-lines in a form not read" <<<"$body"
then ok "an expression is not read: no stop, and the description says it was not counted"
else bad "expression (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
own big-limit '      max-diff-lines: 500'
if [ "$rc" = 0 ] && grep -qF "422 reviewable lines, within the limit of 500" <<<"$body"
then ok "a project's own max-diff-lines is the limit counted against"
else bad "own max (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# ── the installed plinth against the newest template tag (#843) ─────────
# The person's plugin can be older than the latest release: the plan would
# target an old tag and report nothing to do. Newer tags are literals far from
# any real pin, so these stay true across a pin raise.
release_says() { # <fixture dir> <release tag> <template_ref at that tag>
  mkdir -p "$1/repos/coolbress/plinth/releases" "$1/repos/coolbress/plinth/contents/scripts"
  printf '{"tag_name":"%s"}\n' "$2" > "$1/repos/coolbress/plinth/releases/latest.json"
  ref_says "$1" "$2" "$3"
}
ref_says() { # <fixture dir> <plinth ref> <template_ref at that ref>
  mkdir -p "$1/repos/coolbress/plinth/contents/scripts"
  printf '{"content":"%s"}\n' "$(printf 'template_ref="%s"\n' "$3" | base64 | tr -d '\n')" \
    > "$1/repos/coolbress/plinth/contents/scripts/new-project.sh?ref=$2.json"
}
cat > "$work/bin/claude" <<'MOCK'
#!/usr/bin/env bash
printf 'claude %s\n' "$*" >> "$GH_LOG"
MOCK
chmod +x "$work/bin/claude"
skew_steps='  claude plugin marketplace update plinth
  claude plugin update plinth@plinth
  /reload-plugins (or start a new session)
  /plinth:template-update'
stopped_for() { # <description> <newer tag named> <what names it>: rc, words, order, nothing written
  if [ "$rc" = 1 ] && grep -qF "this plinth targets template $target_ref, but $2 is out ($3)" <<<"$out" \
     && grep -qF -- "$skew_steps" <<<"$out" && grep -q "Nothing has been written" <<<"$out" \
     && [ ! -e "$(wt_of "$fx")" ] && [ ! -e "$work/uvx.log" ] \
     && ! git -C "$repo" rev-parse -q --verify "refs/heads/chore/template-$target_ref" >/dev/null \
     && ! grep -q '^claude ' "$work/gh.log"
  then ok "$1"
  else bad "$1 (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
}
goes_on() { # <description>: the plan is printed
  if [ "$rc" = 0 ] && grep -qF "Command:" <<<"$out" && ! grep -q "claude plugin" <<<"$out"
  then ok "$1"
  else bad "$1 (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
}
newer_api="$work/api-newer"; tag_names "$newer_api" "$target_sha"; release_says "$newer_api" v98.0.0 v99.0.0
fx=skew-older; fixture "$fx"; reset_logs
FLOOR_CHECK_API_DIR="$newer_api" run
stopped_for "an installed target older than the latest release's stops the plan: the commands in order, nothing written, none of them run" \
  v99.0.0 "the latest plinth release, v98.0.0"
base="$(git -C "$BARE" rev-parse main)"; reset_logs
FLOOR_CHECK_API_DIR="$newer_api" run --apply "$base"
stopped_for "--apply on the same older target stops the same way, before the worktree" v99.0.0 "the latest plinth release, v98.0.0"
# What the person met: on the installed target already, so "nothing to do".
fx=skew-current; fixture "$fx"; reset_logs
sed -i.bak "s/^_commit: .*/_commit: $target_ref/" "$repo/.copier-answers.yml" && rm "$repo/.copier-answers.yml.bak"
git -C "$repo" commit -q -am at-target && git -C "$repo" push -q origin main
FLOOR_CHECK_API_DIR="$newer_api" run
stopped_for "a project already on the installed target is told about the newer tag, not that there is nothing to do" \
  v99.0.0 "the latest plinth release, v98.0.0"
# The project itself is newer than the plugin.
fx=skew-ahead; fixture "$fx"; reset_logs
sed -i.bak "s/^_commit: .*/_commit: v99.0.0/" "$repo/.copier-answers.yml" && rm "$repo/.copier-answers.yml.bak"
git -C "$repo" commit -q -am ahead && git -C "$repo" push -q origin main
FLOOR_CHECK_API_DIR="$newer_api" run
stopped_for "a project ahead of the installed target gets the same stop" v99.0.0 "the latest plinth release, v98.0.0"
# The pin alone can be newer than the release.
pin_api="$work/api-skew-pin"; tag_names "$pin_api" "$target_sha"; release_says "$pin_api" v98.0.0 "$target_ref"
ref_says "$pin_api" "$sha40" v99.0.0
fx=skew-pin; fixture "$fx"; reset_logs
FLOOR_CHECK_API_DIR="$pin_api" run
stopped_for "the CI pin's tag newer than the installed target stops too, and is the one named" \
  v99.0.0 "the tag this repository's plinth pin $sha40 was tested with"
# Updating the plugin cannot bring a tag no release carries: the stop says so.
if grep -qF "v99.0.0 is in no release yet (the latest, v98.0.0, targets $target_ref): if these find no new version, run /plinth:template-update again after the next release" <<<"$out"
then ok "a pin past the latest release: the stop says the commands may find nothing until a release"
else bad "pin past the release is not said"; printf '%s\n' "$out" | sed 's/^/        /'; fi
fx=skew-older-says; fixture "$fx"; reset_logs
FLOOR_CHECK_API_DIR="$newer_api" run
if grep -q "in no release yet" <<<"$out"; then bad "a tag a release carries is said to be in none"
else ok "a tag the latest release carries: no such line"; fi

same_api="$work/api-skew-same"; tag_names "$same_api" "$target_sha"; release_says "$same_api" v98.0.0 "$target_ref"; ref_says "$same_api" "$sha40" v0.0.1
fx=skew-same; fixture "$fx"; reset_logs
FLOOR_CHECK_API_DIR="$same_api" run
goes_on "an installed target equal to the latest release's goes on to the plan"
older_api="$work/api-skew-newer"; tag_names "$older_api" "$target_sha"; release_says "$older_api" v0.0.1 v0.0.1; ref_says "$older_api" "$sha40" v0.0.1
fx=skew-installed-newer; fixture "$fx"; reset_logs
FLOOR_CHECK_API_DIR="$older_api" run
goes_on "an installed target newer than the latest release's goes on to the plan"
# The pin's tag not read, the release's read: the release decides, and it says so.
half_api="$work/api-skew-half"; tag_names "$half_api" "$target_sha"; release_says "$half_api" v98.0.0 "$target_ref"
fx=skew-pin-unread; fixture "$fx"; reset_logs
FLOOR_CHECK_API_DIR="$half_api" run
goes_on "the pin's tag not read, the release's equal: goes on"
grep -qF "the tag the plinth pin $sha40 was tested with was not read" <<<"$out" && ok "and it says the pin's tag was not read" \
  || { bad "pin's tag unread is not said"; printf '%s\n' "$out" | sed 's/^/        /'; }
# No one pin to read at all: the comparison is narrower, and it says so.
fx=skew-two-pins; fixture "$fx"
printf 'jobs:\n  label:\n    uses: coolbress/plinth/.github/workflows/label.yml@%s\n' "$(printf '%040d' 8)" > "$repo/.github/workflows/label.yml"
says="$(FLOOR_CHECK_API_DIR="$same_api" python3 "$checker" --root "$repo" --print-plugin-skew 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -qF "the CI pin was not compared (workflow pins disagree:" <<<"$says" && grep -qF "compared with the latest release alone" <<<"$says"
then ok "pins that disagree: goes on, and says the pin was not compared"
else bad "pins that disagree (rc=$rc)"; printf '%s\n' "$says" | sed 's/^/        /'; fi

unread() { # <description> <fixture dir> <why>
  fx="skew-unread-$((pass+fail))"; fixture "$fx"; reset_logs
  FLOOR_CHECK_API_DIR="$2" run
  goes_on "$1: goes on"
  if grep -qF "the latest plinth release was not read ($3); going on with the template tag this plinth targets, $target_ref" <<<"$out"
  then ok "$1: the warning names why and the installed target"
  else bad "$1: no named warning"; printf '%s\n' "$out" | sed 's/^/        /'; fi
}
gone_api="$work/api-skew-404"; tag_names "$gone_api" "$target_sha"
unread "no release found" "$gone_api" "not found"
err_api="$work/api-skew-err"; tag_names "$err_api" "$target_sha"; mkdir -p "$err_api/repos/coolbress/plinth/releases"
printf 'not json\n' > "$err_api/repos/coolbress/plinth/releases/latest.json"
unread "an API error on the release" "$err_api" "offline or API error"
odd_api="$work/api-skew-odd"; tag_names "$odd_api" "$target_sha"; mkdir -p "$odd_api/repos/coolbress/plinth/releases"
printf '{"name":"no tag"}\n' > "$odd_api/repos/coolbress/plinth/releases/latest.json"
unread "a release with no tag name" "$odd_api" "an unexpected release response"
notag_api="$work/api-skew-noref"; tag_names "$notag_api" "$target_sha"; mkdir -p "$notag_api/repos/coolbress/plinth/releases"
printf '{"tag_name":"v98.0.0"}\n' > "$notag_api/repos/coolbress/plinth/releases/latest.json"
unread "the release's new-project.sh not read" "$notag_api" "scripts/new-project.sh at v98.0.0: not found"

# The comparison itself failing is not a stop either, and not silence.
cat > "$work/bin/python3" <<MOCK
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = --print-plugin-skew ] && { echo "boom" >&2; exit 1; }; done
exec "$(command -v python3)" "\$@"
MOCK
chmod +x "$work/bin/python3"
fx=skew-crash; fixture "$fx"; reset_logs
FLOOR_CHECK_API_DIR="$same_api" run
rm -f "$work/bin/python3"
goes_on "the comparison crashing goes on to the plan"
grep -qF "the installed plinth was not compared with the latest release (the check exited 1); going on with the template tag this plinth targets, $target_ref" <<<"$out" \
  && ok "and the warning says it was not compared and names the target" \
  || { bad "a crashed comparison is not said"; printf '%s\n' "$out" | sed 's/^/        /'; }

# A repository the door did not make: no comparison, the existing reason stands.
fx=skew-foreign; fixture "$fx"; reset_logs
sed -i.bak '/^_src_path/d' "$repo/.copier-answers.yml" && rm "$repo/.copier-answers.yml.bak"
git -C "$repo" commit -q -am foreign && git -C "$repo" push -q origin main
FLOOR_CHECK_API_DIR="$newer_api" run
if [ "$rc" != 0 ] && ! grep -q "claude plugin" <<<"$out"; then ok "a repository the door did not make gets no plugin stop"
else bad "foreign repository (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# The skill names the order once and leaves the typing to the person.
skill="$root/skills/template-update/SKILL.md"
skill_steps="$(grep -E '^[1-4]\. `(claude plugin|/reload-plugins|/plinth:template-update)' "$skill" | sed -E 's/^[1-4]\. `([^`]*)`.*/\1/')"
want_steps='claude plugin marketplace update plinth
claude plugin update plinth@plinth
/reload-plugins
/plinth:template-update'
if [ "$skill_steps" = "$want_steps" ] && [ "$(grep -c 'claude plugin update plinth@plinth' "$skill")" = 1 ] \
   && grep -q 'Never run them yourself' "$skill"
then ok "the skill names the order once and says the agent never runs it"
else bad "the skill's order"; fi

# The skill names the four fields and the one edit it allows (#856).
skill="$root/skills/template-update/SKILL.md"
skill_text="$(tr '\n' ' ' < "$skill" | tr -s ' ')"
if grep -qF '`## What and why`, `## What I checked myself`, `## How it was verified` and a `Review:` line' <<<"$skill_text" \
   && ! grep -qF 'two headings' <<<"$skill_text"
then ok "the skill names the form's four fields, not two headings"
else bad "the skill's fields"; fi
if grep -qF "run the project's default review" <<<"$skill_text" && grep -qF 'replace the `Review:` line with what ran' <<<"$skill_text"
then ok "the skill says the agent runs the default review and replaces the Review: line with what ran"
else bad "the skill's review step"; fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
