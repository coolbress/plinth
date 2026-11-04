#!/usr/bin/env bash
# plinth is not rendered from the template, so a template update never reaches
# its own rules (#819). Each rule plinth shares with the template's AGENTS.md
# and pull-request form is a named phrase below: the phrase must be in the
# template at the tag scripts/new-project.sh pins, and its counterpart in
# plinth's file. Not a file comparison: most of each file is its own. A pin
# raise that rewords or drops a listed rule fails here; whoever raises the pin
# adds the rule to plinth, or writes `differs: <why>` as the counterpart.
# A rule the template adds that is not listed is not caught: list it when the
# pin raise brings it. Reads the template over the network; unreadable is a
# FAIL. The must-not-pass cases run first.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template="${TEMPLATE_REPO:-coolbress/plinth-template}"
ref="${TEMPLATE_REF:-$(sed -n 's/^template_ref="\(.*\)"$/\1/p' "$root/scripts/new-project.sh")}"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

# name | template file | phrase in the template | plinth file | its counterpart
# (fixed strings). Template files: agents = template/AGENTS.md.jinja,
# form = template/.github/PULL_REQUEST_TEMPLATE.md. Plinth files are paths.
rules=(
  "fresh-context default|agents|The default review is a fresh-context review, before the description is written|AGENTS.md|The default review is a fresh-context review, before the description is written"
  "fresh-context reads the review rules|agents|Read by the fresh-context review|AGENTS.md|Read by the fresh-context review"
  "term table|agents|add its plain explanation once, in their language, and keep the English term in brackets|AGENTS.md|add its plain explanation once, in their language, and keep the English term in brackets"
  "record ending|agents|ends in \`## Decision\` instead|AGENTS.md|a record ends in \`## Decision\`"
  "checked-myself field|form|## What I checked myself|.github/PULL_REQUEST_TEMPLATE.md|## What I checked myself"
  "review field|form|Review: <!-- which review ran: fresh-context \| third-party (<name>) \| same-session (not independent) \| none (<reason>) -->|.github/PULL_REQUEST_TEMPLATE.md|Review: <!-- which review ran: fresh-context \| third-party (<name>) \| same-session (not independent) \| none (<reason>) -->"
)

# has <file> <phrase>: the phrase is in the file, line breaks and runs of
# spaces read as one space, so rewrapping a paragraph does not break a match.
has() { [ -r "$1" ] && tr '\n' ' ' <"$1" | tr -s ' ' | grep -qF -- "$2"; }

# check_rules <template dir> <plinth dir>: one line per broken rule; returns 1 if any.
check_rules() {
  local tdir="$1" pdir="$2" entry name tfile tphrase pfile pphrase rc=0
  for entry in "${rules[@]}"; do
    entry="${entry//\\|/$'\x1f'}"
    IFS='|' read -r name tfile tphrase pfile pphrase <<<"$entry"
    tphrase="${tphrase//$'\x1f'/|}"; pphrase="${pphrase//$'\x1f'/|}"
    if ! has "$tdir/$tfile" "$tphrase"; then
      echo "$name: the template no longer has \"$tphrase\"; update this entry"; rc=1; continue
    fi
    case "$pphrase" in differs:*) continue ;; esac
    has "$pdir/$pfile" "$pphrase" || { echo "$name: $pfile lacks \"$pphrase\""; rc=1; }
  done
  return $rc
}

# Must not pass: a plinth file missing one rule, and a template missing one.
mkdir -p "$work/t" "$work/p/.github"
for entry in "${rules[@]}"; do
  entry="${entry//\\|/$'\x1f'}"
  IFS='|' read -r _ tfile tphrase pfile pphrase <<<"$entry"
  printf '%s\n' "${tphrase//$'\x1f'/|}" >>"$work/t/$tfile"
  printf '%s\n' "${pphrase//$'\x1f'/|}" >>"$work/p/$pfile"
done
if check_rules "$work/t" "$work/p" >/dev/null; then ok "a fixture carrying every rule passes"
else bad "a fixture carrying every rule fails: $(check_rules "$work/t" "$work/p")"; fi
cp -R "$work/p" "$work/p2"; grep -vF 'Read by the fresh-context review' "$work/p/AGENTS.md" >"$work/p2/AGENTS.md"
if out="$(check_rules "$work/t" "$work/p2")"; then bad "a plinth file missing a rule passes"
else ok "a plinth file missing a rule fails ($out)"; fi
cp -R "$work/t" "$work/t2"; grep -vF 'What I checked myself' "$work/t/form" >"$work/t2/form"
if out="$(check_rules "$work/t2" "$work/p")"; then bad "a template that dropped a listed rule passes"
else ok "a template that dropped a listed rule fails ($out)"; fi

# The real files: the template at the pinned tag against plinth's own.
mkdir -p "$work/real"
base="https://raw.githubusercontent.com/$template/$ref/template"
if curl -fsSL --retry 3 -o "$work/real/agents" "$base/AGENTS.md.jinja" 2>/dev/null \
   && curl -fsSL --retry 3 -o "$work/real/form" "$base/.github/PULL_REQUEST_TEMPLATE.md" 2>/dev/null \
   && [ -s "$work/real/agents" ] && [ -s "$work/real/form" ]; then
  if out="$(check_rules "$work/real" "$root")"
  then ok "plinth's CLAUDE.md and pull-request template carry each rule shared with $template@$ref (${#rules[@]} listed)"
  else bad "rules shared with $template@$ref missing or stale:"; sed 's/^/        /' <<<"$out"; fi
else
  bad "could not read $template@$ref AGENTS.md.jinja and the pull-request form; cannot verify"
fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
