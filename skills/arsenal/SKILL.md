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
point them to it when they ask what to type next. To find a tool by the
step of that loop and the concern (a wrong problem, a false green, lost
state), use "By step and concern" below; "How a tool gets on this list" says
why each one is here.

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

## By step and concern

The second way in: find the step of the loop in
`${CLAUDE_PLUGIN_ROOT}/docs/how-to/run-a-project.md`, then the concern (Value,
Use, Health, Proof, Flow, Safety, Memory, Stewardship), then the problem. Who
invokes it: **person** (typed; a user-only skill, invisible to the agent),
**agent** (picked from its description), **commit** (Claude Code's commit
instruction runs a project skill named `verify` or `simplify`), **text** (the
generated repository's own text, no skill). Evidence is what the recorded runs
show (U1, U2, RC1, RC2, #302, #403, #458, #467, #469; #475 has the sources):
"0" means none of those runs called it, not that it does not help. The runs
were small, short and one person's; in every one the generated repository
text, not a typed skill, carried steps 2, 4, 7 and 8.

### 1 Start, and after the first merge

| Concern | Problem | Tool | Who | How to use it | Evidence |
| --- | --- | --- | --- | --- | --- |
| Safety | A repository without the wall | `/plinth:new-project` | person | Type `/` and pick it; give `<owner>/<name>` | typed 4 |
| Health | An existing repository missing the floor | `/plinth:floor-check` | agent or person | Ask "is this repository set up?", or type it | 0 |
| Safety | An agent token that can rewrite the checks or the ruleset | The token how-to; candidate `wizard` | person; `wizard` agent | run-a-project.md, "Give the agent a token"; ask the agent to walk you through it | #403 record 1, one loop on that token; `wizard` no evidence yet |
| Safety | Production data, spend, restore, open data | The four things by hand; candidate `wizard` | person; `wizard` agent | run-a-project.md, "Set four things by hand" | 0; effect not measured (#402); `wizard` no evidence yet |

### 2 Shape

| Concern | Problem | Tool | Who | How to use it | Evidence |
| --- | --- | --- | --- | --- | --- |
| Value | The wrong problem built | `/grill-with-docs` (calls `grilling`, `domain-modeling`) | person | Type it with the idea before any code | 0; the generated text asked instead (U1 six questions, RC1 one, U2 one) |
| Proof | A "done" nobody can see | The one rule; the template's "Done means" field (#299) | text | Write in the issue what you will look at to call it done | followed via text (U1, RC1) |
| Value | A question code or a source can settle first | `prototype`, `research` | agent | Say "prototype it first" or "research this" | 0 |

### 3 Plan

| Concern | Problem | Tool | Who | How to use it | Evidence |
| --- | --- | --- | --- | --- | --- |
| Flow | A job too big for one session | `/to-spec`, `/to-tickets`; `/wayfinder` when the way is unclear | person | Type `/to-spec`, then `/to-tickets` on the spec | 0; no run needed it |

### 4 Build

| Concern | Problem | Tool | Who | How to use it | Evidence |
| --- | --- | --- | --- | --- | --- |
| Flow | Context degraded by a long session | `/clear`, one ticket per session (built in) | person | `/clear` between tickets | not recorded |
| Proof | Code with no test that pins it | `/implement` (calls `tdd`, `code-review`) | person; `tdd` agent | Type `/implement #N` | 0 and 0; tests first via text (U2, RC1, #302 27 of 27) |
| Proof | A plausible change that misses a case | `code-review` | agent | Ask for a review of the change | 1 (U1, after the person asked) |
| Health | Scaffolding or reshuffling the change did not need | The template's `simplify` | commit | Nothing to type; runs before a code commit | Sonnet 5.5 1 of 18, Opus 5.5 6 of 6 (#467); #474 open |
| Proof | A commit over a red or wrong check | The template's `verify` | commit | Nothing to type; runs before a code commit | 5 of 6 (#458); on Sonnet 5.5 1 of 5 and 2 of 16, Opus 5.5 6 of 6 (#467); #474, #476 open |
| Use | A page that looks templated | `design-taste-frontend` | person names it | Say so in the ticket, or type `/design-taste-frontend` | 1 named (U2); 0 unnamed on a rendered repository (#469) |
| Flow | A merge or rebase conflict | `resolving-merge-conflicts` | agent | Say "resolve the conflict" | 0; none arose |

### 5 Check

| Concern | Problem | Tool | Who | How to use it | Evidence |
| --- | --- | --- | --- | --- | --- |
| Proof | A green that did not check the property | The required checks; the three questions | CI; person | Ask run-a-project.md's three questions of every green | every run; each recorded false green was caught by the person looking (U1 23, 26; U2 13; #403 record 3) |
| Use | Can I see it running | Built-in `/run`; the built-in `/verify` is shadowed by the template's (#476) | person or agent | Type `/run`, or ask to see it running | `run` 1 (U2) |
| Proof | What no check asserts | `third-party / review` | CI | Turn on the reviewer (configure-the-third-party-reviewer.md) | off in the observed runs |

### 6 Merge, 7 Break, 8 Resume

| Step | Concern | Problem | Tool | Who | How to use it | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| 6 | Safety | The agent merging unasked | The rule in the generated `AGENTS.md` | text | Merge yourself, or say so each time | RC1 merged unasked twice; RC2, #403 asked |
| 7 | Proof | A fix with no reproduction, or one that weakens a check | `diagnosing-bugs` | agent | Say "diagnose this" with the report | 0; reproduce-first via text (U1, U2, RC1) |
| 7 | Flow | Issues other people open | `/triage` | person | Type it on the new issues | 0; no outside issue arrived |
| 8 | Memory | State lost with the chat or the machine | The record; ask "where is this, what's next" | text | Ask it in a new session | met 4 of 4 (U1, U2, RC1, #403) |
| 8 | Memory | Work moving to another tool or person | `/handoff` | person | Type it before you stop | 0; none moved |

### 9 Healthy, and any step

| Step | Concern | Problem | Tool | Who | How to use it | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| 9 | Safety | Vulnerable or stale dependencies | Dependabot and the checks | automatic | Merge its pull requests on green | U2, RC1 |
| 9 | Stewardship | Drift behind the template | `/plinth:floor-check`, `/plinth:template-update` | person | `floor-check` reports it; type `/plinth:template-update` to apply | 0; no project crossed a release |
| 9 | Stewardship | Code that grew more than it needs | `/ponytail-audit` | person | Type it every week or two | 0 |
| 9 | Health | Shallow modules, hard-to-test seams | `/improve-codebase-architecture` (uses `codebase-design`) | person | Type it after a burst of work | 0 |
| Any | Flow | Which skill now | `/ask-matt` | person | Type it with where you are | 0 |
| Any | Use | An answer that did not land | `/wait-what` | person | Type it after the answer | 0 |
| Any | Use | Which tool for a concern | `/plinth:arsenal` | agent or person | Ask, or type it | 3 agent, 2 typed |

No tool answers these three yet, and no recorded run shows the cost of the gap:

| Concern | Problem |
| --- | --- |
| Value | What shipped, held against what was asked |
| Stewardship | The end of a project: data, keys, users told, who takes over |
| Health | How the work went, for the next round |

## How a tool gets on this list

Four criteria (#475) for the plugins and skills plinth installs or lists.
Every one of those meets them, or is named below with why. The other rows name
what plinth does not select: Claude Code's built-ins (`/clear`, `/run`), the
generated repository's text and its `verify` and `simplify` skills (shipped by
plinth-template at a release tag), the required checks, `third-party / review`
and Dependabot. They are the wall or the platform, and the criteria do not
apply to them.

1. **It fills a gap.** It serves a row above: a step's problem that no other
   listed tool, and not the generated repository text alone, already answers.
2. **Its cost is stated and bounded.** Tokens always loaded (a model-invocable
   skill's description is in every session's listing; a user-only skill's is
   not), tokens per call, hooks (none in the default set), run time, install
   scope, and development dependencies it adds to a repository; measured, not
   estimated.
3. **It is pinned and licensed.** A full commit SHA in plinth's marketplace,
   raised by pull request; its licence recorded in `NOTICE` and the Source
   column.
4. **Its place is chosen.** The default set holds a tool that serves a step
   every project walks and costs no hook; everything else is listed, not
   installed. A tool outside the plugin system is only ever listed.

Named exceptions:

- **Two tools on one row** (criterion 1): `/plinth:floor-check` reports drift
  and `/plinth:template-update` applies it; `/to-spec` writes the spec,
  `/to-tickets` cuts it and `/wayfinder` is for when the way itself is unclear;
  `prototype` settles a question in code and `research` in sources.
- **The generated text already carried the step** (criterion 1):
  `/grill-with-docs`, `/implement` and `diagnosing-bugs` stay for the
  safeguards run-a-project.md describes at their steps, with evidence 0 until a
  run records a call.
- **No evidence yet** (criterion 1): `wizard`, a candidate on the two "after
  the first merge" rows.
- **Cost measured only in part** (criterion 2): `mattpocock-skills` and
  `ponytail-skills` state their share of the listing, measured; their tokens
  per call and run time are not measured yet. Impeccable's cost is stated as
  what it writes into the repository, not in tokens.
- **Not pinned by plinth** (criterion 3): Impeccable, listed with its own
  installer, which writes into the repository.
- **Listed, not installed** (criterion 4): `last30days` and `ponytail` run
  hooks; Impeccable is outside plinth's marketplace.
