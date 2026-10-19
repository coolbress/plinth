# How to run a project with plinth

You say what you want and an AI agent writes the code, whether or not you
can read it yet. This page is the loop you walk, stage by stage: what you type, what the agent does,
what you check, and where plinth holds the line. It assumes the install and a
first repository from [Getting started](../tutorials/getting-started.md).

plinth has two halves, and it helps to know which is which:

- **Outside the agent, built by plinth:** the rules on GitHub that decide
  what merges, and the repository plinth sets up. An agent without
  administration cannot switch them off; one working with administration,
  as after the browser login, can change them. Either can rewrite the CI file
  inside a pull request, which the pull request's diff shows
  ([what green means](../explanation/concepts.md#about-what-green-means)),
  unless its token lacks workflow permission
  ([the agent's own token](#give-the-agent-a-token-that-cannot-change-the-checks)).
- **Inside the agent, made by others:** the skills you type or the agent
  picks up, such as `/grilling` and `/implement` from
  [mattpocock/skills](https://github.com/mattpocock/skills). plinth does not
  write these. It chooses them, pins them to a commit, and this page shows
  how to walk them. Their authors own them and their licences
  apply; `/plinth:arsenal` lists each one with its source.

Three lines carry it: **you decide** (steps 2, 3 and 6), **the checks answer**
(step 5), **the record remembers** (step 8). If you remember one command, make
it `/plinth:arsenal`: it lists the tools by step and says which one fits.

## What you type, and what runs by itself

Some skills run only when you type them: type `/`, then pick. The agent cannot
start them, so if you do not type them, they do not happen. The rest the agent
can pick up from an ordinary request when the moment fits.

| You type these | The agent can pick these up itself |
| --- | --- |
| `/implement #N`: build one ticket | `grilling`: shape an idea by interview |
| `/triage`: sort issues other people opened | `tdd`: test first, one small step at a time |
| `/plinth:new-project`, `/plinth:template-update` | `diagnosing-bugs`: reproduce, then fix |
| | `code-review`: review a change |
| | `/plinth:floor-check`: read a repository's setup |
| | `/plinth:arsenal`: the tool catalog |

For the left column, asking in your own words ("update the template") does
not run the skill. The agent may do the work by hand, without the skill's
safeguards, or not do it at all. Those safeguards differ by skill:
`/plinth:new-project` tries to delete a repository it could not finish
setting up, and names it when its token cannot;
`/plinth:template-update` asks before each step and works in a separate
folder; on a conflict it recommends a resolution for each file and applies
one only on your word for that file. Type the skill. You can type a skill
from the right column too: `/grilling` starts step 2.

### Skills plinth lists but does not install

Twelve more of Matt Pocock's skills are listed, not installed: on #520's
trial tasks no outcome separated a set with them from one without. You type
`/ask-matt` (which skill now), `/grill-with-docs` (the interview, also
writing `CONTEXT.md`), `/to-spec` and `/to-tickets` (plan a big job),
`/wayfinder` (map a job too foggy to plan), `/improve-codebase-architecture`
(tidy up), `/handoff` (pass work to another place) and `/wait-what` ("say
that again, plainly"); the agent picks up `research`, `prototype`,
`resolving-merge-conflicts` and `wizard` itself. To get all twelve, run this once in a terminal, then start a new
session:

```sh
claude plugin install mattpocock-skills-extra@plinth
```

`/ponytail-audit` (what to delete or replace with the standard library) is
listed too: no recorded run called it, and it cost every session a little
of its skill list (#598). To get it, run this once, then start a new session:

```sh
claude plugin install ponytail-skills@plinth
```

## Pick the size of the job first

| The change | Do this |
| --- | --- |
| A typo | Ask directly; it can go straight to a pull request |
| Fits in one session | `/grilling`, then the agent opens an issue with what "done" means, then `/implement #N` |
| Takes several sessions | `/grilling`, then ask the agent to write the plan into one issue and cut it into tickets ([step 3](#3-plan-a-big-job-a-plan-then-tickets)), then `/implement #N` for each ticket |
| You cannot yet see how to get there | `/wayfinder`, [listed](#skills-plinth-lists-but-does-not-install); when the way is clear it hands over to `/to-spec` |

## The one rule: say what proves it

Every "done" needs something you can see and check yourself, whether or not
you read the code: a command's output, a page, a number you can check by hand,
or a test's name that says what it checks. Ask for it in the interview, find it in each ticket, and look for it
in the pull request before you merge. For example: *"Done means: with my
sample file, it prints 33,000 won for September, and the next payment dates in
order."*

## The loop

```text
 start ─► first pull request merged ─► the agent's own token, four things by hand
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

`/plinth:new-project <name>` creates the repository and a first pull request;
merge it once its checks are green. For a repository you already have, ask for
`/plinth:floor-check`: it lists what is missing and changes nothing.

### Give the agent a token that cannot change the checks

The browser login from Getting started holds `workflow`, and so does the one
`gh auth login` asks for by default over HTTPS: an agent working with it can
push a change under `.github/workflows/`, including one that replaces
plinth's checks with jobs that do nothing and turns every check green
([what green means](../explanation/concepts.md#about-what-green-means)).
GitHub refuses a push that adds or changes a file there when the token lacks
workflow permission, for fine-grained and classic tokens alike. So once the
first pull request is merged, give the agent a token of its own without it:

1. On GitHub: **Settings → Developer settings → Personal access tokens →
   Fine-grained tokens → Generate new token**. Repository access: **Only
   select repositories**, this one. Repository permissions: **Contents**,
   **Issues** and **Pull requests** at **Read and write**. Leave
   **Workflows** and **Administration** at **No access**. If a `gh` command
   later answers 403, add the permission it needed, but never those two.
   Without Administration the token cannot edit or delete the ruleset
   either; the browser login can, because its `repo` scope includes
   administration.
2. In a separate terminal window, not with `!` in Claude Code, run
   `gh auth login`: GitHub.com, HTTPS, **Yes** to authenticating Git, then
   **Paste an authentication token**. It replaces the browser login.
3. Make sure nothing overrides it. `gh`, and the `git push` it serves, use
   `GH_TOKEN` or `GITHUB_TOKEN` before any stored login, and a running Claude
   Code keeps the environment it started with. If either is set in a shell
   startup file (`~/.zshrc`, `~/.bashrc`, `~/.zshenv`), remove it there, then
   restart Claude Code. In the new session, `gh auth status` should show a
   `github_pat_` token, stored in the keyring or gh's config file; after your
   account it should not say `(GH_TOKEN)` or `(GITHUB_TOKEN)`. Then
   `gh api repos/<owner>/<name>/actions/permissions` should answer
   `Resource not accessible by personal access token (HTTP 403)`: that read
   needs Administration, so the token has none. (`permissions.admin` on the
   repository says `true` for you either way: it is your account's role, not
   the token's.) `/plinth:new-project` asks the same when it finishes, for the
   login the agent inherits, and prints the answer.
4. Keep SSH out of the agent's reach. Over SSH the refusal does not happen: a
   deploy key with write access pushed a workflow change in the same
   measurement. In the project, `git remote -v` should show
   `https://github.com/…`, but the agent could switch the remote itself and
   use any SSH key it can read, under any file name. So check on GitHub, not
   on the machine: **Settings → SSH and GPG keys** on your account should list
   no authentication key this machine holds, and the repository's **Settings →
   Deploy keys** none with write access. (`ssh -T git@github.com` answering
   `Permission denied (publickey)` tests only the keys SSH picks by itself.)
   The token protects only pushes that go over HTTPS.
5. Leave no other credential for github.com on the machine. The first two
   pushed a workflow change past the token in a measurement with gh 2.101.0
   and git 2.55.0; the others are what gh and git document, not measured:
   - **Another account stored in `gh`.** `gh auth login` adds an account
     beside those already stored and makes it the active one; the agent can
     run `gh auth switch`. See them with `gh auth status`; remove each one
     that is not the token's with
     `gh auth logout --hostname github.com --user <login>`.
   - **Another git credential helper.** Git asks its helpers in the order
     `git config --show-origin --get-regexp 'credential.*helper'` lists them.
     One listed before gh's answers first; one listed after gh's answers when
     gh has no login, and in one run it stored the credential a push had
     just succeeded with, so it held that token afterwards. The macOS
     keychain helper is the usual one: git installed on macOS often lists it
     for every host in its system config. Delete its github.com entry (**Keychain
     Access**, search `github.com`), then keep it out with an empty
     `helper =` line before gh's, which is what `gh auth setup-git` writes:

     ```ini
     [credential "https://github.com"]
         helper =
         helper = !/opt/homebrew/bin/gh auth git-credential
     ```

   - **A `machine github.com` line in `~/.netrc`**, or an `Authorization`
     header in git's `http.extraHeader`: git over HTTPS sends either. Remove
     the line.
   - **`GH_TOKEN` or `GITHUB_TOKEN`**: `gh auth status` names it after the
     account; remove it as step 3 says. While one is set, an account stored
     in `gh` is a second credential even when it is the only one: the agent
     can unset the variable, and the stored login answers.

   `/plinth:floor-check` lists these on the machine it runs on and prints
   only whether each is there, never its value. Its rules are best effort:
   what they find is a warning, and finding nothing is a note, not a pass,
   since a credential written in a form they do not recognise is not
   reported. Go through this list yourself as well. What it could not read
   is not verified. So is a configuration hidden behind `GH_CONFIG_DIR`,
   `XDG_CONFIG_HOME`, `GIT_CONFIG` or a `GIT_CONFIG_*` variable: the agent can unset the
   variable, so give it its own token in the configuration read without one.
   It does not read SSH keys (step 4, on GitHub), a program named by
   `GIT_ASKPASS` or `core.askPass`, or a token saved anywhere else.
   The macOS keychain helper itself was not in the measurement; a credential
   store file in its place was. Every run lists SSH keys as not verified.

What it costs: the agent cannot push a change under `.github/workflows/`, so
a template update, or a fix `/plinth:floor-check` asks for in `ci.yml`, stops
at a commit. You push that branch from a separate terminal with a credential
that has the permission, the way the generator's admin-token path runs
([Getting started](../tutorials/getting-started.md#create-the-repository)).
Dependabot's updates to the pinned workflow are not affected: Dependabot
pushes with its own credential. Creating another repository with
`/plinth:new-project` needs the permission again; the generator stops, says
so and prints the fix.

One loop finished on this token without Claude Code asking for more
permission: an issue, the change, a pull request with its checks green, a
merge a person made, and a resume in a new session (one run, on a public
command-line repository, #403 record 1). Not run on it: a change that needs a
new dependency, a failing check, a review round, the agent attempting the
merge. That Contents, Issues and Pull requests are enough for every step on
this page is not verified.

### Give the agent its own account

The token above stops the agent from changing the checks, but not from
merging. GitHub decides who may merge by the account, not by the token: your
account owns the repository, so any token of yours can merge, even one
without Administration (#517 measured this). While the agent works under
your account, "ask before you merge" is something it is asked to do, not
something GitHub enforces.

A repository `/plinth:new-project` made carries a second rule set on
GitHub (a ruleset) that lets only the repository's admin merge. With the
agent on an account of its own, which is not the admin, GitHub refuses that
account's merge, and only you can merge. This is optional; skip it and the
rest of this page still works.

1. **Create the agent's account.** Sign out of GitHub in your browser, or
   open a private window, and sign up for a new account with a different
   email address. GitHub's terms let one person hold one free extra account
   for automation, called a machine account. Turn on two-factor
   authentication for it, as for your own.
2. **Invite it to the repository.** Signed in as yourself: the
   repository's **Settings → Collaborators → Add people**, then the agent
   account's name. Then, signed in as the agent account, open
   `https://github.com/<owner>/<name>/invitations` and accept. Do not make it
   an admin. Invite it only to the repositories it works on.
3. **Make its token.** Signed in as the agent account: **Settings →
   Developer settings → Personal access tokens → Tokens (classic) → Generate
   new token (classic)**. Tick only **`repo`**, nothing else, and choose a
   short expiry, such as 30 days. It has to be a classic token: a
   fine-grained token cannot be made for a repository the account was only
   invited to, because the owner offered is the agent account itself
   (#568 step 1). Leaving **`workflow`** unticked keeps the token from
   changing the checks, as in the section above: a push of a file under
   `.github/workflows/` was refused (#568 step 1). `repo` reaches every
   repository the agent account was invited to, which is why step 2 invites
   it only where it works.
4. **Sign the agent's session into it.** In a separate terminal window, not
   with `!` in Claude Code, run `gh auth login`: GitHub.com, HTTPS, **Yes**
   to authenticating Git, then **Paste an authentication token**, and paste
   the agent's token.
5. **Take your own login off this machine.** The agent can use any login it
   finds here, and yours can merge. Go through step 5 of the section above
   and remove every credential for github.com that is not the agent's:
   another account in `gh` (`gh auth status` lists them; remove yours with
   `gh auth logout --hostname github.com --user <your login>`), another git
   credential helper, `~/.netrc`, `GH_TOKEN` and `GITHUB_TOKEN`, and SSH
   keys (step 4). Then restart Claude Code.
6. **Check it.** In the new session, `gh api user --jq .login` prints the
   agent account's name, and `/plinth:floor-check` prints a line starting
   `the merge: boundary`. If it says `the merge: guidance`, the login the
   agent has is still the repository's admin, or the repository has no
   ruleset that reserves the merge (the same run shows a WARN with the
   command that adds one).

When a pull request is ready, the agent asks you, and you merge it yourself,
with the merge button on the pull request's page, signed in to GitHub as
yourself. The button looks as it does on any repository: green, with no
checkbox to bypass a rule and no warning about one, and the merge goes
through as usual (one measurement, #569). If the agent tries,
GitHub refuses (a 405 in the measurement), and
`scripts/merge-when-green.sh` stops and says that you merge, not to retry. If
the agent turns on auto-merge, the pull request stays open after its checks
pass (#568 step 1).

What it costs: you merge every pull request yourself, in the browser. Issues,
pull requests and commits show the agent account as their author. The token
expires and has to be made again, as in step 3. Everything that needs
administration, such as `/plinth:new-project` for another repository or the
admin-token commands on this page, runs with your own token in a separate
terminal: `scripts/with-admin-token.sh` asks for it each time and passes it
to that one command only, so it does not stay behind as a login.

What it does not cover: a browser on this machine signed in to GitHub as you,
if the agent can drive that browser; a credential for your account stored in
a form `/plinth:floor-check` does not recognise; and anything outside
GitHub's merge. The agent still pushes branches and opens pull requests, and
the checks and your review in step 5 are what judge them. Measured on a
public repository owned by a personal account on GitHub Free; a private
repository, GitHub Pro and a repository an organization owns were not
measured. On GitLab the same idea is a Developer login, not built yet
(#553).

### Set four things by hand that no check covers

Also once the first pull request is merged, settle four things outside the
repository. They are guidance: plinth does not check them, and it cannot,
because every check the host requires reads a pull request or the
repository's settings, and these live somewhere else
([what plinth does not do](../explanation/concepts.md#about-what-plinth-does-not-do)).
The token above limits what the agent can do on GitHub; these are meant to
limit what it, or anyone, can do elsewhere. Each is the safeguard whose
absence a reported incident turned on; what writing them down changes has
not been measured.

1. Keep production credentials and the production database out of the
   agent's session: give the agent a development database filled with
   made-up or scrubbed data, not a copy of production's. Protects against
   an agent deleting live data or reading real people's records.
2. Give every paid service the project uses a spend ceiling that stops the
   spending, not an alert that only tells you, for example a monthly limit
   on each API key. Protects against a leaked or runaway key running up a
   bill.
3. Restore once, on purpose, before it matters: roll back one merged change
   with a pull request that reverts it, and if there is a database, restore
   it from a backup yourself, in a place the agent cannot reach, into a new,
   empty database, check your data is there, then delete that database.
   Protects against finding out the way back does not work on the day you
   need it.
4. If the app has a database, put one made-up row in each table that should
   be private and try to read it from outside, with only the public key
   every visitor gets and no login, at the database's own address rather
   than the app's page; what you can read, anyone can. Protects against
   data left open to everyone.

### 2. Shape the idea: `/grilling`

Say what you want in your own words. The agent interviews you in rounds. It
looks up the facts itself and brings you only the decisions.

- Answer in plain words. "I don't know, recommend one" is a valid answer.
- Push back at least once. Agreeing to every recommended answer is how an
  idea gets built wrong with confidence.
- Say what is out of scope, and what proves it is done (the rule above).
- In a project's first interview, also settle three things no ticket repeats:
  who besides you is affected; the limits of cost and risk, and the outside
  rules that bind the project (law on data and accessibility, the terms of
  the services it calls, licences); and how long it must last, who takes it
  over, and what happens at the end (data deleted or handed over, keys
  revoked, users told). Have the agent write the answers in the README; a
  ticket refers to them and adds only its own result and proof. Each was
  missing from the whole project in two or three of the three recorded
  project runs, all trial projects (#408). The fifth thing, the agent's
  reach, is what the
  [four things by hand](#set-four-things-by-hand-that-no-check-covers) above
  limit.

It asks you to confirm that you both understand the same thing before it
acts. Ask it to put the words you agreed on into `CONTEXT.md`, so later
sessions use the same names, and to write up a decision that is hard to
reverse, surprising without its context, and a real trade-off under
`docs/adr/`; `domain-modeling` does both. `/grill-with-docs`, [listed](#skills-plinth-lists-but-does-not-install),
runs the same interview and does both on its own.

### 3. Plan a big job: a plan, then tickets

For work that takes more than one session. Ask the agent to write the plan
into one issue, then cut it into small tickets that say which ticket waits
for which. `/to-spec` and `/to-tickets`, [listed](#skills-plinth-lists-but-does-not-install), do these two
steps as skills. Normally each ticket is something you could see working when it is
done; ask of every ticket, "what can I see when this one is finished?". A
large change across the whole codebase is cut differently, in safe batches.

Keep the interview, the spec and the tickets in one session. If the session
gets very long before the tickets exist, `/compact` between two of those
steps, not in the middle of one.

### 4. Build one ticket: `/implement #N`

Start each ticket in a fresh session (`/clear`), one ticket per session. The
agent writes a test that fails first where it can, then the code that makes it
pass, has the change reviewed, and saves it as a commit. `/implement` stops
there; the agent then opens the pull request, following the repository's
rules.

Before a commit that changes code, not only documents or tests, Claude Code
tells the agent to run the `verify` skill the repository carries: it first
cleans the change up without changing what it does, then runs the checks. The
cleanup never removes input validation, error handling that prevents a loss, a
security measure or anything the ticket asked for, and on a commit that answers
a review finding it touches only that fix's lines. The repository also refuses
the shell writes agents use most, a `cat` heredoc, `tee` and `sed -i` (not
`echo` or `printf` into a file), so the agent writes code with its edit tools;
in trials, that and a single skill together, and neither alone, raised how
often one model ran it (#496). The agent is still asked, not forced. In trials it ran the lint, type
and test commands from `AGENTS.md` before every commit even when it skipped the
skill; what a skipped skill left out was the package build. The checks in step
5 are what decide (#474).

When the ticket is a page a person will look at, name `taste-skill` in the
ticket or the prompt, or type `/design-taste-frontend`: on a repository
rendered from the template the agent did not reach for it on its own (one
run, #469). For dashboards and dense product UI, use `/design` first.

If you have corrected the agent twice and it is still off, stop: `/clear`, and
say it again more precisely.

### 5. Check what the checks cannot

On GitHub, nine required checks (ten for a service) run on every pull request,
with the code-scan rule beside them (a dependency update passes that rule
unscanned; see step 9). Nothing merges until they pass. They answer only
their own questions: style, types, tests, packaging, secrets, dependencies,
size, the title and the project's setup. A mistake no test looks for passes
all of them. Before you say "merge", ask three things:

- **"What shows it works, and what did you not check?"** The pull request's
  description should answer both, for each thing "done" meant.
- **"Can I see it?"** Run the command, open the page, or compare a number with
  one you worked out. To have the agent launch and drive the app, type `/run`.
  In a repository plinth rendered, `/verify` runs the checks in `AGENTS.md`,
  not the app: the project skill takes the place of Claude Code's bundled one
  (#476).
- **"What did the reviewer say?"** If the optional third-party reviewer is on,
  read its comments, not just its green mark. Each should end as fixed,
  answered, or moved to an issue.

### 6. Merge on your word

The agent is told to ask before it merges, and a yes covers that one pull
request,
unless you gave it a standing instruction for the session. With one account,
the agent working under yours, that is guidance: GitHub lets your login
merge, so the agent could; with
[the agent's own account](#give-the-agent-its-own-account) it is a
boundary: GitHub refuses that account's merge, and you press the merge
button. `/plinth:floor-check` says which one you have. When you merge, the
ticket it was built for closes by itself. Then take the next ticket.

### 7. When something breaks

Show the agent the exact error and what you did before it. It first makes a
command that fails the same way, then, where a test can reach the problem,
writes a test that fails for this bug, then fixes it. Say no to a fix that
works by switching off or weakening a check instead of fixing the code. For
issues other people report, `/triage` sorts them: ready for the agent, needs
you, needs more information, or will not do.

### 8. Stop, and come back later

The plan, the decisions and what is left belong in issues and pull requests.
The chat ends, and the agent's own memory stays on one machine. To come back,
open a new session and ask "Where is this project, and what's next?". Read the
answer, and ask about anything marked as not verified. `/handoff`, [listed](#skills-plinth-lists-but-does-not-install), is for
moving work somewhere else: another tool, another folder, another person.

### 9. Keep it healthy

- **As they arrive:** dependency updates come as pull requests. Take them one
  at a time, on green. A dependency update can pass the code-scan rule without
  being scanned; the scan runs on `main` after the merge.
- **After each plinth release:** `/plinth:floor-check` says whether the
  repository is behind the template; `/plinth:template-update` takes the
  update as a draft pull request; on a conflict it recommends a resolution
  for each file and applies it only on your word.
- **Once, on a repository the door made before the merge ruleset:** `/plinth:floor-check`
  warns that no ruleset reserves the merge to an admin. The door now adds a
  second ruleset that lets only the repository's admin merge; while the agent
  works under your own account it changes nothing; with
  [the agent's own account](#give-the-agent-its-own-account) it is what
  stops the agent's merge. Add it in a separate
  terminal, from a plinth checkout, with a token that has administration:
  `scripts/with-admin-token.sh scripts/create-merge-ruleset.sh <owner>/<name>`.
- **Every week or two, or after a burst of work:** `/ponytail-audit`,
  [listed](#skills-plinth-lists-but-does-not-install), lists what to delete
  or replace with the standard library, biggest cut first;
  `/improve-codebase-architecture`, [listed](#skills-plinth-lists-but-does-not-install), finds places
  to deepen. Each becomes a new idea for step 2.

## What the agent tells you, and when

A repository `/plinth:new-project` made turns on the output style
`Beginner or non-engineer`: the agent does the same work and explains it in
plain words. After each change it ends with an **Insight** block (what
changed, why this way, what you can check yourself and what is not verified
yet). At a merge, a template update or a failure it gives a decision report:
what changed; what shows it, each check as `pass`, `fail` or
`not yet confirmed` as the run's summary says it; what is still unknown, and
on GitLab that no check is required by name; and what you are asked to
decide. Before any choice it recommends one option with its reason and asks
you to confirm. The first time it uses a term such as "squash" or "token",
it explains it in one clause.

Read the report's `not yet confirmed` lines before you say "merge": a green
check can carry one, naming something it passed without confirming. To turn
the style off for yourself, type `/output-style default` in the repository;
it writes `"outputStyle": "default"` to `.claude/settings.local.json`, which
the repository's `.gitignore` keeps out of commits. Removing that setting,
with the comma that joins it to another one if there is one, brings the style
back. The same setting in your own `~/.claude/settings.json`
did not turn it off when this was measured (#555): the project's setting
takes precedence. A repository made before plinth-template v1.14.0 gets the
style through `/plinth:template-update`.

At the start of a task, at an important choice, on a failure, and at the end
or a resume, the agent reports: the goal now; the next action and why; what
you decide; the evidence so far; where to return if stuck. You can steer at any
of them: "narrow this to one file", "show me the two outcomes as examples",
"is this mine to decide, or can the code tell you?". Asking for an
explanation is not approving a change.

## Common mistakes

| Mistake | Instead |
| --- | --- |
| Agreeing to every question in the interview | Push back at least once; say "I don't know" when you don't |
| Asking in plain words for work a typed skill exists for | Type the skill (`/plinth:template-update`, `/implement #N`) |
| A "done" with nothing you can see | Say what proves it, before the work starts |
| Two tickets in one session | `/clear`, one ticket per session |
| Tickets cut by layer (all the storage, then all the screens) | Cut so each ticket shows something working |
| Merging because everything is green | Ask the three questions in step 5 |
| A fix with no failing test first | Ask for the test that reproduces the bug |
| Decisions left only in the chat | Put them in the issue or pull request |
| `/triage` on tickets your own plan made | Triage is for issues someone else opened |
| `/wayfinder` for a job you can already describe | `/grilling` |

## Where plinth holds the line

The skills guide; they enforce nothing. What holds is on GitHub: a change
reaches `main` only as a pull request whose required checks passed, and a
repository administrator, the agent included if it has that access, can
change those rules. [Concepts](../explanation/concepts.md) explains why;
[Required checks](../reference/required-checks.md) lists what each check
asserts.
