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
# A mktemp that fails must stop here: `cd ""` stays in the current folder,
# and the trap below would then delete it (seen in a sandbox that refused
# the temp folder, #1012).
work="$(mktemp -d)" && work="$(cd "$work" && pwd -P)" && [ -n "$work" ] \
  || { echo "template-update-cases: could not make a temp folder" >&2; exit 1; }
trap 'rm -rf "$work"' EXIT
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
# The plan's admin command files (#1045) go here, not under /tmp, but in the
# one case that reads the default.
mkdir -p "$work/admin"; export TEMPLATE_UPDATE_ADMIN_TMP="$work/admin"
# The checker's GitHub reads come from fixtures, never the network: a
# missing file answers 404. Each directory answers that the target tag still
# names the commit plinth was tested with (#519), and that it was tested with
# the plinth the fixtures' workflows call, $sha40 (#511), so the update is
# not held for the pin (#1183), unless a case writes another first.
tested_is() { # <fixture dir> <plinth_sha default>: the target tag's copier.yml
  mkdir -p "$1/repos/coolbress/plinth-template/contents"
  printf 'plinth_sha:\n  type: str\n  default: "%s"\n' "$2" | base64 | tr -d '\n' | jq -R '{encoding: "base64", content: .}' \
    > "$1/repos/coolbress/plinth-template/contents/copier.yml?ref=$target_sha.json"
}
tag_names() { # <fixture dir> <commit>: what the target tag names on GitHub
  mkdir -p "$1/repos/coolbress/plinth-template/commits"
  printf '{"sha":"%s"}\n' "$2" > "$1/repos/coolbress/plinth-template/commits/$target_ref.json"
  [ -e "$1/repos/coolbress/plinth-template/contents/copier.yml?ref=$target_sha.json" ] || tested_is "$1" "$sha40"
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
  "api repos/o/r/rules/branches/main"*)
    # The rules on main, with each required check named in MOCK_REQUIRED
    # (comma-separated), filtered by the script's own --jq as gh does (#1004).
    [ "${MOCK_REQUIRED:-}" = unreadable ] && { echo "HTTP 403" >&2; exit 1; }
    jqf="."; prev=""
    for a in "$@"; do [ "$prev" = --jq ] && jqf="$a"; prev="$a"; done
    jq -n --arg r "${MOCK_REQUIRED:-}" '[{type: "pull_request"}, {type: "required_status_checks",
      parameters: {required_status_checks: [$r | split(",")[] | select(. != "") | {context: ., integration_id: 15368}]}}]' \
      | jq -r "$jqf" ;;
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
printf '%s\n' "$PWD" > "$UVX_LOG.cwd.$$"
# An archetype move (#1004), as copier 9.18.2 and 9.19.1 were measured to do
# it from data-ml to cli: the model files the project left unchanged go, the
# image job and the container files go, the cli test of the built wheel is
# added untracked, and the answers record cli. MOCK_MOVE=handdel is a project
# that deleted the model by hand: pyproject.toml, __main__.py and uv.lock are
# left unmerged (`UU`) with markers instead.
# `copier recopy` into a folder holding only the answers file is the old
# archetype's own render at the recorded tag (#1016): the data-ml files as
# move_fixture writes them. Logged apart, so UVX_LOG keeps the update line.
case " $* " in *" copier recopy "*)
  printf '%s\n' "$*" > "$UVX_LOG.recopy"
  [ "${MOCK_RECOPY_FAIL:-}" = 1 ] && { echo "copier: the template could not be fetched" >&2; exit 1; }
  dst="${!#}"; [ -f "$dst/.copier-answers.yml" ] || { echo "mock recopy: no answers file in $dst" >&2; exit 1; }
  # MOCK_OLD_RENDER: a folder holding the render a plain update's plan
  # compares with (#1184), in place of the data-ml files.
  [ -n "${MOCK_OLD_RENDER:-}" ] && { cp -R "$MOCK_OLD_RENDER/." "$dst/"; exit 0; }
  mkdir -p "$dst/src/demo" "$dst/tests" "$dst/data"
  printf 'model\n' > "$dst/MODEL_CARD.md"; printf 'train\n' > "$dst/src/demo/train.py"
  printf 'test\n' > "$dst/tests/test_train.py"; printf 'data\n' > "$dst/data/README.md"; printf 'FROM x\n' > "$dst/Dockerfile"
  exit 0 ;;
esac
new=""; for a in "$@"; do case "$a" in archetype=*) new="${a#archetype=}" ;; esac; done
if [ -n "$new" ]; then
  [ "${MOCK_MOVE_FAIL:-}" = 1 ] && { echo "ValueError: Validation error for question 'archetype': The package name would collide" >&2; exit 1; }
  sed -i.bak "s/^archetype: .*/archetype: $new/" .copier-answers.yml && rm .copier-answers.yml.bak
  # On GitLab (#1012) the template renders .gitlab-ci.yml, whose
  # docker-image job and Dockerfile come with backend and go with cli.
  if [ -f .gitlab-ci.yml ]; then
    if [ "$new" = backend ]; then
      printf '\ndocker-image:\n  stage: test\n  script:\n    - docker build .\n' >> .gitlab-ci.yml; printf 'FROM x\n' > Dockerfile
    else
      awk '/^docker-image:/ { s = 1; next } /^[^ ]/ { s = 0 } !s' .gitlab-ci.yml > .gl && mv .gl .gitlab-ci.yml; rm -f Dockerfile
    fi
    exit 0
  fi
  # A move to backend (#1017): the image job and its Dockerfile come, nothing goes.
  if [ "$new" = backend ]; then
    printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n  image:\n    runs-on: ubuntu-latest\n' "$(printf '%040d' 7)" > .github/workflows/ci.yml
    # MOCK_CI_EXCLUDE: the project's own diff-size-exclude, kept by the move (review on #1052).
    [ -z "${MOCK_CI_EXCLUDE:-}" ] || printf '    with:\n      diff-size-exclude: "%s"\n' "$MOCK_CI_EXCLUDE" \
      | sed -i.bak '3r /dev/stdin' .github/workflows/ci.yml && rm -f .github/workflows/ci.yml.bak
    printf 'FROM x\n' > Dockerfile
    # Its image workflows call docker's actions, which the door allows only
    # for backend (#1018).
    printf 'jobs:\n  image:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: docker/setup-buildx-action@%s\n      - uses: docker/build-push-action@%s\n' \
      "$(printf '%040d' 7)" "$(printf '%040d' 7)" > .github/workflows/release.yml
    # MOCK_RELEASE=big (#1044): as the template renders the move, release.yml
    # rewritten whole (the cli one is 450 lines here, this 100 more), and
    # 450 lines in two files, so the move needs a split by file without it.
    if [ "${MOCK_RELEASE:-}" = big ]; then
      for i in $(seq 1 100); do echo "      # image step $i"; done >> .github/workflows/release.yml
      mkdir -p src; for i in $(seq 1 300); do echo "i$i = $i"; done > src/serve.py
      for i in $(seq 1 150); do echo "s$i = $i"; done > src/store.py
    fi
    exit 0
  fi
  printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n' "$(printf '%040d' 7)" > .github/workflows/ci.yml
  # cli's release.yml publishes with pypa's action, which the door allows only
  # for cli and library (#1018).
  printf 'jobs:\n  publish:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: pypa/gh-action-pypi-publish@%s\n' "$(printf '%040d' 7)" > .github/workflows/release.yml
  rm -f Dockerfile; mkdir -p tests; printf 'def test_built_wheel():\n    pass\n' > tests/test_built_wheel.py
  conflict() { # <path> <ours> <theirs>
    local b o t; b="$(git hash-object -w "$1")"
    printf '%b' "$2" > .o; printf '%b' "$3" > .t; o="$(git hash-object -w .o)"; t="$(git hash-object -w .t)"; rm .o .t
    git update-index --force-remove "$1"
    printf '100644 %s 1\t%s\n100644 %s 2\t%s\n100644 %s 3\t%s\n' "$b" "$1" "$o" "$1" "$t" "$1" | git update-index --index-info
    printf 'top\n<<<<<<< before updating\n%b=======\n%b>>>>>>> after updating\nend\n' "$2" "$3" > "$1"
  }
  if [ "${MOCK_MOVE:-asis}" = handdel ]; then
    conflict pyproject.toml 'dependencies = []\n' 'classifiers = ["Typing :: Typed"]\ndependencies = []\n'
    conflict src/demo/__main__.py 'def main():\n    own_helper()\n' 'def main():\n    print(greet())\n'
    conflict uv.lock 'lock-before\n' 'lock-after\n'
  else
    rm -rf MODEL_CARD.md src/demo/train.py tests/test_train.py data
    printf 'cli pyproject\n' > pyproject.toml; printf 'cli main\n' > src/demo/__main__.py; printf 'cli lock\n' > uv.lock
  fi
  exit 0
fi
# copier records the tag a commit carries, not the commit (measured, 9.18.2).
[ "$ref" = "$TARGET_SHA" ] && ref="$TARGET_REF"
sed -i.bak "s/^_commit: .*/_commit: $ref/" .copier-answers.yml && rm .copier-answers.yml.bak
printf 'template line\n' >> AGENTS.md
# MOCK_QUESTIONS (#1185): a file of `<name>\t<default>\t<applies>` lines,
# questions the target tag asks. As copier does, each that applies (its
# `when:` true) and is not recorded yet is recorded with its --data value or
# else its default (`null` when it has none); one that does not apply is not
# recorded. records_language is also said in AGENTS.md, as the template
# renders it.
if [ -n "${MOCK_QUESTIONS:-}" ]; then
  while IFS=$'\t' read -r qn qd qa; do
    [ "$qa" = yes ] && ! grep -q "^$qn:" .copier-answers.yml || continue
    qv="$qd"; for a in "$@"; do case "$a" in "$qn="*) qv="${a#"$qn="}" ;; esac; done
    printf '%s: %s\n' "$qn" "$qv" >> .copier-answers.yml
    [ "$qn" != records_language ] || printf 'Records are written in %s.\n' "$qv" >> AGENTS.md
  done < "$MOCK_QUESTIONS"
fi
# MOCK_TOUCH: more files the template changes, each merged cleanly (#1184).
for f in ${MOCK_TOUCH:-}; do printf 'template line\n' >> "$f"; done
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
  # MOCK_CONFLICT_DIR (#1186): a conflict in each file `list` names (`<path>\t<key>`),
  # written as copier writes one: <key>.head, the markers around <key>.ours
  # and <key>.theirs, then <key>.tail; the index holds the three stages.
  custom)
    while IFS=$'\t' read -r cp ck; do
      [ -n "$cp" ] || continue
      cd_="$MOCK_CONFLICT_DIR/$ck"
      cb="$(git hash-object -w "$cp")"
      cat "$cd_.head" "$cd_.ours" "$cd_.tail" > .o; cat "$cd_.head" "$cd_.theirs" "$cd_.tail" > .t
      co="$(git hash-object -w .o)"; ct="$(git hash-object -w .t)"; rm .o .t
      git update-index --force-remove "$cp"
      printf '100644 %s 1\t%s\n100644 %s 2\t%s\n100644 %s 3\t%s\n' "$cb" "$cp" "$co" "$cp" "$ct" "$cp" | git update-index --index-info
      { cat "$cd_.head"; echo "<<<<<<< before updating"; cat "$cd_.ours"; echo "======="; cat "$cd_.theirs"; echo ">>>>>>> after updating"; cat "$cd_.tail"; } > "$cp"
    done < "$MOCK_CONFLICT_DIR/list" ;;
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
  out="$(cd "$repo" && PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" GLAB_LOG="$work/glab.log" UVX_LOG="$work/uvx.log" "$script" "$@" 2>&1)"; rc=$?
}
reset_logs() { : > "$work/gh.log"; : > "$work/glab.log"; rm -f "$work/uvx.log" "$work/gh.log.body" "$work/glab.log.body"; }
wt_of() { printf '%s\n' "$work/$1-template-$target_ref"; }
awt_of() { printf '%s\n' "$work/$1-archetype-$2"; }

# ── plan: read-only ─────────────────────────────────────────────────────
fixture plan; reset_logs
want="$(python3 "$checker" --root "$repo" --repo o/r --print-update-command 2>/dev/null)"
run
base="$(git -C "$BARE" rev-parse main)"
if [ "$rc" = 0 ] && grep -qF "$want" <<<"$out" && grep -qF -- "--apply $base" <<<"$out"; then ok "the plan prints the checker's own command and the apply line naming the verified base"
else bad "plan (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# The plan runs copier on a copy outside the repository (#1184), never in it.
ran_in="$(cat "$work/uvx.log.cwd."* 2>/dev/null)"; rm -f "$work/uvx.log.cwd."*
if [ ! -e "$(wt_of plan)" ] && ! git -C "$repo" rev-parse -q --verify "refs/heads/chore/template-$target_ref" >/dev/null \
   && [ -n "$ran_in" ] && ! grep -qF "$repo" <<<"$ran_in"
then ok "the plan creates no worktree, no branch, and runs copier only on a copy outside the repository"
else bad "the plan wrote something"; fi

# ── plan: the rehearsal (#1184) ─────────────────────────────────────────
# The plan runs the line on a copy of the base and says what it does: what
# merges cleanly where the repository has the template's render, what merges
# into the repository's own changes, what is left in conflict with the lines
# the repository added there, what the template changed, and how to undo.
# The old render is the mock recopy's: MOCK_OLD_RENDER's files.
fixture rehearse
printf '# Contributing\nOur own rule\n' > "$repo/CONTRIBUTING.md"
git -C "$repo" commit -q -am "our rule" && git -C "$repo" push -q origin main
mkdir -p "$work/old-render/.github/ISSUE_TEMPLATE"
printf '# Agents\n' > "$work/old-render/AGENTS.md"; printf '# Contributing\n' > "$work/old-render/CONTRIBUTING.md"
printf 'name: task\n' > "$work/old-render/.github/ISSUE_TEMPLATE/task.yml"
# The target tag's CHANGELOG: two sections after v1.0.0, one with the fixed
# heading; v1.0.0 itself and [Unreleased] are not between.
api_cl="$work/api-cl"; tag_names "$api_cl" "$target_sha"
printf '%s\n' "# Changelog" "" "## [Unreleased]" "" "### Added" "- later" "" \
  "## [${target_ref#v}] - 2026-11-25" "" "**Lead.**" "" "### Files and questions" "" "- \`AGENTS.md\`" "- question \`records_language\`" "" "### Added" "" "- a question" "" \
  "## [1.0.1] - 2026-01-02" "" "### Fixed" "" "- a fix" "" "## [1.0.0] - 2026-01-01" "" "- first" \
  | base64 | tr -d '\n' | jq -R '{encoding: "base64", content: .}' \
  > "$api_cl/repos/coolbress/plinth-template/contents/CHANGELOG.md?ref=$target_sha.json"
# What the plan must leave as it was: the checkout's status (an untracked
# file), every ref, the worktrees and the stash (one entry), and nothing of
# its own in the temporary directory.
printf 'mine\n' > "$repo/notes.txt"
printf 'x\n' >> "$repo/AGENTS.md"; git -C "$repo" stash push -q -m "the person's" -- AGENTS.md
snap() { git -C "$repo" status --porcelain; git -C "$repo" for-each-ref; git -C "$repo" worktree list --porcelain; git -C "$repo" stash list; }
before="$(snap)"; plan_tmp="$work/plan-tmp"; mkdir -p "$plan_tmp"
plan_run() { # <env...>: the plan with its own TMPDIR
  reset_logs
  out="$(cd "$repo" && env "$@" TMPDIR="$plan_tmp" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" 2>&1)"; rc=$?
}
plan_run FLOOR_CHECK_API_DIR="$api_cl" MOCK_COPIER=conflict MOCK_TOUCH=.github/ISSUE_TEMPLATE/task.yml MOCK_OLD_RENDER="$work/old-render"
block() { awk -v h="$1" 'index($0, h) == 1 { f = 1; next } f && /^[^ ]/ { exit } f' <<<"$out"; }
clean="$(block "Merges cleanly, where this repository has the template's render of v1.0.0:")"
own="$(block "Merges cleanly into this repository's own changes")"
left="$(block "Left in conflict")"
if [ "$rc" = 0 ] && grep -q "^Rehearsed on a copy of origin/main outside this repository, in [0-9]* s" <<<"$out" \
   && [ "$(sort <<<"$clean")" = "$(printf '  .copier-answers.yml\n  AGENTS.md\n' | sort)" ] && [ "$own" = "  .github/ISSUE_TEMPLATE/task.yml" ] \
   && [ "$left" = "$(printf '  CONTRIBUTING.md\n    lines this repository added to the template'"'"'s render of v1.0.0:\n      + Our own rule')" ]
then ok "the plan rehearses the update: what merges cleanly, what merges into this repository's own changes, and each conflict with the lines this repository added"
else bad "plan, the three lists (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
if grep -qF -- "copier recopy --defaults --overwrite --quiet --vcs-ref v1.0.0 ." "$work/uvx.log.recopy" 2>/dev/null
then ok "the comparison is copier's own render of the recorded answers at the recorded tag"
else bad "plan, what ran"; cat "$work/uvx.log" "$work/uvx.log.recopy" 2>/dev/null | sed 's/^/        /'; fi
changes="$(block "What the template changed, v1.0.0 to $target_ref:")"
want_changes="$(printf '  %s\n' "## [${target_ref#v}] - 2026-11-25" "  ### Files and questions" "" "  - \`AGENTS.md\`" "  - question \`records_language\`" "## [1.0.1] - 2026-01-02")"
if [ "$changes" = "$want_changes" ]
then ok "the plan prints the CHANGELOG's section headings between the two tags, quoting the files-and-questions heading where a section has it"
else bad "plan, the template's changes"; printf '%s\n' "$changes" | sed 's/^/        /'; fi
undo="$(block "Undo:")"
if grep -qxF "    gh pr close chore/template-$target_ref" <<<"$undo" && grep -qF "revert --no-edit" <<<"$undo" \
   && grep -qxF "    git worktree remove --force ../rehearse-template-$target_ref" <<<"$undo"
then ok "the plan says how to undo the update before it merges and after"
else bad "plan, undo"; printf '%s\n' "$out" | sed 's/^/        /'; fi
if [ "$(snap)" = "$before" ] && [ -z "$(ls -A "$plan_tmp")" ] && [ ! -e "$(wt_of rehearse)" ]
then ok "the plan leaves the checkout as it was (status, refs, worktrees, stash) and no copy in the temporary directory"
else bad "plan, the checkout or the temporary directory changed"; diff <(printf '%s\n' "$before") <(snap) | sed 's/^/        /'; ls -A "$plan_tmp" | sed 's/^/        /'; fi
# copier failing in the rehearsal: a stop, and still nothing left behind.
plan_run FLOOR_CHECK_API_DIR="$api_cl" MOCK_COPIER=fail
if [ "$rc" = 1 ] && grep -qF "copier failed in the rehearsal" <<<"$out" && grep -qF "copier: something broke" <<<"$out" \
   && ! grep -qE -- "--apply [0-9a-f]{40}" <<<"$out" && [ "$(snap)" = "$before" ] && [ -z "$(ls -A "$plan_tmp")" ]
then ok "copier failing in the rehearsal stops the plan with its last line, and leaves the checkout and the temporary directory as they were"
else bad "plan, copier fails (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; ls -A "$plan_tmp" | sed 's/^/        /'; fi
# The old render failing: the lists are given without the comparison, said.
plan_run FLOOR_CHECK_API_DIR="$api_cl" MOCK_COPIER=conflict MOCK_RECOPY_FAIL=1
if [ "$rc" = 0 ] && grep -qx "Merges cleanly:" <<<"$out" && grep -qF "Not compared with the template's render of v1.0.0" <<<"$out" \
   && grep -qF "copier: the template could not be fetched" <<<"$out" && grep -qx "  CONTRIBUTING.md" <<<"$out" && ! grep -q "lines this repository added" <<<"$out" \
   && [ -z "$(ls -A "$plan_tmp")" ]
then ok "an old render copier could not make: the lists without the comparison, and the plan says what it could not show"
else bad "plan, old render fails (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# The CHANGELOG not read: the compare link in its place.
plan_run FLOOR_CHECK_API_DIR="$work/api-none" MOCK_OLD_RENDER="$work/old-render"
if [ "$rc" = 0 ] && grep -qF "its CHANGELOG was not read (coolbress/plinth-template CHANGELOG.md at $target_ref: not found); every change: https://github.com/coolbress/plinth-template/compare/v1.0.0...$target_ref" <<<"$out"
then ok "a CHANGELOG not read: the plan prints the compare link instead"
else bad "plan, CHANGELOG unread (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# The CHANGELOG read failing (an answer that does not parse, as the API
# failing is served): the compare link too, with that reason.
api_bad="$work/api-badcl"; tag_names "$api_bad" "$target_sha"
echo 'not json' > "$api_bad/repos/coolbress/plinth-template/contents/CHANGELOG.md?ref=$target_sha.json"
plan_run FLOOR_CHECK_API_DIR="$api_bad" MOCK_OLD_RENDER="$work/old-render"
if [ "$rc" = 0 ] && grep -qF "its CHANGELOG was not read (coolbress/plinth-template CHANGELOG.md at $target_ref: offline or API error); every change: https://github.com/coolbress/plinth-template/compare/v1.0.0...$target_ref" <<<"$out"
then ok "a CHANGELOG read that fails: the plan prints the compare link and says the read failed"
else bad "plan, CHANGELOG read failed (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
rm -f "$work"/uvx.log.cwd.* "$work/uvx.log.recopy"

# ── new questions (#1185) ───────────────────────────────────────────────
# A question the target tag asks that the repository never answered takes
# its default under --defaults, unasked. The plan names each that applies,
# with its default and help; one with no default stops it; --apply passes
# the person's answers as --data and the description records each, or
# "default kept". The mock records them as copier does (MOCK_QUESTIONS).
repo_was="$repo"; bare_was="$BARE"
api_q="$work/api-q"; tag_names "$api_q" "$target_sha"
{ printf 'plinth_sha:\n  type: str\n  default: "%s"\n\n' "$sha40"
  printf 'description:\n  type: str\n  help: One line saying what this project is.\n  default: ""\n\n'
  printf 'records_language:\n  type: str\n  help: |\n    The language records are written in,\n    named in English. Example Korean.\n\n    A second paragraph.\n  default: English\n\n'
  printf 'hosting:\n  type: str\n  when: "{{ archetype == '"'web'"' }}"\n  help: Where will your app run?\n  default: render\n\n'
  printf 'contact:\n  type: str\n  help: Where reports go.\n'
} | base64 | tr -d '\n' | jq -R '{encoding: "base64", content: .}' \
  > "$api_q/repos/coolbress/plinth-template/contents/copier.yml?ref=$target_sha.json"
printf 'records_language\tEnglish\tyes\ndescription\t'"''"'\tyes\nhosting\trender\tno\n' > "$work/questions.txt"
{ cat "$work/questions.txt"; printf 'contact\tnull\tyes\n'; } > "$work/questions-nodefault.txt"
q_run() { # <env...> -- <args...>: the script in $repo
  local e=()
  while [ "$1" != -- ]; do e+=("$1"); shift; done; shift
  reset_logs
  out="$(cd "$repo" && env ${e[@]+"${e[@]}"} FLOOR_CHECK_API_DIR="$api_q" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" GLAB_LOG="$work/glab.log" UVX_LOG="$work/uvx.log" "$script" "$@" 2>&1)"; rc=$?
}
fixture questions
q_run MOCK_QUESTIONS="$work/questions.txt" --
asked="$(awk 'index($0, "New questions") == 1 { f = 1; next } f && /^[^ ]/ { exit } f' <<<"$out")"
want_asked="$(printf '%s\n' "  records_language, default English" "    The language records are written in," "    named in English. Example Korean." "    " "    A second paragraph." \
  "  description, default ''" "    One line saying what this project is.")"
if [ "$rc" = 0 ] && [ "$asked" = "$want_asked" ] && grep -qF -- "with --answer <name> <value> for each new question" <<<"$out"
then ok "the plan names each new question that applies, with its default and its help, and leaves out one whose when: is false"
else bad "plan, new questions (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
q_run MOCK_QUESTIONS="$work/questions-nodefault.txt" --
if [ "$rc" = 1 ] && grep -qx "  contact, no default: copier's --defaults would record null" <<<"$out" \
   && grep -qF "stopped: no default for contact" <<<"$out" && grep -qF -- "--answer contact <value>" <<<"$out" \
   && ! grep -qF "To apply it" <<<"$out" && [ ! -e "$(wt_of questions)" ]
then ok "a new question with no default stops the plan with its name, and says to answer it on --apply"
else bad "plan, a question with no default (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
base="$(git -C "$BARE" rev-parse main)"
q_run MOCK_QUESTIONS="$work/questions.txt" -- --apply "$base" --answer hosting render
if [ "$rc" = 2 ] && grep -qF "not a new question of this update: hosting (the plan lists: records_language description)" <<<"$out" \
   && [ ! -e "$(wt_of questions)" ] && ! git -C "$repo" rev-parse -q --verify "refs/heads/chore/template-$target_ref" >/dev/null
then ok "--apply given an answer for a question the plan does not list exits 2 and creates nothing"
else bad "--apply, an unlisted answer (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
q_run MOCK_QUESTIONS="$work/questions.txt" -- --apply "$base" --answer records_language Korean --answer description '한국어 설명, 두 단어'
wt="$(wt_of questions)"; body="$(cat "$work/gh.log.body" 2>/dev/null)"
if [ "$rc" = 0 ] && grep -qx "records_language: Korean" "$wt/.copier-answers.yml" && grep -qx "Records are written in Korean." "$wt/AGENTS.md" \
   && grep -qx "description: 한국어 설명, 두 단어" "$wt/.copier-answers.yml"
then ok "--apply with records_language answered Korean records Korean in .copier-answers.yml and in the rendered AGENTS.md; an answer with spaces stays one word"
else bad "--apply, the answers (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; cat "$wt/.copier-answers.yml" 2>/dev/null | sed 's/^/        /'; fi
if grep -qxF -- "- \`records_language\`: Korean" <<<"$body" && grep -qxF -- "- \`description\`: 한국어 설명, 두 단어" <<<"$body" \
   && grep -qF -- " --data records_language=Korean --data 'description=한국어 설명, 두 단어'" <<<"$body" && ! grep -qF "(default kept)" <<<"$body"
then ok "the description records each answer, and the command with the answers quoted, Hangul as typed"
else bad "the description, answers"; printf '%s\n' "$body" | sed 's/^/        /'; fi
# Its verification prose says so too, not that each took the default (review on #1211).
if grep -qF "takes the person's answer where one is given" <<<"$body" && ! grep -qF "a question it never answered takes the" <<<"$body"
then ok "with answers given, the description's verification does not say each never-answered question took the default"
else bad "the verification prose with answers"; section "$work/gh.log.body" "How it was verified" | sed 's/^/        /'; fi
fixture questions-default
base="$(git -C "$BARE" rev-parse main)"
q_run MOCK_QUESTIONS="$work/questions.txt" -- --apply "$base"
wt="$(wt_of questions-default)"; body="$(cat "$work/gh.log.body" 2>/dev/null)"
if [ "$rc" = 0 ] && grep -qx "records_language: English" "$wt/.copier-answers.yml" \
   && grep -qxF -- "- \`records_language\`: English (default kept)" <<<"$body" && grep -qxF -- "- \`description\`: '' (default kept)" <<<"$body" \
   && ! grep -q "hosting" <<<"$body"
then ok "--apply given no answer records each new question at its default, and the description says default kept for each"
else bad "--apply, defaults kept (rc=$rc)"; printf '%s\n' "$out" "$body" | sed 's/^/        /'; fi
fixture questions-null
base="$(git -C "$BARE" rev-parse main)"
q_run MOCK_QUESTIONS="$work/questions-nodefault.txt" -- --apply "$base"
if [ "$rc" = 1 ] && grep -qF "copier recorded null for contact" <<<"$out" && ! grep -q "pr create" "$work/gh.log" \
   && [ "$(git -C "$BARE" rev-parse main)" = "$base" ] && ! git -C "$BARE" rev-parse -q --verify "refs/heads/chore/template-$target_ref" >/dev/null
then ok "--apply that leaves a question with no default unanswered stops before committing: copier recorded null"
else bad "--apply, a null recorded (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
q_run -- --apply "$base" --archetype cli --answer records_language Korean
if [ "$rc" = 2 ]; then ok "--answer is refused with an archetype move (usage)"; else bad "--answer with --archetype (rc=$rc)"; fi
q_run -- --apply "$base" --answer records_language Korean --answer records_language English
if [ "$rc" = 2 ]; then ok "--answer naming one question twice is refused (usage)"; else bad "--answer twice (rc=$rc)"; fi
rm -f "$work"/uvx.log.cwd.* "$work/uvx.log.recopy"
repo="$repo_was"; BARE="$bare_was"; export BARE

# ── conflicts: a combination that keeps this repository's lines (#1186) ─
# A conflict whose "before" side holds a line this repository added to the
# template's render offers no one side as the recommendation: the
# combination, the template's side with that line kept, is written beside
# the record. A conflict with no such line may still take the template's
# side. The description names each kept line and where it is now.
repo_was="$repo"; bare_was="$BARE"
cx="$work/conflicts"; mkdir -p "$cx" "$work/comb-old"
part() { printf '%b' "$2" > "$cx/$1"; } # <key.part> <text>
part agents.head '# Agents\n\n## Always\n\n'; part agents.old '- a template rule\n'
part agents.ours '- a template rule\n- Our own rule\n'; part agents.theirs '- a rewritten template rule\n- another template rule\n'
part agents.tail "\n## This project\n\nThis project's own rules: a template update never changes this section.\n"
part yml.head 'jobs:\n  ci:\n    with:\n'; part yml.old '      versions: "3.13"\n'
part yml.ours '      timeout: 20\n      # no second run here\n      versions: ""\n'; part yml.theirs '      # the newer version\n      versions: "3.14"\n'
part yml.tail '    permissions: {}\n'
part contrib.head '# Contributing\n\n'; part contrib.old '- keep it short\n'; part contrib.ours '- keep it short\n'
part contrib.theirs '- keep it brief\n'; part contrib.tail ''
printf 'AGENTS.md\tagents\nsettings.yml\tyml\nCONTRIBUTING.md\tcontrib\n' > "$cx/list"
fixture combine
while IFS=$'\t' read -r cp ck; do
  cat "$cx/$ck.head" "$cx/$ck.ours" "$cx/$ck.tail" > "$repo/$cp"
  cat "$cx/$ck.head" "$cx/$ck.old" "$cx/$ck.tail" > "$work/comb-old/$cp"
done < "$cx/list"
git -C "$repo" add -A && git -C "$repo" commit -q -m "our lines" && git -C "$repo" push -q origin main
base="$(git -C "$BARE" rev-parse main)"; reset_logs
out="$(cd "$repo" && MOCK_COPIER=custom MOCK_CONFLICT_DIR="$cx" MOCK_OLD_RENDER="$work/comb-old" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" 2>&1)"; rc=$?
wt="$(wt_of combine)"
comb_of() { sed -n "s|^    The combination, the template's side with those lines kept: \(.*/$1\)\$|\1|p" <<<"$out"; }
ca="$(comb_of AGENTS.md)"; cy="$(comb_of settings.yml)"
if [ "$rc" = 3 ] && grep -qxF "  AGENTS.md: 1; neither side whole keeps both, so neither is the recommendation." <<<"$out" \
   && grep -qxF "      + - Our own rule    (no old place; propose: under ## This project, the file's last section)" <<<"$out" \
   && [ -f "$ca" ] && grep -qxF -- "- Our own rule" "$ca" && grep -qxF -- "- a rewritten template rule" "$ca" && ! grep -q '^<<<<<<<\|^>>>>>>>' "$ca" \
   && case "$ca" in "$wt"/*) false ;; *) true ;; esac
then ok "a conflict whose before side holds a line this repository added offers no one side; the combination keeps the line, outside the worktree"
else bad "combination, Markdown (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; cat "$ca" 2>/dev/null | sed 's/^/        /'; fi
if [ -f "$cy" ] && grep -qxF '      versions: ""' "$cy" && ! grep -qF '"3.14"' "$cy" && ! grep -qF "the newer version" "$cy" \
   && grep -qxF '      timeout: 20' "$cy" && grep -qxF '      # no second run here' "$cy" && grep -qxF '    permissions: {}' "$cy" \
   && grep -qxF '      +       versions: ""    (replaces versions: "3.14")' <<<"$out"
then ok "a key this repository set that the template's side sets too: this repository's value replaces the template's, with its own comment"
else bad "combination, YAML"; cat "$cy" 2>/dev/null | sed 's/^/        /'; fi
if grep -qxF "  CONTRIBUTING.md: none; the template's side keeps every line this repository added" <<<"$out"
then ok "a conflict with no line this repository added may still take the template's side"
else bad "combination, no added line"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# The person's word: AGENTS.md as combined, with the line moved under
# `## This project`; settings.yml as combined; CONTRIBUTING.md the template's side.
grep -vxF -- "- Our own rule" "$ca" > "$wt/AGENTS.md"; printf -- '- Our own rule\n' >> "$wt/AGENTS.md"
cp "$cy" "$wt/settings.yml"; cat "$cx/contrib.head" "$cx/contrib.theirs" > "$wt/CONTRIBUTING.md"
git -C "$wt" add AGENTS.md settings.yml CONTRIBUTING.md
reset_logs
run --finish "$wt" --resolved AGENTS.md "the combination, the line moved under ## This project, on the person's word" \
  --resolved settings.yml "the combination, on the person's word" --resolved CONTRIBUTING.md "the template's side, on the person's word"
body="$(cat "$work/gh.log.body" 2>/dev/null)"
kept="$(awk '/^Lines this repository added that the template.s side dropped/ { f = 1; next } f && /^$/ && n++ { exit } f && /^- /' <<<"$body")"
if [ "$rc" = 0 ] && grep -qxF -- "- \`AGENTS.md\`, under \`## This project\`, line 11: \`- Our own rule\`" <<<"$kept" \
   && grep -qxF -- "- \`settings.yml\`, under \`jobs.ci.with\`, line 6: \`timeout: 20\`" <<<"$kept" \
   && grep -qxF -- "- \`settings.yml\`, under \`jobs.ci.with\`, line 5: \`versions: \"\"\`" <<<"$kept" && ! grep -qF CONTRIBUTING <<<"$kept"
then ok "the description lists each kept line and the file and section it is in now"
else bad "the description's kept lines (rc=$rc)"; printf '%s\n' "$out" "$body" | sed 's/^/        /'; fi
rm -f "$work"/uvx.log.cwd.* "$work/uvx.log.recopy"
repo="$repo_was"; BARE="$bare_was"; export BARE

# The helper itself, on the shapes the review on #1186 found (each failed
# before its fix): a parent key keeps the template's children; a key is
# matched only under its own table; a line starting with a tab is reported
# whole; a line the template's side already holds is not counted as kept.
combine_py="$root/scripts/template-update-combine.py"; hx="$work/helper"; mkdir -p "$hx"
printf 'jobs:\n  t:\n    steps:\n      - name: Test\n<<<<<<< before updating\n        run: pytest\n        timeout-minutes: 20\n=======\n        run: pytest -q --strict\n>>>>>>> after updating\n' > "$hx/a.yml"
printf 'jobs:\n  t:\n    steps:\n      - name: Test\n        run: pytest\n        timeout-minutes: 20\n' > "$hx/a.base"
printf 'jobs:\n  t:\n    steps:\n      - name: Test\n        run: pytest\n' > "$hx/a.old"
python3 "$combine_py" combine "$hx/a.yml" "$hx/a.base" "$hx/a.old" "$hx/out/a.yml" > "$hx/a.report"
if grep -qxF '        run: pytest -q --strict' "$hx/out/a.yml" && grep -qxF '        timeout-minutes: 20' "$hx/out/a.yml" && ! grep -qxF '        run: pytest' "$hx/out/a.yml"
then ok "the combination keeps the template's change to a sibling of a line this repository added"
else bad "helper, a parent key"; cat "$hx/out/a.yml" "$hx/a.report" 2>/dev/null | sed 's/^/        /'; fi
printf '<<<<<<< before updating\n[tool.a]\ntimeout = 10\n[tool.b]\ntimeout = 20\n=======\n[tool.a]\ntimeout = 15\n[tool.b]\ntimeout = 10\n>>>>>>> after updating\n' > "$hx/b.toml"
printf '[tool.a]\ntimeout = 10\n[tool.b]\ntimeout = 20\n' > "$hx/b.base"; printf '[tool.a]\ntimeout = 10\n[tool.b]\ntimeout = 10\n' > "$hx/b.old"
python3 "$combine_py" combine "$hx/b.toml" "$hx/b.base" "$hx/b.old" "$hx/out/b.toml" > "$hx/b.report"
if [ "$(cat "$hx/out/b.toml")" = "$(printf '[tool.a]\ntimeout = 15\n[tool.b]\ntimeout = 20')" ]
then ok "a key is replaced only under its own table: the template's [tool.a] change and this repository's [tool.b] value both stay"
else bad "helper, a key in two tables"; cat "$hx/out/b.toml" "$hx/b.report" 2>/dev/null | sed 's/^/        /'; fi
printf 'test:\n<<<<<<< before updating\n\tpytest\n\tmypy .\n=======\n\tpytest -q\n>>>>>>> after updating\n' > "$hx/Makefile"
printf 'test:\n\tpytest\n\tmypy .\n' > "$hx/m.base"; printf 'test:\n\tpytest\n' > "$hx/m.old"
python3 "$combine_py" combine "$hx/Makefile" "$hx/m.base" "$hx/m.old" "$hx/out/Makefile" > "$hx/m.report"
if [ "$(cut -f4- "$hx/m.report")" = "$(printf '\tmypy .')" ] && grep -qxF "$(printf '\tmypy .')" "$hx/out/Makefile"
then ok "a line that starts with a tab is reported and kept whole"
else bad "helper, a tab"; cat -t "$hx/m.report" 2>/dev/null | sed 's/^/        /'; fi
printf 'a:\n  x: 1\nb:\n  x: 1\n' > "$hx/w.yml"
if ! python3 "$combine_py" where "$hx/w.yml" "  x: 1" 2 >/dev/null && [ "$(python3 "$combine_py" where "$hx/w.yml" "  x: 1" 1)" = "$(printf 'b\t4')" ]
then ok "a line the template's side already holds as often is not counted as kept; one more is found where it is"
else bad "helper, where with a count"; fi

# Round 2 of the review on #1224, each as the reviewer reproduced it.
hc() { # <name> <file name> <ours> <theirs> <old> [<head>] [<the base's head>]: combine; sets $hout and $hrep
  # <the base's head>: what the base and the old render had above the block,
  # when the template changed it cleanly (the file now holds <head> there).
  local d="$hx/$1"; mkdir -p "$d"
  { printf '%b' "${6:-}"; echo "<<<<<<< before updating"; printf '%b' "$3"; echo "======="; printf '%b' "$4"; echo ">>>>>>> after updating"; } > "$d/$2"
  printf '%b%b' "${7-${6:-}}" "$3" > "$d/base"; printf '%b%b' "${7-${6:-}}" "$5" > "$d/old"
  python3 "$combine_py" combine "$d/$2" "$d/base" "$d/old" "$d/out/$2" > "$d/report"
  hout="$(cat "$d/out/$2" 2>/dev/null)"; hrep="$(cat "$d/report")"
}
hc steps ci.yml '      - name: Setup\n        run: echo setup\n      - name: Test\n        run: pytest --custom\n' \
  '      - name: Setup\n        run: echo setup\n      - name: Test\n        run: pytest -q\n' \
  '      - name: Setup\n        run: echo setup\n      - name: Test\n        run: pytest\n' 'jobs:\n  t:\n    steps:\n'
if [ "$hout" = "$(printf 'jobs:\n  t:\n    steps:\n      - name: Setup\n        run: echo setup\n      - name: Test\n        run: pytest --custom')" ]
then ok "a YAML key is matched within its own sequence item: the Test step's run is replaced, the Setup step's kept"
else bad "helper, sequence items"; printf '%s\n%s\n' "$hout" "$hrep" | sed 's/^/        /'; fi
hc scope a.toml '[tool.a]\ntimeout = 10\n[tool.b]\ntimeout = 20\n' '[tool.a]\ntimeout = 20\n[tool.b]\ntimeout = 30\n' '[tool.a]\ntimeout = 10\n[tool.b]\ntimeout = 10\n'
if [ "$hout" = "$(printf '[tool.a]\ntimeout = 20\n[tool.b]\ntimeout = 20')" ] && grep -qF 'replaces timeout = 30' <<<"$hrep"
then ok "a line the template's side holds under another table is not counted as kept: [tool.b]'s value stays the project's"
else bad "helper, kept within its scope"; printf '%s\n%s\n' "$hout" "$hrep" | sed 's/^/        /'; fi
# A header the template renamed cleanly, outside the block (review on #1234):
# the project's line is read in the base's table, where it was added.
keys='k1 = 1\nk2 = 2\nk3 = 3\nk4 = 4\nk5 = 5\nk6 = 6\nk7 = 7\nk8 = 8\nk9 = 9\nk10 = 10\n'
hc renamed a.toml 'timeout = 20\n' 'timeout = 30\n' 'timeout = 10\n' "[tool.b]\n$keys" "[tool.a]\n$keys"
if [ "$hout" = "$(printf "[tool.b]\n${keys}timeout = 20")" ] && grep -qF 'replaces timeout = 30' <<<"$hrep"
then ok "a table the template renamed outside the block: the project's timeout is still its own, and replaces the template's"
else bad "helper, a header changed cleanly"; printf '%s\n%s\n' "$hout" "$hrep" | sed 's/^/        /'; fi
# An unnamed step whose command continues on the next line (review on #1234).
hc runstep ci.yml '      - run: |\n          pytest --custom\n' '      - run: |\n          pytest -q\n' '      - run: |\n          pytest\n' 'jobs:\n  t:\n    steps:\n'
if [ "$hout" = "$(printf 'jobs:\n  t:\n    steps:\n      - run: |\n          pytest --custom')" ] && grep -qF 'replaces - run: |' <<<"$hrep"
then ok "a step matched by its first line whose command changed below it is replaced, not run twice"
else bad "helper, a step's continuation"; printf '%s\n%s\n' "$hout" "$hrep" | sed 's/^/        /'; fi
hc order build.sh 'set -eu\nmkdir -p build\ncd build\nmake\n' 'set -eu\nmake -j4\n' 'set -eu\nmake\n'
if [ "$hout" = "$(printf 'set -eu\nmkdir -p build\ncd build\nmake -j4')" ]
then ok "consecutive additions after one shared line keep their order"
else bad "helper, order"; printf '%s\n%s\n' "$hout" "$hrep" | sed 's/^/        /'; fi
hc owner p.toml 'dependencies = [\n  "a",\n  "custom",\n]\n' 'dependencies = ["b"]\n' 'dependencies = [\n  "a",\n]\n' '[project]\n'
if [ "$(grep -c '^dependencies' <<<"$hout")" = 1 ] && grep -qxF '  "custom",' <<<"$hout" && grep -qF 'replaces dependencies = ["b"]' <<<"$hrep"
then ok "an item added inside a multi-line value is matched by the key that owns it: one assignment, the project's"
else bad "helper, the owning key"; printf '%s\n%s\n' "$hout" "$hrep" | sed 's/^/        /'; fi
hc tabs t.toml 'timeout = 20\n' 'timeout\t=\t30\n' 'timeout = 10\n'
if [ "$(cut -f3 <<<"$hrep")" = 0 ] && [ "$(cut -f4- <<<"$hrep")" = "timeout = 20" ] && grep -qF 'replaces timeout\t=\t30' <<<"$hrep"
then ok "a template line with tabs in the placement is shown with \\t, and the fields stay in place"
else bad "helper, tabs in the placement"; printf '%s\n' "$hrep" | cat -t | sed 's/^/        /'; fi

# #1233: the four shapes round 4 of the review on #1224 reproduced.
hc comment t.toml '# Keep this timeout for slow tests\ntimeout = 10\n' 'timeout = 30\n' 'timeout = 10\n' '[tool.x]\n'
if [ "$hout" = "$(printf '[tool.x]\n# Keep this timeout for slow tests\ntimeout = 30')" ]
then ok "a comment added above an unchanged key is kept above the template's line, with one assignment, the template's"
else bad "helper, a comment-only addition"; printf '%s\n%s\n' "$hout" "$hrep" | sed 's/^/        /'; fi
hc provenance s.toml '[tool.a]\ntimeout = 20\n[tool.b]\ntimeout = 20\nmode = "custom"\n' \
  '[tool.a]\ntimeout = 30\n[tool.b]\ntimeout = 30\nmode = "new"\n' '[tool.a]\ntimeout = 10\n[tool.b]\ntimeout = 20\nmode = "old"\n'
if [ "$hout" = "$(printf '[tool.a]\ntimeout = 20\n[tool.b]\ntimeout = 30\nmode = "custom"')" ]
then ok "a line is this repository's only in the scope it changed it: [tool.b]'s timeout takes the template's change"
else bad "helper, added with its scope"; printf '%s\n%s\n' "$hout" "$hrep" | sed 's/^/        /'; fi
hc anchor n.toml '[tool.a]\nmode = "mine"\nenabled = true\n[tool.b]\nenabled = true\ncustom = 42\ntimeout = 1\n' \
  '[tool.a]\nmode = "tpl"\nenabled = true\n[tool.b]\nenabled = true\ntimeout = 2\n' \
  '[tool.a]\nmode = "x"\nenabled = true\n[tool.b]\nenabled = true\ntimeout = 1\n'
if [ "$hout" = "$(printf '[tool.a]\nmode = "mine"\nenabled = true\n[tool.b]\nenabled = true\ncustom = 42\ntimeout = 2')" ]
then ok "a line goes after its own neighbour, in its own table, not the first line with the same text"
else bad "helper, anchors by scope"; printf '%s\n%s\n' "$hout" "$hrep" | sed 's/^/        /'; fi
hc entries r.toml '[[tool.sources]]\nname = "mine"\nurl = "a"\n[[tool.sources]]\nname = "two"\nurl = "custom"\n' \
  '[[tool.sources]]\nname = "tpl1"\nurl = "a2"\n[[tool.sources]]\nname = "two"\nurl = "b2"\n' \
  '[[tool.sources]]\nname = "one"\nurl = "a"\n[[tool.sources]]\nname = "two"\nurl = "b"\n'
if [ "$hout" = "$(printf '[[tool.sources]]\nname = "mine"\nurl = "a2"\n[[tool.sources]]\nname = "two"\nurl = "custom"')" ]
then ok "each [[table]] entry is its own scope: the second entry's url stays there"
else bad "helper, array-of-tables entries"; printf '%s\n%s\n' "$hout" "$hrep" | sed 's/^/        /'; fi
# The fresh-context review of #1233: a comment above a step goes above that
# step, not the first `- name:`; an entry the template's added entry shifts is
# left for the person, never put in another entry.
hc stepcomment ci.yml '      - name: Setup\n        run: echo setup\n      # runs the tests\n      - name: Test\n        run: pytest\n' \
  '      - name: Setup\n        run: echo setup\n      - name: Test\n        run: pytest -q\n' \
  '      - name: Setup\n        run: echo setup\n      - name: Test\n        run: pytest\n' 'jobs:\n  t:\n    steps:\n'
if [ "$hout" = "$(printf 'jobs:\n  t:\n    steps:\n      - name: Setup\n        run: echo setup\n      # runs the tests\n      - name: Test\n        run: pytest -q')" ]
then ok "a comment above a YAML step goes above that step, once"
else bad "helper, a comment above a step"; printf '%s\n%s\n' "$hout" "$hrep" | sed 's/^/        /'; fi
hc shifted e.toml '[[s]]\nname = "one"\nurl = "a"\n[[s]]\nname = "two"\nurl = "custom"\n' \
  '[[s]]\nname = "new"\nurl = "n"\n[[s]]\nname = "one"\nurl = "a"\n[[s]]\nname = "two"\nurl = "b"\n' \
  '[[s]]\nname = "one"\nurl = "a"\n[[s]]\nname = "two"\nurl = "b"\n'
if grep -qxF $'risk\tno old place\t0\turl = "custom"' <<<"$hrep" && ! grep -q 'replaces' <<<"$hrep" \
   && [ "$(grep -c '^url = "custom"' <<<"$hout")" = 1 ] && grep -qxF 'url = "a"' <<<"$hout"
then ok "an entry the template's added [[table]] entry shifts is left for the person: no line is put in another entry"
else bad "helper, a shifted [[table]] entry"; printf '%s\n%s\n' "$hout" "$hrep" | sed 's/^/        /'; fi
# A TOML combination that does not parse is said: here the project's `b`
# has no old place and lands beside the head's own `b` (#1233).
hc parse d.toml 'a = 2\nb = 1\n' 'a = 3\n' 'a = 2\n' '[x]\nb = 0\n'
if grep -q $'^invalid\tTOML: ' <<<"$hrep"
then ok "a TOML combination that does not parse says so"
else bad "helper, an invalid TOML combination"; printf '%s\n%s\n' "$hout" "$hrep" | sed 's/^/        /'; fi



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

# ── GitLab (#1012, was not served before: #924) ─────────────────────────
# Told by origin's URL, or by `host: gitlab` in the answers file. The plan,
# --apply and --finish run copier as on GitHub; only what reads and writes
# the host changes: glab api for the project, its branch, its settings and a
# draft merge request. The mock answers for the project o/r on MOCK_GL_HOST
# (gitlab.com unless a case says otherwise) and logs every call.
cat > "$work/bin/glab" <<'MOCK'
#!/usr/bin/env bash
set -u
# The API host glab was told apart from --hostname (#1152), when there is one.
printf 'glab %s%s\n' "${GITLAB_API_HOST:+[api-host=$GITLAB_API_HOST] }" "$*" >> "$GLAB_LOG"
[ "${1:-}" = api ] || { echo "mock glab: unexpected: $*" >&2; exit 1; }
shift; method=GET; input=""; host=""; path=""
while [ $# -gt 0 ]; do
  case "$1" in
    -X | --method) method="$2"; shift 2 ;;
    --hostname)    host="$2"; shift 2 ;;
    --input)       input="$2"; shift 2 ;;
    -H | --header) shift 2 ;;
    --paginate)    shift ;;
    *)             path="$1"; shift ;;
  esac
done
# As glab 1.122.0 answers a port in --hostname (measured for #1152).
case "$host" in *:*) echo "Error parsing --hostname: invalid hostname." >&2; exit 1 ;; esac
[ "$host" = "${MOCK_GL_HOST:-gitlab.com}" ] || { echo "mock glab: no project on host '$host'" >&2; exit 1; }
case "$method $path" in
  "GET projects/o%2Fr")
    case "${MOCK_GL_PIPELINE:-on}" in
      on)     gate=',"only_allow_merge_if_pipeline_succeeds":true,"allow_merge_on_skipped_pipeline":false' ;;
      off)    gate=',"only_allow_merge_if_pipeline_succeeds":false,"allow_merge_on_skipped_pipeline":false' ;;
      absent) gate='' ;;
    esac
    printf '{"id":42,"path_with_namespace":"o/r","default_branch":"main"%s}\n' "$gate" ;;
  "GET projects/o%2Fr/repository/branches/main")
    printf '{"name":"main","commit":{"id":"%s"}}\n' "${MOCK_REMOTE_SHA:-$(git -C "$BARE" rev-parse main)}" ;;
  "GET projects/o%2Fr/protected_branches"*)
    [ "${MOCK_GL_PROTECTED:-main}" = unreadable ] && { echo '{"message":"403 Forbidden"}'; exit 1; }
    if [ "${MOCK_GL_PROTECTED:-main}" = none ]; then echo '[]'; else printf '[{"name":"%s"}]\n' "${MOCK_GL_PROTECTED:-main}"; fi ;;
  "GET projects/o%2Fr/merge_requests"*) cat "${MOCK_MR_EXISTING:-/dev/null}" 2>/dev/null || echo '[]' ;;
  "POST projects/o%2Fr/merge_requests")
    [ -e "${MOCK_MR_FAIL:-/nonexistent}" ] && { rm "$MOCK_MR_FAIL"; echo '{"message":"500 Internal Server Error"}'; exit 1; }
    cp "$input" "$GLAB_LOG.body"
    echo '{"iid":9,"web_url":"https://gitlab.com/o/r/-/merge_requests/9"}' ;;
  *) echo '{"message":"404 Not found"}'; exit 1 ;;
esac
MOCK
chmod +x "$work/bin/glab"
# A GitLab project at an old tag (or the target tag, for a move): the
# include of plinth's GitLab pipeline with its checksum, as the template
# renders it, and origin named by its GitLab URL, which git rewrites to the
# bare repository on disk.
gl_include="https://raw.githubusercontent.com/coolbress/plinth/$sha40/gitlab/python-ci.yml"
gl_int="sha256-L3/GAoKaw0Arw6hDCKeKQlV1QPEgHYxGBHsH4zG1IY8="
gl_fixture() { # <name> [<tag> <archetype>]
  fixture "$1"
  git -C "$repo" rm -q -r .github
  printf '_commit: %s\n_src_path: gh:coolbress/plinth-template\narchetype: %s\nhost: gitlab\n' "${2:-v1.0.0}" "${3:-cli}" > "$repo/.copier-answers.yml"
  printf 'include:\n  - remote: %s\n    integrity: %s\n' "$gl_include" "$gl_int" > "$repo/.gitlab-ci.yml"
  mkdir -p "$repo/.gitlab/merge_request_templates"; printf '## What and why\n' > "$repo/.gitlab/merge_request_templates/Default.md"
  git -C "$repo" add -A && git -C "$repo" commit -q -m "on GitLab" && git -C "$repo" push -q origin main
  local url="${MOCK_GL_URL:-https://${MOCK_GL_HOST:-gitlab.com}/o/r.git}"
  git -C "$repo" remote set-url origin "$url"
  git -C "$repo" config url."$BARE".insteadOf "$url"
}
no_post() { ! grep -qE -- '-X (POST|PUT)' "$work/glab.log"; }

gl_fixture gl-plan; reset_logs
want="$(python3 "$checker" --root "$repo" --repo o/r --host gitlab --print-update-command 2>/dev/null)"
base="$(git -C "$BARE" rev-parse main)"
run
if [ "$rc" = 0 ] && [ -n "$want" ] && grep -qF "Command:    $want" <<<"$out" && grep -qF "verified against GitLab" <<<"$out" \
   && grep -qF -- "--apply $base" <<<"$out"
then ok "GitLab: the plan prints the checker's own GitLab line (the include's pin and checksum) and the apply line"
else bad "GitLab plan (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
if [ ! -s "$work/gh.log" ] && grep -qF "api --hostname gitlab.com projects/o%2Fr/repository/branches/main" "$work/glab.log" && no_post \
   && [ ! -e "$work/uvx.log" ] && [ ! -e "$(wt_of gl-plan)" ]
then ok "GitLab: the plan reads the project through glab alone, never gh, and writes nothing"
else bad "GitLab plan's reads"; sed 's/^/        /' "$work/glab.log" "$work/gh.log"; fi
reset_logs
out="$(cd "$repo" && MOCK_REMOTE_SHA="$(printf '%040d' 2)" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" GLAB_LOG="$work/glab.log" UVX_LOG="$work/uvx.log" "$script" 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -q "not verified" <<<"$out" && grep -qF "GitLab's o/r main" <<<"$out" && [ ! -e "$work/uvx.log" ]
then ok "GitLab: origin/main that differs from GitLab's own main is not a verified base: stops"
else bad "GitLab unverified base (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# Self-hosted: the host glab is asked is origin's own.
export MOCK_GL_HOST=gitlab.example.com
gl_fixture gl-self; reset_logs; run
if [ "$rc" = 0 ] && grep -qF "api --hostname gitlab.example.com projects/o%2Fr" "$work/glab.log"
then ok "GitLab: on a self-hosted gitlab.* origin, glab is asked that host"
else bad "GitLab self-hosted (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
unset MOCK_GL_HOST
# A self-hosted GitLab on its own HTTPS port (#1152): glab refuses a port in
# --hostname, so the port goes to it as GITLAB_API_HOST beside the bare host.
# An ssh:// origin's port is the SSH server's: dropped.
export MOCK_GL_HOST=gitlab.example.com MOCK_GL_URL=https://gitlab.example.com:8443/o/r.git
gl_fixture gl-port; reset_logs; run
if [ "$rc" = 0 ] && grep -qF "glab [api-host=gitlab.example.com:8443] api --hostname gitlab.example.com projects/o%2Fr" "$work/glab.log" \
   && ! grep -q -- "--hostname [^ ]*:" "$work/glab.log"
then ok "GitLab on https://<host>:8443: glab is asked --hostname <host> with GITLAB_API_HOST=<host>:8443"
else bad "GitLab https port (rc=$rc)"; sed 's/^/        /' "$work/glab.log"; printf '%s\n' "$out" | sed 's/^/        /'; fi
gl_fixture gl-portmove "$target_ref" cli; reset_logs
out="$(cd "$repo" && MOCK_GL_PIPELINE=off MOCK_GL_PROTECTED=none PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" GLAB_LOG="$work/glab.log" UVX_LOG="$work/uvx.log" "$script" --archetype backend 2>&1)"; rc=$?
if grep -qF "GITLAB_API_HOST=gitlab.example.com:8443 glab api --hostname gitlab.example.com -X PUT projects/o%2Fr" <<<"$out" \
   && grep -qF "GITLAB_API_HOST=gitlab.example.com:8443 glab api --hostname gitlab.example.com -X POST projects/o%2Fr/protected_branches" <<<"$out"
then ok "  and the commands printed for a Maintainer carry the same port"
else bad "printed Maintainer commands on a port (rc=$rc)"; printf '%s\n' "$out" | grep -i glab | sed 's/^/        /'; fi
export MOCK_GL_URL=ssh://git@gitlab.example.com:2222/o/r.git
gl_fixture gl-sshport; reset_logs; run
if [ "$rc" = 0 ] && grep -qF "glab api --hostname gitlab.example.com projects/o%2Fr" "$work/glab.log" && ! grep -qF "api-host=" "$work/glab.log"
then ok "GitLab on ssh://<host>:2222: the SSH port is not the API's; glab is asked <host> alone"
else bad "GitLab ssh port (rc=$rc)"; sed 's/^/        /' "$work/glab.log"; printf '%s\n' "$out" | sed 's/^/        /'; fi
unset MOCK_GL_URL MOCK_GL_HOST

# The stop that is left: a checkout whose answers say GitLab, with an origin
# whose URL names no GitLab project.
fixture gl-noname; reset_logs
printf 'host: gitlab\n' >> "$repo/.copier-answers.yml"
run
if [ "$rc" = 1 ] && grep -qF "origin's URL names no GitLab project" <<<"$out" && [ ! -s "$work/gh.log" ] && [ ! -s "$work/glab.log" ] \
   && [ ! -e "$work/uvx.log" ] && [ ! -e "$(wt_of gl-noname)" ]
then ok "GitLab: an origin that names no project stops before glab, copier or a worktree"
else bad "GitLab, no project in origin (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# A GitHub repository whose path only contains the word is still GitHub's.
fixture gitlab-word; reset_logs
git -C "$repo" remote set-url origin https://github.com/o/gitlab-mirror.git
git -C "$repo" config url."$BARE".insteadOf https://github.com/o/gitlab-mirror.git
run
if [ "$rc" = 0 ] && ! grep -q "GitLab" <<<"$out" && [ ! -s "$work/glab.log" ]; then ok "a GitHub repository named gitlab-mirror is not taken for GitLab"
else bad "gitlab in a GitHub path (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# --apply: a clean update opens a draft merge request with copier's changes.
gl_fixture gl-clean; reset_logs
want="$(python3 "$checker" --root "$repo" --repo o/r --host gitlab --print-update-command 2>/dev/null)"
base="$(git -C "$BARE" rev-parse main)"
run --apply "$base" --assisted-by "Claude:claude-test-1"
wt="$(wt_of gl-clean)"; mr_body="$work/glab.log.body"
if [ "$rc" = 0 ] && [ "$(cat "$work/uvx.log" 2>/dev/null)" = "${want#uvx }" ] && grep -qF "Draft merge request: https://gitlab.com/o/r/-/merge_requests/9" <<<"$out"
then ok "GitLab --apply: copier runs the checker's words, then a draft merge request is opened"
else bad "GitLab clean apply (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
if [ -f "$mr_body" ] && [ "$(jq -r .title "$mr_body")" = "Draft: chore(template): update plinth-template v1.0.0 to $target_ref" ] \
   && [ "$(jq -r .source_branch "$mr_body")" = "chore/template-$target_ref" ] && [ "$(jq -r .target_branch "$mr_body")" = main ] \
   && jq -r .description "$mr_body" | grep -qF "Assisted-by: Claude:claude-test-1" \
   && jq -r .description "$mr_body" | grep -qF "when this merge request opened" \
   && ! jq -r .description "$mr_body" | grep -qiF "pull request"
then ok "GitLab: the merge request is a draft from the update branch into main, its description in merge-request words"
else bad "GitLab merge request body"; cat "$mr_body" 2>/dev/null | sed 's/^/        /'; fi
if [ "$(git -C "$BARE" rev-parse "refs/heads/chore/template-$target_ref" 2>/dev/null)" = "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" ] \
   && [ "$(git -C "$BARE" rev-parse main)" = "$base" ] && [ ! -s "$work/gh.log" ] \
   && grep -qxF "pr=https://gitlab.com/o/r/-/merge_requests/9" "$(git -C "$wt" rev-parse --absolute-git-dir)/plinth-template-update"
then ok "GitLab: the update branch is pushed, main is not, gh never runs, and the record keeps the merge request"
else bad "GitLab push/record"; fi
if jq -r .description "$mr_body" | grep -qF "\`diff-size\` was not counted here before pushing: on GitLab"
then ok "GitLab: the description says the size was not counted here, and that the pipeline's diff-size job counts it"
else bad "GitLab size line"; jq -r .description "$mr_body" | grep -i size | sed 's/^/        /'; fi

# A conflict stops before any merge request; --finish opens it once resolved.
# The first try at the merge request fails; the second finds the one GitLab
# made from this project at the pushed commit and opens no other.
gl_fixture gl-conflict; reset_logs; base="$(git -C "$BARE" rev-parse main)"
out="$(cd "$repo" && MOCK_COPIER=conflict PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" GLAB_LOG="$work/glab.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" 2>&1)"; rc=$?
wt="$(wt_of gl-conflict)"
if [ "$rc" = 3 ] && grep -qF CONTRIBUTING.md <<<"$out" && no_post && ! git -C "$BARE" rev-parse -q --verify "refs/heads/chore/template-$target_ref" >/dev/null
then ok "GitLab: a conflict stops at exit 3, nothing pushed and no merge request opened"
else bad "GitLab conflict (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
printf 'resolved\n' > "$wt/CONTRIBUTING.md"; git -C "$wt" add CONTRIBUTING.md
: > "$work/mr-fail"
out="$(cd "$repo" && MOCK_MR_FAIL="$work/mr-fail" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" GLAB_LOG="$work/glab.log" UVX_LOG="$work/uvx.log" "$script" --finish "$wt" --resolved CONTRIBUTING.md "took the template's side, on the user's word" 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -qF "opening the merge request failed" <<<"$out" && git -C "$BARE" rev-parse -q --verify "refs/heads/chore/template-$target_ref" >/dev/null
then ok "GitLab --finish: a merge request that fails to open leaves the branch pushed and says to run again"
else bad "GitLab finish, merge request failing (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
pushed="$(git -C "$wt" rev-parse HEAD)"
printf '[{"web_url":"https://gitlab.com/o/r/-/merge_requests/3","sha":"%s","source_project_id":7},{"web_url":"https://gitlab.com/o/r/-/merge_requests/8","sha":"%s","source_project_id":42}]\n' "$pushed" "$pushed" > "$work/mr-existing.json"
: > "$work/glab.log"
out="$(cd "$repo" && MOCK_MR_EXISTING="$work/mr-existing.json" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" GLAB_LOG="$work/glab.log" UVX_LOG="$work/uvx.log" "$script" --finish "$wt" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -qF "Draft merge request: https://gitlab.com/o/r/-/merge_requests/8" <<<"$out" && no_post
then ok "GitLab --finish again: adopts the merge request from this project at the pushed commit (not a fork's), opens no second"
else bad "GitLab finish adoption (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; sed 's/^/        /' "$work/glab.log"; fi

# An archetype move on GitLab: copier as on GitHub; in place of the required
# checks, the plan names "Pipelines must succeed" and the protected branch,
# as /plinth:floor-check reads them, and the command a Maintainer runs.
gl_fixture gl-move "$target_ref" cli; reset_logs; base="$(git -C "$BARE" rev-parse main)"
run --archetype backend
if [ "$rc" = 0 ] && grep -qF "Archetype:  cli -> backend" <<<"$out" && grep -qF ".gitlab-ci.yml: docker-image" <<<"$out" \
   && grep -qF '"Pipelines must succeed" on, skipped pipelines not counted' <<<"$out" && grep -qF "nothing to change in the project's settings" <<<"$out" \
   && grep -qF "main is protected on o/r" <<<"$out" && grep -qF "protected_branches?per_page=100 --paginate" "$work/glab.log" && grep -qF -- "--apply $base --archetype backend" <<<"$out" \
   && no_post && [ ! -s "$work/gh.log" ] && [ ! -e "$(awt_of gl-move backend)" ]
then ok "GitLab move plan: the job it starts, the merge gate in place of required checks, nothing to change, nothing written"
else bad "GitLab move plan (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
reset_logs
out="$(cd "$repo" && MOCK_GL_PIPELINE=off MOCK_GL_PROTECTED=none PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" GLAB_LOG="$work/glab.log" UVX_LOG="$work/uvx.log" "$script" --archetype backend 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -qF "only_allow_merge_if_pipeline_succeeds=false" <<<"$out" \
   && grep -qF "glab api --hostname gitlab.com -X PUT projects/o%2Fr -F only_allow_merge_if_pipeline_succeeds=true -F allow_merge_on_skipped_pipeline=false" <<<"$out" \
   && grep -qF "glab api --hostname gitlab.com -X POST projects/o%2Fr/protected_branches -f name=main -F push_access_level=0 -F merge_access_level=40 -F allow_force_push=false" <<<"$out" \
   && grep -qF "a Maintainer runs, with their own login (never the agent's)" <<<"$out" && no_post
then ok "GitLab move plan: a merge gate that is off and an unprotected main each name the command a Maintainer runs; none is run"
else bad "GitLab move plan, gate off (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
reset_logs
out="$(cd "$repo" && MOCK_GL_PIPELINE=absent MOCK_GL_PROTECTED=unreadable PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" GLAB_LOG="$work/glab.log" UVX_LOG="$work/uvx.log" "$script" --archetype backend 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -qF 'whether "Pipelines must succeed" is on was not read' <<<"$out" && grep -qF "whether main is protected was not read" <<<"$out" \
   && ! grep -qF "nothing to change in the project's settings" <<<"$out"
then ok "GitLab move plan: settings not read are said as not read, never as nothing to change"
else bad "GitLab move plan, unread (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
reset_logs
run --apply "$base" --archetype backend
mr_body="$work/glab.log.body"
if [ "$rc" = 0 ] && [ "$(jq -r .title "$mr_body" 2>/dev/null)" = "Draft: chore(template): move from the cli archetype to backend" ] \
   && jq -r .description "$mr_body" | grep -qF "docker-image" \
   && jq -r .description "$mr_body" | grep -qF '"Pipelines must succeed" on, skipped pipelines not counted' \
   && ! jq -r .description "$mr_body" | grep -qE "require-check|with-admin-token|Actions allowlist" && [ ! -s "$work/gh.log" ]
then ok "GitLab move --apply: a draft merge request whose by-hand section names GitLab's merge gate, not GitHub's checks"
else bad "GitLab move apply (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; jq -r .description "$mr_body" 2>/dev/null | sed 's/^/        /'; fi

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
# Undo (#1184): before merge and after, the plan's own lines, no home path.
undo="$(awk '/^To undo it, from the repository/ { f = 1; next } f && /^## / { exit } f' <<<"$body")"
n="$(basename "$wt")"
if grep -qxF "  gh pr close chore/template-$target_ref" <<<"$undo" && grep -qxF "  git push origin --delete chore/template-$target_ref" <<<"$undo" \
   && grep -qxF "  git worktree remove --force ../$n" <<<"$undo" && grep -qxF "  git branch -D chore/template-$target_ref" <<<"$undo" \
   && grep -qxF "  git worktree add -b revert/template-$target_ref ../$n-revert origin/main" <<<"$undo" \
   && grep -qF "revert --no-edit \"\$(gh pr view chore/template-$target_ref --json mergeCommit --jq .mergeCommit.oid)\"" <<<"$undo" \
   && grep -qxF "  (cd ../$n-revert && gh pr create --fill)" <<<"$undo" && ! grep -qF "$work" <<<"$body"
then ok "the description says how to undo it before it merges (close, delete branch and worktree) and after (revert in a pull request), in relative paths"
else bad "the description's undo"; printf '%s\n' "$undo" | sed 's/^/        /'; fi
# ── the description follows the form at the pinned tag (#856) ───────────
cp "$work/gh.log.body" "$work/clean.body"
fields_pass "the description of a clean update" "$work/clean.body"
checked="$(section "$work/clean.body" "What I checked myself")"
if grep -q "^Not a person's check" <<<"$checked" && ! grep -qi "no person" <<<"$checked" && tr '\n' ' ' <<<"$checked" | grep -q "conflict marker in a file the update changed" \
   && grep -q "reviewable lines" <<<"$checked" && grep -qi "plinth pin" <<<"$checked" \
   && ! grep -q "^Not checked yet" <<<"$checked"
then ok "What I checked myself says what the script checked (conflicts, size, pin) and that it is not a person's check, and leaves what was not checked to the Not verified line"
else bad "What I checked myself"; printf '%s\n' "$checked" | sed 's/^/        /'; fi
# The template's own line, worded as its CONTRIBUTING.md step 5 gives it (#1020):
# one `Not verified: ` line, the last of How it was verified before `Review:`.
verified="$(section "$work/clean.body" "How it was verified" | grep -v '^$')"
if [ "$(grep -c '^Not verified: ' <<<"$verified")" = 1 ] \
   && [ "$(grep -B1 '^Review: ' <<<"$verified" | head -1)" = "$(grep '^Not verified: ' <<<"$verified")" ] \
   && grep '^Not verified: ' <<<"$verified" | grep -q "still works after the update" \
   && grep '^Not verified: ' <<<"$verified" | grep -q "had not run" \
   && ! grep -qE '^Not (verified here|checked yet)' "$work/clean.body"
then ok "How it was verified ends with the template's Not verified: line, saying the repository's own checks had not run"
else bad "the Not verified: line"; printf '%s\n' "$verified" | sed 's/^/        /'; fi
if grep -qx 'Review: none (no review had run when this pull request opened)' "$work/clean.body"
then ok "the Review: line says no review has run"
else bad "the Review: line"; sed 's/^/        /' "$work/clean.body"; fi
# The form at the pinned commit, from one checkout (tests/lib/template-checkout.sh).
# shellcheck source=tests/lib/template-checkout.sh
. "$root/tests/lib/template-checkout.sh"
if ! template_checkout "$work"; then
  bad "no checkout of the template: $template_error; cannot verify the description against its form"
elif cp "$template_dir/template/.github/PULL_REQUEST_TEMPLATE.md" "$work/form.md" 2>/dev/null && [ -s "$work/form.md" ]; then
  if said="$(form_fields "$work/form.md" "$work/clean.body")"; then ok "the description writes every field of the form at $target_ref, in its order"
  else bad "the description against the form at $target_ref"; printf '%s\n' "$said" | sed 's/^/        /'; fi
  { cat "$work/form.md"; printf '\n## A field the form gained\n'; } > "$work/form-more.md"
  if said="$(form_fields "$work/form-more.md" "$work/clean.body")"; then bad "a form that gained a heading passes"
  else ok "a form that gained a heading the script does not write fails ($said)"; fi
  { cat "$work/form.md"; printf '\nRisk: <!-- a label -->\n'; } > "$work/form-label.md"
  if said="$(form_fields "$work/form-label.md" "$work/clean.body")"; then bad "a form that gained a label line passes"
  else ok "a form that gained a label line the script does not write fails ($said)"; fi
else
  bad "$template_at has no template/.github/PULL_REQUEST_TEMPLATE.md; cannot verify the description against it"
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
# --finish runs before the plan's code in the script: the undo lines must be
# defined by then (review on #1206).
if grep -qxF "  gh pr close $(git -C "$wt" rev-parse --abbrev-ref HEAD)" <<<"$body" && ! grep -qF "command not found" <<<"$out"
then ok "a conflict resolved through --finish: the description says how to undo it too"
else bad "the undo after --finish"; printf '%s\n%s\n' "$out" "$body" | sed 's/^/        /'; fi
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
# Newer than the pin the target tag was tested with: the update keeps it.
mkdir -p "$FLOOR_CHECK_API_DIR/repos/coolbress/plinth/compare"
printf '{"status":"behind","behind_by":1}\n' > "$FLOOR_CHECK_API_DIR/repos/coolbress/plinth/compare/$raised...$sha40.json"
run --apply "$(git -C "$BARE" rev-parse main)"
if [ "$rc" = 0 ] && grep -q -- "--data plinth_sha=$raised$no_shared\$" "$work/uvx.log"; then ok "copier is given the pin the workflows carry today, not the one first rendered"
else bad "raised pin (rc=$rc): uvx got '$(cat "$work/uvx.log" 2>/dev/null)'"; fi

# ── the plinth pin: raised first, never moved by the update (#511, #1183) ─
tested="$(printf '%040d' 8)"
pin_api="$work/api-pin"
mkdir -p "$pin_api/repos/coolbress/plinth/compare"
tested_is "$pin_api" "$tested"
printf '{"status":"ahead","ahead_by":2}\n' > "$pin_api/repos/coolbress/plinth/compare/$sha40...$tested.json"
tag_names "$pin_api" "$target_sha"
pinrun() { # <fixture dir> <args...>: run with that API fixture
  local api="$1"; shift
  out="$(cd "$repo" && FLOOR_CHECK_API_DIR="$api" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" "$@" 2>&1)"; rc=$?
}
# What the plan and --apply may not touch when they stop: the worktree list,
# the branches and every file under .git but those a fetch rewrites.
git_state() { # <repo>
  git -C "$1" worktree list --porcelain
  git -C "$1" for-each-ref --format='%(refname) %(objectname)' refs/heads
  (cd "$1/.git" && find . -type f ! -name FETCH_HEAD ! -path './logs/*' ! -path './refs/remotes/*' ! -name packed-refs -exec shasum {} + | sort)
}
# The open pull requests: #12 raises the plinth pin in ci.yml and label.yml,
# #13 changes something else.
pulls_open() { # <fixture dir>
  mkdir -p "$1/repos/o/r/pulls/12" "$1/repos/o/r/pulls/13"
  printf '[{"number":12,"title":"chore(deps): bump coolbress/plinth"},{"number":13,"title":"docs: a typo"}]\n' > "$1/repos/o/r/pulls?state=open&per_page=100.json"
  jq -n --arg a "$sha40" --arg b "$tested" '[{filename: ".github/workflows/ci.yml", patch: ("-    uses: coolbress/plinth/.github/workflows/python-ci.yml@" + $a + "\n+    uses: coolbress/plinth/.github/workflows/python-ci.yml@" + $b + " # v9.0.0")}]' \
    > "$1/repos/o/r/pulls/12/files?per_page=100.json"
  printf '[{"filename":"README.md","patch":"+uses: coolbress/plinth/x@y"}]\n' > "$1/repos/o/r/pulls/13/files?per_page=100.json"
}
labelled() { # a label.yml calling plinth at $sha40, as the template renders it
  printf 'jobs:\n  label:\n    uses: coolbress/plinth/.github/workflows/label.yml@%s\n' "$sha40" > "$repo/.github/workflows/label.yml"
  git -C "$repo" add -A && git -C "$repo" commit -q -m label && git -C "$repo" push -q origin main
}

# The live pin older than the tested one, with the pin's pull request open:
# the plan stops before anything is written and names it.
pr_api="$work/api-pin-pr"; rm -rf "$pr_api"; cp -R "$pin_api" "$pr_api"; pulls_open "$pr_api"
fixture pinbehind; labelled; reset_logs
git -C "$repo" fetch -q origin; git_before="$(git_state "$repo")"
pinrun "$pr_api"
if [ "$rc" = 1 ] && grep -q "^no update command: the plinth pin is behind; the workflows call $sha40; $target_ref was tested with $tested, 2 commit(s) newer" <<<"$out" \
   && grep -qF "https://github.com/coolbress/plinth/compare/$sha40...$tested" <<<"$out" \
   && grep -q "^merge first: #12 chore(deps): bump coolbress/plinth (https://github.com/o/r/pull/12)" <<<"$out" && ! grep -q "#13" <<<"$out" \
   && grep -q "^Nothing has been written" <<<"$out" && ! grep -q "^Command:" <<<"$out" && ! grep -q -- "--apply" <<<"$out"
then ok "a live pin older than the tested one: the plan exits 1, names both SHAs, the compare and the open pin pull request (#1183)"
else bad "plan, pin behind, pull request open (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
if [ "$git_before" = "$(git_state "$repo")" ] && [ ! -e "$(wt_of pinbehind)" ] && [ ! -e "$work/uvx.log" ] \
   && [ "$(git -C "$repo" for-each-ref --format='%(refname)' refs/heads)" = refs/heads/main ]
then ok "and it writes nothing: no worktree, no branch, no change under .git but the fetch, no copier"
else bad "the stopped plan wrote something"; diff <(printf '%s\n' "$git_before") <(git_state "$repo") | sed 's/^/        /'; fi
# --apply on the same base stops the same way, before anything is created.
reset_logs; pinrun "$pr_api" --apply "$(git -C "$BARE" rev-parse main)"
if [ "$rc" = 1 ] && grep -q "^merge first: #12 " <<<"$out" && grep -q "nothing was created" <<<"$out" \
   && [ "$git_before" = "$(git_state "$repo")" ] && [ ! -e "$(wt_of pinbehind)" ] && [ ! -e "$work/uvx.log" ] && ! grep -q "pr create" "$work/gh.log"
then ok "--apply with the pin behind stops the same way: no worktree, no branch, no copier, nothing opened"
else bad "--apply, pin behind (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# No open pull request changes the pin: the plan prints the change to make,
# every file that calls plinth at the one tested SHA, and makes none.
none_api="$work/api-pin-nopr"; rm -rf "$none_api"; cp -R "$pin_api" "$none_api"; mkdir -p "$none_api/repos/o/r"
printf '[]\n' > "$none_api/repos/o/r/pulls?state=open&per_page=100.json"
reset_logs; pinrun "$none_api"
if [ "$rc" = 1 ] && grep -q "^no open pull request changes the plinth uses: lines" <<<"$out" \
   && grep -q "^raise it first in one pull request of its own: every coolbress/plinth uses: line in .github/workflows/ci.yml, .github/workflows/label.yml to $tested, all at that one SHA; merge it, then plan the update again" <<<"$out" \
   && [ "$git_before" = "$(git_state "$repo")" ] && [ "$(git -C "$repo" status --porcelain)" = "" ] && ! grep -q "^Command:" <<<"$out"
then ok "the pin behind and no pull request open: the plan prints the change to ci.yml and label.yml at one SHA, and makes none"
else bad "plan, pin behind, no pull request (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# The open pull requests not read: said, and the change printed.
reset_logs; pinrun "$pin_api"
if [ "$rc" = 1 ] && grep -q "^the open pull requests were not read (offline or API error)" <<<"$out" && grep -q "^raise it first in one pull request" <<<"$out"
then ok "the open pull requests not read: said, never read as none, and the change printed"
else bad "plan, pin behind, pulls unread (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# Live equal to the tested one (every other case here) or newer: no stop.
equal_api="$work/api-pin-equal"; rm -rf "$equal_api"; mkdir -p "$equal_api"; tag_names "$equal_api" "$target_sha"
fixture pinequal; reset_logs; pinrun "$equal_api"
if [ "$rc" = 0 ] && grep -q "^Plinth pin: the workflows call $sha40, the one $target_ref was tested with$" <<<"$out" && grep -q "^Command: .*plinth_sha=$sha40$no_shared\$" <<<"$out" \
   && grep -qF -- "--apply $(git -C "$BARE" rev-parse main)" <<<"$out" && ! grep -q -- "--plinth-pin" <<<"$out"
then ok "the live pin equal to the tested one: the plan goes on, one --apply line and no pin choice"
else bad "plan, pin equal (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
behind_api="$work/api-pin-newer"; rm -rf "$behind_api"; cp -R "$pin_api" "$behind_api"
printf '{"status":"behind","behind_by":3}\n' > "$behind_api/repos/coolbress/plinth/compare/$sha40...$tested.json"
reset_logs; pinrun "$behind_api"
if [ "$rc" = 0 ] && grep -q "^Plinth pin: the workflows call $sha40, newer than $tested that $target_ref was tested with; the update keeps it" <<<"$out" \
   && grep -q "^Command: .*plinth_sha=$sha40$no_shared\$" <<<"$out" && ! grep -q -- "--plinth-pin" <<<"$out"
then ok "the live pin newer than the tested one: the plan goes on with the live pin, and says it is kept"
else bad "plan, pin newer (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# The tested pin unreadable, or the two not compared: a stop that says what
# was not read, never an update as if the pin were current.
unread_api="$work/api-pin-unread"; rm -rf "$unread_api"; mkdir -p "$unread_api/repos/coolbress/plinth-template/contents"
printf 'not json\n' > "$unread_api/repos/coolbress/plinth-template/contents/copier.yml?ref=$target_sha.json"; tag_names "$unread_api" "$target_sha"
reset_logs; pinrun "$unread_api"
if [ "$rc" = 1 ] && grep -q "^no update command: whether the plinth pin is older than the one $target_ref was tested with was not read; the one $target_ref was tested with was not read (coolbress/plinth-template copier.yml at $target_ref: offline or API error)" <<<"$out" \
   && ! grep -q "^Command:" <<<"$out" && [ ! -e "$(wt_of pinequal)" ]
then ok "the tested pin unreadable: the plan stops and says what it could not read"
else bad "plan, tested unread (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
uncmp_api="$work/api-pin-uncompared"; rm -rf "$uncmp_api"; cp -R "$pin_api" "$uncmp_api"; rm "$uncmp_api/repos/coolbress/plinth/compare/$sha40...$tested.json"
reset_logs; pinrun "$uncmp_api" --apply "$(git -C "$BARE" rev-parse main)"
if [ "$rc" = 1 ] && grep -q "$target_ref was tested with $tested, but the two were not compared (offline or API error)" <<<"$out" \
   && grep -q "nothing was created" <<<"$out" && [ ! -e "$(wt_of pinequal)" ] && [ ! -e "$work/uvx.log" ] \
   && grep -q "^run it again if a read failed; otherwise raise the plinth pin to $tested or a later plinth release" <<<"$out"
then ok "the two pins not compared: --apply stops before anything is created, says so, and how to get past it"
else bad "--apply, pins uncompared (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# A pin raised by hand in the workflows, not in the answers file (#1015):
# copier's old render names the recorded plinth_sha. The line carries the
# pin the workflows call, so the uses: line is not in conflict for that; the
# plan says so before anything is written.
recorded="$(printf '%040d' 6)"
handraised() { # <name> <recorded plinth_sha>: answers record it, ci.yml and label.yml call $sha40
  fixture "$1"
  printf 'plinth_sha: %s\n' "$2" >> "$repo/.copier-answers.yml"
  printf 'jobs:\n  label:\n    uses: coolbress/plinth/.github/workflows/label.yml@%s\n' "$sha40" > "$repo/.github/workflows/label.yml"
  printf 'jobs:\n  own:\n    runs-on: ubuntu-latest\n' > "$repo/.github/workflows/own.yml"
  git -C "$repo" add -A && git -C "$repo" commit -q -m "raise the pin by hand" && git -C "$repo" push -q origin main
}
handraised pinhand "'$recorded'  # quoted, with a comment"; reset_logs
run
if [ "$rc" = 0 ] && grep -q "^Pin conflict: .*records plinth_sha $recorded; the workflows call $sha40" <<<"$out" \
   && grep -q "The update carries the pin the workflows call: no conflict on that line is expected" <<<"$out" && ! grep -q "keep the side" <<<"$out"
then ok "a pin raised by hand, the live pin carried: the plan says no conflict on that line is expected"
else bad "hand-raised pin, live carried (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# The recorded plinth_sha equal to the workflows': nothing new.
handraised pinrecorded "$sha40"; reset_logs
run
if [ "$rc" = 0 ] && ! grep -q "Pin conflict" <<<"$out"
then ok "the recorded plinth_sha equal to the workflows' pin: the plan says nothing of a pin conflict"
else bad "recorded equal to live (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# An answers file with CRLF line endings: the recorded pin is still read.
handraised pincrlf "$recorded"
sed -i.bak $'s/$/\r/' "$repo/.copier-answers.yml" && rm "$repo/.copier-answers.yml.bak"
git -C "$repo" commit -q -am crlf && git -C "$repo" push -q origin main; reset_logs
run
if [ "$rc" = 0 ] && grep -q $'\r' "$repo/.copier-answers.yml" \
   && grep -q "^Pin conflict: .*records plinth_sha $recorded; the workflows call $sha40\.$" <<<"$out"
then ok "an answers file with CRLF line endings: the recorded pin is read"
else bad "CRLF answers file (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# No plinth_sha recorded at all (every older fixture): nothing new either.
fixture pinnorecord; reset_logs
run
if [ "$rc" = 0 ] && ! grep -q "Pin conflict" <<<"$out"
then ok "no plinth_sha recorded: the plan says nothing of a pin conflict"
else bad "no recorded pin (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# A version comment on the plinth uses: line (#1045), as Dependabot writes it
# and plinth's README shows it: the template renders the line with none, so
# once the line carries another pin than the recorded one, copier meets two
# changed sides and leaves the line in conflict, even where both name the
# same pin. The plan says so, and that either side runs the same plinth.
commented() { # <file>...: a `# v2.41.0` after each plinth pin
  local f
  for f in "$@"; do sed -i.bak 's/^\(    uses: coolbress\/plinth\/.*@[0-9a-f]*\)$/\1 # v2.41.0/' "$repo/.github/workflows/$f" && rm "$repo/.github/workflows/$f.bak"; done
  git -C "$repo" commit -q -am "a version comment" && git -C "$repo" push -q origin main
}
handraised pincomment "$recorded"; commented ci.yml label.yml; reset_logs
run
said="$(grep -A2 "^ *The update leaves" <<<"$out" | tr '\n' ' ')"
if [ "$rc" = 0 ] && grep -q "# v2.41.0" "$repo/.github/workflows/ci.yml" \
   && grep -q "^Pin conflict: .*records plinth_sha $recorded; the workflows call $sha40" <<<"$out" \
   && grep -q "in conflict in ci.yml, label.yml " <<<"$said" && grep -q "both sides name $sha40: they differ only by the trailing comment" <<<"$said" \
   && ! grep -q "no conflict on that line is expected" <<<"$out" && [ ! -e "$(wt_of pincomment)" ]
then ok "a pin raised by hand with a version comment, the live pin carried: the plan says the line conflicts by the comment alone (#1045)"
else bad "a commented pin, live carried (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# The plan's line only names files; nothing is written before --apply.
if [ "$(grep -n "^Pin conflict:" <<<"$out" | cut -d: -f1)" -lt "$(grep -n "^Nothing has been written" <<<"$out" | cut -d: -f1)" ]
then ok "the expected conflict is said before the --apply line"
else bad "pin conflict line placement"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# One file with the comment, one without: only the commented one is named.
handraised pincommentone "$recorded"; commented label.yml; reset_logs
run
if [ "$rc" = 0 ] && grep -q "in conflict in label.yml (" <<<"$out" && ! grep -q "in conflict in ci.yml" <<<"$out"
then ok "only the workflow whose line carries a comment is named (#1045)"
else bad "one commented file (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# The workflows at the recorded pin, with a comment: the line carries that
# pin, which copier's two renders name alike, so the comment stays and no
# conflict is said.
handraised pincommentrecorded "$sha40"; commented ci.yml label.yml; reset_logs
run
if [ "$rc" = 0 ] && ! grep -q "Pin conflict" <<<"$out" && grep -q "# v2.41.0" "$repo/.github/workflows/ci.yml"
then ok "the recorded pin with a version comment, carried as it is: no pin conflict said (#1045)"
else bad "a commented recorded pin (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# A comment on another line of the file, not the uses: line, changes nothing.
handraised pincommentelse "$recorded"
printf '# v2.41.0 is the version\n' >> "$repo/.github/workflows/ci.yml"
git -C "$repo" commit -q -am "a comment elsewhere" && git -C "$repo" push -q origin main; reset_logs
run
if [ "$rc" = 0 ] && grep -q "no conflict on that line is expected" <<<"$out" && ! grep -q "trailing comment" <<<"$out"
then ok "a comment elsewhere in the file: no conflict said (#1045)"
else bad "a comment elsewhere (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# --apply runs the live line, and the description says nothing of a pin
# choice; the plan's pin line is in what the script checked.
fixture pinapply; reset_logs
pinrun "$behind_api" --apply "$(git -C "$BARE" rev-parse main)"
body="$(cat "$work/gh.log.body" 2>/dev/null)"
if [ "$rc" = 0 ] && grep -q -- "--vcs-ref $target_sha --data plinth_sha=$sha40$no_shared\$" "$work/uvx.log" \
   && ! grep -q "The plinth pin:" <<<"$body" && ! grep -q -- "--plinth-pin" <<<"$body"
then ok "--apply runs copier with the live SHA, and the description offers no pin choice"
else bad "--apply, live (rc=$rc): uvx got '$(cat "$work/uvx.log" 2>/dev/null)'"; printf '%s\n%s\n' "$out" "$body" | sed 's/^/        /'; fi
if section "$work/gh.log.body" "What I checked myself" | grep -q "^- The plan's plinth pin line: the workflows call $sha40, newer than $tested"
then ok "What I checked myself carries the plan's plinth pin line"
else bad "the plan's pin line"; sed 's/^/        /' "$work/gh.log.body"; fi

# --plinth-pin is gone (#1183): in any form, exit 2 with the new order, so
# an older skill text never gets the live pin unawares.
fixture pinflag
for args in "--apply $(git -C "$BARE" rev-parse main) --plinth-pin tested" "--apply $(git -C "$BARE" rev-parse main) --plinth-pin live" \
            "--plinth-pin tested" "--plinth-pin=tested" "--plinth-pin"; do
  reset_logs
  # shellcheck disable=SC2086 # the words of one case
  pinrun "$pin_api" $args
  if [ "$rc" = 2 ] && grep -q "^template-update: --plinth-pin is gone: .*the plan stops and names the pull request that raises it; merge that first" <<<"$out" \
     && [ ! -e "$work/uvx.log" ] && [ ! -e "$(wt_of pinflag)" ]
  then ok "$args: exit 2 with the new order, nothing run"
  else bad "$args (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
done

# ── the target tag names another commit than plinth was tested with (#519)
moved_api="$work/api-moved"; rm -rf "$moved_api"; cp -R "$pin_api" "$moved_api"
tag_names "$moved_api" "$(printf '%040d' 5)"
fixture tagmoved; reset_logs
pinrun "$moved_api"
if [ "$rc" = 1 ] && grep -q "$target_ref now names commit $(printf '%040d' 5), not $target_sha" <<<"$out" && ! grep -q -- "--apply" <<<"$out"
then ok "a moved target tag: the plan stops, names both commits, and offers no --apply line"
else bad "plan, moved tag (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
reset_logs
pinrun "$moved_api" --apply "$(git -C "$BARE" rev-parse main)"
if [ "$rc" = 1 ] && [ ! -e "$work/uvx.log" ] && ! grep -q "pr create" "$work/gh.log" && grep -q "now names commit" <<<"$out"
then ok "a moved target tag: --apply stops before copier, opens nothing"
else bad "--apply, moved tag (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
git -C "$repo" worktree remove --force "$(dirname "$repo")/$(basename "$repo")-template-$target_ref" 2>/dev/null
git -C "$repo" branch -q -D "chore/template-$target_ref" 2>/dev/null
unread_api="$work/api-tag-unread"; rm -rf "$unread_api"; cp -R "$equal_api" "$unread_api"
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

# ── the printed --finish line survives a path with spaces and Hangul ────
spaced="$work/내 Projects"; mkdir -p "$spaced"
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
# Copied off a screen: the path is printed as typed, inside single quotes,
# not as the escaped bytes of bash 3.2's printf %q (#1065).
if grep -qF -- "--finish '$wt'" <<<"$line"; then ok "the printed --finish line shows a path with Hangul as typed"
else bad "the printed --finish line does not show the path as typed: '$line'"; fi
if [ "$rc" = 0 ] && grep -q "pr create" "$work/gh.log"; then ok "the printed --finish line runs as printed under a directory with a space and Hangul"
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
# The same, with a third pin recorded (#1015): label.yml meets the recorded
# pin, its own and the carried one, so it conflicts; ci.yml does not.
two_fixture pins-recorded; reset_logs
printf 'plinth_sha: %s\n' "$(printf '%040d' 6)" >> "$repo/.copier-answers.yml"
git -C "$repo" commit -q -am record && git -C "$repo" push -q origin main
out="$(cd "$repo" && FLOOR_CHECK_API_DIR="$work/api-behind" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q "^Pin conflict: .*the workflows call $sha40 and $old_pin\.$" <<<"$out" \
   && grep -q "^ *The update leaves the plinth uses: line in conflict in label.yml (" <<<"$out" \
   && grep -q "keep the side naming $sha40" <<<"$out"
then ok "a Moves: file at an older pin with a third pin recorded: the plan names it as a conflict, and ci.yml not"
else bad "plan, moves with a recorded pin (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
repo="$work/pins-behind"; BARE="$work/pins-behind.git"; export BARE   # back to the case the apply below reads
reset_logs
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
   && grep -q "more than one commit and the update cannot carry one (above); nothing was created" <<<"$out" && ! grep -q "pr create" "$work/gh.log" \
   && [ ! -e "$(wt_of pins-unread)" ]
then ok "two pins and the compare unread at the apply: it stops before any worktree, names why, opens nothing"
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

# ── an archetype move (#1004) ───────────────────────────────────────────
# A data-ml project at the target tag, with the model example, the image job
# and a file of its own, moved to cli: the plan rehearses copier outside the
# repository and names what goes, what comes, the CI jobs that stop and the
# command for a required check that stops; --apply makes the draft.
move_fixture() { # <name>
  fixture "$1"
  printf '_commit: %s\n_src_path: gh:coolbress/plinth-template\narchetype: data-ml\n' "$target_ref" > "$repo/.copier-answers.yml"
  printf 'jobs:\n  ci:\n    uses: coolbress/plinth/.github/workflows/python-ci.yml@%s\n  image:\n    runs-on: ubuntu-latest\n' "$sha40" > "$repo/.github/workflows/ci.yml"
  mkdir -p "$repo/src/demo" "$repo/tests" "$repo/data"
  printf 'model\n' > "$repo/MODEL_CARD.md"; printf 'train\n' > "$repo/src/demo/train.py"
  printf 'test\n' > "$repo/tests/test_train.py"; printf 'data\n' > "$repo/data/README.md"
  printf 'FROM x\n' > "$repo/Dockerfile"; printf 'data-ml pyproject\n' > "$repo/pyproject.toml"
  printf 'data-ml main\n' > "$repo/src/demo/__main__.py"; printf 'data-ml lock\n' > "$repo/uv.lock"
  printf 'def own():\n    return 1\n' > "$repo/src/demo/own.py"
  # export-ignore leaves a path out of `git archive`: the rehearsal must see it (review on #1004).
  printf 'tests/ export-ignore\n' > "$repo/.gitattributes"
  git -C "$repo" add -A && git -C "$repo" commit -q -m "data-ml at the target tag" && git -C "$repo" push -q origin main
}

# The plan writes each admin command to a file and prints `bash <file>`
# (#1045): what the plan says, then each file it names, as a person reads it.
with_admin() { # <plan output>
  printf '%s\n' "$1"
  sed -n 's/^    bash \(.*\.sh\)$/\1/p' <<<"$1" | while IFS= read -r f; do cat "$f"; done
}
move_fixture move-plan; reset_logs
base="$(git -C "$BARE" rev-parse main)"; before_status="$(git -C "$repo" status --porcelain)"
# The one case that reads the default folder for the admin commands.
out="$(cd "$repo" && unset TEMPLATE_UPDATE_ADMIN_TMP && MOCK_REQUIRED="ci / test,image" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --archetype cli 2>&1)"; rc=$?
plan_said="$out"; out="$(with_admin "$out")"
# Each line naming a command a person runs with an admin token fits 120
# characters, and the line before it says where to run it (#1045).
admin_files="$(sed -n 's/^    bash \(.*\.sh\)$/\1/p' <<<"$plan_said")"
long="$(awk '/^    bash / && length($0) > 120' <<<"$plan_said")"
if [ "$rc" = 0 ] && [ -n "$admin_files" ] && [ "$(wc -l <<<"$admin_files" | tr -d ' ')" = 1 ] && [ -z "$long" ] && [[ "$admin_files" == /tmp/plinth-admin.* ]] \
   && grep -B1 '^    bash ' <<<"$plan_said" | head -n 1 | grep -qF "in a separate terminal, not through !" \
   && grep -qxF "$root/scripts/with-admin-token.sh $root/scripts/require-check.sh --drop --repo o/r 'image'" "$admin_files"
then ok "the drop command is a file outside the repository: the plan prints bash <file> in $(awk '/^    bash /{ print length($0) }' <<<"$plan_said") characters, to run in a separate terminal (#1045)"
else bad "the admin command file (rc=$rc)"; printf '%s\n' "$plan_said" | sed 's/^/        /'; fi
[ -z "$admin_files" ] || { rm -f "$admin_files"; rmdir "$(dirname "$admin_files")"; }
plan_ok=1
for want in "Archetype:  data-ml -> cli, at $target_ref" "--data archetype=cli" \
            "Deletes:" "  MODEL_CARD.md" "  src/demo/train.py" "  tests/test_train.py" "  data/README.md" "  Dockerfile" \
            "Adds:" "  tests/test_built_wheel.py" "CI jobs that stop:" "  .github/workflows/ci.yml: image" \
            "Conflicts:  none" \
            "Required check that stops running: image, required on main now. Before the move's pull request merges, a person runs, with an admin token (never the agent's):" \
            "with-admin-token.sh $root/scripts/require-check.sh --drop --repo o/r 'image'" \
            "--apply $base --archetype cli"; do
  grep -qF -- "$want" <<<"$out" || { plan_ok=0; bad "the move's plan lacks: $want"; }
done
[ "$plan_ok" = 1 ] && [ "$rc" = 0 ] && ok "the move's plan names the files it deletes and adds, the CI job that stops, the drop command and the apply line"
[ "$plan_ok" = 1 ] && [ "$rc" = 0 ] || printf '%s\n' "$out" | sed 's/^/        /'
if grep -qF "  src/demo/own.py" <<<"$out"; then bad "the plan lists the project's own file"; else ok "the plan does not list the project's own file"; fi
if ! grep -qF "Changed by this repository" <<<"$out" && ! grep -qF -- "--keep" <<<"$out" && [ -s "$work/uvx.log.recopy" ]
then ok "every deleted file as the old archetype rendered it: deleted as before, nothing new in the plan (#1016)"
else bad "unchanged deletes (#1016)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
if [ "$(git -C "$repo" status --porcelain)" = "$before_status" ] && [ ! -e "$(awt_of move-plan cli)" ] \
   && ! git -C "$repo" rev-parse -q --verify refs/heads/chore/archetype-cli >/dev/null && [ "$(git -C "$BARE" rev-parse main)" = "$base" ] \
   && ! grep -qxF "$repo" "$work"/uvx.log.cwd.* 2>/dev/null
then ok "the plan rehearses copier outside the repository: no worktree, no branch, the checkout unchanged"
else bad "the move's plan wrote something"; fi
rm -f "$work"/uvx.log.cwd.*
out="$(cd "$repo" && MOCK_REQUIRED="ci / test" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --archetype cli 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -qF "image stops running, and no ruleset requires it on main: nothing to drop. Classic branch protection is not read" <<<"$out" && ! grep -qF -- "--drop" <<<"$out"
then ok "a check that stops but is not required: no drop command"
else bad "not required (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
out="$(cd "$repo" && MOCK_REQUIRED=unreadable PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --archetype cli 2>&1)"; rc=$?; out="$(with_admin "$out")"
if [ "$rc" = 0 ] && grep -qF "whether main requires image was not read" <<<"$out" && grep -qF -- "require-check.sh --drop --repo o/r 'image'" <<<"$out"
then ok "the required checks unread: says so, and still names the drop command"
else bad "unread rules (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
out="$(cd "$repo" && MOCK_MOVE_FAIL=1 PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --archetype cli 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -qF "Validation error for question 'archetype'" <<<"$out" && grep -qF "copier refused the move in the rehearsal" <<<"$out" \
   && [ ! -e "$(awt_of move-plan cli)" ]
then ok "copier refusing the move (a colliding package name) stops the plan with copier's sentence"
else bad "refused move (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
run --finish "$work/x" --archetype cli
[ "$rc" = 2 ] && ok "--finish with an archetype move: a usage error" || bad "--finish $work/x --archetype cli: exit $rc, expected 2"
run --apply "$base" --archetype web
if [ "$rc" = 1 ] && [ ! -e "$(awt_of move-plan web)" ] && ! git -C "$repo" rev-parse -q --verify refs/heads/chore/archetype-web >/dev/null
then ok "--apply with an archetype the checker refuses stops before a worktree or branch exists"
else bad "--apply --archetype web (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
run --archetype web
if [ "$rc" = 1 ] && grep -qF "no move command: web is not moved to or from here" <<<"$out"; then ok "a move to web stops with the checker's reason"
else bad "move to web (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
run --archetype dashboard
if [ "$rc" = 1 ] && grep -qF "no move command: dashboard is not moved to or from here" <<<"$out"; then ok "a move to dashboard stops with the checker's reason (#1069)"
else bad "move to dashboard (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
fixture move-old; reset_logs
run --archetype library
if [ "$rc" = 1 ] && grep -qF "update the template first" <<<"$out" && [ ! -e "$work/uvx.log" ]; then ok "a move behind the target tag stops before copier: update first"
else bad "move behind the tag (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# The Actions allowlist (#1018): the door allows only the release actions of
# the archetype it renders, and a move does not change the setting. The plan
# names each action the moved workflows use that the allowlist refuses, with
# the command a person runs; one that allows them, or one not read, is said.
allowlist_at() { # <api dir> <pattern>...: a selected-actions allowlist, as the door sets it
  local d="$1"; shift
  mkdir -p "$d/repos/o/r/actions/permissions"; [ -e "$d/repos/coolbress/plinth-template" ] || tag_names "$d" "$target_sha"
  printf '{"enabled":true,"allowed_actions":"selected","sha_pinning_required":true}\n' > "$d/repos/o/r/actions/permissions.json"
  printf '{"github_owned_allowed":true,"verified_allowed":false,"patterns_allowed":%s}\n' \
    "$(printf '%s\n' "$@" | jq -R . | jq -sc .)" > "$d/repos/o/r/actions/permissions/selected-actions.json"
}
allow_cmd() { # <prefix> <pattern>...: the command the plan gives, under <prefix>
  local pre="$1" w="" a; shift
  for a in "$@"; do w="$w -f 'patterns_allowed[]=$a'"; done
  printf '%swith-admin-token.sh gh api -X PUT repos/o/r/actions/permissions/selected-actions -F github_owned_allowed=true -F verified_allowed=false%s\n' "$pre" "$w"
}
dataml_api="$work/api-allow-data-ml"; allowlist_at "$dataml_api" 'coolbress/plinth/*'
move_fixture move-allow-data-ml; reset_logs; base="$(git -C "$BARE" rev-parse main)"
out="$(cd "$repo" && FLOOR_CHECK_API_DIR="$dataml_api" MOCK_REQUIRED="ci / test" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --archetype cli 2>&1)"; rc=$?; out="$(with_admin "$out")"
if [ "$rc" = 0 ] && grep -qF "The Actions allowlist refuses pypa/gh-action-pypi-publish (.github/workflows/release.yml line 5), which the workflows use after the move" <<<"$out" \
   && grep -qF "$(allow_cmd "$root/scripts/" 'coolbress/plinth/*' 'pypa/gh-action-pypi-publish@*')" <<<"$out" \
   && [ "$(grep -n -- "--apply $base" <<<"$out" | cut -d: -f1)" -gt "$(grep -nF "The Actions allowlist refuses" <<<"$out" | cut -d: -f1)" ]
then ok "data-ml to cli under data-ml's allowlist: the plan names pypa's publish action and the command that allows it (#1018)"
else bad "data-ml to cli, allowlist refuses (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
dataml_ok_api="$work/api-allow-data-ml-ok"; allowlist_at "$dataml_ok_api" 'coolbress/plinth/*' 'pypa/gh-action-pypi-publish@*'
out="$(cd "$repo" && FLOOR_CHECK_API_DIR="$dataml_ok_api" MOCK_REQUIRED="ci / test" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --archetype cli 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -qF "The Actions allowlist lets every action the workflows use after the move start (2 uses): nothing to allow." <<<"$out" \
   && ! grep -qF "allowlist refuses" <<<"$out" && ! grep -qF "actions/permissions/selected-actions" <<<"$out"
then ok "an allowlist that already allows them: said, and no command (#1018)"
else bad "allowlist allows (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
out="$(cd "$repo" && MOCK_REQUIRED="ci / test" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --archetype cli 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -qF "Whether the Actions allowlist lets every action the workflows use after the move start was not read" <<<"$out" \
   && ! grep -qF "actions/permissions/selected-actions" <<<"$out" && grep -qF -- "--apply $base --archetype cli" <<<"$out"
then ok "an allowlist that cannot be read: the plan says it was not read, and still gives the apply line (#1018)"
else bad "allowlist unread (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# --apply: the move as rendered, in a draft.
move_fixture move-apply; reset_logs
base="$(git -C "$BARE" rev-parse main)"
out="$(cd "$repo" && MOCK_REQUIRED="ci / test,image" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" --archetype cli --assisted-by "Claude:claude-test-1" 2>&1)"; rc=$?
wt="$(awt_of move-apply cli)"
if [ "$rc" = 0 ] && [ "$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)" = chore/archetype-cli ] && grep -q -- "--draft" "$work/gh.log"
then ok "--apply --archetype cli opens a draft from chore/archetype-cli"
else bad "move apply (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
names="$(git -C "$wt" show --name-status --format= HEAD 2>/dev/null)"
if grep -qx "D	MODEL_CARD.md" <<<"$names" && grep -qx "D	src/demo/train.py" <<<"$names" && grep -qx "D	tests/test_train.py" <<<"$names" \
   && grep -qx "A	tests/test_built_wheel.py" <<<"$names" && ! grep -q "own.py" <<<"$names" && [ -f "$wt/src/demo/own.py" ] \
   && grep -qx "archetype: cli" "$wt/.copier-answers.yml"
then ok "the commit deletes the model files, adds tests/test_built_wheel.py, keeps the project's own file, and the answers record cli"
else bad "the move's commit"; printf '%s\n' "$names" | sed 's/^/        /'; fi
body="$(cat "$work/gh.log.body" 2>/dev/null)"
if grep -qF "chore(template): move from the data-ml archetype to cli" "$work/gh.log" \
   && grep -qF -- "- tests/test_built_wheel.py" <<<"$(section "$work/gh.log.body" "What and why")" \
   && grep -qF "scripts/with-admin-token.sh scripts/require-check.sh --drop --repo o/r 'image'" <<<"$body" \
   && ! grep -qF "$root" <<<"$body"
then ok "the description names the move, the added test, and the drop command from plinth's folder, with no local path"
else bad "the move's description"; printf '%s\n' "$body" | sed 's/^/        /'; fi
what_why="$(section "$work/gh.log.body" "What and why" | tr '\n' ' ')"
if ! grep -qF "left unchanged and keeps its own" <<<"$what_why" \
   && grep -qF "none of the files it deletes had been changed by this repository" <<<"$what_why"
then ok "the description says what copier deletes, and that none of it was changed here (#1016)"
else bad "the move's sentence (#1016)"; printf '%s\n' "$what_why" | sed 's/^/        /'; fi
cp "$work/gh.log.body" "$work/move.body"; fields_pass "the description of an archetype move" "$work/move.body"
if [ -n "${template_dir:-}" ] && [ -s "$work/form.md" ]; then
  if said="$(form_fields "$work/form.md" "$work/move.body")"; then ok "the move's description writes every field of the form, in its order"
  else bad "the move's description against the form"; printf '%s\n' "$said" | sed 's/^/        /'; fi
fi

# --apply on a project that deleted the model by hand: the three measured
# conflicts stop it, showing this repository's side of each before anything
# is resolved; resolved to the template's side, --finish opens the draft.
move_fixture move-hand; reset_logs
git -C "$repo" rm -rq MODEL_CARD.md src/demo/train.py tests/test_train.py data
git -C "$repo" commit -q -m "model deleted by hand" && git -C "$repo" push -q origin main
base="$(git -C "$BARE" rev-parse main)"
out="$(cd "$repo" && MOCK_MOVE=handdel MOCK_REQUIRED="image" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" --archetype cli 2>&1)"; rc=$?
wt="$(awt_of move-hand cli)"
if [ "$rc" = 3 ] && grep -qF "This repository's side of src/demo/__main__.py" <<<"$out" && grep -qF "    own_helper()" <<<"$out" \
   && grep -qF "This repository's side of pyproject.toml" <<<"$out" && grep -qF "uv.lock: generated; after pyproject.toml is resolved, uv lock in the worktree makes it again" <<<"$out" \
   && ! grep -q "pr create" "$work/gh.log" && ! git -C "$BARE" rev-parse -q --verify refs/heads/chore/archetype-cli >/dev/null
then ok "the hand-deleted move stops at the three conflicts, showing this repository's side of each, nothing pushed"
else bad "hand-deleted move (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
for f in pyproject.toml src/demo/__main__.py uv.lock; do
  awk '/^<<<<<<< before updating$/ { s = 1; next } /^=======$/ && s { s = 2; next } /^>>>>>>> after updating$/ { s = 0; next } s != 1' "$wt/$f" > "$wt/$f.new" && mv "$wt/$f.new" "$wt/$f"
  git -C "$wt" add "$f"
done
# As a move a plinth before #1016 left at its conflicts: its record carries
# no comparison, and the description must not claim one (review on #1016).
sf="$(git -C "$wt" rev-parse --absolute-git-dir)/plinth-template-update"
grep -v '^compared=' "$sf" > "$sf.old" && mv "$sf.old" "$sf"
out="$(cd "$repo" && PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --finish "$wt" \
  --resolved pyproject.toml "the template's side, on the user's word" --resolved src/demo/__main__.py "the template's side, on the user's word" \
  --resolved uv.lock "the template's side, then uv lock, on the user's word" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q "pr create" "$work/gh.log" && git -C "$wt" show --name-status --format= HEAD | grep -qx "A	tests/test_built_wheel.py" \
   && grep -qF "src/demo/__main__.py: the template's side, on the user's word" "$work/gh.log.body"
then ok "resolved to the template's side, --finish opens the draft with the added test and each resolution"
else bad "hand-deleted finish (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
what_why="$(section "$work/gh.log.body" "What and why" | tr '\n' ' ')"
if grep -qF "was not compared" <<<"$what_why" && ! grep -qF "none of the files it deletes had been changed" <<<"$what_why"
then ok "a record with no comparison: the description says it was not compared (review on #1016)"
else bad "no comparison recorded"; printf '%s\n' "$what_why" | sed 's/^/        /'; fi

# A file only the old archetype ships, changed by the project (#1016):
# copier deletes it all the same, reporting no conflict. The plan lists it
# apart; --apply stops before anything is written until each is named,
# --keep restoring it after copier, --drop letting it go.
move_changed() { # <name>
  move_fixture "$1"
  printf 'own line\n' >> "$repo/src/demo/train.py"; printf 'own card line\n' >> "$repo/MODEL_CARD.md"
  git -C "$repo" commit -q -am "the project's own training code" && git -C "$repo" push -q origin main
  base="$(git -C "$BARE" rev-parse main)"
}
move_changed move-own; reset_logs
out="$(cd "$repo" && MOCK_REQUIRED="image" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --archetype cli 2>&1)"; rc=$?
apart="$(awk '/^Changed by this repository/ { f = 1; next } /^[^ ]/ { f = 0 } f' <<<"$out")"
dels="$(awk '/^Deletes:/ { f = 1; next } /^[^ ]/ { f = 0 } f' <<<"$out")"
if [ "$rc" = 0 ] && [ "$apart" = "$(printf '  MODEL_CARD.md\n  src/demo/train.py')" ] \
   && ! grep -qxF "  src/demo/train.py" <<<"$dels" && ! grep -qxF "  MODEL_CARD.md" <<<"$dels" && grep -qxF "  tests/test_train.py" <<<"$dels" \
   && grep -qF -- "--keep <path>" <<<"$out" && grep -qF -- "--drop <path>" <<<"$out"
then ok "the plan lists the changed files the move deletes apart, with --keep and --drop"
else bad "changed files in the plan (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
wt="$(awt_of move-own cli)"
stops_clean() { # <what>
  if [ "$rc" = 1 ] && [ ! -e "$wt" ] && ! git -C "$repo" rev-parse -q --verify refs/heads/chore/archetype-cli >/dev/null \
     && ! grep -q "pr create" "$work/gh.log"
  then ok "$1"; else bad "$1 (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
}
run --apply "$base" --archetype cli
stops_clean "--apply with neither named stops before a worktree or branch exists"
grep -qF "src/demo/train.py" <<<"$out" && grep -qF "MODEL_CARD.md" <<<"$out" && grep -qF -- "--keep" <<<"$out" \
  && ok "and names each changed file and the choice" || bad "the stop names the files"
run --apply "$base" --archetype cli --keep src/demo/train.py
stops_clean "--apply with one of two named stops"
grep -qF "MODEL_CARD.md" <<<"$out" && ok "and names the one left" || bad "the one left is named"
run --apply "$base" --archetype cli --keep src/demo/train.py --drop MODEL_CARD.md --keep tests/test_train.py
stops_clean "--keep for a file the move deletes unchanged stops"
run --apply "$base" --archetype cli --keep src/demo/train.py --drop src/demo/train.py --drop MODEL_CARD.md
stops_clean "a file both kept and dropped stops"
for args in "--keep src/demo/train.py" "--archetype cli --drop MODEL_CARD.md" "--apply $base --keep src/demo/train.py"; do
  run $args
  [ "$rc" = 2 ] && ok "$args outside --apply --archetype: a usage error" || bad "$args: exit $rc, expected 2"
done
run --apply "$base" --archetype cli --keep src/demo/train.py --drop MODEL_CARD.md --assisted-by "Claude:claude-test-1"
names="$(git -C "$wt" show --name-status --format= HEAD 2>/dev/null)"
if [ "$rc" = 0 ] && grep -q "pr create" "$work/gh.log" && ! grep -q "	src/demo/train.py$" <<<"$names" && grep -qx "D	MODEL_CARD.md" <<<"$names" \
   && grep -qx "D	tests/test_train.py" <<<"$names" \
   && [ "$(git -C "$wt" show HEAD:src/demo/train.py 2>/dev/null)" = "$(printf 'train\nown line')" ]
then ok "--keep restores the file after copier and the commit carries it; --drop deletes it"
else bad "keep and drop (rc=$rc)"; printf '%s\n%s\n' "$out" "$names" | sed 's/^/        /'; fi
body="$(cat "$work/gh.log.body" 2>/dev/null)"
what_why="$(section "$work/gh.log.body" "What and why" | tr '\n' ' ')"
if grep -qF -- "- src/demo/train.py: kept (\`--keep\`)" <<<"$body" && grep -qF -- "- MODEL_CARD.md: deleted (\`--drop\`)" <<<"$body" \
   && grep -qF "only as the person chose" <<<"$what_why" && ! grep -qF "left unchanged and keeps its own" <<<"$what_why"
then ok "the description names each changed file with the person's choice"
else bad "keep and drop in the description"; printf '%s\n' "$body" | sed 's/^/        /'; fi
move_changed move-recopy; reset_logs
out="$(cd "$repo" && MOCK_RECOPY_FAIL=1 PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --archetype cli 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -qF "the old archetype's render" <<<"$out" && ! grep -q "^Deletes:" <<<"$out"
then ok "the old render failing stops the plan: no Deletes list that could not be compared"
else bad "recopy failing (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

# A move that adds a required check (#1017): cli to backend starts `image`,
# which require-check.sh refuses before it has run on main, while the move's
# own `ci / floor-check` reads the new archetype. The plan says whether the
# plinth the workflows call passes it (its floor-check.py at that commit
# carries the rule), and the order: merge, let image run, then require it;
# with an older plinth, raise the pin first, and --apply refuses the move.
floor_at_pin() { # <api dir> <has the rule: yes|no>
  local text='def other():'; [ "$2" = yes ] && text='def archetype_gained(repo):'
  mkdir -p "$1/repos/coolbress/plinth/contents/scripts"; tag_names "$1" "$target_sha"
  printf '{"encoding":"base64","content":"%s"}' "$(printf '%s\n    pass\n' "$text" | base64 | tr -d '\n')" \
    > "$1/repos/coolbress/plinth/contents/scripts/floor-check.py?ref=$sha40.json"
}
held_api="$work/api-floor-held"; floor_at_pin "$held_api" yes
fails_api="$work/api-floor-fails"; floor_at_pin "$fails_api" no
move_cli() { # <name>
  fixture "$1"
  printf '_commit: %s\n_src_path: gh:coolbress/plinth-template\narchetype: cli\n' "$target_ref" > "$repo/.copier-answers.yml"
  git -C "$repo" commit -q -am "cli at the target tag" && git -C "$repo" push -q origin main
  base="$(git -C "$BARE" rev-parse main)"
}
plinth_ver="$(sed -nE 's/^[[:space:]]*"version":[[:space:]]*"([^"]+)".*/\1/p' "$root/.claude-plugin/plugin.json" | head -n 1)"
move_cli move-add; reset_logs; add_at=("$repo" "$BARE" "$base")
out="$(cd "$repo" && FLOOR_CHECK_API_DIR="$held_api" MOCK_REQUIRED="ci / test" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --archetype backend 2>&1)"; rc=$?
out="$(with_admin "$out")"
held_line="image starts running. The move's pull request passes ci / floor-check before image is required: the plinth its workflows call (${sha40:0:12}) reads a check the move adds as not required yet; until image is required, ci / floor-check fails on main and on every pull request brought up to date with it. Once the move is merged and image has run on main, a person requires it, with an admin token (never the agent's): the file below, which holds the command, in a separate terminal, not through ! (with-admin-token.sh asks for the token at a terminal, which ! does not give it):"
if [ "$rc" = 0 ] && grep -qxF "$held_line" <<<"$out" && grep -qxF "$root/scripts/with-admin-token.sh $root/scripts/require-check.sh --repo o/r 'image'" <<<"$out" && grep -qF -- "--apply $base --archetype backend" <<<"$out" \
   && [ "$(grep -n -- "--apply $base" <<<"$out" | cut -d: -f1)" -gt "$(grep -nF "image starts running" <<<"$out" | cut -d: -f1)" ] \
   && ! grep -q "check-add" <<<"$out"
then ok "a move to backend, with a plinth that has the rule: merge, let image run on main, then require it, in that order (#1017)"
else bad "a move that adds image, rule held (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
out="$(cd "$repo" && FLOOR_CHECK_API_DIR="$fails_api" MOCK_REQUIRED="ci / test" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --archetype backend 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -qF "image starts running, and the plinth the workflows call (${sha40:0:12}) fails the move's ci / floor-check until image is required, which require-check.sh refuses before image has run on main. Raise the plinth pin first: merge a pull request that moves every coolbress/plinth uses: line to plinth v$plinth_ver or later" <<<"$out" \
   && grep -qF "Raise the plinth pin first (above);" <<<"$out" && ! grep -qF -- "--apply $base" <<<"$out" && ! grep -qF "require-check.sh --repo" <<<"$out"
then ok "with a plinth that lacks the rule, the plan says to raise the plinth pin first and gives no apply line (#1017)"
else bad "a move that adds image, rule missing (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
out="$(cd "$repo" && FLOOR_CHECK_API_DIR="$fails_api" MOCK_REQUIRED="ci / test" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" --archetype backend 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -qF "raise the plinth pin to v$plinth_ver or later first" <<<"$out" && [ ! -e "$(awt_of move-add backend)" ] \
   && ! git -C "$repo" rev-parse -q --verify refs/heads/chore/archetype-backend >/dev/null && ! grep -q "pr create" "$work/gh.log"
then ok "--apply refuses that move before a worktree or branch exists (#1017)"
else bad "--apply with the rule missing (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# A cli project that already requires its own `image` job (Codex review on
# #1029): any plinth's floor check finds it required, so no pin raise.
move_cli move-add-req; reset_logs
out="$(cd "$repo" && FLOOR_CHECK_API_DIR="$fails_api" MOCK_REQUIRED="ci / test,image" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --archetype backend 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -qF "image starts running, and main already requires it: nothing to add" <<<"$out" \
   && grep -qF -- "--apply $base --archetype backend" <<<"$out" && ! grep -qF "Raise the plinth pin first" <<<"$out"
then ok "image already required: the plan asks for no pin raise and gives the apply line, whatever the plinth"
else bad "a move that adds an image already required (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
out="$(cd "$repo" && FLOOR_CHECK_API_DIR="$fails_api" MOCK_REQUIRED="ci / test,image" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" --archetype backend 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q "pr create" "$work/gh.log" && grep -qF "image starts running, and main already requires it" "$work/gh.log.body"
then ok "and --apply opens the move's draft"
else bad "--apply with image already required (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
repo="${add_at[0]}"; BARE="${add_at[1]}"; base="${add_at[2]}"; reset_logs
out="$(cd "$repo" && MOCK_REQUIRED="ci / test" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --archetype backend 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -qF "image starts running; whether the plinth the workflows call passes the move's ci / floor-check before image is required was not read (scripts/floor-check.py at that commit could not be read). This plinth (v$plinth_ver) does" <<<"$out" \
   && grep -qF -- "--apply $base --archetype backend" <<<"$out"
then ok "the plinth at the pin unread: says so, names the version that passes, and still gives the apply line"
else bad "a move that adds image, plinth unread (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
out="$(cd "$repo" && FLOOR_CHECK_API_DIR="$held_api" MOCK_REQUIRED="ci / test" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" --archetype backend --assisted-by "Claude:claude-test-1" 2>&1)"; rc=$?
body="$(cat "$work/gh.log.body" 2>/dev/null)"
if [ "$rc" = 0 ] && grep -qF "chore(template): move from the cli archetype to backend" "$work/gh.log" \
   && grep -qF -- "- image starts running. The move's pull request passes ci / floor-check before image is required" <<<"$body" \
   && grep -qF "\`scripts/with-admin-token.sh scripts/require-check.sh --repo o/r 'image'\`" <<<"$body" && ! grep -qF "$root" <<<"$body"
then ok "the move's description gives the same order, with the command from plinth's folder (#1017)"
else bad "the description of a move that adds image (rc=$rc)"; printf '%s\n%s\n' "$out" "$body" | sed 's/^/        /'; fi

# cli to backend under cli's allowlist (#1018): docker's two actions are
# refused, and the command keeps what the allowlist already allows.
cli_api="$work/api-allow-cli"; cp -R "$held_api" "$cli_api"; allowlist_at "$cli_api" 'coolbress/plinth/*' 'pypa/gh-action-pypi-publish@*'
backend_allow="$(allow_cmd "" 'coolbress/plinth/*' 'pypa/gh-action-pypi-publish@*' 'docker/build-push-action@*' 'docker/setup-buildx-action@*')"
move_cli move-allow; reset_logs
out="$(cd "$repo" && FLOOR_CHECK_API_DIR="$cli_api" MOCK_REQUIRED="ci / test" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --archetype backend 2>&1)"; rc=$?; out="$(with_admin "$out")"
if [ "$rc" = 0 ] && grep -qF "The Actions allowlist refuses docker/setup-buildx-action (.github/workflows/release.yml line 5), docker/build-push-action (.github/workflows/release.yml line 6), which the workflows use after the move" <<<"$out" \
   && grep -qF "$root/scripts/$backend_allow" <<<"$out" && grep -qF -- "--apply $base --archetype backend" <<<"$out"
then ok "cli to backend under cli's allowlist: the plan names docker's two actions and one command that keeps pypa's (#1018)"
else bad "cli to backend, allowlist refuses (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
out="$(cd "$repo" && FLOOR_CHECK_API_DIR="$cli_api" MOCK_REQUIRED="ci / test" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" --archetype backend --assisted-by "Claude:claude-test-1" 2>&1)"; rc=$?
body="$(cat "$work/gh.log.body" 2>/dev/null)"
if [ "$rc" = 0 ] && grep -qF -- "- The Actions allowlist refuses docker/setup-buildx-action" <<<"$body" \
   && grep -qF "\`scripts/$backend_allow\`" <<<"$body" && ! grep -qF "$root" <<<"$body"
then ok "the move's description carries the allowlist command in its by-hand list, from plinth's folder (#1018)"
else bad "the description's allowlist line (rc=$rc)"; printf '%s\n%s\n' "$out" "$body" | sed 's/^/        /'; fi

# A move whose release.yml alone is over ci / diff-size's 400 (#1044), as
# #1017's cli to backend run was: the template rewrites it whole. A plinth
# whose ci / diff-size leaves it out of the count in the pull request that
# changes archetype: lets the rest split by file and the last part open
# within the limit; with one that counts it, the plan says to raise the pin
# first and --apply refuses.
size_at_pin() { # <api dir> <has the rule: yes|no>
  local text='# Measure'; [ "$2" = yes ] && text='          # An archetype move (#1044): .copier-answers.yml changes archetype:'
  mkdir -p "$1/repos/coolbress/plinth/contents/.github/workflows"
  printf '{"encoding":"base64","content":"%s"}' "$(printf '%s\n' "$text" | base64 | tr -d '\n')" \
    > "$1/repos/coolbress/plinth/contents/.github/workflows/python-ci.yml?ref=$sha40.json"
}
size_held_api="$work/api-size-held"; cp -R "$held_api" "$size_held_api"; size_at_pin "$size_held_api" yes
size_fails_api="$work/api-size-fails"; cp -R "$held_api" "$size_fails_api"; size_at_pin "$size_fails_api" no
move_cli_big() { # <name>
  move_cli "$1"
  for i in $(seq 1 450); do echo "      # pypi step $i"; done > "$repo/.github/workflows/release.yml"
  git -C "$repo" add -A && git -C "$repo" commit -q -m "cli's release.yml" && git -C "$repo" push -q origin main
  base="$(git -C "$BARE" rev-parse main)"
}
rel_said="changes 556 lines, over ci / diff-size's limit of 400 by itself, and a split by file cannot cut one file"
move_cli_big move-size; reset_logs
out="$(cd "$repo" && MOCK_RELEASE=big FLOOR_CHECK_API_DIR="$size_held_api" MOCK_REQUIRED="ci / test" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --archetype backend 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -qF ".github/workflows/release.yml $rel_said. The plinth the workflows call (${sha40:0:12}) leaves it out of the count in the pull request that changes archetype: (#1044)" <<<"$out" \
   && grep -qF -- "--apply $base --archetype backend" <<<"$out" && ! grep -q "diff-size-move" <<<"$out"
then ok "a move whose release.yml alone is over 400, plinth with the rule: the plan says it is left out of the count, and gives the apply line (#1044)"
else bad "release.yml over the limit, rule held, plan (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
out="$(cd "$repo" && MOCK_RELEASE=big FLOOR_CHECK_API_DIR="$size_held_api" MOCK_REQUIRED="ci / test" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" --archetype backend --assisted-by "Claude:claude-test-1" 2>&1)"; rc=$?
wt="$(awt_of move-size backend)"
first="$(sed -n '/^Proposed split/,/^This update keeps/p' <<<"$out")"
rest="$(sed -n '/^This update keeps/,/^$/p' <<<"$out")"
if [ "$rc" = 4 ] && grep -q "^Over the limit: 4[0-9][0-9] reviewable lines, against the limit of 400" <<<"$out" \
   && grep -qxF "  src/serve.py" <<<"$first" && grep -qF "  .copier-answers.yml (" <<<"$rest" \
   && grep -qxF "  .github/workflows/release.yml (556, not counted: an archetype move, #1044)" <<<"$rest" && ! grep -q "release.yml" <<<"$first" \
   && ! grep -q "pr create" "$work/gh.log"
then ok "--apply counts the move without release.yml and proposes a split by file, release.yml kept with the answers file"
else bad "release.yml over the limit, rule held, split (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
( set -e; while IFS= read -r l; do eval "$l"; done < <(sed -n '/^To make the first/,/^then open/p' <<<"$out" | sed -n 's/^  \(git .*\)$/\1/p') ) >/dev/null 2>&1
git -C "$BARE" update-ref refs/heads/main "$(git -C "$wt-part-1" rev-parse HEAD)"   # the first part is merged
( while IFS= read -r l; do eval "$l"; done < <(sed -n '/^Once it is merged/,/^$/p' <<<"$out" | sed -n 's/^  \(git .*\)$/\1/p') ) >/dev/null 2>&1
reset_logs; run --finish "$wt" --assisted-by "Claude:claude-test-1"
body="$(cat "$work/gh.log.body" 2>/dev/null)"
if [ "$rc" = 0 ] && grep -q "pr create" "$work/gh.log" && grep -qF "counted here before pushing: 152 reviewable lines, within the limit of 400" <<<"$body" \
   && grep -qF "\`.github/workflows/release.yml\` (556 lines) is not in that count: an archetype move" <<<"$body" \
   && git -C "$wt" diff --name-only "$(git -C "$BARE" rev-parse main)" HEAD | grep -qx ".github/workflows/release.yml"
then ok "run as printed, the first part merged, the move's last part opens within the limit with release.yml, saying it is not counted (#1044)"
else bad "release.yml over the limit, rule held, last part (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; printf '%s\n' "$body" | sed 's/^/        /'; fi
move_cli_big move-size-fails; reset_logs
out="$(cd "$repo" && MOCK_RELEASE=big FLOOR_CHECK_API_DIR="$size_fails_api" MOCK_REQUIRED="ci / test" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --archetype backend 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -qF ".github/workflows/release.yml $rel_said. The plinth the workflows call (${sha40:0:12}) counts it, so the move's last pull request would fail ci / diff-size however it is split. Raise the plinth pin first" <<<"$out" \
   && grep -qF "whose ci / diff-size leaves .github/workflows/release.yml out of the move's count" <<<"$out" && ! grep -qF -- "--apply $base" <<<"$out"
then ok "with a plinth that counts it, the plan says to raise the plinth pin first and gives no apply line (#1044)"
else bad "release.yml over the limit, rule missing, plan (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
out="$(cd "$repo" && MOCK_RELEASE=big FLOOR_CHECK_API_DIR="$size_fails_api" MOCK_REQUIRED="ci / test" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" --archetype backend 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -qF "raise the plinth pin to v$plinth_ver or later first" <<<"$out" && [ ! -e "$(awt_of move-size-fails backend)" ] \
   && ! git -C "$repo" rev-parse -q --verify refs/heads/chore/archetype-backend >/dev/null && ! grep -q "pr create" "$work/gh.log"
then ok "--apply refuses that move before a worktree or branch exists (#1044)"
else bad "release.yml over the limit, rule missing, --apply (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
out="$(cd "$repo" && MOCK_RELEASE=big FLOOR_CHECK_API_DIR="$held_api" MOCK_REQUIRED="ci / test" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --archetype backend 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -qF ".github/workflows/release.yml $rel_said. Whether the plinth the workflows call leaves it out of the count in the move's pull request was not read (.github/workflows/python-ci.yml at that commit could not be read). This plinth (v$plinth_ver) does" <<<"$out" \
   && grep -qF -- "--apply $base --archetype backend" <<<"$out"
then ok "the plinth's python-ci.yml unread: the plan says so, names the version that does, and gives the apply line"
else bad "release.yml over the limit, rule unread, plan (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
out="$(cd "$repo" && MOCK_RELEASE=big FLOOR_CHECK_API_DIR="$held_api" MOCK_REQUIRED="ci / test" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" --archetype backend 2>&1)"; rc=$?
if [ "$rc" = 4 ] && grep -qF ".github/workflows/release.yml alone is 556 lines" <<<"$out" \
   && grep -qF "was not read when the move was applied (.github/workflows/python-ci.yml at that commit could not be read), and --finish does not read it again." <<<"$out" \
   && grep -qF "open this part with --over-limit (below)" <<<"$out" && ! grep -q "pr create" "$work/gh.log"
then ok "applied with the plinth unread: --finish counts release.yml, says it does not read the plinth again, and names --over-limit (review on #1044)"
else bad "release.yml over the limit, rule unread, --apply (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
# The project's own diff-size-exclude already leaves release.yml out (Codex
# review on #1052): nothing to refuse, whatever the plinth.
move_cli_big move-size-excluded; reset_logs
own_exclude="*.md *.lock .github/workflows/release.yml"
out="$(cd "$repo" && MOCK_CI_EXCLUDE="$own_exclude" MOCK_RELEASE=big FLOOR_CHECK_API_DIR="$size_fails_api" MOCK_REQUIRED="ci / test" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --archetype backend 2>&1)"; rc=$?
if [ "$rc" = 0 ] && ! grep -qF "release.yml changes" <<<"$out" && grep -qF -- "--apply $base --archetype backend" <<<"$out"
then ok "release.yml in the project's own diff-size-exclude: the plan asks for no pin raise and gives the apply line"
else bad "release.yml excluded by the project, plan (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
out="$(cd "$repo" && MOCK_CI_EXCLUDE="$own_exclude" MOCK_RELEASE=big FLOOR_CHECK_API_DIR="$size_fails_api" MOCK_REQUIRED="ci / test" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --apply "$base" --archetype backend 2>&1)"; rc=$?
if [ "$rc" = 4 ] && ! grep -qF "raise the plinth pin" <<<"$out" && ! grep -qF "release.yml alone" <<<"$out" && [ -e "$(awt_of move-size-excluded backend)" ]
then ok "and --apply goes ahead: the rest is over the limit and split by file"
else bad "release.yml excluded by the project, --apply (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi
move_cli move-size-small; reset_logs
out="$(cd "$repo" && FLOOR_CHECK_API_DIR="$size_fails_api" MOCK_REQUIRED="ci / test" PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" UVX_LOG="$work/uvx.log" "$script" --archetype backend 2>&1)"; rc=$?
if [ "$rc" = 0 ] && ! grep -qF "release.yml changes" <<<"$out" && grep -qF -- "--apply $base --archetype backend" <<<"$out"
then ok "a release.yml within the limit: the plan says nothing of it, whatever the plinth"
else bad "release.yml within the limit, plan (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/        /'; fi

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
# The archetype move's steps sit one level down, in reference.md.
skill_text="$(cat "$skill" "$root/skills/template-update/reference.md" | tr '\n' ' ' | tr -s ' ')"
if grep -qF '`## What and why`, `## What I checked myself`, `## How it was verified` and a `Review:` line' <<<"$skill_text" \
   && ! grep -qF 'two headings' <<<"$skill_text"
then ok "the skill names the form's four fields, not two headings"
else bad "the skill's fields"; fi
if grep -qF "run the project's default review" <<<"$skill_text" && grep -qF 'replace the `Review:` line with what ran' <<<"$skill_text"
then ok "the skill says the agent runs the default review and replaces the Review: line with what ran"
else bad "the skill's review step"; fi
if ! grep -qF 'Nothing else changes outside the files' <<<"$skill_text" \
   && grep -qF 'Outside the files, only the required checks and the Actions allowlist change with the archetype' <<<"$skill_text"
then ok "the skill says the Actions allowlist changes with the archetype too (#1018)"
else bad "the skill's outside-the-files sentence"; fi
if ! grep -qF 'GitLab is not served yet' <<<"$skill_text" && grep -qF 'On GitLab it runs the same steps through `glab`' <<<"$skill_text" \
   && grep -qF 'a draft merge request' <<<"$skill_text"
then ok "the skill says GitLab is served through glab, with a draft merge request (#1012)"
else bad "the skill's GitLab line"; fi
if grep -qF 'prints a `Pin conflict:` line' <<<"$skill_text" && grep -qF 'Tell the user this before asking for the yes' <<<"$skill_text" \
   && grep -qF "A plinth \`uses:\` line the plan's \`Pin conflict:\` line named is that conflict" <<<"$skill_text"
then ok "the skill tells the person of the expected pin conflict before the yes, and which side to recommend (#1015)"
else bad "the skill's pin conflict lines"; fi
if grep -qF 'carries a trailing comment' <<<"$skill_text" && grep -qF 'give the person that line as printed' <<<"$skill_text" \
   && grep -qF 'through `!` `with-admin-token.sh` has no terminal' <<<"$skill_text"
then ok "the skill says a version comment conflicts, and relays the bash <file> line for a separate terminal (#1045)"
else bad "the skill's #1045 lines"; fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
