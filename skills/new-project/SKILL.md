---
name: new-project
description: Create a new GitHub repository with required checks already enforced (with --host gitlab, a GitLab.com project with its wall). User-invoked only; creates a remote repository, and if a step that raises the wall fails, deletes it when the token can or names it when it cannot.
argument-hint: "[<owner>/]<name> [--archetype=cli|library|backend|data-ml|web] [--hosting=render|railway|digitalocean|fly|vps|home] [--private|--public] [--host=github|gitlab] [--third-party-review|--no-third-party-review] [--license=mit|apache-2.0] [--dir=<path>]; what is not given is asked"
disable-model-invocation: true
---

# New project

Creates `[<owner>/]<name>` on GitHub with the wall already up. When a step it
cannot go on without fails, it deletes the repository if its token can, and
names it otherwise. The owner is optional: a bare name goes under the user's login. One script does all of it; this skill runs it and relays what it says.

## Ask first what the arguments leave out

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
with no answer, ask the same question in text instead, with its choices
numbered, one question at a time. Never answer a question for the person.

1. **The name**, when the arguments carry none, in text (it has no choices):
   "What should the repository be called? (`name`, or `owner/name` for an
   organization)".
2. **The archetype**, when there is no `--archetype=`. Never choose `cli` for
   them in silence. Ask it in two steps.

   First, header `Kind`: "What are you making?"

   | Label | Description |
   | --- | --- |
   | A terminal command (cli) | A program people install and type in a terminal. If you are not sure, choose this one. |
   | Code other code imports (library) | Python code that other projects install and use, published as a package. |
   | Always-on server or data job | Something that keeps running: a service or API, or data processing and model training. It also checks that its container builds and starts. |
   | A website people log in to (web) | A website with logins and a database, on GitHub only, about $13 a month to run on Render. It also checks the container, the database changes and the production settings. |

   With `--host gitlab` in the arguments, leave out `web` and say once that
   web is made on GitHub only. For the third answer ask, header `Service`:
   "Is it a backend (a service or API) or data-ml (data processing or
   training a model)?"

   | Label | Description |
   | --- | --- |
   | A service or API (backend) | A program that keeps running and answers requests. It also checks that its container builds and starts. |
   | Data or a model (data-ml) | Data processing, or a model you train. It also checks the container, and comes with a model card and a test of the training. |

   Every kind gets the same checks besides (title, lint, types, tests,
   build, secrets, dependencies, change size, the project's own setup) and
   CodeQL; say so only if asked. In text, the same two steps. Add
   `--archetype=cli`, `library`, `backend`, `data-ml` or `web`.
3. **Where a web app runs**, for `web` only: the question in
   [Where a web app runs](#where-a-web-app-runs), unchanged.
4. **The recommended defaults.** Of host (`--host=`), visibility
   (`--private`/`--public`), the third-party reviewer
   (`--third-party-review`/`--no-third-party-review`), license (`--license=`)
   and directory (`--dir=`), take the ones the arguments do not give. If none
   is left, ask nothing. Otherwise ask one question, header `Defaults`,
   naming only those left with their defaults: "Use the recommended
   defaults? public on GitHub, MIT license, in `~/<name>`, no third-party
   reviewer." With `--host gitlab` given, say "private on GitLab.com" in
   place of "public on GitHub" and leave out the reviewer, which is GitHub
   only.

   | Label | Description |
   | --- | --- |
   | Yes (Recommended) | Create it with these. |
   | Customize | Choose each one. |

   Every answer becomes a flag, a default included, so that the command
   said before the run (below) asks nothing when typed again. **Yes** adds
   the flag for each default still open: `--host=github`, `--public`,
   `--no-third-party-review`, `--license=mit` and `--dir=<home>/<name>`,
   with the home directory written out as an absolute path; with
   `--host gitlab` given, `--private` in place of `--public`, and no
   reviewer flag. **Customize** asks each choice still open, leaving out
   what the arguments give and what does not apply: the host for `web`,
   which is GitHub only, and the reviewer on GitLab, which is GitHub only.
   Visibility and the reviewer depend on the host, so when the host is
   still open, ask in two calls: first the host and the license, then
   visibility and, on GitHub, the reviewer. When the host is already
   settled, ask visibility, the reviewer and the license in one call.

   - Header `Host`: "Where should the repository live?" **GitHub
     (Recommended)** (`--host=github`). **GitLab.com**: a GitLab.com
     project; needs `glab` installed and logged in (`--host=gitlab`).
   - Header `License`: "Which license?" **MIT (Recommended)**: short, the
     usual choice for a small project (`--license=mit`). **Apache-2.0**:
     when a company or the project you build on asks for it
     (`--license=apache-2.0`).
   - Header `Visibility`: "Public or private?" Public is `--public`,
     private `--private`, on either host. On GitHub, **Public
     (Recommended)**: the whole wall on every plan; **Private**: on GitHub
     Free a private repository cannot keep the ruleset, so plinth stops
     before creating it; on a paid plan it has no CodeQL or push protection
     unless the account has GitHub Code Security and Secret Protection; on
     a personal account, plinth reads the plan first, which needs the
     `read:user` permission on your GitHub login (it says the command that
     adds it). On GitLab, **Private (Recommended)**: plinth's default there,
     since GitLab.com's free plan protects a private project's main branch;
     **Public**: anyone can read it.
   - Header `Reviewer`, on GitHub only, asked as a fact the person knows,
     not a preference: "Is a code reviewer, such as Codex's, already
     connected to your GitHub account?" **No, or not sure (Recommended)**:
     `--no-third-party-review`; the last lines say when to turn it on.
     **Yes**: `--third-party-review`; each pull request gets a
     `third-party / review` result, which reports and is not required, so a
     pull request still merges without it. The last lines then say what to
     do right away: turn the reviewer on for the new repository.

   Then, when no `--dir=` was given, ask the directory on its own, header
   `Folder`: "Where should the local copy go?" with one choice,
   **`~/<name>` (Recommended)**, a new folder in your home directory
   (`--dir=<home>/<name>`, written out); another path is typed into Other
   and becomes `--dir=<path>`. It must not
   exist yet, or be empty.

   A typed answer that is none of the choices (other than the folder) is
   asked again.

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

The script checks tools, token, owner and visibility first and creates nothing
until all four pass. It then creates the repository, renders the template into
`~/<name>` (or `--dir`), pushes `main`, raises the ruleset and CodeQL, and
opens the first pull request. With `--third-party-review` the template also
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
  verbatim. It names the one fix. Do not work around it; do not run
  `gh repo create`, `gh auth`, or the script with different arguments.
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
  of them on. The next step for the user is to open
  the pull request URL, wait for the checks, and merge with squash. On
  GitHub, end with one line in the person's language: try typing
  `/plinth:guide` in the new repository's folder; it explains the whole way
  in plain words and names the command to type after this merge.

Do not edit the generated repository in this session.
