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

One row per stage, found by its Trigger: the state a project is in. Tool is
the one tool for each job of the stage, a job after its colon; its Class
says where it comes from, in the same order: installed (plinth installs it),
built in (Claude Code has it), platform (GitHub or the host), listed (to add
first, from [listed.md](listed.md)). plinth piece is what plinth gives
around the tool. Also is at most one alternative, with its condition. Then
is the row that usually comes next; `-` is none.

| Trigger | Tool | Class | plinth piece | Also | Then |
| --- | --- | --- | --- | --- | --- |
| No repository yet (step 1) | `/plinth:new-project <owner>/<name>`, typed | installed | the template, rendered with its checks and rules | - | Repository made, its first pull request open |
| Repository made, its first pull request open (step 1) | the pull request's page: squash and merge it once every check is green | platform | the merge command in `${CLAUDE_PLUGIN_ROOT}/docs/tutorials/getting-started.md` | - | First pull request merged |
| A repository plinth did not make (step 1) | `/plinth:floor-check`: what is missing, one fix each, read-only | installed | - | - | An idea in your own words |
| First pull request merged (step 1) | - | - | `${CLAUDE_PLUGIN_ROOT}/docs/how-to/give-the-agent-a-token.md`, `give-the-agent-its-own-account.md` and `set-four-things-by-hand.md` there | `/run-skill-generator` (built in): once, after the token, so that the run command builds, launches and drives this app, from a skill of its own beside the project's verify skill | An idea in your own words |
| An idea in your own words (step 2) | `/grilling`: an interview before any code | installed | - | `/design` (built in): screen mockups on a canvas, for an idea that is a page people look at, before or beside the interview, with Claude Code v2.1.265 or later and an account where the Design template is available | A ticket ready |
| A job bigger than one session (step 3) | `/to-spec`, then `/to-tickets` | installed | - | `/wayfinder` (installed): when the way is unclear | A ticket ready |
| A ticket ready (step 4) | `/clear`, then `/implement #N`: one ticket per session, test first; `/frontend-design`: a page a person will look at | built in, then installed; installed | the project's `verify` skill, its check before each commit, which takes the place of the bundled `/verify` (that one runs the app, as `/run` does) | `/simplify` (built in): cleanup of the changed code | A pull request with checks running |
| A pull request with checks running (step 5) | the required checks; `/run`: see the change working; `/security-review`: a security pass over the branch's diff before the merge | platform; built in; built in | the fresh-context review's findings in the description (a subagent given the diff, the criteria and the rules, not the conversation); the third-party reviewer's comments, when it is on | `/simplify` (built in): cleanup of the changed code | Green, and seen working |
| Green, and seen working (step 6) | the squash merge, on the person's `merge #N` | platform | the decision report; `/plinth:floor-check` says whether the agent's login is only told not to merge, or cannot merge at all | - | A ticket ready |
| Something broke (step 7) | `diagnosing-bugs` ("diagnose this"): reproduce, a failing test and the fix; `/triage`: issues someone else opened; `/doctor`: Claude Code itself misbehaving, not the app; `/rewind`: the agent's own edits in this session, never a merge | installed; installed; built in; built in | a merge that broke `main`: the project's `docs/how-to/undo-a-merged-change.md` first, then the restore in a `web` project's README, "Where it runs", while the other archetypes have no restore steps of their own; a leaked secret or something bad that ran here: `${CLAUDE_PLUGIN_ROOT}/docs/how-to/run-a-project.md#7-when-something-breaks`, with its revoke list | - | A pull request with checks running |
| Stopping, or coming back (step 8) | the issues and pull requests: the record; `/plinth:records-check`: what is out of place in it, read-only; `/handoff`: before another tool or person takes over; `/resume`: back to an earlier conversation, same machine only; `/recap`: a one-line summary of this one, same machine only | platform; installed; installed; built in; built in | - | - | A ticket ready |
| Between pieces of work (step 9) | Dependabot: dependency updates, merged on green; `/plinth:floor-check`, then `/plinth:template-update`: the template behind; `/plinth:floor-check`: a look back, when the guide says one is due | platform; installed; installed | the reminder issue titled "Template update available: …" (template v1.39.0 on, GitHub), whose command is `/plinth:template-update`; the look back's seven questions, in the guide's note, with `/insights` (built in) and `/usage` (built in) for its bills question | `/improve-codebase-architecture` (installed): when the code has grown hard to change; the hardest for a beginner | An idea in your own words |
| A merged change to put out (release and deploy, after step 6) | a version tag the person pushes; Render: a `web` app or a `dashboard` there, once `main` is green | platform; platform | the project's `docs/how-to/publish-a-release.md` and `.github/workflows/release.yml`, with GitHub's generated release notes grouped by `.github/release.yml`; `${CLAUDE_PLUGIN_ROOT}/docs/how-to/choose-where-a-web-app-runs.md`: plinth does not deploy a `web` app that runs anywhere else; a GitLab project has none of these | - | The project in use |
| The project in use (operate) | the host's dashboard: its deploy-failure notification first, then its logs; `/triage`: what users report, written as an issue | platform; installed | `${CLAUDE_PLUGIN_ROOT}/docs/how-to/set-four-things-by-hand.md`, "After the first deploy": an uptime monitor (UptimeRobot or Better Stack) and an error tracker with a free plan each, one copy of the data off the host and the bill to expect. None is installed: the person sets each up in the service's own account | - | Something broke |
| Looking back on a piece of work (retrospective) | `/retro`: it reads the session and suggests rules and checks, most serious first, and changes nothing | installed | at a project's end, the questions of the issue form "End or hand over this project" | `/insights` (built in): where recent sessions on this machine went wrong, not in cloud sessions | A ticket ready |
| Ending the project, or handing it over (end) | - | - | the README, from step 2; the issue form "End or hand over this project" (New issue on GitHub), which lists each step and asks what to do differently next time | `/handoff` (installed): when another person or tool takes it over | - |
| A `web` project to put online (after step 1) | Render: built and checked by plinth | platform | `${CLAUDE_PLUGIN_ROOT}/docs/how-to/choose-where-a-web-app-runs.md`: Render, or another place that page names, whose steps and risks become the person's | - | An idea in your own words |
| Correcting the agent the same way again (any step) | - | - | `${CLAUDE_PLUGIN_ROOT}/docs/how-to/turn-a-correction-into-a-rule.md`: a line in `AGENTS.md`, then a reviewer rule, then a test | - | - |
| Unsure which skill now (any step) | `/plinth:guide`, typed by the person: user-only, so the agent asks the person to type it | installed | this table, `/plinth:arsenal`: on GitLab, where the guide does not read the project, the answer | - | - |

When and how to report to the person is the rendered repository's output
style, "Beginner or non-engineer", not this catalog. A repository rendered
before plinth-template v1.19.0 has an `AGENTS.md` line that sends the agent
here for a five-item report. Until `/plinth:template-update` brings it to
v1.19.0, that line still means this: at the start of a task, an important
choice, a failure, and the end or a resume, report the goal now; the next
action and why; what the person decides or confirms; the evidence of
progress or completion; where to return when stuck and where the record
lives. Not every turn. A request for an explanation is not approval of a
change.

`/plinth:guide` reads this table and the repository's state and tells the
person, in their language, where the project is and the one command to type
next; a step or tool belongs in this table before the guide can name it.
`/handoff` writes a temporary file whose path the next session needs, so the
issues and pull requests stay the first record.

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
