# How to make your own check required

You added a check of your own, a job in one of your workflows, and you want
pull requests to wait for it before they can merge. That means adding its
name to the repository's ruleset, the list of rules the default branch keeps.
`scripts/require-check.sh` adds one name, after making sure the name will
actually arrive.

Why that matters: a pull request waits for every name on the list. A name
that never reports, because it is misspelled or its job does not run, holds
every pull request forever, and nothing merges until someone with
administration removes it.

## Before you start

- **The check has run on the default branch.** Merge the workflow that adds
  it first, and let it run on that merge. The script looks at the last ten
  commits there. A workflow that runs only on pull requests never reports
  there: add `push` to its `on:` for the default branch, as plinth's own
  `ci.yml` does, and merge that.
- **The job has no `if:`.** A job with `if:` is skipped when the condition
  is false. A skipped job counts as a pass without running, and a skipped
  call to a reusable workflow reports no name at all, so nothing merges. Put
  the condition on the job's steps instead, so the job always runs and
  reports.
- **You run it, not the agent.** Changing the ruleset needs a login that
  administers the repository. The agent's token has no Administration
  ([the agent's token](give-the-agent-a-token.md)), so it cannot run this,
  and that is on purpose: the ruleset is what holds the agent to the checks.

## Make it required

1. Find the name exactly as GitHub shows it: on a merged pull request, open
   the **Checks** tab, or look at the list under the last commit on the
   default branch. A job called through a reusable workflow is named
   `<calling job> / <job>`, like `ci / lint`.
2. In a separate terminal window, not with `!` in Claude Code, go to your
   repository's folder and run:

   ```bash
   scripts/with-admin-token.sh scripts/require-check.sh '<check name>'
   ```

   Both scripts are in plinth's folder. If you do not have it at hand, ask
   the agent: "print the full path of plinth's `scripts/require-check.sh`",
   and use that path for both. The first one asks for a token with
   administration (input is hidden, and it never lands in your shell
   history) and passes it to the second. Add `--dry-run` before the name to
   see what would change first.
3. Read what it printed. On success it lists every name the ruleset now
   requires, read back from GitHub. Your next pull request waits for the new
   one.

It works on the repository of the folder you run it in; `--repo <owner/name>`
names another one. It changes one thing: it adds the name to the required
checks of the ruleset that holds the pull request rule. Every other rule and
name stays as it was.

## When it refuses

Each refusal says what to fix, and changes nothing.

| It says | Why | What to do |
| --- | --- | --- |
| this login does not administer the repository | Your login, or the token you pasted, cannot change rulesets | Run it again through `with-admin-token.sh` with a token that has administration: classic with `repo`, or fine-grained with Administration: write |
| has never reported on the last ten commits | The name is misspelled, or the check has not run on the default branch | Copy the name from the list it prints, or make the workflow run on the default branch and merge that first |
| has `if:` | The job, or the job calling its workflow, can be skipped | Move the condition into the job's steps, merge that, try again |
| comes from app ..., not GitHub Actions | The check is posted by another service | `scripts/upgrade-ruleset.sh <owner/name> '<name>:<app id>'`, which takes any app |
| which GitHub runs itself | A check like CodeQL's default setup, which has no workflow file in the repository | CodeQL is required through its own rule already ([Required checks](../reference/required-checks.md#code-scanning-rule)) |
| cannot tell which job reports it | The job's name is set by an expression or a matrix, or the workflow uses a form the script does not read | Give the job a plain `name:`, or use `scripts/upgrade-ruleset.sh` and check the name yourself |

## Undo it

In the repository on GitHub: **Settings → Rules → Rulesets**, open the
ruleset, and remove the name under **Require status checks to pass**. That
also needs administration.

The checks plinth itself requires, and what each one means, are in
[Required checks](../reference/required-checks.md).
