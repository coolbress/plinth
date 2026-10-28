---
name: new-project
description: Create a new GitHub repository with required checks already enforced (with --host gitlab, a GitLab.com project with its wall). User-invoked only; creates a remote repository, and if a step that raises the wall fails, deletes it when the token can or names it when it cannot.
argument-hint: "[<owner>/]<name> [--license=<spdx>] [--archetype=cli|library|backend|data-ml|web] [--hosting=render|railway|digitalocean|fly|vps|home] [--dir=<path>] [--private] [--host=github|gitlab]"
disable-model-invocation: true
---

# New project

Creates `[<owner>/]<name>` on GitHub with the wall already up. When a step it
cannot go on without fails, it deletes the repository if its token can, and
names it otherwise. The owner is optional: a bare name goes under the user's login. One script does all of it; this skill runs it and relays what it says.

Run, with the user's arguments exactly as typed:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/new-project.sh $ARGUMENTS
```

With `--host gitlab`, put `PLINTH_ASSISTED_BY=<agent>:<model>` in front of it,
naming yourself as a commit trailer would (e.g. `Claude:claude-opus-5-5`): the
first merge request's description ends with that `Assisted-by` line.

The script checks tools, token, owner and visibility first and creates nothing
until all four pass. It then creates the repository, renders the template into
`~/<name>` (or `--dir`), pushes `main`, raises the ruleset and CodeQL, and
opens the first pull request. Last, it re-runs the failed jobs of `main`'s
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
  and `not verified:` line as printed. The next step for the user is to open
  the pull request URL, wait for the checks, and merge with squash. On
  GitHub, end with one line in the person's language: try typing
  `/plinth:guide` in the new repository's folder; it explains the whole way
  in plain words and names the command to type after this merge.

Do not edit the generated repository in this session.
