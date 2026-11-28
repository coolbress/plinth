#!/usr/bin/env bash
# Each tool version plinth pins has one source a bot raises (#1220):
#   tools/lint/pyproject.toml    zizmor, ruff, mypy (`ci / tools`), locked in its uv.lock
#   tools/copier/pyproject.toml  copier (the door, /plinth:template-update), locked in its uv.lock
# Dependabot's uv ecosystem raises both (.github/dependabot.yml). Every other
# place that names one of these versions is checked here against its source:
#   - `zizmor@<version>` anywhere in .github/, docs/, scripts/ or skills/
#     (python-ci.yml runs it in consumers' CI, which cannot read the lock);
#   - no `copier==<version>` or `copier_version="<version>"` there at all:
#     everything that runs copier reads tools/copier (scripts/lib/copier-pin.sh).
# Each pin is exact (`==`) and its uv.lock holds that version. Then the same
# checks run on a made-up tree with one stale copy of each, and must fail.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

pin_in() { # <pyproject.toml> <package> -> the exact pin's version
  sed -n "s/^ *\"$2==\([^\"]*\)\",\{0,1\}\$/\1/p" "$1"
}
locked() { # <uv.lock> <package> <version>: the lock holds that version
  awk -v n="$2" -v v="$3" '$0 == "name = \"" n "\"" {getline; if ($0 == "version = \"" v "\"") f=1} END {exit !f}' "$1"
}

# problems <tree>: one line per copy that disagrees with its source; none when all agree.
problems() {
  local t="$1" z c p group
  for group in lint:zizmor lint:ruff lint:mypy copier:copier; do
    p="${group#*:}"; group="${group%%:*}"
    [ -n "$(pin_in "$t/tools/$group/pyproject.toml" "$p")" ] \
      || { echo "tools/$group/pyproject.toml has no exact pin of $p (\"$p==<version>\")"; continue; }
    locked "$t/tools/$group/uv.lock" "$p" "$(pin_in "$t/tools/$group/pyproject.toml" "$p")" 2>/dev/null \
      || echo "tools/$group/uv.lock does not hold $p==$(pin_in "$t/tools/$group/pyproject.toml" "$p") (uv lock --project tools/$group)"
  done
  z="$(pin_in "$t/tools/lint/pyproject.toml" zizmor)"
  while IFS= read -r hit; do
    case "$hit" in *"zizmor@$z "*|*"zizmor@$z\`"*|*"zizmor@$z") ;; *) echo "names another zizmor than tools/lint's $z: $hit" ;; esac
  done < <(cd "$t" && grep -rnoE 'zizmor@[0-9][0-9A-Za-z.]*.?' .github docs scripts skills 2>/dev/null | grep -v '^\.github/dependabot\.yml:')
  while IFS= read -r hit; do
    echo "names copier's version outside tools/copier (read it with scripts/lib/copier-pin.sh): $hit"
  done < <(cd "$t" && grep -rnE 'copier==[0-9]|copier_version="[0-9]' .github docs scripts skills 2>/dev/null)
  for c in /tools/lint /tools/copier; do
    awk -v d="$c" '/package-ecosystem: uv/ {u=1} u && $0 ~ "^ *- " d "$" {f=1} END {exit !f}' "$t/.github/dependabot.yml" 2>/dev/null \
      || echo ".github/dependabot.yml's uv ecosystem does not cover $c"
  done
}

echo "-- this repository: each pin has one source"
out="$(problems "$root")"
if [ -z "$out" ]; then ok "zizmor, ruff, mypy and copier: every copy agrees with tools/, and Dependabot covers both groups"
else bad "copies disagree with their source:"; printf '        %s\n' "$out"; fi

echo "-- a made-up tree with a stale copy of each fails"
tmp="$(mktemp -d)" || { echo "tool-pins: could not make a temp folder" >&2; exit 1; }; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/tools/lint" "$tmp/tools/copier" "$tmp/.github/workflows" "$tmp/scripts" "$tmp/docs"
cp "$root/tools/lint/pyproject.toml" "$root/tools/lint/uv.lock" "$tmp/tools/lint/"
cp "$root/tools/copier/pyproject.toml" "$root/tools/copier/uv.lock" "$tmp/tools/copier/"
cp "$root/.github/dependabot.yml" "$tmp/.github/"
z="$(pin_in "$root/tools/lint/pyproject.toml" zizmor)"
printf '      - run: uvx zizmor@%s --no-progress .\n' "$z" > "$tmp/.github/workflows/same.yml"
[ -z "$(problems "$tmp")" ] && ok "the copy at tools/lint's zizmor passes" || bad "a tree whose copies all agree was refused: $(problems "$tmp")"
printf '      - run: uvx zizmor@1.0.0 --no-progress .\n' > "$tmp/.github/workflows/stale.yml"
printf 'uvx --from copier==9.0.0 copier copy\n' > "$tmp/scripts/render.sh"
printf 'copier_version="9.0.0"\n' > "$tmp/scripts/door.sh"
out="$(problems "$tmp")"
grep -q 'names another zizmor than .*stale\.yml' <<<"$out" && ok "a workflow on another zizmor fails" || bad "zizmor@1.0.0 in a workflow was not refused: $out"
grep -q 'outside tools/copier.*render\.sh' <<<"$out" && ok "a copier==<version> outside tools/copier fails" || bad "copier==9.0.0 in a script was not refused: $out"
grep -q 'outside tools/copier.*door\.sh' <<<"$out" && ok "a copier_version=\"<version>\" outside tools/copier fails" || bad "copier_version=\"9.0.0\" was not refused: $out"
sed -i.bak 's/^\( *"zizmor==\)[^"]*/\10.0.1/' "$tmp/tools/lint/pyproject.toml"
grep -q 'uv.lock does not hold zizmor==0.0.1' <<<"$(problems "$tmp")" && ok "a pin its lock does not hold fails" || bad "a pin its uv.lock does not hold was not refused"
sed 's#- /tools/copier##' "$root/.github/dependabot.yml" > "$tmp/.github/dependabot.yml"
grep -q 'does not cover /tools/copier' <<<"$(problems "$tmp")" && ok "a group Dependabot does not watch fails" || bad "a dependabot.yml without /tools/copier was not refused"

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
