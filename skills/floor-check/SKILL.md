---
name: floor-check
description: Read-only check of an existing repository against the plinth floor (the document set, agent settings, lockfile, container image, the live ruleset) plus what this machine's Claude Code settings say about the sandbox. Reports what is missing as a list with one fix per item and never changes anything. Use when the user asks whether a repository is set up, protected, "has the floor", or what /plinth:new-project would have given it.
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
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/floor-check.py" --root . --sandbox --credentials \
  --ruleset "${CLAUDE_PLUGIN_ROOT}/ruleset.json" ${repo:+--repo} ${repo:+"$repo"}
```

Without a repository name the checker says `no --repo: wall not checked` and
checks only the files. It reads the GitHub API through `gh` with the user's
own login, so bypass actors are visible; without a login they show as SKIP.
`--sandbox` adds the one item that belongs to this machine, not the
repository: Claude Code's sandbox. Only `sandbox.enabled: true` in the
user's settings is read, and it is an `INFO`, not a PASS. `/sandbox` on
Claude Code 2.1.278 does not write that key, so without it the item is not
verified (SKIP), not reported off. Either way the `INFO` lines under it say
what the sandbox closes and what it breaks, measured on macOS only: `gh`,
through the floor's own `Read(~/.config/gh/**)` deny, with no fix a
repository's settings can make (anthropics/claude-code#95135,
anthropics/claude-code#67105), and `/plinth:new-project`'s copier step.
Relay those lines as they are and do not tell the user to turn the sandbox
on or off; on Linux and WSL2 nothing was measured. This SKIP is one the
not-verified line below names without a way to verify it: nothing plinth
reads can.

`--credentials` adds the other item of this machine: what can push to
github.com besides the agent's token. It names `GH_TOKEN` or `GITHUB_TOKEN`
when set, counts the accounts `gh auth status` stores, and lists git
credential helpers for github.com other than gh's, an `Authorization`
`http.extraHeader`, and a github.com login in `~/.netrc`, each a WARN with no
value printed. Finding none is an INFO saying so, best effort, never a PASS:
a credential in a form the rules do not recognise is not reported, so do not
tell the user the machine is clean. `GH_CONFIG_DIR`, `XDG_CONFIG_HOME`, `GIT_CONFIG` or a `GIT_CONFIG_*`
variable, when set, is a SKIP naming it: the configuration it hides is not
read. SSH keys are a SKIP every time, the other one with no way to
verify it here: GitHub's settings say which keys push, not this machine.
Relay the WARN lines with the fix from
"Give the agent a token that cannot change the checks" in
`${CLAUDE_PLUGIN_ROOT}/docs/how-to/run-a-project.md`; never run a logout or
delete a credential yourself.

`--ruleset` expects the wall
`/plinth:new-project` raises, the CodeQL alert thresholds of its
`code_scanning` rule included; for a repository with a different wall (plinth
itself, for one) pass `--expect-checks "<name>, <name>"` as well. Add
`--project <dir>` when the project is not at the repository root — the
directory the repository's own CI gives `python-ci.yml` as its
`working-directory` — because without it `pyproject.toml` and `uv.lock` are
read from the root and reported missing although they exist one level down.

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
```

Ruleset fixes need repository administration, so they go through
`with-admin-token.sh` (spell out the plugin root path); tell the user to run
that line in a separate terminal window, not with `!`: `!` runs it without a
terminal, so the token prompt gets nothing. Never run it.

INFO lines are facts, not defects; leave them where they are. INFO lines
indented under a FAIL or WARN are the exception: they belong to that finding
and carry its repair or what the repair needs (a command, a URL, the change it
brings), so write the fix line under that item from them. SKIP lines are
what the run could not check (offline, no `--repo`, an API error, a token
that does not see the item); the summary counts them as `N not verified`.
After the FAIL and WARN list, name what was not verified in one line, and
what would verify it (a network, a login, an admin-read token). An exit code
of 1 means at least one FAIL; 0 means no FAIL in what was checked, and the
not-verified count says what was not.
A third count, `K left to /plinth:floor-check`, appears only in a run with
`--actions-token` (`ci / floor-check`) and only when K is above 0: INFO
lines for reads that token cannot make and this skill, run with a login that
administers the repository, does (push protection, the ruleset's bypass
actors, the CodeQL default setup languages, the squash commit settings, and
a private repository's missing CodeQL rule). In that job's summary their
`not yet confirmed` lines end `; left to /plinth:floor-check` and are not
annotated; the other `not yet confirmed` lines are. This skill's own run
never prints the count; without the flag those reads are SKIPs.

## What four of the checks read, and what they do not

Four checks are static reads with a stated scope (#95, the predicates #42
left open; the plinth pins, #447). A finding from any of them is a WARN, never a FAIL, so a
repository that passed before they existed still passes; a PASS from them
covers only what is listed here.

| Check | Reads | Does not read |
| --- | --- | --- |
| Tracked dotenv | `git ls-files` under `--root`: a tracked file named `.env` or `.env.<anything>`, except `.env.example`, `.env.sample`, `.env.template` | File contents, git history, an untracked local `.env` (not the defect), `.envrc`, other names such as `prod.env`. It is not a secret scanner; `ci / secrets` is. Outside a git work tree it is a SKIP |
| Action pins | Every `uses:` line in `.github/workflows/*.yml` and `*.yaml`: `owner/repo@<40-hex SHA>`, `docker://…@sha256:<digest>` or a local `./` path. Comments and block scalars (`run: \|`) are skipped | Composite actions under `.github/actions`, whether the SHA exists upstream, what the pinned action itself calls. A `uses` written in a form the line pattern cannot read (flow style, a quoted, anchored or explicit `?` key: any `uses` in key position that is not a plain `uses: value`) is a SKIP naming the line |
| Plinth pins agree | The same `uses:` lines as Action pins, those of `coolbress/plinth/...` at a full commit SHA: two or more SHAs across the files (`ci.yml` and `label.yml` are rendered at one commit; a hand edit moves one) are a WARN naming each file with its SHA, and the INFO under it is the `sed` line that moves each lagging file's plinth references, and nothing else in it, to the SHA the `ci` job calls. The owner, repository and SHA compare in any letter case, as GitHub reads them. One SHA, or none outside the `ci` job, prints nothing, whatever the template state | A plinth `uses:` on a tag or branch (the Action pins WARN, not repeated). A `uses` it cannot read is a SKIP naming the file and line, unless the readable ones already disagree. Not a FAIL: `label / label` is not a required check |
| JSON logs | For a service archetype (`backend`, `data-ml`), the Python under `src/`: a `logging.Formatter` subclass that calls `json.dumps`, structlog's `JSONRenderer`, python-json-logger, or loguru with `serialize=True`; comments are ignored, string literals are not | Anything at run time: the application is never started, so the PASS line says "static hint", not proof of what the process prints. Logging it does not recognise is a SKIP; only a source tree with no logging at all is a WARN. Other archetypes are not asked |

## The ci job

One item reads `.github/workflows/ci.yml` and asks whether its `ci` job still
calls `coolbress/plinth/.github/workflows/python-ci.yml` pinned to a full
commit SHA (#325). The `ci / <job>` check names come from that call; a pull
request that replaces it with plain jobs of the same names turns every
required check green without running them. With a repository name it reads
the file from the default branch through the API, not from the checkout, so
the answer is about what merged. Offline or without one it reads the
checkout and says so in the line. A `ci` job that is missing, runs its own
steps, calls another repository, a fork or a local file, pins a tag or a
branch, or carries any key but `uses:`, `with:`, `secrets:` and
`permissions:` (an `if:`, `needs:`, `name:` or `strategy:` can get it
skipped, renamed or cut short while plain jobs report its check names) is a
FAIL. The INFO line under it is a `gh api` command that prints
the SHA to pin: the pinned tag's or branch's commit, or otherwise the commit
of plinth's latest release. A file or job the line reader cannot
read is a SKIP: flow style, an anchor, an alias, a merge key, a
double-quoted key with an escape, or any top-level line that is not a plain or
quoted `key: …` (a tag, an explicit `?` key, a `---` marker that starts a
second document; one opening the file is read past). plinth itself
calls `./.github/workflows/plinth-ci.yml`, accepted for `coolbress/plinth`
only; no other local workflow is.

When the job calls plinth's workflow, the same item reads two values of its
`with:` block, the inputs that set how much a check holds (#435):
`max-diff-lines` of 0 or less (measured, never fails) or above plinth's default of
400, and `deps-fail-on-severity: critical` (plinth's default is `high`), are
each a WARN naming the input, its value and the default, on every run. A
project may choose the value; the line keeps the choice visible after the
pull request that set it. A stricter value or none prints nothing, and
neither WARN changes the exit code. A value it cannot read (an expression
such as `${{ vars.X }}`, a value continued on the next line, a limit that
is not a whole number, a severity spelled other than `critical`, `high`,
`moderate` or `low`) is a SKIP, and so is a `with:` line it cannot name (an
explicit `?` key, a merge key) or a second `with:` on the job. The
other inputs (`diff-size-exclude`, `extra-python-versions`,
`working-directory`) are not judged: no direction of "looser" is agreed for
them.

`ci / floor-check` runs the same item on the pull request's own `ci.yml`
(`--caller-from-checkout`): a pull request that keeps the call but weakens it
fails there, before the merge, and one that repairs a broken default branch
can merge. A pull request that removes the call removes `ci / floor-check`
with it, so that one is seen only after the merge, from outside the pull
request: here, run by a person, or by the e2e runner.

## Push protection

One item reads whether GitHub's push protection is on (#303): it refuses a
push that carries a secret in a format GitHub knows, where `ci / secrets`
reports one only after it is on GitHub. On is a PASS that says that much and
no more: the person pushing can let a secret through, and a format GitHub
does not know passes. Off is a WARN, never a FAIL, and the INFO line under it
is one `gh api` call that sends what the door sends. It needs repository
administration, and on a private repository GitHub Secret Protection too:
relay it as printed for the user to run, behind `with-admin-token.sh` in a
separate terminal when their login cannot administer the repository, and
never run it. The status
sits in the repository's security settings, which a token without repository
administration does not get: that is a SKIP, and so is a repository GitHub
reports no status for. `ci / floor-check` passes `--actions-token`, which
turns the first of those into an INFO, because the Actions token never gets
them and no consumer could clear that SKIP: this skill, with the user's
login, is the run that reads the item. Never pass that flag here.

## A private repository

A private repository's wall is read against what its licences allow (#351).
The `code_scanning` rule is expected only where GitHub Code Security is
enabled on the repository, and push protection only where GitHub Secret
Protection is: both are paid products for Team and Enterprise. Every other
item, the required check names first, is expected as on a public repository.

| The repository's security settings say | CodeQL rule missing | Push protection off |
| --- | --- | --- |
| The product is enabled | FAIL, as on a public repository | WARN with its call, as on a public repository |
| The product is disabled | INFO naming the gap; `ci / lint`'s security rules stand in its place | INFO naming the gap; `ci / secrets` stands in its place |
| No answer (a token without repository administration, or no status in the answer) | SKIP | SKIP |

The two gap lines are INFO at the normal indent: facts about the plan, not
defects. Leave them out of the FAIL and WARN list and write no fix under
them. They say where the product is turned on and that it may be billed;
that is the user's purchase to make, never a step to run or to recommend as
a repair. A SKIP here goes in the not-verified line with what verifies it,
which the line itself names: a login that administers the repository when
the token did not read the security settings; the repository's Settings >
Advanced Security page when GitHub gave no status for the product, because
no login changes that answer. What a private repository answers on each plan
is not measured yet (#352). `ci / floor-check` reads a private
repository with the Actions token, which never gets the security settings: a
missing rule is an INFO there, outside the not-verified count, saying the
licence state is judged when this skill is run with a login that administers
the repository. So a private repository that has Code Security and lost its
rule fails here and not in CI. Never pass `--actions-token` here.

## Template drift

One item compares the template tag this repository was rendered from
(`.copier-answers.yml`'s `_commit`) with the tag plinth is tested with today
(`scripts/new-project.sh`'s `template_ref`). Equal is a PASS, worded as
"the recorded tag is the target tag" and nothing more: it does not mean this
repository's own render matches the template file for file, only that it was
made from the current tag. Behind is a WARN, never a FAIL, naming both tags,
the template's own files that changed between them (one GitHub compare call,
and a diff of `AGENTS.md`, `CONTRIBUTING.md` and `.gitignore` if they are
among them — the template's own change, not necessarily this repository's:
another archetype, inherited forms or a hand-made edit can mean some of it
was never rendered here), and a `copier update` line carrying the commit of
plinth this repository's own workflows call today, read from their `uses:`
lines so the update does not move that pin under it. When that pin cannot be
established (no such `uses:` line, or two that disagree) the tags and file
list still print, with no command. A repository the door did not make, or
whose recorded tag is not an exact release tag, is a SKIP, not a PASS. It
never runs `copier update`; `/plinth:template-update` runs that line, the
user's to start, and leaves any conflict for a person before it opens a draft
pull request.

A repository made before this item shipped hears about it two ways: an agent
running an updated plugin's `/plinth:floor-check` by hand, or its own
`ci / floor-check` once its workflow pin is raised (Dependabot proposes
that) — CI downloads the checker from the plinth commit its own workflow is
pinned to, so an older pin keeps running the older checker until then.

Do not fix anything in this session, and do not run anything that writes.
