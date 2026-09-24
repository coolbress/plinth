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
# every test; install-smoke, markdownlint and workflow-lint need network
failed=; for t in tests/*.sh; do "./$t" || failed="$failed $t"; done
[ -z "$failed" ] || { echo "FAILED:$failed"; false; }
```

The last line is there because a loop ends with the status of its last test:
without it a failure in the middle scrolls past and the block still ends in 0.

`tests/install-smoke.sh` installs plinth into a temporary Claude Code config
directory exactly as the README says, so it needs network and a few minutes.
`tests/markdownlint.sh` needs Node.js, and network the first time: `npx`
downloads the one version pinned in that file, the same file `ci / docs` runs,
and lints from its cache afterwards. `tests/shell-lint.sh` needs shellcheck and
`tests/workflow-lint.sh` needs actionlint and `uvx` (or `pipx`), with network
the first time for zizmor; a missing tool is a FAIL that names the install
command, never a skip. Everything else runs offline in seconds.

That list is every step of `ci / install`, `ci / docs` and `ci / tools` but
one, the link check. CodeQL and the `canary` jobs run only on GitHub.

The two lint files are what `ci / tools` calls, with the same flags, but a
local pass is the CI pass only where the tool is the same one:

- zizmor is: both sides run the exact version pinned in `tests/workflow-lint.sh`.
- actionlint is pinned there too, and CI installs that checksum-verified Linux
  build. A laptop runs the actionlint it has. Another version still runs, and
  the output names it and says the pass is not the pinned pass; in CI another
  version is a FAIL.
- shellcheck and bash are not pinned, in CI or here. The file prints the
  versions it ran. macOS ships bash 3.2 and the runner has 5.x, so `bash -n`
  can fail locally on syntax CI accepts: a stricter pass, not the same one.

The link check is left out on purpose.
`ci / docs` runs a checksum-pinned Linux build of lychee
(`.github/workflows/plinth-ci.yml`); a package manager installs whatever
version it has, the check needs network, and the sites it asks can answer
differently from one hour to the next, so a local pass does not promise a
pass there. To look before pushing anyway, with a lychee of your own:

```bash
lychee --no-progress --exclude-path .scratch -- './**/*.md'   # network; not the pinned build
```

Tier 2 is the same journey on real GitHub, and no pull request runs it:

```bash
scripts/with-admin-token.sh scripts/e2e.sh   # creates plinth-e2e-<run> under you, merges its first pull request, deletes it
```

It runs the generator with `--archetype=backend`, reads the wall back with
the floor checker, waits for every check on the first pull request (pushing
the generator's recovery commit once if CodeQL has not picked it up, #117),
squash-merges it and deletes the repository; ten to twenty minutes, with the
token the generator asks for. A backend, not the generator's cli default,
because it is the archetype with the most machinery: only a service archetype
shapes the ruleset with the `image` check and renders the template's `image`
job, so only it puts them in the gate (#164; the cli path is covered offline
by `tests/new-project-failpath.sh` and `tests/e2e-driver.sh`). One journey a
night, no matrix; the job summary and the log's `archetype:` line say which. A classic token (`repo`, `workflow`, `delete_repo`) is the one
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

1. Branch from `origin/main`, always naming the base. Unless the checkout is
   yours alone — no command tells you whether another session is in it — make
   the branch in its own worktree: `git fetch origin`, then
   `git worktree add --no-track -b <type>/<slug> .claude/worktrees/<slug> origin/main`.
   In a checkout that is yours alone, `git switch -c <type>/<slug> --no-track
   origin/main` does the same in place. Without the base either command starts
   the branch at whatever `HEAD` is, which carries another task's commits into
   yours. `--no-track` leaves the branch with no upstream: tracking
   `origin/main`, a bare `git push` refuses and the fix git prints first is
   `git push origin HEAD:main` — a push to `main`, not to your branch.
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
   request title and description, and the branch is deleted on merge. The
   description is the commit only when the merge passes it: without a body,
   GitHub's default squash message is the description hard-wrapped at 72
   columns, and `gh pr merge --squash` takes that default.

   ```bash
   body="$(gh pr view <n> --json body --jq .body)" &&
     gh pr merge <n> --squash --match-head-commit <sha> --body "$body"
   ```

   The `&&` stops the merge when the read fails, rather than merging with an
   empty body, and no file is left in the checkout to be committed later.
   `--match-head-commit` names the head step 4 read the description against:
   a commit pushed after it stops the merge. It pins the commits only; the
   description is read when the command runs, so finish editing it before
   step 4, not after.

## Cut a release

Write the why first, in a file anywhere (a temporary directory will do): a
short paragraph on why this release exists, and one line
`tested with <template> <tag>` naming the template tag `scripts/new-project.sh`
pins (the script prints the exact line). No headings: run 1 puts the text
under the version's heading in `CHANGELOG.md`, above the entries, and nothing
reads the file after that. Then, from an up-to-date `main`, run the same
command twice:

```bash
scripts/make-release.sh v0.5.0 why.md   # 1: bumps both manifests, writes the why into CHANGELOG.md, on release/v0.5.0
# push the branch, open the pull request, merge it, pull main
gh workflow run e2e.yml --ref main      # tier 2 on the release commit; the nightly run counts too
scripts/make-release.sh v0.5.0 why.md   # 2: tags the merged release commit, creates the GitHub Release
```

The version's section of `CHANGELOG.md` is the release note. The release pull
request shows it in its diff, and run 2 publishes that section of the merged
`main`, heading left out, as the Release's text, with GitHub's generated index
of pull requests under it. Run 2 reads no file, so any clone or worktree can
run it; given the second argument, it says it does not read it. Run 1 also
adds the version's link reference at the end of `CHANGELOG.md` and moves the
`[Unreleased]` compare link to the new tag. Neither link resolves before run 2,
so `ci / docs` skips the two links of the version `plugin.json` names, from
the release pull request until the next release moves the version on.

The script refuses a why without the exact tested line, a why that is nothing
but that line and markup, a why-file with a heading line, and in run 2 a
section whose why (above its first `###`) fails the same checks, as after an
edit to the pull request. It also refuses a version that is not above the
current one, a tag or release that already exists, a leftover
`release/vX.Y.Z` branch, and any `main` that has uncommitted changes to
tracked files or differs from `origin/main` (an untracked why-file in the
checkout is fine). Run 2 also refuses a release
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
