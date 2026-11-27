#!/usr/bin/env bash
# The `## Run` block of skills/floor-check/SKILL.md hands the checker the same
# arguments under bash and zsh. Offline.
#
# The agent runs that block in whatever shell the machine has, and zsh does not
# split an unquoted expansion into words: `${repo:+--repo "$repo"}` arrived as
# the single argument `--repo o/r`, so the wall was never checked (#241). The
# block is read out of SKILL.md, not copied here, so a test cannot pass a stale
# copy. `gh` and `python3` are stubs on PATH: `gh` answers the repository name,
# `python3` appends each argument it was given, one per line, to $CALLS, then
# a `--` line. The block is two calls joined by a pipe (#1105): the checker,
# with --format json, and scripts/floor-report.py reading its output.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skill="$root/skills/floor-check/SKILL.md"
work="$(mktemp -d)" || { echo "floor-check-run-block: could not make a temp folder" >&2; exit 1; }; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

# The first ```bash fence after `## Run`, without the fences.
block="$(awk '/^## Run$/{r=1; next} r && /^## /{exit} r && /^```bash$/{f=1; next} f && /^```$/{exit} f' "$skill")"
if ! grep -q 'floor-check.py' <<<"$block"; then
  echo "  FAIL  no \`\`\`bash block that runs floor-check.py under ## Run in $skill"; exit 1
fi

mkdir -p "$work/bin"
printf '#!/bin/sh\nprintf "%%s" "$STUB_REPO"\n' > "$work/bin/gh"
# Each call also logs what it read on stdin and prints "piped": the second
# call reads "piped" only through a pipe from the first.
printf '#!/bin/sh\nin="$(cat)"\nfor a in "$@"; do printf "[%%s]\\n" "$a" >> "$CALLS"; done\nprintf "stdin: %%s\\n--\\n" "$in" >> "$CALLS"\necho piped\n' > "$work/bin/python3"
chmod +x "$work/bin/gh" "$work/bin/python3"

base="[/plugin/scripts/floor-check.py]
[--root]
[.]
[--sandbox]
[--plugins]
[--credentials]
[--ruleset]
[/plugin/ruleset.json]
[--merge-ruleset]
[/plugin/ruleset-merge.json]"

for sh in bash zsh; do
  # A missing shell is a failure, not a skip: a skipped zsh is today's bug unseen.
  if ! command -v "$sh" >/dev/null; then bad "$sh is not installed, so the block was not run under it"; continue; fi
  for repo in o/r ""; do
    : > "$work/calls"
    (cd "$work" && PATH="$work/bin:$PATH" CLAUDE_PLUGIN_ROOT=/plugin STUB_REPO="$repo" CALLS="$work/calls" "$sh" -c "$block" </dev/null 2>&1)
    got="$(cat "$work/calls")"
    report=$'[/plugin/scripts/floor-report.py]\n[--root]\n[.]\nstdin: piped\n--'
    if [ -n "$repo" ]; then want="$base"$'\n'"[--repo]"$'\n'"[$repo]"$'\n[--format]\n[json]\nstdin: \n--\n'"$report"; what="repo=$repo: --repo and the value as two arguments, the JSON piped to the report"
    else want="$base"$'\n[--format]\n[json]\nstdin: \n--\n'"$report"; what="repo empty: neither --repo nor a value, the JSON piped to the report"; fi
    if [ "$got" = "$want" ]; then ok "$sh, $what"
    else bad "$sh, $what; got:"; sed 's/^/        /' <<<"$got"; fi
  done
done

# The read-only rule opens the skill (#1105): within its first 40 lines, the
# part of a long file Claude Code keeps after compacting a session, it says
# to change nothing and to run no command the report prints.
n="$(grep -n '^\*\*Read-only\.\*\*' "$skill" | head -1 | cut -d: -f1)"
rule="$(awk -v n="${n:-0}" 'NR >= n && n > 0 { print } NR > n && /^$/ { exit }' "$skill" | tr '\n' ' ')"
if [ -n "$n" ] && [ "$n" -le 40 ] && grep -qF 'do not run anything that writes' <<<"$rule" && grep -qF 'never run it' <<<"$rule"
then ok "the read-only rule is at line $n of SKILL.md, within the first 40"
else bad "no '**Read-only.**' paragraph within SKILL.md's first 40 lines that says not to write and never to run a printed command (found at line ${n:-none})"; fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
