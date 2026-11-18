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
# a checkout it would name the checkout's path.
render() {
  env -u GH_TOKEN -u GITHUB_TOKEN uvx --quiet --from "copier==$copier_version" --exclude-newer "$copier_newer" \
    copier copy --defaults --quiet \
    --data project_name=probe --data owner=coolbress --data license=MIT --data archetype=cli \
    --data owner_has_pr_template=false --data owner_has_issue_forms=false --data visibility=public \
    --vcs-ref HEAD "$1" "$2" </dev/null >/dev/null 2>"$work/copier.err" || { cat "$work/copier.err" >&2; return 1; }
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
            continue
        kv = re.fullmatch(r"      ([A-Za-z0-9_-]+):\s*(.*)", line)
        if kv and block in ("permissions", "with"):
            out[block][kv.group(1)] = kv.group(2).strip("\"'")
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
printf '    secrets: inherit\n' >>"$work/rendered.yml"
if out="$(mirror "$work/good.yml" "$work/rendered.yml" "$tag" "$sha")"; then bad "a rendered caller with a key the job lacks (secrets:) passes"
else ok "a rendered caller with a key the job lacks fails ($(head -1 <<<"$out"))"; fi
perl -ni -e 'print unless /^    secrets: inherit$/' "$work/rendered.yml"
grep -v '^  canary-template:' "$work/good.yml" | sed '/^    name: canary-template/,$d' >"$work/none.yml"
if out="$(mirror "$work/none.yml" "$work/rendered.yml" "$tag" "$sha")"; then bad "no canary-template job passes"
else ok "no canary-template job fails ($out)"; fi

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

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
