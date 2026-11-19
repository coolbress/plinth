#!/usr/bin/env bash
# plinth is not rendered from the template, so a template update never reaches
# its own rules (#819). Each rule plinth shares with the template's AGENTS.md,
# CONTRIBUTING.md, pull-request form and issue tracker page is a named phrase below: the phrase must be in the
# template at the tag scripts/new-project.sh pins, and its counterpart in
# plinth's file. Not a file comparison: most of each file is its own. A pin
# raise that rewords or drops a listed rule fails here; whoever raises the pin
# adds the rule to plinth, or writes `differs: <why>` as the counterpart.
# A rule the template adds that is not listed is not caught: list it when the
# pin raise brings it. Reads the template from one checkout at the pinned
# commit (tests/lib/template-checkout.sh); none is a FAIL. The must-not-pass
# cases run first.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/template-checkout.sh
. "$root/tests/lib/template-checkout.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

# name | template file | phrase in the template | plinth file | its counterpart
# (fixed strings). Template files: agents = template/AGENTS.md.jinja,
# form = template/.github/PULL_REQUEST_TEMPLATE.md,
# contributing = template/CONTRIBUTING.md.jinja,
# tracker = template/docs/agents/issue-tracker.md.jinja. Plinth files are paths.
rules=(
  "fresh-context default|agents|The default review is a fresh-context review, before the description is written|AGENTS.md|The default review is a fresh-context review, before the description is written"
  "fresh-context reads the review rules|agents|Read by the fresh-context review|AGENTS.md|Read by the fresh-context review"
  "term table|agents|add its plain explanation once, in their language, and keep the English term in brackets|AGENTS.md|add its plain explanation once, in their language, and keep the English term in brackets"
  "record ending|agents|ends in \`## Decision\` instead|AGENTS.md|a record ends in \`## Decision\`"
  "checked-myself field|form|## What I checked myself|.github/PULL_REQUEST_TEMPLATE.md|## What I checked myself"
  "review field|form|Review: <!-- which review ran: fresh-context \| third-party (<name>) \| same-session (not independent) \| none (<reason>) -->|.github/PULL_REQUEST_TEMPLATE.md|Review: <!-- which review ran: fresh-context \| third-party (<name>) \| same-session (not independent) \| none (<reason>) -->"
  "another repository's reference|agents|A reference to another repository's issue or pull request is \`owner/repo#N\`; a bare \`#N\`, or \`plinth #N\`, links to this repository's own \`#N\`.|AGENTS.md|A reference to another repository's issue or pull request is \`owner/repo#N\`; a bare \`#N\`, or \`plinth #N\`, links to this repository's own \`#N\`."
  "another repository's reference in the form|form|Any reference to another repository's issue or pull request, here or above: \`owner/repo#N\`.|.github/PULL_REQUEST_TEMPLATE.md|Any reference to another repository's issue or pull request, here or above: \`owner/repo#N\`."
  "public records|agents|Write them as public: no home path, account or folder name from the person's computer|AGENTS.md|Write them as public: no home path, account or folder name from the owner's computer"
  "public records in the form|form|A pasted output keeps home paths out: \`~/...\`, or the condition it shows.|.github/PULL_REQUEST_TEMPLATE.md|A pasted output keeps home paths out: \`~/...\`, or the condition it shows."
  "squash-merge command|contributing|body=\"\$(gh pr view <n> --json body --jq .body)\" && gh pr merge <n> --squash --match-head-commit <sha> --body \"\$body\"|CONTRIBUTING.md|body=\"\$(gh pr view <n> --json body --jq .body)\" && gh pr merge <n> --squash --match-head-commit <sha> --body \"\$body\""
  "a defect is a bug|tracker|A defect is a \`bug\`, whoever finds it: a person who reports it, or an agent that reproduced it and can say what the fix must do.|docs/agents/issue-tracker.md|A defect is a \`bug\`, whoever finds it: a person who reports it, or an agent that reproduced it and can say what the fix must do."
  "a ready bug's criteria|tracker|A \`bug\` made \`ready-for-agent\` gains \`## Acceptance criteria\` (and \`## Not building\` when it helps) below the form's fields, in the same issue|docs/agents/issue-tracker.md|A \`bug\` made \`ready-for-agent\` gains \`## Acceptance criteria\` (and \`## Not building\` when it helps) below the form's fields, in the same issue"
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
mkdir -p "$work/t" "$work/p/.github" "$work/p/docs/agents"
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

# The real files: the template at the pinned commit against plinth's own.
if template_checkout "$work"; then
  mkdir -p "$work/real"; t="$template_dir/template"
  cp "$t/AGENTS.md.jinja" "$work/real/agents" 2>/dev/null; cp "$t/.github/PULL_REQUEST_TEMPLATE.md" "$work/real/form" 2>/dev/null
  cp "$t/CONTRIBUTING.md.jinja" "$work/real/contributing" 2>/dev/null
  cp "$t/docs/agents/issue-tracker.md.jinja" "$work/real/tracker" 2>/dev/null
  if [ -s "$work/real/agents" ] && [ -s "$work/real/form" ] && [ -s "$work/real/contributing" ] && [ -s "$work/real/tracker" ]; then
    if out="$(check_rules "$work/real" "$root")"
    then ok "plinth's CLAUDE.md, CONTRIBUTING.md, pull-request template and issue tracker page carry each rule shared with $template_at (${#rules[@]} listed)"
    else bad "rules shared with $template_at missing or stale:"; sed 's/^/        /' <<<"$out"; fi
  else
    bad "$template_at has no AGENTS.md.jinja, CONTRIBUTING.md.jinja, pull-request form or docs/agents/issue-tracker.md.jinja under template/; cannot verify"
  fi
else
  bad "no checkout of the template: $template_error"
fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
