# How to run a project with plinth

You say what you want and an AI agent writes the code, whether or not you
can read it yet. This page is the loop: nine steps from an idea to a merged
change. It assumes the install and a first repository from
[Getting started](../tutorials/getting-started.md).

Each step says where you are, the next action, what to look at, what is
yours to decide, and whether the step holds if you forget it (#515):

- **default**: it happens unless someone changes it;
- **boundary**: GitHub or Claude Code refuses to go past it;
- **guidance only**: the agent is asked to follow it, and nothing stops a
  step that is skipped.

If you remember one command, make it `/plinth:arsenal`: it says where you
are, the next action and the tool for it.

## The one rule: say what proves it

Every "done" needs something you can see and check yourself, whether or not
you read the code: a command's output, a page, a number you can check by hand,
or a test's name that says what it checks. Ask for it in the interview, find
it in each ticket, and look for it in the pull request before you merge. For
example: *"Done means: with my sample file, it prints 33,000 won for
September, and the next payment dates in order."*

## The loop

```text
 start ─► first pull request merged ─► the agent's token and account, four things by hand
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
- **Look at:** the first pull request's checks; merge it once they are green.
- **Yours:** the name, and that first merge.
- **If you forget:** a boundary once it exists: the required checks and the
  ruleset are on GitHub, beyond an agent without administration.

Then, before step 2, three setup steps, each on its own page, in this order.
Until they are done, the agent works with your own login and the protections
below are missing.

1. The agent's token, made on your account, ending with its step 5: every
   other credential for github.com off this machine. This is the default
   path.
2. The agent's own account, strongly recommended. Its token replaces the one
   from 1, and its step 5 repeats that list for your own login, the token
   from 1 included. It comes second because that step works from the token
   page's list. From then on you merge in the browser.
3. The four things by hand.

#### Give the agent a token that cannot change the checks

Until this is done, the agent's login can push a change under
`.github/workflows/` that turns every check green, and edit or delete the
ruleset. With the token, GitHub refuses both: a boundary, for pushes over
HTTPS.
[Give the agent a token](give-the-agent-a-token.md).

#### Give the agent its own account

Until this is done, the agent works under your account, and your account can
merge: "ask before you merge" is guidance only. With its own account, GitHub
refuses the agent's merge and only you can merge: a boundary. Strongly
recommended; the token alone is the default.
[Give the agent its own account](give-the-agent-its-own-account.md).

#### Set four things by hand that no check covers

Keep production data out of the agent's session, put a spend ceiling on every
paid service, restore once on purpose, and try to read private data from
outside. No check can see these; they stay guidance only, and until they are
done nothing limits the agent there.
[Set four things by hand](set-four-things-by-hand.md).

### 2. Shape the idea: `/grilling`

- **Where you are:** an idea in your own words. A typo can go straight to a
  pull request; anything bigger starts here.
- **Next:** type `/grilling` with the idea. The agent interviews you in
  rounds, looks up the facts itself and brings you only the decisions, then
  opens an issue with what "done" means (a job of several sessions gets a
  plan first, step 3).
- **Look at:** that you both mean the same thing. Have it put the agreed words into `CONTEXT.md`, and a
  decision that is hard to reverse, surprising and a real trade-off under
  `docs/adr/` (`domain-modeling` does both; `/grill-with-docs`,
  [listed](#skills-plinth-lists-but-does-not-install), runs the interview
  and does both).
- **Yours:** the answers; "I don't know, recommend one" is valid. Push back
  at least once: agreeing to every recommendation is how an idea gets built
  wrong with confidence. Say what is out of scope and what proves it done. In
  a project's first interview, also settle who besides you is affected; the
  limits of cost and risk, and the outside rules that bind it (law on data and
  accessibility, the terms of the services it calls, licences); and how long
  it must last, who takes it over, and what happens at the end (data deleted
  or handed over, keys revoked, users told). Have the agent write them in the
  README. Each was missing in two or three of the three recorded project
  runs, all trial projects (#408).
- **If you forget:** guidance only.

### 3. Plan a big job: a plan, then tickets

- **Where you are:** a shaped idea that takes more than one session.
- **Next:** ask the agent to write the plan into one issue, then cut it into
  small tickets that say which waits for which. `/to-spec` and `/to-tickets`,
  [listed](#skills-plinth-lists-but-does-not-install), do these as skills;
  `/wayfinder`, listed, is for a job you cannot yet see how to get through.
- **Look at:** each ticket: "what can I see when this one is finished?". Not
  cut by layer (all the storage, then all the screens); a change across the
  whole codebase is cut in safe batches.
- **Yours:** the cut. Keep the interview, the plan and the tickets in one
  session; `/compact` between two of them if it gets long, never mid-step.
- **If you forget:** guidance only.

### 4. Build one ticket: `/implement #N`

- **Where you are:** a ticket that says what "done" means.
- **Next:** `/clear`, then type `/implement #N`: one ticket per session. The
  agent writes a failing test first where it can, then the code, has it
  reviewed and commits; then it opens the pull request. For a page a person
  will look at, name `taste-skill` in the ticket or type
  `/design-taste-frontend` (unnamed, the agent did not reach for it, one run,
  #469); for dashboards and dense product UI, `/design` first.
- **Look at:** the commit and the pull request's description.
- **Yours:** when to stop. Corrected twice and still off: `/clear`, and say
  it again more precisely.
- **If you forget:** partly a boundary: the repository refuses a `cat`
  heredoc, `tee` and `sed -i` (not `echo` or `printf` into a file), so the
  agent writes code with its edit tools. Before a code commit, Claude Code
  tells the agent to run the repository's `verify` skill: a cleanup that never
  removes validation, loss-preventing error handling, a security measure or
  anything the ticket asked for, then the checks. That part is guidance only:
  in trials the refusal and one skill together raised how often one model ran
  it (#496), and a skipped skill left out the package build, not the lint,
  type and test commands. Step 5's checks decide (#474).

### 5. Check what the checks cannot

- **Where you are:** a pull request with its checks running.
- **Next:** wait for the required checks: nine on GitHub (ten for a
  service), with the code-scan rule beside them. Then ask: "What shows it
  works, and what did you not check?", "Can I see it?", "What did the reviewer
  say?".
- **Look at:** the description, answering the first for each thing "done"
  meant. Run the command, open the page, or compare a number you worked out;
  `/run` launches the app (`/verify` runs the checks, not the app, #476). If
  the optional third-party reviewer is on, read its comments, each ended as fixed,
  answered, or moved to an issue.
- **Yours:** whether what you saw is what "done" meant.
- **If you forget:** the checks are a boundary: nothing merges until they
  pass. They answer only their own questions (style, types, tests, packaging,
  secrets, dependencies, size, the title, the setup); a mistake no test looks
  for passes them all. The three questions are guidance only.

### 6. Merge on your word

- **Where you are:** green checks, and you have seen it work.
- **Next:** say "merge"; a yes covers that one pull request, unless you gave
  a standing instruction for the session. Claude Code may then ask you to
  approve the agent's `gh pr merge`: approving it is your merge. To merge
  yourself from a terminal, use the repository's squash command (its
  `CONTRIBUTING.md`, step 7), with the pull request's number and the head
  commit you checked:

  ```bash
  body="$(gh pr view <n> --json body --jq .body)" &&
    gh pr merge <n> --squash --match-head-commit <sha> --body "$body"
  ```

  With the agent on its own account, the agent cannot merge, and your login
  is off the machine: press the merge button in the browser, signed in as
  yourself.
- **Look at:** the agent's decision report: who it works as, and the
  `not yet confirmed` lines ([below](#what-the-agent-tells-you-and-when)).
- **Yours:** the merge. The ticket closes by itself; take the next one.
- **If you forget:** guidance only while the agent works under your account:
  GitHub lets your login merge, so the agent could. A boundary with
  [the agent's own account](give-the-agent-its-own-account.md).
  `/plinth:floor-check` says which one you have.

### 7. When something breaks

- **Where you are:** an error, or wrong behaviour.
- **Next:** show the agent the exact error and what you did before it. It
  makes a command that fails the same way, then, where a test can reach it, a
  test that fails for this bug, then fixes it. Issues someone else opened:
  `/triage` sorts them (ready for the agent, needs you, needs more
  information, will not do); not for tickets your own plan made.
- **Look at:** the command or test failing before the fix, passing after.
- **Yours:** say no to a fix that switches off or weakens a check instead of
  fixing the code.
- **If you forget:** guidance only; the fix still meets step 5's checks.

### 8. Stop, and come back later

- **Where you are:** ending a session, or returning to work under way.
- **Next:** before you stop, have the plan, the decisions and what is left
  put in issues and pull requests: the chat ends, and the agent's memory stays
  on one machine. To come back, open a new session and ask "Where is this
  project, and what's next?". `/handoff`, listed, moves work to another tool,
  folder or person.
- **Look at:** the answer, who it works as, and anything not verified.
- **Yours:** what to pick up next.
- **If you forget:** guidance only: what is not in an issue or pull request
  goes with the chat.

### 9. Keep it healthy

- **Where you are:** between pieces of work.
- **Next:** take dependency updates as they arrive, one pull request at a
  time, on green; one can pass the code-scan rule unscanned, and the scan runs
  on `main` after the merge. After each plinth release, `/plinth:floor-check`
  says whether the repository is behind the template and
  `/plinth:template-update` takes the update as a draft pull request; a
  repository made before the merge ruleset gets a warning and
  [the command that adds it](give-the-agent-its-own-account.md#a-repository-made-before-the-merge-ruleset).
  Every week or two, `/ponytail-audit` and `/improve-codebase-architecture`,
  [listed](#skills-plinth-lists-but-does-not-install), find what to cut or
  deepen; each becomes an idea for step 2.
- **Look at:** `/plinth:floor-check`'s report.
- **Yours:** each merge, and on a template conflict, which side: it
  recommends one per file and applies it only on your word.
- **If you forget:** the update pull requests are a default; taking them,
  and the template update you type, are guidance only.

## What you type, and what runs by itself

Four skills run only when you type them: `/implement #N`, `/triage`,
`/plinth:new-project` and `/plinth:template-update`. Asking in your own words
("update the template") does not run them: the agent may do the work by hand,
without their safeguards, or not at all. `/plinth:new-project` tries to delete a repository it could not finish,
or names it; `/plinth:template-update` asks before each step and applies a
conflict's resolution only on your word. Type the skill. The rest, `/grilling`
included, the agent can also pick up from an ordinary request.

### Skills plinth lists but does not install

Twelve more of Matt Pocock's skills, `/ask-matt`, `/to-spec`,
`/to-tickets`, `/wayfinder` and `/handoff` among them, and `/ponytail-audit`
are listed, not installed; `/plinth:arsenal` lists each. #520 moved the
twelve on #475's four criteria and their measured cost; no run compared a set
with them and one without, so whether they change a result is not known. Run
either line once, then start a new session:

```sh
claude plugin install mattpocock-skills-extra@plinth
claude plugin install ponytail-skills@plinth
```

## What the agent tells you, and when

A repository `/plinth:new-project` made turns on the output style
`Beginner or non-engineer`: the same work, in plain words. A change ends with
an **Insight** block: what changed, why, what you can check and what is not
verified. At a merge, a template update or a failure, a decision report: what
changed; each check as `pass`, `fail` or `not yet confirmed`, as the run says;
what is unknown (on GitLab, that no check is required by name); and what you
decide, with the option it recommends and why. It says which account it works
as at the first task, a resume and before a merge, and explains a term the
first time. Asking for an explanation is not approving a change.

A green check can carry a `not yet confirmed` line, something it passed
without confirming: read those before you say "merge". To turn the style off
for yourself, type `/output-style default`; it goes to
`.claude/settings.local.json`, kept out of commits; removing it brings the
style back. Set in your own `~/.claude/settings.json`, it did not turn the
style off (#555). A repository made before plinth-template v1.14.0 gets the style through
`/plinth:template-update`.

## Where plinth holds the line

The skills guide; they enforce nothing. Most are made by others, such as
[mattpocock/skills](https://github.com/mattpocock/skills); plinth chooses and
pins them, and their licences apply. A change reaches `main` only as a pull
request whose required checks passed. An administrator, the agent too after
the browser login, can change those rules, and any agent can rewrite the CI
file inside a pull request unless its token lacks workflow permission
([what green means](../explanation/concepts.md#about-what-green-means)).
[Concepts](../explanation/concepts.md) explains why;
[Required checks](../reference/required-checks.md) lists what each check
asserts.
