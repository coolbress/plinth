---
name: new-project
description: Create a new GitHub repository with required checks already enforced (with --host gitlab, a GitLab.com project with its wall). User-invoked only; creates a remote repository, and if a step that raises the wall fails, deletes it when the token can or names it when it cannot.
argument-hint: "[<owner>/]<name> [--archetype=cli|library|backend|data-ml|web] [--hosting=render|railway|digitalocean|fly|vps|home] [--private|--public] [--host=github|gitlab] [--third-party-review|--no-third-party-review] [--code-of-conduct=<contact>|--no-code-of-conduct] [--description=<one line>|--no-description] [--license=mit|apache-2.0|proprietary] [--dir=<path>]; what is not given is asked"
disable-model-invocation: true
---

# New project

Creates `[<owner>/]<name>` on GitHub with the wall already up. When a step it
cannot go on without fails, it deletes the repository if its token can, and
names it otherwise. The owner is optional: a bare name goes under the user's login. One script does all of it; this skill runs it and relays what it says.

## Check first, before any question

Before the first question, and before reading the owner's files, read both
hosts' readiness. It changes nothing: it asks `gh` and `glab` whether they are
installed and logged in, and as whom.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/new-project.sh --readiness
```

It prints one line per host, `github: ok, …` or `github: missing, …`, then the
same for `gitlab:`. Show each beside its choice in the host question, `ok` as
✓ and `missing` as ✗ with the words after it, for example "✓ gh logged in as
octocat" or "✗ glab (GitLab CLI) is not installed". With `--host` in the
arguments the host is not asked, and this read is skipped.

Once the host is known (the first question, or `--host`), run the script's
preflight for it with the arguments as typed and the host chosen:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/new-project.sh --preflight --host=<github|gitlab> $ARGUMENTS
```

It checks only the tools, git's identity for the first commit, and the login
and token (glab's on GitLab.com, gh's on GitHub), reads nothing about an owner
or a repository and creates nothing; the name may be missing. Exit 0 ends with
a `preflight: ok` line: go on to the next question. Any `warning:` line before
it is shown and explained as below. Exit 2 is the checklist: it names every
item missing at once, each with its fix (`N things to fix; nothing was
created:` above them when there are two or more). Show it and explain each
item as [What the script printed](#what-the-script-printed) says, each fix in
the `!` form, and ask nothing else. When the person says it is done, run the
preflight again; go on only once it passes. One stop is the exception: a
fine-grained token whose owner wants to keep it rather than log in again. Then
ask the questions and run the script; it stops at the same check and prints
the admin-token path (below).

## What the script printed

Every stop, every `warning:` line and the final lines are shown verbatim, in
a code block, as the script printed them, untranslated: they are what a
person searches for. Under the block, add one plain sentence for each line,
in the language the person writes to you in, whatever it is, and in the same
order: what it means for them, not a word-for-word translation. A
line indented under another (a `fix:` or a continuation) shares its
parent's sentence. The first time a word appears, say what it is in a few
words: the ruleset (the rules GitHub enforces on `main`: no direct push, and
the required checks pass before a merge), CodeQL (GitHub's automatic security
scan of the code), the wall (the ruleset and its checks together), rollback
(deleting a repository a failed run half made), `plinth-template@vX.Y.Z` (the
version of the template the project is made from), a scope (one permission
a GitHub login carries).

Two lines get a fuller sentence:

- `administration:` saying the credential has it: the login used here can
  remove these safety rules or delete the repository, so an agent working
  with it could too. After the first merge, follow the link in the line to
  give the agent a token without that permission; it takes about five
  minutes.
- A stop that offers `--force-defaults`: it means the owner's shared files
  (a code of conduct, a security policy, forms) could not be read, and the
  flag writes the template's own copies instead of using the owner's. Running
  again usually reads them; the flag is for when it does not.

**How a fix is run.** You never run a fix yourself, `gh auth` above all.
When the fix is a command the person types (`gh auth login …`,
`gh auth refresh …`, `curl … | sh`, `claude update`, `brew install git`),
show it in its own code block with `!` in front, for example
`! gh auth refresh -h github.com -s repo,workflow`, and say in
the person's language: type it into Claude Code's prompt, `!` included; it
runs the command here and its output lands in the conversation. For
`gh auth`, add that it prints a one-time code and a URL, the URL opens in
the browser, and the code is entered there. After a program is installed
(`uv`, `git`, `gh`), say that the running session does not see it yet: quit
Claude Code (`/exit`), start it again (`claude`), and type
`/plinth:new-project` again. A fix that is a web page or a flag is said as
one, without `!`. The admin-token path is the exception: its three lines run
in a separate terminal window, never with `!` (below).

## Ask first what the arguments leave out

What is installed without asking, what is asked and what starts off and is
told follows one rule, "How an item is sorted" in
`${CLAUDE_PLUGIN_ROOT}/docs/reference/off-by-default.md`; when the person
asks why a choice is or is not asked, read it there rather than answer from
this file.

Every choice that changes the wall is a flag, and the script asks nothing: a
flag it is not given takes its default. So before running it, ask for each
choice the arguments (`$ARGUMENTS`) do not give, in the order below, and wait
for each answer. A choice given as a flag is never asked; arguments that give
every choice are asked nothing. Values that only tune a check
(`max-diff-lines`, `deps-fail-on-severity`, `extra-python-versions`) are not
asked: their defaults fit most projects, and the project's README says how to
change them.

**How to ask.** Ask with the AskUserQuestion tool, the picker: at most four
choices per question and four questions per call; it adds an "Other" box for
typed text on its own, so never add one. Use the questions, labels and
descriptions below as written, translated into the person's language. Where
the tool is not available (a `claude -p` run, for one) or a call comes back
with no answer, ask the same questions in text instead, in the same order,
with their choices numbered, one question at a time. Never answer a question
for the person. Never ask for a secret (a token, a password, an API key): none
is typed into the chat, and none of the questions below needs one.

1. **The host**, when there is no `--host`. Header `Host`: "Where should the
   repository live?" Each choice carries its readiness line from
   [Check first](#check-first-before-any-question).

   | Label | Description |
   | --- | --- |
   | GitHub (Recommended) | ✓ or ✗ and its readiness. A GitHub repository with the wall; every kind of project, the web app included (`--host=github`). |
   | GitLab.com | ✓ or ✗ and its readiness. A GitLab.com project with its wall; needs `glab` installed and logged in. The web app is made on GitHub only. On GitLab.com the next-step guide and template updates are partly manual: `/plinth:guide` reads GitHub only, and the project's `AGENTS.md` names where the next work is instead (`--host=gitlab`). |

   Then run the preflight for that host, as
   [Check first](#check-first-before-any-question) says, before the next
   question.
2. **What to make**, when there is no `--archetype=`, in text (it has no
   choices): "What do you want to make? A sentence or two in your own words
   is enough; \"I don't know\" is an answer too." Keep the answer: the
   archetype's reason quotes it, the names translate it, and the visibility
   reads it. With `--archetype=` given, steps 2, 3 and 4 are not asked.
3. **Follow-ups**, only when the answer to step 2 leaves the archetype open
   (it fits two kinds, says too little, or is "I don't know"); one that names
   what is made asks none. Ask only what decides between the kinds still open:

   - Header `Use`: "How will it be used?" **Someone runs it, in a terminal or
     on a schedule** (cli). **Other code imports it** (library). **It keeps
     running and answers requests** (backend). **People open it in a browser
     and log in** (web; left out on GitLab.com).
   - Header `Model`: "Does it train a machine-learning model here?" **Yes**
     (data-ml). **No**: collecting, cleaning or processing data with no model
     trained is cli.
   - A schedule word ("daily", "every hour", "every morning") is not a
     question: say what it means for where it runs. cli runs on the person's
     own computer, only while it is on, started by a scheduler there (cron,
     launchd) that plinth does not set up; running it in the cloud on a
     schedule needs a place that costs money.
4. **The archetype recommendation**, header `Kind`: "I recommend `ARCHETYPE`:
   `REASON`. It makes `MAKES`; it does not make `NOT`." `REASON` is one line
   quoting the person's words from step 2; take `MAKES` and `NOT` from the
   table below, as written there. Never choose for them in silence: the
   person always picks.

   | Label | Description |
   | --- | --- |
   | Use `ARCHETYPE` (Recommended) | Make it as this kind (`--archetype=ARCHETYPE`). |
   | Another kind | See the other kinds and pick one. |
   | Not sure | Start with the narrowest, a terminal command (`--archetype=cli`); a kind can be changed later, with some work. |

   Until plinth has them, add one sentence for the gap the description falls
   into: there is no light dashboard kind (web brings logins, a database and
   a monthly cost); `cli` runs only on the person's computer; a bot needs a
   place to run, and that costs money.

   | Kind | Makes | Does not make |
   | --- | --- | --- |
   | cli | A command people install and run in a terminal; on GitHub a release only when a tag is pushed. | A server, a web page, or anything that runs by itself away from the person's computer. |
   | library | A package other code imports. | A command, a server or a web page. |
   | backend | A service in a container that keeps running and answers requests. | Web pages with logins, or a place to run it. |
   | data-ml | A model trained here, with a model card; on GitHub a `v*` tag publishes the model, its metrics and the card. | A server that answers with the model, or data collected on a schedule. |
   | web | A web app with logins and a Postgres database, on GitHub only. | A light page with no logins; it costs money to run. |

   **Another kind** asks header `Kind` again with the kinds below other than
   the one recommended, so at most four; on GitLab.com leave out `web`. When
   the `Use` follow-up was asked, it is not asked again: this list is the
   next step after it, not a repeat. Every kind gets the same checks besides
   (title, lint, types, tests, build, secrets, dependencies, change size, the
   project's own setup) and CodeQL; say so only if asked.

   | Label | Description |
   | --- | --- |
   | A terminal command (cli) | A command people install and run in a terminal; also the choice for a tool that runs on a schedule on the owner's machine (a data collector, a pipeline). On GitHub its release workflow runs only when a tag is pushed (`v*`, or a member's `<prefix>-v*`), so a project that never tags publishes nothing. If you are not sure, choose this one. |
   | Code other code imports (library) | A package other code imports. |
   | A service or API (backend) | A service that keeps running and answers requests, in a container. It also checks that its container builds and starts. |
   | A model you train (data-ml) | A model trained here, with a model card. On GitHub a `v*` tag publishes the model, its metrics and the card as release files. It also checks the container, and comes with a test of the training. Data processing, collection or a pipeline with no model trained is `cli`. |
   | A website people log in to (web) | A web app with logins and a database, on GitHub only. It costs money to run: about US $13 a month on Render. It also checks the container, the database changes and the production settings. |

   Right after the archetype is set, say its prerequisites in one line: for
   `web`, a Render account and about US $13 a month (a $7 web service and a
   $6 Postgres, the template's figures), with where it runs asked next; for
   the others, nothing beyond what the preflight checked.
5. **Where a web app runs**, for `web` only: the question in
   [Where a web app runs](#where-a-web-app-runs), unchanged.
6. **The name**, when the arguments carry none. Header `Name`: "What should
   the repository be called?" Offer two or three names in ASCII that
   translate what step 2 means, short, lowercase, with `-` between words: a
   translation, not a romanization of the person's words, since `gh` and
   github.com turn every letter outside ASCII into `-`. The picker's own Other
   takes a typed name; add no choice for it. Say in one line that
   `owner/name` puts it under an organization. The name is at most 46
   characters, the owner not counted: the new project's Python package takes
   the same name, and from 47 characters lines of its code pass the 100 its
   own lint check allows. When step 2 was not asked (`--archetype=` given),
   ask the name in text, with no suggestions.

   Before showing a suggestion, check it, and check a typed name as soon as it
   is given:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/new-project.sh <name> --check --host=<host> --archetype=<archetype> $ARGUMENTS
   ```

   with the arguments as typed after the name, so a `--dir=` or `--license=`
   given there is checked as the run will use it.

   It runs every check the run makes before it renders, reads only, and
   creates nothing: the name rules, the 46 characters, the names the chosen
   archetype's template refuses (read from the pinned template's
   `copier.yml`, such as `train` for data-ml), a name already taken, a folder
   already there, and the owner (an organization the login is not a member
   of). Exit 0 ends with `check: ok`. Show only suggestions that passed; when
   fewer than two pass because of the name (taken, refused, too long, a
   folder in the way), find others and check them. A stop that is not about
   the name (the tools or login, the template's tag, an owner that cannot be
   read, the network) is the same for every name: show it and explain it as
   [What the script printed](#what-the-script-printed) says, and suggest no
   more names until it passes. A typed name that stops is shown and
   explained the same way, and the name is asked again.
7. **Who may see the project**, when neither `--public` nor `--private` is
   given: ask it alone, before the defaults, since it decides the license
   recommended, what the wall can hold on the account's plan and who can read
   the code. Header `Visibility`: "Who may see this project's code?" On
   GitHub, list **Anyone on the internet (public) (Recommended)** first: GitHub
   Free cannot keep the ruleset on a private repository. When step 2 signals
   data that should stay private (a company's or a customer's, a household
   budget, health, anything personal), list **Only people you add (private)
   (Recommended)** first instead and say why, quoting those words. On
   GitLab.com, private is recommended.

   | Label | Description |
   | --- | --- |
   | Anyone on the internet (public) | Anyone on the internet can read and copy the code; the license recommended is MIT. On GitHub the whole wall stands on every plan. On GitLab.com, anyone can read it. |
   | Only people you add (private) | Only you and the people you add can read it; the license recommended is Proprietary. On GitHub Free a private repository cannot keep the ruleset, so plinth stops before creating it; on a paid plan it has no CodeQL or push protection unless the account has GitHub Code Security and Secret Protection; on a personal account, plinth reads the plan first, which needs the `read:user` permission on your GitHub login (it says the command that adds it). On GitLab.com this is plinth's default, since the free plan protects a private project's main branch. |

   The answer becomes `--public` or `--private`, on either host. On GitLab.com,
   leave out the GitHub sentences; on GitHub, the GitLab.com ones. In text,
   the same question with the two choices numbered.

   For private on GitHub, read the plan now, not at the end: run the check of
   step 6 again with `--private`. When it stops because the plan cannot keep
   the wall (GitHub Free), ask header `Plan`: "Your plan cannot keep the wall
   on a private repository. What now?" **Public instead** (`--public`, the
   whole wall). **Upgrade the plan and start again**: GitHub Pro for a
   personal account, Team for an organization; then type
   `/plinth:new-project` again. **Stop**: nothing is created. When it stops
   because the token cannot read the plan, show its fix in the `!` form and
   run the check again once the person says it is done. When it passes with a
   `plan: not verified` line, the plan could not be read and GitHub decides
   at the ruleset: show the line, say that if GitHub refuses the ruleset the
   repository is deleted again, and ask the same `Plan` question with
   **Private anyway** in place of the upgrade.
8. **The recommended defaults.** Of the third-party reviewer
   (`--third-party-review`/`--no-third-party-review`), the code of conduct
   (`--code-of-conduct=`/`--no-code-of-conduct`), the description
   (`--description=`/`--no-description`), license (`--license=`) and
   directory (`--dir=`), take the ones the arguments do not give. The host
   and the visibility are known by now. First, when the code of conduct is
   among them and the host is GitHub, read whether the owner already
   publishes one:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/owner-files.sh [<owner>]
   ```

   with the owner from the name, or nothing for a bare name. A
   `code_of_conduct: yes` line means the owner's applies: leave the code of
   conduct out of every question below and add no flag for it. Any other
   line (`no`, or `unknown: …`) leaves it to ask; the script stops on its
   own if the lookup fails again. If nothing is left, ask nothing. Otherwise
   ask one question, header `Defaults`, naming only those left with their
   defaults: "Use the recommended defaults? MIT license, in `~/<name>`, no
   third-party reviewer, no code of conduct, no description." It never names
   the host or the visibility. On GitLab.com, leave out the reviewer, the
   code of conduct and the description, which are GitHub only. The license
   follows the visibility: for a private project, say "Proprietary license"
   in place of "MIT license".

   | Label | Description |
   | --- | --- |
   | Yes (Recommended) | Create it with these. |
   | Customize | Choose each one. |

   Every answer becomes a flag, a default included, so that the command
   said before the run (below) asks nothing when typed again. **Yes** adds
   the flag for each default still open: `--no-third-party-review`,
   `--no-code-of-conduct`, `--no-description`, `--license=mit` and
   `--dir=<home>/<name>`, with the home directory written out as an absolute
   path; on GitLab.com, none of the three GitHub-only flags; for a private
   project, `--license=proprietary` in place of `--license=mit`. The host of
   step 1 is a flag too: `--host=github` or `--host=gitlab`.
   **Customize** asks each choice still open in one call, leaving out what
   the arguments give and what does not apply: the license and, on GitHub,
   the reviewer, the code of conduct and the description.

   - Header `License`: "Which license?" Three choices, each saying what
     it grants; for a private repository list **Proprietary
     (Recommended)** first, for a public one **MIT (Recommended)**.
     **MIT**: anyone may use, copy, change and sell the code, keeping your
     copyright line; short, the usual choice for a public project
     (`--license=mit`). **Apache-2.0**: the same, plus a patent grant; when
     a company or the project you build on asks for it
     (`--license=apache-2.0`). **Proprietary**: grants nothing; nobody
     else may use, copy or share the code without your written permission
     (`--license=proprietary`).
   - Header `Reviewer`, on GitHub only, asked as a fact the person knows,
     not a preference: "Is a code reviewer, such as Codex's, already
     connected to your GitHub account?" **No, or not sure (Recommended)**:
     `--no-third-party-review`; the last lines say when to turn it on.
     **Yes**: `--third-party-review`; each pull request gets a
     `third-party / review` result, which reports and is not required, so a
     pull request still merges without it. The last lines then say what to
     do right away: turn the reviewer on for the new repository.
   - Header `Conduct`: "Add a code of conduct?" **No (Recommended)**:
     `--no-code-of-conduct`; most small projects start without one, and
     `/plinth:floor-check` does not ask for it. **Yes, the Contributor
     Covenant**: the most used one, version 3.0, written as
     `CODE_OF_CONDUCT.md`; it names where reports of bad behaviour go, so
     the next question asks that.
   - Header `Description`: "A one-line description for the repository's
     page? Type it into Other." **Skip for now**: `--no-description`; it can
     be added later on the repository's page. A line typed into Other
     becomes `--description=<that line>`, at most 350 characters.

   With **Yes** to the code of conduct, ask in text, since it has no
   choices: "Where should reports under the code of conduct go? An email
   address or a web page; anyone who can read the repository can read it."
   The answer becomes `--code-of-conduct=<answer>`. An empty answer is
   asked again.

   Then, when no `--dir=` was given, ask the directory on its own, header
   `Folder`: "Where should the local copy go?" with one choice,
   **`~/<name>` (Recommended)**, a new folder in your home directory
   (`--dir=<home>/<name>`, written out); another path is typed into Other
   and becomes `--dir=<path>`. It must not
   exist yet, or be empty.

   A typed answer that is none of the choices (other than the folder and
   the description) is asked again.

Then run, with the arguments as typed and the flags the answers added:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/new-project.sh $ARGUMENTS <added flags>
```

Before running it, say in one line the command the person can type next time
to get the same run with no question: `/plinth:new-project` followed by their
arguments and the added flags, not the script's path.

Put `PLINTH_ASSISTED_BY=<agent>:<model>` in front of it, on either host,
naming yourself as a commit trailer would (e.g. `Claude:claude-opus-5-5`): the
first pull request's description (the first merge request's, with
`--host gitlab`) ends with that `Assisted-by` line.

The run takes several minutes, and up to about 26: on GitHub it waits up to
five times, 5 minutes at most each, and once for a minute more. The first
three waits and the minute come before the wall stands,
at most about 16 minutes in; the last two only report main's first CI run (on
GitLab it waits once). Tell the person that in one line before it starts, and that a
quiet stretch is waiting, not stuck. Run it once: run it in the background, or
with the longest timeout the Bash tool allows, which is shorter than the worst
case. Either way, wait for that same run to end and read its output before
saying anything about the result. If the tool says the command was moved to
the background, that is not a failure: wait for that same run to end. Never
run the script again while it is running: a second run works on the same
repository name. An interrupt before the wall stands deletes the repository,
by design; say so if the person asks to stop.

The script checks tools, token, owner and visibility first and creates nothing
until all four pass. It then renders the template into `~/<name>` (or
`--dir`), where a name or answer the template refuses stops with copier's
words before anything exists on GitHub, creates the repository, pushes `main`, raises the ruleset and CodeQL (and,
for `cli`, `library`, `backend` and `data-ml`, which release from a `v*`
tag, a tag
ruleset no one can bypass that keeps those tags from being moved or
deleted), makes the Actions token read-only by default and unable to approve
a pull request, and opens the first pull request. With `--third-party-review` the template also
renders `.github/workflows/third-party.yml`, the caller of the
`third-party / review` check, and the ruleset is the same as without it: the
check reports and is not required, so the first pull request merges whether
or not a reviewer comes. Last, it re-runs the failed jobs of `main`'s
first CI run, which ran before the wall and failed its floor check. With `--private` the repository is private: an
owner on GitHub Free stops before anything is created, and elsewhere the same
ruleset goes up, with CodeQL and push protection only where GitHub Code
Security and GitHub Secret Protection are already enabled on the new
repository. The script turns neither product on, and its last lines name each
part it left out. If a step it cannot go on without fails after
creation, it deletes the repository when its token can and names it when it
cannot; a label that fails is named and left. If the create's own answer is
lost, it does neither.

`--archetype=web` is a Django app with a Postgres database, made on GitHub
only: its deployment and checks are built for GitHub, so with `--host gitlab`
the script refuses before it reads anything on GitLab, and says why. Render is
the one place plinth builds and checks; where else the app can run, and what
each place leaves to the person, is in
`${CLAUDE_PLUGIN_ROOT}/docs/how-to/choose-where-a-web-app-runs.md`.

## Where a web app runs

Only for `--archetype=web` on GitHub, and only when the arguments carry no
`--hosting=`: before running the script, ask the person this, in these words,
and wait for the answer. For any other archetype, or with `--host gitlab`,
do not ask it and do not pass `--hosting`.

> **Where will your app run?** Before you choose, you can read what each
> place costs and what it leaves to you:
> <https://github.com/coolbress/plinth/blob/main/docs/how-to/choose-where-a-web-app-runs.md>
>
> 1. **Render — recommended.** About $13 a month. It puts your app online at
>    a secure `https://` address (the padlock in the browser), puts out a new
>    version only after the project's automatic tests pass, and can bring your
>    data back as it was at any moment from 3 days ago up to 10 minutes ago.
>    plinth has tried every step of this.
> 2. **Another hosting service** (Railway, DigitalOcean, Fly.io). From about
>    $10 to $42 a month. Similar, but plinth has not tried them: some put out
>    a new version even when its tests fail, and on some, backups stay off
>    until you switch them on.
> 3. **A server you rent.** From about €6 a month for more power, but keeping
>    it updated, secure and backed up is your job every month.
> 4. **A computer at home.** Free to try on your own network. Putting it on
>    the internet is the riskiest choice: anyone can reach it, a flaw can lead
>    into your home network, and your data is only as safe as the backups you
>    make yourself.
>
> plinth sets up and checks only Render. Choices 2, 3 and 4 are places plinth
> does not deploy to for you and has not checked: the project's README will
> have the steps, and doing them is up to you.

If they pick 2, ask which one:

> 1. **Railway.** About $10 a month, an estimate. Backups are off until you
>    switch them on.
> 2. **DigitalOcean App Platform.** About $20 a month. Daily copies of your
>    data are kept for 7 days.
> 3. **Fly.io.** About $42 a month, most of it for the database.

Then add one argument: `--hosting=render` (1), `--hosting=railway`,
`--hosting=digitalocean` or `--hosting=fly` (2), `--hosting=vps` (3) or
`--hosting=home` (4). If the person does not answer, says they do not know, or
asks you to choose, use `--hosting=render`. Never pick another place for them.

For 3 or 4, before running the script, say this once more:

> One rule matters most on your own server or home computer. A port is a
> numbered door through which the internet reaches one program on the
> computer; a proxy is a program that takes every visitor's connection first,
> handles HTTPS, and passes the visit on to the app. Never open the app's own
> port (8000) to the internet without a proxy in front of it, and never open
> the database's port (5432) at all. The README's steps show how.

A template that does not ask this question yet makes the script stop for 2,
3 or 4 before anything is created; show that message as it is.

With `--host gitlab` the target is a GitLab.com project. It checks `glab`
(installed, recent enough, logged in to gitlab.com, with the api scope where
readable), the namespace (a bare name under the login, or a group where the
login is Maintainer or above) and the path (GitLab's rules, not reserved, no
project or subgroup there, no more public than its group). It then renders
the template with `host=gitlab`, prints the plan line, creates the project,
pushes `main`, and raises the wall: main protected (no push, Maintainers
merge, no force push), merges only when the pipeline succeeds, squash and
fast-forward, each read back; then the labels. Last, it opens the first
merge request (a First day section in README.md, in the rendered template's
shape) and reads `main`'s first pipeline until it completes or five minutes
pass; a red one is named with its failed jobs and not re-run. If a step after
the create fails before the wall reads back, it deletes the project for good
where the login can, says so when GitLab only scheduled the deletion, and
names the project where the login cannot delete it. A label or the merge
request that fails is named and left: the project is right by then. The
project is private unless `--public` is given.

What to do with the output:

- **It stopped before creating anything** (exit 2): show the user the message
  verbatim and explain it, with the fix in the `!` form, as
  [What the script printed](#what-the-script-printed) says. It names the one
  fix. Do not work around it; do not run `gh repo create`, `gh auth`, or the
  script with different arguments.
- **It asks for the admin path**: the message contains three short lines, a
  `P=` assignment, a call through it to `with-admin-token.sh` ending in a
  backslash, and the arguments. Show all three verbatim, as one block, and
  tell the user to run them in a separate terminal window, not with `!`: `!`
  runs a line without a terminal, so the token prompt gets nothing. It
  prompts for a token at that terminal; never put a token on a command line
  or in a file, and never ask the user to paste one into the chat.
- **It rolled back** (exit 1): show the message. If it says `ROLLBACK FAILED`,
  repeat the URL and that the repository exists without a wall.
- **It created the GitLab project** (`--host gitlab`, exit 0): show the
  `create gitlab.com/…` plan line, the `token scopes:` line when there is
  one, any `warning:` line about a label, and every line from `done:` on: the
  first merge request (or why it was not opened, with the command that opens
  it), the first pipeline on `main`, the wall, both GitLab Free limits, and
  `next:`. A `not confirmed` or `failed` pipeline is said as it is, never as
  passed.
- **The GitLab run rolled back** (exit 1): show the message. If it says
  `ROLLBACK FAILED` or `ROLLBACK PARTLY DONE`, repeat the URL and that the
  project exists with part of its wall or none.
- **It finished** (exit 0): show the final lines, the `administration:` line,
  the `where it runs:` line and the `first commit on main:` line among them, and for a private repository every `private:`, `not raised:`
  and `not verified:` line as printed. When there is a `to do now` block,
  show it first, every line under it, as the person's next step: with the
  third-party reviewer chosen, turning it on for this repository, without
  which each pull request waits 20 minutes for a review and then shows a
  failed check. Show the `starts off` block as
  printed, every line under it: what the project starts with turned off, when
  each is worth turning on, and where its steps are (the list is
  `${CLAUDE_PLUGIN_ROOT}/docs/reference/off-by-default.md`). Do not turn any
  of them on. Under the lines, the plain sentence for each, as
  [What the script printed](#what-the-script-printed) says, the
  `administration:` line's included. The next step for the user is to open
  the pull request URL, wait for the checks, and merge with squash. On
  GitHub, end with one line in the person's language: try typing
  `/plinth:guide` in the new repository's folder; it names the command to
  type next and explains this step and the next in plain words, and
  `/plinth:guide map` shows the whole way.

Do not edit the generated repository in this session.
