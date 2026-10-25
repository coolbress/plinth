# How to run the eval suite

The eval suite gives Claude Code the same four small tasks three ways and
checks the results afterwards:

- **none**: the project plinth renders, without `AGENTS.md`, `CLAUDE.md`
  and `.claude/`, and with no plugins;
- **repo-only**: the project as plinth renders it, plugins off;
- **plinth**: the project as plinth renders it, with plinth on.

It prints one table, so you can see whether a change still helps or got
worse. Run it before a release that changes the files the agent reads in a
new project (`AGENTS.md`, `.claude/`, the output style) or one of plinth's
default skills. You do not need it for other releases. It never runs in CI,
because it uses your Claude usage and needs a login.

## Before you start

You need:

- a clone of plinth, with the change you want to test checked out;
- Claude Code, `git`, `uv`, `python3` and `perl` (macOS and most Linux
  systems have `perl` already);
- a network connection: the suite downloads the project template and its
  Python packages;
- about an hour. The whole suite is 36 runs, one after another.

## What it costs

Each run reports what it would cost at Claude's API list prices. The suite
adds these numbers up and stops on its own:

- **The ceiling.** Before each run it adds up what the runs so far cost.
  Once the total reaches the ceiling, it starts no new run, prints the
  table for the runs it did, and exits with status 3. The ceiling is US$10
  unless you set another one with `--ceiling`, for example `--ceiling 5`.
  A run can also spend no more than US$2, or what is left under the
  ceiling if that is less, so the total can go over the ceiling by at most
  the run in progress.
- **A full suite** cost about US$5 the first time (36 runs).
- **The money is an estimate.** If you log in with a Claude subscription
  (claude.ai), the runs use your subscription's usage limits, and you are not
  charged that amount unless you have turned on extra usage. If you log in with
  an API key, the estimate is close to what is billed.

## Steps

1. From the top folder of your plinth clone, run:

   ```bash
   scripts/eval-suite.sh
   ```

2. It makes a temporary Claude Code configuration folder and installs
   plinth into it from your clone. Your own configuration (`~/.claude`)
   is not used or changed.
3. It asks you to log in, in that temporary folder only: a browser opens.
   Log in with the account whose usage you want to spend.
4. It renders the two starting projects from the template version plinth
   pins, then runs the tasks. Each run prints one line with its cost.
   You can leave it alone.
5. At the end it prints the table, and the folder that keeps every run's
   record, including each session's full log and final report.
6. The temporary configuration folder, with its login, is deleted when
   the script ends, also when it stops early on an error.
   The records folder is kept; delete it when you no longer need it.

## Smaller runs

The full suite is four tasks × three arms × three runs. To try one thing,
name it:

```bash
scripts/eval-suite.sh --task ledger --arm plinth --runs 1
```

`--task` and `--arm` can be given more than once. The tasks are `cli-name`,
`ledger`, `about` and `greeting-push`; the arms are `none`, `repo-only` and
`plinth`. `--model` picks the model (default `sonnet`), and `--out` names a
new folder for the records.

## Reusing a logged-in folder

To skip the login, pass a temporary configuration folder you logged in to
before, with plinth installed:

```bash
scripts/eval-suite.sh --config-dir /path/to/that/folder
```

This folder is **not** deleted at the end; delete it yourself when you are
done. The suite refuses `~/.claude`, the folder in `CLAUDE_CONFIG_DIR`, your
home folder, and any folder inside or around one of them.

## What it does not touch

- **GitHub.** Each run's `origin` is a bare Git repository in the records
  folder, and the session starts with `gh` logged out: no token variable,
  and an empty `gh` configuration. No run creates or reads a GitHub
  repository. The only GitHub download is the public project template.
- **Your Claude Code login.** An API key or token in your environment
  (`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`)
  is not passed to the sessions, so they use the temporary folder's login.

## Reading the table

| Column | Means |
| --- | --- |
| Task passed | the hidden test, run after the session, passed in the checkout or a worktree the agent left |
| Checks pass | `ruff check`, `ruff format --check`, `mypy` and `pytest` all passed in that same tree |
| Pushed to `origin/main` | the agent moved `main` on the remote |
| Pushed a branch | the agent pushed a branch other than `main` |
| `Assisted-by` | a commit it made carries that trailer |
| Turns, Tokens, Cost | the middle value over the runs |

Under the table it prints the total cost and how many risky commands were
run (a force push, a merge, `gh repo create`, `--no-verify`, `rm -rf`, a
workflow edit). Post the table where the release is discussed; keep the
records folder out of the repository.
