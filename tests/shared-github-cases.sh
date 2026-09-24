#!/usr/bin/env bash
# Verdicts of scripts/lib/shared-github.sh: which of the owner's shared
# community-health files apply to a new repository. The door fetches with
# `gh api` and hands the answers in; here the answers are small fixtures, so
# each decision runs without a repository and without the door's `gh` mock.
# tests/new-project-failpath.sh still runs the same logic through the whole door.
#
# A fetched answer is `ok:<output>` or `err:<gh's own words>`, which is what the
# door passes. Two fixtures are past bugs: #88 (a template under `.github/` was
# missed and the door wrote over it) and #101 (a failed listing read as "no
# config", so the config-only warning never printed).
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# Any `gh` a decision reaches for is a failure, not a network call.
mkdir -p "$work/bin"
printf '#!/bin/sh\necho called >> "%s/gh-called"; exit 1\n' "$work" > "$work/bin/gh"; chmod +x "$work/bin/gh"
PATH="$work/bin:$PATH"
# shellcheck source=scripts/lib/shared-github.sh
. "$root/scripts/lib/shared-github.sh" || { echo "  FAIL  cannot source scripts/lib/shared-github.sh"; exit 1; }

pass=0; fail=0
is() { # <label> <want> <got>
  if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "  PASS  $1"
  else fail=$((fail+1)); echo "  FAIL  $1"; echo "        want: $2"; echo "        got:  $3"; fi
}
b64() { printf '%s' "$1" | base64; }
nf='err:gh: Not Found (HTTP 404)'
e500='err:mock gh: HTTP 500'
form_yml="$(b64 $'name: Bug\ndescription: x\nbody: []\n')"

echo "-- why_unknown"
is "the reason is peeled off an unknown answer" "x: HTTP 500" "$(why_unknown "unknown: x: HTTP 500")"
is "an answer that is not unknown has no reason" "(no message)" "$(why_unknown yes)"

echo "-- usable_form"
u() { if usable_form "$1" "$2"; then echo 0; else echo 1; fi; }
is "a markdown template with a name is offered" 0 "$(u $'---\nname: Bug\n---\n' bug.md)"
is "a markdown template with an empty quoted name is not" 1 "$(u $'---\nname: ""\n---\n' bug.md)"
is "an empty markdown file is not" 1 "$(u "" bug.md)"
is "a form with name, description and body is offered" 0 "$(u $'name: Bug\ndescription: x\nbody: []\n' bug.yml)"
is "a form without a body is not" 1 "$(u $'name: Bug\ndescription: x\n' bug.yml)"

echo "-- shared_of"
is "#88: absent at the root, present under .github/ is present" yes \
  "$(shared_of PULL_REQUEST_TEMPLATE.md "$nf" .github/PULL_REQUEST_TEMPLATE.md 'ok:' docs/PULL_REQUEST_TEMPLATE.md "$nf")"
is "absent everywhere is no" no \
  "$(shared_of PULL_REQUEST_TEMPLATE.md "$nf" .github/PULL_REQUEST_TEMPLATE.md "$nf" docs/PULL_REQUEST_TEMPLATE.md "$nf")"
is "a failed lookup and nothing present is unknown, with the path and gh's words" \
  "unknown: docs/PULL_REQUEST_TEMPLATE.md: mock gh: HTTP 500" \
  "$(shared_of PULL_REQUEST_TEMPLATE.md "$nf" .github/PULL_REQUEST_TEMPLATE.md "$nf" docs/PULL_REQUEST_TEMPLATE.md "$e500")"
is "present wins over a failed lookup elsewhere" yes \
  "$(shared_of PULL_REQUEST_TEMPLATE.md "$e500" .github/PULL_REQUEST_TEMPLATE.md 'ok:')"
is "a malformed answer is unknown, not absent" "unknown: x: not a fetched answer" "$(shared_of x 'garbage')"

echo "-- shared_forms"
is "#101: a failed listing is unknown, not no and not config-only" \
  "unknown: .github/ISSUE_TEMPLATE: mock gh: HTTP 500" "$(shared_forms "$e500")"
is "no folder is no" no "$(shared_forms "$nf")"
is "a folder holding only a config is config-only" config-only "$(shared_forms 'ok:config.yml' config.yml "$nf")"
is "a config beside a usable form is yes" yes \
  "$(shared_forms $'ok:config.yml\nbug.yml' config.yml "$nf" bug.yml "ok:$form_yml")"
is "an empty form is no" no "$(shared_forms 'ok:bug.yml' bug.yml "ok:")"
is "a folder holding only .gitkeep is no" no "$(shared_forms 'ok:.gitkeep' .gitkeep "$nf")"
is "a markdown template with a name is yes" yes "$(shared_forms 'ok:bug.md' bug.md "ok:$(b64 $'---\nname: Bug\n---\n')")"
is "a candidate that could not be read is unknown" "unknown: .github/ISSUE_TEMPLATE/bug.yml: mock gh: HTTP 500" \
  "$(shared_forms 'ok:bug.yml' bug.yml "$e500")"
is "a candidate that was never fetched is unknown" "unknown: .github/ISSUE_TEMPLATE/bug.yml: not fetched" \
  "$(shared_forms 'ok:bug.yml')"
got="$(shared_forms 'ok:bug.yml' bug.yml 'ok:!!!not base64!!!')"
is "content that does not decode is unknown" "unknown: .github/ISSUE_TEMPLATE/bug.yml: content could not be decoded" "${got%% (*}"
is "the first usable template decides, before a later unreadable one" yes \
  "$(shared_forms $'ok:a.yml\nb.yml' a.yml "ok:$form_yml" b.yml "$e500")"

echo "-- shared_repo_public"
is "public is yes" yes "$(shared_repo_public 'ok:public')"
is "private is no: GitHub never inherits from it" no "$(shared_repo_public 'ok:private')"
is "no .github repository is no" no "$(shared_repo_public "$nf")"
is "a failed lookup is unknown, with gh's words" "unknown: mock gh: HTTP 500" "$(shared_repo_public "$e500")"

echo "-- purity"
is "no decision called gh" no "$([ -e "$work/gh-called" ] && echo yes || echo no)"
# Comments are cut first: they may name `gh api` to say where the data came from.
is "the library has no gh call in it" 0 "$(sed 's/#.*//' "$root/scripts/lib/shared-github.sh" | grep -cE '(^|[^[:alnum:]_])gh[[:space:]]')"

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
