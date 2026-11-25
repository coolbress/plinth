# Template update: moving to another archetype

`/plinth:template-update --archetype <a>` follows this, on the person's word for each step, as [Moving to another archetype](SKILL.md#moving-to-another-archetype) in the skill says.

## Contents

- [Plan the move](#plan-the-move)
- [On GitLab](#on-gitlab)
- [A required check that stops or starts](#a-required-check-that-stops-or-starts)
- [The Actions allowlist](#the-actions-allowlist)
- [`release.yml` and the diff limit](#releaseyml-and-the-diff-limit)
- [Files this repository changed](#files-this-repository-changed)
- [The yes, and the conflicts a move leaves](#the-yes-and-the-conflicts-a-move-leaves)
- [What the pull request says](#what-the-pull-request-says)

## Plan the move

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/template-update.sh --archetype <a>
```

## On GitLab

On GitLab no check is required by name, so the required-check and Actions
allowlist steps below are GitHub's alone. There the plan names the jobs of
`.gitlab-ci.yml` that stop and start (`docker-image`, which `backend` and
`data-ml` carry), whether "Pipelines must succeed" is on with
skipped pipelines not counted, and whether the default branch is protected,
as `/plinth:floor-check` reads them on GitLab. When both hold, there is nothing
to change in the project's settings. When either does not, or was not read,
it names the `glab api` command a Maintainer runs with their own login, or
says to run `/plinth:floor-check`. Give the person that line; never run it
yourself.

## A required check that stops or starts

The plan runs the move on a copy of the default branch outside the
repository and prints what it deletes, adds and changes, any conflicts, and
the CI jobs that stop. When a job that stops is a required check (`image`,
moving from `backend` or `data-ml` to `cli` or `library`), it names the
`scripts/with-admin-token.sh` command that drops it. A required check that
no longer runs blocks every merge, so the person runs that command in a
separate terminal, with an admin token, before the move's pull request
merges. Never run it yourself, and never with your token. The plan writes
each such command to a file outside the repository and prints a short
`bash <that file>` line: give the person that line as printed. A
command of 300 characters pasted from a chat breaks into pieces, and
through `!` `with-admin-token.sh` has no terminal to ask for the token. When the move
starts a check (`image`, moving from `cli` or `library` to `backend` or
`data-ml`), it cannot be required before the move merges, since
`require-check.sh` refuses a name that has not run on the default branch.
The plan says whether the plinth the workflows call lets the move's own
`ci / floor-check` pass meanwhile. If it does, the order is: merge the move,
let the check run on the default branch, then the person requires it with the
command the plan names. If the default branch already requires the check,
there is nothing to add. Otherwise, if that plinth is older, the plan says to raise the
plinth pin first and gives no `--apply` line, and `--apply` refuses the move:
tell the person that, and plan the move again once the pin is raised.

## The Actions allowlist

The Actions allowlist does not move with the archetype either.
`/plinth:new-project` allows the release actions of the archetype it
renders, so after a move `release.yml` or the image workflows can call an
action the allowlist refuses (`pypa/gh-action-pypi-publish` moving to `cli`,
`docker/setup-buildx-action` and `docker/build-push-action` moving to
`backend`). Such a run ends in `startup_failure` with no job, though the
move's own checks were green. The plan reads the allowlist and names each
refused action with the `scripts/with-admin-token.sh gh api` command that
allows it. The person runs it, as for a required check, before the move's
pull request merges. When the allowlist cannot be read, the plan says so.

## `release.yml` and the diff limit

`release.yml` is rewritten whole by a move between an archetype that
publishes to PyPI (`cli`, `library`) and one that publishes an image
(`backend`, `data-ml`): 560 to 576 lines, more than `ci / diff-size`'s
default limit of 400 by itself, and no split by file can cut one file
(measured on plinth-template v1.50.1 and v1.50.2). `ci / diff-size`
from a plinth with the rule leaves it out of the count in the pull request
that changes `archetype:` and keeps `_commit:`, and names it in its summary;
that pull request's `archetype:` change already asks an admin's approval
when the account that pushed is not an admin. The plan says which applies:

- The plinth the workflows call has the rule: nothing to do. On exit 4,
  follow the split as in [step 3](SKILL.md#3-what-it-says). `release.yml` stays with
  `.copier-answers.yml` in the last part, listed as not counted, and that
  part opens within the limit. Never cut `release.yml` by hand.
- It does not: the plan says to raise the plinth pin first and gives no
  `--apply` line, and `--apply` refuses the move. Tell the person, and plan
  the move again once a pull request moving every `coolbress/plinth` `uses:`
  line to the version the plan names is merged.
- It was not read: the plan says so and still gives the `--apply` line. Tell
  the person the move's last part fails `ci / diff-size` if that plinth is
  older than the version the plan names.

## Files this repository changed

copier deletes a file of the old archetype that the project changed as
readily as one it left alone, and reports no conflict for it. The plan
compares each file the move deletes with the old archetype's own render, and
lists the ones that differ apart: "Changed by this repository, and the move
deletes them". For each, show the person what they changed
(`git diff` against the old archetype's version, or the file itself) and ask
whether to keep it (`--keep <path>`: restored after copier, as the project's
own file) or let it go (`--drop <path>`). Never choose for them: `--apply`
stops before writing anything until each is named once.

## The yes, and the conflicts a move leaves

Show the plan whole, and ask whether to apply exactly that. On a yes:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/template-update.sh --apply <sha from the plan> --archetype <a> [--keep <path> | --drop <path>]... --assisted-by <agent>:<model>
```

Exit codes are as in [step 3](SKILL.md#3-what-it-says). On exit 3 the script also shows this
repository's side of each conflict. For a `data-ml` project whose model files
were already deleted by hand, expect three conflicts (measured with copier
9.18.2 and 9.19.1): `pyproject.toml`, `src/<package>/__main__.py` and
`uv.lock`. First show the person their side of each, and name any code in it
that is theirs, beyond what the old archetype rendered and the hand deletion
left: a function, a dependency, a subcommand. If there is any, stop there and
ask how to keep it. Otherwise recommend the template's side for each file.
On their word, take that side in all three, run `uv lock` in the worktree
once `pyproject.toml` is resolved, and `git add` the three. Then run the
`--finish` line with one `--resolved` per file, for example
`--resolved uv.lock "the template's side, then uv lock, on the user's word"`.

## What the pull request says

Files the new archetype adds, such as `tests/test_built_wheel.py` when
moving to `cli`, go into the same commit. The description lists what the
move deleted and added, and what a person does by hand: the required check
to drop or add, the actions to allow, and each changed file with the
person's choice. Outside the files, only the required checks and the Actions
allowlist change with the archetype: the labels are one
list for every archetype, and `/plinth:floor-check` reads the archetype from
`.copier-answers.yml`, so after the move it expects the new archetype's files
and no longer the old one's.
