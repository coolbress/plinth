# How to upgrade the template pin

Move the plinth-template tag `/plinth:new-project` renders, and
`/plinth:floor-check` compares repositories against, to a newer release.
For why the tag is pinned, see [About pins](../explanation/concepts.md#about-pins).

## Before you start

The new tag must be a published release of `coolbress/plinth-template`, and
its own checks must have passed on the commit it tags.

## Steps

1. Branch from `origin/main` in a worktree, as
   [CONTRIBUTING.md](../../CONTRIBUTING.md#land-a-change) step 1 says.
2. Confirm the release exists:

   ```bash
   gh release view vA.B.C --repo coolbress/plinth-template
   ```

3. In `scripts/new-project.sh`, set `template_ref="vA.B.C"`. If the new tag
   needs a newer copier, raise `copier_version` and `copier_newer` in the same
   block.
4. List every other place the old tag appears:

   ```bash
   git grep -n 'vOLD' -- ':!CHANGELOG.md'
   ```

   Replace each: the README status line, the example output in
   `docs/tutorials/getting-started.md`, and the summary check in
   `tests/new-project-failpath.sh`. Run the command again; it prints nothing
   when you are done.
5. Under `## [Unreleased]` in `CHANGELOG.md`, add a `Changed` entry that says
   what an instance rendered at the new tag receives, and that
   `/plinth:floor-check` now reports a repository on the old tag as behind.
6. Run every check in [CONTRIBUTING.md](../../CONTRIBUTING.md#run-the-checks).
   With network, `tests/archetype-single-source.sh` reads the new tag's
   `copier.yml`. If it fails, the template changed which archetypes get a
   container image: change the set in `scripts/floor-check.py` to match, in
   the same pull request.
7. Open the pull request titled `chore(new-project): render plinth-template vA.B.C`.
8. In the next release, write `tested with plinth-template vA.B.C` in the why
   ([How to cut a release](cut-a-release.md)). Its `e2e` run is the first live
   render at the new tag.
