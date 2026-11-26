#!/usr/bin/env bash
# The archetype vocabulary has one source: the template's copier.yml. The floor
# checker only needs to know which archetypes get a container image and a
# .env.example, and those names must be exactly the ones copier.yml conditions
# on. Reads the real copier.yml from one checkout at the commit the door pins
# (tests/lib/template-checkout.sh), not `main`: the checker must agree with
# what the door actually renders. A template that moves ahead of the pin is not
# a failure here; raising the pin brings its vocabulary into this check. No
# checkout, or no copier.yml in it, is a FAIL, not a pass (a check that cannot
# fail is not a check).
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/template-checkout.sh
. "$root/tests/lib/template-checkout.sh"
work="$(mktemp -d)" || { echo "archetype-single-source: could not make a temp folder" >&2; exit 1; }; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

# 1. The checker validates no full list of choices; it reads the archetype from
#    .copier-answers.yml and copier is the judge of valid values.
if grep -qE "cli.*library.*backend.*data-ml" "$root/scripts/floor-check.py"
then bad "floor-check.py hardcodes the archetype choices; the template owns that list"
else ok "floor-check.py does not hardcode the archetype choices"; fi

# 2. The conditional set equals what copier.yml's `_exclude` conditions name.
if ! template_checkout "$work"; then
  bad "no checkout of the template: $template_error"
elif ! copier="$(cat "$template_dir/copier.yml" 2>/dev/null)" || [ -z "$copier" ]; then
  bad "$template_at has no copier.yml; cannot verify the vocabulary"
else
  from_template="$(grep -o "archetype not in \[[^]]*\]" <<<"$copier" | head -1 | grep -o "'[a-z-]*'" | tr -d "'" | sort | tr '\n' ' ')"
  from_checker="$(python3 "$root/scripts/floor-check.py" --print-conditional-archetypes | tr ' ' '\n' | sort | tr '\n' ' ')"
  if [ -n "$from_template" ] && [ "$from_template" = "$from_checker" ]
  then ok "conditional archetypes agree with $template_at copier.yml: $from_checker"
  else bad "conditional archetypes differ: checker '$from_checker' vs $template_at '$from_template'"; fi
fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
