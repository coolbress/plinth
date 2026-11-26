#!/usr/bin/env bash
# `new-project.sh --where` reads the folder /plinth:new-project starts in, from
# local state only, and prints one `folder:` line (plus `toplevel:` inside a
# repository), so the skill can offer the right path before its first question
# (#1121). Each state is a fixture folder; gh, glab, curl, wget and ssh on PATH
# are stubs that record a call, and every case checks that none was made.
# The skill's half (the folder question, its options, hand-offs printed and
# not run) is read from skills/new-project/ at the end.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
door="$root/scripts/new-project.sh"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

work="$(mktemp -d "${TMPDIR:-/tmp}/np-where.XXXXXX")" || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$work"' EXIT
work="$(cd "$work" && pwd -P)"
mkdir -p "$work/bin" "$work/home"
for t in gh glab curl wget ssh; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/calls.log"\nexit 1\n' "$t" "$work" > "$work/bin/$t"
  chmod +x "$work/bin/$t"
done
: > "$work/calls.log"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

# where <case> <folder> <expected folder: line> [<expected toplevel>]
where() {
  local name="$1" d="$2" want="$3" top="${4:-}" out rc
  out="$(cd "$d" && HOME="$work/home" PATH="$work/bin:$PATH" "$door" --where 2>&1)"; rc=$?
  if [ "$rc" != 0 ]; then bad "$name: exit $rc, not 0: $out"; return; fi
  if [ "$(grep -c '^folder: ' <<<"$out")" = 1 ] && grep -qxF "folder: $want" <<<"$out"; then ok "$name: folder: $want"
  else bad "$name: wanted \"folder: $want\", got:"; sed 's/^/        /' <<<"$out"; fi
  if [ -n "$top" ]; then
    if grep -qxF "toplevel: $top" <<<"$out"; then ok "$name: toplevel: $top"
    else bad "$name: wanted \"toplevel: $top\", got:"; sed 's/^/        /' <<<"$out"; fi
  elif grep -q '^toplevel:' <<<"$out"; then bad "$name: printed a toplevel outside a repository"; fi
  if [ -s "$work/calls.log" ]; then bad "$name: made a call it must not:"; sed 's/^/        /' "$work/calls.log"; : > "$work/calls.log"
  else ok "$name: no gh, glab, curl, wget or ssh call"; fi
}

repo() { # repo <dir> [<remote url>]: a repository with one commit, and origin when given
  mkdir -p "$1" && git -C "$1" init -q -b main && git -C "$1" commit -q --allow-empty -m init
  [ -z "${2:-}" ] || git -C "$1" remote add origin "$2"
}
answers() { # answers <dir> <src_path> <commit>
  printf '# Changes here will be overwritten by Copier\n_commit: %s\n_src_path: %s\narchetype: cli\n' "$3" "$2" > "$1/.copier-answers.yml"
}

echo "-- folders outside a repository"
mkdir -p "$work/empty"; where empty "$work/empty" empty
mkdir -p "$work/clutter/.claude" "$work/clutter/.vscode" "$work/clutter/.idea"
touch "$work/clutter/.DS_Store" "$work/clutter/Thumbs.db"
where only-ignored "$work/clutter" empty
mkdir -p "$work/onefile/.claude"; touch "$work/onefile/notes.txt"
where one-file "$work/onefile" files
mkdir -p "$work/hidden"; touch "$work/hidden/.env"
where hidden-file "$work/hidden" files
where home "$work/home" home

echo "-- repositories, by their remote"
repo "$work/noremote"; where git-no-remote "$work/noremote" git-no-remote "$work/noremote"
repo "$work/gh-https" https://github.com/octo/tool.git
where github-https "$work/gh-https" "git-remote github.com octo/tool" "$work/gh-https"
repo "$work/gh-ssh" git@github.com:Octo/Tool.git
where github-ssh "$work/gh-ssh" "git-remote github.com Octo/Tool" "$work/gh-ssh"
repo "$work/gl" ssh://git@gitlab.com/group/sub/proj.git
where gitlab-subgroup "$work/gl" "git-remote gitlab.com group/sub/proj" "$work/gl"
repo "$work/other" https://git.example.org/team/app.git
where other-host "$work/other" "git-remote-other git.example.org" "$work/other"
repo "$work/made" https://github.com/octo/made.git
answers "$work/made" gh:coolbress/plinth-template 0123abc
where plinth-made "$work/made" "plinth-made octo/made 0123abc" "$work/made"
repo "$work/made-local"; answers "$work/made-local" gh:coolbress/plinth-template 0123abc
where plinth-made-no-remote "$work/made-local" "plinth-made none 0123abc" "$work/made-local"
repo "$work/othertpl" https://github.com/octo/othertpl.git
answers "$work/othertpl" gh:someone/another-template 9999fff
where another-template "$work/othertpl" "git-remote github.com octo/othertpl" "$work/othertpl"

echo "-- from a subfolder, the enclosing state and its top folder"
for c in noremote:git-no-remote "gh-https:git-remote github.com octo/tool" \
         "other:git-remote-other git.example.org" "made:plinth-made octo/made 0123abc"; do
  d="${c%%:*}"; mkdir -p "$work/$d/src/deep"
  where "subfolder of $d" "$work/$d/src/deep" "${c#*:}" "$work/$d"
done

echo "-- a repository at the home folder (dotfiles) is not a project"
repo "$work/home" git@github.com:me/dotfiles.git
where home-is-a-repository "$work/home" home
mkdir -p "$work/home/newproj"; where empty-under-a-home-repository "$work/home/newproj" empty
touch "$work/home/newproj/x.txt"; where files-under-a-home-repository "$work/home/newproj" files
out="$(cd "$work/empty" && env -u HOME PATH="$work/bin:$PATH" "$door" --where 2>&1)"
if [ "$out" = "folder: empty" ]; then ok "no HOME: folder: empty, and nothing on stderr"
else bad "no HOME: wanted only \"folder: empty\", got:"; sed 's/^/        /' <<<"$out"; fi

echo "-- made by plinth: one test, shared with the guide"
for f in "$root/scripts/guide-state.sh" "$door"; do
  if grep -q 'scripts/lib/copier-answers.sh' "$f" && grep -q 'made_by_plinth ' "$f"; then ok "$(basename "$f") uses made_by_plinth from scripts/lib/copier-answers.sh"
  else bad "$(basename "$f") does not use made_by_plinth from scripts/lib/copier-answers.sh"; fi
  if grep -q '_src_path" *!\?= \|"\$src" != "gh:' "$f"; then bad "$(basename "$f") still compares _src_path itself"
  else ok "$(basename "$f") has no _src_path comparison of its own"; fi
done

echo "-- the skill: the folder first, hand-offs printed, never run"
skill="$root/skills/new-project/SKILL.md"; questions="$root/skills/new-project/questions.md"
both="$(cat "$skill" "$questions")"
flat="$(tr '\n' ' ' <<<"$both" | tr -s ' ')"
where_at="$(grep -nF 'new-project.sh --where' "$skill" | head -n 1 | cut -d: -f1)"
ready_at="$(grep -nF 'new-project.sh --readiness' "$skill" | head -n 1 | cut -d: -f1)"
if [ -n "$where_at" ] && [ -n "$ready_at" ] && [ "$where_at" -lt "$ready_at" ]; then ok "SKILL.md runs --where before --readiness"
else bad "SKILL.md: --where at line ${where_at:-none}, --readiness at ${ready_at:-none}"; fi
fq_at="$(grep -n '^## 0\. The folder' "$questions" | cut -d: -f1)"
host_at="$(grep -n '^## 1\. The host' "$questions" | cut -d: -f1)"
if [ -n "$fq_at" ] && [ -n "$host_at" ] && [ "$fq_at" -lt "$host_at" ]; then ok "questions.md asks the folder (0) before the host (1)"
else bad "questions.md: the folder section at ${fq_at:-none}, the host at ${host_at:-none}"; fi
for p in '`files`' '`git-no-remote`' '`git-remote <host>' '`git-remote-other <host>' '`plinth-made <path>' \
         'New separate project (Recommended)' 'Check it and add plinth' 'Next step in this project' 'Cancel' \
         '/plinth:floor-check' '/plinth:guide' 'gh repo create' '--source=' 'glab repo create' \
         'For `empty` or `home`' 'a name argument or `--dir=`' 'no folder question' \
         'runs no preflight' 'print the command' 'never run it yourself' 'never call the Skill tool' \
         'every hand-off is run from its top folder' 'print `cd <top folder>` first' \
         'ends as Cancel' 'naming the top folder' 'only once the folder step goes on to the host' \
         'open a new session there'; do
  if grep -qF -- "$p" <<<"$flat"; then ok "the skill says \"$p\""; else bad "the skill does not say \"$p\""; fi
done

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
