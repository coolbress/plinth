# Getting started

This tutorial walks from an empty machine to a merged first pull request:
install plinth, create a repository with the required checks already enforced,
and merge the pull request the generator opens for you.

## Before you start

- Tools: `claude` (2.1.234 or newer), `gh`, `git`, `uv`. The generator checks
  all four and names the missing one.
- Log in to GitHub with `gh auth login` (browser login). Do not export
  `GH_TOKEN`; an agent session can read the environment.
- The repository will be **public**. Private repositories are not supported
  yet: the wall requires CodeQL, which needs a GitHub Code Security license there.
- The generated project is **Python (uv)**. Other languages are not produced
  by this version.
- Optional but recommended: run `/sandbox` once in Claude Code. The generator
  warns if it is off.

## Install plinth

<!-- install-block:start -->
```bash
claude plugin marketplace add coolbress/plinth
claude plugin install plinth@plinth
```
<!-- install-block:end -->

On a clean or CI machine, add the official marketplace first:
`claude plugin marketplace add anthropics/claude-plugins-official`.
One dependency lives there. Claude Code asks you to trust each marketplace the
first time; answer yes for these two.

Then start Claude Code and type `/plinth:arsenal` to see what was installed.

## Create the repository

```text
/plinth:new-project my-app
```

`my-app` is created under your GitHub login; `someorg/my-app` creates it in an
organization you belong to. Before creating anything the generator prints one
line with what it is about to do, for example:

```text
create you/my-app (public, MIT, cli, as owner) from coolbress/project-template@v2.18.0 in /home/you/my-app; wall: ruleset + CodeQL; then the first pull request. rollback: on
```

If a check fails it stops there and prints the one fix. Two you may meet:

- `gh is using a fine-grained token`: type the printed `with-admin-token.sh`
  line yourself, prefixed with `!`. It asks for an admin token at the
  terminal and never puts it on a command line.
- `rollback: off`: your token has no `delete_repo` scope. The generator
  continues; if it fails later the repository stays and it prints the URL to
  delete it by hand. `gh auth refresh -h github.com -s delete_repo` turns
  rollback on.

When it finishes it prints the repository URL, the local directory, and the
URL of the first pull request.

## Merge the first pull request

The generator opened a pull request titled `docs: first pull request through
the wall`. Its change is one line appended to `README.md`:

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
