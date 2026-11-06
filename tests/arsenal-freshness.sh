#!/usr/bin/env bash
# The arsenal says what ships. A row written before a release workflow existed
# told a real project that a release on a tag was "planned, not built yet"
# (#833), and nothing tied the claim to the template. This reads the template
# at the tag scripts/new-project.sh pins and the whole of skills/arsenal/SKILL.md
# and fails when:
#   - a table cell says "planned", "not built yet" or "nothing yet" about
#     something the template renders or the plugin installs;
#   - a cell names an issue as the plan and that issue is closed or unreadable;
#   - a cell marks a tool "(listed", or the "Listed, not installed" table names
#     a plugin, that the plugin installs;
#   - the release row, the reminder row or run-a-project.md does not say what
#     the template has, archetype by archetype;
#   - plinth's own user-only skill is not on the one list of skills the person
#     types, or a page that used to repeat that list does not point at it.
# It reads the template's source tree, not a render. Other words for a plan
# ("waits for #N") are not caught, and the frontmatter of the dependencies'
# skills is not read: only plinth's own are held against the list. Reads over
# the network; unreadable is a FAIL. The must-not-pass cases run first.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template="${TEMPLATE_REPO:-coolbress/plinth-template}"
ref="${TEMPLATE_REF:-$(sed -n 's/^template_ref="\(.*\)"$/\1/p' "$root/scripts/new-project.sh")}"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

typed_section="Skills only the person can start"
typed_anchor="skills-only-the-person-can-start"
release_row="| A merged change to put out"
reminder_row="| Between pieces of work"
plan_row="| A job bigger than one session"

# flat <file>: one line, line breaks and runs of spaces as one space.
flat() { tr '\n' ' ' <"$1" | tr -s ' '; }

# Each table cell in the catalog, one per line.
cells() { grep '^| ' "$1" | sed -e 's/^| //' -e 's/ |$//' | awk '{ gsub(/ \| /, "\n"); print }'; }

# real_state <owner/repo> <n>: open or closed; nothing when it cannot be read.
real_state() { gh api "repos/$1/issues/$2" --jq .state 2>/dev/null; }
state_of=real_state

# installed <plinth dir>: what the plugin installs, one name per line: its own
# skills, its dependencies, and the skills their marketplace entries carry.
installed() {
  local p="$1"
  find "$p/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | while read -r f; do basename "$(dirname "$f")"; done
  jq -r '.dependencies[]? | if type == "string" then . else .name end' "$p/.claude-plugin/plugin.json" |
    while read -r dep; do
      echo "$dep"
      jq -r --arg d "$dep" '.plugins[] | select(.name == $d) | .skills[]?' "$p/.claude-plugin/marketplace.json" | sed 's#.*/##'
    done
}

# release_sources <template dir>: the template's conditional release workflows.
release_sources() { find "$1/template/.github/workflows" -type f -name '*release.yml*' 2>/dev/null; }

# stale_claims <arsenal> <template dir> <plinth dir>: one line per stale claim.
stale_claims() {
  local arsenal="$1" tdir="$2" pdir="$3" cell issue repo n state rc=0 name inst
  inst="$(installed "$pdir")"
  while IFS= read -r cell; do
    if grep -qiE 'planned|not built yet|nothing yet' <<<"$cell"; then
      if grep -qiE 'release|publish' <<<"$cell" && [ -n "$(release_sources "$tdir")" ]; then
        echo "says not there, but the template renders a release workflow: $cell"; rc=1
      fi
      if grep -qi 'reminder' <<<"$cell" && [ -f "$tdir/template/.github/workflows/template-reminder.yml" ]; then
        echo "says not there, but the template renders the reminder: $cell"; rc=1
      fi
      for name in $(grep -oE '`/?[a-zA-Z0-9:_.-]+`' <<<"$cell" | tr -d '`' | sed -e 's#^/##' -e 's#^plinth:##'); do
        if grep -qxF -- "$name" <<<"$inst"; then
          echo "says not there, but the plugin installs \`$name\`: $cell"; rc=1
        fi
      done
    fi
    if grep -qiE '(^|[^a-z])plan(ned)?([^a-z]|$)' <<<"$cell"; then
      for issue in $(grep -oE '([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[0-9]+' <<<"$cell"); do
        repo="${issue%#*}"; n="${issue##*#}"
        state="$("$state_of" "${repo:-coolbress/plinth}" "$n")"
        case "$state" in
          open) ;;
          closed) echo "names $issue as the plan, and it is closed: $cell"; rc=1 ;;
          *) echo "names $issue as the plan, and its state could not be read: $cell"; rc=1 ;;
        esac
      done
    fi
    for name in $(grep -oE '`/?[a-zA-Z0-9:_.-]+` \(listed' <<<"$cell" | cut -d'`' -f2 | sed -e 's#^/##' -e 's#^plinth:##'); do
      if grep -qxF -- "$name" <<<"$inst"; then
        echo "marks \`$name\` listed, and the plugin installs it: $cell"; rc=1
      fi
    done
  done < <(cells "$arsenal")
  while IFS= read -r name; do
    if grep -qxF -- "$name" <<<"$inst"; then
      echo "the \"Listed, not installed\" table names \`$name\`, and the plugin installs it"; rc=1
    fi
  done < <(awk '/^## Listed, not installed/{on=1; next} on && /^## /{exit} on && /^\| `/' "$arsenal" | cut -d'`' -f2)
  return $rc
}

# missing_facts <arsenal> <run-a-project> <template dir>: what the template has
# and the release row, the reminder row or step 9 does not say.
missing_facts() {
  local arsenal="$1" howto="$2" tdir="$3" row src arch archs all_archs="" dest rc=0 step9 reminder title
  row="$(grep -F -- "$release_row" "$arsenal" | head -1)"
  [ -n "$row" ] || { echo "the arsenal has no row starting '$release_row'"; rc=1; }
  if [ -z "$(release_sources "$tdir")" ]; then
    echo "the template has no release workflow; the release row needs rewriting"; rc=1
  fi
  while IFS= read -r src; do
    [ -n "$src" ] || continue
    if grep -qiE 'pypi' "$src"; then dest="PyPI"
    elif grep -q 'ghcr\.io' "$src"; then dest="GHCR"
    else dest="GitHub release"; fi
    archs="$(basename "$src" | sed 's/{% endif.*//' | grep -oE "'[a-z-]+'" | tr -d "'")"
    [ -n "$archs" ] || { echo "no archetype in the workflow's file name, so the row cannot be checked: $(basename "$src")"; rc=1; }
    all_archs="$all_archs $archs"
    for arch in $archs; do
      grep -qE "\`$arch\`[^,;]*$dest" <<<"$row" || { echo "the release row does not say \`$arch\` goes to $dest: $row"; rc=1; }
    done
  done < <(release_sources "$tdir")
  # The other way round: the row's next-action cell names no archetype beyond
  # those with a workflow (`web` deploys, `main` is the branch).
  for arch in $(awk -F ' \\| ' '{ print $2 }' <<<"$row" | grep -oE '`[a-z-]+`' | tr -d '`'); do
    case "$arch" in web|main) continue ;; esac
    case " $(echo $all_archs) " in *" $arch "*) ;; *) echo "the release row names \`$arch\`, and the template has no release workflow for it"; rc=1 ;; esac
  done
  if [ -f "$tdir/template/docs/how-to/publish-a-release.md.jinja" ]; then
    grep -qF 'docs/how-to/publish-a-release.md' <<<"$row" || { echo "the release row does not name docs/how-to/publish-a-release.md"; rc=1; }
  else
    echo "the template has no docs/how-to/publish-a-release.md.jinja; the release row names it"; rc=1
  fi
  grep -qE '`web`[^,;]*Render' <<<"$row" || { echo "the release row does not say \`web\` goes out on Render"; rc=1; }
  flat "$howto" | grep -qF 'A merged change to put out' || { echo "run-a-project.md does not point at the release row"; rc=1; }

  reminder="$tdir/template/.github/workflows/template-reminder.yml"
  if [ -f "$reminder" ]; then
    title="$(sed -n 's/.*title="\(Template update available\):.*/\1/p' "$reminder" | head -1)"
    if [ -z "$title" ] || ! grep -qF '/plinth:template-update' "$reminder"; then
      echo "the reminder workflow no longer titles its issue 'Template update available:' or names /plinth:template-update; update this test and the two places"; rc=1
    else
      step9="$(awk '/^### 9\./{on=1; next} on && /^#/{exit} on' "$howto" | tr '\n' ' ' | tr -s ' ')"
      row="$(grep -F -- "$reminder_row" "$arsenal" | head -1)"
      grep -qF "$title" <<<"$row" && grep -qF '/plinth:template-update' <<<"$row" || { echo "the 'Between pieces of work' row does not name the reminder issue and what to type"; rc=1; }
      grep -qF "$title" <<<"$step9" && grep -qF '/plinth:template-update' <<<"$step9" || { echo "run-a-project.md step 9 does not name the reminder issue and what to type"; rc=1; }
    fi
  else
    echo "the template has no template-reminder.yml; the 'Between pieces of work' row and step 9 name it"; rc=1
  fi
  return $rc
}

# typed_list <plinth dir>: the one list holds plinth's own user-only skills, the
# other pages point at it, and step 3's row asks for nothing the person must type.
typed_list() {
  local p="$1" f list rc=0 name
  list="$(awk -v h="## $typed_section" 'index($0, h) == 1 {on=1; next} on && /^## /{exit} on' "$p/skills/arsenal/SKILL.md")"
  [ -n "$list" ] || { echo "the arsenal has no section '$typed_section'"; rc=1; }
  for f in "$p"/skills/*/SKILL.md; do
    grep -q '^disable-model-invocation: true' "$f" || continue
    name="$(basename "$(dirname "$f")")"
    grep -qF "/plinth:$name" <<<"$list" || { echo "/plinth:$name is user-only and not on the list"; rc=1; }
  done
  flat "$p/skills/guide/SKILL.md" | grep -qF "$typed_section" || { echo "skills/guide/SKILL.md does not point at the list"; rc=1; }
  grep -qF "$typed_anchor" "$p/docs/how-to/run-a-project.md" || { echo "run-a-project.md does not point at the list"; rc=1; }
  grep -qF "$typed_anchor" "$p/README.md" || { echo "README.md does not point at the list"; rc=1; }
  grep -F -- '| `mattpocock-skills` |' "$p/skills/arsenal/SKILL.md" | grep -qF "$typed_section" || { echo "the mattpocock-skills row does not point at the list"; rc=1; }
  if grep -F -- "$plan_row" "$p/skills/arsenal/SKILL.md" | grep -qi 'ask for it'; then
    echo "step 3's row says 'ask for it' for a skill the person must type"; rc=1
  fi
  return $rc
}

# ---- Must not pass: fixtures. Issue states come from a stub, not the network.
stub_state() { case "$2" in 703|706) echo closed ;; 900) echo open ;; *) ;; esac; }
state_of=stub_state

t="$work/t"; p="$work/p"
mkdir -p "$t/template/.github/workflows" "$t/template/docs/how-to" "$p/skills/arsenal" "$p/skills/guide" "$p/.claude-plugin" "$p/docs/how-to"
printf 'uses: pypa/gh-action-pypi-publish\n' >"$t/template/.github/workflows/{% if archetype in ['cli', 'library'] %}release.yml{% endif %}"
printf 'image: ghcr.io/x\n' >"$t/template/.github/workflows/{% if archetype == 'backend' %}release.yml{% endif %}"
printf 'gh release create\n' >"$t/template/.github/workflows/{% if archetype == 'data-ml' %}release.yml{% endif %}"
printf 'body\n' >"$t/template/docs/how-to/publish-a-release.md.jinja"
printf 'title="Template update available: $a to $b"\nrun /plinth:template-update\n' >"$t/template/.github/workflows/template-reminder.yml"
printf '{"dependencies":["dep"]}\n' >"$p/.claude-plugin/plugin.json"
printf '{"plugins":[{"name":"dep","skills":["./engineering/implement"]},{"name":"extra","skills":["./engineering/ask-matt"]}]}\n' >"$p/.claude-plugin/marketplace.json"

good_arsenal() {
  cat <<'ROW'
## Where you are, and what to do next

| Where you are | Next action | Tool |
| --- | --- | --- |
| A job bigger than one session (step 3) | A plan in one issue | `/implement`, typed |
| Between pieces of work (step 9) | The template update | The monthly issue "Template update available: …": type `/plinth:template-update` |
| A merged change to put out (release and deploy) | A `web` app on Render goes out by itself; `cli` and `library` publish to PyPI, `backend` its image to GHCR, `data-ml` its model as a GitHub release | The project's `docs/how-to/publish-a-release.md` |
| Unsure | Say | `/ask-matt` (listed) |

## Skills only the person can start

- `/plinth:guide`

## Installed by default

| Plugin | What |
| --- | --- |
| `mattpocock-skills` | See "Skills only the person can start" |

## Listed, not installed

| Plugin | What |
| --- | --- |
| `extra` | More |
ROW
}
good_arsenal >"$p/skills/arsenal/SKILL.md"
printf -- '---\nname: guide\ndisable-model-invocation: true\n---\nThe arsenal, "Skills only the person can start".\n' >"$p/skills/guide/SKILL.md"
printf '[list](x#skills-only-the-person-can-start)\n' >"$p/README.md"
cat >"$p/docs/how-to/run-a-project.md" <<'H'
Release: the row "A merged change to put out". [list](x#skills-only-the-person-can-start)

### 9. Keep it healthy

An issue "Template update available: …": type `/plinth:template-update`.

### Next
H
a="$p/skills/arsenal/SKILL.md"; h="$p/docs/how-to/run-a-project.md"

if out="$(stale_claims "$a" "$t" "$p")"; then ok "a catalog that matches the template has no stale claim"
else bad "a catalog that matches the template has a stale claim: $out"; fi
if out="$(missing_facts "$a" "$h" "$t")"; then ok "a catalog that matches the template misses no fact"
else bad "a catalog that matches the template misses a fact: $out"; fi
if out="$(typed_list "$p")"; then ok "one typed list, with the pointers, passes"
else bad "one typed list, with the pointers, fails: $out"; fi

# variant <name> <sed expression>: the good catalog with one line changed.
variant() { sed "$2" "$a" >"$work/$1.md"; printf '%s' "$work/$1.md"; }
# The row as it stood when it told a real project a release was not built (#833).
old_row='| A merged change to put out (release and deploy, after step 6) | A `web` app on Render goes out by itself once `main` is green; the other archetypes publish nothing yet | Render, from `${CLAUDE_PLUGIN_ROOT}/docs/how-to/choose-where-a-web-app-runs.md`; a release on a tag is planned for `library` and `cli` (#703) and `backend` (#706), not built yet |'
awk -v r="$old_row" 'index($0, "| A merged change to put out") == 1 { print r; next } { print }' "$a" >"$work/old.md"
if out="$(stale_claims "$work/old.md" "$t" "$p")"; then bad "the old release row passes"
else
  ok "the old release row is a stale claim"
  grep -q 'names #703 as the plan, and it is closed' <<<"$out" && ok "the old release row names a closed issue as the plan" || bad "the old row's closed #703 went unnoticed: $out"
fi
if out="$(missing_facts "$work/old.md" "$h" "$t")"; then bad "the old release row says every fact"
else ok "the old release row misses what each archetype does"; fi

not_passing() { # <what> <stale_claims or missing_facts arguments...>
  local what="$1"; shift
  if out="$("$@")"; then bad "$what passes"; else ok "$what fails"; fi
}
not_passing "a cell planning an open-issue feature the template renders" stale_claims "$(variant a 's/| Say |/| A release is planned (#900) |/')" "$t" "$p"
not_passing "a cell naming a closed issue as the plan" stale_claims "$(variant b 's/| Say |/| Planned in #703 |/')" "$t" "$p"
not_passing "a cell naming an issue whose state cannot be read" stale_claims "$(variant c 's/| Say |/| Planned in #901 |/')" "$t" "$p"
not_passing "a cell naming another repository's closed issue as the plan" stale_claims "$(variant d 's|Say |Planned in owner/repo#703 |')" "$t" "$p"
not_passing "the reminder called not built yet" stale_claims "$(variant e 's/| Say |/| The reminder is not built yet |/')" "$t" "$p"
not_passing "an installed skill called planned" stale_claims "$(variant f 's/| Say |/| `\/implement` is planned |/')" "$t" "$p"
not_passing "an installed skill marked listed" stale_claims "$(variant g 's|`/ask-matt` (listed)|`/implement` (listed)|')" "$t" "$p"
printf '| `dep` | More |\n' >>"$(variant h 's/^nothing$//')"
not_passing "an installed plugin in the Listed table" stale_claims "$work/h.md" "$t" "$p"
not_passing "a release row without one archetype" missing_facts "$(variant i 's/, `data-ml` its model as a GitHub release//')" "$h" "$t"
not_passing "a release row with an archetype's wrong destination" missing_facts "$(variant j 's/`backend` its image to GHCR/`backend` its image to PyPI/')" "$h" "$t"
not_passing "a reminder row without the issue's title" missing_facts "$(variant k 's/The monthly issue "Template update available: …"/The monthly issue/')" "$h" "$t"
sed 's/An issue "Template update available: …"/An issue/' "$h" >"$work/h9.md"
not_passing "a step 9 without the issue's title" missing_facts "$a" "$work/h9.md" "$t"
grep -v 'A merged change' "$h" >"$work/hr.md"
not_passing "a run-a-project.md without the release pointer" missing_facts "$a" "$work/hr.md" "$t"
mkdir -p "$work/empty/template"
not_passing "a template with no release workflow" missing_facts "$a" "$h" "$work/empty"
# Each file the catalog names, gone from the template; and one workflow whose
# name carries no archetype.
cp -R "$t" "$work/t2"; rm "$work/t2/template/.github/workflows/template-reminder.yml"
not_passing "a template that dropped the reminder" missing_facts "$a" "$h" "$work/t2"
cp -R "$t" "$work/t3"; rm "$work/t3/template/docs/how-to/publish-a-release.md.jinja"
not_passing "a template that dropped the release how-to" missing_facts "$a" "$h" "$work/t3"
cp -R "$t" "$work/t4"; rm "$work/t4/template/.github/workflows/"*release.yml*
printf 'uses: pypa/gh-action-pypi-publish\n' >"$work/t4/template/.github/workflows/release.yml.jinja"
not_passing "a release workflow whose name carries no archetype" missing_facts "$a" "$h" "$work/t4"
cp -R "$t" "$work/t5"; rm "$work/t5/template/.github/workflows/"*backend*release.yml*
not_passing "a template that dropped one archetype's release workflow" missing_facts "$a" "$h" "$work/t5"

cp -R "$p" "$work/p2"; sed -i.bak 's#/plinth:guide#/plinth:other#' "$work/p2/skills/arsenal/SKILL.md"
not_passing "a user-only skill missing from the list" typed_list "$work/p2"
cp -R "$p" "$work/p3"; printf 'no pointer\n' >"$work/p3/README.md"
not_passing "a README without the pointer" typed_list "$work/p3"
cp -R "$p" "$work/p4"; sed -i.bak 's/A plan in one issue | `\/implement`, typed/A plan | Ask for it; `\/to-spec`/' "$work/p4/skills/arsenal/SKILL.md"
not_passing "step 3's row saying ask for it" typed_list "$work/p4"

# ---- The real files: the template at the pinned tag against plinth's own.
state_of=real_state
# The live lookup, run every time: no cell may need it, and it must still work.
if [ "$(real_state coolbress/plinth 703)" = closed ]; then ok "issue state reads over the network (#703 closed)"
else bad "could not read coolbress/plinth#703's state; a named plan cannot be verified"; fi

mkdir -p "$work/real"
if curl -fsSL --retry 3 --max-time 120 "https://codeload.github.com/$template/tar.gz/$ref" | tar -xz --strip-components=1 -C "$work/real" 2>/dev/null \
   && [ -f "$work/real/copier.yml" ]; then
  if out="$(stale_claims "$root/skills/arsenal/SKILL.md" "$work/real" "$root")"
  then ok "no arsenal cell contradicts $template@$ref or what the plugin installs"
  else bad "stale claims against $template@$ref:"; sed 's/^/        /' <<<"$out"; fi
  if out="$(missing_facts "$root/skills/arsenal/SKILL.md" "$root/docs/how-to/run-a-project.md" "$work/real")"
  then ok "the release and reminder facts match $template@$ref"
  else bad "facts missing against $template@$ref:"; sed 's/^/        /' <<<"$out"; fi
else
  bad "could not read $template@$ref; cannot verify"
fi
if out="$(typed_list "$root")"; then ok "the person-typed skills are one list, and the other pages point at it"
else bad "the person-typed list:"; sed 's/^/        /' <<<"$out"; fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
