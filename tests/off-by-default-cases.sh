#!/usr/bin/env bash
# The off-by-default list (#763): docs/reference/off-by-default.md is its one
# source, scripts/off-by-default.sh its one reader, and new-project.sh and
# guide-state.sh both call that reader. Cases: what each archetype is told,
# a feature the project already has is not listed, a Steps page that does not
# exist fails --check (must-not-pass first), and a phrase a project file must
# contain is read in the template at the tag the door pins (network; an
# unreadable template is a FAIL, as in archetype-single-source.sh).
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/off-by-default.sh"
work="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

reviewer='off: The third-party reviewer (`third-party / review`). Turn it on when a code reviewer such as Codex'"'"'s is connected to your GitHub account: https://github.com/coolbress/plinth/blob/main/docs/how-to/configure-the-third-party-reviewer.md'
howto='https://github.com/coolbress/plinth/blob/main/docs/how-to/configure-the-third-party-reviewer.md'
on_repo="now: Turn on Codex code review for this repository in your Codex settings, \`https://chatgpt.com/codex/settings/code-review\`. Until it is on, \`third-party / review\` waits 20 minutes on each pull request and then fails; it does not block the merge. The steps: $howto#1-enable-the-reviewer-on-the-repository"
summons="off: The summons token (\`SUMMONS_TOKEN\`). Turn it on when the reviewer does not start on its own once a pull request is ready: $howto#summoning-the-reviewer"
require="off: Requiring the third-party reviewer (\`third-party / review\` in the ruleset, through \`scripts/upgrade-ruleset.sh\`). Turn it on when it has reported on a pull request and you want no merge without it; the command needs repository administration: $howto#3-make-it-part-of-the-wall-optional"
hsts='off: HSTS preload and include-subdomains. Turn it on when every subdomain answers over HTTPS (include-subdomains), and you accept that preload takes months to undo: the steps are in README.md under "HSTS preload and include-subdomains are off"'

# 1. A Steps page that does not exist fails --check; so does a table with no rows.
printf '# x\n\n## The list\n\n| Feature | Archetypes | Turn it on when | Steps | On when the project has | Listed only when the project has |\n| --- | --- | --- | --- | --- | --- |\n| A | all | b | `docs/how-to/no-such-page.md` | - | - |\n' > "$work/missing.md"
if out="$(PLINTH_OFF_BY_DEFAULT="$work/missing.md" "$script" --check 2>&1)"; then bad "--check passed a Steps page that does not exist"
elif grep -qF "docs/how-to/no-such-page.md" <<<"$out"; then ok "--check fails a Steps page that does not exist, and names it"
else bad "--check failed without naming the missing page: $out"; fi
printf '# x\n\n## The list\n\n| Feature | Archetypes | Turn it on when | Steps | On when the project has | Listed only when the project has |\n| --- | --- | --- | --- | --- | --- |\n' > "$work/empty.md"
if PLINTH_OFF_BY_DEFAULT="$work/empty.md" "$script" cli >/dev/null 2>&1; then bad "a list with no rows printed nothing and passed"
else ok "a list with no rows is an error, not an empty answer"; fi
printf '# x\n\n## The list\n\n| Feature | Archetypes | Turn it on when | Steps | On when the project has | Listed only when the project has |\n| --- | --- | --- | --- | --- | --- |\n| A | all | b | somewhere | - | - |\n' > "$work/badsteps.md"
if PLINTH_OFF_BY_DEFAULT="$work/badsteps.md" "$script" --check >/dev/null 2>&1; then bad "--check passed a Steps cell in neither form"
else ok "--check fails a Steps cell that is neither a docs/ page nor a project file with a phrase"; fi
printf '# x\n\n## The list\n\n| Feature | Archetypes | Turn it on when | Steps | On when the project has | Listed only when the project has |\n| --- | --- | --- | --- | --- | --- |\n| A | all | b | `docs/how-to/configure-the-third-party-reviewer.md#no-such-heading` | - | - |\n' > "$work/anchor.md"
if out="$(PLINTH_OFF_BY_DEFAULT="$work/anchor.md" "$script" --check 2>&1)"; then bad "--check passed an anchor the page has no heading for"
elif grep -qF "#no-such-heading" <<<"$out"; then ok "--check fails an anchor the page has no heading for, and names it"
else bad "--check failed the anchor without naming it: $out"; fi
printf '# x\n\n## The list\n\n| Feature | Archetypes | Turn it on when | Steps | On when the project has | Listed only when the project has |\n| --- | --- | --- | --- | --- | --- |\n| A | all | b | `docs/how-to/configure-the-third-party-reviewer.md` | - |\n' > "$work/five.md"
if PLINTH_OFF_BY_DEFAULT="$work/five.md" "$script" cli >/dev/null 2>&1; then bad "a row of five cells (the list before #765) was read"
else ok "a row with five cells is an error"; fi

# 2. The real list passes --check.
if out="$("$script" --check 2>&1)"; then ok "the list's Steps pages all exist"; else bad "--check on the list: $out"; fi

# 3. What each archetype is told.
for a in cli library backend data-ml; do
  out="$("$script" "$a")"
  if [ "$out" = "$reviewer" ]; then ok "$a: the reviewer only, not the web item"
  else bad "$a: got"$'\n'"$out"; fi
done
out="$("$script" web)"
if [ "$out" = "$reviewer"$'\n'"$hsts" ]; then ok "web: the reviewer and HSTS"; else bad "web: got"$'\n'"$out"; fi
if "$script" >/dev/null 2>&1; then bad "no archetype given passed"; else ok "no archetype given is a usage error"; fi

# 4. With a project directory: a feature it has is not listed; one with no
#    sign in the project is said to have started off.
mkdir -p "$work/p/.github/workflows"
out="$("$script" web "$work/p")"
if grep -qF "${reviewer#off: }" <<<"$out" && grep -qxF "started off (whether it is on now is not read): ${hsts#off: }" <<<"$out"
then ok "a project without the caller: the reviewer is off, HSTS started off"
else bad "project without the caller: got"$'\n'"$out"; fi
: > "$work/p/.github/workflows/third-party.yml"
out="$("$script" web "$work/p")"
if ! grep -qF "The third-party reviewer (" <<<"$out" && grep -qxF "started off (whether it is on now is not read): ${require#off: }" <<<"$out" && grep -qF "HSTS" <<<"$out"
then ok "a project with .github/workflows/third-party.yml: the reviewer is not listed, requiring it is said to have started off"
else bad "project with the caller: got"$'\n'"$out"; fi

# 4b. --new (new-project.sh, just rendered): what the project has is dropped,
#     an item with no sign is plainly off.
out="$("$script" --new web "$work/p")"
if [ "$out" = "$on_repo"$'\n'"$summons"$'\n'"$require"$'\n'"$hsts" ]; then ok "--new: the caller rendered drops the reviewer and names what is left of it (#765); HSTS is off, not 'started off'"
else bad "--new with the caller: got"$'\n'"$out"; fi
out="$("$script" --new cli "$work/p")"
if [ "$out" = "$on_repo"$'\n'"$summons"$'\n'"$require" ]; then ok "--new cli with the caller: the three reviewer steps left, no HSTS"
else bad "--new cli with the caller: got"$'\n'"$out"; fi
# A `now:` row in the guide (a directory, not --new): a step whose doing is not read.
out="$("$script" cli "$work/p")"
if grep -qxF "to do, if not done yet (whether it is done is not read): ${on_repo#now: }" <<<"$out"
then ok "the guide says the now step as one to do if not done yet, not as started off"
else bad "the guide's now step: got"$'\n'"$out"; fi
rm "$work/p/.github/workflows/third-party.yml"
out="$("$script" --new web "$work/p")"
if [ "$out" = "$reviewer"$'\n'"$hsts" ]; then ok "--new without the caller: both off"; else bad "--new without the caller: got"$'\n'"$out"; fi
if "$script" --new web >/dev/null 2>&1; then bad "--new without a directory passed"; else ok "--new needs the project directory"; fi

# 5. Both callers read the list through the script, and name no item themselves.
for f in scripts/new-project.sh scripts/guide-state.sh; do
  if grep -q 'off-by-default.sh' "$root/$f" && ! grep -qiE 'third-party\.yml|HSTS' "$root/$f"
  then ok "$f calls the reader and names no item"; else bad "$f does not call scripts/off-by-default.sh, or names an item itself"; fi
done

# 5b. The sorting rule is written once, in the list's page, and both skills
#     point to it by its heading (#772).
if grep -qx '## How an item is sorted' "$root/docs/reference/off-by-default.md"
then ok "the list's page carries the sorting rule"; else bad "docs/reference/off-by-default.md has no '## How an item is sorted'"; fi
for f in skills/new-project/SKILL.md skills/guide/SKILL.md; do
  if grep -q 'How an item' "$root/$f" && grep -q 'off-by-default.md' "$root/$f"
  then ok "$f points to the sorting rule"; else bad "$f does not point to 'How an item is sorted'"; fi
done

# 6. A project-file phrase is in the template at the pinned tag.
template="${TEMPLATE_REPO:-coolbress/plinth-template}"
ref="${TEMPLATE_REF:-$(sed -n 's/^template_ref="\(.*\)"$/\1/p' "$root/scripts/new-project.sh")}"
while IFS=$'\t' read -r file phrase; do
  [ -n "$file" ] || continue
  body="$(curl -fsSL --retry 3 "https://raw.githubusercontent.com/$template/$ref/template/$file.jinja" 2>/dev/null ||
          curl -fsSL --retry 3 "https://raw.githubusercontent.com/$template/$ref/template/$file" 2>/dev/null)"
  if [ -z "$body" ]; then bad "could not read $file in $template@$ref; cannot verify \"$phrase\""
  elif grep -qF "$phrase" <<<"$body"; then ok "$template@$ref $file contains \"$phrase\""
  else bad "$template@$ref $file does not contain \"$phrase\""; fi
done < <("$script" --project-phrases)
[ -n "$("$script" --project-phrases)" ] || bad "--project-phrases printed nothing; the list has a project-file item"

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
