#!/usr/bin/env bash
# The fixed term table (#809): docs/reference/terms.md has one row per term a
# beginner meets in the first project, each with a plain explanation, and
# states the rule that the English term stays in brackets after a
# translation. GLOSSARY.md links it, and /plinth:guide points at it with the
# first-use rule. The must-not-pass cases run first.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
page="$root/docs/reference/terms.md"
guide="$root/skills/guide/SKILL.md"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

terms=(repository issue "pull request" branch commit check CI merge ruleset draft review "template update")

# check_table <file>: prints each missing or empty row; returns 1 if any.
check_table() {
  local f="$1" t row expl rc=0
  [ -r "$f" ] || { echo "unreadable: $f"; return 1; }
  for t in "${terms[@]}"; do
    row="$(grep -E "^\| \*\*$t\*\* \|" "$f" | head -1)"
    if [ -z "$row" ]; then echo "no row: $t"; rc=1; continue; fi
    expl="$(printf '%s' "$row" | awk -F'|' '{print $3}' | tr -d '[:space:]')"
    [ -n "$expl" ] || { echo "no explanation: $t"; rc=1; }
  done
  grep -q -E 'English term .*in brackets' "$f" || { echo "no bracket rule"; rc=1; }
  return $rc
}

# Must not pass: a table missing a term, one with an empty explanation, one
# without the bracket rule, and no file at all.
good="$work/good.md"
{ echo "Keep the English term in brackets after any translation."
  echo "| Term | Plain explanation |"; echo "| --- | --- |"
  for t in "${terms[@]}"; do echo "| **$t** | words |"; done; } >"$good"
grep -v -F '**ruleset**' "$good" >"$work/missing.md"
sed 's/^| \*\*draft\*\* | words |$/| **draft** |  |/' "$good" >"$work/empty.md"
grep -v 'in brackets' "$good" >"$work/norule.md"
check_table "$work/missing.md" >/dev/null && bad "a table without ruleset passed" || ok "a table without a term fails"
check_table "$work/empty.md" >/dev/null && bad "an empty explanation passed" || ok "a row without an explanation fails"
check_table "$work/norule.md" >/dev/null && bad "a table without the bracket rule passed" || ok "a table without the bracket rule fails"
check_table "$work/absent.md" >/dev/null && bad "a missing file passed" || ok "a missing file fails"
check_table "$good" >/dev/null && ok "a complete fixture passes" || bad "a complete fixture failed"

# The real table.
if out="$(check_table "$page")"; then
  ok "docs/reference/terms.md has all ${#terms[@]} terms, each explained, and the bracket rule"
else
  bad "docs/reference/terms.md:"; printf '        %s\n' "$out"
fi
grep -q -F '(docs/reference/terms.md)' "$root/GLOSSARY.md" \
  && ok "GLOSSARY.md links the table" || bad "GLOSSARY.md does not link docs/reference/terms.md"
if grep -q -F 'docs/reference/terms.md' "$guide" && grep -q -E 'first time' "$guide"; then
  ok "/plinth:guide points at the table and states the first-use rule"
else
  bad "/plinth:guide does not point at docs/reference/terms.md with the first-use rule"
fi

echo "-- $pass passed, $fail failed"
[ "$fail" -eq 0 ]
