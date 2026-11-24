#!/usr/bin/env bash
# /plinth:new-project shows every answer in one table before it creates
# anything, and asks again only the rows the person picks (#1068). The skill is
# text an agent follows, so this test reads skills/new-project/SKILL.md: each
# row, the primary choice's form, the "change some" groups, what a change asks
# next, and the text-mode line. The door's own half (a description shortened to
# 350 characters is accepted) is a case in tests/new-project-failpath.sh.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skill="${1:-$root/skills/new-project/SKILL.md}"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
says() { # says <what> <text> <phrase>...
  local what="$1" text="$2"; shift 2
  for p in "$@"; do
    if printf '%s\n' "$text" | grep -qF -- "$p"; then ok "$what says \"$p\""
    else bad "$what does not say \"$p\""; fi
  done
}

# The step, from its heading to the run that follows it, as one line.
step="$(sed -n '/^8\. \*\*Every answer in one table/,/^Then run, with the arguments/p' "$skill" | tr '\n' ' ' | tr -s ' ')"
if [ -n "$step" ]; then ok "step 8 is the table, read up to the run"
else bad "step 8 \"Every answer in one table\" is missing, so the checks below read nothing"; fi

echo "-- the table holds every answer, the name and the visibility among them"
# One row each, in a table whose first cell is the row's number.
row() { printf '%s\n' "$step" | grep -oE "\| $1 \| $2 \|[^|]*\|[^|]*\|" | head -n 1; }
for pair in "1::Repository and host" "2::Kind" "3::Visibility" "4::License" \
            "5::Third-party reviewer" "6::Code of conduct" "7::Description" "8::Local folder"; do
  n="${pair%%::*}"; name="${pair#*::}"
  if [ -n "$(row "$n" "$name")" ]; then ok "row $n is \"$name\""
  else bad "the table has no row $n \"$name\""; fi
done
says "the repository row" "$(row 1 'Repository and host')" '`owner/name` on GitHub' 'GitLab.com' '`--host=github`'
says "the kind row" "$(row 2 Kind)" '`--archetype=`' 'where it runs' '`--hosting=`'
says "the visibility row" "$(row 3 Visibility)" '`--public`' '`--private`'
says "the license row" "$(row 4 License)" 'MIT for a public project, Proprietary for a private one'
says "the reviewer row" "$(row 5 'Third-party reviewer')" '`--no-third-party-review`'
says "the code-of-conduct row" "$(row 6 'Code of conduct')" "the owner's applies" '`--no-code-of-conduct`'
says "the description row" "$(row 7 Description)" 'sentence of step 2' 'one line of at most 350 characters' '`--no-description`'
says "the folder row" "$(row 8 'Local folder')" '`--dir=' 'absolute path'
# The code-of-conduct row is filled after the owner's files are read, and the
# table is checked with --check before it is shown, so a description still too
# long is shortened again.
owner_at="$(printf '%s\n' "$step" | grep -bo 'scripts/owner-files.sh' | head -n 1 | cut -d: -f1)"
table_at="$(printf '%s\n' "$step" | grep -bo '| 1 | Repository and host |' | head -n 1 | cut -d: -f1)"
if [ -n "$owner_at" ] && [ -n "$table_at" ] && [ "$owner_at" -lt "$table_at" ]
then ok "the owner's files are read before the table is shown"
else bad "owner-files.sh (at ${owner_at:-none}) is not read before the table (at ${table_at:-none})"; fi
says "the step" "$step" 'A `code_of_conduct: yes` line means the owner'"'"'s applies' 'the script ignores `--code-of-conduct` then' \
  '<name> --check --host=<host>' 'shorten it and check again'

echo "-- the primary choice names the action, the visibility and owner/name"
says "the step" "$step" 'header `Create`' \
  '| Create `VISIBILITY` repository `owner/name` (Recommended) |' \
  '`VISIBILITY` is `public` or `private`' 'No second "are you sure"'

echo "-- change some: one multi-select of at most four groups matching the rows"
says "the step" "$step" '| Change some |' 'header `Change`' 'multi-select'
groups="$(printf '%s\n' "$step" | grep -oE '\| (Name and folder|Description|License|Reviewer and code of conduct) \| rows? [0-9, and]+ \|' | sort -u)"
if [ "$(printf '%s\n' "$groups" | grep -c .)" = 4 ]; then ok "four groups, each naming its rows"
else bad "the groups are not the four with their rows:"; printf '%s\n' "$groups" | sed 's/^/        /'; fi
says "the groups" "$groups" '| Name and folder | rows 1 and 8 |' '| Description | row 7 |' \
  '| License | row 4 |' '| Reviewer and code of conduct | rows 5 and 6 |'
says "the step" "$step" 'On GitLab.com leave out rows 5, 6 and 7' 'On GitLab.com leave out **Description** and **Reviewer and code of conduct**'

echo "-- only the picked groups are asked; what a change moves is asked too"
says "the step" "$step" 'Only the groups picked are asked' \
  'A code of conduct turned on asks its report contact before the table returns' 'An empty answer is asked again' \
  'typed into Other ("make it private")' \
  'A visibility changed this way asks the license again, with the new recommendation first' \
  'each changed row marked' 'show the table again'

echo "-- text mode"
says "the step" "$step" 'numbers to change, comma-separated; 0 to keep'

echo "-- every answer stays a flag, so the command said before the run asks nothing"
says "the step" "$step" 'Every row becomes a flag, a default included'
# The bundled question is gone, read as one line so a phrase across lines counts.
flat="$(tr '\n' ' ' < "$skill" | tr -s ' ')"
for old in 'header `Defaults`' 'Use the recommended defaults?' '| Customize |' 'It never names the host or the visibility.'; do
  if printf '%s\n' "$flat" | grep -qF -- "$old"; then bad "the skill still says \"$old\""
  else ok "the skill no longer says \"$old\""; fi
done

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
