# How to upgrade the template pin

Move the plinth-template tag `/plinth:new-project` renders, and
`/plinth:floor-check` compares repositories against, to a newer release.
For why the tag is pinned, see [About pins](../explanation/concepts.md#about-pins).

## When

Raise the pin once per plinth release, before cutting it
([How to cut a release](cut-a-release.md), step 1), to the template's latest
release, not once for each template tag. A tag the pin skips still
reaches the release: the later tag carries its changes, the release's `e2e`
run renders that later tag, and the eval suite question reads the template's
diff from the tag the release before was tested with, every tag between
included. Five tags were absorbed that way
(v1.20.0, v1.32.0, v1.34.0 to v1.36.0) before this was the rule (#954).

Raise sooner only when something in plinth needs the new tag to merge, such
as a change that tests what the template now renders.

## Before you start

The new tag must be a published release of `coolbress/plinth-template`, and
its own checks must have passed on the commit it tags.

## Steps

1. Branch from `origin/main` in a worktree, as
   [CONTRIBUTING.md](../../CONTRIBUTING.md#land-a-change) step 1 says.
2. Run the script with the tag and, from the template's checks or release
   page, the commit they passed on:

   ```bash
   scripts/raise-template-pin.sh vA.B.C abcdef0
   ```

   It reads the tag's commit from GitHub and stops, changing nothing, when
   the tag does not exist, is not a published release, or names another
   commit than the one given. Then it edits, each line only in the tag and
   the commit:

   - `template_ref` and `template_sha` in `scripts/new-project.sh`. Both
     doors stop before creating anything, and `/plinth:floor-check` prints no
     update line, while the tag names any other commit (#519);
   - the README status line, the example output in
     `docs/tutorials/getting-started.md` and the summary check in
     `tests/new-project-failpath.sh`;
   - the `canary-template` job's `name:` in `.github/workflows/ci.yml`;
   - one `Changed` line in the changelog fragment
     `changelog.d/template-pin.md`, or, when an earlier raise since the
     release wrote one, that line's tag.

   It prints whether the next release owes [the eval suite](run-the-eval-suite.md):
   owed when the template's diff from the tag the last release was tested
   with to the new tag changes `template/AGENTS.md.jinja`,
   `template/CLAUDE.md.jinja` or anything under `template/.claude/`. It is
   the answer `scripts/make-release.sh` reaches in run 1, read the same way.
   Then it prints what is left, the steps below. If the new tag needs a
   newer copier, raise it in `tools/copier/pyproject.toml` and run
   `uv lock --project tools/copier`, or merge Dependabot's pull request that
   does (#1220).
3. Re-render `canary-template/`, the new tag's `cli` project that the
   `canary-template` job runs through this commit's `python-ci.yml`:

   ```bash
   tests/template-render.sh --write
   ```

   If the rendered `.github/workflows/ci.yml` grants or passes something new
   in its `ci` job, copy it into the `canary-template` job too.
   Then copy the two `FROM` lines of the new tag's
   `template/Dockerfile.jinja` into `canary-web/Dockerfile`: its base images
   move with the pin, since `ci / web-audit` builds and starts that image
   without scanning it.
   `tests/template-render.sh` fails until the render, the name, the copy and
   canary-web's `FROM` lines all match the new pin (#953, #975).
4. The script lists every other line still naming the old tag or its commit.
   Change each, or keep one that names the release a thing arrived in, such
   as "from plinth-template v1.45.0".
5. Finish the line in `changelog.d/template-pin.md`: what an instance rendered at the new tag
   receives (`gh release view vA.B.C --repo coolbress/plinth-template`), and
   that `/plinth:floor-check` now reports a repository on the old tag as
   behind. If the new tag's `plinth_sha` default moved (the script says so
   when `copier.yml` changed), say which plinth a new project calls, but do
   not write that an update moves an existing repository's plinth pin:
   `/plinth:template-update` keeps the pin its workflows call and never
   moves it. The order is the pin pull request first, then the update: when
   the tag's pin is newer than the one a repository's workflows call, the
   update's plan stops before writing anything and names the pull request
   that raises the pin (Dependabot's, or the change to make in one), to merge
   first; the update runs after that, with no pin choice (#511, #1183). Say
   so in the line when the default moved: an existing repository needs its
   pin raised before this update.
6. Run every check in [CONTRIBUTING.md](../../CONTRIBUTING.md#run-the-checks).
   `tests/archetype-single-source.sh` reads the new tag's `copier.yml`, from
   the checkout `tests/lib/template-checkout.sh` makes. If it fails, the
   template changed which archetypes get a container image: change the set in
   `scripts/floor-check.py` to match, in the same pull request.
7. Open the pull request titled `chore(new-project): render plinth-template vA.B.C`,
   saying what the release brings and the script's eval suite line.
8. In the release, write `tested with plinth-template vA.B.C` in the why
   ([How to cut a release](cut-a-release.md)), and the eval suite line when
   it is owed. Its `e2e` run is the first live render at the new tag.
