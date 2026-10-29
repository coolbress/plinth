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
  --ruleset "${CLAUDE_PLUGIN_ROOT}/ruleset.json" --merge-ruleset "${CLAUDE_PLUGIN_ROOT}/ruleset-merge.json" \
  ${repo:+--repo} ${repo:+"$repo"}
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
`${CLAUDE_PLUGIN_ROOT}/docs/how-to/give-the-agent-a-token.md`; never run a logout or
delete a credential yourself.

`--credentials` also asks whether a production database URL is within the
agent's reach (#648). It reads three places: this environment's variables,
every `.env*` file under the repository, tracked or not (a directory named
`.env*`, usually a virtualenv, is not entered), and the `env` block of
`.claude/settings.json` and `.claude/settings.local.json`, the repository's
and the user's. A `postgres://` or `postgresql://` URL there (any letter case,
a `+driver` allowed) is a WARN naming the variable, or the file and line,
never the value, with one fix line: keep the production URL only in the
host's settings and use a local database for work, the template's SQLite
default. Not a WARN: a URL whose every host is local (`localhost`, a
loopback address, `0.0.0.0`, a Unix socket, a `.localhost` name), a reserved
placeholder name (`example.com`, `.example`, `.test`, `.invalid`), a host
written as a variable (`${PGHOST}`, `<host>`), a database whose name says it
is for tests (`test`, `app_test`, `testing`), an empty value, a `#` comment.
Nothing found is an INFO naming what is not read, never a PASS: shell profile
files, any other file, and other schemes (`mysql://`, `mongodb://`). Relay a
WARN with its fix line; never delete the line or the variable yourself.

`--merge-ruleset` expects the second ruleset the door applies: the
`update` rule alone, with the repository's admin role exempt from it, so
an account with write access cannot merge and the admin merges as before. It is a
PASS in that shape, a FAIL in any other, a WARN when no ruleset carries
`update` (every repository made before it; the WARN names
`scripts/create-merge-ruleset.sh`, which needs repository administration, so
give it to the user to run), and a SKIP when its bypass actors cannot be
read: never a PASS then.

With `--merge-ruleset` one more line follows, starting `the merge:`. It
says whether "merge on your word" is guidance or a boundary for the login
this run reads with, which in this session is the login the agent inherits.
GitHub lets the admin role past the merge ruleset whatever the token, so the
account's role decides: `guidance` (an INFO) when the login is the
repository's admin, or when it is not but no ruleset reserves the merge;
`boundary` (a PASS) when it is not the admin and the merge ruleset stands,
or when it cannot write to the repository at all.
A login that is not the admin cannot read that ruleset's bypass actors, so
its actor line stays a SKIP; the boundary is then read from GitHub's own
answer on the ruleset, that this login can never bypass it. That answer is
this login's only: the line then says that whether the admin is still exempt,
so that the person's own merge goes through, was not read, and that the
person's own run of this skill reads it.
The line is printed when the branch has no rules or its rules cannot be read,
too: no rules is `guidance` for any login that can write; unread rules leave
it a SKIP for one that is not the admin.
A role it cannot read, or a merge ruleset not found in its shape, is a SKIP:
never a boundary then. Put the line in the summary in plain words: with
guidance, the agent could merge and is only asked to wait; with a boundary,
GitHub refuses the agent's merge and the person merges. Guidance is a setup,
not a defect: leave it out of the FAIL and WARN list. The way to a boundary
is `${CLAUDE_PLUGIN_ROOT}/docs/how-to/give-the-agent-its-own-account.md`,
for the user to do;
the boundary holds only while no admin login is left where the agent can
reach it, which the `--credentials` lines are about. `ci / floor-check`
(`--actions-token`) does not decide it: the Actions token is not the agent's
login, so the line there is an INFO saying `not verified here`, left to this
skill.

`--ruleset` expects the wall
`/plinth:new-project` raises, the CodeQL alert thresholds of its
`code_scanning` rule included; for a repository with a different wall (plinth
itself, for one) pass `--expect-checks "<name>, <name>"` as well. Add
`--project <dir>` when the project is not at the repository root — the
directory the repository's own CI gives `python-ci.yml` as its
`working-directory` — because without it `pyproject.toml` and `uv.lock` are
read from the root and reported missing although they exist one level down.

## A GitLab checkout

A checkout rendered with `host: gitlab` (its `.copier-answers.yml` says so,
or pass `--host gitlab`) is read as a GitLab project. When `origin` is on
gitlab.com, run this instead of the command above, with the project's path
(`group/name`) as `--repo`, or the argument if the user gave one:

```bash
repo="$(git remote get-url origin 2>/dev/null | sed -nE 's#^(https://gitlab\.com/|git@gitlab\.com:)(.+)$#\2#p' | sed 's#\.git$##')"
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/floor-check.py" --root . --host gitlab --sandbox --credentials ${repo:+--repo} ${repo:+"$repo"}
```

The wall is read through `glab api` with the user's own login: the
protected default branch (no one pushes, Maintainers merge, no force push),
"Pipelines must succeed" with skipped pipelines not counted, squash always
and fast-forward, the labels, and the include on the default branch. Reading
the protection needs the Maintainer role; with less it is a SKIP. Without
`glab` or its login (`glab auth login --hostname gitlab.com`), the wall is a
SKIP and the checkout's include is read instead. `--credentials` reads
gitlab.com there: `GITLAB_TOKEN`, `GITLAB_ACCESS_TOKEN` or `OAUTH_TOKEN` set,
git helpers for gitlab.com other than glab's, an `Authorization` header and a
gitlab.com login in `~/.netrc`; the login glab itself stores is a SKIP. Relay
them as on GitHub. The production database URL item reads the same three
places as on GitHub. The template drift item's `copier update` line carries
the include's commit and its checksum together (`plinth_sha` and
`plinth_gitlab_integrity`). In place of `gh`'s denies,
the agent settings must deny `glab`'s token and config reads. The issue and
merge request templates are under `.gitlab/`. Dependabot does not run there,
which is an INFO. In place of the `ci` job, the top-level include of
`.gitlab-ci.yml` is judged by the GitLab pipeline's own `floor-check` rule,
read from `${CLAUDE_PLUGIN_ROOT}/gitlab/python-ci.yml`. That rule needs
PyYAML: without it, the job's PyYAML is installed by hash into a temporary
directory from PyPI (its wheels cover CPython 3.11 to 3.14; another Python
without PyYAML gets a SKIP saying so), and with `--no-network` the include is
a SKIP unless PyYAML is already there.

A FAIL in the wall carries its fix as a `glab api` line or a settings URL;
it needs the Maintainer role, so give it to the user to run, not yourself.

## A JavaScript or TypeScript repository

A GitHub repository with `package.json` and no `pyproject.toml` where the
project is read (the root, or `--project`) is read as a JavaScript or
TypeScript project (#681), the shape v0, Lovable and Bolt export. Run the same
command. The first line under the header is an INFO saying so in plain words:
plinth has no checks for that language (no lint, typecheck, test or build
check), and the checks that do not depend on the language still apply. Those
keep their verdicts: the document set, `.claude/settings.json`,
`.gitattributes`, `.github/dependabot.yml`, tracked dotenv files, action pins,
and, with a repository name, the ruleset's rules, push protection, CodeQL and
the labels.

Each item that depends on Python is an `N/A` line saying `does not apply` and
why, in one sentence: `pyproject.toml`, `uv.lock`, the archetype's items
(container image, `.env.example`, JSON logs), the `ci` job's call to
`python-ci.yml` (not read, from the checkout or the default branch), and the
ruleset's required checks named `ci / <job>`, which only that call reports.
With none left to require, the `required_status_checks` rule and its
strictness are not asked for either; a name `--expect-checks` gives that is
not `ci / <job>` is still judged. CodeQL's default setup is asked to analyse
`javascript-typescript` (or the older `javascript` or `typescript`) in place of
`python`, and its fix line names that language. `N/A` lines are neither failures nor
not-verified items: the summary line counts them on their own, `K do not
apply`, printed only when K is above 0.

When `bun.lock` or `bun.lockb` is the only lockfile (no `package-lock.json`,
`npm-shrinkwrap.json`, `yarn.lock` or `pnpm-lock.yaml`), one INFO line says
that GitHub's dependency review does not read it, so a vulnerable dependency
is not reported before a merge.

What it leaves out: the project's own lockfile, scripts and source are not
read, and no JavaScript or TypeScript check exists to stand in for the Python
ones. Template drift is a SKIP as for any repository the door did not make.
A repository that also holds a `pyproject.toml`, one whose Python project is
one directory down (the `--project` line stands), and a GitLab checkout are
read as before. `ci / floor-check` is not involved: it runs only from
`python-ci.yml`, which such a repository does not call.

## Report

Lead with a summary in plain words, for a person who may not know the
checker's terms yet. It comes before the checker's output and replaces none
of it:

1. How many items fail and how many were not verified, the two numbers on
   the checker's last line, which starts `-- N failed, M not verified`, and
   how many WARN lines there are. With no FAIL, say that no check failed in
   what was verified, and that the not-verified count is what could not be
   verified, whether or not the checker read it.
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
`N/A` lines (a JavaScript or TypeScript repository, above) are not defects
either: leave them out of the FAIL and WARN list, write no fix under them, and
in the summary say that plinth has no checks for that language rather than
that those items pass.
A third count, `K left to /plinth:floor-check`, appears only in a run with
`--actions-token` (`ci / floor-check`) and only when K is above 0: INFO
lines for reads that token cannot make and this skill, run with a login that
administers the repository, does (push protection, the ruleset's bypass
actors, the CodeQL default setup languages, the squash commit settings, and
a private repository's missing CodeQL rule). In that job's summary their
`not yet confirmed` lines end `; left to /plinth:floor-check` and are not
annotated; the other `not yet confirmed` lines are. This skill's own run
never prints the count; without the flag those reads are SKIPs.

## What five of the checks read, and what they do not

Five checks are static reads with a stated scope (#95, the predicates #42
left open; the plinth pins, #447; the release workflow, #703). A finding from any of them is a WARN, never a FAIL, so a
repository that passed before they existed still passes; a PASS from them
covers only what is listed here.

| Check | Reads | Does not read |
| --- | --- | --- |
| Tracked dotenv | `git ls-files` under `--root`: a tracked file named `.env` or `.env.<anything>`, except `.env.example`, `.env.sample`, `.env.template` | File contents, git history, an untracked local `.env` (not the defect), `.envrc`, other names such as `prod.env`. It is not a secret scanner; `ci / secrets` is. Outside a git work tree it is a SKIP |
| Action pins | Every `uses:` line in `.github/workflows/*.yml` and `*.yaml`: `owner/repo@<40-hex SHA>`, `docker://…@sha256:<digest>` or a local `./` path. Comments and block scalars (`run: \|`) are skipped | Composite actions under `.github/actions`, whether the SHA exists upstream, what the pinned action itself calls. A `uses` written in a form the line pattern cannot read (flow style, a quoted, anchored or explicit `?` key: any `uses` in key position that is not a plain `uses: value`) is a SKIP naming the line |
| Plinth pins agree | The same `uses:` lines as Action pins, those of `coolbress/plinth/...` at a full commit SHA: two or more SHAs across the files (`ci.yml` and `label.yml` are rendered at one commit; a hand edit moves one) are a WARN naming each file with its SHA, and the INFO under it is the `sed` line that moves each lagging file's plinth references, and nothing else in it, to the SHA the `ci` job calls. The owner, repository and SHA compare in any letter case, as GitHub reads them. One SHA, or none outside the `ci` job, prints nothing, whatever the template state | A plinth `uses:` on a tag or branch (the Action pins WARN, not repeated). A `uses` it cannot read is a SKIP naming the file and line, unless the readable ones already disagree. Not a FAIL: `label / label` is not a required check |
| Release workflow | For a `cli`, `library`, `backend` or `data-ml` on GitHub, `.github/workflows/release.yml` at the repository root (also with `--project`) as text, comments dropped: present (plinth-template 1.29.0 renders it for `cli` and `library`, 1.30.0 for `backend`, 1.31.0 for `data-ml`); every line of its `on:` block is `push:`, `tags:` or a tag pattern under it, so another event, another filter or a key it cannot read (a quoted one) is a WARN naming that line; no `secrets.<name>` other than `GITHUB_TOKEN`, and no `password:`. For `data-ml`, the files its `ASSETS:` line names: one ending in `.pkl`, `.pickle`, `.joblib` or `.pt`, in any letter case, is a WARN; no such line, or a value that is not one line of plain file names (a folded or literal block such as `>-`, a value continued on a deeper-indented line, a second `ASSETS:` line, an expression, a comment), is a SKIP | Whether PyPI has a publisher registered, whether the `pypi` environment exists or what protects it, whether the image was pushed or who can fetch it, whether the release exists or its files match their `SHA256SUMS`, which files a `data-ml` step uploads other than through `ASSETS`, whether the tag-against-version step is still there, what the jobs do. Missing on an instance rendered before the template release that adds it is a WARN whose INFO names the update. On GitLab, an INFO: the template renders no release workflow there. `web` is not asked |
| Model card | For a `data-ml`, on either host, `MODEL_CARD.md` in the project directory: present (plinth-template 1.31.0 renders it). Missing is a WARN whose INFO names the update | What the card says, whether its personal-data answer is true or filled in, whether the training run fills its results. Other archetypes are not asked |
| JSON logs | For a service archetype (`backend`, `data-ml`, `web`), the Python under `src/`: a `logging.Formatter` subclass that calls `json.dumps`, structlog's `JSONRenderer`, python-json-logger, or loguru with `serialize=True`; comments are ignored, string literals are not | Anything at run time: the application is never started, so the PASS line says "static hint", not proof of what the process prints. Logging it does not recognise is a SKIP; only a source tree with no logging at all is a WARN. Other archetypes are not asked |

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
lines so the update does not move that pin under it, and, on GitHub, the
owner's two answers `/plinth:new-project` gave the first render: whether the
owner's public `.github` repository publishes a pull-request template and
issue forms, read the same way, each true only while this repository has
none of its own (its own already replace the owner's, and true would delete
them). Without them an update reads both as false and can write one local
form that hides every shared one (#726). They need `--repo`; without it, or
when a read fails, the item prints the tags and files with no command and
says what was not read. When the target tag was
tested with a newer plinth commit (its `copier.yml` `plinth_sha` default,
compared with the live pin on GitHub), a second line carries that one, under
a line naming both SHAs, their release tags and the compare URL: the person
chooses, the item never does. A live pin newer than the tested one is kept
and said so, with no second line; a comparison that could not be read is
said so too, with only the first line (#511). Each line is printed only
while the target tag still names the commit plinth was tested with
(`scripts/new-project.sh`'s `template_sha`): a tag that names another commit
is a WARN naming both, with no line, and so is a repository already on that
tag, in place of the PASS; a tag whose commit could not be read
still shows the line, said to be not verified, and `/plinth:template-update`
refuses to run it until it is (#519). When that pin cannot be
established (no such `uses:` line, or two that disagree) the tags and file
list still print, with no command. A repository the door did not make, or
whose recorded tag is not an exact release tag, is a SKIP, not a PASS. It
never runs `copier update`; `/plinth:template-update` runs that line, the
user's to start, and resolves a conflict only on a person's word for that
file before it opens a draft pull request.

A repository made before this item shipped hears about it two ways: an agent
running an updated plugin's `/plinth:floor-check` by hand, or its own
`ci / floor-check` once its workflow pin is raised (Dependabot proposes
that) — CI downloads the checker from the plinth commit its own workflow is
pinned to, so an older pin keeps running the older checker until then.

Do not fix anything in this session, and do not run anything that writes.

End the report with one line in the person's language: try typing
`/plinth:guide`; it explains the whole way in plain words, where this
repository is on it, and the one command to type next. On a repository plinth
did not make, it points back here.
