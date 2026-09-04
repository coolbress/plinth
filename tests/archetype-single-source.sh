#!/usr/bin/env bash
# The archetype vocabulary has one source: the template's copier.yml. The floor
# checker only needs to know which archetypes get a container image and a
# .env.example, and those names must be the ones copier.yml conditions on.
# Offline: `gh` is mocked with the shape copier.yml has.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

# 1. The checker validates no full list of choices; it reads the archetype from
#    .copier-answers.yml and copier is the judge of valid values.
if grep -qE "cli.*library.*backend.*data-ml" "$root/scripts/floor-check.py"
then bad "floor-check.py hardcodes the archetype choices; the template owns that list"
else ok "floor-check.py does not hardcode the archetype choices"; fi

# 2. The conditional set equals what copier.yml's `_exclude` conditions name.
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT; mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'MOCK'
#!/usr/bin/env bash
printf '_exclude:\n  - "{%% if archetype not in [%s] %%}.env.example{%% endif %%}"\n  - "{%% if archetype not in [%s] %%}Dockerfile{%% endif %%}"\narchetype:\n  type: str\n' "'backend', 'data-ml'" "'backend', 'data-ml'" | base64
MOCK
chmod +x "$work/bin/gh"
from_template="$(PATH="$work/bin:$PATH" bash -c 'gh api x --jq .content | base64 -d' \
  | grep -o "archetype not in \[[^]]*\]" | head -1 | grep -o "'[a-z-]*'" | tr -d "'" | sort | tr '\n' ' ')"
from_checker="$(python3 "$root/scripts/floor-check.py" --print-conditional-archetypes | tr ' ' '\n' | sort | tr '\n' ' ')"
if [ -n "$from_template" ] && [ "$from_template" = "$from_checker" ]
then ok "conditional archetypes agree with copier.yml: $from_checker"
else bad "conditional archetypes differ: checker '$from_checker' vs template '$from_template'"; fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
