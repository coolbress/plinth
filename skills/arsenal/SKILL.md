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
route by hand: run `/ask-matt` and let it pick the skill.

`/plinth:new-project` is user-only, typed by the user as `/` plus a pick from
the list, invisible to the agent: when a pasted line drew "not installed", the
line arrived as text, and this catalog being open shows plinth is installed.

## Installed by default

| Plugin | What | When | Cost | Source |
| --- | --- | --- | --- | --- |
| `mattpocock-skills` | Planning, specs, tickets, TDD, code review, domain modelling | Any change bigger than a typo; start with `/ask-matt` | ~1.6k tokens always on | [mattpocock/skills](https://github.com/mattpocock/skills) (MIT) |
| `taste-skill` | Frontend design that does not look templated: landing pages, portfolios, redesigns | Any page a person will look at, server-rendered HTML included, from its first version; the user will not ask for styling. It reads the brief, decides direction, and asks at most one question | ~1.7k tokens always on (13 skills), ~34k when `taste-skill` fires | [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) (MIT) |
| `last30days` | What people said about a topic in the last 30 days | Finding candidates and recent reactions. Not for deciding; verify with `/research` | ~100 tokens always on, ~90k per call | [mvanhorn/last30days-skill](https://github.com/mvanhorn/last30days-skill) (MIT) |
| `ponytail-skills` | Write the least code that works; review and audit for over-engineering | While implementing, and when a diff feels bigger than the task | ~1k tokens always on, no hooks | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) (MIT) |

Built into Claude Code, nothing to install: `/design` for screen mockups and
layouts before building, `/dataviz` for charts, `/security-review` for a
security pass over pending changes. For product UI (dashboards, dense forms)
use `/design` first; `taste-skill` puts dashboards, admin panels and dense
product UI outside its scope and names a design system for them (Fluent,
Carbon, Atlassian, Polaris).

## Listed, not installed

| Plugin | What | When | Cost | Source |
| --- | --- | --- | --- | --- |
| `ponytail` | The full ponytail plugin with its hooks | Only if you want ponytail enforced every turn | 3 hooks, ~1k tokens | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) (MIT) |
| `impeccable` | A design with a point of view; writes a product record (`PRODUCT.md`) and a design record (`DESIGN.md`) | A page that should be remembered, when you will answer its questions: five of them and 43 minutes on the page where `taste-skill` asked none and took five (one measurement, 2026-09-12) | Hooks, agents and skills written into the repository (`.claude/`, `.github/`); no plinth pin | [pbakaus/impeccable](https://github.com/pbakaus/impeccable) (Apache-2.0) |

`ponytail` installs with `claude plugin install ponytail@plinth`. Impeccable is
not in plinth's marketplace: run `npx impeccable install` from the project
root, which writes the hooks, agents and skills above into the repository. Its
own marketplace plugin loaded hooks and agents but did not register its skill
on Claude Code 2.1.269.

Every third-party entry is pinned to a commit in this repository's
`.claude-plugin/marketplace.json`; the licenses are listed in `NOTICE`.
