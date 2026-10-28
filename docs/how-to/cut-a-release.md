# How to cut a release

Release plinth: bump both manifests, publish the version's `CHANGELOG.md`
section as the GitHub Release, and tag the merged commit. For what a release
promises, see [About pins](../explanation/concepts.md#about-pins).

## Before you start

You need a clone whose `main` equals `origin/main` with no uncommitted changes
to tracked files, and `gh` logged in with write access to the repository.

If the template pin moved since the release before, step 3 checks whether
the move changes what a new project's agent reads, and then asks for
[the eval suite](run-the-eval-suite.md)'s table or the reason it was not run
(step 2).

## Steps

1. Read the template tag the door pins:

   ```bash
   sed -nE 's/^template_ref="([^"]+)"$/\1/p' scripts/new-project.sh
   ```

   Beside it, `template_sha` is the commit that tag named when it was
   tested. It moves only with `template_ref`, in the pin pull request
   ([How to upgrade the template pin](upgrade-the-template-pin.md)), never
   in a release: both doors, `/plinth:floor-check` and
   `/plinth:template-update` stop when the tag names another commit (#519).

2. Write the why in a file outside the repository, for example
   `${TMPDIR:-/tmp}/why.md`: a short paragraph on why this release exists, and one
   line `tested with plinth-template <tag>` with the tag from step 1. Use no
   heading lines.

   If that tag is not the one the release before was tested with (the
   `tested with` line of the previous version's `CHANGELOG.md` section), the
   script reads the template's changes between the two tags. When they touch
   `template/AGENTS.md.jinja`, `template/CLAUDE.md.jinja` or anything under
   `template/.claude/` (the settings, the output style, the default skills),
   the why needs one more line, either of:

   ```text
   eval suite: <https://github.com/coolbress/plinth/issues/647#issuecomment-<id>>
   eval suite not run: <the reason>
   ```

   For the first, run [the eval suite](run-the-eval-suite.md) and post its
   table on #647; the link is that comment's, in angle brackets (a bare link
   fails `ci / docs`). The line stays in the release's section and its
   GitHub Release, so whoever reads the release sees the table or the reason.
   A release whose pin did not move, or whose move touches none of those
   files, needs neither.
3. Run the script once, from the up-to-date `main`:

   ```bash
   scripts/make-release.sh vX.Y.Z "${TMPDIR:-/tmp}/why.md"
   ```

   It bumps `version` in both manifests, moves the `Unreleased` entries under
   the new version's heading with your why above them, and commits on
   `release/vX.Y.Z`.
4. Push that branch and open a pull request titled `chore(release): vX.Y.Z`.
   Land it as [CONTRIBUTING.md](../../CONTRIBUTING.md#land-a-change) says.
   It needs no third-party review: with `pass-release-pull-requests` on,
   `third-party / review` passes a pull request with exactly that title and
   a diff of run 1's shape (only the two manifests and `CHANGELOG.md`; each
   manifest's `"version"` line replaced by the title's, higher than before;
   `CHANGELOG.md` only adding lines, the replaced `[Unreleased]` link aside,
   so an edited note still passes) without
   summoning the reviewer, and its log says
   `release pull request: not summoned`
   ([what it passes without summoning](configure-the-third-party-reviewer.md#pull-requests-it-passes-without-summoning)).
   Merge when the checks are green; do not wait for a review that was not
   asked for. To have the release note read, a person posts the summons on
   the pull request; an agent does not write it (`AGENTS.md`).
5. Update `main`: `git switch main && git pull --ff-only`.
6. Start the `e2e` workflow on the merged commit, and wait for it to pass.
   It runs two jobs: `e2e`, the door's journey on a backend and then on a
   web repository, and `upgrade`, which updates
   a repository rendered at the template tag an earlier release pinned and
   checks that the tested plinth pin lands in it (#519). Both must pass:

   ```bash
   gh workflow run e2e.yml --ref main
   ```

   If `gh` answers HTTP 403, your login cannot run workflows: run the same
   command through `scripts/with-admin-token.sh` in a separate terminal
   window, not with Claude Code's `!`, which gives the token prompt no
   terminal:

   ```bash
   scripts/with-admin-token.sh gh workflow run e2e.yml --ref main
   ```

   If a nightly run already passed on that exact commit, skip this step.
7. Run the same command again:

   ```bash
   scripts/make-release.sh vX.Y.Z "${TMPDIR:-/tmp}/why.md"
   ```

   It pushes the annotated tag and creates the GitHub Release from the
   version's `CHANGELOG.md` section. The tag goes on the commit that set the
   version: a pull request merged after it stays unreleased. It does not read
   the why-file this time, so any clone at the merged `main` can run it.
8. Tell installers to run `claude plugin update plinth`, then `/reload-plugins`,
   plus any one-time command the version's `CHANGELOG.md` section names (the
   first release after v1.10.0 names `claude plugin update taste-skill@plinth`;
   the first after v1.11.0 names `claude plugin install plinth@plinth` and then
   `claude plugin prune`, in that order).

## If the script refuses

| It says | Do this |
| --- | --- |
| The why must say what this release was tested with | Add the exact line it prints; if you tested another template tag, raise the pin first ([How to upgrade the template pin](upgrade-the-template-pin.md)) |
| The why says nothing but the tested line | Add a sentence on why the release exists |
| The why has a heading line | Remove every line that starts with `#` |
| The template pin moved and changes what a new project's agent reads | Run the eval suite and add `eval suite: <link>`, or add `eval suite not run: <the reason>` (step 2) |
| The `eval suite:` line must be the link to the comment | Give the comment's link alone, in angle brackets |
| More than one `eval suite` line | Keep one |
| Cannot read what the template changed | Check that `gh` is logged in and can reach GitHub, then run step 3 again |
| The previous section has no `tested with` line | Restore that line in the previous version's section of `CHANGELOG.md` in a pull request |
| The version is not above the current one | Pick the next version |
| The tag or the release already exists | Pick the next version |
| `release/vX.Y.Z` already exists on origin | Finish that release, or delete the leftover branch |
| Run this from `main` | `git switch main` |
| Shallow clone | `git fetch --unshallow` |
| A local tag points elsewhere (run 2) | `git tag -d vX.Y.Z`, then run step 7 again |
| `main` has uncommitted changes or differs from `origin/main` | Commit or discard them, then `git pull --ff-only` |
| No green `e2e` run on the commit (run 2) | Wait for the run you started; if it failed, read its log and dispatch it again. If `main` moved past the release commit, dispatch it from a branch at that commit |
| The section's why fails a check (run 2) | Fix the version's section of `CHANGELOG.md` in a pull request, merge it, and run step 7 again |
