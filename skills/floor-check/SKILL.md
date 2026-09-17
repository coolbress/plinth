---
name: floor-check
description: Read-only check of an existing repository against the plinth floor (the document set, agent settings, lockfile, container image, the live ruleset) plus the sandbox state of this machine. Reports what is missing as a list with one fix per item and never changes anything. Use when the user asks whether a repository is set up, protected, "has the floor", or what /plinth:new-project would have given it.
argument-hint: "[owner/name]"
disallowed-tools: Edit, Write, NotebookEdit
---

# Floor check

Runs the same checker that `ci / floor-check` runs in CI, from the same file.
Token, network and inputs can still make the two results differ: an item the
run could not read is a SKIP line, never a PASS. Read-only: it changes no
file and no setting.

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
own login, so bypass actors are visible; without a login they show as SKIP.
`--sandbox` adds the one item that belongs to this machine, not the
repository: whether Claude Code's sandbox is on. `--ruleset` expects the wall
`/plinth:new-project` raises, the CodeQL alert thresholds of its
`code_scanning` rule included; for a repository with a different wall (plinth
itself, for one) pass `--expect-checks "<name>, <name>"` as well.

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
`with-admin-token.sh` (spell out the plugin root path); tell the user to run
that line in a separate terminal window, not with `!`: `!` runs it without a
terminal, so the token prompt gets nothing. Never run it.

INFO lines are facts, not defects; leave them where they are. SKIP lines are
what the run could not check (offline, no `--repo`, an API error, a token
that does not see the item); the summary counts them as `N not verified`.
After the FAIL and WARN list, name what was not verified in one line, and
what would verify it (a network, a login, an admin-read token). An exit code
of 1 means at least one FAIL; 0 means no FAIL in what was checked, and the
not-verified count says what was not. In consumer CI that count is not 0:
the bypass-actor read needs an admin-read token the Actions token never is.

## What three of the checks read, and what they do not

Three checks are static reads with a stated scope (#95, the predicates #42
left open). A finding from any of them is a WARN, never a FAIL, so a
repository that passed before they existed still passes; a PASS from them
covers only what is listed here.

| Check | Reads | Does not read |
| --- | --- | --- |
| Tracked dotenv | `git ls-files` under `--root`: a tracked file named `.env` or `.env.<anything>`, except `.env.example`, `.env.sample`, `.env.template` | File contents, git history, an untracked local `.env` (not the defect), `.envrc`, other names such as `prod.env`. It is not a secret scanner; `ci / secrets` is. Outside a git work tree it is a SKIP |
| Action pins | Every `uses:` line in `.github/workflows/*.yml` and `*.yaml`: `owner/repo@<40-hex SHA>`, `docker://…@sha256:<digest>` or a local `./` path. Comments and block scalars (`run: \|`) are skipped | Composite actions under `.github/actions`, whether the SHA exists upstream, what the pinned action itself calls. A `uses` written in a form the line pattern cannot read (flow style, a quoted or explicit `?` key) is a SKIP naming the line |
| JSON logs | For a service archetype (`backend`, `data-ml`), the Python under `src/`: a `logging.Formatter` subclass that calls `json.dumps`, structlog's `JSONRenderer`, python-json-logger, or loguru with `serialize=True`; comments are ignored, string literals are not | Anything at run time: the application is never started, so the PASS line says "static hint", not proof of what the process prints. Logging it does not recognise is a SKIP; only a source tree with no logging at all is a WARN. Other archetypes are not asked |

Do not fix anything in this session, and do not run anything that writes.
