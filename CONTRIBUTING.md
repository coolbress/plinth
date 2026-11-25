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
# one checkout of plinth-template at the pinned commit, for the tests that read it
export PLINTH_TEMPLATE_DIR="$(mktemp -d)/plinth-template" && tests/lib/template-checkout.sh "$PLINTH_TEMPLATE_DIR"
# the tests this change touched or reaches (below), each on its own; in place of <test> name each one
./tests/<test>.sh
```

Before a pull request, the local run is the tests the change touched and the
tests it reaches; CI runs every `tests/*.sh` on each pull request, on runners
that share nothing with this machine. Every test is a `run:` step of
`plinth-ci.yml`, which `ci.yml` calls on each pull request.
`tests/all-tests-are-wired.sh` fails when a `tests/*.sh` is a `run:` step in
no workflow; it does not check that the workflow runs on a pull request, so a
step moved to a workflow that does not is for the reviewer to catch.

A change reaches the `tests/*.sh` that name a file it changed, or a script
that calls it:

```bash
git diff --name-only origin/main...HEAD                  # what changed
grep -l -F -e '<changed file>' -e '<script that calls it>' tests/*.sh
```

A test can reach a file only through a shared library under `tests/lib/` or
`scripts/lib/`, which the test never names. For a changed library, grep for
the library's own name too: in `tests/*.sh` for the tests that source it, and
in `scripts/` for the scripts that do, then for those scripts' names in
`tests/*.sh`. A change to a Markdown file reaches the tests that read every
one: `markdownlint`, `de-jargon` and `doc-pinned-facts`.

The whole set, for whoever wants it locally, queues each test on its own in
`scripts/heavy.sh`, plinth-template's queue (#989), so the slot goes back
between tests and another project's heavy command can take it.
install-smoke, markdownlint, workflow-lint, python-lint, gitlab-ci-cases,
build-cases, release-allowlist, template-render, arsenal-freshness, uv-pin and
release-download-token need network:

```bash
bash -c 'failed=; notrun=; for t in tests/*.sh; do scripts/heavy.sh "./$t"; s=$?
case $s in 0) ;; 75) notrun="$notrun $t" ;; *) failed="$failed $t" ;; esac; done
[ -z "$notrun" ] || echo "DID NOT RUN (no free slot):$notrun"
[ -z "$failed" ] || echo "FAILED:$failed"
[ -z "$failed$notrun" ]'
```

The last lines are there because a loop ends with the status of its last
test: without them a failure in the middle scrolls past and the block still
ends in 0. The block ends non-zero when any test failed or did not run, and
names each under its own heading.

The queue's slots are shared with every project made with plinth on the
machine, sandboxed Claude Code sessions included (it needs `perl`; without it
the test does not run and exits 75). A test waits while
all are taken, in the order it arrived, and `scripts/heavy.sh` prints once a
minute how many wait ahead and what runs for how long. `PLINTH_HEAVY_SLOTS`
sets how many run at once (2 unless set; 1 on a small machine) and
`PLINTH_HEAVY_WAIT` the minutes each test waits (20 unless set). Past that, or
as soon as the commands it saw end say it would, the test does not run and
`scripts/heavy.sh` exits 75 with a "did not run" line, which the block lists
under "DID NOT RUN", not as failed or passed: report those tests as not
verified. A test that itself exits 75 lands there too; run it on its own to
tell. A single test run while working needs no queue. CI does not queue:
each runner is a machine of its own.

`tests/install-smoke.sh` installs plinth into a temporary Claude Code config
directory exactly as the README says, so it needs network and a few minutes.
`tests/markdownlint.sh` needs Node.js, and network the first time: `npx`
downloads the one version pinned in that file, the same file `ci / docs` runs,
and lints from its cache afterwards. `tests/shell-lint.sh` needs shellcheck and
`tests/workflow-lint.sh` needs actionlint, and it and `tests/python-lint.sh`
need `python3` 3.10 or later that can make a venv (on Debian and Ubuntu, the
`python3-venv` package): zizmor, ruff and mypy install into a venv from
`tests/lint-tools.txt`, every file checked against its hash, with network the
first time; a missing tool is a FAIL that names the install command, never a
skip. `tests/weakened-checks-cases.sh` needs `python3` 3.11 or later, the
version whose standard library parses TOML, as the runner's does.
`tests/install-smoke-interrupt.sh` needs `perl`, `pkill` and `pgrep` and takes
about 20 seconds. `tests/gitlab-ci-cases.sh` installs the GitLab
`floor-check` job's PyYAML from PyPI, pinned by hash, so it needs network.
The tests that compare plinth with the template (`template-rules-drift`,
`archetype-single-source`, `off-by-default-cases`, `uv-pin`,
`release-allowlist`, `arsenal-freshness`, `template-update-cases`,
`template-render` and `install-smoke`) read the checkout `PLINTH_TEMPLATE_DIR`
names, which must be at the pinned commit with nothing changed; without it,
each fetches its own. `ci / install` makes the checkout once, in a step of
its own, so a network error there is the fetch failing, not a test.
`tests/template-update-cases.sh` takes minutes rather than seconds.
Everything else runs offline in seconds.

The whole set, with the commands above it, is every step of `ci / install`, `ci / docs` and `ci / tools` but
one, the link check. CodeQL and the `canary`, `canary-web` and
`canary-template` jobs run only on GitHub.

The lint files are what `ci / tools` calls, with the same flags, but a
local pass is the CI pass only where the tool is the same one:

- zizmor, ruff and mypy are: both sides install the same hash-checked files
  from `tests/lint-tools.txt`. ruff and mypy run with their defaults and no
  configuration file, and mypy checks against the same Python version
  whatever runs it. To raise one of these pins, edit `tests/lint-tools.in` and
  regenerate `tests/lint-tools.txt` with the command written at its top.
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
pass there. Both skip the hosts in `.lycheeignore`, each of which refuses
every automated request. `ci / docs` also checks the links that failed once
more after a minute, so a host that fails only some requests does not fail it,
while a page that is gone fails both times. A link to one of this repository's
own commits is looked up in the checkout's history instead of on github.com. To look before pushing anyway, with a lychee of your own:

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
by `tests/new-project-failpath.sh` and `tests/e2e-driver.sh`).
`PLINTH_E2E_ARCHETYPE=web` runs the same journey on the web archetype, as
`plinth-e2e-web-<run>`, whose ruleset also requires `ci / migrations` and
`ci / deploy-check` (#615); the workflow runs the backend journey, then the
web one. The job summary and the log's `archetype:` line say which. A classic token (`repo`, `workflow`, `delete_repo`) is the one
measured to work; a fine-grained one without Administration: write is
refused before anything exists. Its
first act is to create and delete a sibling name, `<name>-probe`, so a
token that cannot delete stops before anything is left behind and the real
name never collides with a deletion GitHub is still finishing. The `e2e` workflow
runs it nightly and on demand from the secret `PLINTH_E2E_TOKEN` (a
fine-grained token: Actions, Administration, Contents, Pull requests,
Workflows: write on all of the owner's repositories; registered by a person,
once). A run that
could not delete its repository names it in the job summary and is red. A
release needs a green run on the commit it tags, or on a commit with its tree
([How to cut a release](docs/how-to/cut-a-release.md)).

## Land a change

1. Branch from `origin/main`, always naming the base. Unless the checkout is
   yours alone, make the branch in its own worktree, with the command in
   `AGENTS.md`. In a checkout that is yours alone, `git switch -c <type>/<slug> --no-track
   origin/main` does the same in place. Without the base either command starts
   the branch at whatever `HEAD` is, which carries another task's commits into
   yours. `--no-track` leaves the branch with no upstream: tracking
   `origin/main`, a bare `git push` refuses and the fix git prints first is
   `git push origin HEAD:main` — a push to `main`, not to your branch.
2. Commit with a Conventional Commits title, `type(scope): summary`, using one
   of the eleven standard types. The pull request title follows the same rule
   and does not end in `(#N)`: the squash merge adds the pull request's own
   number, and `ci / pr-title` refuses a title that would carry two. The title
   GitHub gives a revert, `Revert "<title>"`, passes when `<title>` passes on
   its own: `Revert "feat(x): y"` does, `Revert "fix stuff"` does not. A commit
   made with AI carries the trailer `Assisted-by: <agent>:<model>` (see
   `AGENTS.md`).
3. Open a pull request as a draft; mark it ready when it is. The description
   becomes the body of the squash commit, so write it as one, in this shape:

   ```text
   ## What and why

   The problem, what actually changed, the result, and why this approach.

   ## What I checked myself

   What you ran, opened or read yourself, and what you saw; or `Skipped: <reason>`.

   ## How it was verified

   What was run and what it showed; important unverified items and follow-ups.

   Review: fresh-context | third-party (<name>) | same-session (not independent) | none (<reason>)

   Closes #N

   Assisted-by: <agent>:<model>
   ```

   The issue link goes after the verification section, directly above the
   attribution. `Closes #N` only when the pull request completes that issue;
   partial work links with `Part of #N`, related work with `Related to #N`.
   `Closes` drives GitHub's auto-close, so the wrong verb closes an unfinished
   issue. So does a closing keyword (close, fix, resolve and their `-s` and
   `-d` forms) directly before `#N` in a sentence: "the two fixes #65
   decided" closed #65 on merge. `ci / docs` asks GitHub which issues the
   merge will close and fails on any the closing line does not name; reword
   the sentence ("the two fixes that #65 decided"). It reads the description
   when it runs: not the title, and not an issue linked in the sidebar
   afterwards. With no issue to link, omit the line. Existing attribution is
   preserved: several trailers form one contiguous block at the end. From
   another repository, include this one: `Closes coolbress/plinth#N`.

   Check the template that actually applies before you write. This repository's
   own is `.github/PULL_REQUEST_TEMPLATE.md`;
   `gh pr create --body`/`--body-file` bypasses it entirely, so read it
   yourself. Remove its guidance comments — GitHub keeps HTML comments in the
   squash message.

   CI runs `ci / install`, `ci / tools`, `ci / docs`, `ci / release-gate` and
   `CodeQL`; the canary jobs run the reusable workflow at this commit against
   `canary/` and `canary-web/`, and `canary-template` against
   `canary-template/`, plinth-template's `cli` render at the pinned commit,
   with the grant and inputs its rendered `ci.yml` gives the call (#953). No
   ruleset requires the canaries; `scripts/merge-when-green.sh` still waits
   for them, as for every check. `third-party / review`
   waits for a review by the Codex reviewer once the pull request is ready,
   and it is required on `main`: a pull request without an accepted review on
   its head does not merge, a draft, a pull request only Dependabot pushed to
   and a release pull request whose diff is a release's aside. When the review does not come, follow
   [When the reviewer does not come](docs/how-to/configure-the-third-party-reviewer.md#when-the-reviewer-does-not-come).

   Before pushing a fix for a review finding, run
   `scripts/merge-when-green.sh <n> --round`. It only reads, and prints the
   review round line `third-party / review` writes for the head; from round 3
   it says the budget is spent and that a wording fix is answered on its
   thread, not pushed, since each push starts another round
   ([When to stop](docs/how-to/configure-the-third-party-reviewer.md#when-to-stop)).
   From round 3, or when the round cannot be read, it exits 1 until you add
   `--row <irreversible|issue|answer|unclassified> "<why>"`: the finding's row
   of that table, judged by what the diff does, and the reason. It prints a
   line for the description's review section. It runs only when you run it;
   `git push` does not.
4. Before merging, read the title and the description against the final
   diff: what changed and why, what was verified and what was not, as of the
   last commit. A review fix that changed the scope or the approach changes
   both, because the title becomes the squash commit's subject and the
   description its body; #370 merged under a title its last fix had made
   wrong.

   Say what was actually run, and name what was not. A review you ran in the
   same session that wrote the change is not an independent review, and must
   not be described as one. A change to behaviour is verified as `AGENTS.md`
   says.

   Put user-facing explanation and history where it belongs — `README.md`,
   `CHANGELOG.md`, or the page under `docs/` that covers it. Not every change
   needs a README edit.

   A change's changelog line goes in its own file, a fragment:
   `changelog.d/<branch-slug>.md`, starting with the Keep a Changelog section
   it belongs to, then the line:

   ```markdown
   ### Fixed

   - What changed for the person, and the issue (#N).
   ```

   A fragment can hold several sections (Added, Changed, Deprecated, Removed,
   Fixed, Security), each a `###` heading with its lines under it, and
   nothing else. A link in it is absolute
   (`https://github.com/coolbress/plinth/blob/main/<path>`): the line moves
   from `changelog.d/` to the root at release, and a relative one breaks in
   one place or the other. Two pull requests open from the same `main` each add their
   own file, so neither conflicts with the other in `CHANGELOG.md` (#1136).
   `scripts/make-release.sh` writes the fragments into the new version's
   section and deletes them; `## [Unreleased]` in `CHANGELOG.md` stays empty,
   and `ci / docs` fails a pull request that writes a line there or adds a
   fragment the release would refuse
   (`scripts/changelog-fragments.py check` says why).

   A section whose
   version has a `vX.Y.Z` tag is released: its text is that version's
   Release. A pull request open across a release can merge `main` in and
   keep its line where it sat, now inside the section the release just
   tagged (#877). `ci / docs` fails when a pull request changes a released
   section, naming it; move the line into a fragment. A change that puts
   a section back as its tag has it passes. To correct a released section on
   purpose (a typo, a wrong link), add one line to the description naming
   each version it corrects, and only those pass. The line counts as plain
   text at the start of a line, not inside an HTML comment, a code block or a
   quote:

   ```text
   Corrects released section: 2.28.0
   ```

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

   `scripts/merge-when-green.sh <n>` prints the review round line first, then
   runs that command once nothing is left to read, and stops otherwise: every check on the head green, and a reply
   under every top-level inline comment, on any commit. On this repository a
   pull request titled `chore(release): vX.Y.Z` also needs a green `e2e` run on
   its head (#855). A green
   `third-party / review` is the reviewer's verdict, since the check already
   binds it to the head and its push; on a repository with no such check it
   stops unless you pass `--no-reviewer`, since merging without a reviewer is
   your call. It takes the head when it starts and passes it as
   `--match-head-commit`. A check name with several runs on the head (a review
   check that failed and then passed on the reviewer's late review) counts
   by the run started last; one still running holds the merge. Merging on a count that was printed but not checked
   let two unread findings through once (#306); this is the check.

   One check state is not green and still passes: a neutral `CodeQL` on a
   pull request whose author is `dependabot[bot]` and whose head has no
   `Analyze (...)` run (#872). Code scanning's default setup starts no
   analysis for an event Dependabot causes, so every Dependabot pull request
   carries one, and the push to `main` runs the analysis. After such a merge
   the script waits for the `Analyze (...)` jobs on the merge commit and says
   whether they passed, failed (exit 1: the failure is on `main` now, and it
   says what to do next), or did not start or finish in time. A neutral
   `CodeQL` on any other pull request, a person's included, stops: it means
   code scanning could not tell which alerts the change adds, often because no
   analysis ran for that head.

   When several pull requests are open, only the session the person names (or
   the person) merges, one at a time, with `scripts/merge-when-green.sh`, and
   does not edit a description while it waits. One left behind `main` goes up
   to date with `--update`, which stops rather than update twice. Other
   sessions do not bring their own pull request up to date
   (coolbress/plinth-template#293 has why).

   After the merge it prints, for each issue the pull request closes or names
   on a `Part of #N` line, the acceptance criteria still unticked and, for an issue
   it closed, a body with no `## Outcome` (`## Decision` for a record). Tick
   the criteria the change met and write the ending, whether or not the issue
   closed ([closing an issue](docs/agents/issue-tracker.md#closing-an-issue)). It only reads; an issue it cannot read is printed as
   "not read", and the exit status does not change.

## Cut a release

[How to cut a release](docs/how-to/cut-a-release.md). A release that moves
the template tag starts with
[How to upgrade the template pin](docs/how-to/upgrade-the-template-pin.md).

## What a change must keep true

- Check names are the contract with every consumer. `ci / <job>` in
  `python-ci.yml` and the contexts in `ruleset.json` must stay identical;
  `tests/python-ci-contract.sh` holds the snapshot, and
  `tests/required-checks-doc.sh` holds
  [docs/reference/required-checks.md](docs/reference/required-checks.md) to the same list.
- Every third-party marketplace entry stays pinned as `AGENTS.md` says.
- Every `tests/*.sh` is a `run:` step in a workflow; `tests/all-tests-are-wired.sh`
  fails otherwise.
- `.github/workflows/e2e.yml` keeps its file name: `scripts/make-release.sh`
  asks GitHub for that workflow's runs by it, and refuses to release when the
  query fails.
- Shell and workflow files pass `bash -n`, `shellcheck -S warning`, actionlint
  and zizmor, and plinth's own Python passes ruff and mypy (`ci / tools`). Anything they catch is not for a reviewer to report;
  see `## Code Review Rules` in `AGENTS.md`.
- `## Code Review Rules` in `AGENTS.md` changes only in a pull request that
  changes nothing else; `third-party / review` fails the combination. Creating
  the section is exempt: there was nothing to weaken.
