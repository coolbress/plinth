# Arsenal: why each tool, and the evidence

For maintainers. `skills/arsenal/SKILL.md` and the files beside it are what an
agent reads to choose a tool; they carry no issue numbers, which mean nothing
on a user's machine. This page holds what they were built from: the coverage
of each step by concern, the evidence each tool has, the criteria a tool meets
to be installed or listed, and the measurements behind the cost columns, with
the issues that recorded them.

## Contents

- [By step and concern](#by-step-and-concern)
- [How a tool gets on the list](#how-a-tool-gets-on-the-list)
- [What the cost columns were measured on](#what-the-cost-columns-were-measured-on)
- [What left the arsenal's rows](#what-left-the-arsenals-rows)

## By step and concern

Reference. Find the step of the loop in
`${CLAUDE_PLUGIN_ROOT}/docs/how-to/run-a-project.md`, then the concern, then
the problem. The eight concerns (Value, Use, Health, Proof, Flow, Safety,
Memory, Stewardship) are the maintainers' coverage check, a way to see which
concern no tool covers yet at a step, not a question to put to the person. Who
invokes it: **person** (the person types it or does it; a user-only skill is
invisible to the agent), **agent** (picked from its description), **commit**
(Claude Code's commit instruction asks the agent to run a project skill named
`verify`; the agent may skip it), **text** (the generated
repository's own text, no skill). Evidence is what the recorded runs
show (U1, U2, RC1, RC2, #302, #403, #458, #467, #469, #474, #496; #475 has the sources):
"0" means none of those runs called it, not that it does not help. The runs
were small, short and one person's; in every one the generated repository
text, not a typed skill, carried steps 2, 4, 7 and 8.

### 1 Start, and after the first merge

| Concern | Problem | Tool | Who | How to use it | Evidence |
| --- | --- | --- | --- | --- | --- |
| Safety | A repository without the wall | `/plinth:new-project` | person | Type `/` and pick it; give `<owner>/<name>` | typed 4 |
| Health | An existing repository missing the floor | `/plinth:floor-check` | agent or person | Ask "is this repository set up?", or type it | 0 |
| Safety | An agent token that can rewrite the checks or the ruleset | The token how-to | person | `${CLAUDE_PLUGIN_ROOT}/docs/how-to/give-the-agent-a-token.md` | #403 record 1, one loop on that token |
| Safety | Production data, spend, restore, open data | The four things by hand | person | `${CLAUDE_PLUGIN_ROOT}/docs/how-to/set-four-things-by-hand.md` | 0; effect not measured (#402) |

### 2 Shape

| Concern | Problem | Tool | Who | How to use it | Evidence |
| --- | --- | --- | --- | --- | --- |
| Value | The wrong problem built | `/grilling`, with `domain-modeling` for `GLOSSARY.md`; `/grill-with-docs` (listed) runs both | person | Type it with the idea before any code | 0; the generated text asked instead (U1 six questions, RC1 one, U2 one) |
| Proof | A "done" nobody can see | The one rule; the template's "Done means" field (#299) | text | Write in the issue what you will look at to call it done | followed via text (U1, RC1) |
| Value | A question code or a source can settle first | `prototype`, `research` (listed) | agent | Say "prototype it first" or "research this" | 0 |

### 3 Plan

| Concern | Problem | Tool | Who | How to use it | Evidence |
| --- | --- | --- | --- | --- | --- |
| Flow | A job too big for one session | `/to-spec`, `/to-tickets`; `/wayfinder` when the way is unclear | person | Type `/to-spec`, then `/to-tickets` on the spec | 0; no run needed it |

### 4 Build

| Concern | Problem | Tool | Who | How to use it | Evidence |
| --- | --- | --- | --- | --- | --- |
| Flow | Context degraded by a long session | `/clear`, one ticket per session (built in) | person | `/clear` between tickets | not recorded |
| Proof | Code with no test that pins it | `/implement` (calls `tdd`, `code-review`) | person; `tdd` agent | Type `/implement #N` | 0 and 0; tests first via text (U2, RC1, #302 27 of 27) |
| Proof | A plausible change that misses a case | A fresh-context review: a new subagent given only the diff, the issue's criteria and the Code Review Rules (the default, from the template's `AGENTS.md`); `code-review`, run by the authoring session, not independent | agent | Nothing to type: `AGENTS.md` asks the agent to run it before the pull request (template v1.38.0), and the agent may skip it; ask "which review ran?" | `code-review` 1 (U1, after the person asked); fresh-context: one trial on a docs change, 4 findings, 2 of them not in the same-session review, which had 6 the fresh one did not (#808) |
| Health, Proof | Scaffolding or reshuffling the change did not need; a commit over a red or wrong check | The template's `verify`, its cleanup step and its check of the commit | commit | Nothing to type: Claude Code asks the agent to run it before a code commit, and the agent may skip it; check the commit | The check: 5 of 6 (#458); on Sonnet 5.5 0 of 10 beside `simplify` (#474). The cleanup: on Sonnet 5.5 0 of 5 before. Both as one skill with shell writes refused: Sonnet 5.5 4 of 5, Opus 5.5 5 of 5 (#496) |
| Use | A page that looks templated | `frontend-design` (#1082) | person names it | Say so in the ticket, or type `/frontend-design` | Not run yet for `frontend-design`; `design-taste-frontend`, the skill it replaced: 1 named (U2), 0 unnamed on a rendered repository (#469) |
| Flow | A merge or rebase conflict | No tool: ask the agent to show both sides of each conflict and say which to keep | person | Ask the agent to show both sides of each conflict and say which to keep | 0; none arose; `resolving-merge-conflicts` was removed upstream in v1.3.2 (#714) |

### 5 Check

| Concern | Problem | Tool | Who | How to use it | Evidence |
| --- | --- | --- | --- | --- | --- |
| Proof | A green that did not check the property | The required checks; the three questions | CI; person | Ask the three questions of `${CLAUDE_PLUGIN_ROOT}/docs/how-to/run-a-project.md`, step 5, of every green: "What shows it works, and what did you not check?", "Can I see it?", "What did the reviewer say?" | every run; each recorded false green was caught by the person looking (U1 23, 26; U2 13; #403 record 3) |
| Safety | An injection, log-in or data-exposure risk in the change | `/security-review` (built in) | person | Type it before you merge: it reads the diff against `origin`'s default branch, so it needs an `origin` remote; the required CodeQL check still runs | 0 |
| Use | Can I see it running | Built-in `/run`; the built-in `/verify` is shadowed by the template's (#476) | person or agent | Type `/run`, or ask to see it running | `run` 1 (U2) |
| Proof | What no check asserts | `third-party / review` | CI | Turn on the reviewer (configure-the-third-party-reviewer.md) | off in the observed runs |
| Use | A `web` page that some people cannot use: no label, too little contrast, a slow load | `ci / web-audit`: Lighthouse CI and axe-core on `/` and the log-in page; reports, never fails, required by no ruleset | CI | Nothing to type on a `web` project: read the job's summary on the pull request. Automated checks catch only part of accessibility, so also try the page with the keyboard alone and a screen reader | 0; no recorded run had it (#709) |

### 6 Merge, 7 Break, 8 Resume

| Step | Concern | Problem | Tool | Who | How to use it | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| 6 | Safety | The agent merging unasked | The rule in the generated `AGENTS.md` | text | Merge yourself, or say so each time | RC1 merged unasked twice; RC2, #403 asked |
| 7 | Proof | A fix with no reproduction, or one that weakens a check | `diagnosing-bugs` | agent | Say "diagnose this" with the report | 0; reproduce-first via text (U1, U2, RC1) |
| 7 | Flow | Issues other people open | `/triage` | person | Type it on the new issues | 0; no outside issue arrived |
| 7 | Health | Claude Code itself misbehaving, not the app | `/doctor` (built in); `/debug` (built in) is for Claude Code itself, not the app | person | Type `/doctor` for a checkup of the install, settings, extensions and `CLAUDE.md`; never `/debug` for a bug in the app | 0 |
| 8 | Memory | State lost with the chat or the machine | The record; ask "where is this, what's next" | text | Ask it in a new session | met 4 of 4 (U1, U2, RC1, #403) |
| 8 | Memory | Coming back on the same machine | `/resume` and `/recap` (built in, same machine only) | person | `/resume` returns to an earlier conversation, `/recap` says this one in a line; across machines the issues and pull requests stay the record | 0 |
| 8 | Memory | Work moving to another tool or person | `/handoff`; it writes a temporary file whose path the next session needs, so the issue and pull request stay the first record | person | Type it before you stop | 0; none moved |

### 9 Healthy, and any step

| Step | Concern | Problem | Tool | Who | How to use it | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| 9 | Safety | Vulnerable or stale dependencies | Dependabot and the checks | automatic | Merge its pull requests on green | U2, RC1 |
| 9 | Stewardship | Drift behind the template | `/plinth:floor-check`, `/plinth:template-update` | person | `floor-check` reports it; type `/plinth:template-update` to apply | 0; no project crossed a release |
| 9 | Stewardship | Code that grew more than it needs | `/ponytail-audit` (listed) | person | Type it every week or two | 0 |
| 9 | Health | Shallow modules, hard-to-test seams | `/improve-codebase-architecture` (uses `codebase-design`); the hardest for a beginner: engineer vocabulary, a design interview, an HTML report | person | Type it after a burst of work | 0 |
| After | Health | How the work went, for the next round | `/retro` (calls `writing-for-agents`) | person | Type it in the session you are looking back on, before `/clear`; it suggests rules and checks, and you choose which to keep | 0; new in #714 |
| After | Health | Where recent sessions go wrong | `/insights` (built in) | person | Type it for an HTML report of recent sessions on this machine; not in cloud sessions | 0 |
| Any | Flow | Which skill now | `/plinth:guide` (user-only: the agent asks the person to type it) | person | Type it in the project's folder | 0; `/ask-matt` was here until #1086: it routes to skills plinth does not carry (#593) |
| Any | Use | An answer that did not land | `/wait-what` (listed) | person | Type it after the answer | 0 |
| Any | Use | Which tool for a concern | `/plinth:arsenal` | agent or person | Ask, or type it | 3 agent, 2 typed |

No tool answers this one yet, and no recorded run shows the cost of the gap:

| Concern | Problem |
| --- | --- |
| Value | What shipped, held against what was asked |

## How a tool gets on the list

Four criteria (#475) for the plugins and skills plinth installs or lists:
what a tool has to show to be added or kept. The exceptions below are the
known gaps, not a certificate that every other tool was checked against every
criterion; `last30days` and Impeccable, for instance, are listed for rows
`research` and `frontend-design` also answer. The other rows name
what plinth does not select: Claude Code's built-ins (`/clear`, `/run`,
`/security-review`, `/resume`, `/recap`, `/insights`, `/doctor`), the
generated repository's text and its `verify` skill (shipped by
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
  `/implement` and `diagnosing-bugs` stay installed for the safeguards
  run-a-project.md describes at their steps, with evidence 0 until a run
  records a call.
- **A name shared with a built-in** (criterion 1): `code-review`, kept
  because `/implement` calls it by name (above).
- **Cost measured only in part** (criterion 2): every entry's share of the
  listing and its hooks are measured, but tokens per call are measured only
  for `taste-skill` (the page-design skill before #1082) and `last30days`, and
  run time only for `last30days`'s
  hook. For the rest, `ponytail`'s "~1k tokens" included, the Cost column is
  the part measured so far. Impeccable's cost is stated as what it writes into
  the repository, not in tokens.
- **Not pinned by plinth** (criterion 3): Impeccable, listed with its own
  installer, which writes into the repository; `claude-security` and
  `sentry`, listed with the official marketplace's install line, which pins
  `sentry` and serves `claude-security` from its own tree.
- **Listed, not installed** (criterion 4): `last30days`, `ponytail` and
  `claude-security` run hooks; Impeccable and `sentry` are outside plinth's
  marketplace, and `sentry` needs a Sentry account; `mattpocock-skills-extra`
  runs none; #520 moved its skills here on these four criteria and their
  measured cost, since no run compared a set with them and one without, and
  `/ask-matt` routes to them (#593); #702 moved five of them back into the
  default set (#704), user-only skills for planning, clean-up and handoff
  that cost nothing in the listing; #714 added `/retro`, user-only, with
  `writing-for-agents`, which the agent can call by itself and so is in the
  listing;
  `ponytail-skills` runs none, but `/ponytail-audit` had no call in any
  recorded run (#520), and #594 measured that dropping the dependency while
  the entry stays leaves an installed plinth working.

## What the cost columns were measured on

The skill-listing share in `skills/arsenal/installed.md`:

"Always on" is each plugin's share of the skill listing, as `/context`
reports it with a 1M-context model (#255, again for #354, #468, #469 on an
installed default set, #477 with each plugin loaded as the catalog narrows
it, #593 on an installed default set after `claude plugin update`, #598
after `claude plugin update` and `claude plugin prune`, #704 before and
after the five user-only skills joined, which left it unchanged, and #714
before and after the raise to mattpocock/skills v1.3.2, on a fresh install
and on an update, where `writing-for-agents` added ~50). With
plinth's own two listed skills (~0.27k) the set comes to ~0.91k; it was
~0.87k before #908 named `/plinth:guide` in this catalog's description
(~80 to ~120 for it), ~0.82k before #714, ~0.97k before #598 listed `ponytail-skills` and ~1.28k before #593 listed
twelve `mattpocock-skills` skills. Claude Code caps the listing, built-in skills
included, at 1% of the context window. At 1M that leaves room for all of it.
At 200k the cap is ~2k, and on Haiku 4.5, the 200k model measured for #469
and #477, 9 of the 14 descriptions the default set had then were cut to under 20 tokens, about
the skill's name, because the built-in skills share the same cap. For #704
two were still cut (`code-review`, `design-taste-frontend`), six with
`mattpocock-skills-extra` installed. For #714, `writing-for-agents` (~40 at
200k) pushed the built-in `security-review` under 20 as well, and with the
extra plugin installed it was cut itself. Setting `skillListingBudgetFraction` to
0.015 in a repository's `.claude/settings.json` left none cut, for ~0.2k more
tokens always on at 200k (~0.4k with the extra plugin) and none at 1M, measured
again for #714 (2.1k before the raise, 2.2k after; 2.4k with the extra
plugin both times); plinth-template sets it from the release after v1.28.0
(coolbress/plinth-template#138).

`code-review` is the one installed skill that shares its name with a Claude
Code built-in: `/code-review` there reviews the diff for bugs at a chosen
effort, and `mattpocock-skills:code-review` reviews it against the
repository's standards and the issue's spec. A session lists both. plinth
keeps the plugin's because `/implement` calls `/code-review` by name when it
finishes a ticket (#520).

What changed for you with mattpocock/skills v1.3.2 (#714), where you can
see it:

- The glossary file is `GLOSSARY.md`, no longer `CONTEXT.md`; the skills read
  and write the new name. `/plinth:template-update` renames a project's file,
  its content kept.
- `/implement #N` first fetches the ticket and says its title; given an
  unclear reference, it asks which one.
- `tdd` gives each place it proposes to test a one-line note on what a test
  there catches and what it misses.
- `diagnosing-bugs`, when it breaks code on purpose to see a test fail,
  checks against an untouched copy that the change really happened before
  trusting the failure.
- `grilling` words each question so that "yes" accepts its recommended
  answer.
- `/to-tickets`, cutting up an existing issue, makes each ticket a sub-issue
  of it, and leaves out "Blocked by" when the blocking is set as links.
- `/wayfinder` gives the map and its tickets only `wayfinder:` labels, never
  `ready-for-agent`; writes cross-references with real issue numbers; pushes
  research branches without opening a pull request; and reads a ticket's
  type from its label.

Where the other facts in `skills/arsenal/installed.md` and `listed.md` come from:

- `taste-skill` not reached for on its own on a rendered repository: one run, #469.
- `/debug` never offered for the app, and the built-ins placed in the table: #1080.
- The `ponytail-skills` pin held before v5: #711, #715; it left the default set in #598.
- The six of `mattpocock-skills-extra` beside the default set's skills, none
  twice: measured for #593, again for #704 after five moved back, and for #714.
- The counts of installed, listed and neither: #520, #593, #704, #714; the
  skills in neither: #475, #477, #714.
- `claude-security` and `sentry`, read on their repositories on 2026-11-24: #1080.

## What left the arsenal's rows

- `wizard` left the first-merge row, the two "after the first merge" safety
  rows above and the selection note in #1086 (2026-11-26). No recorded run
  called it: neither record, #643 nor #799, names it; #475 named it a
  candidate with no evidence; and #520's 130 headless runs made no call to it.
  It stays in `mattpocock-skills-extra`'s list.
- `/ask-matt` left the "Unsure which skill now" row and the "Which skill now"
  row in #1086: it routes to skills plinth does not carry (#593), and
  `/plinth:guide` is the one that reads the project. It stays in
  `mattpocock-skills-extra`'s list.
- The merge-conflict row names no tool: `resolving-merge-conflicts` was
  removed upstream in mattpocock/skills v1.3.2 (#714), and the plain
  instruction does the job.
- The end of a project left "No tool answers" in #1086: the template's issue
  form "End or hand over this project" answers it, and the table's end row
  names it.
- In #1086's second part (2026-11-27) the "Where you are" table took six
  columns, Trigger, Tool, Class, plinth piece, Also and Then, with one tool
  per job and at most one alternative. What the guide says of each step
  (Next action, How to use it, It leaves) moved to `skills/guide/steps.md`,
  which `scripts/guide-state.sh` joins to the table by the step's name. These
  left the rows, each still in its plugin or in Claude Code:
  - `domain-modeling` and `/grill-with-docs` (listed) on the idea row:
    `/grilling` is its one tool; `domain-modeling`, which keeps
    `GLOSSARY.md`, stays installed and `installed.md` names it. `/design` moved here from the build row as the
    idea row's Also, with its two conditions from Claude Code's commands
    reference (read 2026-11-26, and again 2026-11-27).
  - `/wayfinder` became the plan row's Also, for when the way is unclear.
  - `/debug` left "Something broke": it debugs Claude Code, and `/doctor` is
    the row's one tool for Claude Code itself; `installed.md` keeps the
    warning that it is not for the app.
  - `/ponytail-audit` (listed) left "Between pieces of work";
    `/improve-codebase-architecture` is that row's Also. Both stay where
    they were, in `listed.md` and `installed.md`.
  - The build row's Also is `/simplify`, and so is the check row's: cleanup
    of the changed code. Its plinth piece names the project's `verify`
    skill: Claude Code's commands reference (read 2026-11-27) lists a
    bundled `/verify` that builds and runs the app, and the template's
    `verify` takes its place on purpose and says so, keeping the name its
    commit-time instruction uses (coolbress/plinth-template#66, "Not
    building").
