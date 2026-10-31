#!/usr/bin/env bash
# What the door sets up agrees with what the template it renders needs (#747).
#
# 1. The Actions allowlist: every action a rendered workflow uses, in every
#    archetype, is GitHub-owned or matched by a pattern the door allows for
#    that archetype, through floor-check.py's own matcher. Without that the
#    first `v*` tag ends in startup_failure with no job. Each pattern the door
#    names for an archetype is needed: cut it and an action is refused (the
#    must-not-pass side, and a stale pattern is caught too). No verified
#    creators, no wildcard wider than one named action.
# 2. SECURITY.md's route: a public render names GitHub's private reporting
#    form, which the door turns on for a public repository; a private render
#    names an issue, which needs nothing turned on, and never the form, which
#    a private repository is not offered.
#
# Renders the template at the tag the door pins (TEMPLATE_REF overrides, a
# branch or commit included) with the copier the door runs. Network; an
# unreadable template is a FAIL, not a pass.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
door="$root/scripts/new-project.sh"
template="${TEMPLATE_REPO:-coolbress/plinth-template}"
ref="${TEMPLATE_REF:-$(sed -n 's/^template_ref="\(.*\)"$/\1/p' "$door")}"
copier_version="$(sed -n 's/^copier_version="\(.*\)"$/\1/p' "$door")"
copier_newer="$(sed -n 's/^copier_newer="\(.*\)"$/\1/p' "$door")"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

# The door's patterns for one archetype: its release_actions case, run as written.
door_patterns() { # <archetype>
  local arch="$1" release_actions=()
  eval "$(sed -n '/^release_actions=()$/,/^esac$/p' "$door")"
  printf '%s\n' 'coolbress/plinth/*' ${release_actions[@]+"${release_actions[@]}"}
}
[ -n "$(sed -n '/^release_actions=()$/,/^esac$/p' "$door")" ] && ok "the door names its release actions in one case block" ||
  bad "no release_actions case block in scripts/new-project.sh"
grep -q -- '-F github_owned_allowed=true -F verified_allowed=false "${allow_args\[@\]}"' "$door" &&
  ok "the door allows GitHub-owned actions and its named patterns, not verified creators" ||
  bad "the door's allowlist call is not GitHub-owned plus the named patterns, with verified_allowed=false"

render() { # <dest> <copier --data args...>
  local dest="$1"; shift
  env -u GH_TOKEN -u GITHUB_TOKEN uvx --quiet --from "copier==$copier_version" --exclude-newer "$copier_newer" \
    copier copy --defaults --quiet --data project_name=probe --data owner=o --data license=MIT "$@" \
    --vcs-ref "$ref" "gh:$template" "$dest" </dev/null >/dev/null 2>&1
}

# Archetypes from the template's own copier.yml, not a list kept here.
copier_yml="$(curl -fsSL --retry 3 "https://raw.githubusercontent.com/$template/$ref/copier.yml" 2>/dev/null)"
archetypes="$(awk '/^archetype:/{a=1;next} a&&/^[^ #]/{exit} a&&/^  choices:/{c=1;next} c&&/^    [^:]+: /{print $NF}' <<<"$copier_yml")"
[ -n "$archetypes" ] || bad "could not read the archetypes from $template@$ref copier.yml"

for arch in $archetypes; do
  out="$work/$arch"
  if ! render "$out" --data "archetype=$arch"; then bad "$arch: could not render $template@$ref"; continue; fi
  patterns="$(door_patterns "$arch")"
  verdict="$(python3 - "$root/scripts/floor-check.py" "$out" "$patterns" <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("fc", sys.argv[1]); fc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fc)
root, patterns = Path(sys.argv[2]), [p for p in sys.argv[3].splitlines() if p]
uses = [v for p in fc.workflow_files(root) for _, v, r in fc.iter_uses(fc.read(p)) if r and not v.startswith("./")]
def refused(pats):
    return sorted({v.split("@", 1)[0] for v in uses
                   if v.split("/", 1)[0].lower() not in fc.GITHUB_OWNED and not fc.allowlist_allows(v, pats)})
print("refused:" + " ".join(refused(patterns)))
for p in patterns:
    print(f"cut {p}:" + " ".join(refused([q for q in patterns if q != p])))
for p in patterns:
    owner_repo = p.split("@", 1)[0]
    if p != "coolbress/plinth/*" and ("*" in owner_repo or not p.endswith("@*")):
        print(f"wide {p}")
PY
)"
  r="$(sed -n 's/^refused://p' <<<"$verdict")"
  [ -z "$r" ] && ok "$arch: every action its workflows use is allowed by the door" ||
    bad "$arch: the door's allowlist refuses $r (its first run that uses one ends in startup_failure)"
  while IFS= read -r line; do
    p="${line#cut }"; p="${p%%:*}"; left="${line#*:}"
    [ -n "$left" ] && ok "$arch: cut $p and $left is refused (must not pass)" ||
      bad "$arch: the door allows $p, which no workflow of this archetype needs"
  done < <(grep '^cut ' <<<"$verdict")
  ! grep -q '^wide ' <<<"$verdict" && ok "$arch: each pattern names one action, at any ref" ||
    bad "$arch: a pattern wider than one named action: $(grep '^wide ' <<<"$verdict" | tr '\n' ' ')"
done

# SECURITY.md's route against what the door sets up.
form="Security → Report a vulnerability"
pvr_call='[ "$private" = 1 ] ||'$'\n''  setup_call "private vulnerability reporting" -X PUT "repos/$repo/private-vulnerability-reporting"'
if render "$work/public" --data archetype=cli --data visibility=public && render "$work/private" --data archetype=cli --data visibility=private; then
  pub="$(sed '/^## Response/,$d' "$work/public/SECURITY.md")"; priv="$(sed '/^## Response/,$d' "$work/private/SECURITY.md")"
  if grep -qF "**$form**" <<<"$pub" && grep -qF "$pvr_call" "$door"; then ok "public: SECURITY.md names the form, and the door turns it on there"
  else bad "public: SECURITY.md names the form only if the door turns it on for a public repository (form named: $(grep -cF "$form" <<<"$pub"))"; fi
  if ! grep -q "private reporting form" <<<"$priv" && grep -q "Open an issue in this repository" <<<"$priv" &&
     grep -qF -- '--data "visibility=$([ "$private" = 1 ] && echo private || echo public)"' "$door"
  then ok "private: SECURITY.md names an issue, not the form a private repository lacks, and the door passes the answer"
  else bad "private: SECURITY.md must name an issue and not the form, from the visibility the door passes"; fi
else
  bad "could not render SECURITY.md from $template@$ref"
fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
