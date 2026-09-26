# Getting started

This tutorial walks from an empty machine to a merged first pull request:
install plinth, create a repository with the required checks already enforced,
and merge the pull request the generator opens for you.

## Before you start

- Tools: `claude` (2.1.234 or newer), `gh`, `git`, `uv`. The generator checks
  all four and names the missing one. Installing the plugin needs git 2.37 or
  newer: an older one (the macOS system git can be 2.30) fails with
  `index.lock: File exists`. `brew install git` fixes it.
- Log in to GitHub with `gh auth login -s repo,workflow,delete_repo`
  (browser login). The default scopes lack `workflow`, which the generator
  needs; `delete_repo` lets a failed run delete the repository it created.
  The command runs from inside a Claude Code session too: it prints a
  one-time code and a URL, and a browser finishes it. No terminal is needed
  and nothing secret is typed. Do not export `GH_TOKEN`; an agent session can
  read the environment.
- The repository will be **public**. Private repositories are not supported
  yet: the wall requires CodeQL, which needs a GitHub Code Security license there.
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
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin marketplace add coolbress/plinth
claude plugin install plinth@plinth
```
<!-- install-block:end -->

The first line adds Anthropic's official marketplace, where one dependency
lives; where it is already added, the line only says so. Claude Code asks you
to trust each marketplace the first time; answer yes for these two.

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
create you/my-app (public, MIT, cli, as owner) from coolbress/plinth-template@v1.5.3 in /home/you/my-app; wall: ruleset + CodeQL; then the first pull request. rollback: on
```

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
     from a shell startup file (`~/.zshrc`, `~/.bashrc`); remove them there,
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
enables only when every required check is green; that is the wall, and nobody
can push past it, including you.

A red check: click **Details** and read the last lines of the log. Fix it in
the branch and push; the checks run again.

When everything is green, **Squash and merge**. That is the whole journey:
install, create, merge.

## Next

- `cd my-app && claude`, then `/plinth:floor-check` to read the wall from
  the inside.
- To move plinth to a new version later: `claude plugin update plinth`, then
  `/reload-plugins`.
