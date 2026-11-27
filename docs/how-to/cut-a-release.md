# How to cut a release

Release plinth: bump both manifests, publish the version's `CHANGELOG.md`
section as the GitHub Release, and tag the merged commit. For what a release
promises, see [About pins](../explanation/concepts.md#about-pins).

## Before you start

plinth releases on a weekly train: at most one release a week, while pull
requests stay small and merge as often as they are ready. Each train carries
one template pin raise (step 1) and at most one eval-suite run (step 2).
Decided 2026-11-25 (#1132): every release costs an `e2e` run, a smoke run and
an update on each consumer, so the releases are batched and the merges are not.

A hotfix releases outside the train, only when:

- a published advisory reaches something plinth ships or pins;
- installing plinth as the README says fails; or
- a consumer's required check fails because of plinth.

The why-file then carries one line, `hotfix: <reason>`, and the release's
`CHANGELOG.md` section and GitHub Release say it. Run 1 holds the train:
when origin's highest `vX.Y.Z` tag is less than 7 days old and the why-file
has no `hotfix:` line, it stops before changing anything and names the tag
and its age. A `hotfix:` line with no reason always stops.

An early release that is not a hotfix goes out only when the owner decided
it in a comment, as on #1132 for v2.46.0. The why-file then carries one line
instead of `hotfix:`, the comment's link in angle brackets:
`train exception: <https://github.com/coolbress/plinth/issues/1132#issuecomment-7210202040>`.
Run 1 reads that comment with `gh` and stops when it cannot. The line stays
in the release's section and its GitHub Release. A why with both lines stops.

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

   If plinth-template has a newer release than that tag, raise the pin
   first, once for this release, to the latest one:

   ```bash
   gh release view --repo coolbress/plinth-template --json tagName --jq .tagName
   scripts/raise-template-pin.sh vA.B.C <commit>
   ```

   Its pull request ([How to upgrade the template pin](upgrade-the-template-pin.md))
   merges before step 3's run 1; then read the tag again. The script's eval
   suite line is the answer run 1 reaches.

   Beside it, `template_sha` is the commit that tag named when it was
   tested. It moves only with `template_ref`, in the pin pull request
   ([How to upgrade the template pin](upgrade-the-template-pin.md)), never
   in a release: both doors, `/plinth:floor-check` and
   `/plinth:template-update` stop when the tag names another commit (#519).

2. Write the why in a file outside the repository, for example
   `${TMPDIR:-/tmp}/why.md`: a short paragraph on why this release exists, and one
   line `tested with plinth-template <tag>` with the tag from step 1. Use no
   heading lines. A hotfix (see [Before you start](#before-you-start)) adds
   one line, `hotfix: <reason>`. When it tells a consumer to raise its plinth
   pin, name every
   `coolbress/plinth` `uses:` line (`ci.yml` and `label.yml`): one raised
   alone leaves two pins, and `/plinth:template-update` stops on them (#793).

   If that tag is not the one the release before was tested with (the
   `tested with` line of the previous version's `CHANGELOG.md` section), the
   script reads the template's changes between the two tags. When they touch
   `template/AGENTS.md.jinja`, `template/CLAUDE.md.jinja` or anything under
   `template/.claude/` (the settings, the output style, the default skills),
   the why needs one more line, one of:

   ```text
   eval suite: on the release candidate
   eval suite: <https://github.com/coolbress/plinth/issues/647#issuecomment-<id>>
   eval suite not run: <the reason>
   ```

   Use the first. The suite then runs once in step 5, on the release branch
   run 1 makes. That run also gives the smoke verdict, so no separate smoke
   run is needed (#1134). Its link cannot go in the commit it tests, so it
   goes in the release pull request's description, and step 8 puts it in the
   GitHub Release. The second line is for a run made before the candidate
   existed, with the smoke run still due in step 5; the link is the comment's,
   in angle brackets (a bare link fails `ci / docs`). Either way,
   [the release run](run-the-eval-suite.md#the-release-run),
   `scripts/eval-suite.sh --release`, runs
   the `repo-only` and `plinth` arms, three runs each, under a US$15 ceiling;
   it leaves out the `none` arm, which nothing a release changes reaches
   (#647's Decisions, "[the suite a release runs](https://github.com/coolbress/plinth/issues/647)"). The line stays in the release's section, and its
   GitHub Release shows the table's link or the reason.
   A release whose pin did not move, or whose move touches none of those
   files, needs neither.
3. Run the script once, from the up-to-date `main`:

   ```bash
   scripts/make-release.sh vX.Y.Z "${TMPDIR:-/tmp}/why.md"
   ```

   It bumps `version` in both manifests, writes the changelog fragments in
   `changelog.d/` under the new version's heading with your why above them,
   grouped by section, deletes the fragments, and commits on
   `release/vX.Y.Z`.
4. Push that branch and open a pull request titled `chore(release): vX.Y.Z`.
   It needs no third-party review: with `pass-release-pull-requests` on,
   `third-party / review` passes a pull request with exactly that title and
   a diff of run 1's shape (only the two manifests and `CHANGELOG.md`, and
   the `changelog.d/` fragments removed; each
   manifest's `"version"` line replaced by the title's, higher than before;
   `CHANGELOG.md` only adding lines, the replaced `[Unreleased]` link aside,
   so an edited note still passes) without
   summoning the reviewer, and its log says
   `release pull request: not summoned`
   ([what it passes without summoning](configure-the-third-party-reviewer.md#pull-requests-it-passes-without-summoning)).
   Do not wait for a review that was not
   asked for, and do not toggle draft to start one. To have the release note read, a person posts the summons on
   the pull request; an agent does not write it (`AGENTS.md`).
5. Start the `e2e` workflow on the release branch, and wait for it to pass.
   The merge is what reaches an installation with auto-update on: the version
   moves on the default branch, which is what its marketplace follows (#855).
   So this comes before the merge, and a failed run has reached no one.
   The workflow runs two jobs: `e2e`, the door's journey on a backend and then
   on a web repository, and `upgrade`, which updates
   a repository rendered at the template tag an earlier release pinned and
   checks that the tested plinth pin lands in it (#519). Both must pass:

   ```bash
   gh workflow run e2e.yml --ref release/vX.Y.Z
   ```

   If `gh` answers HTTP 403, your login cannot run workflows: run the same
   command through `scripts/with-admin-token.sh` in a separate terminal
   window, not with Claude Code's `!`, which gives the token prompt no
   terminal:

   ```bash
   scripts/with-admin-token.sh gh workflow run e2e.yml --ref release/vX.Y.Z
   ```

   On this branch `e2e` also moves the test repository's calls to
   `coolbress/plinth` from the template's pin to the run's own commit, and
   fails unless the called `ci / floor-check` job's `job.workflow_sha` is that
   commit and `label.yml`'s run called `pr-label.yml` there and succeeded
   (#862). So it covers a call from another repository at the commit
   about to ship, which a run on any other ref does not; a scheduled or `main`
   run keeps the template's pin, what users get today. It does not cover
   `pr-review.yml`, which is off in the repository it makes.

   Beside that dispatch, the owner runs the
   [smoke run](run-the-eval-suite.md#the-release-smoke-run) from a clone on this
   branch. It needs the owner's Claude login, so an agent or CI does not run
   it; it costs about US$0.90 of usage, and every run must pass. It checks
   two skills, `/plinth:floor-check` and `/plinth:guide`, as an agent follows them:

   ```bash
   git switch release/vX.Y.Z
   scripts/eval-suite.sh --smoke
   ```

   When the why says `eval suite: on the release candidate`, run
   `scripts/eval-suite.sh --release` there instead: one run that prints the
   smoke verdict from its first six rows, then runs the rest of the suite
   ([the release run](run-the-eval-suite.md#the-release-run)). Its smoke
   verdict is the gate, as the smoke run's would be. Put its link in the pull
   request's description on one line, `eval suite: <link>`, in angle brackets.

   Post its table on #647. Name the `e2e` run and that comment in the pull
   request's description. If the smoke run fails, read the failed runs'
   `reader.md`. When a session timed out or crashed, run it again and say so in
   the description. When a skill broke, that is a fix, handled as below.

   If `e2e` fails, read its log.
   When the fault was GitHub's or the run's, dispatch it again. When it needs
   a fix, or when `main` moves before the merge, close the pull request, delete
   `release/vX.Y.Z` on origin and locally, land the fix if there is one, and
   start again from step 3 with the same number: nothing has used it yet, and
   run 1 writes any new fragments. Updating the branch instead would
   change its files, leave those fragments in `changelog.d/` and ask for another
   run anyway.
6. Merge the pull request with `scripts/merge-when-green.sh <n>` once that run
   and the checks are green. The script stops, and prints the command from
   step 5, while the head has no green `e2e` run on a `release/v*` branch (#855,
   #862): a run on any other ref did not call the workflows at this commit.
   The merge button and `gh pr merge` refuse too: `ci / release-gate`, a check
   the ruleset requires, fails on a release pull request whose head has no
   such run (#863). It ran when the branch was pushed, before the `e2e` run
   existed, so it is red until something runs it again: the script re-runs it
   once the `e2e` run is green and waits for it, or use "Re-run" on it in the
   pull request's Checks tab. The script does not read the smoke run: check
   that the description names it before you merge.
7. Update `main`: `git switch main && git pull --ff-only`.
8. Run the same command again:

   ```bash
   scripts/make-release.sh vX.Y.Z "${TMPDIR:-/tmp}/why.md"
   ```

   It pushes the annotated tag and creates the GitHub Release from the
   version's `CHANGELOG.md` section. The tag goes on the commit that set the
   version: a pull request merged after it stays unreleased. It does not read
   the why-file this time, so any clone at the merged `main` can run it.
   First it looks for the green `e2e` run: on the commit it tags, or on a
   commit with that commit's tree. A squash merge of an up-to-date branch
   leaves the same tree, so the release branch's run counts.
9. Tell installers to run `claude plugin marketplace update plinth`, then
   `claude plugin update plinth@plinth`, then `/reload-plugins`, plus any one-time command the version's `CHANGELOG.md` section names (those
   so far are in [Install, in detail](../../README.md#install-in-detail)). A
   release that raises a dependency's pin names
   `claude plugin update <name>@plinth` for that entry: neither
   `update plinth` nor `install plinth@plinth` fetches the new commit
   (measured for #714).

## If the script refuses

| It says | Do this |
| --- | --- |
| The release before is less than 7 days old | Wait, or add `hotfix: <reason>` for a hotfix, or `train exception: <link>` for an early release the owner decided in a comment ([Before you start](#before-you-start)) |
| Cannot read the comment the `train exception:` line names | Check the link and that `gh` is logged in, then run step 3 again |
| The why-file has both a `hotfix:` and a `train exception:` line | Keep the one that is true |
| The why must say what this release was tested with | Add the exact line it prints; if you tested another template tag, raise the pin first ([How to upgrade the template pin](upgrade-the-template-pin.md)) |
| The why says nothing but the tested line | Add a sentence on why the release exists |
| The why has a heading line | Remove every line that starts with `#` |
| The template pin moved and changes what a new project's agent reads | Run the eval suite and add `eval suite: <link>`, or add `eval suite not run: <the reason>` (step 2) |
| The `eval suite:` line must be the link to the comment | Give the comment's link alone, in angle brackets |
| The section says `eval suite: on the release candidate`, and the release pull request's description must carry the link (run 2) | Edit the merged pull request's description: add `eval suite: <link>` on one line, then run step 8 again |
| More than one `eval suite` line | Keep one |
| Cannot read what the template changed | Check that `gh` is logged in and can reach GitHub, then run step 3 again |
| A changelog fragment does not read, or a line is under `[Unreleased]` | Fix the fragment it names, or move the line into a fragment (CONTRIBUTING.md, Land a change), in a pull request; then run step 3 again |
| `changelog.d/` has untracked files | Commit them through a pull request, or remove them |
| The previous section has no `tested with` line | Restore that line in the previous version's section of `CHANGELOG.md` in a pull request |
| The version is not above the current one | Pick the next version |
| The tag or the release already exists | Pick the next version |
| `release/vX.Y.Z` already exists on origin | Finish that release, or delete the leftover branch |
| Run this from `main` | `git switch main` |
| Shallow clone | `git fetch --unshallow` |
| A local tag points elsewhere (run 2) | `git tag -d vX.Y.Z`, then run step 8 again |
| `main` has uncommitted changes or differs from `origin/main` | Commit or discard them, then `git pull --ff-only` |
| No green `e2e` run on the commit or its tree (run 2) | Wait for the run you started; if it failed, read its log and dispatch it again. The version has already moved on `main`, so do this first. If `main` is still at the release commit, dispatch with `--ref main`; if it moved past, from a branch at that commit |
| Cannot list the `e2e` runs (run 2) | Check that `gh` is logged in and can reach GitHub, then run step 8 again |
| The section's why fails a check (run 2) | Fix the version's section of `CHANGELOG.md` in a pull request, merge it, and run step 8 again |
