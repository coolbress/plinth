---
name: floor-check
description: Read-only check of an existing repository against the plinth floor (the document set, agent settings, lockfile, container image, the live ruleset) plus the sandbox state of this machine. Reports what is missing as a list with one fix per item and never changes anything. Use when the user asks whether a repository is set up, protected, "has the floor", or what /plinth:new-project would have given it.
argument-hint: "[owner/name]"
disallowed-tools: Edit, Write, NotebookEdit
---

# Floor check

Runs the same checker that `ci / floor-check` runs in CI, from the same file,
so the two can never disagree. Read-only: it changes no file and no setting.

## Run

From the repository root (the current directory). The repository on GitHub is
the argument if the user gave one (`$ARGUMENTS`), otherwise the remote:

```bash
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)"   # or the argument
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/floor-check.py" --root . --sandbox \
  --ruleset "${CLAUDE_PLUGIN_ROOT}/ruleset.json" ${repo:+--repo "$repo"}
```

Without a repository name the checker says `no --repo: wall not checked` and
checks only the files. It reads the GitHub API through `gh` with the user's
own login, so bypass actors are visible; without a login they show as INFO.
`--sandbox` adds the one item that belongs to this machine, not the
repository: whether Claude Code's sandbox is on. `--ruleset` expects the wall
`/plinth:new-project` raises; for a repository with a different wall (plinth
itself, for one) pass `--expect-checks "<name>, <name>"` instead.

## Report

Give the checker's output whole. Do not summarise it, shorten it, or drop
PASS lines; the user reasons from the text they receive, and a FAIL you
paraphrased is a FAIL they cannot hand to an agent.

After the output, list every FAIL and WARN line again as a bulleted list, and
under each one write one line that fixes it: a command, or a file and what to
put in it. Nothing else under the item. The user pastes that line to an agent
as is.

```text
- FAIL  CHANGELOG.md missing or empty
  Create CHANGELOG.md in the Keep a Changelog format with an Unreleased section.
- FAIL  main: required checks dropped: ['ci / secrets']
  ${CLAUDE_PLUGIN_ROOT}/scripts/with-admin-token.sh ${CLAUDE_PLUGIN_ROOT}/scripts/upgrade-ruleset.sh owner/name 'ci / secrets:15368'
- WARN  sandbox off in ~/.claude/settings.json: ...
  Run /sandbox once in Claude Code.
```

Ruleset fixes need repository administration, so they go through
`with-admin-token.sh` (spell out the plugin root path); tell the user to type
that line themselves, prefixed with `!`. Never run it.

INFO lines are facts, not defects; leave them where they are. An exit code of
1 means at least one FAIL; 0 means the floor is intact.

Do not fix anything in this session, and do not run anything that writes.
