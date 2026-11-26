#!/usr/bin/env bash
# /plinth:new-project shows every answer in one table before it creates
# anything, and asks again only the rows the person picks (#1068). The skill is
# text an agent follows, so this test reads skills/new-project/questions.md,
# where the skill's questions are written out (and the skill itself for what it no longer says): each
# row, the primary choice's form, the "change some" groups, what a change asks
# next, the text-mode line, and what a choice costs beside it (#1154). The door's own half (a description shortened to
# 350 characters is accepted) is a case in tests/new-project-failpath.sh.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skill="${1:-$root/skills/new-project/SKILL.md}"
questions="$(dirname "$skill")/questions.md"
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

# The step, from its heading to the next heading or the end, as one line.
step="$(awk '/^## 8\. Every answer in one table/ {on=1; print; next} on && /^## / {exit} on' "$questions" | tr '\n' ' ' | tr -s ' ')"
if [ -n "$step" ]; then ok "step 8 is the table, read up to the run"
else bad "step 8 \"Every answer in one table\" is missing from $questions, so the checks below read nothing"; fi

echo "-- the table holds every answer, the name and the visibility among them"
# One row each, in a table whose first cell is the row's number.
row() { printf '%s\n' "$step" | grep -oE "\| $1 \| $2 \|[^|]*\|[^|]*\|" | head -n 1; }
for pair in "1::Repository and host" "2::Kind" "3::Visibility" "4::License" \
            "5::Third-party reviewer" "6::Code of conduct" "7::Description" "8::Records language" \
            "9::Local folder"; do
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
says "the records-language row" "$(row 8 'Records language')" 'language the sentence of step 2 is written in' 'named in English' '`--records-language=<language>`'
says "the folder row" "$(row 9 'Local folder')" '`--dir=' 'absolute path'
# The code-of-conduct row is filled after the owner's files are read, and the
# table is checked with --check before it is shown, so a description still too
# long is shortened again.
owner_at="$(printf '%s\n' "$step" | grep -bo 'scripts/owner-files.sh' | head -n 1 | cut -d: -f1)"
table_at="$(printf '%s\n' "$step" | grep -bo '| 1 | Repository and host |' | head -n 1 | cut -d: -f1)"
if [ -n "$owner_at" ] && [ -n "$table_at" ] && [ "$owner_at" -lt "$table_at" ]
then ok "the owner's files are read before the table is shown"
else bad "owner-files.sh (at ${owner_at:-none}) is not read before the table (at ${table_at:-none})"; fi
says "the step" "$step" 'A `code_of_conduct: yes` line means the owner'"'"'s applies' 'the script ignores `--code-of-conduct` then' \
  '<name> --check <flags of the table>' 'shorten it and check again'
# The table check names the name once: $ARGUMENTS may hold it too, and a name
# given twice stops the check (one name only).
check_line="$(printf '%s\n' "$step" | grep -oE 'new-project\.sh <name> --check[^`]*' | head -n 1)"
case "$check_line" in
  *'$ARGUMENTS'*) bad "the table check passes \$ARGUMENTS beside <name>: $check_line" ;;
  '') bad "the table check line is missing" ;;
  *) ok "the table check gives the name once" ;;
esac
says "the step" "$step" 'the new name in place of the old' 'The name is replaced the same way: one name, the new one.'

echo "-- the primary choice names the action, the visibility and owner/name"
says "the step" "$step" 'header `Create`' \
  '| Create `VISIBILITY` repository `owner/name` (Recommended) |' \
  '`VISIBILITY` is `public` or `private`' 'No second "are you sure"'

echo "-- change some: one multi-select of at most four groups matching the rows"
says "the step" "$step" '| Change some |' 'header `Change`' 'multi-select'
groups="$(printf '%s\n' "$step" | grep -oE '\| (Name and folder|Records language and description|License|Reviewer and code of conduct) \| rows? [0-9, and]+ \|' | sort -u)"
if [ "$(printf '%s\n' "$groups" | grep -c .)" = 4 ]; then ok "four groups, each naming its rows"
else bad "the groups are not the four with their rows:"; printf '%s\n' "$groups" | sed 's/^/        /'; fi
says "the groups" "$groups" '| Name and folder | rows 1 and 9 |' '| Records language and description | rows 7 and 8 |' \
  '| License | row 4 |' '| Reviewer and code of conduct | rows 5 and 6 |'
says "the step" "$step" 'On GitLab.com leave out rows 5 and 6' 'On GitLab.com leave out **Reviewer and code of conduct**'
# The description and the records language are door flags on both hosts now
# (#1068, coolbress/plinth-template#331): GitLab keeps their rows and group.
for old in 'the GitLab door sets no description yet' 'leave out **Description**'; do
  if printf '%s\n' "$step" | grep -qF -- "$old"; then bad "the step still says \"$old\""
  else ok "the step no longer says \"$old\""; fi
done

echo "-- the records language: asked in its group, hinted when public and not English"
says "the step" "$step" 'header `Records`' '`--records-language=English`' \
  'When the visibility is public and the records language is not English' 'on a public page' 'Say nothing of it otherwise' \
  'named in English: write it as `Korean`, not `ko`'

echo "-- only the picked groups are asked; what a change moves is asked too"
says "the step" "$step" 'Only the groups picked are asked' \
  'A code of conduct turned on asks its report contact before the table returns' 'An empty answer is asked again' \
  'typed into Other ("make it private")' \
  'A visibility changed this way asks the license again, with the new recommendation first' \
  'each changed row marked' 'show the table again'

echo "-- text mode"
# #1067: a claude -p run numbered Create as 1, the same number as row 1; 0 never said it creates.
says "the step" "$step" 'Type 0 to create it as shown, or the numbers of the rows to change' \
  'Do not number `Create` and `Change some` as choices in text' 'only 0 creates. "Stop" ends it, with nothing created'
says "the name step" "$(tr '\n' ' ' < "$questions" | tr -s ' ')" 'gives nothing to translate' 'plain names for the kind'

echo "-- what a choice costs, beside the choice (#1154)"
qflat="$(tr '\n' ' ' < "$questions" | tr -s ' ')"
says "the questions" "$qflat" \
  'the whole history, the issues and the Actions logs are public too' \
  'a fork made while it is public stays public if the repository is made private later' \
  'https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility' \
  'the month'"'"'s total' 'Claude Pro, US$20 a month (US$17 a month billed yearly' 'https://claude.com/pricing' \
  'a US$7 web service and a US$6 Postgres' 'https://render.com/pricing' 'about US$33 a month in all' \
  '`cli`, `library` and `data-ml`: no host cost' '`backend`: no host cost until its image runs somewhere' \
  'each run is 13 jobs (14 for `backend`, `data-ml` and `web`)' 'each billed as at least one minute' \
  'about 13 to 15 billed minutes' 'an edited title or description runs it again' \
  'US$18 a month, about 3,000 Linux minutes at US$0.006' \
  'https://docs.github.com/en/billing/reference/actions-runner-pricing' \
  'https://docs.github.com/en/billing/concepts/product-billing/github-actions' \
  'roughly 40 to 75 pull requests a month' 'an estimate, not measured on a private repository'
# Every price is dated where it is printed.
n_read="$(grep -o 'read 2026-11-26' "$questions" | wc -l | tr -d ' ')"
if [ "$n_read" -ge 3 ]; then ok "the questions date their prices ($n_read \"read 2026-11-26\")"
else bad "the questions date $n_read prices, fewer than the 3 places that print one"; fi
grep -qF '9 jobs' "$root/docs/explanation/concepts.md" && bad "concepts.md still says 9 jobs" || ok "concepts.md no longer says 9 jobs"
says "concepts.md" "$(tr '\n' ' ' < "$root/docs/explanation/concepts.md" | tr -s ' ')" 'each CI run is 13 jobs (14 for backend, data-ml and web'

echo "-- every answer stays a flag, so the command said before the run asks nothing"
says "the step" "$step" 'Every row becomes a flag, a default included' \
  'the description'"'"'s, `--records-language=`, and on GitHub the reviewer'"'"'s' \
  'For `web`, add `--custom-user-model` without asking' '`--no-custom-user-model`' \
  'When the arguments give every row, show the table and ask nothing' \
  'A row changed at the table replaces its flag among the arguments' 'never both'
# The bundled question is gone, read as one line so a phrase across lines counts.
flat="$(cat "$skill" "$questions" | tr '\n' ' ' | tr -s ' ')"
for old in 'header `Defaults`' 'Use the recommended defaults?' '| Customize |' 'It never names the host or the visibility.'; do
  if printf '%s\n' "$flat" | grep -qF -- "$old"; then bad "the skill still says \"$old\""
  else ok "the skill no longer says \"$old\""; fi
done

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
