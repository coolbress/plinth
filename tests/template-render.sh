#!/usr/bin/env bash
# canary-template/ is plinth-template's `cli` render at the commit
# scripts/new-project.sh pins, committed, and ci.yml's `canary-template` job
# runs it through this commit's python-ci.yml (#953). A change to python-ci.yml
# that the template's caller cannot run then fails in plinth's own pull
# request, not after a release, the template's Dependabot raise and a template
# pull request. This test holds the two halves to the pin:
#   1. canary-template/ is exactly what the door's copier renders from the
#      pinned commit, with the answers below; a pin raise that does not
#      re-render fails here. `tests/template-render.sh --write` re-renders.
#   2. The `canary-template` job grants exactly the permissions the rendered
#      caller's `ci` job grants, passes every input it passes with the same
#      value, and adds only working-directory, max-diff-lines: 0 (the render
#      is generated, not reviewed line by line) and floor-check-required-checks
#      (plinth's own ruleset, as `canary` passes it). Its name says the tag and
#      the commit it was rendered from.
#   3. canary-web/Dockerfile's FROM lines are the pinned template's
#      template/Dockerfile.jinja's, in order: copied by hand at a pin raise
#      (#975).
#   4. scripts/heavy.sh is the pinned template's template/scripts/heavy.sh,
#      byte for byte (#989): one queue, one rule, for plinth and the projects.
#      A pin whose template has no scripts/heavy.sh yet (before v1.48.0) is
#      compared at heavy_from instead, the commit plinth copied it from.
# Committed, not rendered in the job: a job that calls a reusable workflow
# has no steps of its own, and python-ci.yml checks out the repository, so
# the project it runs on has to be in the commit. The template is read from
# one checkout (tests/lib/template-checkout.sh); copier from PyPI at the
# door's pin. The must-not-pass cases run first.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
door="$root/scripts/new-project.sh"
dir="canary-template"
# shellcheck source=tests/lib/template-checkout.sh
. "$root/tests/lib/template-checkout.sh"
copier_version="$(sed -n 's/^copier_version="\(.*\)"$/\1/p' "$door")"
copier_newer="$(sed -n 's/^copier_newer="\(.*\)"$/\1/p' "$door")"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

# render <template checkout> <dest>: the door's copier call for a public `cli`
# project of an owner with no shared .github, then what the door does after:
# no .git. `_src_path` is set to the door's own form, gh:<repo>: rendered from
# a checkout it would name the checkout's path. Arguments after the two are
# more of the door's answers, for the web render below.
render() {
  env -u GH_TOKEN -u GITHUB_TOKEN uvx --quiet --from "copier==$copier_version" --exclude-newer "$copier_newer" \
    copier copy --defaults --quiet \
    --data project_name=probe --data owner=coolbress --data license=MIT --data archetype=cli \
    --data owner_has_pr_template=false --data owner_has_issue_forms=false --data visibility=public \
    "${@:3}" --vcs-ref HEAD "$1" "$2" </dev/null >/dev/null 2>"$work/copier.err" || { cat "$work/copier.err" >&2; return 1; }
  rm -rf "$2/.git"
  sed -i.bak "s|^_src_path: .*|_src_path: gh:$template_repo|" "$2/.copier-answers.yml" && rm -f "$2/.copier-answers.yml.bak"
}

# mirror <plinth ci.yml> <rendered ci.yml> <tag> <sha>: one line per way the
# canary-template job is not the rendered caller; exit 1 if any.
mirror() {
  python3 - "$@" <<'PY'
import re, sys

def job(path, name):
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return None
    m = re.search(rf"^  {re.escape(name)}:\n((?:(?:    .*|\s*)\n)*)", text, re.M)
    if not m:
        return None
    # Every key of the job: a scalar as its value, a block (permissions,
    # with, secrets, anything else) as a mapping of its keys.
    out, block = {"permissions": {}, "with": {}}, None
    for line in m.group(1).splitlines():
        line = re.sub(r"\s+#.*$", "", line.rstrip())
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        k = re.fullmatch(r"    ([A-Za-z0-9_-]+):\s*(.*)", line)
        if k:
            block = k.group(1) if k.group(2) == "" else None
            if block is None:
                out[k.group(1)] = k.group(2).strip("\"'")
            else:
                out.setdefault(block, {})
            continue
        kv = re.fullmatch(r"      ([A-Za-z0-9_-]+):\s*(.*)", line)
        if kv and block is not None:
            out[block][kv.group(1)] = kv.group(2).strip("\"'")
        elif block is not None:
            out[block].setdefault("(unread)", []).append(line.strip())
    return out

plinth_yml, rendered_yml, tag, sha = sys.argv[1:5]
mine, theirs = job(plinth_yml, "canary-template"), job(rendered_yml, "ci")
problems = []
if mine is None:
    problems.append(f"{plinth_yml} has no canary-template job, or cannot be read")
if theirs is None:
    problems.append(f"{rendered_yml} has no ci job, or cannot be read")
if problems:
    print("\n".join(problems)); sys.exit(1)
if mine.get("uses") != "./.github/workflows/python-ci.yml":
    problems.append(f"canary-template uses {mine.get('uses')!r}, not ./.github/workflows/python-ci.yml at this commit")
want_name = f"canary-template (plinth-template {tag} at {sha[:7]})"
if mine.get("name") != want_name:
    problems.append(f"canary-template is named {mine.get('name')!r}, not {want_name!r}: the name says what was rendered")
if mine["permissions"] != theirs["permissions"]:
    problems.append(f"canary-template grants {mine['permissions']}; the rendered caller grants {theirs['permissions']}")
for k, v in theirs["with"].items():
    if mine["with"].get(k) != v:
        problems.append(f"the rendered caller passes {k}: {v!r}; canary-template passes {mine['with'].get(k)!r}")
extra = {k: v for k, v in mine["with"].items() if k not in theirs["with"]}
if extra.get("working-directory") != "canary-template":
    problems.append(f"canary-template passes working-directory {extra.get('working-directory')!r}, not canary-template")
if extra.get("max-diff-lines", "0") != "0":
    problems.append(f"canary-template passes max-diff-lines {extra['max-diff-lines']!r}; only 0 is plinth's own")
for k in sorted(set(extra) - {"working-directory", "max-diff-lines", "floor-check-required-checks"}):
    problems.append(f"canary-template passes {k}, which the rendered caller does not")
for k in sorted(set(mine) - {"uses", "name", "permissions", "with"}):
    problems.append(f"canary-template has {k}:, which the rendered caller does not")
for k in sorted(set(theirs) - {"uses", "permissions", "with"}):
    if mine.get(k) != theirs[k]:
        problems.append(f"the rendered caller has {k}: {theirs[k]!r}; canary-template has {mine.get(k)!r}")
print("\n".join(problems))
sys.exit(1 if problems else 0)
PY
}

# ---- Must not pass: the caller.
tag="v9.9.9"; sha="abcdef0123456789abcdef0123456789abcdef01"
cat >"$work/rendered.yml" <<'EOF'
jobs:
  ci:
    uses: coolbress/plinth/.github/workflows/python-ci.yml@0000000000000000000000000000000000000000
    with:
      # a comment
      extra-python-versions: "3.13"
    permissions:
      contents: read
      actions: write
EOF
good() {
  cat <<EOF
jobs:
  canary:
    uses: ./.github/workflows/python-ci.yml
  canary-template:
    name: canary-template (plinth-template $tag at ${sha:0:7})
    uses: ./.github/workflows/python-ci.yml
    permissions:
      contents: read
      actions: write   # why
    with:
      working-directory: canary-template
      extra-python-versions: "3.13"
      max-diff-lines: 0
      floor-check-required-checks: "ci / install"
EOF
}
good >"$work/good.yml"
if out="$(mirror "$work/good.yml" "$work/rendered.yml" "$tag" "$sha")"; then ok "a canary-template job that mirrors the rendered caller passes"
else bad "a mirroring canary-template job fails: $out"; fi
seed() { # <name> <perl expression> <what it shows>
  good | perl -pe "$2" >"$work/$1.yml"
  if out="$(mirror "$work/$1.yml" "$work/rendered.yml" "$tag" "$sha")"; then bad "$3 passes"
  else ok "$3 fails ($(head -1 <<<"$out"))"; fi
}
seed wider  's/^(      actions: write.*)$/$1\n      checks: write/' "a job granting more than the rendered caller"
seed narrow '$_ = "" if /^      actions: write/' "a job granting less than the rendered caller"
seed input  '$_ = "" if /extra-python-versions/' "a job not passing an input the rendered caller passes"
seed value  's/"3\.13"/"3.14"/' "a job passing another value"
seed extra  's/^      max-diff-lines: 0$/      web: true/' "a job passing an input the rendered caller does not"
seed limit  's/^      max-diff-lines: 0$/      max-diff-lines: 400/' "a job passing a diff limit other than 0"
seed dir    's/^      working-directory: canary-template$/      working-directory: canary/' "a job running another directory"
seed uses   's{^    uses: \./\.github/workflows/python-ci\.yml$}{    uses: coolbress/plinth/.github/workflows/python-ci.yml\@main} if $. > 3' "a job calling another workflow than this commit's"
seed name   "s/ at ${sha:0:7}//" "a job whose name does not say the commit"
seed if     's/^    with:$/    if: false\n    with:/' "a job with an if:"
printf '    secrets:\n      API_TOKEN: ${{ secrets.API_TOKEN }}\n' >>"$work/rendered.yml"
if out="$(mirror "$work/good.yml" "$work/rendered.yml" "$tag" "$sha")"; then bad "a rendered caller passing a secrets: block the job lacks passes"
else ok "a rendered caller passing a secrets: block the job lacks fails ($(head -1 <<<"$out"))"; fi
perl -0pi -e 's/    secrets:\n      API_TOKEN: .*\n//' "$work/rendered.yml"
printf '    secrets: inherit\n' >>"$work/rendered.yml"
if out="$(mirror "$work/good.yml" "$work/rendered.yml" "$tag" "$sha")"; then bad "a rendered caller with a key the job lacks (secrets:) passes"
else ok "a rendered caller with a key the job lacks fails ($(head -1 <<<"$out"))"; fi
perl -ni -e 'print unless /^    secrets: inherit$/' "$work/rendered.yml"
grep -v '^  canary-template:' "$work/good.yml" | sed '/^    name: canary-template/,$d' >"$work/none.yml"
if out="$(mirror "$work/none.yml" "$work/rendered.yml" "$tag" "$sha")"; then bad "no canary-template job passes"
else ok "no canary-template job fails ($out)"; fi

# same_froms <template Dockerfile.jinja> <canary-web Dockerfile>: the FROM
# lines, in order, are the template's; prints both sets and exits 1 if not.
# canary-web/Dockerfile is the template's web Dockerfile with uvicorn as the
# command, and `ci / web-audit` builds and starts it without scanning it: base
# images left behind the template's carry what its scan already fixed (#975).
same_froms() {
  local want got
  want="$(grep -E '^FROM ' "$1" 2>/dev/null)"; got="$(grep -E '^FROM ' "$2" 2>/dev/null)"
  [ -n "$want" ] && [ "$want" = "$got" ] && return 0
  printf 'the template'"'"'s:\n%s\n%s'"'"'s:\n%s\n' "${want:-(none)}" "${2#"$root"/}" "${got:-(none)}" | sed 's/^/        /'
  return 1
}

# ---- Must not pass: canary-web's base images.
printf '# x\nFROM a@sha256:1 AS build\nRUN x\nFROM b@sha256:2\n' >"$work/tpl.Dockerfile"
cp "$work/tpl.Dockerfile" "$work/web.Dockerfile"
if same_froms "$work/tpl.Dockerfile" "$work/web.Dockerfile" >/dev/null; then ok "a Dockerfile with the template's FROM lines passes"
else bad "a Dockerfile with the template's FROM lines fails"; fi
for c in 's/sha256:2/sha256:3/' 's/ AS build//' '/^FROM b/d' 's/^RUN x$/FROM c@sha256:4/'; do
  sed "$c" "$work/tpl.Dockerfile" >"$work/web.Dockerfile"
  if same_froms "$work/tpl.Dockerfile" "$work/web.Dockerfile" >/dev/null; then bad "a Dockerfile edited by '$c' passes"
  else ok "a Dockerfile edited by '$c' fails"; fi
done
: >"$work/empty"
if same_froms "$work/empty" "$work/empty" >/dev/null; then bad "a template with no FROM line passes"
else ok "a template with no FROM line fails: nothing read is not a match"; fi

# same_file <template's> <plinth's>: byte for byte; prints the diff and exits
# 1 if not, or if the template's is missing (nothing read is not a match).
same_file() {
  [ -f "$1" ] || { echo "        the template has no ${1##*/}"; return 1; }
  diff -u "$1" "$2" 2>&1 | head -40 | sed 's/^/        /'
  cmp -s "$1" "$2"
}

# ---- Must not pass: plinth's heavy.sh.
printf '#!/usr/bin/env bash\nslots=${PLINTH_HEAVY_SLOTS:-2}\n' >"$work/tpl.heavy.sh"
cp "$work/tpl.heavy.sh" "$work/heavy.sh"
if same_file "$work/tpl.heavy.sh" "$work/heavy.sh" >/dev/null; then ok "a heavy.sh that is the template's passes"
else bad "a heavy.sh that is the template's fails"; fi
sed 's/:-2/:-4/' "$work/tpl.heavy.sh" >"$work/heavy.sh"
if same_file "$work/tpl.heavy.sh" "$work/heavy.sh" >/dev/null; then bad "a heavy.sh with another default passes"
else ok "a heavy.sh with another default fails"; fi
if same_file "$work/no-such-heavy.sh" "$work/heavy.sh" >/dev/null; then bad "a template with no heavy.sh passes"
else ok "a template with no heavy.sh fails"; fi

# ---- The real ones: the template at the pinned commit.
if ! template_checkout "$work"; then
  bad "no checkout of the template: $template_error"
  echo "-- $pass passed, $fail failed"; exit 1
fi
if [ "${1:-}" = --write ]; then
  rm -rf "${root:?}/$dir"
  render "$template_dir" "$root/$dir" || { echo "could not render $template_at" >&2; exit 1; }
  echo "rendered $template_at into $dir/"
  exit 0
fi

if ! render "$template_dir" "$work/fresh"; then
  bad "could not render $template_at"
else
  # Must not pass: a render that differs in one file, by one file more or less.
  cp -R "$work/fresh" "$work/changed"; echo "# drift" >>"$work/changed/pyproject.toml"
  cp -R "$work/fresh" "$work/more"; echo x >"$work/more/extra.txt"
  cp -R "$work/fresh" "$work/less"; rm "$work/less/README.md"
  for c in changed more less; do
    if diff -r "$work/fresh" "$work/$c" >/dev/null 2>&1; then bad "a render with a file $c passes"
    else ok "a render with a file $c fails"; fi
  done
  if [ "$(sed -n 's/^_commit: //p' "$work/fresh/.copier-answers.yml")" = "$template_ref" ]
  then ok "the render records _commit: $template_ref, as the door's does"
  else bad "the render records _commit: $(sed -n 's/^_commit: //p' "$work/fresh/.copier-answers.yml"), not $template_ref"; fi
  if out="$(diff -r "$work/fresh" "$root/$dir" 2>&1)"
  then ok "$dir/ is the cli render of $template_at"
  else bad "$dir/ is not the cli render of $template_at; re-render it with tests/template-render.sh --write:"
       sed 's/^/        /' <<<"$out" | head -40; fi
fi

# Against the fresh render's caller, so a pin raise that changes the grant
# names it, not only the render's diff.
caller="$work/fresh/.github/workflows/ci.yml"; [ -f "$caller" ] || caller="$root/$dir/.github/workflows/ci.yml"
if out="$(mirror "$root/.github/workflows/ci.yml" "$caller" "$template_ref" "$template_sha")"
then ok "ci.yml's canary-template job grants and passes what the rendered caller does, and is named for $template_ref at ${template_sha:0:7}"
else bad "ci.yml's canary-template job is not the rendered caller:"; sed 's/^/        /' <<<"$out"; fi

if out="$(same_froms "$template_dir/template/Dockerfile.jinja" "$root/canary-web/Dockerfile")"
then ok "canary-web/Dockerfile's FROM lines are template/Dockerfile.jinja's at $template_ref"
else bad "canary-web/Dockerfile's FROM lines are not template/Dockerfile.jinja's at $template_at; copy the template's:"; echo "$out"; fi

# The answers the door adds at this pin (#1068, #1092): a web project with its
# own user model, a description and a records language, rendered as the door
# passes them (copier takes the last --data archetype=), and read back where
# the template puts each.
web="$work/web"
if ! render "$template_dir" "$web" --data archetype=web --data custom_user_model=true \
     --data "description=매일 아침 날씨를 모으는 도구" --data records_language=Korean; then
  bad "could not render $template_at as the door's web project with its answers"
else
  answers="$web/.copier-answers.yml"
  for line in 'archetype: web' 'custom_user_model: true' 'records_language: Korean' 'description: 매일 아침 날씨를 모으는 도구'; do
    if grep -qxF "$line" "$answers"; then ok "the web render records $line"
    else bad "the web render's .copier-answers.yml has no line $line"; fi
  done
  models="$(find "$web" -path '*/accounts/models.py' | head -n 1)"
  if [ -n "$models" ] && grep -q '^class User(AbstractUser)' "$models"
  then ok "accounts/models.py holds User(AbstractUser)"; else bad "no accounts/models.py with User(AbstractUser) (found: ${models:-none})"; fi
  if grep -rqF 'AUTH_USER_MODEL = "accounts.User"' "$web" --include='*.py'
  then ok "the settings set AUTH_USER_MODEL = \"accounts.User\""; else bad "no settings file sets AUTH_USER_MODEL = \"accounts.User\""; fi
  if grep -qxF '> 매일 아침 날씨를 모으는 도구' "$web/README.md"
  then ok "README.md's line under the title is the description"; else bad "README.md does not carry the description"; fi
  if grep -qF 'Korean' "$web/AGENTS.md"
  then ok "AGENTS.md names the records language"; else bad "AGENTS.md does not name Korean"; fi
fi

# Until the pin carries it, the commit plinth copied it from (plinth-template#287).
heavy_from="c19a631782a808c3451cf3b0fd396ab9110f1f71"
heavy_dir="$template_dir" heavy_at="$template_at"
if [ ! -e "$template_dir/template/scripts/heavy.sh" ]; then
  heavy_dir="$work/heavy-from" heavy_at="$template_repo@${heavy_from:0:7} (the pin, $template_ref, has none yet)"
  template_fetch "$heavy_dir" "$template_repo" "$heavy_from" || heavy_dir=""
fi
if [ -z "$heavy_dir" ]; then bad "could not fetch $heavy_at to compare scripts/heavy.sh with"
elif out="$(same_file "$heavy_dir/template/scripts/heavy.sh" "$root/scripts/heavy.sh")"
then ok "scripts/heavy.sh is template/scripts/heavy.sh at $heavy_at"
else bad "scripts/heavy.sh is not template/scripts/heavy.sh at $heavy_at; copy the template's:"; echo "$out"; fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
