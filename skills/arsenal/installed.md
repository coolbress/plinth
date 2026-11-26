# Installed by default

What plinth installs with itself, what each plugin costs, and the Claude Code
built-ins the arsenal's table names.

| Plugin | What | When | Cost | Source |
| --- | --- | --- | --- | --- |
| `mattpocock-skills` | Fifteen skills: `/implement` (calls `tdd`, `code-review`), `/triage`, `grilling`, `domain-modeling`, `codebase-design`, `diagnosing-bugs`; for planning `/to-spec`, `/to-tickets`, `/wayfinder`; for clean-up `/improve-codebase-architecture`; `/handoff`; and for looking back `/retro`, with `writing-for-agents`, which it calls | Any change bigger than a typo: `/grilling` to shape it, `/implement #N` to build it; a job bigger than one session: `/to-spec`, then `/to-tickets`; after a piece of work: `/retro` | ~0.54k tokens always on (7 skills listed; those on "Skills only the person can start" are not; `writing-for-agents` is listed, ~50 of it, since the agent can call it by itself) | [mattpocock/skills](https://github.com/mattpocock/skills) (MIT) |
| `taste-skill` | One skill, `design-taste-frontend`: frontend design that does not look templated, for landing pages, portfolios and redesigns, with its own redesign mode and pre-flight check. Dashboards and dense product UI go to `/design` first | A page a person will look at, server-rendered HTML included: say so in the ticket or the prompt, or type `/design-taste-frontend`; on a repository rendered from the template the agent did not reach for it on its own (one run). Dashboards and dense product UI: `/design` first | ~0.1k tokens always on (1 skill), ~34k when it fires | [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) (MIT) |

"Always on" is each plugin's share of the skill listing, as `/context`
reports it with a 1M-context model, on an installed default set. With
plinth's own two listed skills (~0.27k) the set comes to ~0.91k. Claude Code
caps the listing, built-in skills included, at 1% of the context window. At
1M that leaves room for all of it. At 200k the cap is ~2k, and because the
built-in skills share it, some descriptions are cut to about the skill's
name: they still run when called by name, but are less likely to be picked.
Setting `skillListingBudgetFraction` to 0.015 in a repository's
`.claude/settings.json` left none cut, for ~0.2k more tokens always on at
200k (~0.4k with `mattpocock-skills-extra`) and none at 1M; plinth-template
sets it.

`code-review` is the one installed skill that shares its name with a Claude
Code built-in: `/code-review` there reviews the diff for bugs at a chosen
effort, and `mattpocock-skills:code-review` reviews it against the
repository's standards and the issue's spec. A session lists both. plinth
keeps the plugin's because `/implement` calls `/code-review` by name when it
finishes a ticket.

Built into Claude Code, nothing to install: `/design` for screen mockups and
layouts before building, `/dataviz` for charts, `/security-review` for a
security pass over the branch's changes before the merge (step 5; the
template's required CodeQL check still runs), `/resume` and `/recap` to come
back on the same machine (step 8; on another machine the issues and pull
requests are the record), `/insights` for where recent sessions on this
machine went wrong (looking back), and `/doctor` when Claude Code itself
misbehaves. `/debug` turns on Claude Code's own debug log and reads it: it
debugs Claude Code, never the app, so it is not offered when the app breaks.
For product UI (dashboards, dense forms) use `/design` first; `taste-skill`
puts dashboards, admin panels and dense product UI outside its scope and
names a design system for them (Fluent, Carbon, Atlassian, Polaris).

Every third-party entry is pinned to a full commit SHA in plinth's
`.claude-plugin/marketplace.json`; the licenses are listed in `NOTICE`.
