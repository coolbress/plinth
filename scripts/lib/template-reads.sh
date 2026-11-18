# shellcheck shell=bash disable=SC2034  # template_reads* and template_changed are read by the scripts that source this file
# What a template pin move changes for a new project's agent (#700, #954).
# Sourced by scripts/make-release.sh, which asks for the eval suite from it,
# and by scripts/raise-template-pin.sh, which says ahead of the release what
# that run 1 will ask: one reading, so the two cannot answer differently.

# released_template_ref <CHANGELOG.md> <version> <template name>: the tag the
# `## [<version>]` section's `tested with <name> <tag>` line names, or nothing.
released_template_ref() {
  python3 - "$1" "$2" "$3" <<'PY'
import re, sys
text, ver, name = open(sys.argv[1]).read(), sys.argv[2], sys.argv[3]
m = re.search(r"^## \[" + re.escape(ver) + r"\][^\n]*\n(.*?)(?=^## \[|^\[Unreleased\]: |\Z)", text, re.M | re.S)
t = m and re.search(r"^tested with " + re.escape(name) + r" (\S+)$", m[1], re.M)
print(t[1] if t else "")
PY
}

# template_agent_reads <repo> <from tag> <to tag>: sets template_reads to one
# line per file the template's diff between the two tags changes that a new
# project's agent reads (template/AGENTS.md.jinja, template/CLAUDE.md.jinja,
# anything under template/.claude/), renames' old names included, and to
# nothing when it touches none. Over 300 files GitHub cuts the list short, so
# a cut list is one line that says so. template_changed gets every changed
# file's name. A diff that cannot be read returns 1 with gh's answer in
# template_reads_error. Call it directly, not in $(...): it sets variables.
template_agent_reads() {
  local out
  template_reads="" template_changed="" template_reads_error=""
  out="$(gh api "repos/$1/compare/$2...$3" \
           --jq '(.files | length), (.files[] | .filename, (.previous_filename // empty))' 2>&1)" \
    || { template_reads_error="$out"; return 1; }
  template_changed="$(tail -n +2 <<<"$out")"
  template_reads="$(grep -E '^template/(AGENTS\.md\.jinja|CLAUDE\.md\.jinja|\.claude/)' <<<"$template_changed" | sort -u || true)"
  [ "$(head -1 <<<"$out")" -lt 300 ] || template_reads="(over 300 files changed; GitHub lists no more)"
}
