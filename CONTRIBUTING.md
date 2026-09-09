# Contributing

plinth is a Claude Code plugin, its marketplace, and the reusable CI workflow
that repositories built with it call. Changes land through pull requests only;
`main` is protected by a ruleset that requires the checks below.

## Run the checks

```bash
claude plugin validate --strict .                           # marketplace manifest
claude plugin validate --strict .claude-plugin/plugin.json  # plugin manifest
claude plugin validate --strict skills                      # skill frontmatter
./scripts/check-ruleset.sh                                  # the wall the door applies
for t in tests/*.sh; do "./$t"; done                        # every test; install-smoke needs network
```

`tests/install-smoke.sh` installs plinth into a temporary Claude Code config
directory exactly as the README says, so it needs network and a few minutes.
Everything else runs offline in seconds.

Tier 2 is the same journey on real GitHub, and no pull request runs it:

```bash
scripts/with-admin-token.sh scripts/e2e.sh   # creates plinth-e2e-<run> under you, merges its first pull request, deletes it
```

It runs the generator, reads the wall back with the floor checker, waits for
every check on the first pull request (pushing the generator's recovery
commit once if CodeQL has not picked it up, #117), squash-merges it and
deletes the repository; ten to twenty minutes, with the token the generator
asks for. A classic token (`repo`, `workflow`, `delete_repo`) is the one
measured to work; a fine-grained one without Administration: write is
refused before anything exists. Its
first act is to create and delete a sibling name, `<name>-probe`, so a
token that cannot delete stops before anything is left behind and the real
name never collides with a deletion GitHub is still finishing. The `e2e` workflow
runs it nightly and on demand from the secret `PLINTH_E2E_TOKEN` (a
fine-grained token: Administration, Contents, Pull requests, Workflows: write
on all of the owner's repositories; registered by a person, once). A run that
could not delete its repository names it in the job summary and is red. A
release needs a green run on the commit it tags (below).

## Land a change

1. Branch from `main`: `git switch -c <type>/<slug>`.
2. Commit with a Conventional Commits title, `type(scope): summary`, using one
   of the eleven standard types. A commit made with AI carries the trailer
   `Assisted-by: <agent>:<model>` (see `AGENTS.md`).
3. Open a pull request as a draft; mark it ready when it is. The description
   becomes the body of the squash commit, so write it as one, in this shape:

   ```text
   ## What and why

   The problem, what actually changed, the result, and why this approach.

   ## How it was verified

   What was run and what it showed; important unverified items and follow-ups.

   Closes #N

   Assisted-by: <agent>:<model>
   ```

   The issue link goes after the verification section, directly above the
   attribution. `Closes #N` only when the pull request completes that issue;
   partial work links with `Part of #N`, related work with `Related to #N`.
   `Closes` drives GitHub's auto-close, so the wrong verb closes an unfinished
   issue. With no issue to link, omit the line. Existing attribution is
   preserved: several trailers form one contiguous block at the end. From
   another repository, include this one: `Closes coolbress/plinth#N`.

   Check the template that actually applies before you write. This repository
   has no local `PULL_REQUEST_TEMPLATE.md` and **inherits** `coolbress/.github`'s;
   `gh pr create --body`/`--body-file` bypasses it entirely, so read it
   yourself. Remove its guidance comments — GitHub keeps HTML comments in the
   squash message.

   CI runs `ci / install`, `ci / tools`, `ci / docs` and `CodeQL`; the canary
   job runs the reusable workflow against `canary/`. `third-party / review`
   waits for a review by the Codex reviewer once the pull request is ready; it
   is optional and does not block the merge.
4. Before merging, read the description against the final diff: what changed
   and why, what was verified and what was not, as of the last commit. A
   review fix that changed the scope changes the description too, because
   the description is what lands on `main`.

   Say what was actually run, and name what was not. A review you ran in the
   same session that wrote the change is not an independent review, and must
   not be described as one. When you change behaviour, verify the boundaries
   and partial failures of the inputs and states it touches; record which paths
   you exercised and which you did not, and do not widen the result of a few
   cases into a guarantee about all of them.

   Put user-facing explanation and history where it belongs — `README.md`,
   `CHANGELOG.md`, or the page under `docs/` that covers it. Not every change
   needs a README edit.
5. Merge when green. Squash is the only merge method, the commit is the pull
   request title and description, and the branch is deleted on merge.

## Cut a release

Write the notes first: why this release exists, in a file, plus one line
`tested with <template> <tag>` naming the template tag `scripts/new-project.sh`
pins (the script prints the exact line). Then, from an up-to-date `main`, run
the same command twice:

```bash
scripts/make-release.sh v0.5.0 notes.md   # 1: bumps both manifests and CHANGELOG.md on release/v0.5.0
# push the branch, open the pull request, merge it, pull main
gh workflow run e2e.yml --ref main        # tier 2 on the release commit; the nightly run counts too
scripts/make-release.sh v0.5.0 notes.md   # 2: tags the merged release commit, creates the GitHub Release
```

The script refuses an empty notes file, a notes file without the tested line,
a version that is not above the current one, a tag or release that already
exists, a leftover `release/vX.Y.Z` branch, and any `main` that has
uncommitted changes to tracked files or differs from `origin/main` (the
untracked notes file in the checkout is fine). Run 2 also refuses a release
commit without a green `e2e` run on that exact commit: the latest green run
on another commit does not count, and neither does a failed, cancelled,
skipped or still-running one, or a query that failed. If `main` has moved past
the release commit, dispatch the workflow from a branch at that commit. The
tag goes on the commit that set the version, so a pull request merged after
the release one stays unreleased. Installers get the release with `claude plugin update plinth`;
third-party marketplaces do not auto-update by default.

## What a change must keep true

- Check names are the contract with every consumer. `ci / <job>` in
  `python-ci.yml` and the contexts in `ruleset.json` must stay identical;
  `tests/python-ci-contract.sh` holds the snapshot.
- Every third-party marketplace entry is pinned to a full commit SHA.
- Every `tests/*.sh` is a `run:` step in a workflow; `tests/all-tests-are-wired.sh`
  fails otherwise.
- `.github/workflows/e2e.yml` keeps its file name: `scripts/make-release.sh`
  asks GitHub for that workflow's runs by it, and refuses to release when the
  query fails.
- Shell and workflow files pass `bash -n`, `shellcheck -S warning`, actionlint
  and zizmor (`ci / tools`). Anything they catch is not for a reviewer to report;
  see `## Code Review Rules` in `AGENTS.md`.
- `## Code Review Rules` in `AGENTS.md` changes only in a pull request that
  changes nothing else; `third-party / review` fails the combination. Creating
  the section is exempt: there was nothing to weaken.
