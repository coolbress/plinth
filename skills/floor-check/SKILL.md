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
  ${repo:+--repo} ${repo:+"$repo"}
```

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
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/floor-check.py" --root . --host gitlab --sandbox --plugins --credentials ${repo:+--repo} ${repo:+"$repo"}
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

An item the run could not read is a SKIP line, never a PASS.

Lead with a summary in plain words, for a person who may not know the
checker's terms yet. It comes before the checker's output and replaces none
of it:

1. How many items fail and how many were not verified, the two numbers on
   the checker's last line, which starts `-- N failed, M not verified`, and
   how many WARN lines there are. With no FAIL, say that no check failed in
   what was verified, and that the not-verified count is what could not be
   verified, whether or not the checker read it. When the line goes on
   `(K cannot be read here)`, say how many of the M the person can clear
   (M minus K) before the K that stay; never present the M as M problems.
2. For each FAIL, one plain sentence on what it means for the person: what
   can happen to their project or their merge while it stays, not what the
   checker compared. For example, "a pull request can merge without the
   secret scan running" rather than "required checks dropped".
3. Which one to fix first, and why: the one that lets a change reach `main`
   unchecked or reach other people comes before a missing document. With no
   FAIL, name the WARN to look at first, or say there is none.

Then give the checker's output whole. Do not summarise it, shorten it, or
drop PASS lines; the user reasons from the text they receive, and a FAIL you
paraphrased is a FAIL they cannot hand to an agent. The summary above is the
only paraphrase, and it says what a FAIL means, never that one is fixed.

After the output, list every FAIL and WARN line again as a bulleted list, and
under each one write one line that fixes it: a command, or a file and what to
put in it. Nothing else under the item. The user pastes that line to an agent
as is.

```text
- FAIL  CHANGELOG.md missing or empty
  Create CHANGELOG.md in the Keep a Changelog format with an Unreleased section.
- FAIL  main: required checks dropped: ['ci / secrets']
  ${CLAUDE_PLUGIN_ROOT}/scripts/with-admin-token.sh ${CLAUDE_PLUGIN_ROOT}/scripts/upgrade-ruleset.sh owner/name 'ci / secrets:15368'
```

Ruleset fixes need repository administration, so they go through
`with-admin-token.sh` (spell out the plugin root path); tell the user to run
that line in a separate terminal window, not with `!`: `!` runs it without a
terminal, so the token prompt gets nothing. Never run it. The same holds for
every `gh api -X` call printed under a repository setting (push protection,
the Actions allowlist, private vulnerability reporting, the Actions token, the
tag ruleset): relay it as printed, behind `with-admin-token.sh` in a separate
terminal when the user's login cannot administer the repository.

An INFO naming a product the plan lacks (GitHub Code Security or Secret
Protection on a private repository) is a fact about the plan: buying it is the
user's choice, never a step to run or to recommend as a repair.

INFO lines are facts, not defects; leave them where they are. INFO lines
indented under a FAIL or WARN are the exception: they belong to that finding
and carry its repair or what the repair needs (a command, a URL, the change it
brings), so write the fix line under that item from them. SKIP lines are
what the run could not check (offline, no `--repo`, an API error, a token
that does not see the item); the summary counts them as `N not verified`.
After the FAIL and WARN list, name what was not verified in one line, and
what would verify it (a network, a login, an admin-read token): the SKIPs
without the mark first, since the person can clear them. Then say in one line
that the SKIPs ending `[cannot be read here]` cannot be read from this machine
or repository whatever is changed there, and name what stands in for each
where its line names it (`ci / secrets` for push protection, `ci / lint`'s
security rules for CodeQL). Three kinds carry the mark: SSH keys (the
account's settings say which push), the sandbox while Claude Code does not
record its state, and a GitHub status a private repository's plan does not
expose to its administrator (push protection, the CodeQL rule, the CodeQL
default setup languages). That last kind is marked only when the token is
shown to read an admin-only setting (the Actions permissions) and the
security settings still come back empty: GitHub answers a fine-grained token
without the Administration permission the same way, which is how the agent
works after the first merge. Without that proof the SKIPs stay plain, with an
INFO under them saying to run this again with a token that has
Administration; relay that as a SKIP the person can clear. They stay listed, so the person knows what was not checked; they are counted
inside M, never as a PASS. An exit code
of 1 means at least one FAIL; 0 means no FAIL in what was checked, and the
not-verified count says what was not.
`N/A` lines (a JavaScript or TypeScript repository, above) are not defects
either: leave them out of the FAIL and WARN list, write no fix under them, and
in the summary say that plinth has no checks for that language rather than
that those items pass.
A third count, `K left to /plinth:floor-check`, appears only in a run with
`--actions-token` (`ci / floor-check`) and only when K is above 0: INFO
lines for reads that token cannot make and this skill, run with a login that
administers the repository, does (push protection, private vulnerability
reporting, the Actions allowlist, the Actions token settings, the ruleset's bypass actors, the CodeQL default setup languages, the squash commit settings, and
a private repository's missing CodeQL rule). In that job's summary their
`not yet confirmed` lines end `; left to /plinth:floor-check` and are not
annotated; the other `not yet confirmed` lines are. This skill's own run
never prints the count; without the flag those reads are SKIPs.

Do not fix anything in this session, and do not run anything that writes.

End the report with one line in the person's language: try typing
`/plinth:guide`; it names in plain words the one command to type next, then
what is open and what happened so far, and, before the first merge, how to
use the tools of that step and the next; `/plinth:guide map` shows the whole
way on one screen, and `/plinth:guide map <step>` one step in depth. On a repository plinth did not make,
it points back here.

## What each item reads

`${CLAUDE_PLUGIN_ROOT}/skills/floor-check/reference.md` says, item by item,
what the checker reads and what it does not, and why each verdict is worded
as it is. The report does not need it: open it only when the person asks why
an item says what it says, or what a check covers.
