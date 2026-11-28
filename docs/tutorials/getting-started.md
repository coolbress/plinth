# Getting started

This tutorial walks from an empty machine to a merged first pull request:
install plinth, create a repository with the required checks already enforced,
and merge the pull request the generator opens for you.

## Before you start

- Tools: `claude` (2.1.274 or newer), `gh`, `git`, `uv`, `python3`. The
  generator checks all five and names the missing one. Installing the plugin needs git 2.37 or
  newer: an older one (the macOS system git can be 2.30) fails with
  `index.lock: File exists`. `brew install git` fixes it.
- Log in to GitHub. The login you create the project with can administer
  every repository your account owns, not only the new one, and an agent
  working with it can change a repository's rules
  ([who can change the wall](../explanation/concepts.md#about-who-can-change-the-wall));
  after the first merge the agent moves to a token without that, as the
  `administration:` line and [Next](#next) say. The login the run needs is
  `gh auth login -s repo,workflow` (browser login). The default scopes lack
  `workflow`, which the generator needs.
- `delete_repo` is an opt-in: `gh auth refresh -h github.com -s delete_repo`
  adds it to that login. With it, a run that fails deletes the repository it
  created, and the login can delete any repository it administers. Without
  it the generator prints `rollback: off` and goes on (a private repository
  whose plan it cannot read is the exception: see `--private` below); a run that fails then
  leaves the repository and prints its settings page for you to delete it,
  as the last bullet under [Create the repository](#create-the-repository) says.
- The login command runs from inside a Claude Code session too: it prints a
  one-time code and a URL, and a browser finishes it. No terminal is needed
  and nothing secret is typed. Do not export `GH_TOKEN`; an agent session can
  read the environment.
- The repository will be **public**. `--private` works on GitHub Pro, Team or
  Enterprise, with some parts of the wall left out unless the repository has
  GitHub Code Security and Secret Protection
  ([about private repositories](../explanation/concepts.md#about-private-repositories)).
- The generated project is **Python (uv)**. Other languages are not produced
  by this version.
- Claude Code's sandbox (`/sandbox`) is optional. On macOS, measured on Claude
  Code 2.1.278, it stops `gh` (the floor's `Read(~/.config/gh/**)` deny is
  enforced against `gh` itself; anthropics/claude-code#95135, #67105) and the
  generator's `uvx --from copier copier` step, so this tutorial does not
  complete with it on there. Linux and WSL2 were not measured.

## Install plinth

<!-- install-block:start -->
```bash
claude plugin marketplace add coolbress/plinth
claude plugin install plinth@plinth
```
<!-- install-block:end -->

Neither command asks a question; each ends with a line that starts
`✔ Successfully` (measured on Claude Code 2.1.307).

Then start Claude Code and type `/plinth:arsenal` to see what was installed.

## Create the repository

```text
/plinth:new-project my-app
```

Type `/` and choose `plinth:new-project` from the list rather than pasting the
line: the skill is user-only, so the agent cannot run it and cannot see it. An
answer that it "is not installed" usually means the line reached the agent as
text (a leading space is enough); `/plinth:arsenal` shows what is installed.

`my-app` is created under your GitHub login; `someorg/my-app` creates it in an
organization you belong to. Run it from anywhere: the generator creates
`~/my-app` itself (`--dir=<path>` puts it elsewhere), and an existing directory
is fine as long as it is empty. Before creating anything the generator prints
one line with what it is about to do, for example:

```text
create you/my-app (public, MIT, cli, as owner) from coolbress/plinth-template@v1.52.0 in /home/you/my-app; wall: ruleset + CodeQL + v* tags kept; then the first pull request. rollback: on
```

Before any question, the generator reads whether `gh` and `glab` are
installed and logged in, and as whom, without changing anything. Then it asks
what the command did not say, in a picker (a window of choices; Other lets you
type an answer instead):

1. **Where should the repository live?** GitHub (recommended) or GitLab.com,
   each with what was just read beside it, for example "✓ gh logged in as
   you". Then it checks that host's tools, git's identity for the first
   commit (a name and email you set, not one git makes up from this
   computer's name), and the login and its token, and lists every item missing at once,
   each with its fix; say "done" and it checks again.
2. **What do you want to make?** A sentence or two in your own words; "I
   don't know" is an answer too. When that leaves the kind open, it asks how
   it will be used, or whether it trains a model.
3. **The kind it recommends**, with your words quoted as the reason and what
   it makes and does not make: a terminal command (`cli`), the one to choose
   when unsure, and also the choice for a tool that runs on a schedule on the
   owner's machine (a data collector, a pipeline), or on GitHub while your
   computer is off (asked when you describe a schedule); code other code imports
   (`library`); a service or API (`backend`); a model trained here, with a
   model card (`data-ml`; on GitHub a `v*` tag publishes the model, its
   metrics and the card as release files); a website people log in to
   (`web`, then where it runs); or a page of tables and charts with no login
   (`dashboard`, then whether it runs on your computer or on Render). A
   chatbot, an assistant or AI answers is the kind its interface fits,
   calling Claude (`--calls-claude`): a terminal is `cli`, a page
   `dashboard`, a service or a bot `backend`. Data processing, collection or a pipeline
   with no model trained is `cli`. Accept it, pick another kind, or say you
   are not sure (`cli`).
4. **The name**, when the command gave none: two or three suggestions in
   English that say what step 2 meant, each already checked (free, a folder
   not in the way, a name the kind's template takes); Other takes your own,
   checked at once.
5. **Who may see this project's code?** Anyone on the internet can read and
   copy it (public, recommended on GitHub; the licence recommended is MIT),
   or only you and the people you add (private; the licence recommended is
   Proprietary; recommended when your description mentions a company's,
   a customer's or personal data). On GitHub Free a private repository
   cannot keep the ruleset: the generator reads your plan at this answer and
   offers public instead, upgrading and starting again, or stopping. On
   GitLab.com private is the default.
6. **Every answer in one table.** The repository and its host, the kind,
   who may see it, the licence (MIT for a public project, Proprietary for a
   private one), on GitHub the third-party reviewer (none), the code of
   conduct (none, or your account's own when it publishes one) and the
   description (your sentence from step 2, cut to one line of 350
   characters), and the folder (`~/my-app`). The first button names what it
   does, for example "Create public repository you/my-app". **Change some**
   picks rows to change: the name and folder, the description, the licence,
   or the reviewer and code of conduct (a code of conduct asks where reports
   go); only those are asked, then the table comes back with the changed
   rows marked. To change who may see it, the kind or the host, type it into
   Other ("make it private"): that question comes back, and after the
   visibility the licence too.

Where the picker cannot be shown (`claude -p`), the same questions come as
text, numbered; at the table, you type 0 to create it as shown, or the
numbers of the rows to change, comma-separated.

A reviewer you say is connected gets the check `third-party / review` on
every pull request. It reports and is not required: a pull request still
merges without it. The last lines then start with what to do now: turn
code review on for the new repository in your Codex settings, or each pull
request waits 20 minutes for a review and shows a failed check. They also
say how to require the check once it has reported. Before it runs, the agent shows the whole command with your
answers as flags; type that next time and nothing is asked.

It takes a few minutes, most of them waiting for GitHub to run the first
checks; the last lines are the result. The example line's
`(public, MIT, cli, ...)` is what the defaults give. Each answer is a flag
you can type instead:

- `--private`: only on a plan that can hold the wall on a private repository
  ([Before you start](#before-you-start)). On a personal account the
  generator reads your plan first, which needs the `read:user` scope that
  the login above does not ask for: log in with
  `gh auth login -s repo,workflow,read:user`, or add it to the
  login you have with `gh auth refresh -h github.com -s read:user`. Without
  it the generator stops and prints that command. For an organization the
  plan is often unreadable (it is shown to the organization's owners), and
  then the run needs the rollback: without `delete_repo` it stops before
  creating anything and prints `gh auth refresh -h github.com -s delete_repo`.
- `--license=apache-2.0`: MIT's freedoms plus a patent grant. Take it when
  your company, or the project you build on, asks for Apache-2.0; MIT is
  shorter and the usual choice for a small public project.
- `--license=proprietary`: grants nothing; nobody else may use, copy or
  share the code without your permission. The agent recommends it for a
  private repository (`--private`, or GitLab's default).
- `--archetype=<kind>`: `cli`, `library`, `backend`, `data-ml`, `web` for
  a web app with a database, which costs money to run (about US $13 a month
  on Render; [where else it can run](../how-to/choose-where-a-web-app-runs.md), named
  with `--hosting=<place>`), or `dashboard` for a page of tables and charts
  with no login, on your computer (`--hosting=local`, the default) or on
  Render, about US $7 a month (`--hosting=render`, GitHub only).
- `--scheduled-run` (`cli` only, GitHub only): the command also runs on
  GitHub every day and by hand, even while your computer is off; each run's
  results are a download under Artifacts on the run's page, kept 90 days,
  never a commit. Runs can start late or be dropped when GitHub is busy, and
  in a public repository GitHub turns the schedule off after 60 days with
  no activity. `--no-scheduled-run`, the default, runs it on your computer
  only.
- `--calls-claude` (`cli`, `dashboard` or `backend`, GitHub only): the
  project calls Claude, a chatbot or an assistant among them. It gets the
  Anthropic SDK, the one place that calls it, tests that use a fake Claude
  and need no key, and README steps: make the API key later in a workspace
  of its own, set its spend limit and the organization's, and never paste it
  into a chat. `--no-calls-claude`, the default, adds none of it.
- `--third-party-review`: the reviewer's check, for an account with a code
  reviewer connected ([the reviewer](../how-to/configure-the-third-party-reviewer.md));
  `--no-third-party-review` says no without being asked.
- `--code-of-conduct=<email or page>`: a code of conduct, the Contributor
  Covenant 3.0, naming where reports go; not written when your account's
  `.github` repository already publishes one, which then applies.
  `--no-code-of-conduct` says no without being asked.
- `--description=<one line>`: the line under the repository's name on
  GitHub or GitLab.com, and under the title in `README.md`;
  `--no-description` leaves it empty.
- `--records-language=<language>`: the language the project's issues, pull
  requests and documents are written in, named in English (`Korean`);
  English when not given.
- `--no-custom-user-model`, for `web` only: start with Django's `auth.User`
  instead of the project's own `accounts.User`, which a new `web` project
  gets without being asked.
- `--public`, `--dir=<path>`, `--host=github`: the defaults, said out loud,
  so that nothing is asked.

If a check fails it stops there and prints the fix; the agent shows it and
says what each line means. A fix that is a command you type goes into
Claude Code's prompt with `!` in front, for example
`! gh auth refresh -h github.com -s repo,workflow`: the command
runs here and its output lands in the conversation. After installing a
program such as `uv`, quit Claude Code (`/exit`) and start it again, or it
does not see the new program. Four you may meet:

- `uv is not installed`: run the printed `curl … | sh` line with `!`, then
  restart Claude Code and type `/plinth:new-project` again.
- `gh's token lacks the scope(s)`: run the printed
  `gh auth refresh -h github.com -s repo,workflow`. Like the
  login, it runs from inside Claude Code, prints a one-time code and a URL,
  and a browser finishes it. Unset `GH_TOKEN` and `GITHUB_TOKEN` first if
  either is set: `gh` uses them before any login it stores. If that leaves
  `gh` with no login, the refresh has nothing to refresh: run
  `gh auth login -s repo,workflow` instead. The stop also names the
  `delete_repo` opt-in on its own line, as in [Before you start](#before-you-start).
- `gh is using a fine-grained token`: either of two fixes. The browser login
  is shorter, but its token is scoped `repo` across the account rather than
  to selected repositories; the admin-token path keeps the fine-grained
  token's narrow reach.
  1. `gh auth login -s repo,workflow`, as in
     [Before you start](#before-you-start), then run the generator again
     where you ran it. Unset `GH_TOKEN` and `GITHUB_TOKEN` first if either
     is set: `gh` uses them before any login it stores. They usually come
     from a shell startup file (`~/.zshrc`, `~/.bashrc`, or `~/.zshenv`,
     which every zsh reads, Claude Code's own shell included); remove them there,
     then restart Claude Code, and the login and the generator stay inside
     it, with no terminal switch.
  2. Copy the three printed lines (`P=...`, then `with-admin-token.sh`
     through it, then the arguments) as one block into a separate terminal
     window, not with `!` in Claude Code, which runs a line without a
     terminal. It asks for an admin token at that terminal and never puts it
     on a command line. The stop also prints a link that opens GitHub's
     fine-grained token form with its permissions filled in for your owner;
     the one choice left there is "All repositories".
- `rollback: off`: your token has no `delete_repo` scope. The generator
  continues; if it fails later the repository stays and it prints the URL to
  delete it by hand. `gh auth refresh -h github.com -s delete_repo` turns
  rollback on.

When it finishes, the last lines start with `done:` and the repository's
URL. Under it, after a line for each part a private repository or a host
other than Render leaves out: `local:`, the folder; `first pull request:`,
its URL, with what to do (wait for every check, then squash-merge); where the first day's
notes are; an `administration:` line, saying whether the login used here can
change the repository's rules, and so whether an agent using it could; and
the `next:` line:

```text
  next: cd /home/you/my-app && claude, then type /plinth:guide for the command after this merge, and /plinth:guide map for the whole way on one screen
```

A `to do now` block follows when you said a code reviewer is connected, then
a `starts off` block, listing what the project starts with turned off, when
each is worth turning on, and where its steps are. The agent adds a plain sentence for each
line.

## Merge the first pull request

The generator opened a pull request titled `docs: first pull request through
the wall`. Its change is a **First day** section appended to `README.md`,
three sentences for the next session: the push that clears a merge stuck on
CodeQL, adding the repository to a fine-grained token, and what to do with
the pull requests Dependabot opens from the first minute (its first usually
lands before the door's, which is why yours is #2, and after "Update branch"
the merge waits a minute or two for the checks, not for an approval). The
same three are in the pull request's body. Then the line:

```text
Made with [plinth](https://github.com/coolbress/plinth).
```

Open the pull request. The checks run for a few minutes. The merge button
enables only when every required check is green; that is the wall, and nothing
merges past it, including your own merge.

A red check: click **Details** and read the last lines of the log. Fix it in
the branch and push; the checks run again.

When everything is green, **Squash and merge**. From a terminal instead, the
command is in the repository's `CONTRIBUTING.md` (step 7); for this pull
request, with its number from the URL the generator printed (usually 2) and
`<sha>` from `gh pr view <n> --json headRefOid --jq .headRefOid`:

```bash
body="$(gh pr view <n> --json body --jq .body)" &&
  gh pr merge <n> --squash --match-head-commit <sha> --body "$body"
```

If you ask the agent to merge instead, Claude Code may first ask you to
approve its `gh pr merge` command: approving it is your merge, as in
[step 6 of Run a project](../how-to/run-a-project.md#6-merge-on-your-word).

Then do what the `next:` line said: `cd ~/my-app`, and there
`git switch main && git pull` first (the generator left the checkout on the
pull request's branch, and the next session starts from `main`). Then
`claude`, and type `/plinth:guide`: it names the command to type next and,
until this first pull request is merged, explains in plain words the step you
are at and the next one, each with its tool and how to use it. After the
first merge it says the command, what is open and what happened so far,
without that depth. `/plinth:guide map` shows the whole way on one screen,
each step with its command, and `/plinth:guide map <step>` one step in depth;
the map is worth reading once before this first merge.

If the `administration:` line said the login has it, do its link next, before
the agent works on its own: about five minutes for a token without that
permission ([Next](#next)).

That is the whole journey: install, create, merge.

## How the agent explains its work

When you open the new repository in Claude Code, its agent explains its work
in plain words: the repository turns on an output style named
`Beginner or non-engineer` for everyone who opens it. After each change the
agent says what changed and what you can check yourself; at a merge, a
template update or a failure it gives a decision report; before any choice it
recommends one option and asks you to confirm.
[What the agent tells you](../how-to/run-a-project.md#what-the-agent-tells-you-and-when)
shows what each part looks like.

To turn it off for yourself, type `/output-style default` in Claude Code
inside the repository. It writes `"outputStyle": "default"` to
`.claude/settings.local.json`, a file the repository's `.gitignore` keeps out
of commits. To have the style again, remove `"outputStyle": "default"` from
that file, with the comma that joins it to another setting if there is one,
so the file stays valid JSON.

## On GitLab instead

The same walk on GitLab.com, for a project that must stay private on a free
plan ([about GitLab](../explanation/concepts.md#about-gitlab)):

- Install `glab` 1.122.0 or newer (`brew install glab` on macOS), and log in
  with `glab auth login --hostname gitlab.com --web --git-protocol https`.
  The browser login keeps the token in the system keyring where there is
  one. Without one (a Linux or WSL machine with no Secret Service), glab
  writes it in plain text to `~/.config/glab-cli/config.yml` and prints a
  warning. The project's agent settings deny reading that directory, but the
  file stays on disk until you log in again with a keyring available. A
  personal access token needs the `api` scope.
- Type `/plinth:new-project my-app --host gitlab`. The project is created
  private under your GitLab username, or under `group/my-app` where you are a
  Maintainer or above. Rollback, which deletes the project if a later step
  fails, needs the Owner role.
- Its last lines name the first merge request, the first pipeline on `main`,
  and the wall. One line says what GitLab Free cannot hold: a merge request
  that drops a job still merges when what is left passes.
- Wait for the merge request's pipeline to pass, then merge it with the
  command in the project's `CONTRIBUTING.md`, which squashes it with the
  description as the commit body.
- Before the agent works on its own, take your login away from it. The
  browser login is your Maintainer or Owner role with the `api` scope, so an
  agent working with it can change `main`'s protection and the merge checks,
  or as Owner delete the project. Give the agent a login with the Developer
  role instead. A Developer pushes branches and opens merge requests, and
  cannot push to the protected `main` or change the project's settings. On
  GitLab.com Free, that login is a second account added to the project as a
  Developer, logged in to `glab` where the agent runs: project access tokens
  need Premium or Ultimate on GitLab.com. Keep your own login for merging
  and for `/plinth:floor-check`.
- Later, `/plinth:floor-check` in the project reads the wall back through
  `glab`, with your Maintainer login.

## Next

- [Run a project](../how-to/run-a-project.md): the loop from an idea to a
  merged change, what to type at each stage, and what to check before you
  merge.
- Before the agent works on its own, give it a token without workflow
  permission ([Give the agent a token](../how-to/give-the-agent-a-token.md)).
  The login above holds `workflow`, so an agent working with it can push a
  change to `.github/workflows/`, the checks included. Changes there then go
  through a credential that has it, pushed by you.
- `cd my-app && claude`, then `/plinth:floor-check` to read the wall from
  the inside.
- To move plinth to a new version later: `claude plugin marketplace update
  plinth`, then `claude plugin update plinth@plinth`, then `/reload-plugins`.
  A move from an older version can take one-time commands first:
  [Install, in detail](../../README.md#install-in-detail).
- Optional, to have new versions arrive by themselves, since third-party
  marketplaces do not auto-update by default: start a session outside any
  project, run `/plugin`, and choose Marketplaces, plinth, Enable auto-update.
  It also brings raised dependency pins, and the same menu turns it off.
  Inside a project the same choice rewrites that project's committed
  `.claude/settings.json`. The pass runs in a session after its first message,
  within about ten minutes, not when a session opens and not in `claude -p`
  ([When auto-update runs](https://code.claude.com/docs/en/plugins/loading#when-auto-update-runs)).
  The session then shows `Plugin updated: plinth · Run /reload-plugins to apply`
  and keeps the old skills until `/reload-plugins` or a new session:
  [what it does and what was measured](../../README.md#install-in-detail).
