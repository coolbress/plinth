---
name: arsenal
description: The tool for each stage of a plinth project, from the task alone - what to use, what plinth installs or lists, what each costs, how to add it, and what not to use with plinth. Use when choosing a tool for a stage or a job, or asked what plinth installs or what a tool costs. What to do now in a project is /plinth:guide, which the person types.
---

# Arsenal

Which tool for each stage of a project, answered from the task without
reading the project. When the person asks what to type next, ask them to type
`/plinth:guide` in the project's folder: it reads the project and picks from
this table, and it is user-only, so an agent cannot call it. Nothing here is
enforced; the required checks on GitHub are the only enforcement. The steps
are those of `${CLAUDE_PLUGIN_ROOT}/docs/how-to/run-a-project.md`, which says
for each one what to look at, what the person decides, and whether it holds
if forgotten.

## Where you are, and what to do next

| Where you are | Next action | Tool | How to use it | It leaves | Then |
| --- | --- | --- | --- | --- | --- |
| No repository yet (step 1) | Create it with the wall; merge its first pull request on green | `/plinth:new-project <owner>/<name>`, typed | Type `/plinth:new-project <owner>/<name>` with the name the repository should have; it asks a few questions first | A repository on GitHub with its checks and rules, and its first pull request open | Repository made, its first pull request open |
| Repository made, its first pull request open (step 1) | Wait for green, squash and merge it, then bring `main` up to date in its folder | The pull request's page, or the merge command in `${CLAUDE_PLUGIN_ROOT}/docs/tutorials/getting-started.md` | When every check on it is green, say `merge #N` with its number, or squash and merge it on its page | One commit on `main`, the project's first | First pull request merged |
| A repository plinth did not make (step 1) | List what is missing; nothing is changed | `/plinth:floor-check` | Type `/plinth:floor-check` in the repository's folder | A list of what is missing, one fix each; nothing in the repository changes | An idea in your own words |
| First pull request merged (step 1) | Before step 2: a token that cannot change the checks; recommended next: the agent's own account, four things by hand | `${CLAUDE_PLUGIN_ROOT}/docs/how-to/give-the-agent-a-token.md`, `give-the-agent-its-own-account.md` and `set-four-things-by-hand.md` there | Nothing to type: open the token page and do what it says; the other two pages are recommended next, in that order | A token for the agent; recommended: an account for it, and four settings done by hand | An idea in your own words |
| An idea in your own words (step 2) | An interview, then an issue saying what "done" means | `/grilling`, with `domain-modeling` for `GLOSSARY.md`; `/grill-with-docs` (listed) | Type `/grilling` with the idea, before any code, and answer its questions one at a time | An issue that says what "done" means | A ticket ready |
| A job bigger than one session (step 3) | A plan in one issue, cut into tickets | `/to-spec`, then `/to-tickets`, or `/wayfinder` when the way is unclear, each typed | Type `/to-spec` to write the plan as one issue, then `/to-tickets #N` with that issue's number | A spec issue, and ticket issues cut from it that `/implement` takes one at a time | A ticket ready |
| A ticket ready (step 4) | A fresh session, test first, one ticket | `/clear`, then `/implement #N`; a page: `/design-taste-frontend`; dense product UI: `/design` | Type `/clear`, then `/implement #N` with the ticket's number: one ticket per session | A tested commit on a branch, from which the pull request is opened | A pull request with checks running |
| A pull request with checks running (step 5) | Wait for green, then the three questions, and see it run | The required checks; `/run`; the fresh-context review's findings in the description (a subagent given the diff, the criteria and the rules, not the conversation); the third-party reviewer's comments, when it is on; `/security-review` (built in, nothing to install): a security pass over what the branch changes, before you merge | Wait for every check to be green, then ask the three questions of `${CLAUDE_PLUGIN_ROOT}/docs/how-to/run-a-project.md`, step 5: "What shows it works, and what did you not check?", "Can I see it?" (type `/run` to see the change working), "What did the reviewer say?" (read the review's findings in the description); before you merge, type `/security-review`: it reads the diff against `origin`'s default branch for injection, log-in and data-exposure risks, so the project needs an `origin` remote | The checks' results on the pull request, and the change seen running | Green, and seen working |
| Green, and seen working (step 6) | The person says "merge", for that pull request | The decision report; `/plinth:floor-check` says whether the merge is guidance or a boundary | Say `merge #N` with the pull request's number: the person says it, the agent never merges on its own | One squashed commit on `main`, and the pull request closed | A ticket ready |
| Something broke (step 7) | When a merged change broke `main`: undo it first, then restore data it lost or changed, then reproduce and fix, then a short incident note; a leaked secret: revoke or rotate it first; otherwise reproduce, a failing test, then the fix | the project's `docs/how-to/undo-a-merged-change.md` (a revert through a pull request and the same checks); the restore: a `web` project's README, "Where it runs", and the restore tried in step 3 of `${CLAUDE_PLUGIN_ROOT}/docs/how-to/set-four-things-by-hand.md`, while the other archetypes have no restore steps of their own; a leaked secret or something bad that ran on this computer: `${CLAUDE_PLUGIN_ROOT}/docs/how-to/run-a-project.md#7-when-something-breaks`, with its revoke list; rewriting history after a leak is the person's own admin action and does not reach clones or forks ([GitHub's "Removing sensitive data"](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)); `diagnosing-bugs` ("diagnose this"); `/rewind` (built in) rolls back the agent's own edits in this session and never undoes a merge; `/triage` for issues someone else opened; when Claude Code itself misbehaves, `/doctor` (built in), a checkup of its install, settings, extensions and `CLAUDE.md`; `/debug` (built in) is for Claude Code itself, not the app | When a merge broke `main`, open the project's `docs/how-to/undo-a-merged-change.md` first; otherwise say `diagnose this: …` with what broke (a failing check, an error); type `/plinth:floor-check` when a plinth job fails on a plinth older than its latest release; type `/triage` on issues someone else opened; type `/doctor` when Claude Code, not the app, misbehaves | A revert pull request first when a merge broke `main`; a failing test that shows the bug, then the fix in a pull request; the incident note in the issue's Outcome; `/triage` leaves the issue labelled | A pull request with checks running |
| Stopping, or coming back (step 8) | Put what is left in issues and pull requests; ask "where is this, what's next?" | The record; `/plinth:records-check` counts what is out of place in it, read-only, by the repository's own conventions; `/handoff` to move work to another tool or person; `/resume` and `/recap` (built in, same machine only): back to an earlier conversation, and a one-line summary of this one | Before you stop, leave what is left in issues and pull requests; coming back, type `/plinth:guide`; at a milestone's end or coming back, type `/plinth:records-check`; type `/handoff` before another tool or person takes over; on the same machine, type `/resume` to go back to an earlier conversation or `/recap` for a one-line summary, while on any machine the issues and pull requests stay the record | Issues and pull requests that say where the work is; `/handoff` a temporary file | A ticket ready |
| Between pieces of work (step 9) | Dependency updates on green; the template update after a plinth release, or when the monthly reminder issue opens | Dependabot; `/plinth:floor-check`, then `/plinth:template-update`, typed; the reminder is an issue titled "Template update available: …", from template v1.39.0 on GitHub, and what to type for it is `/plinth:template-update`; `/improve-codebase-architecture`; `/ponytail-audit` (listed) | Say `merge #N` for each Dependabot pull request on green, one at a time; type `/plinth:floor-check`, then `/plinth:template-update` when it or the monthly issue says the template is behind | Dependencies and the template brought up to date, each in a merged pull request | An idea in your own words |
| A merged change to put out (release and deploy, after step 6) | A `web` app on Render goes out by itself once `main` is green; on a version tag the person pushes, `cli` and `library` publish to PyPI (a `Proprietary` one attaches its files to a GitHub release instead), `backend` its image to GHCR, `data-ml` its model as a GitHub release | Render, from `${CLAUDE_PLUGIN_ROOT}/docs/how-to/choose-where-a-web-app-runs.md`; plinth does not deploy a `web` app that runs anywhere else; the others: the project's `docs/how-to/publish-a-release.md` and its `.github/workflows/release.yml`, on GitHub, with GitHub's generated release notes, grouped by the project's `.github/release.yml`; a GitLab project has none of these | Nothing to type for a `web` app on Render; for the others, push a version tag as the project's `docs/how-to/publish-a-release.md` says | A new version: the app live, or a package, an image or a release for the tag | The project in use |
| The project in use (operate) | Turn on the host's deploy-failure notification first; read the host's logs when something looks wrong; keep the spend limits and the restore you tried | The host's dashboard: on Render, its notification settings, which need no other account; `${CLAUDE_PLUGIN_ROOT}/docs/how-to/set-four-things-by-hand.md`, whose "After the first deploy" names that notification, then an uptime monitor (UptimeRobot or Better Stack) and an error tracker with a free plan each, one copy of the data off the host and the bill to expect. None is installed: the person sets each up in the service's own account | Nothing to type: open the host's dashboard when something looks wrong | Nothing in the repository; what went wrong becomes an issue | Something broke |
| Looking back on a piece of work (retrospective) | In the session you are looking back on, before you clear it, ask what to change for the next run; keep what you agree with as a rule or a check, written into an issue | `/retro`, typed: it reads the session and suggests rules and checks, most serious first, and changes nothing; at the end of a project, the end-or-hand-over form's questions; `/insights` (built in): an HTML report of recent sessions on this machine and where they go wrong, not in cloud sessions | Type `/retro` in the session you are looking back on, before `/clear`, and keep the suggestions you agree with; type `/insights` to see where recent sessions on this machine went wrong | Suggested rules and checks; the ones you keep go into an issue | A ticket ready |
| Ending the project, or handing it over (end) | Do what the README says from step 2: data deleted or handed over, keys revoked, users told; what is left goes in issues | The README; the issue form "End or hand over this project" (New issue on GitHub), which lists each step and asks what to do differently next time; the record; `/handoff` when another person or tool takes it over | Nothing to type: follow the README from step 2; type `/handoff` when another person or tool takes it over | Data deleted or handed over, keys revoked, users told, and what is left in issues | - |
| A `web` project to put online (after step 1) | Choose where it runs: Render, built and checked by plinth, or a listed place whose steps and risks become the person's | `${CLAUDE_PLUGIN_ROOT}/docs/how-to/choose-where-a-web-app-runs.md` | Nothing to type: read the page and choose where it runs | The choice, made in the project | An idea in your own words |
| Correcting the agent the same way again (any step) | A line in `AGENTS.md`, then a reviewer rule, then a test that fails on the old mistake | `${CLAUDE_PLUGIN_ROOT}/docs/how-to/turn-a-correction-into-a-rule.md` | Nothing to type: follow the page, the cheapest rung first | A line in `AGENTS.md`, a reviewer rule or a test, in a pull request | - |
| Unsure which skill now (any step) | Ask the person to type `/plinth:guide`: it is user-only, so the agent cannot call it | `/plinth:guide`, typed by the person | The person types `/plinth:guide` in the project's folder; this table is `/plinth:arsenal`, and on GitLab, where the guide does not read the project, it is the answer | Nothing: it only reads | - |

A tool marked listed is not installed; the listed file below says how to add
it. Of the default set, `/improve-codebase-architecture` is the hardest for a
beginner: it uses engineer vocabulary, runs a design interview and writes an
HTML report. `/handoff` writes a temporary file whose path the next session
needs, so the issue and the pull request stay the first record.

When and how to report to the person is the rendered repository's output
style, "Beginner or non-engineer", not this catalog.

A repository rendered before plinth-template v1.19.0 has an `AGENTS.md` line
that sends the agent here for a five-item report. Until
`/plinth:template-update` brings it to v1.19.0, that line still means this:
at the start of a task, an important choice, a failure, and the end or a
resume, report the goal now; the next action and why; what the person
decides or confirms; the evidence of progress or completion; where to return
when stuck and where the record lives. Not every turn. A request for an
explanation is not approval of a change.

`/plinth:guide` reads this table and the repository's state and tells the
person, in their language, where the project is and the one command to type
next; a step or tool belongs in this table before the guide can name it. It
explains a row in depth from its cells: what the tool is for (Next action),
when to use it and what to type (How to use it, whose command is the one the
guide prints), what it leaves behind (It leaves), and what usually comes next
(Then, the start of another row; `-` for none).

## Skills only the person can start

These are user-only: the person types `/` and picks one from the list. The
agent cannot see or run them, and asking in your own words does not start them.
When a pasted line drew "not installed", the line arrived as text, and this
catalog being open shows plinth is installed. This is the one list; other pages
point here.

- plinth: `/plinth:new-project`, `/plinth:template-update`, `/plinth:guide`
- Installed by default: `/implement`, `/triage`, `/to-spec`, `/to-tickets`,
  `/wayfinder`, `/improve-codebase-architecture`, `/handoff`, `/retro`
- Listed, once installed: `/ask-matt`, `/grill-with-docs`, `/wait-what`

## More, when the question needs it

Each file below answers one question; read it only when asked that question.

- [installed.md](installed.md): what plinth installs by default, what each
  plugin costs, and the Claude Code built-ins the table names.
- [listed.md](listed.md): the tools plinth lists but does not install, and
  the line that installs each.
- [not-used.md](not-used.md): tools an agent can reach without installing
  anything that break a plinth rule. Read it before suggesting a built-in
  command the table does not name.

Why each tool is on the table, the coverage by step and concern, and the
recorded evidence are for maintainers, in
`${CLAUDE_PLUGIN_ROOT}/docs/reference/arsenal-evidence.md`; no answer needs it.
