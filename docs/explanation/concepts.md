# Concepts

Why plinth is shaped the way it is. For the checks themselves, see
[Required checks](../reference/required-checks.md); the vocabulary is in
[CONTEXT.md](../../CONTEXT.md).

## About why plinth exists

AI agents now write code well; checking what they wrote has not kept up.
Research and practice in 2026 point the same way. An agent's own "done" is not
evidence. Review bots raise many comments and still miss problems. Planning
kits shape what the agent does, but hold it to nothing. The harness, the
program that turns a model into an agent, is solved and keeps improving:
Claude Code is one. What most people building with an agent still lack sits
outside it. They need rules the work must pass, kept somewhere the agent does
not control, and a way of working that leaves evidence another person can
read. Platforms are adding such gates, mostly on paid or enterprise plans.

plinth fills that gap for a public repository: the rules live on the host
(today GitHub), the service that holds the repository and, outside the
agent, refuses a merge; the way of working comes from skills others already
made well, with a guide to walking them. Its author's earlier attempts to keep the rules inside the
agent came to the same conclusion.

## About what plinth is

A good project stands: it does what its user needs, shows that it does and
keeps showing it while in use, within the cost, the risk and the outside
rules you accepted, for as long as you need it.

That sentence is what plinth is for. A project settles five things once, and
everything else follows from them:

- whose use, and for what, and who else is affected;
- the expected result, and how it is confirmed (for an exploratory project,
  the question it exists to answer);
- the limits of cost and risk, and the outside rules that bind the project:
  law on data and accessibility, terms of service, licences; in the United
  States, output a person only prompted may carry no copyright;
- how long it must last, who takes it over, and what happens at the end:
  data deleted or handed over, keys revoked, users told;
- the agent's reach: what it may touch, and the most it can destroy or
  spend.

Every verdict plinth gives is read as one of three: pass, fail, or not yet
confirmed. A check that could not run, a setting a token could not read, a
property nothing asserts: each is the third, whatever colour GitHub shows.
GitHub's check list has only green and red, so where a green did not check,
the check's own text says so, and condition 4 under [what green
means](#about-what-green-means) lists the cases that are known.

plinth helps someone building with a coding agent keep purpose, decisions and
context, repeat small verifiable changes, and leave a repository another
developer can take over.

It is not a harness: Claude Code is. plinth adds two things around it. The
first is a repository configured so that the host requires checks before a
merge, where an agent without administration on the repository cannot switch
them off. The second is skills the harness loads only when a task calls for
them. Nothing in the plugin enforces anything; the plugin can be uninstalled
and the checks still stand.

## About the promise

Gated where a check can. Guided where it can't.

The host refuses a merge while a required check is red, on the properties
those checks assert and on nothing else. Most of the checks run other
people's tools: ruff, mypy, pytest, gitleaks, zizmor, GitHub's dependency
review and CodeQL. plinth chooses them, wires all but CodeQL into a
reusable workflow it maintains, turns on CodeQL's default setup where the
plan has it (a private repository needs GitHub Code Security, see [about
private repositories](#about-private-repositories)), and configures the
repository so that the host requires their results before a merge. What
plinth itself wrote is that workflow, the checks in it that run no outside
tool (`ci / pr-title`, `ci / diff-size`, and `ci / floor-check`, which runs
the floor checker), and the guidance. The
[reference page](../reference/required-checks.md) says, check by check, what
each one asserts. For some of what no check covers, the arsenal points at
chosen tools: a planning skill, a design skill, a research skill. Pointing
is all it does. Nothing happens unless a person or the model picks one, and
the catalog opens by saying that nothing in it is enforced.

The way of working stays "You decide. The checks answer. The record
remembers."

## About the scope

plinth is for an agent's user who does not read the diff: someone who
directs the work, reads the checks and the record, and needs the checks to
carry what a reader of the diff would otherwise carry.

It covers GitHub.com, Python projects managed with uv, and Claude Code as the
harness. New repositories are created by `/plinth:new-project`. An existing
repository is only read: `/plinth:floor-check` reports what it is missing and
changes nothing. A template update is proposed, as a draft pull request by
`/plinth:template-update`, only for a repository made from plinth's template;
it has no answer for one made another way. Private repositories are covered
on the plans GitHub enforces a ruleset on ([about private
repositories](#about-private-repositories)).

## About what plinth does not do

The host blocks the merge; plinth set it up that way; neither blocks an
agent's actions. Every check the host requires reads a pull request or the
repository's settings, and the only thing a red one stops is the merge of
that pull request. A production database, a credential, a spend ceiling and
a deployed app are outside every one of those checks: an agent session that
can reach them can act on them, and nothing plinth configures sees it
happen.

Safety, as plinth uses the word, covers secrets, dependencies and the supply
chain, and also the agent's reach and the way back: which credentials and
data an agent session can touch, whether a spend ceiling exists, and whether
a restore has been tried once. For the first three, plinth has checks and
settings: `ci / secrets` and push protection, `ci / deps` and Dependabot, and
the pins. For the other three it has one check at the edge and nothing
behind it: `ci / floor-check` fails when `.claude/settings.json` drops a
deny the template sets (a force push, `rm -rf`, `gh auth token`, reads of
`.env` and of gh's own configuration), which bounds what the agent runs and
reads on the machine it works on. No check reads what a session can touch in
production, what it may spend, or whether a backup was ever restored, and
the direction heading below says what is planned for those.

## About what plinth does now, and where it is going

This page describes what a check, a script or a recorded run in this
repository does today, except under this heading. What follows here is
direction, not a feature: expect nothing from it until a release note says
it shipped.

- Running a project on a token without workflow or administration
  permission, with Claude Code in its default auto mode, and recording what
  the agent could and could not do (#403).
- Making a lowered standard visible: a check configuration, a workflow input
  or a test set that no longer matches what was agreed (#404), and saying,
  per check and per commit, what was actually checked and what was not
  (#405).
- Candidate checks specified and measured before any is adopted: mutation
  testing, changed-line coverage, and ruff's complexity, commented-out code
  and unused-argument rules (#406); an arsenal indexed by the concern a tool
  answers, with written selection criteria (#407); finding which of the five
  things a project settles once go unrecorded, and asking for those (#408);
  a `verify` skill shipped in the template (#409).
- Four guide lines at the start of a project, a follow-up task not yet
  filed: production credentials and database outside the agent session; a
  spend ceiling per service; one rehearsed restore; an anonymous probe of
  any database the app uses. They are guidance, not gates, and their effect
  on this user has not been measured anywhere.
- GitLab, after those (#353).

## About how the pieces fit

```text
 ┌─ GitHub ─────────────────────────────────────────────────────────┐
 │ the rules on main: changes arrive as pull requests, and none     │
 │ merges until the required checks and the code-scan rule pass     │
 └──────────────────────────────────────────────────────────────────┘
          ▲ set up by new-project        ▲ read by floor-check
 ┌─ your repository ────────────────────────────────────────────────┐
 │ the rules the agent reads every turn, how changes are proposed,  │
 │ what the agent may not touch, and the CI that runs the checks    │
 └──────────────────────────────────────────────────────────────────┘
          ▲ made from plinth's template; template-update brings fixes
 ┌─ Claude Code ────────────────────────────────────────────────────┐
 │ plinth's four skills and a default set of others                 │
 └──────────────────────────────────────────────────────────────────┘
```

The files behind the middle box are `AGENTS.md`, `CONTRIBUTING.md`, the issue
forms and pull request template, `.claude/settings.json`, and a CI file that
calls plinth's reusable workflow. `floor-check` reads both GitHub's rules and
the repository. The code-scan rule passes a pull request Dependabot opened
without scanning it; the scan runs on `main` after the merge (see "About what
green means" below).

Each part promises something different:

| | By | Holds because | Does not hold |
| --- | --- | --- | --- |
| The agent is told | `AGENTS.md`, loaded every turn | Claude Code loads it | whether the agent follows it |
| You choose | skills | you, or the model, pick one | when neither does |
| The checks answer | the required checks | the host refuses the merge | what no check asserts; an administrator's edit |
| The record remembers | issues and pull requests | they live on the host, not on one machine | what nobody wrote down |

[Run a project](../how-to/run-a-project.md) walks the loop through these
parts.

## About the three review layers

A change can be reviewed in three ways, and they fail differently.

- **Automated checks** are deterministic and, once required by a ruleset,
  cannot be merged past. They catch only what they assert.
- **Automated review**, such as an AI reviewer on the pull request, reads
  the change and can notice what no check asserts. It is a filter, not a
  gate: it misses things and sometimes invents them.
- **Human review** is reading the diff. For someone who builds by
  describing what they want, it is often the weakest of the three.

plinth puts most of its weight on the first layer, adds the second as an
option (`third-party / review`), and does not claim the two replace the
third. Giving less weight to human review is a choice made for this kind of
user, not a claim that checks are as good as a careful reader.

## About what green means

A check only catches what it asserts: green means the asserted properties
hold, not that the code is right. `ci / test` passing says the tests that
exist pass, not that they test the right things. `ci / secrets` passing says
gitleaks found nothing it knows, and even a red one arrives after the push:
by then the secret is on the host and has to be revoked, not just removed.
What stops a secret before it lands is GitHub's push protection, a
repository setting and not a check: the door turns it on,
`/plinth:floor-check` reports whether it still is, and by default it stops
the formats of known providers, not every secret. [Secrets at the push](../reference/required-checks.md#secrets-at-the-push)
names it and the paid rule that blocks the merge.

Past that, a green check means what it asserts only while five conditions
hold. Four are evidence conditions: they decide whether the green is
evidence of the property. One is the enforcement condition: it decides
whether a red could have stopped the merge at all. "Unchanged" below means
that a change is visible and was reviewed, not that none happened: the CI
file and the ruleset are meant to change, through a pull request or a
person's decision. For each condition, what breaks it today and what plinth
has against it today. Nothing listed closes a condition; each narrows it.

### 1. The CI definition is unchanged (evidence)

The check names the ruleset requires come from the workflow files on the
pull request's branch: `ci.yml`'s call to plinth's reusable workflow for the
checks named `ci / <job>`, and, where a repository also requires
`third-party / review`,
the separate workflow that calls plinth's review workflow. What runs behind
each name is decided by those files, and every file that supplies a required
check is under this condition; what plinth has below reads `ci.yml` only.

What breaks it. A pull request can change the checks themselves. The CI file is part
of the repository, so a pull request that replaces the call to plinth's
workflow with jobs of the same names that do nothing gets every required
check green. GitHub reports each check from the file on the pull request's
branch, and the ruleset pins the check's name and app, not what it runs.
This needs no administration, only write access and workflow permission,
both of which the setup's login gives an agent. The change is visible in the pull request's diff, and nothing blocks
it. `ci / diff-size` warns about a workflow edit the description does not
name, but that warning runs inside plinth's workflow: a pull request that
stops calling it removes the warning too.

What plinth has. The control that acts first is on the push, before any pull request exists.
GitHub refuses a push that adds or changes a file under `.github/workflows/`
when the token lacks workflow permission: a fine-grained token without
Workflows, a classic one without the `workflow` scope. Measured on both with a
push adding one (#328); GitHub's refusal names creating and updating alike.
An agent pushing with such a token cannot get a rewrite of the checks onto a
branch at all ([the agent's own token](../how-to/run-a-project.md#give-the-agent-a-token-that-cannot-change-the-checks)).
It does not cover three cases: a push over SSH (a deploy key with write access
pushed a workflow change in the same measurement), a token that has the
permission (the browser login plinth's setup uses, and what `gh auth login`
asks for by default over HTTPS), and a person who pushes the change.

Past the push, the next signal comes after the merge, from outside the pull request.
`/plinth:floor-check` reads `ci.yml` on the default branch through the API
and fails when its `ci` job no longer calls plinth's `python-ci.yml` at a
full commit SHA (plinth itself calls its own `plinth-ci.yml` by local path,
accepted for plinth only). Only a run from outside the pull request's own workflows
sees this: the skill a person runs, or the e2e runner. `ci / floor-check`
runs the same item on the pull request's own `ci.yml`, so a pull request that
keeps the call but weakens it (a tag instead of a SHA, an `if:`) fails before
the merge. One that replaces the call removes `ci / floor-check` with it.
Nothing a pull request runs can refuse its own `ci.yml` before the merge. Pinning a
workflow so that a pull request cannot change it takes GitHub's required
workflows, an organization feature.

### 2. The ruleset is unchanged (enforcement)

The ruleset is what refuses the merge. Every other condition is about
whether a green tells the truth; this one is about whether a red could have
stopped anything.

What breaks it. Anyone holding administration on the repository can edit the
ruleset, drop a required check from it, add a bypass actor, or delete it:
an owner, or an agent working on a token with administration, as it does
after the browser login plinth's setup uses, whose `repo` scope includes it.
The edit is not a pull request: it has no diff on a branch, no check runs on it,
and nothing watches the repository between pull requests
([about who can change the wall](#about-who-can-change-the-wall)).

What plinth has. The generated `AGENTS.md` tells the agent never to ask for
administration on its everyday token, and the token the how-to has you make
for it leaves Administration at No access, so a one-off change goes through
`scripts/with-admin-token.sh` in a person's own terminal. The ruleset is
read back against `ruleset.json`, the wall the door applies:
`/plinth:floor-check` fails when a required check was dropped, when a
required check accepts a status from any source or from an app other than
the expected one, when the CodeQL alert thresholds were weakened, and when
the ruleset has a bypass actor, where its token reads them; where it cannot,
that line is a SKIP. `ci / floor-check` runs the same read on every pull request with the
Actions token, which never reads bypass actors, so that line is a SKIP there
every time. A ruleset edited between two pull requests is seen on the next
one only in the fields that run reads: the required checks, their source
and the CodeQL thresholds. A bypass actor added then is seen only when a
person runs the skill, and a field the checker does not compare is not seen
at all. Nothing sees the edit when it happens.

### 3. The check configuration, the workflow inputs and the tests are the agreed standard (evidence)

A check runs with the configuration the repository gives it, the inputs the
caller passes, and the tests that exist: all three live on the pull
request's branch.

What breaks it. `ci / lint` runs ruff with the repository's `pyproject.toml`,
so an edit to its `[tool.ruff]` table decides which rules run; `ci / test`
runs the tests that are there, so a deleted test, a test moved out of the
test paths, or a skip marker shrinks what is asserted; a `# noqa` or a
`type: ignore` does the same to one line. The inputs `ci.yml` passes to
plinth's workflow set thresholds: `max-diff-lines: 0` turns the diff limit
into a measurement that never fails, and `deps-fail-on-severity` raises the
severity a vulnerable dependency needs to be red. Each is in the pull
request's diff. The test and configuration edits need only write access.
The two input edits are a change to a workflow file, which the push refusal
under condition 1 stops for a token without workflow permission and nothing
stops for the browser login.

What plinth has. `ci / diff-size` names, in its log and job summary, every
change to the checks the description does not name: a workflow file, a
check configuration file (`conftest.py`, `pytest.ini`, `ruff.toml`,
`mypy.ini`, `.coveragerc`, `.gitleaks.toml`, `ruleset.json` and the others
it lists), a deleted test file, one moved out of the test paths, and a
change to `pyproject.toml`'s `[tool.*]` tables. It is a WARN, never a red:
it makes the change visible, and whether the change is justified is the
reviewer's call. It cannot see a weakened assertion inside a kept test, a
skip marker, or a threshold passed as a workflow input by the caller.
`ci / floor-check` accepts a `with:` block on the `ci` job and does not read
its values. Nothing today compares a repository's configuration with what
was agreed: that is #404, under the direction heading above.

### 4. The checks actually ran on this commit (evidence)

A pass on a pull request is one of three things, and the check's own text
is what tells them apart: passed after checking; passed without checking;
could not be confirmed.

What breaks it. A check can report a pass without having looked. Two cases
are measured rather than assumed. CodeQL does not analyse a pull
request head that Dependabot pushed, and the code scanning rule passes it;
the dependency and test checks still run there, and `main` is analysed after
the merge (measured on five such heads in three repositories; heads other
bots push were not measured). On a private repository without GitHub Code
Security, GitHub refuses dependency review, and `ci / deps` passes saying
nothing was checked where the dependency graph still answers; where the
graph is off, the review fails instead (#395). The third kind is a setting
the Actions token cannot read: push protection, the ruleset's bypass actors.
The checker behind `ci / floor-check` prints PASS, FAIL, WARN, INFO and SKIP
lines; a SKIP is a not yet confirmed, never a PASS, and the summary counts
them as not verified. In consumer CI that count is never 0: the bypass-actor
read needs an admin-read token, which the Actions token never is.

What plinth has. The ruleset's `required_status_checks` rule, with `strict`,
asks for every required check reported on the pull request's head with the
branch up to date, so a check that ran on an older commit does not count.
`third-party / review`, where a ruleset requires it, passes on a review of
the pull request's current commit, and without one in two cases its policy
names: a pull request whose recorded pushes are all Dependabot's, and a
release pull request whose diff is a release's, where the repository has
turned that on; its log says which. `ci / deps` says nothing was checked
where that is so. No job in plinth's workflows is skipped with `if:`: a
check that does not apply, such as `ci / deps` outside a pull request,
reports a pass that says so. A release is tagged only on a commit the e2e
runner's green run covers (the door's whole journey on real GitHub, through
the wall, then deleted). Saying, per check and per commit, what was actually
checked is #405.

### 5. The check looks at the property, and a check the agent can see becomes a target the agent can fit (evidence)

A check asserts a proxy for the property: a test suite for correctness, a
title pattern for a readable history, a line count for a reviewable change.
The agent reads the same workflow file the check runs, so every check is a
visible target, and an agent that cannot make one pass can make the proxy
fit instead.

What breaks it. `ci / test` passing says the tests that exist pass, and a
test rewritten to assert less still passes. `ci / pr-title` accepts any
conforming title, and `ci / diff-size`'s warning is cleared by naming the
path in the description, whatever the description says about it: both are
text matches, and the agent writes the text. A check that was chosen for a
property can be passed by producing the shape it looks for.

What plinth has. The reference page says, check by check, what each asserts,
so that no green is read as more. `ci / diff-size` keeps a change small
enough for a person to read where its limit is positive, docs and lockfiles
outside the count, and `third-party / review`, once configured, adds a
reader that is not the author: automated review, a filter and not a
gate, as [the three review layers](#about-the-three-review-layers) say. Nothing in plinth today
measures whether the tests look at the right thing, or whether a passed
check was fitted to: the candidate checks for that, mutation testing and
coverage among them, are #406, measured before any is adopted.

## About who can change the wall

The ruleset stops everyone who merges, owners included, from merging past a
red check. It does not stop anyone holding administration from editing the
ruleset itself. The wall is aimed at the everyday agent, not at the
administrator.

That is why the generated `AGENTS.md` tells the agent never to ask for
administration on its everyday token: a change to the ruleset or to code
scanning is a person's decision, made in Settings or through
`scripts/with-admin-token.sh`. A weakened ruleset is noticed by
`ci / floor-check`, but only when a pull request runs it; nothing watches the
repository between pull requests.

## About guidance written for the agent

Much of what a larger project would put in explanation pages lives in files
the agent reads instead: `AGENTS.md` (with `CLAUDE.md` pointing to it),
`CONTRIBUTING.md` and `docs/agents/`. That is deliberate. `AGENTS.md` is read
natively by most coding agents, and a 2026 study of 124 pull requests across
10 repositories measured 28.64% faster median runtime and 16.58% fewer output
tokens with one present, at the same completion rate
([arXiv:2601.20404](https://arxiv.org/abs/2601.20404)).

It is also why plinth ships no set of architecture decision records. The
generated guidance leads the agent to write one into the project when a
decision calls for it.

## About pins

Most of what plinth runs from other repositories is pinned. A consumer's CI
calls plinth's reusable workflow at a commit SHA, not a tag, and Dependabot
proposes raising it. Every third-party entry in plinth's own marketplace is
pinned to a full commit SHA. A commit SHA cannot move.

Two things are not pinned that way. `mattpocock-skills` comes from
Anthropic's official marketplace at whatever version it serves; plinth's
install test only checks that the version is at least 1.2.3 and below 2.0.0.
And the door renders one release tag of plinth-template, which whoever
maintains that repository can move; the door does not check which commit it
resolves to. Each plinth release names the tag it was tested with, and
`/plinth:floor-check` reports a repository rendered from an older tag as
behind.

A pin is also the recovery plan. plinth has one maintainer, and a SHA keeps
working only while its repository exists. If maintenance stops, fork the
marketplace and the workflow repository, point `claude plugin marketplace add`
and the `uses:` lines at the fork, and change the `coolbress/plinth` download
URLs inside `python-ci.yml` and `pr-review.yml` to the fork too; the pinned
commits keep working from there. Signed releases are not promised.

## About private repositories

On a public repository the wall is whole on every plan. On a private one,
three of its parts are paid GitHub products, and `/plinth:new-project
--private` raises what the plan allows and names the rest:

| Plan | What the door does |
| --- | --- |
| GitHub Free, a personal account or an organization | GitHub does not enforce a ruleset on its private repositories. Where the token reads the plan, the door stops before creating anything. Where it cannot (a fine-grained token), the ruleset call decides: the repository is created, the refused ruleset ends the run, and it is deleted again, or named for you to delete when the token cannot |
| GitHub Pro, Team or Enterprise | A ruleset with the same required checks as a public repository; its `code_scanning` rule depends on GitHub Code Security, below |
| With GitHub Code Security | CodeQL default setup and the `code_scanning` rule; `ci / deps` reviews each pull request's dependencies |
| Without it | No CodeQL and no `code_scanning` rule (in its place, `ci / lint`'s security rules); GitHub refuses dependency review, so `ci / deps` passes saying nothing was checked (in its place, Dependabot alerts after the merge) |
| With GitHub Secret Protection | Push protection on |
| Without it | No push protection (in its place, `ci / secrets`, which finds a secret after the push) |

The door turns no paid product on. Its summary, the README's First day section
and the first pull request name each part left out. On a Pro account GitHub
gives no status for either product, so the summary says "not verified" rather
than "not raised" (recorded on #352, 2026-10-05).

CI runs on the plan's Actions minutes. Measured on that run: each CI run is 9
jobs, about 9 billed minutes with each job rounded up, and the first pull
request took four CI runs.

GitLab Free remains an alternative for code that must stay private on a free
plan: it has protected branches and requires pipelines to pass, with no CodeQL
and no push protection.
