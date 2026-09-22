#!/usr/bin/env bash
# The `## Run` block of skills/floor-check/SKILL.md hands the checker the same
# arguments under bash and zsh. Offline.
#
# The agent runs that block in whatever shell the machine has, and zsh does not
# split an unquoted expansion into words: `${repo:+--repo "$repo"}` arrived as
# the single argument `--repo o/r`, so the wall was never checked (#241). The
# block is read out of SKILL.md, not copied here, so a test cannot pass a stale
# copy. `gh` and `python3` are stubs on PATH: `gh` answers the repository name,
# `python3` prints each argument it was given on its own line.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skill="$root/skills/floor-check/SKILL.md"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
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
printf '#!/bin/sh\nfor a in "$@"; do printf "[%%s]\\n" "$a"; done\n' > "$work/bin/python3"
chmod +x "$work/bin/gh" "$work/bin/python3"

base="[/plugin/scripts/floor-check.py]
[--root]
[.]
[--sandbox]
[--ruleset]
[/plugin/ruleset.json]"

for sh in bash zsh; do
  # A missing shell is a failure, not a skip: a skipped zsh is today's bug unseen.
  if ! command -v "$sh" >/dev/null; then bad "$sh is not installed, so the block was not run under it"; continue; fi
  for repo in o/r ""; do
    got="$(cd "$work" && PATH="$work/bin:$PATH" CLAUDE_PLUGIN_ROOT=/plugin STUB_REPO="$repo" "$sh" -c "$block" 2>&1)"
    if [ -n "$repo" ]; then want="$base"$'\n'"[--repo]"$'\n'"[$repo]"; what="repo=$repo: --repo and the value as two arguments"
    else want="$base"; what="repo empty: neither --repo nor a value"; fi
    if [ "$got" = "$want" ]; then ok "$sh, $what"
    else bad "$sh, $what; got:"; sed 's/^/        /' <<<"$got"; fi
  done
done

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
