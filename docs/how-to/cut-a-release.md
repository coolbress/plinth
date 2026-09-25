# How to cut a release

Release plinth: bump both manifests, publish the version's `CHANGELOG.md`
section as the GitHub Release, and tag the merged commit. For what a release
promises, see [About pins](../explanation/concepts.md#about-pins).

## Before you start

You need a clone whose `main` equals `origin/main` with no uncommitted changes
to tracked files, and `gh` logged in with write access to the repository.

## Steps

1. Read the template tag the door pins:

   ```bash
   sed -nE 's/^template_ref="([^"]+)"$/\1/p' scripts/new-project.sh
   ```

2. Write the why in a file outside the repository, for example
   `$TMPDIR/why.md`: a short paragraph on why this release exists, and one
   line `tested with plinth-template <tag>` with the tag from step 1. Use no
   heading lines.
3. Run the script once, from the up-to-date `main`:

   ```bash
   scripts/make-release.sh vX.Y.Z "$TMPDIR/why.md"
   ```

   It bumps `version` in both manifests, moves the `Unreleased` entries under
   the new version's heading with your why above them, and commits on
   `release/vX.Y.Z`.
4. Push that branch and open a pull request titled `chore(release): vX.Y.Z`.
   Land it as [CONTRIBUTING.md](../../CONTRIBUTING.md#land-a-change) says.
5. Update `main`: `git switch main && git pull --ff-only`.
6. Start the `e2e` workflow on the merged commit, and wait for it to pass:

   ```bash
   gh workflow run e2e.yml --ref main
   ```

   If a nightly run already passed on that exact commit, skip this step.
7. Run the same command again:

   ```bash
   scripts/make-release.sh vX.Y.Z "$TMPDIR/why.md"
   ```

   It pushes the annotated tag and creates the GitHub Release from the
   version's `CHANGELOG.md` section. The tag goes on the commit that set the
   version: a pull request merged after it stays unreleased. It does not read
   the why-file this time, so any clone at the merged `main` can run it.
8. Tell installers to run `claude plugin update plinth`, then `/reload-plugins`.

## If the script refuses

| It says | Do this |
| --- | --- |
| The why must say what this release was tested with | Add the exact line it prints; if you tested another template tag, raise the pin first ([How to upgrade the template pin](upgrade-the-template-pin.md)) |
| The why says nothing but the tested line | Add a sentence on why the release exists |
| The why has a heading line | Remove every line that starts with `#` |
| The version is not above the current one | Pick the next version |
| The tag or the release already exists | Pick the next version |
| `release/vX.Y.Z` already exists on origin | Finish that release, or delete the leftover branch |
| Run this from `main` | `git switch main` |
| Shallow clone | `git fetch --unshallow` |
| A local tag points elsewhere (run 2) | `git tag -d vX.Y.Z`, then run step 7 again |
| `main` has uncommitted changes or differs from `origin/main` | Commit or discard them, then `git pull --ff-only` |
| No green `e2e` run on the commit (run 2) | Wait for the run you started; if it failed, read its log and dispatch it again. If `main` moved past the release commit, dispatch it from a branch at that commit |
| The section's why fails a check (run 2) | Fix the version's section of `CHANGELOG.md` in a pull request, merge it, and run step 7 again |
