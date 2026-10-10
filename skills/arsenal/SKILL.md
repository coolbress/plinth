---
name: arsenal
description: Catalog of the tools plinth installs and the ones it lists but does not install. Use when the user asks which skill or plugin to use for a task, what plinth installed, what a tool costs, or how to install an optional one.
---

# Arsenal

plinth installs a default set of plugins and lists a few more you can install
yourself. This catalog says what each one is for, when to reach for it, and what
it costs. Nothing here is enforced; the required checks on GitHub are the only
enforcement.

For the planning-to-review flow (grill, spec, tickets, implement, review) do not
route by hand: run `/ask-matt` and let it pick the skill. The person's
walk-through, stage by stage, is `${CLAUDE_PLUGIN_ROOT}/docs/how-to/run-a-project.md`:
point them to it when they ask what to type next.

## Reporting

At four moments only (the start of a task, an important choice, a failure, the
end or a resume) report five items: the goal now; the next action and why;
what the person decides or confirms; the evidence of progress or completion;
where to return when stuck and where the record lives. Not every turn. A
request for an explanation is not approval of a change.

`/plinth:new-project` and `/plinth:template-update` are user-only, typed by
the user as `/` plus a pick from the list, invisible to the agent: when a pasted line drew "not installed", the
line arrived as text, and this catalog being open shows plinth is installed.

## Installed by default

| Plugin | What | When | Cost | Source |
| --- | --- | --- | --- | --- |
| `mattpocock-skills` | Planning, specs, tickets, TDD, code review, domain modelling | Any change bigger than a typo; start with `/ask-matt` | ~0.8k tokens always on (10 skills listed) | [mattpocock/skills](https://github.com/mattpocock/skills) (MIT) |
| `taste-skill` | One skill, `design-taste-frontend`: frontend design that does not look templated, for landing pages, portfolios and redesigns, with its own redesign mode and pre-flight check. Dashboards and dense product UI go to `/design` first | A page a person will look at, server-rendered HTML included: say so in the ticket or the prompt, or type `/design-taste-frontend`; on a repository rendered from the template the agent did not reach for it on its own (one run, #469). Dashboards and dense product UI: `/design` first | ~0.1k tokens always on (1 skill), ~34k when it fires | [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) (MIT) |
| `ponytail-skills` | One skill, `/ponytail-audit`: a ranked list of what to delete or replace with the standard library, repository-wide, biggest cut first; applies nothing | Every week or two, or after a burst of work | ~0.15k tokens always on (1 skill), no hooks | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) (MIT) |

"Always on" is each plugin's share of the skill listing, as `/context`
reports it with a 1M-context model (#255, again for #354, #468, #469 on an
installed default set, and #477 with each plugin loaded as the catalog narrows
it). With plinth's own two listed skills (~0.2k) the set comes to ~1.3k. Claude Code caps the listing, built-in skills
included, at 1% of the context window. At 1M that leaves room for all of it.
At 200k the cap is ~2k, and on Haiku 4.5, the 200k model measured for #469
and #477, 9 of the default set's 14 descriptions were cut to under 20 tokens, about
the skill's name, because the built-in skills share the same cap.

Built into Claude Code, nothing to install: `/design` for screen mockups and
layouts before building, `/dataviz` for charts, `/security-review` for a
security pass over pending changes. For product UI (dashboards, dense forms)
use `/design` first; `taste-skill` puts dashboards, admin panels and dense
product UI outside its scope and names a design system for them (Fluent,
Carbon, Atlassian, Polaris).

## Listed, not installed

| Plugin | What | When | Cost | Source |
| --- | --- | --- | --- | --- |
| `last30days` | What people said about a topic in the last 30 days | Finding candidates and recent reactions, when you want that research. Not for deciding; verify with `/research` | ~90 tokens always on, ~90k per call, a `SessionStart` hook (~0.4 s) | [mvanhorn/last30days-skill](https://github.com/mvanhorn/last30days-skill) (MIT) |
| `ponytail` | The full ponytail plugin with its hooks: the least-code mode every turn, its review, and the audit too | Only if you want the mode enforced every turn | 3 hooks, ~1k tokens | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) (MIT) |
| `impeccable` | A design with a point of view; writes a product record (`PRODUCT.md`) and a design record (`DESIGN.md`) | A page that should be remembered, when you will answer its questions: five of them and 43 minutes on the page where `taste-skill` asked none and took five (one measurement, 2026-09-12) | Hooks, agents and skills written into the repository (`.claude/`, `.github/`); no plinth pin | [pbakaus/impeccable](https://github.com/pbakaus/impeccable) (Apache-2.0) |

`last30days` installs with `claude plugin install last30days@plinth` and
`ponytail` with `claude plugin install ponytail@plinth`; nothing in the default
set runs a hook, and both of these do. Impeccable is
not in plinth's marketplace: run `npx impeccable install` from the project
root, which writes the hooks, agents and skills above into the repository. Its
own marketplace plugin loaded hooks and agents but did not register its skill
on Claude Code 2.1.269.

Every third-party entry is pinned to a commit in this repository's
`.claude-plugin/marketplace.json`; the licenses are listed in `NOTICE`.
`mattpocock-skills` carries 20 of the 25 skills upstream ships; the five left
out are `setup-matt-pocock-skills`, `grill-me`, `teach`, `to-questionnaire`
and `writing-for-agents` (#475, #477).
