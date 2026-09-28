# How to run a project with plinth

You say what you want; an AI agent writes the code; you do not read it. This
page is the loop you walk, stage by stage: what you type, what the agent does,
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
  picks up, such as `/grill-with-docs` and `/implement` from
  [mattpocock/skills](https://github.com/mattpocock/skills). plinth does not
  write these. It chooses them, pins them to a commit (mattpocock-skills
  comes from Anthropic's official marketplace instead, and CI checks its
  version against a tested range), and this page shows how to walk them. Their authors own them and their licences
  apply; `/plinth:arsenal` lists each one with its source.

Three lines carry it: **you decide** (steps 2, 3 and 6), **the checks answer**
(step 5), **the record remembers** (step 8). If you remember one command, make
it `/ask-matt`: it reads your situation and names the next skill.

## What you type, and what runs by itself

Some skills run only when you type them: type `/`, then pick. The agent cannot
start them, so if you do not type them, they do not happen. The rest the agent
can pick up from an ordinary request when the moment fits.

| You type these | The agent can pick these up itself |
| --- | --- |
| `/ask-matt`: which skill now | `tdd`: test first, one small step at a time |
| `/grill-with-docs`: shape an idea by interview | `diagnosing-bugs`: reproduce, then fix |
| `/to-spec`, `/to-tickets`: plan a big job | `code-review`: review a change |
| `/implement #N`: build one ticket | `research`: look things up at the source |
| `/triage`: sort issues other people opened | `prototype`: a throwaway to settle a question |
| `/wayfinder`: map a job too foggy to plan | `/plinth:floor-check`: read a repository's setup |
| `/improve-codebase-architecture`: tidy up | `/plinth:arsenal`: the tool catalog |
| `/handoff`: pass work to another place | |
| `/wait-what`: "say that again, plainly" | |
| `/plinth:new-project`, `/plinth:template-update` | |

For the left column, asking in your own words ("update the template") does
not run the skill. The agent may do the work by hand, without the skill's
safeguards, or not do it at all. Those safeguards differ by skill:
`/plinth:new-project` tries to delete a repository it could not finish
setting up, and names it when its token cannot;
`/plinth:template-update` asks before each step and works in a separate
folder, leaving any conflict for you. Type the skill.

## Pick the size of the job first

| The change | Do this |
| --- | --- |
| A typo | Ask directly; it can go straight to a pull request |
| Fits in one session | `/grill-with-docs`, then the agent opens an issue with what "done" means, then `/implement #N` |
| Takes several sessions | `/grill-with-docs`, `/to-spec`, `/to-tickets`, then `/implement #N` for each ticket |
| You cannot yet see how to get there | `/wayfinder` first; when the way is clear it hands over to `/to-spec` |

## The one rule: say what proves it

Every "done" needs something you can see without reading code: a command's
output, a page, a number you can check by hand, or a test's name that says what
it checks. Ask for it in the interview, find it in each ticket, and look for it
in the pull request before you merge. For example: *"Done means: with my
sample file, it prints 33,000 won for September, and the next payment dates in
order."*

## Give the agent a token that cannot change the checks

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
2. In a separate terminal window, not with `!` in Claude Code, run
   `gh auth login`: GitHub.com, HTTPS, **Yes** to authenticating Git, then
   **Paste an authentication token**. It replaces the browser login.
3. In the project, `git remote -v` should show `https://github.com/…`. Over
   SSH the refusal does not happen: a deploy key with write access pushed a
   workflow change in the same measurement.

What it costs: the agent cannot push a change under `.github/workflows/`, so
a template update, or a fix `/plinth:floor-check` asks for in `ci.yml`, stops
at a commit. You push that branch from a separate terminal with a credential
that has the permission, the way the generator's admin-token path runs
([Getting started](../tutorials/getting-started.md#create-the-repository)).
Dependabot's updates to the pinned workflow are not affected: Dependabot
pushes with its own credential. Creating another repository with
`/plinth:new-project` needs the permission again; the generator stops, says
so and prints the fix.

This token was measured on one push each way, not through a whole loop: that
Contents, Issues and Pull requests are enough for every step on this page is
not verified.

## The loop

```text
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

### 2. Shape the idea: `/grill-with-docs`

Say what you want in your own words. The agent interviews you in rounds. It
looks up the facts itself and brings you only the decisions.

- Answer in plain words. "I don't know, recommend one" is a valid answer.
- Push back at least once. Agreeing to every recommended answer is how an
  idea gets built wrong with confidence.
- Say what is out of scope, and what proves it is done (the rule above).

It asks you to confirm that you both understand the same thing before it
acts. The words you agreed on go into `CONTEXT.md`, so later sessions use the
same names. A decision that is hard to reverse, surprising without its
context, and a real trade-off is written up separately under `docs/adr/`.

### 3. Plan a big job: `/to-spec`, then `/to-tickets`

For work that takes more than one session. `/to-spec` writes the plan into one
issue. `/to-tickets` cuts it into small tickets and marks which ticket waits
for which. Normally each ticket is something you could see working when it is
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
  one you worked out.
- **"What did the reviewer say?"** If the optional third-party reviewer is on,
  read its comments, not just its green mark. Each should end as fixed,
  answered, or moved to an issue.

### 6. Merge on your word

The agent is told to ask before it merges, and a yes covers that one pull
request,
unless you gave it a standing instruction for the session. When you merge, the
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
answer, and ask about anything marked as not verified. `/handoff` is for
moving work somewhere else: another tool, another folder, another person.

### 9. Keep it healthy

- **As they arrive:** dependency updates come as pull requests. Take them one
  at a time, on green. A dependency update can pass the code-scan rule without
  being scanned; the scan runs on `main` after the merge.
- **After each plinth release:** `/plinth:floor-check` says whether the
  repository is behind the template; `/plinth:template-update` takes the
  update as a draft pull request and leaves any conflict for you.
- **Every week or two, or after a burst of work:**
  `/improve-codebase-architecture` finds places to simplify. Each becomes a
  new idea for step 2.

## What the agent tells you, and when

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
| `/triage` on tickets `/to-tickets` made | Triage is for issues someone else opened |
| `/wayfinder` for a job you can already describe | `/grill-with-docs` |

## Where plinth holds the line

The skills guide; they enforce nothing. What holds is on GitHub: a change
reaches `main` only as a pull request whose required checks passed, and a
repository administrator, the agent included if it has that access, can
change those rules. [Concepts](../explanation/concepts.md) explains why;
[Required checks](../reference/required-checks.md) lists what each check
asserts.
