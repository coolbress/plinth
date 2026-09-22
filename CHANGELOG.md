# Changelog

All notable changes to plinth. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). A version is a
`vX.Y.Z` tag on `main` plus a GitHub Release; `scripts/make-release.sh` cuts
one, and the version number moves only there. After 0.5.16 a version's section
opens with why it exists and which template tag it was tested with, and the
section is its Release's text. For 0.5.16 and earlier that why is in the
Release each heading links to. Numbers before the first tag were bumped inside
pull requests and have no tag.

## [Unreleased]

### Fixed

- `/plinth:floor-check` checks the wall again when the agent's shell is zsh.
  The skill's command passed the repository as `${repo:+--repo "$repo"}`,
  which zsh does not split into words, so the checker got the single argument
  `--repo <owner>/<name>` and the wall went unchecked. The flag and its value
  are now two expansions, the same in bash and zsh, and still add nothing
  when there is no repository. `tests/floor-check-run-block.sh` runs the
  skill's own command under both shells.

## [0.5.20] - 2026-09-23

This release is about `floor-check` saying two things it could not say before.
It now reports when a repository has fallen behind the template tag plinth is
tested with, naming both tags, the template's own files that changed between
them, and a `copier update` line carrying the plinth commit that repository's
own CI calls today — always a warning, never a failure, and it never runs the
update itself. And run at the root of a repository whose Python project is one
directory down, it no longer reports two files missing that are there: it names
the directory and the `--project` flag to run again with, for whichever of
`pyproject.toml` and `uv.lock` it finds below. It still never chooses a project
for you. Underneath both, `new-project` renders plinth-template v1.5.0, where
the plinth commit a repository pins is a recorded answer rather than one
computed on every render, so `copier update` can keep the pin a repository
already has instead of re-rendering it from the template's default — which used
to hand a conflict to every repository whose Dependabot had raised it, and to
move the pin back without a word on every repository whose Dependabot had not.

tested with plinth-template v1.5.0

### Added

- `floor-check` reports when a repository is behind the template tag plinth
  is tested with today: the tag it was made from, the tag it would move to,
  the template's own files that changed between the two, and a `copier
  update` line carrying the plinth commit its own CI calls right now, read
  from its workflow `uses:` lines, so the update does not move that pin under
  it. Always a WARN, never a FAIL — `ci / floor-check` does not turn red for
  falling behind. A repository the door did not make, or whose recorded tag
  is not an exact release tag, is not verified rather than passed. It reports
  only; running the update, resolving conflicts and opening a pull request is
  a later skill (#219; stage 2 is #232).

### Changed

- `floor-check` names `--project` when a repository's project is one
  directory down. Run at the root of such a repository — a monorepo, a
  `backend/` folder — it reported `pyproject.toml missing` and `uv.lock
  missing` for files that exist, and nothing said that `--project <dir>` is
  the answer. Now, when a run is checking the root itself and exactly one
  directory directly below it holds a `pyproject.toml`, both lines name that
  directory and the flag to run again with. Both items then speak about that
  directory: the `uv.lock` line names it and the flag when it holds a
  lockfile, and names `<dir>/uv.lock` as the missing one when it does not —
  a `uv.lock` lying at a root that holds no `pyproject.toml` is nobody's
  lockfile and no longer passes the item. A run that was given a
  `--project` is left alone: the caller chose that project, so its missing
  files read as files to add there rather than as a reason to go and check a
  different one. A candidate is skipped when its name opens with a dot, when it is one
  of the directories this checker already never walks into (`node_modules`,
  `dist`, `.venv`, `.git`, `.plinth-ci`, `.smoke`, `.scratch`), or when it is
  a symlink — anything else one level down is offered, `build/` and `vendor/`
  included. With no candidate the lines read as before; with several they read
  as before plus a list of them. It never chooses a project or re-runs itself:
  which one is meant is the reader's to say. No other item changed, and the
  failure count moves in one situation: a root that holds a `uv.lock` but no
  `pyproject.toml`, with a project found below it. That item used to pass on
  the root's file; it now reports on the project's, which fails whether or not
  the project has a lockfile of its own. Measured over the four combinations
  of a root and a project lockfile: both with a root one go from `10 failed`
  to `11`, and both without one stay at `11` (#221).

- `new-project` renders plinth-template v1.5.0. A repository it creates now
  records `plinth_sha` — the commit of plinth whose reusable workflows its CI
  calls — in `.copier-answers.yml`, where it was computed on every render
  before. What that buys is an update that can be told to keep the pin the
  repository already has: while the answer was computed, `copier update`
  re-rendered the `uses:` pins from the template's own default, so a
  repository whose Dependabot had raised them got a conflict in each workflow
  file and one whose Dependabot had not was moved back without a word.
  Rendering is otherwise unchanged, the door passes the same answers, and the
  value a new repository gets is the same one (plinth-template#22).

## [0.5.19] - 2026-09-22

Two changes, and the first one reaches every repository plinth creates.

A new repository now says how to branch, and what to do about a checkout
another session may already be using. Its `AGENTS.md` — the file its agents
load every turn — opens with the rule to inspect the checkout before editing,
and, unless the checkout is yours alone, to leave it untouched and work in a
uniquely named worktree branched from an explicitly verified base. Every
branch instruction names that base. Until now the instruction and its command
disagreed: "Branch from `main`" was paired with `git switch -c <type>/<slug>`,
which branches from whatever `HEAD` is, and two agent sessions sharing one
checkout turned that into a branch cut from another task's scratch commit.
Naming the base keeps another task's commits out of the new branch; the rule
is what covers the uncommitted work git still carries along without a word.
Neither is a technical block: no hook, no deny rule, nothing that refuses a
command. `.gitignore` also ignores `.claude/worktrees/`, the path the rule
names, which `git add .` would otherwise stage as a gitlink.

The second matters only to a repository that passes `summons-token` to
`third-party / review`: a run whose head a newer push has replaced no longer
asks the reviewer for a review. It used to keep asking at its ask points while
the newer commit's run waited behind it in the concurrency group, and those
requests were served against the pull request's current head while being
counted as the old one's — up to four for a single commit on the token owner's
review allowance. Without the secret nothing is posted, as before, and no
input, job, check name or permission changed.

tested with plinth-template v1.4.3

### Changed

- `new-project` renders plinth-template v1.4.3 instead of v1.4.1, so a new
  repository says how to branch and what to do about a checkout another
  session may already be using. The `AGENTS.md` its agents load every turn
  opens with the rule to inspect the checkout before editing (`git fetch
  origin`, then `git status -sb`, `git worktree list`,
  `git log --oneline origin/main..HEAD`) and, unless the checkout is yours
  alone, to leave it untouched and work in a uniquely named worktree branched
  from an explicitly verified base. Every branch instruction names that base,
  and the worktree the rule names is the one `.gitignore` now ignores,
  `.claude/worktrees/`. `git switch -c <type>/<slug>` alone starts the branch
  at whatever `HEAD` is, so in a checkout another task left on a scratch
  commit it carries that commit into the new branch, which is the incident
  behind this change; naming the base does not stop uncommitted changes riding
  along, so the rule and the base are two guards and not one said twice.
  Neither is a technical block: no hook, no deny rule, nothing that refuses a
  command. plinth's own `AGENTS.md`, `CONTRIBUTING.md` and `.gitignore` carry
  the same three (#218). v1.4.3 adds one fix on top: the instance's
  tree-hygiene tests read git's "not a git repository" message in a fixed
  locale, so a fresh render skips them instead of failing three of them where
  git speaks another language (plinth-template#19).

### Fixed

- With the `summons-token` secret, a run of `third-party / review` whose head
  a newer push has replaced no longer posts the summons. The caller's
  concurrency group holds the newer commit's run until the old one ends, and
  the old one kept asking at its ask points. The reviewer reviews the pull
  request's current head, so those requests served the newer commit while
  being counted as the old head's, and could reach up to four for one commit
  on the token owner's review allowance. At each ask point the check now reads
  the activity log it already fetches for that look, and does not ask when the
  log confirms that another commit was pushed after this head; its log says
  `this head is no longer the branch's newest push (<commit>): not asking`.
  "Confirms" is narrow: the log is short of a full page of 100, this head's
  push is in it, every entry has a readable time, and every push at the
  latest second names a commit, none of them this head; the order the log
  lists them in is not read. Anything else, a push of this head in the same
  second as another commit's included, leaves the decision to the rules of
  #206, unchanged. A head pushed back after another commit is the newest push
  again and asks as usual. A push that lands just after the log is read is
  not seen. No input, job or check name changed, no API call was added, and
  the job's permission stays `pull-requests: read` (#215).

## [0.5.18] - 2026-09-19

One change, to when `third-party / review` asks the reviewer for a review.
It matters only to a caller that passes the `summons-token` secret; without
it nothing is posted, as before. The files that changed are the reusable
workflow `pr-review.yml`, plinth's own caller `third-party.yml`, the summons
test and the name of its CI step, the third-party reviewer how-to, and
`CHANGELOG.md`. No input, job, check name or secret was renamed, and nothing
a new repository receives from the door changes.

Why: on 2026-09-18 the reviewer's own trigger did not start three times on
this repository, while a request from the owner's account drew a review in
about two minutes. With a token the check used to ask at the start of the
wait and again halfway, whatever the reviewer was doing. It now asks a third
of the way in only if no accepted reviewer has been active since the push,
and at two thirds only if none has been active since the first ask point
(#206). plinth's own caller passes `secrets.SUMMONS_TOKEN`, which the owner
created on the day of this release. On a scratch pull request (#214) the check
logged `summons-token reads as coolbress` with the asks due at 300 s and
600 s; the review arrived before either, so no summons was posted there.
(Corrected after publication: this paragraph first said the secret did not
exist yet.)

tested with plinth-template v1.4.1

### Changed

- With the `summons-token` secret, `third-party / review` no longer posts the
  summons at the start of the wait. A third of the way into `wait-seconds` it
  asks if no accepted reviewer has started, and at two thirds once more if
  none has been active since the first of those points. As before it counts
  its earlier summonses for the commit by a hidden marker and stops at two; a
  count that cannot be read (the comments call failed) reads as none, so a
  run then can post more. "Started" means an account in `reviewer-logins` has an
  issue comment on the pull request created or updated after the newest push
  of the head; where that push cannot be read, the first ask goes out on
  schedule, and the second is measured from the first ask point.
  The log says at each point why it asked or did not. Why: on 2026-09-18 the
  reviewer's own trigger did not start three times while a request from the
  owner's account drew a review in about two minutes, and a request that
  lands on a review already running is folded into it (measured on #207,
  #205). Without the secret nothing changes and nothing is posted. The
  failure message names the how-to's summons section, which now says whose
  token this is, what it costs, and that a reviewer with a native request
  needs no summons. The token needs the repository permission "Pull
  requests: Read and write"; "Issues: Read and write" alone was refused on a
  pull request (measured on #207, #205). plinth's own caller passes
  `secrets.SUMMONS_TOKEN`, which the owner created on 2026-09-19. No input,
  job or check name changed, no API call was added, and the job's
  permission stays `pull-requests: read` (#206).

## [0.5.17] - 2026-09-19

One change, to how plinth is released. The files that changed are the
release script and its test, `CHANGELOG.md`, `CONTRIBUTING.md`, `AGENTS.md`,
and plinth's own CI and release configuration. No skill, reusable workflow,
input, job, check name or secret changed, and nothing a new repository
receives from the door changes.

Why: this release moves the release note into `CHANGELOG.md`. A release
used to be written twice, as the entries below and again in a separate notes
file that no reviewer saw before it went public and that only one checkout
held. From this version on, the version's section of `CHANGELOG.md` is the
Release's text, written once and shown in the release pull request's diff.
This is the first release cut that way: run 1 took this text as a file and
wrote it into the section, and run 2 publishes that section of the merged
`main` and reads nothing else (#209).

tested with plinth-template v1.4.1

### Changed

- A release's note is its section of this file, not a separate notes file.
  `scripts/make-release.sh` run 1 takes the why as a file
  (`vX.Y.Z <why-file>`), checks it as it checked the notes file and also
  refuses a heading line in it, and writes it under the new version's heading
  above the entries. It also adds the version's link reference and moves the
  `[Unreleased]` compare link to the new tag. Run 2 reads no file: it runs
  run 1's checks again on that section of the merged `main`, on the text
  above its first `###`, then publishes the section, heading left out, with
  the generated index under it. The text is in the release pull request's diff
  before it is public, and run 2 runs from any clone or worktree. Every
  version heading down to 0.5.0 links its Release, where the earlier
  why-texts are. `ci / docs` skips the two links of the version `plugin.json`
  names, from its release pull request (where they return 404) until the next
  release; every other version's links are checked. No check name, job or
  workflow input changed (#209).

## [0.5.16] - 2026-09-19

### Fixed

- `tests/e2e-driver.sh` numbers each case's mock log instead of naming it
  with `$RANDOM`. The mock `gh` keeps counters beside the log that a new case
  does not reset, so when the cancellation case drew an earlier case's name
  it counted its second deletion as the third or fourth, never sent the
  signal, and the driver finished with exit 0. That happens on about 0.09%
  of runs (8 of 9,403 bash 3.2 seeds); seeds 6126 and 1672 reproduce #201's
  two failing lines on the unchanged file and pass after (#201).
- `third-party / review` no longer counts Copilot's could-not-review notice
  as a review. Asked by a person who has reached their quota, Copilot still
  submits a review on the current commit whose body is `Copilot was unable
  to review this pull request because …` (measured on two public pull
  requests, 2026-09-19), and a caller accepting
  `copilot-pull-request-reviewer[bot]` passed on it. A review whose body
  begins with that text, in any letter case, no longer counts, and the log
  names it; a review that mentions the words further down still counts (#204).

## [0.5.15] - 2026-09-18

### Changed

- The how-to for `third-party / review` says that the check is not a barrier
  against people with write access: three of its signals are issue comments
  (the security review's marker, the completion comment, the summary row), and it does not look
  at whether such a comment was edited after it was posted, or by whom, so one
  that someone else edited can still count. Left as it is by the owner's
  decision, with the reasons on #196. No check changed.
- `third-party / review` binds the reviewer's completion comment to the push,
  as it does the summary row: the comment counts only when its `created_at` is
  later than the newest push of the head in the repository's activity log and
  the head is the one commit the branch has pointed at that begins with the
  characters the comment names (ten, as the vendor writes them; a later head
  can be made to share them, and the comment stays on the pull request). Where
  the push cannot be read, or the log is a full page of 100, the comment does
  not count and the "not yet" log names its commit and the reason. A fork's
  branch is not in the base repository's log, so a fork's pull request no
  longer passes on a completion comment (nor, since 0.5.14, on the row): it
  passes on a review, a review comment or the marker. No input, job or check
  name changed, and no API call was added (#193).
- `third-party / review` asks for the repository's activity log newest first
  by name (`direction=desc`; it was the endpoint's default), and the judgement
  takes the newest push of the head as the latest timestamp among the head's
  pushes, not the first one listed; when one of them has no readable timestamp
  neither the completion comment nor the summary row counts. In an
  oldest-first log a head pushed, replaced and pushed back had its older push
  read as the newest, so a comment or row made between the two pushes counted.
  That order was not seen from the API. The gate's code is unchanged (#197).

## [0.5.14] - 2026-09-18

### Changed

- `third-party / review` reads a fourth signal: a `Completed` row in the
  accepted reviewer's summary comment table whose commit is a prefix of the
  head and whose completion time is later than the newest push of that head
  in the repository's activity log, where that head is the one commit the
  branch has pointed at that begins with the row's characters (seven
  characters can be made to match an earlier head; where the push cannot be
  read, or the log is a full page of 100, the row does not count). A
  review started by a push that found nothing left only that row on
  #190, and the check failed after the full wait on a commit the reviewer had
  looked at. Any other status does not count, and the trigger column is not
  read. No input, job or check name changed (#191).
- The inline-comment report of `third-party / review` says
  `inline comments: could not be read` when the comments call failed or did
  not return a list, instead of `no inline comments on this head`; the step
  now writes `null`, not `[]`, when a call fails, and the verdict reads either
  as "no signal" as before. A missing file no longer raises (#188).
- `third-party / review` posts its summons only when the caller passes the
  new optional secret `summons-token`, a token of the repository owner, whose
  login it checks first; a token whose login cannot be read, is another
  person's, or cannot post the comment fails the check at once with the
  reason. The comparison is with the repository owner, so this fits a
  repository owned by a person, not an organization. Without the secret
  nothing is posted and the check waits for the reviewer's own trigger. Why:
  a mention from `github-actions[bot]` drew no review (twice, in the full
  wait, on #186) while a person's did within sixteen seconds, and no reviewer
  read documents honouring a bot's mention. The job's permission drops to
  `pull-requests: read`; a caller granting more is not broken. `ask-comment`
  stays declared (removing an input breaks callers) and is now the text
  posted with a token; no caller gives one today. The decision is lifted out
  and run by `tests/pr-review-summon.sh` (#185).
- What #167's gate leaves, measured: on a Dependabot or release pull request
  the check passes in seconds instead of waiting about four minutes for the
  reviewer's own review (the time measured on #186 from the push run's start
  to the review), and the reviewer reviews those pull requests anyway when
  its automatic reviews are on (#185).
- `third-party / review` prints, once it has decided, how many inline
  comments the accepted reviewer left on the reviewed head and their URLs,
  in the log and the job summary; zero prints as zero, and the line says it
  is a snapshot as of that run. The verdict is unchanged: the check still
  blocks on presence, never on findings. `AGENTS.md` and the how-to say to
  read the inline comments, not only the summary, and to record in the pull
  request description what happened to each (#176).
- The how-to says what was measured about the reviewer's triggers (#186,
  2026-09-18): with the provider's "Automatic reviews" toggle off, the summons
  `third-party / review` posts from `github-actions[bot]` drew no review in
  the check's full wait and the check failed; the same text from a person's
  account started a review in sixteen seconds. So the toggle stays on; the
  0.5.13 note that "the provider's own app may review on its own trigger" is
  the trigger that has been observed to work. What the check's own summons
  does with the toggle on is not measured, and #185 decides what becomes of
  it (#176).

## [0.5.13] - 2026-09-18

### Changed

- `third-party / review` passes a pull request Dependabot opened, as long as
  every push to its branch was Dependabot's by the repository's activity log,
  without posting the summons or waiting, and its log says so. Every other bot's pull request, a coding
  agent's included, is looked at like a person's. A new input,
  `pass-release-pull-requests` (default `false`), does the same for a pull
  request titled exactly `chore(release): vX.Y.Z`; a title is its author's
  choice, so it is off unless the caller asks, and this repository's own call
  turns it on. The step on the reviewer's instructions still runs on all of
  them. No input, job or check name is renamed. On those pull requests the
  check is no evidence of a review; a repository that requires it should know
  that. Commenting the summons still gets a review, and the provider's own app
  may review on its own trigger. The decision is lifted out of the workflow
  and run by `tests/pr-review-gate.sh` (#167).
- `ci / tools` runs its four linters through `tests/shell-lint.sh` (`bash -n`,
  shellcheck) and `tests/workflow-lint.sh` (actionlint, zizmor), so
  CONTRIBUTING's "every `tests/*.sh`" runs them with CI's flags. The actionlint
  and zizmor pins live only in `tests/workflow-lint.sh`; the workflow's install
  step reads them from there. A missing tool is a FAIL with the install
  command and does not hide the other tool's result. An actionlint that is not
  the pinned version is a FAIL in CI; locally it runs and the output says the
  pass is not the pinned pass. shellcheck and bash stay unpinned and the
  versions that ran are printed. `tests/lint-wrappers-cases.sh` holds those
  verdicts with stub tools (#170).

### Fixed

- CONTEXT.md said that under the code scanning rule "a missing analysis
  blocks". Measured otherwise: CodeQL default setup starts no analysis for a
  head Dependabot pushed, the `CodeQL` check lands `neutral`, and both the rule
  and the older required check name accept it (plinth-template #16 merged that
  way on 2026-09-16). CONTEXT.md and the README now say what happens, and the
  First day note the door writes into a new repository no longer says the wall
  treats Dependabot's pull requests like any other: it says CodeQL does not
  analyse those heads and what does run on them. No check or ruleset changed,
  and `main` is still analysed after the merge (#179).

## [0.5.12] - 2026-09-17

### Added

- The floor checker reads the three predicates #42 named and never shipped:
  a tracked dotenv file (`git ls-files`: `.env` and `.env.<anything>`, not
  `.env.example`, `.env.sample` or `.env.template`; an untracked local `.env`
  is not the defect), an action not pinned to a full commit SHA (every
  `uses:` line of `.github/workflows`, a sha256 digest for `docker://`,
  comments and `run: |` blocks skipped), and a service archetype with no JSON
  logs (a known setup anywhere under `src/`). Each finding is a WARN with the
  path and one repair line, never a FAIL: a consumer whose `ci / floor-check`
  passed yesterday passes today, and promoting one is a later compatibility
  decision. What cannot be read is a SKIP, not a pass: no git work tree, a
  `uses` in a form the line pattern does not know, logging the hints do not
  recognise. The JSON-log PASS says it is a static hint, not proof of what
  the process prints. Scope and limits are in `skills/floor-check/SKILL.md`
  (#95).

### Changed

- `ci / docs` runs markdownlint through `tests/markdownlint.sh`, which holds
  the only version pin, so CONTRIBUTING's "every `tests/*.sh`" now lints
  markdown with what the required check runs (it needs Node.js, and network
  on the first run). CONTRIBUTING says the link check is CI-only and why, and
  gives the command for a local look with an unpinned lychee. The documented
  test loop names the tests that failed and ends non-zero; it used to end
  with the status of the last test, so a failure in the middle still read as
  0. CONTRIBUTING also names what the list does not cover: the four linters
  of `ci / tools`, CodeQL and the canary jobs (#113).

### Fixed

- Installing on a machine with git older than 2.37 failed with
  `index.lock: File exists`, and nothing said why (#171). The cause is in git
  and the installer, not here: for a `git-subdir` source (`ponytail-skills`)
  the installer checks out offline first inside a partial clone that has no
  trees; git 2.30.1 to 2.35.3 segfault there and leave `index.lock`, and the
  installer's networked retry dies on the lock. 2.37.0 and newer fail the
  offline attempt cleanly and the retry succeeds (2.36 was not measured). The
  macOS system git can be 2.30.1. The README and the tutorial now state git
  2.37 or newer, and `tests/install-smoke.sh` stops on an older git with the
  cause and the fix instead of the lock message.

## [0.5.11] - 2026-09-17

### Changed

- The e2e journey (`scripts/e2e.sh`, the nightly and the release gate)
  renders a backend instance: the door runs with `--archetype=backend`, so
  the ruleset it applies is shaped with the `image` check and the instance's
  first pull request waits for the template's `image` job like every other
  required check. Before, the door ran with its cli default, and the two
  template releases about that job (v1.4.0, #127; v1.4.1, #151) had only
  ever been exercised on real GitHub by a hand-run repository: v0.5.9 and
  v0.5.10 shipped behind a green gate that never ran the check. The cli path
  stays covered offline (`tests/new-project-failpath.sh`,
  `tests/e2e-driver.sh`); one journey a night, no matrix. The log says
  `archetype: backend` and lists the required checks the pull request waited for, the
  job summary names the archetype, and the driver test fails if the
  archetype is missing or another value (#164).

## [0.5.10] - 2026-09-17

### Changed

- The "First day" note the door writes into the first pull request and
  README.md says two more things about Dependabot: its first pull request
  usually lands while the door waits for CodeQL, so the door's own is #2; and
  after "Update branch" the merge stays blocked for a minute or two while the
  required checks and CodeQL run on the new head, a merge tried then is refused
  with "the base branch policy prohibits the merge", and the answer is to wait
  for a clean state, not to add an approval. Measured on a real instance on 2026-09-16
  with `PUT /pulls/N/merge`: a Dependabot pull request merged with no review
  before and after a web branch update; the only refusal named the strict
  status-check rule ("10 of 10 required status checks are expected"). The
  approval the second real-project record needed was a merge attempted before
  those checks had rerun (#153, from #149).

- The tutorial's `new-project` step, the README's skill table and the arsenal
  say how the door is invoked: type `/` and pick it. It is user-only, so the
  agent cannot see or run it, and an agent answering that it is not installed
  usually means the line reached it as text. In the second real-project record the
  owner pasted the line with a leading space and lost four minutes to that
  answer (#152, from #149).

### Fixed

- `tests/e2e-driver.sh` runs the journey with a 2 s wait instead of 1 s.
  `scripts/e2e.sh` reads its deadline from `$SECONDS`, whole seconds, so a
  1 s deadline set at the end of a wall-clock second was already reached at
  the first poll's check, and the cases that need a second poll (a read that
  succeeds, the recovery push, the merge after it) failed on some runs of
  `ci / tools`, on `main` too. Measured on one laptop: 2 of 20 runs red
  before, 0 of 5 after; the race forced by hand reproduces `main`'s failing
  pair at 1 s and passes at 2 s (#156).

## [0.5.9] - 2026-09-13

### Changed

- `new-project` renders plinth-template v1.4.1. The `image` job's comment
  now tells a server instance to capture `docker logs` into a variable and
  pipe from that; an instance that rewrote the step as `docker logs … | head
  -1` under `pipefail` failed on some runs with exit 141, `head` closing the
  pipe before `docker logs` finished, with the container healthy (#151, from
  #149). The job itself is unchanged; the template's test refuses a live
  docker process on a pipe.

## [0.5.8] - 2026-09-13

### Changed

- `taste-skill` replaces `frontend-design` in the default set, pinned to
  `ccbc156` of Leonxlnx/taste-skill (#68, from #149). In the second
  real-project record the When line of 0.5.7 worked: Sonnet 5 reached for
  `frontend-design` unprompted on a page a person looks at, and the owner read
  the result as generic. On the same page and the same sentence `taste-skill`
  took under five minutes, asked nothing, touched one file, and the owner
  preferred it. Impeccable, the owner's favourite by eye, is listed and not
  installed: its marketplace plugin did not register its skill on Claude Code
  2.1.269, and its `npx impeccable install` writes hooks, agents and skills
  into the repository, which nothing in the default set does. One measurement, one
  page, one owner; the next observation looks again. The default install's
  always-on estimate rises by about 1.6k tokens (thirteen skill descriptions
  where there was one) on the `claude plugin details` meter; no check locks
  that number, the meter is an estimate.

## [0.5.7] - 2026-09-11

### Fixed

- `new-project` reads the owner's shared `.github/ISSUE_TEMPLATE` listing once.
  The config-only warning came from a second read of the same folder, and a
  second read that failed printed as "no config", so the owner whose contact
  links stop applying was not told (#101). The answer now comes from the one
  listing already held; a listing that cannot be read still stops the run.
- The arsenal's When line for `frontend-design` names the moment instead of
  quoting a phrase: any page a person will look at, server-rendered HTML
  included, from its first version (#68, finding N of #120). In the first
  real-project record the agent never reached for the plugin across four
  feature pull requests, and the owner's one stated gap was an unstyled page.

## [0.5.6] - 2026-09-11

### Fixed

- `floor-check` compares the alert thresholds of the live `code_scanning`
  rule with the ones `ruleset.json` gives CodeQL (`errors`,
  `high_or_higher`). Both thresholds set to `none`, a rule that blocks
  nothing, printed `CodeQL enforced (rule)` and exited 0 (#96). Weaker is now
  a FAIL naming the field and the ruleset page that edits it; equal or
  stricter passes; a field the rule does not carry, or a value GitHub does
  not document, is `not verified`. Where several rulesets carry a CodeQL
  rule the strictest live value is compared, as GitHub enforces every rule.
  A repository that requires CodeQL by check name (the door before #41)
  still passes the enforcement line, and the thresholds are `not verified`
  there rather than claimed: a check name asks the analysis to finish and
  blocks on no alert. A consumer whose rule was weakened sees a new FAIL in
  `ci / floor-check` when it raises its pin; the FAIL is the finding.

## [0.5.5] - 2026-09-11

### Added

- A backend or data-ml repository's ruleset requires the check `image`, the
  plain job plinth-template v1.4.0 renders into its `ci.yml` (build the
  Dockerfile, run the image, read its first log line). The door asks
  `scripts/floor-check.py --print-ruleset` for the archetype's ruleset, so the
  name and the archetype set have one owner, and the checker expects the same
  name of the wall and the job in `ci.yml` for those archetypes. `ruleset.json`
  is unchanged: applied by hand, it is the wall every archetype reports to. A
  service repository created earlier that raises its plinth pin sees
  `ci / floor-check` fail until `image` is required and the job exists; the
  name is a new contract, added and never renamed (#127). The door now needs
  `python3`. `scripts/check-ruleset.sh` takes an optional second argument, the
  contexts a shaped ruleset adds, so the body the door posts for a service
  archetype is held to the same invariants as `ruleset.json`.

### Changed

- The door renders plinth-template v1.4.0. The instance's `ci.yml` grants
  `issues: read` to its python-ci.yml call, so `ci / floor-check`'s label check
  reads labels instead of reporting `not verified` (#102); `AGENTS.md` says a
  ruleset or code-scanning change is a person's, never administration on the
  everyday token, and `CONTRIBUTING.md` states the limit of the wall (#129); a
  service instance carries the `image` job and its Dependabot docker updates
  ignore major and minor (#127). The template pins python-ci.yml at `98e8e56`,
  the first pin that carries the label check.
- README states the limit of the wall: anyone holding administration can change
  the ruleset; it stops the everyday agent, not the administrator (#129).

### Fixed

- The three things the door prints at the end and the next session never sees
  (the CodeQL recovery push, the fine-grained token line, what to do with
  Dependabot's pull requests) are written into the first pull request's body
  and a "First day" section of `README.md`; the terminal says where they now
  live (#141, from #120 and #125).

## [0.5.4] - 2026-09-11

### Fixed

- The door opens the first pull request only once CodeQL default setup's
  first run on `main` has completed and a minute has passed, and enables
  default setup once GitHub has detected the languages, with `actions` and
  `python` spelled out. The listed `dynamic/github-code-scanning/codeql`
  workflow was the signal before, and three repositories in a row
  (`plinth-e2e-20260909052724` and `plinth-e2e-34324833382` in #62,
  `dividend_calendar` in #120, all 2026-09-09) had a first pull request that
  was never analysed and merged only after a re-push; enabled twenty seconds
  after the first push, default setup analysed `actions` alone and the Python
  under `src/` was never scanned. Measured on three more (#117): a pull
  request pushed 2 s after the run completed was not analysed
  (`plinth-e2e-34499093907`, 2026-09-10); pushed 230 s and 66 s after, it was
  (`plinth-e2e-34502351744`, 2026-09-10; `plinth-e2e-34546889124`,
  2026-09-11, no re-push). If CodeQL still has not picked the pull request up
  after 90 s, the door pushes one empty commit itself, the recovery it used to
  print for the user to type (analysed every time it was tried, the door's own
  included: `plinth-e2e-34548699421`, 2026-09-11, pushed 4 s after the run and
  missed, re-pushed at 90 s and analysed 8 s later); the printed line stays for
  the case after that. The door prints the times it saw, and
  warns with the fix when Python is not in the list. `PLINTH_FIRST_PR_WAIT`
  now bounds three waits and defaults to 300 s.
- `floor-check` reports the languages CodeQL default setup analyses, warns
  with the one `PATCH` when Python is not among them, and says `not verified`
  when the token cannot read the setup (the Actions token in CI cannot).

## [0.5.3] - 2026-09-10

### Changed

- The door renders
  [`coolbress/plinth-template@v1.3.0`](https://github.com/coolbress/plinth-template/releases/tag/v1.3.0):
  its settings also deny `. ./.env` and `source .env` (#128), and a `cat` or
  `grep` of `.env` inside `$(...)` or a subshell (#136); its README and
  AGENTS.md say what the deny reaches and what only the sandbox does.

### Fixed

- `floor-check` also asks the agent settings for `Bash(cat *.env)` and
  `Bash(grep *.env)`, and this repository's settings carry them. The Read
  deny's Bash check sees only a top-level command: measured on Claude Code
  2.1.267 with `Read(./.env)` denied in every spelling, `echo "$(cat .env)"`,
  `x=$(cat .env)`, `export $(cat .env | xargs)`, `(cat .env)` and
  `{ cat .env; }` ran (anthropics/claude-code#89055). A Bash rule reaches
  those; with the two rules each is refused, and `cat .env.example`,
  `grep KEY .env.example`, `grep -rn "os.environ" .` still run. The
  sandbox-off warning now names what stays open: `bash -c`, another reader
  inside `$(...)`, a `grep -r` that names no file, an interpreter (#136).

- `floor-check` also asks the agent settings to deny `. ./.env` and
  `source .env` (`Bash(. *.env*)`, `Bash(source *.env*)`), and this
  repository's settings do. Measured on Claude Code 2.1.267 with the sandbox
  off: `Read(./.env)` already stops `cat`, `head`, `tail`, `sed`, `grep` and
  `<` on `.env`, alone and in a pipe, `&&` or `;` chain, but not a sourced
  `.env`, which an agent did to load a key and got the value back in a shell
  error (#128). The two Bash rules stop every sourcing shape tried, including
  inside `set -a; ...; set +a`, and leave `.venv/bin/activate` alone. Still
  open, and now named by the sandbox-off warning: `$(cat .env)`, `bash -c
  "cat .env"`, and an interpreter opening the file; only the sandbox's
  `denyRead` stops those.

- The door prints the admin fix's arguments on a third line, joined to the
  call by a backslash. With the arguments on the call line it was 82
  characters and still wrapped at 80 columns (#132, measured after #125);
  every printed line now stays under about 60, `P=` runs alone if a paste
  splits the lines, and the backslash keeps the call and its arguments one
  command.

## [0.5.2] - 2026-09-10

### Added

- Tier 2, the real repository journey: `scripts/e2e.sh` runs the door against
  GitHub (create, render, `main`, labels, CodeQL, ruleset, the first pull
  request), reads the wall back with the floor checker, waits for every check
  to be green, squash-merges, reads `main` back, and deletes the repository.
  Its first act is to create and delete a sibling name, `<name>-probe`, so
  a token that can create but not delete stops before anything is left behind;
  a repository it could not delete is named on stderr and in the job summary,
  and the exit is 1; the cleanup trap stays armed through the last deletion,
  so a cancellation landing there is reported too (#122). When CodeQL has not
  picked the first pull request up after a fifth of the wait, it pushes the
  door's recovery commit once (the door's own advice; measured necessary on
  2026-09-09, #117), and only on a read of the check names that succeeded
  (exit 0, or 8: pending): any other exit of `gh pr checks` is not evidence
  that CodeQL is absent, and a merged repository whose deletion failed is
  named apart from a rollback (#122).
  `.github/workflows/e2e.yml` runs it nightly and on demand from the secret
  `PLINTH_E2E_TOKEN`; an absent secret is red, not a pass.
  `tests/e2e-driver.sh` holds its failure paths against a mocked `gh`.

### Fixed

- The door's admin path as a new user meets it (#125, observed in #120). The
  fine-grained-token fix is printed as two short lines, `P=<scripts dir>` and
  the call through it, so a copy split by wrapping still runs; the skills and
  the tutorial say to run it in a separate terminal window, not with `!`, and
  `with-admin-token.sh` says so itself when it has no terminal to prompt at.
  An existing target directory that is empty is accepted (a non-empty one, a
  file or an unreadable directory is still refused before anything exists),
  and the name refusal says a bare `<name>` is valid.
- `floor-check.py` counts what it could not verify. An item the run could not
  read (offline, no `--repo`, an API error, a token that does not see it) is a
  `SKIP` line, and the summary reads `-- N failed, M not verified`; exit codes
  are unchanged, so a consumer CI that treats 0 as pass keeps working. Before,
  an offline run of a valid instance ended `-- 0 failed` with the wall
  unchecked, and the skill read that as "the floor is intact" (#119). The skill
  and README § Status now say what 0 means and what the live baseline showed.
- The door renders the template with copier at one pinned version and no
  dependency published after one pinned date (both constants beside the
  template tag), with the token removed from copier's environment, and
  before the repository exists on disk. Copier runs as you, with your git
  configuration in reach, and the template is public, so nothing there needs
  the one credential that reaches every repository of the owner, and nothing
  it writes can be a hook or a config line that a later git command, run
  with the token, would execute (whatever `.git` it leaves is removed before
  `git init`).
- `tests/install-smoke.sh` removes the fresh config directory it made (about
  200 MB of pinned plugins per run) instead of leaving it under the temp
  directory; `CLAUDE_CONFIG_DIR` keeps one.

### Changed

- `scripts/make-release.sh` run 2 tags nothing without a green `e2e` run on
  the very commit it is about to tag: not the latest green run, not one on a
  later `main`, not a failed, cancelled, skipped or running one, and a query
  that fails is refused rather than read as "no run". The nightly run counts;
  so does `gh workflow run e2e.yml --ref main` once the release pull request
  has merged. `tests/make-release-guards.sh` grew from 59 to 73 cases.

## [0.5.1] - 2026-09-09

### Fixed

- **The door builds a repository whose `main` is the default branch and carries
  the wall.** It proved a token could push by pushing a throwaway
  `__push-probe` branch first; GitHub adopts the first branch pushed to an empty
  repository as its default and then refuses to delete it, so the ruleset
  (which targets `~DEFAULT_BRANCH`) went up on the probe and `main` was left
  with no rules at all. `main` is now pushed first and nothing before it — that
  push is itself the proof the token works — and the default branch is read back
  from the API before the ruleset is applied, repaired if it is not `main`, and
  the run rolls back if it cannot be. **A repository created by v0.5.0 is
  affected and does not repair itself; the release notes carry the two
  commands.**
- The floor checker states the branch it checked the wall on and warns when that
  is not `main`. It followed the default branch in silence, so it reported an
  intact wall on a repository whose `main` had no rules — the one signal an
  already-created repository has, saying the opposite of the truth. A warning,
  never a failure: `ci / floor-check` runs in every consumer's CI, and a
  repository whose default is deliberately `master` or `trunk` is not broken.
- The door no longer deletes a repository whose CI run it saw. It required the
  first pull request's run on two consecutive polls and then used that same
  counter to decide whether a run had ever appeared, so a run seen once was
  reported as never appearing and the rollback deleted the repository.

## [0.5.0] - 2026-09-08

### Added

- `scripts/make-release.sh`: one command, run twice. From an up-to-date `main`
  it bumps `plugin.json` and `marketplace.json` together and opens this file's
  next section on a `release/vX.Y.Z` branch; from the merged `main` it pushes
  the tag and creates the GitHub Release (notes on top, generated index under
  them). It refuses an empty notes file, one without the
  `tested with <template> <tag>` line naming the tag the door pins, a version
  not above the current one, and an existing tag or release.
  `tests/make-release-guards.sh` holds the guards.
- `.github/release.yml`: the generated part of the release notes grouped by
  pull-request type label.
- `marketplace.json` carries the marketplace version, equal to the plugin's;
  `tests/marketplace-manifest.sh` fails when they differ.

- Plugin and marketplace manifests; the default plugin set as dependencies
  (`mattpocock-skills`, `frontend-design`, `last30days`, `ponytail-skills`)
  and a catalog entry (`ponytail`, hooks included).
- Placeholder skills `new-project` and `floor-check`; the `arsenal` catalog skill.
- `/plinth:floor-check [owner/name]` (0.4.0): runs `scripts/floor-check.py`,
  the checker `ci / floor-check` runs, read-only, with `--sandbox` for this
  machine's Claude Code sandbox state (WARN when off). The checker reads the
  GitHub API through `gh` when it is installed, so the owner's login sees
  bypass actors. The skill relays the output whole and adds one fix line per
  FAIL or WARN.
- Optional third-party review check: reusable `pr-review.yml` (check name
  `third-party / review`; passes when an accepted reviewer account left a
  review signal on the current commit; drafts are not summoned; the verdict
  never blocks; a change to the `## Code Review Rules` section cannot be mixed
  with other changes in one pull request) and this repository's caller
  `third-party.yml`. Not in `ruleset.json`; a repository adds it with
  `scripts/upgrade-ruleset.sh`. `AGENTS.md` gains the `## Code Review Rules`
  section the reviewer reads.
- Reusable `pr-label.yml` and the caller `label.yml`: the pull request title's
  type becomes a label (not a check).
- Ruleset and security tools for existing repositories, all through
  `scripts/with-admin-token.sh`: `upgrade-ruleset.sh` (adds required checks;
  refuses names that never reported), `add-ruleset-rule.sh` (adds a rule kind;
  presets `linear-history`, `code-scanning`, `signed-commits`),
  `create-tag-ruleset.sh` (tags cannot be deleted or moved) and
  `set-security-setting.sh` (writes, then reads back). Tests for each.
- CI: `ci / tools` (actionlint with a checksum-verified binary, `bash -n`,
  `shellcheck -S warning`, zizmor over every workflow, and the tool tests).
- `/plinth:new-project [<owner>/]<name>`: preflight (tools, token kind and
  scopes, owner and membership, public only), one summary line, then create,
  render the template at the tested tag
  ([`coolbress/plinth-template@v1.0.0`](https://github.com/coolbress/plinth-template/releases/tag/v1.0.0))
  with the owner and the license, so pyproject's author and URLs and the
  LICENSE file follow the choice; the archetype and the license are both
  checked against the template's own `copier.yml` before anything is created,
  because copier refuses a value outside its choices only after the repository
  exists. Then push `main`, the labels (every kind of record and child ticket
  `docs/agents/issue-tracker.md` names; a label that cannot be created warns
  and names itself, and the run carries on, because a label is not a wall
  stone), CodeQL, the ruleset, secret scanning, Dependabot,
  Actions allowlist (`coolbress/plinth/*`, SHA pins required), squash only, and
  the first pull request, whose workflow must start; CodeQL is waited for too
  (default setup must register its workflow before the push, and if CodeQL
  still misses the pull request the summary names the re-push). After the
  repository is created, a fatal exit before setup completes attempts a
  best-effort deletion; the local clone stays, and a failed deletion prints the
  URL loudly. A label that cannot be created, and CodeQL readiness delays, warn
  and carry on.
  `scripts/with-admin-token.sh` for machines whose `gh` token is fine-grained.
  Tests: `tests/new-project-failpath.sh` (mocked `gh`, 65 cases) and
  `tests/token-prompt-not-from-stdin.sh`.
- CI: `ci / install` (real install on a clean runner) and `ci / docs`
  (markdownlint, link check, vocabulary gate, README vs tutorial).
- Dependabot for GitHub Actions, so commit-SHA pins get reviewed bumps.
- Reusable CI `python-ci.yml` with the nine required checks (`ci / pr-title`,
  `lint`, `typecheck`, `test`, `build`, `secrets`, `deps`, `diff-size`,
  `floor-check`), the `ruleset.json` the door applies, which also requires
  CodeQL through a code scanning rule rather than a check name (a name that
  never reports locks the repository silently; the rule blocks with a reason
  and on the alerts themselves; measured on plinth#5), the canary project that
  runs the workflow in this repository's own CI, and the shared floor checker
  `scripts/floor-check.py` (files, agent settings, live ruleset drift, and
  CodeQL enforced as a rule or, for older repositories, as a check name).
- This repository's own floor: `CONTRIBUTING.md`, `.gitattributes` (LF line
  endings, `uv.lock` folded in diffs) and `.claude/settings.json` (denies force
  push, `rm -rf`, `.env` reads and `gh` token reads for agent sessions).

### Changed

- The plugin version moves in a release, not in every pull request that
  touches the plugin (`AGENTS.md`).
- Issues #14 to #70 (the productisation map, its research and decision
  issues, the spec and its tickets) were moved into this repository on
  2026-09-06 with their comments. Commit messages from before that date cite
  them by their old numbers in the earlier repository; for #84 and up the new
  number is the old one minus 68, and the full table is pinned on #31.

[Unreleased]: https://github.com/coolbress/plinth/compare/v0.5.20...HEAD
[0.5.20]: https://github.com/coolbress/plinth/releases/tag/v0.5.20
[0.5.19]: https://github.com/coolbress/plinth/releases/tag/v0.5.19
[0.5.18]: https://github.com/coolbress/plinth/releases/tag/v0.5.18
[0.5.17]: https://github.com/coolbress/plinth/releases/tag/v0.5.17
[0.5.16]: https://github.com/coolbress/plinth/releases/tag/v0.5.16
[0.5.15]: https://github.com/coolbress/plinth/releases/tag/v0.5.15
[0.5.14]: https://github.com/coolbress/plinth/releases/tag/v0.5.14
[0.5.13]: https://github.com/coolbress/plinth/releases/tag/v0.5.13
[0.5.12]: https://github.com/coolbress/plinth/releases/tag/v0.5.12
[0.5.11]: https://github.com/coolbress/plinth/releases/tag/v0.5.11
[0.5.10]: https://github.com/coolbress/plinth/releases/tag/v0.5.10
[0.5.9]: https://github.com/coolbress/plinth/releases/tag/v0.5.9
[0.5.8]: https://github.com/coolbress/plinth/releases/tag/v0.5.8
[0.5.7]: https://github.com/coolbress/plinth/releases/tag/v0.5.7
[0.5.6]: https://github.com/coolbress/plinth/releases/tag/v0.5.6
[0.5.5]: https://github.com/coolbress/plinth/releases/tag/v0.5.5
[0.5.4]: https://github.com/coolbress/plinth/releases/tag/v0.5.4
[0.5.3]: https://github.com/coolbress/plinth/releases/tag/v0.5.3
[0.5.2]: https://github.com/coolbress/plinth/releases/tag/v0.5.2
[0.5.1]: https://github.com/coolbress/plinth/releases/tag/v0.5.1
[0.5.0]: https://github.com/coolbress/plinth/releases/tag/v0.5.0
