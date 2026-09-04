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

## Installed by default

| Plugin | What | When | Cost | Source |
| --- | --- | --- | --- | --- |
| `mattpocock-skills` | Planning, specs, tickets, TDD, code review, domain modelling | Any change bigger than a typo; start with `/ask-matt` | ~1.6k tokens always on | [mattpocock/skills](https://github.com/mattpocock/skills) (MIT) |
| `frontend-design` | Design direction for landing pages and app screens | "Make this screen look good"; it decides direction when the brief is vague | ~70 tokens always on | [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/frontend-design) (Apache-2.0) |
| `last30days` | What people said about a topic in the last 30 days | Finding candidates and recent reactions. Not for deciding; verify with `/research` | ~100 tokens always on, ~90k per call | [mvanhorn/last30days-skill](https://github.com/mvanhorn/last30days-skill) (MIT) |
| `ponytail-skills` | Write the least code that works; review and audit for over-engineering | While implementing, and when a diff feels bigger than the task | ~1k tokens always on, no hooks | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) (MIT) |

Built into Claude Code, nothing to install: `/design` for screen mockups and
layouts before building, `/dataviz` for charts, `/security-review` for a
security pass over pending changes. For product UI (dashboards, forms) use
`/design` first and `frontend-design` while building.

## Listed, not installed

Install with `claude plugin install <name>@plinth`.

| Plugin | What | When | Cost | Source |
| --- | --- | --- | --- | --- |
| `ponytail` | The full ponytail plugin with its hooks | Only if you want ponytail enforced every turn | 3 hooks, ~1k tokens | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) (MIT) |

Every third-party entry is pinned to a commit in this repository's
`.claude-plugin/marketplace.json`; the licenses are listed in `NOTICE`.
