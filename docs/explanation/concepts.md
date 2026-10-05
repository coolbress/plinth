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

plinth fills that gap for a public repository: the rules live on GitHub, and
the way of working comes from skills others already made well, with a guide
to walking them. Its author's earlier attempts to keep the rules inside the
agent came to the same conclusion.

## About what plinth is

plinth helps someone building with a coding agent keep purpose, decisions and
context, repeat small verifiable changes, and leave a repository another
developer can take over.

It is not a harness: Claude Code is. plinth adds two things around it. The
first is required checks in the environment, on GitHub, where an agent without
administration on the repository cannot switch them off. The second is skills the harness
loads only when a task calls for them. Nothing in the plugin enforces
anything; the plugin can be uninstalled and the checks still stand.

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
| The checks answer | the required checks | GitHub refuses the merge | what no check asserts; an administrator's edit |
| The record remembers | issues and pull requests | they live on GitHub, not on one machine | what nobody wrote down |

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
by then the secret is on GitHub and has to be revoked, not just removed.
What stops a secret before it lands is GitHub's push protection, a
repository setting and not a check: the door turns it on,
`/plinth:floor-check` reports whether it still is, and by default it stops
the formats of known providers, not every secret. [Secrets at the push](../reference/required-checks.md#secrets-at-the-push)
names it and the paid rule that blocks the merge.

Some gaps are measured rather than assumed. CodeQL does not analyse a pull
request head that Dependabot pushed, and the code scanning rule passes it;
the dependency and test checks still run there, and `main` is analysed after
the merge (measured on five such heads in three repositories; heads other
bots push were not measured). The reference page says, check by check, what
each asserts.

A pull request can also change the checks themselves. The CI file is part
of the repository, so a pull request that replaces the call to plinth's
workflow with jobs of the same names that do nothing gets every required
check green. GitHub reports each check from the file on the pull request's
branch, and the ruleset pins the check's name and app, not what it runs.
This needs no administration, only write access and workflow permission,
both of which the setup's login gives an agent. The change is visible in the pull request's diff, and nothing blocks
it. `ci / diff-size` warns about a workflow edit the description does not
name, but that warning runs inside plinth's workflow: a pull request that
stops calling it removes the warning too.

The control that acts first is on the push, before any pull request exists.
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
