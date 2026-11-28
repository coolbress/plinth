---
name: new-project
description: Create a new GitHub repository with required checks already enforced (with --host gitlab, a GitLab.com project with its wall). User-invoked only; creates a remote repository, and if a step that raises the wall fails, deletes it when the token can or names it when it cannot.
argument-hint: "[<owner>/]<name> [--archetype=cli|library|backend|data-ml|web|dashboard] [--hosting=render|railway|digitalocean|fly|vps|home|local] [--private|--public] [--host=github|gitlab] [--third-party-review|--no-third-party-review] [--code-of-conduct=<contact>|--no-code-of-conduct] [--description=<one line>|--no-description] [--records-language=<language in English>] [--no-custom-user-model] [--scheduled-run|--no-scheduled-run] [--calls-claude|--no-calls-claude] [--license=mit|apache-2.0|proprietary] [--dir=<path>]; what is not given is asked"
disable-model-invocation: true
---

# New project

Creates `[<owner>/]<name>` on GitHub with the wall already up. When a step it
cannot go on without fails, it deletes the repository if its token can, and
names it otherwise. The owner is optional: a bare name goes under the user's login. One script does all of it; this skill runs it and relays what it says.
Do not edit the generated repository in this session.

## Check first, before any question

First read the folder this session started in. It reads only local files,
with no network and no login:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/new-project.sh --where
```

It prints one `folder:` line, and `toplevel:` with the repository's top
folder when it is inside one. What each value asks, and when it asks
nothing, is [0. The folder](questions.md#0-the-folder) in the questions:
a folder that already holds a project gets that one question before
anything else, and only "New separate project" goes on to the host.

Then, only once the folder step goes on to the host (no folder question, or
**New separate project** chosen), and before reading the owner's files, read both
hosts' readiness; a hand-off or Cancel never reads it. It changes nothing: it asks `gh` and `glab` whether they are
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
descriptions as written, translated into the person's language. Where
the tool is not available (a `claude -p` run, for one) or a call comes back
with no answer, ask the same questions in text instead, in the same order,
with their choices numbered, one question at a time. Never answer a question
for the person. Never ask for a secret (a token, a password, an API key): none
is typed into the chat, and none of the questions needs one.

The questions themselves, with their labels, descriptions, defaults and
reasons, are in `${CLAUDE_PLUGIN_ROOT}/skills/new-project/questions.md`: read
it before the first question. In order:

1. **The host**, when there is no `--host`; then the preflight for it.
2. **What to make**, when there is no `--archetype=`, in text.
3. **Follow-ups**, only when that answer leaves the archetype open.
4. **The archetype recommendation**: the person always picks. For `cli`
   on GitHub, whether it also runs on GitHub on a schedule is part of it:
   a schedule word with the computer off recommends `--scheduled-run`.
5. **Where a web app runs**, for `web` on GitHub with no `--hosting=`; the
   person can read `${CLAUDE_PLUGIN_ROOT}/docs/how-to/choose-where-a-web-app-runs.md`
   first. **Where a dashboard runs**, for `dashboard` on GitHub with no
   `--hosting=`: on the person's computer, or on Render, where anyone with
   its address can read the page.
6. **The name**, when the arguments carry none, each checked with `--check`.
7. **Who may see the project**, when neither `--public` nor `--private` is given.
8. **Every answer in one table, before anything is created**, checked once
   with every flag it holds, then `Create` or `Change some`.

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

`--archetype=dashboard` is a Streamlit page of tables and charts, with no
login and no database. `--hosting=local` (the default) renders nothing to
deploy; `--hosting=render` renders a `render.yaml` for one web service, on
GitHub only: with `--host gitlab` the script refuses Render before it reads
anything on GitLab. It has no release workflow, so no tag ruleset.

`--scheduled-run` (cli only, GitHub only) also renders
`.github/workflows/schedule.yml`, which runs the command on GitHub every day
and by hand, even while the person's computer is off; each run's results are
a download under Artifacts on the run's page, never a commit. The Actions
allowlist and the ruleset are the same as without it: the workflow calls
GitHub's own actions only. With `--host gitlab` the script refuses it before
it reads anything on GitLab: a pipeline schedule was not tried.

`--calls-claude` (cli, dashboard or backend, GitHub only) adds the Anthropic
SDK and the one module that calls it; the key is never asked. With
`--host gitlab` the script refuses it before it reads anything on GitLab.

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
  type next and, until the first merge, explains this step and the next in
  plain words, and
  `/plinth:guide map` shows the whole way on one screen, and
  `/plinth:guide map <step>` one step in depth.
  When `--where` said anything but `empty` or `home` (the session started
  inside another folder or project), say first, in one line, where the new
  project is (its folder, written out) and that this session stays in the
  old folder: to work on the new project, open a new session there (`cd`
  into it, then `claude`).

Do not edit the generated repository in this session.
