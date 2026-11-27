# How to run a project with plinth

You say what you want and an AI agent writes the code, whether or not you
can read it yet. This page is the loop, nine steps from an idea to a merged
change, after [Getting started](../tutorials/getting-started.md).

Each step says where you are, the next action, what to look at, what is
yours to decide, and whether the step holds if you forget it (plinth's issue [#515](https://github.com/coolbress/plinth/issues/515)):

- **default**: it happens unless someone changes it;
- **boundary**: GitHub or Claude Code refuses to go past it;
- **guidance only**: the agent is asked to follow it, and nothing stops a
  step that is skipped.

If you remember one command, make it `/plinth:guide`, typed: it reads the
repository and says, in your language and in plain words, where the project
is now and the one command to type next, then what is open and what happened
so far; before your first pull request is merged, also how to use the tools
of this step and the next. `/plinth:guide map` shows the whole way on one
screen, marking where you are and what is done, worth reading once before your
first pull request is merged; `/plinth:guide map <step>` explains one step in
depth, and `/plinth:guide features` lists what started off.
`/plinth:arsenal` is the catalog behind it, answered from a task without
reading the project: every tool, what it costs and how to install it.

## The one rule: say what proves it

Every "done" needs something you can see and check yourself, whether or not
you read the code: a command's output, a page, a number you can check by hand,
or a test's name that says what it checks. Ask for it in the interview, find
it in each ticket, and look for it in the pull request before you merge. For
example: *"Done means: with my sample file, it prints 33,000 won for
September, and the next payment dates in order."*

## The loop

```text
 start ─► first pull request merged ─► the agent's token (then, recommended: its account, four things by hand)
                                                           │
 ┌─────────────────────────────────────────────────────────┘
 ▼
 shape the idea ─► (plan in tickets) ─► build one ticket ─► checks answer
                                                                 │
   next ticket ◄─ you say "merge" ◄─ you check what they cannot ◄┘
                                          │
            something broke? ─► reproduce, then fix ─► back into the loop
```

### 1. Start

- **Where you are:** plinth is installed; no repository yet, or one plinth
  did not make.
- **Next:** type `/plinth:new-project <owner>/<name>`. It creates the
  repository and a first pull request. For a repository you already have, ask
  for `/plinth:floor-check`: it lists what is missing and changes nothing.
- **Look at:** the first pull request's checks; merge it once they are green
  ([the tutorial](../tutorials/getting-started.md#merge-the-first-pull-request)
  has the command), then `git switch main && git pull` in the repository's
  folder: the generator left the checkout on the pull request's branch.
- **Yours:** the name, and that first merge.
- **If you forget:** a boundary once it exists: the required checks and the
  ruleset are on GitHub, beyond an agent without administration.

Then, before step 2, only [the agent's token](give-the-agent-a-token.md),
ending with every other credential off the machine: until it is done, the
agent can still change the checks. After it, strongly recommended but not in
the way of step 2, in this order; until each is done, its protection is
missing:

1. [Its own account](give-the-agent-its-own-account.md), whose step 6 removes your own login, the token included.
2. [The four things by hand](set-four-things-by-hand.md).

Once the token is done, type `/run-skill-generator` once: built into Claude
Code, it writes the project a skill of its own that teaches `/run` to build,
launch and drive the app, beside the template's `verify`, which it leaves as
it is. Its skill goes in through a pull request like any change: in the trial
a `web` project's driver printed its throwaway password, and CodeQL's
required check blocked the merge
([#1084](https://github.com/coolbress/plinth/issues/1084)).

An uptime monitor and an error tracker wait for the first deploy: the
four-things page's [after the first
deploy](set-four-things-by-hand.md#after-the-first-deploy) names them, with
the data's off-host copy and the bill to expect.

A `web` project also needs a place to run:
[choose where a web app runs](choose-where-a-web-app-runs.md). Render is the
one plinth builds and checks.

#### Give the agent a token that cannot change the checks

Without it, the agent's login can push a change under `.github/workflows/`
that turns every check green, and edit or delete the ruleset. With it,
GitHub refuses both: a boundary, for pushes over HTTPS.

#### Give the agent its own account

Without it, the agent works under your account, which can merge: "ask before
you merge" is guidance only. With it, GitHub refuses the agent's merge: a
boundary.

#### Set four things by hand that no check covers

Production data kept out of the agent's session, a spend limit wherever a
paid service has one, a restore tried once, private data tried from outside;
after the first deploy, an uptime monitor and an error tracker. No check can
see these: guidance only.

### 2. Shape the idea: `/grilling`

- **Where you are:** an idea in your own words. A typo can go straight to a
  pull request; anything bigger starts here.
- **Next:** type `/grilling` with the idea. The agent interviews you,
  looks up facts itself and brings you only decisions, then opens an issue
  saying what "done" means (several sessions' work: step 3 first). When the
  idea is a page people look at, such as a landing page, `/design` (built
  in) sketches it as screen mockups on a canvas, before or beside the
  interview; `/grilling` still writes the issue.
- **Look at:** that you both mean the same thing. Have it put the agreed
  words into `GLOSSARY.md`, and a hard-to-reverse trade-off under `docs/adr/`
  (`domain-modeling`; `/grill-with-docs`,
  [listed](#skills-plinth-lists-but-does-not-install), does both).
- **Yours:** the answers; "I don't know, recommend one" is valid. Push back
  at least once, and say what is out of scope and what proves it done. When
  the idea is the project itself (what it is for and who uses it, usually the
  first interview), also settle who else is affected; the limits of cost and
  risk, and the outside rules (law on data and accessibility, the services'
  terms, licences); and how long it lasts, who takes it over, and how it ends
  (data deleted or handed over, keys revoked, users told), written in the
  README. A small change inside the project does not need them. Each was
  missing in two or three of the three recorded project runs, all trial
  projects ([#408](https://github.com/coolbress/plinth/issues/408)).
- **If you forget:** guidance only.

### 3. Plan a big job: a plan, then tickets

- **Where you are:** a shaped idea that takes more than one session.
- **Next:** ask the agent to write the plan into one issue, then cut it into
  small tickets that say which waits for which. `/to-spec` and `/to-tickets`
  do these as skills; `/wayfinder` is for a job you cannot yet see how to get
  through.
- **Look at:** each ticket: "what can I see when this one is finished?". Not
  cut by layer; a change across the whole codebase goes in safe batches.
- **Yours:** the cut. Keep the interview, the plan and the tickets in one
  session; `/compact` between two of them if it gets long, never mid-step.
- **If you forget:** guidance only.

### 4. Build one ticket: `/implement #N`

- **Where you are:** a ticket that says what "done" means.
- **Next:** `/clear`, then type `/implement #N`: one ticket per session. The
  agent writes a failing test first where it can, then the code, has it
  reviewed and commits; then a new subagent that never saw the session
  reviews the diff (what it is given: step 5), and the agent opens the pull
  request. For a page a person
  will look at, name `frontend-design` in the ticket or type
  `/frontend-design`; for dashboards and dense product UI, `/design` first.
- **Look at:** the commit and the pull request's description: that the
  description says which review ran and what it found, and that the `Assisted-by`
  line the repository's `CONTRIBUTING.md` asks for ends both the commit and
  the description, whose text becomes the squash commit's message at the
  merge. In one run the agent skipped both, and said so when asked
  ([#617](https://github.com/coolbress/plinth/issues/617)).
- **Yours:** when to stop. Corrected twice and still off: `/clear`, and say
  it again more precisely. The same correction again in a later session:
  [turn it into a rule](turn-a-correction-into-a-rule.md), a line, then a
  reviewer rule, then a test.
- **If you forget:** partly a boundary: the repository refuses a `cat`
  heredoc, `tee` and `sed -i`, so the agent writes code with its edit tools.
  Before a code commit, Claude Code tells the agent to run the repository's
  `verify` skill, a cleanup that keeps validation, safety and what the ticket
  asked for, then the checks: guidance only. In trials the refusal and one
  skill together raised how often one model ran it ([#496](https://github.com/coolbress/plinth/issues/496)); a skipped skill
  left out the package build, not the lint, type and test commands. Step 5's
  checks decide ([#474](https://github.com/coolbress/plinth/issues/474)).

### 5. Check what the checks cannot

- **Where you are:** a pull request with its checks running.
- **Next:** wait for the required checks: nine on GitHub (ten for
  `backend` or `data-ml`, twelve for `web`), with the code-scan rule beside
  them. Then ask the three questions:

  1. "What shows it works, and what did you not check?"
  2. "Can I see it?"
  3. "What did the reviewer say?"

  The reviewer, by default, is a fresh-context review the agent ran
  before opening the pull request: a new subagent given only the diff, the
  issue's acceptance criteria and the repository's Code Review Rules, never
  the conversation that wrote the change. In one study, a model judging code
  it had written in the same conversation let wrong or risky changes through
  more often than the same model reading them in a new context
  ([arXiv 2603.04582](https://arxiv.org/abs/2603.04582)). A project gets this
  default from plinth-template v1.38.0, in its `AGENTS.md`;
  the agent may still skip it, so ask which review ran. `/implement`'s
  `/code-review` is briefed and summed up by the session that wrote the
  change, so it is not independent; the optional third-party reviewer is the
  more independent one.
- **Look at:** the description, for each thing "done" meant. Run the
  command, open the page, or check a number; `/run` launches the app
  (`/verify` runs the checks, not the app, [#476](https://github.com/coolbress/plinth/issues/476)). If the optional third-party
  reviewer is on, each of its comments should end fixed, answered, or moved to
  an issue.
- **Yours:** whether what you saw is what "done" meant.
- **If you forget:** the checks are a boundary: nothing merges until they
  pass. They answer only their own questions (style, types, tests, packaging,
  secrets, dependencies, size, the title, the setup); a mistake no test looks
  for passes them all. The three questions are guidance only.

### 6. Merge on your word

- **Where you are:** green checks, seen working.
- **Next:** say "merge"; a yes covers that one pull request, unless you gave
  a standing instruction for the session. On the default path, the agent on
  your token, Claude Code may then ask you to approve the agent's
  `gh pr merge`: approving it is your merge. On the agent's own account that
  command is refused by the ruleset that lets only the admin merge: press the
  merge button in the browser, signed in as yourself. To merge yourself from a
  terminal on the default path, use the repository's squash command (its
  `CONTRIBUTING.md`, step 7); `<sha>` is the head you checked, from
  `gh pr view <n> --json headRefOid`:

  ```bash
  body="$(gh pr view <n> --json body --jq .body)" &&
    gh pr merge <n> --squash --match-head-commit <sha> --body "$body"
  ```

- **Look at:** the agent's decision report: who it works as, and the
  `not yet confirmed` lines ([below](#what-the-agent-tells-you-and-when)).
- **Yours:** the merge. The ticket closes by itself; take the next one.
- **If you forget:** guidance only on the default path; a boundary on the
  agent's own account. `/plinth:floor-check` says which one you have.

### 7. When something breaks

- **Where you are:** an error or wrong behaviour.
- **Next:** first, which kind it is.
  - **A merged change broke `main`** (the app, or `main`'s checks, broke
    after a merge): in this order.
    1. Undo the merge first, with the project's own
       `docs/how-to/undo-a-merged-change.md`: a revert pull request that goes
       through the same checks. The app stays broken while a fix is written;
       the revert does not.
    2. Restore data if the change lost or changed any. A `web` project: its
       README's "Where it runs" and the restore you tried in step 3 of
       [the four things by hand](set-four-things-by-hand.md). The other
       archetypes have no restore steps of their own.
    3. Reproduce and fix, as below.
    4. Leave a short incident note in the issue's Outcome when the incident
       lost data, needed a revert or reached users: what happened, what was
       done, what changes so it does not happen again, with no one blamed
       ([Google SRE book, chapter 15](https://sre.google/sre-book/postmortem-culture/)).
  - **A secret leaked** (a key in a commit, a log or an issue): revoke or
    rotate it at the service first; that is what stops its use. Rewriting
    history comes after, if at all: it is your own admin action, and it does
    not reach clones, forks or cached views
    ([removing sensitive data](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)).
  - **Something bad ran on this computer** (a bad package, a script): treat
    every credential your user account can read as gone, and work through
    [the revoke list](#if-something-bad-ran-on-this-computer) below.
  - **Anything else** (a failing check on an open pull request, an error):
    say `diagnose this: …` and show the agent the exact error and what you
    did before it. It makes a
    command that fails the same way, then, where a test can reach it, a test
    that fails for this bug, then fixes it.

  `/rewind` (built in) takes back what the agent just did in this session,
  files and conversation; it does not undo a merge, which is already on
  `main`. Issues someone else opened, and what users report: write it as an
  issue, then `/triage` sorts them (ready for the agent, needs you, needs
  more information, will not do); not for tickets your own plan made.
- **Look at:** the revert's checks when you undid a merge; the command or
  test failing before the fix, passing after.
- **Yours:** say no to a fix that switches off or weakens a check instead of
  fixing the code; the revoking and any history rewrite are yours.
- **If you forget:** guidance only; the fix still meets step 5's checks.

#### If something bad ran on this computer

Revoke or rotate, in this order:

1. The `gh` login and every GitHub token (`gh auth logout`, then the
   tokens on GitHub's settings page).
2. Other personal access tokens: other hosts, registries.
3. SSH keys: remove them from GitHub and every server, then make new ones.
4. The project's service and API keys: the host, the database, any paid API.
5. Cloud and npm credentials.

Then look, on GitHub: the account's security log; repositories nobody here
made; self-hosted runners nobody here added; authorised OAuth apps and
GitHub Apps. A 2025 attack on npm packages stole such tokens and made
repositories in the accounts it reached
([CISA, 2025-09-23](https://www.cisa.gov/news-events/alerts/2025/09/23/widespread-supply-chain-compromise-impacting-npm-ecosystem),
[Nx postmortem](https://nx.dev/blog/s1ngularity-postmortem)).

### 8. Stop, and come back later

- **Where you are:** stopping, or returning.
- **Next:** before you stop, have the plan, the decisions and what is left
  put in issues and pull requests; the chat ends. To come back, open a new
  session and ask "Where is this project, and what's next?", or type
  `/plinth:guide`. `/handoff`
  moves work to another tool, folder or person. It writes a temporary file
  whose path the next session needs, so the issues and pull requests stay
  the first record.
- **Looking back:** after a piece of work, and above all one that went
  wrong, type `/retro` in that same session before you clear it. It reads
  the session and suggests what to change for the next run, most serious
  first: a rule in `AGENTS.md`, a check that fails, a clearer pointer to a
  file. It changes nothing; put the ones you agree with in an issue. At the
  end of a project, the end-or-hand-over issue form asks the same questions.
- **Look at:** the answer, who it works as, and anything not verified.
- **Yours:** what to pick up next.
- **If you forget:** guidance only: what is not in an issue or pull request
  goes with the chat.

### 9. Keep it healthy

- **Where you are:** between pieces of work.
- **Next:** take dependency updates one pull request at a time, on green;
  one can pass the code-scan rule unscanned, which runs on `main` after the
  merge. When one stays red, read why in its failing check first. When one
  package in a group is the cause, take it out of the group with the
  group's `exclude-patterns` in `.github/dependabot.yml`, so it comes in a
  pull request of its own, and merge the rest; or regenerate what it
  changes on its branch, knowing Dependabot then stops rebasing that
  branch. `@dependabot ignore <name>`, on a group's pull request, is a
  lasting pin, undone only with `@dependabot unignore <name>`, not a way
  past one red run. The file's groups and cooldown are the project's to
  change: `/plinth:floor-check` checks only that it exists, and a template
  update keeps the project's lines unless the template changed the same
  ones. A project's `docs/how-to/keep-this-project-current.md` says the
  same, from plinth-template v1.45.0. After each plinth
  release, `/plinth:floor-check` says whether the repository is behind, and `/plinth:template-update` takes the update as a
  draft pull request. A project on GitHub rendered from template v1.39.0 or
  later also gets a monthly reminder when it is behind: an issue titled
  "Template update available: …". What to type for it is
  `/plinth:template-update`. A repository made before the merge ruleset gets
  [the command that adds it](give-the-agent-its-own-account.md#a-repository-made-before-the-merge-ruleset).
  A look back is due, and `/plinth:guide` says so, at whichever comes first
  since the last issue titled `Look back …` (or since the first merge): a
  version tag pushed, 10 `feat:` pull requests merged, or 30 days with at
  least one merge; never with nothing merged. 10 and 30 are starting values
  with no controlled study behind them. One tool per job, cheapest first:
  `/plinth:floor-check` for whether the floor is intact; `/insights` (built
  in) for the mix of work and a mistake the agent repeated; then, only when
  you want them, `/improve-codebase-architecture` for what to deepen and
  `/ponytail-audit`, [listed](#skills-plinth-lists-but-does-not-install),
  for what to cut. It leaves one issue, `Look back YYYY-MM-DD`, with a short
  answer to each of the seven questions the guide gives, and at most three
  tickets linked to it, each to finish within two days, for step 2 or 4.
  `/improve-codebase-architecture` is the hardest of
  the default skills for a beginner: it uses engineer vocabulary, runs a
  design interview and writes an HTML report.
- **Look at:** `/plinth:floor-check`'s report.
- **Yours:** each merge, and on a template conflict, which side: it
  recommends one per file and applies it only on your word.
- **If you forget:** the update pull requests are a default; taking them,
  and the template update you type, are guidance only.

## After a merge: release and deploy

What puts a merged change out depends on the kind of project: the row "A
merged change to put out" in
[the catalog's table](../../skills/arsenal/SKILL.md#where-you-are-and-what-to-do-next)
says it for each.

## What you type, and what runs by itself

Some skills run only when you type them:
[the list is in the catalog](../../skills/arsenal/SKILL.md#skills-only-the-person-can-start).
Asking in your own words
("update the template") does not run them: the agent may do the work by hand,
without their safeguards (`/plinth:new-project` tries to delete a repository
it could not finish; `/plinth:template-update` asks before each step), or not
at all. Type the skill.

### Skills plinth lists but does not install

What plinth lists but does not install, what each costs and the line that
installs it: [the arsenal's list](../../skills/arsenal/listed.md).

## What the agent tells you, and when

A repository `/plinth:new-project` made turns on the output style
`Beginner or non-engineer`: the same work, in plain words. A change ends with
an **Insight** block: what changed, why, what you can check and what is not
verified. At a merge, a template update or a failure, a decision report: what
changed; each check as `pass`, `fail` or `not yet confirmed`; what is unknown
(on GitLab, that no check is required by name); and what you decide, with the
option it recommends. It says which account it works as at the first task, a
resume and before a merge. A green check can carry a `not yet confirmed`
line: read those before you say "merge". Asking for an explanation is not
approving a change.

To turn the style off
for yourself, type `/output-style default`; it goes to
`.claude/settings.local.json`, kept out of commits; removing it brings the
style back. Set in your own `~/.claude/settings.json`, it did not turn the
style off ([#555](https://github.com/coolbress/plinth/issues/555)). A repository made before plinth-template v1.14.0 gets the style through
`/plinth:template-update`.

## Where plinth holds the line

The skills guide; they enforce nothing. Most are made by others, such as
[mattpocock/skills](https://github.com/mattpocock/skills); plinth chooses and
pins them, and their licences apply. An administrator, the agent too after the
browser login, can change the rules on GitHub, and any agent can rewrite the
CI file inside a pull request unless its token lacks workflow permission
([what green means](../explanation/concepts.md#about-what-green-means)).
[Required checks](../reference/required-checks.md) lists what each check
asserts.
