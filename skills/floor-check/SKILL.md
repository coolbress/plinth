---
name: floor-check
description: Read-only check of an existing repository against the plinth floor (the document set, agent settings, lockfile, container image, the live ruleset) plus what this machine's Claude Code settings say about the sandbox. Reports what is missing as a list with one fix per item and never changes anything. Use when the user asks whether a repository is set up, protected, "has the floor", or what /plinth:new-project would have given it.
argument-hint: "[owner/name]"
disallowed-tools: Edit, Write, NotebookEdit
---

# Floor check

**Read-only.** Do not fix anything in this session, and do not run anything
that writes: it changes no file and no setting. Every `gh api`, `glab api`,
`with-admin-token.sh`, `claude plugin update` or settings line the report
prints is the person's to run; give it to them as printed and never run it.

Runs the same checker that `ci / floor-check` runs in CI, from the same file.
Token, network and inputs can still make the two results differ.

## Run

From the repository root (the current directory). The repository on GitHub is
the argument if the user gave one (`$ARGUMENTS`), otherwise the remote:

```bash
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)"   # or the argument
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/floor-check.py" --root . --sandbox --plugins --credentials \
  --ruleset "${CLAUDE_PLUGIN_ROOT}/ruleset.json" --merge-ruleset "${CLAUDE_PLUGIN_ROOT}/ruleset-merge.json" \
  ${repo:+--repo} ${repo:+"$repo"} --format json \
  | python3 "${CLAUDE_PLUGIN_ROOT}/scripts/floor-report.py" --root .
```

The first command reads the repository; the second turns what it read into
the short report below and keeps the last run in one note on this machine
(`~/.cache/plinth/<host>-<owner>-<repo>/floor.json`), written only from a run
on the default branch with a clean working tree, so a later run says what
changed. Nothing is written in the repository.

Without a repository name the checker says `no --repo: wall not checked` and
checks only the files. It reads the GitHub API through `gh` with the user's
own login, so bypass actors are visible; without a login they show as SKIP.
`--ruleset` expects the wall `/plinth:new-project` raises; for a repository
with a different wall (plinth itself, for one) pass
`--expect-checks "<name>, <name>"` as well. Add `--project <dir>` when the
project is not at the repository root (the directory the repository's own CI
gives `python-ci.yml` as its `working-directory`); without it `pyproject.toml`
and `uv.lock` are read from the root and reported missing. Never pass
`--actions-token` here: it is `ci / floor-check`'s flag, and it turns the
reads only this skill can make into INFO lines.

What the machine's items say, and what to do with them:

- **`--sandbox`.** Claude Code's sandbox is an INFO, never a PASS, or a SKIP
  ending `[cannot be read here]` when the settings do not record it. Relay
  the INFO lines under it as they are, and do not tell the user to turn the
  sandbox on or off.
- **`--plugins`.** A plugin behind the commit its marketplace entry pins is a
  WARN with the one `claude plugin update` line that moves it. A SKIP there
  is not "up to date": never say so.
- **`--credentials`.** What can push besides the agent's token, the scopes of
  the active login, and a production database URL within the agent's reach,
  each a WARN naming where, never the value. Relay the WARN lines with the
  fix from `${CLAUDE_PLUGIN_ROOT}/docs/how-to/give-the-agent-a-token.md`;
  never run a logout, delete a credential, or remove a line or a variable.
  Finding none is an INFO, best effort: never tell the user the machine is
  clean.
- **`--merge-ruleset`.** A WARN when no ruleset reserves the merge names
  `scripts/create-merge-ruleset.sh`, which needs repository administration:
  give it to the user. The line starting `the merge:` says whether "merge on
  your word" is guidance (an INFO: the agent could merge and is only asked
  to wait) or a boundary (a PASS: GitHub refuses the agent's merge); put it
  in the summary in those plain words. Guidance is a setup, not a defect:
  leave it out of the FAIL and WARN list. The way to a boundary is
  `${CLAUDE_PLUGIN_ROOT}/docs/how-to/give-the-agent-its-own-account.md`, for
  the user to do.

## A GitLab checkout

A checkout rendered with `host: gitlab` (its `.copier-answers.yml` says so,
or pass `--host gitlab`) is read as a GitLab project. When `origin` is on
gitlab.com, run this instead of the command above, with the project's path
(`group/name`) as `--repo`, or the argument if the user gave one:

```bash
repo="$(git remote get-url origin 2>/dev/null | sed -nE 's#^(https://gitlab\.com/|git@gitlab\.com:)(.+)$#\2#p' | sed 's#\.git$##')"
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/floor-check.py" --root . --host gitlab --sandbox --plugins --credentials ${repo:+--repo} ${repo:+"$repo"} --format json \
  | python3 "${CLAUDE_PLUGIN_ROOT}/scripts/floor-report.py" --root .
```

The wall is read through `glab api` with the user's own login; reading the
protection needs the Maintainer role, and without it, or without `glab`, the
wall is a SKIP. A FAIL in the wall carries its fix as a `glab api` line or a
settings URL; it needs the Maintainer role, so give it to the user to run.

## A JavaScript or TypeScript repository

A GitHub repository with `package.json` and no `pyproject.toml` where the
project is read is a JavaScript or TypeScript project. Run the same command.
The first line under the header is an INFO saying plinth has no checks for
that language; the checks that do not depend on it keep their verdicts.
Each item that depends on Python is an `N/A` line saying `does not apply` and
why; the summary counts them on their own, `K do not apply`.

## Report

Give the person the report `floor-report.py` printed, in their language, line
for line and in its order: keep its numbers, file names and commands as
printed, add no line, and drop none. It is already the short form:

- the first line is the verdict;
- at most five action rows, those that cannot be undone or reach others
  first, each one of three kinds: do it yourself (outside the repository,
  the admin token, this machine); I can do it in one pull request (every file
  item in one row, except one a pull request cannot undo, such as a tracked
  secret, which has its own row and its lines); later, after what it names. A decision the person must
  make is a question inside the row it gates, not a fourth kind;
- one line naming every other finding;
- what changed since the last run, when there is a note: fixed, still
  missing, new;
- what could not be read, which is not a failure, and what would read it;
- what was not checked, which is not a problem;
- the passes as one line;
- one question, last. End with it: ask nothing else.

Do not write a check's id (`FC-…`) in the chat.

When the person asks to see everything, or for one area
(`floor-check wall`, `floor-check machine`), run the same command with
`--all`, or `--area <area>`, after `floor-report.py`, and give that output
whole. `floor-check machine` is also where the sandbox's lines are: relay them
as they are, and do not tell the person to turn the sandbox on or off.

The hand-off of each row, as the registry names it:

| Registry `handoff` | Row |
| --- | --- |
| `agent` | I can do it in one pull request |
| `person` | Do it yourself |
| `admin` | Do it yourself (the admin token) |
| `ci` | Later, after the next `ci / floor-check` run on the default branch |

A command in a "do it yourself" row is the person's: relay it as printed.
Ruleset fixes and every `gh api -X` call under a repository setting (push
protection, the Actions allowlist, private vulnerability reporting, the
Actions token, the tag ruleset) need repository administration: they go
through `${CLAUDE_PLUGIN_ROOT}/scripts/with-admin-token.sh` (spell out the
plugin root path) when the user's login cannot administer the repository.
Tell the user to run that line in a separate terminal window, not with `!`:
`!` runs it without a terminal, so the token prompt gets nothing. Never run
it.

An INFO naming a product the plan lacks (GitHub Code Security or Secret
Protection on a private repository) is a fact about the plan: buying it is the
user's choice, never a step to run or to recommend as a repair.

When the report says the check stopped early, say so first: what it read
before stopping is all there is, and the rest was not checked.

Do not fix anything in this session, and do not run anything that writes.

## What each item reads

`${CLAUDE_PLUGIN_ROOT}/skills/floor-check/reference.md` says, item by item,
what the checker reads and what it does not, and why each verdict is worded
as it is. The report does not need it: open it only when the person asks why
an item says what it says, or what a check covers.
