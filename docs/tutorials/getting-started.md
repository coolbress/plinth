# Getting started

This tutorial walks from an empty machine to a merged first pull request:
install plinth, create a repository with the required checks already enforced,
and merge the pull request the generator opens for you.

## Before you start

- Tools: `claude` (2.1.274 or newer), `gh`, `git`, `uv`. The generator checks
  all four and names the missing one. Installing the plugin needs git 2.37 or
  newer: an older one (the macOS system git can be 2.30) fails with
  `index.lock: File exists`. `brew install git` fixes it.
- Log in to GitHub with `gh auth login -s repo,workflow,delete_repo`
  (browser login). The default scopes lack `workflow`, which the generator
  needs. `delete_repo` is optional: with it, a run that fails deletes the
  repository it created; without it the generator prints `rollback: off` and
  goes on, as the last bullet under [Create the repository](#create-the-repository) says.
  The same login is administration on every repository you own, and an
  agent working with it can change a repository's rules or delete it
  ([who can change the wall](../explanation/concepts.md#about-who-can-change-the-wall)).
  The command runs from inside a Claude Code session too: it prints a
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
create you/my-app (public, MIT, cli, as owner) from coolbress/plinth-template@v1.31.0 in /home/you/my-app; wall: ruleset + CodeQL; then the first pull request. rollback: on
```

It takes a few minutes, most of them waiting for GitHub to run the first
checks; the last lines are the result. Unless you say otherwise the repository
is public, under the MIT licence and a command-line program (`cli`), which is
what the example line's `(public, MIT, cli, ...)` says. To choose otherwise,
add to the command:

- `--private`: only on a plan that can hold the wall on a private repository
  ([Before you start](#before-you-start)). On a personal account the
  generator reads your plan first, which needs the `read:user` scope that
  the login above does not ask for: log in with
  `gh auth login -s repo,workflow,delete_repo,read:user`, or add it to the
  login you have with `gh auth refresh -h github.com -s read:user`. Without
  it the generator stops and prints that command.
- `--license=apache-2.0`: the template's other licence. Take it when your
  company, or the project you build on, asks for Apache-2.0; MIT is shorter
  and the usual choice for a small project.
- `--archetype=<kind>`: `library` for code other programs import; `backend`
  for a service that answers over the network; `data-ml` for data or
  machine-learning work; `web` for a web app with a database, which costs
  money to run (about US $13 a month on Render;
  [where else it can run](../how-to/choose-where-a-web-app-runs.md)). When
  unsure, keep `cli`, the narrowest.

If a check fails it stops there and prints the fix. Three you may meet:

- `gh's token lacks the scope(s)`: run the printed
  `gh auth refresh -h github.com -s repo,workflow,delete_repo`. Like the
  login, it runs from inside Claude Code, prints a one-time code and a URL,
  and a browser finishes it. Unset `GH_TOKEN` and `GITHUB_TOKEN` first if
  either is set: `gh` uses them before any login it stores. If that leaves
  `gh` with no login, the refresh has nothing to refresh: run
  `gh auth login -s repo,workflow,delete_repo` instead.
- `gh is using a fine-grained token`: either of two fixes. The browser login
  is shorter, but its token is scoped `repo` across the account rather than
  to selected repositories; the admin-token path keeps the fine-grained
  token's narrow reach.
  1. `gh auth login -s repo,workflow,delete_repo`, as in
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

When it finishes it prints the repository URL, the local directory, and the
URL of the first pull request.

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

Then, in the repository's folder, `git switch main && git pull`: the
generator left the checkout on the pull request's branch, and the next
session starts from `main`.

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
- To move plinth to a new version later: `claude plugin update plinth`, then
  `/reload-plugins`. From v1.10.0 or earlier, also run
  `claude plugin update taste-skill@plinth` once before `/reload-plugins`
  (plinth's issue [#469](https://github.com/coolbress/plinth/issues/469)). From v1.11.0 or earlier, also run, once and in this order,
  `claude plugin install plinth@plinth` and then `claude plugin prune` before
  `/reload-plugins`: `mattpocock-skills` moved to plinth's marketplace under
  the same name, and `update` does not install the moved copy. Without the
  two commands nothing is lost: the official copy keeps all 25 of its skills,
  and plinth reports the missing dependency with the command to run. `prune`
  removes the official copy only where it arrived as plinth's dependency; one
  you installed yourself stays beside plinth's ([#477](https://github.com/coolbress/plinth/issues/477)). From v2.1.0 or earlier,
  `claude plugin prune` after the update also removes `/ponytail-audit`,
  which plinth now lists instead of installing; without it the skill keeps
  working ([#598](https://github.com/coolbress/plinth/issues/598)).
