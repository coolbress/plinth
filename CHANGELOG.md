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

### Changed

- The fourth thing `docs/how-to/run-a-project.md` says to set by hand, the
  made-up row read from outside with only the public key and no login, is
  shortened to the weight of the other three: it still names the database's
  own address rather than the app's page, and no longer lists a hosted
  database's routes (tables, views, functions), that a refusal covers only
  the route asked, or that an empty table proves nothing. v1.7.5 shipped
  the long one (#425).

## [1.7.5] - 2026-10-07

A new repository renders plinth-template v1.8.0, whose agent hands a refused
workflow push to a person instead of widening its token and writes an issue's
ending when a merge closes it (#417, #418). The run-a-project guide gains four
things to set by hand that no check covers (#412), the last of which asks for
a made-up row in each table that should be private through every route the
app's public key reaches (#419). plinth's own AGENTS.md now states the review
round budget in place instead of behind a link (#422).

tested with plinth-template v1.8.0

### Added

- `docs/how-to/run-a-project.md` lists four things to set by hand once the
  first pull request is merged: production credentials and the production
  database kept out of the agent's session, which gets made-up or scrubbed
  data instead of a copy, a spend ceiling on every paid
  service, one restore tried on purpose, and a made-up row in each table that
  should be private read from outside, through every route the app's
  public key reaches, with no login. They are guidance: no check covers them,
  the page says so, and their effect has not been measured. The README's limits and the concepts page point at
  them, and the concepts page no longer lists them as direction (#412, #419).

### Changed

- `/plinth:new-project` renders plinth-template v1.8.0. A repository it creates
  tells its agent that a push GitHub refuses because it changes
  `.github/workflows/` goes to a person, never to a wider token (#417), and
  that whoever merges writes an issue's ending when `Closes` closes it (#418).
  `/plinth:floor-check` now reports a repository on v1.7.1 as one tag behind.

## [1.7.4] - 2026-10-06

A documentation release. It carries the direction work of 2026-10-05 and 2026-10-06 into the pages a user reads: the concepts page states what plinth is for, what it promises and the five conditions under which a green check means what it asserts; the glossary gains host, the service that holds the repository and refuses a merge while a required check is red, today GitHub.com; the explanation pages say that plinth configures the host to require checks, most of them established tools and a few plinth's own, rather than running them itself (#411); the README opens with the person plinth is for, three questions, the install and the limits; and the pages describe private repositories as supported on GitHub Pro, Team and Enterprise, as a recorded run found them (#352). No check, script or template changes.

tested with plinth-template v1.7.1

### Changed

- The concepts page now says in one place what plinth is for (a good project
  stands, and the five things a project settles once, the agent's reach
  among them), what it promises (gated where a check can, guided where it
  can't), what it covers, what it does not do (it gates a merge, not an
  agent's actions, and names what is outside every check), and the five
  conditions under which a green check means what it asserts, each with
  what breaks it and what plinth has against it today; direction is kept
  under its own heading. `CONTEXT.md` defines verdict, reach and the two
  kinds of condition, and says a listed arsenal tool can be outside the
  plugin system (#402).
- The README, the getting-started tutorial, the concepts page and the
  required-checks reference describe private repositories as supported on
  GitHub Pro, Team and Enterprise, with the parts of the wall each plan and
  licence allows, after a recorded run on a Pro account merged a private
  repository's first pull request. They no longer call private repositories
  unsupported (#352).
- The README opens for the person plinth is for: three questions a user
  arrives with, one answer each, the install, the first command, a link to
  the run-a-project guide, and the limits beside them. Supported versions,
  install details and the skill-listing budget follow below it. The README
  and the concepts page name that person by what they do: someone who runs
  a software project through an AI agent and leads it rather than reads it
  (#310).

## [1.7.3] - 2026-10-05

New repositories pick up the private-repository fix. `/plinth:new-project`
renders plinth-template v1.7.1, whose CI calls plinth v1.7.2, so a private
repository it creates on GitHub Pro without GitHub Code Security gets a
`ci / deps` that passes with a warning that nothing was checked, where GitHub
refuses dependency review, instead of failing every pull request. No check
name, job, input or secret changes.

tested with plinth-template v1.7.1

### Changed

- `/plinth:new-project` renders plinth-template v1.7.1. A repository it creates
  calls plinth's reusable workflows at `e52e750`, plinth v1.7.2, instead of
  `8f4edfc` (v1.5.0), so its `ci / deps` passes with a warning that nothing was
  checked on a private repository where GitHub refuses dependency review,
  instead of failing every pull request (#395). `/plinth:floor-check` now
  reports a repository on v1.7.0 as one tag behind.

## [1.7.2] - 2026-10-05

Private repositories without GitHub Code Security can merge again. On such a
repository GitHub refuses dependency review with a bare 403, and `ci / deps`
failed every pull request on it, so a private repository created on GitHub Pro
could merge nothing; a recorded run on a Pro account found it. `ci / deps` now
passes there with a warning that nothing was checked, but only on a private
repository that is not a fork and whose dependency graph still accepts an
SBOM report request; any other answer runs the review and fails as before.
`/plinth:new-project` names the gap beside code scanning. plinth-template pins
this release next, so repositories it creates pick the fix up.

tested with plinth-template v1.7.0

### Fixed

- `ci / deps` no longer fails every pull request on a private repository
  without GitHub Code Security. GitHub refuses dependency review there with a
  bare 403, and the action failed on it, so a private repository
  `/plinth:new-project` created on GitHub Pro could merge nothing. Where a
  private repository that is not a fork gets that answer while its dependency
  graph accepts an SBOM report request, the job now passes with a warning and a summary saying nothing was checked, and
  why; a disabled graph gives the same 403 and still fails, as does any other
  answer. The door names the gap beside code scanning, in its
  summary, the README's First day section and the first pull request (#395).

## [1.7.1] - 2026-10-04

The third-party review, harder to skip and plainer about its limits.
`pass-release-pull-requests` used to pass any pull request on its title alone,
and an author chooses the title; a release pull request now passes only when
its diff is the one `scripts/make-release.sh` writes. When the review times
out, the log names a used-up usage limit as a possible cause, and the how-to
says that Codex is the only reviewer verified end to end and what to do when
the reviewer does not come. No check name, job, input or secret changes; a
caller with the release option on whose release pull requests differ from
plinth's is summoned on them.

tested with plinth-template v1.7.0

### Changed

- When `third-party / review` times out, its log names a used-up usage limit
  on the reviewer's account as a possible cause: Codex cloud reviews share one
  limit with interactive Codex use, and a used-up limit can end in silence.
  The check still fails; no limit message from Codex is recognised, since none
  has been captured (#386).
- The third-party reviewer how-to says Codex is the only reviewer verified end
  to end: another reviewer counts when it leaves a review on the current
  commit, and one that reports a clean review only as a comment, in a shape
  other than Codex's, fails after the wait (#387).
- `pass-release-pull-requests` passes a pull request titled
  `chore(release): vX.Y.Z` only when its diff is the one plinth's
  `scripts/make-release.sh` run 1 writes: exactly `.claude-plugin/plugin.json`,
  `.claude-plugin/marketplace.json` and `CHANGELOG.md`, each manifest replacing
  its one `"version"` line with the title's, a higher one, `CHANGELOG.md` only adding lines. The
  title alone used to pass, and an author chooses the title; any other diff
  under it is now summoned, with the reason in the log, and so is one whose
  file list cannot be read. A caller with the option on whose release pull
  requests differ from that is summoned on them (#384).

## [1.7.0] - 2026-10-04

Acceptance criteria tied to evidence. A repository `/plinth:new-project`
creates now renders plinth-template v1.7.0: its task form introduces the
acceptance criteria as a "Done means" checklist, ticked when the issue closes,
and its pull request template and `AGENTS.md` ask a pull request to name, for
each criterion it meets, the test that checks it or why none does. A required
check can show that the existing tests pass, not that the work did what was
asked; this asks for the second in writing. No check enforces it, and no check
name changes. Also: an interrupted `tests/install-smoke.sh` stops what it
started, and this repository's agent rules ask whoever closes an issue to tick
the criteria that were met and to say whether a stated judgement held.

tested with plinth-template v1.7.0

### Changed

- `/plinth:new-project` renders plinth-template v1.7.0. A repository it creates
  ties each acceptance criterion to its evidence: the task form introduces the
  criteria as a "Done means" checklist, ticked when the issue closes; the pull
  request template asks the description to name, for each criterion it meets,
  the test that checks it or why none does; and its `AGENTS.md` says both and
  has a resume read an issue's unticked criteria. No check enforces it (#299).
  `/plinth:floor-check` now reports a repository on v1.6.0 as one tag behind.

### Fixed

- `tests/install-smoke.sh`, interrupted, stops what it started before it
  removes its temporary config dir. A `TERM` or `HUP` to the script used to
  leave `claude` and its marketplace clone running, and they recreated the
  dir after it was removed. Ctrl-C used to end only the `claude` step, and
  the script ran the remaining README lines and ended in a misleading FAIL;
  it now exits 130 there. A config dir the caller set is still left alone.
  `tests/install-smoke-interrupt.sh` covers each signal with a stub `claude`
  and no network (#345).

## [1.6.0] - 2026-10-03

Private repositories, where the plan can hold a wall. `/plinth:new-project
--private` used to stop for every request. On GitHub Pro, Team or
Enterprise it now creates a private repository with the same required checks
as a public one; the CodeQL rule and push protection go on only where the
repository has the Code Security and Secret Protection licences, and the
door names each part it left out and what stands in its place. It never
turns a paid product on. A personal Free account still stops before
anything is created: a ruleset cannot stand on its private repository.
Repositories it creates use plinth-template v1.6.0, whose checks run again
when a pull request is edited.

A minor version: no check name, job, input, secret or skill name changes.
Nothing here has run against a real private repository yet; the README and
the docs pages still describe private repositories as unsupported until a
recorded run on a Pro account updates them (#352).

tested with plinth-template v1.6.0

### Added

- `/plinth:new-project --private` creates a private repository where the
  owner's plan lets a ruleset stand on one, instead of stopping for every
  private request. An owner whose plan reads GitHub Free still stops before
  anything is created, with the reason and the same command for a public
  repository. Elsewhere the ruleset is the public one with the same check
  names. Its `code_scanning` rule and CodeQL are set up only when GitHub Code
  Security reads enabled on the new repository, and push protection only when
  GitHub Secret Protection does; the door turns neither product on, since
  each is billed. The end summary and the README's First day section say the
  repository is private, that CI runs on the plan's Actions minutes, and name
  each part left out with what stands in its place: `ci / lint`'s security
  rules, and `ci / secrets` after the push. Where a product reads disabled,
  the line also says where a person can turn it on and that it may be billed. A setting the token does not read
  is reported as not verified and its part is left out. A classic token
  reads its own plan with the `read:user` scope, which `gh auth login` does
  not ask for: without it `--private` stops and names
  `gh auth refresh -h github.com -s read:user`. A plan no scope would show
  (an organization's to a member who is not an owner, a fine-grained token's)
  is said before creating; the ruleset call then decides, and a refusal
  deletes the repository, so without the `delete_repo` scope that case stops
  first. A repository it creates runs `ci / floor-check` from plinth v1.5.0
  (through plinth-template v1.6.0), which reads a private repository's wall
  against its licences, so its first pull request can merge without the
  CodeQL rule. The README and the docs pages still describe private
  repositories as unsupported, and no run on a real private repository is
  recorded yet (#352). `scripts/check-ruleset.sh
  --without-code-scanning` checks the variant without the rule. No check name
  changes (#350).

### Changed

- `/plinth:new-project` renders plinth-template v1.6.0. A repository it creates
  now calls plinth's reusable workflows at `8f4edfc`, plinth v1.5.0, instead
  of `8e96702` (v1.1.0), so its `ci / floor-check` reads a private
  repository's wall against its licences and reports push protection, and
  `ci / pr-title` refuses a title ending in `(#N)`. Its `ci.yml` runs on the
  `edited` pull-request event too, so a retitled pull request re-runs its
  checks without a push (#322). `/plinth:floor-check` now reports a
  repository on v1.5.9 as one tag behind.

## [1.5.0] - 2026-10-03

The checker learns private repositories, ahead of the generator. A private
repository can carry the same required checks as a public one on GitHub Pro,
Team or Enterprise, but code scanning and push protection there need paid
licences. `/plinth:floor-check` and `ci / floor-check` now read such a
repository's wall against what it has: a missing CodeQL rule is a failure
only where Code Security is on, and otherwise a gap named with what stands
in its place. This release exists so that repositories `/plinth:new-project`
will create as private, in a later release, run a checker that lets their
first pull request merge.

A minor version: a public repository's report does not change, and no check
name, job, input, secret or skill name changes. What a private repository's
security settings answer on each plan has not been measured on GitHub yet.

tested with plinth-template v1.5.9

### Changed

- `/plinth:floor-check` and `ci / floor-check` read a private repository's
  wall against its licences (#351). Where the repository answers
  `"private": true`: a missing CodeQL `code_scanning` rule is a FAIL only
  where GitHub Code Security (or the earlier Advanced Security licence) is
  enabled on it, and push protection that is off is a WARN only where secret
  scanning is enabled. Where the product is disabled, the item is an INFO
  naming the gap and what stands in its place (`ci / lint`'s security rules;
  `ci / secrets`), outside the failed and not-verified counts, and default
  setup's languages are not read. Where the repository's security settings
  give no answer for the product, a missing rule is a SKIP, and so is push
  protection that is off. `ci / floor-check` reads with the Actions token,
  which does not get those settings: on a private repository without the
  rule it prints an INFO saying the licence state is judged when
  `/plinth:floor-check` is run with a login that administers the
  repository, outside the not-verified count, as it does for push
  protection. That item does not fail the run there, whether or not the
  repository has Code Security. So a private repository that has the
  licence and lost its rule is a FAIL in `/plinth:floor-check` and not in
  CI; before this change CI failed every private repository without the
  rule. A rule that is present, the required check names and every other
  item are read as on a public repository, and a public repository's report does not change.
  Not measured on GitHub: what a private repository's security settings
  answer on each plan (#352).

## [1.4.0] - 2026-10-01

Secrets stopped at the push, and issues closed only on purpose.
`/plinth:floor-check` now reports GitHub's push protection, which refuses a
push carrying a known secret format before the secret lands in the
repository (the pusher can still choose to bypass it, and the refused push
has reached GitHub's scanner), and names the command that turns it on when
it is off; `ci / floor-check` says in one line
that the Actions token cannot read it, instead of counting a check it could
never make. The reference docs name push protection and the paid rule that
blocks merging a pull request with an exposed secret, without promising
either.

Two changes apply to plinth's own repository: a pull request whose
description would close an issue outside its closing line fails before the
merge, after a sentence in one closed the 1.0 plan early; and the merge
script reads each check by its newest run, so a review that lands late no
longer needs a manual re-run.

A minor version: `floor-check` gains an item, and no check name, job,
input, secret or skill name changes.

tested with plinth-template v1.5.9

### Fixed

- `scripts/merge-when-green.sh` reads each check name by the run started last
  on the head, not the one finished last, since overlapping runs can finish
  out of order. A review that arrived after `third-party / review` gave up
  started a new run that passed beside the failed one, and the script stopped
  on the old failure until it was re-run by hand (#369). A run still in
  progress under a name holds the merge as before (#363).

### Added

- `floor-check` reports GitHub's push protection, the setting that refuses a
  push carrying a secret in a format GitHub knows; `ci / secrets` reports a
  secret only after it is on GitHub. On is a PASS. Off is a WARN with the
  call that turns it on, never a FAIL, so no repository that passed before
  goes red. A token that does not get the repository's security settings
  gives a SKIP. `ci / floor-check` runs on the Actions token, which never
  gets them, so its step passes `--actions-token` and prints an INFO there
  that names `/plinth:floor-check` as the run that reads it: no consumer's
  `N not verified` grows by a line nobody can clear. The door already turned
  push protection on; this reads it in a repository the door did not make,
  or where it was switched off since.
  [Required checks](docs/reference/required-checks.md#secrets-at-the-push)
  names it, and the paid ruleset rule that blocks a merge with an exposed
  secret, which plinth neither sets nor reads (#303).
- plinth's own `ci / docs` fails a pull request whose description would close
  an issue outside its closing line. GitHub closes an issue when a closing
  keyword stands directly before its number anywhere in a merged description,
  in a sentence too: "the two fixes #65 decided" closed #65 with every
  criterion open. The step reads GitHub's own list of the issues the merge
  will close and compares it with the `Closes #N` line directly above the
  attribution; the failure quotes the line and says how to reword it.
  `Part of #N` and `Related to #N` close nothing and pass. It runs in plinth's
  repository only: no consumer check, check name or input changes (#293).

## [1.3.0] - 2026-10-01

A lighter default set and fewer stalled pull requests. `last30days` is no
longer installed with plinth, so the default set runs no hook; it stays in
the catalog for anyone who wants it, and an existing install is left in place
until removed by hand. `ci / pr-title` refuses a title ending in `(#N)`,
which a squash merge would number twice. `third-party / review` waits 20
minutes by default instead of 15, since reviews on 2026-09-30 and 2026-10-01
finished just after the old window.

A minor version: what a new install gets changes, and `ci / pr-title` has a
new way to fail in every repository whose `python-ci.yml` pin reaches this
release. No check name, job, input, secret or skill name changes. Two
changes apply to plinth's own repository only: its checks re-run when a pull
request is edited, and a failed review check is re-run once the reviewer's
answer arrives.

tested with plinth-template v1.5.9

### Changed

- `last30days` is no longer installed with plinth; it stays in plinth's
  marketplace at the same pin, and `claude plugin install last30days@plinth`
  installs it. It was the only plugin in the default set that ran a hook (a
  `SessionStart` check in every session), and one call costs about 90k
  tokens. The default set is now `mattpocock-skills`, `taste-skill` and
  `ponytail-skills`, and none of them runs a hook; `tests/install-smoke.sh`
  reads the hook count of every dependency after the install and fails on
  one that is not zero. The README, `/plinth:arsenal` and the marketplace
  descriptions list `last30days` as available, not installed. The skill
  listing figures there were measured again without it, on Claude Code
  2.1.286: 32 skills listed, about 3,650 tokens with a 1M-context model, 26
  of the 32 cut to their name on the two 200k models.

  An existing install keeps it. Measured once, on Claude Code 2.1.286, with
  plinth installed from a local copy of the marketplace before this change
  and `claude plugin update plinth` run after it: the update printed only
  plinth's own version change, and `last30days` stayed installed and
  enabled, hook included. To remove it, run
  `claude plugin uninstall last30days@plinth`. `claude plugin prune` also
  offered it, as an auto-installed plugin no longer needed, and removed it;
  after an explicit `claude plugin install last30days@plinth` it offered
  nothing. Not measured: a marketplace added from GitHub rather than from a
  directory, the Claude Code floor (2.1.274), and an install at project
  scope.

  This makes the next release a minor version, not a patch: a new install
  gets one plugin, one skill and one hook fewer. No check name, job, input,
  secret, ruleset or plinth skill name changes (#354).
- `ci / pr-title` fails a title that ends in `(#N)`: a squash merge appends
  the pull request's own number, so the commit on the default branch would
  carry two, as `fix(floor-check): … (#349) (#359)` did. The job summary says
  where the issue number goes instead (the description's `Closes` or
  `Part of` line). A `#N` elsewhere in the title still passes. A repository
  gets this when its `python-ci.yml` pin reaches this release; the check's
  name is unchanged (#360).
- plinth's own `ci.yml` also runs on the `edited` pull-request event, so a
  retitled pull request re-runs the title check, and an edited description
  re-reads `ci / diff-size`'s warning, without a push. The template's
  `ci.yml` is unchanged here (#322).
- `third-party / review` waits 1200 seconds by default instead of 900, still
  inside the job's 25-minute timeout: two zero-finding reviews landed a few
  minutes after the 900-second wait had ended. A repository that passes
  `wait-seconds` keeps its own value (#363).

### Added

- plinth's own repository re-runs a failed `third-party / review` once the
  reviewer has answered since: when the reviewer's comment arrives (any other
  author's comment, or a comment on an issue, does nothing), and every 15
  minutes as a safety net, since scheduled runs start hours late here. It
  re-runs the failed job when an accepted reviewer's review, review comment or issue
  comment is newer than the failed run, once per new signal and never past
  the third attempt. A reaction alone does not re-run it: the check does not
  count one. A zero-finding verdict (a comment and a `+1`) starts no workflow, so
  the check used to stay red until a person re-ran it. Calling repositories do
  not get this yet (#363).

## [1.2.1] - 2026-10-01

Two fixes to what 1.2 shipped. `/plinth:new-project` no longer loses the
repository it has just created when GitHub answers a setup call with a
server error: on 2026-09-30 the call that sets the Actions allowlist answered
502 to most requests for hours, which held up 1.2.0's own release check
through five attempts. The six calls after the ruleset now try again on 502,
503 or 504, up to four times with growing pauses, and a failure that stays
names the call and GitHub's answer. `/plinth:floor-check`'s list of other
credentials on the machine now reads git's helper configuration and
`~/.netrc` the way git and netrc do, checked against `git credential fill`,
so a helper git would use is no longer missed in the configurations the
earlier reading got wrong.

A patch: no check name, job, input, secret or skill changes.

tested with plinth-template v1.5.9

### Fixed

- `/plinth:new-project` tries a setup call again when GitHub answers 502, 503
  or 504, up to four times after 5, 10, 20 and 40 seconds, instead of
  deleting the repository it had just created. On 2026-09-30 the Actions
  allowlist call answered 502 to 7 of 11 requests in two probes, with no
  pattern in which ones. The calls are the ones after the ruleset (secret scanning
  and push protection, Dependabot, the Actions permissions and allowlist, the
  merge settings), each of which sets a value, so sending it again changes
  nothing; the ruleset's own `POST` is not retried. Any other failure, or a
  server error that persists, still stops and deletes the repository, and the
  message now names the call and GitHub's answer instead of printing only
  `gh: Server Error (HTTP 502)` (#356).
- `/plinth:floor-check` reads git's helper list and `~/.netrc`
  closer to how git and netrc do (#349). An empty `helper =` under a
  `credential.<url>` that names a username, a port, a query or a fragment
  no longer hides the helpers listed before it: git does not apply that entry to a plain
  github.com push, and the report said only gh's helper was left. A
  subsection URL that cannot be parsed is now a SKIP naming it (without any
  user or password in it) instead of stopping the run. `default` counts as a
  `~/.netrc` entry only where a keyword stands, not as a login or password,
  and a token sequence the reader cannot place is not verified. `GIT_CONFIG`,
  which makes git read another file in place of `.git/config`, is named when
  set, as `GIT_CONFIG_GLOBAL` is. git cannot report its helper list without
  running the helpers, so the checker still reads the config itself; its
  tests now run `git credential fill` for 17 subsection URLs and fail when
  git applies a helper the checker does not count.

## [1.2.0] - 2026-09-30

Knowing what the agent can reach. 1.1 showed that GitHub refuses a push that
changes a workflow when the token lacks workflow permission; this release
helps a person make sure the agent works with such a token and nothing
else. `/plinth:new-project` now ends by saying whether the credential the
agent inherits has administration on the new repository, which the ruleset
cannot hold against, and points to the guide's agent-token section when it
does. `/plinth:floor-check` now also lists what else on the machine can
push to github.com: another account stored in `gh`, a git credential helper
other than gh's, a login in `~/.netrc`, an `Authorization` header in git's
config, `GH_TOKEN` or `GITHUB_TOKEN`. It names each one, never its value.
It is a best-effort local report, not a defence: finding nothing is an INFO
that says so, and known gaps in how it reads git's and netrc's formats are
tracked in #349.

A minor version: two additions, and no check name, job, input, secret or
skill name changes. `docs/agents/issue-tracker.md` also asks that public
records be written in the product's voice.

tested with plinth-template v1.5.9

### Added

- `/plinth:new-project` ends with one line saying whether the `gh`
  credential the agent inherits can administer the new repository, which is
  what lets an agent edit or delete the ruleset. A classic token's `repo`
  scope can; a fine-grained token is asked a read that needs Administration,
  and a refusal means it cannot. With administration, the line points to
  "Give the agent a token that cannot change the checks"; a fine-grained
  token that can read Administration, and an answer it cannot read, are said
  to be not verified. Through `with-admin-token.sh` it asks about `gh`'s own
  login, not the typed token (#300). That guide section now says the token
  without Administration cannot edit the ruleset, and how to check it.
- `/plinth:floor-check` lists what else on the machine can push to
  github.com past the agent's token: `GH_TOKEN` or `GITHUB_TOKEN`, a second
  account stored in `gh` (or any stored account while one of those two is
  set), a git credential helper other than gh's (the macOS
  keychain helper included), an `Authorization` header in git's config, and a
  github.com login in `~/.netrc`. Each is a warning that says only whether it
  is there. The rules are best effort: finding none is a note, not a pass.
  One it cannot read is not verified, as is a configuration a
  `GH_CONFIG_DIR`, `XDG_CONFIG_HOME` or `GIT_CONFIG_*` variable hides, and
  SSH keys always are. The guide section gains the same list, with how to see
  and remove each (#336).

## [1.1.1] - 2026-09-29

Fixes to 1.1's new readers, and the first release a new repository starts
on 1.1. `/plinth:floor-check` read a `ci.yml` opening with `---`, yamllint's
recommended first line, as not verified, and a trailing comment ending in
`: |` hid the lines under it, so a correct `ci` job could be reported missing
in `ci / floor-check`. `ci / diff-size` warned about a path the description
did name inside a link with a line anchor or common Markdown emphasis.
`/plinth:new-project` with a first-PR wait under 90 seconds could end without
its CodeQL re-push. And `/plinth:new-project` now renders plinth-template
v1.5.9, whose repositories call plinth v1.1.0 from their first pull request.

A patch: no check name, job, input or secret changes, and no skill is added,
removed or renamed; `/plinth:floor-check`'s page now says a leading `---`
is read. The one `Added`
entry is `scripts/merge-when-green.sh`, which plinth's own maintainers run to
merge; nothing a consumer calls or installs uses it.

tested with plinth-template v1.5.9

### Added

- `scripts/merge-when-green.sh <n>`, for whoever merges plinth's own pull
  requests: it runs CONTRIBUTING's squash-merge command only when every check
  on the head is green, `third-party / review` among them, and every top-level
  inline comment has a reply; otherwise it stops and says why. On a repository
  with no `third-party / review` it stops unless `--no-reviewer` is passed. `tests/merge-when-green-cases.sh` runs it against
  a fake `gh`.

### Changed

- `/plinth:new-project` renders plinth-template v1.5.9. A repository it creates
  now calls plinth's reusable workflows at `8e96702`, plinth v1.1.0, instead
  of `2673947` from before 1.0, so its `ci / diff-size` names a change to the
  checks the description does not, and its `ci / floor-check` fails a `ci` job
  that no longer calls plinth's workflow at a commit SHA. `/plinth:floor-check`
  now reports a repository on v1.5.8 as one tag behind.

### Fixed

- `/plinth:floor-check` reads a `ci.yml` that opens with `---`, the line
  yamllint's `document-start` rule asks for, instead of reporting its `ci` job
  as not verified; a second `---` is still not verified. A `: |` or `: >`
  inside a trailing comment (`jobs:  # note: |`) no longer hides the lines
  below it, which had reported `no ci job` and could miss an unpinned `uses:`.
- `ci / diff-size` counts a path as named when a link to it carries a line
  anchor (`[x](.github/workflows/ci.yml#L3)`, a reference definition or an
  autolink), when a run of `_` or `~`
  stands on each side of it (`_ci.yml_`, `~~ci.yml~~`), and next to a typographic quote or apostrophe
  (`ci.yml’s`). `python-ci.yml`, `ci.yml.bak` and `ci.yml~` still do not name
  `ci.yml`.
- `/plinth:new-project` with `PLINTH_FIRST_PR_WAIT` under 90 seconds no longer
  ends the wait for CodeQL without its one empty-commit re-push when a second
  passes between setting the deadline and the re-push time; both now come from
  one clock reading. The default wait of 300 seconds was not affected.

## [1.1.0] - 2026-09-29

The first release after 1.0 is about a pull request that weakens the checks
instead of passing them. `ci / diff-size` now names each change to the checks
the description does not: a deleted test, an edited workflow, a check
configuration file, a changed `[tool.*]` table. `/plinth:floor-check` fails
when the `ci` job no longer calls plinth's workflow at a commit SHA, and
`ci / floor-check` runs the same item on the pull request's own `ci.yml`. The
guide shows how to give the agent a token without workflow permission, so
GitHub refuses the push that would rewrite the checks: measured for both
token kinds on a push adding a workflow file; a change to an existing one,
such as `ci.yml`, falls under the same refusal by GitHub's message ("create or
update") and was not pushed. The guide states SSH as a limit; it does not yet cover other
credentials stored on the machine, such as a second `gh` account one
`gh auth switch` away or a git credential helper (#336).

A minor version, not a patch: a repository whose `ci` job calls plinth's
workflow at a tag, or gives that job any key but `uses:`, `with:`, `secrets:`
and `permissions:` (an `if:` or a `name:`, say), gets a new FAIL in
`ci / floor-check` when its `python-ci.yml` pin reaches this release. The
template's `ci.yml` already calls it at a SHA and is unchanged. Repositories
`/plinth:new-project` creates still pin an earlier plinth commit until the
template's pin is raised, so they get the new warning and item then.

tested with plinth-template v1.5.8

### Added

- `ci / diff-size` names each change to the checks that the pull request
  description does not: a deleted test file, a test moved out of the test
  paths, an edited workflow, a changed check configuration file (`conftest.py`,
  each file pytest reads its configuration from, `ruff.toml`, `.gitleaks.toml`,
  `ruleset.json` and others) or a changed `[tool.*]` table in `pyproject.toml`.
  Naming the path or the file name in the description is enough, where it
  stands whole: `python-ci.yml` does not name `ci.yml`. It is a WARN in the log
  and the job summary, never a red: the description is read when the run starts
  and an edit does not re-run CI, so a failure could only be cleared by a push,
  and a text match should not block a merge. It does not see a weakened
  assertion inside a kept test, a skip marker, or a threshold the caller passes
  as an input. A repository gets it when its `python-ci.yml` pin reaches this
  release. No check name changes.
- `/plinth:floor-check` fails when the `ci` job in `.github/workflows/ci.yml`
  does not call `coolbress/plinth/.github/workflows/python-ci.yml` at a full
  commit SHA: missing, running its own steps, calling another repository, a
  fork or a local file, pinned to a tag or a branch, or carrying any key but
  `uses:`, `with:`, `secrets:` and `permissions:` (an `if:`, `needs:` or
  `name:` can get it skipped or its checks renamed). plinth itself is the
  one exception: for `coolbress/plinth` its own
  `./.github/workflows/plinth-ci.yml` passes. With `--repo` it reads
  the file from the default branch through the API, not the checkout; offline
  it reads the checkout and says so. A file it cannot read is not verified,
  never a pass. It is the signal from outside the pull request the entry
  below points to, and it comes after the merge: a pull request that removes
  the call removes `ci / floor-check` with it. `ci / floor-check` runs the
  same item on the pull request's own `ci.yml` (`--caller-from-checkout`), so
  a pull request that keeps the call but weakens it fails before the merge,
  and one that repairs a broken caller can merge. A repository whose `ci` job
  already calls plinth's workflow at a SHA, as the template's does, is
  unchanged. One that calls it another way gets a new FAIL in
  `ci / floor-check` once its `python-ci.yml` pin reaches this release, fixed
  in that same pull request. It reads the `ci` job, not
  `ci.yml`'s `on:` triggers: a `ci.yml` that no longer runs on pull requests
  still passes (#333), and whether another workflow reporting the same check
  names satisfies the ruleset is #329's question. No check name changes.
- `docs/how-to/run-a-project.md` has a new section, "Give the agent a token
  that cannot change the checks": after the first merge, a fine-grained token
  for the one repository with Contents, Issues and Pull requests at Read and
  write, and no Workflows or Administration. GitHub refuses a push that adds
  or changes a file under `.github/workflows/` without workflow permission,
  measured for fine-grained and classic tokens (#328), so the agent cannot get
  a rewrite of the checks onto a branch. The setup's browser login, and
  `gh auth login` over HTTPS by default, hold that permission; a push over SSH
  is not refused. A change under `.github/workflows/`, a template update
  included, is then pushed by the person. The getting-started tutorial points
  to it, and `docs/explanation/concepts.md` ("About what green means") names
  it as the control before the pull request, with those limits.

### Fixed

- `docs/explanation/concepts.md` and the 1.0.0 notes below said the check
  above would flag a pull request that replaces the call to plinth's workflow
  with jobs that do nothing. It cannot: the warning runs inside that workflow,
  so such a pull request removes it. It flags a workflow edit only while the
  caller still calls plinth's workflow. A signal from outside the pull request
  is #325.

## [1.0.0] - 2026-09-28

By 2026, AI agents write code well; checking it has not kept up. Research and
practitioners point the same way: an agent's own "done" is not evidence,
review bots help but still miss things, and planning kits guide the agent
without holding it to anything. The harness, the program that turns a model
into an agent, is mature and keeps improving: Claude Code is one. What most
people building with an agent still lack sits outside it: rules on GitHub the
agent's work must pass, and a way of working that leaves evidence. Some
platforms offer such gates, several of them on paid plans. GitHub's own
building blocks are free for a public repository but have to be assembled.
plinth 1.0 sets them up for a public repository with one command, and guides
the inside with tools others made well. Our own attempts to put the rules
inside the agent taught the same lesson.

**You decide. The checks answer. The record remembers.** plinth is for someone
who builds software by telling an AI agent what they want and does not read
the code it writes. Why the rules are not simply told to the agent: Claude
Code is the harness, and plinth puts the rules outside it, on GitHub. What
makes the project professional: pro isn't the code you won't read, it's the
setup around it. How to get better code from the agent: don't count on a
better prompt; work in small steps the checks can answer, as [Run a
project](https://github.com/coolbress/plinth/blob/main/docs/how-to/run-a-project.md)
walks through.

**What 1.0 promises: the parts others build on stay put.** The required check
names, the jobs, inputs and secrets of the reusable `python-ci.yml`, the shape
of the ruleset the generator raises, and the four skill names (`new-project`,
`floor-check`, `template-update`, `arsenal`) get no backward-incompatible
change without a major version. A repository's ruleset requires checks by
name, so a rename would break every consumer. From here, versions follow
Semantic Versioning.

**What 1.0 covers.** Public GitHub repositories, Python projects, Claude Code
2.1.274 or newer as the host. Private repositories stop before anything is
created. This release was tagged only after the end-to-end run created a
repository on real GitHub, merged its first pull request and deleted it,
twice, on this commit. Its author ran three tasks on a generated repository
before this release: a first feature, a recovery from a failure, and a resume.

**What 1.0 does not promise.** A green check means what that check asserts
holds, not that the code is right: a defect planted on purpose passed every
check. A pull request can rewrite its own CI file so that the required checks
run nothing and pass; the diff shows it, and nothing in 1.0 blocks it (#301
would flag it). Anyone whose token has administration on the repository can
change the rules, an agent included. So far the author is the only user. A
version number cannot settle whether another person can finish a project with
plinth. That is what comes next (#163), with the candidates from the
pre-release reviews (#299–#304, #310).

tested with plinth-template v1.5.8

### Added

- `docs/explanation/concepts.md` opens with why plinth exists, starting from
  where agentic coding stands in 2026 rather than from its author's history:
  checking has not kept up with writing, the harness is solved, and what is
  missing is rules outside the agent and a way of working that leaves
  evidence. The author's own attempts are one supporting sentence. The next
  section no longer says the agent cannot switch the checks off without
  saying "without administration".
- `docs/how-to/run-a-project.md`: the user's loop, stage by stage, from an
  idea to a merged change, a bug and a resume. It covers what you type and
  what runs by itself, sizing a job, "say what proves it", three questions
  before a merge, and common mistakes. Most flow skills (`/grill-with-docs`,
  `/to-spec`, `/to-tickets`, `/implement`, `/triage`) run only when typed; a
  plain-words request does not run them. #231 left the
  situations page out until a record asked for it. The owner asked for it,
  and RC1 recorded `/plinth:template-update` going unused for a plain
  request. It draws on the retired playbook guide, #68's accepted design,
  plinth-lab#12, and a September 2026 review of practice.
- `docs/explanation/concepts.md` has a section on how the pieces fit: GitHub, the
  repository and Claude Code, and what each part does and does not promise.

### Fixed

- From the second pre-1.0 review. `floor-check` compares each required
  check with the app its own ruleset entry pins. A ruleset whose checks name
  different apps used to switch the comparison off entirely, and printed
  "no --ruleset". A name that only `--expect-checks` gives, with no shared app
  to assume, is reported as not verified. The poll-interval cases in
  `tests/pr-review-summon.sh` sat after the script's last failure gate, so
  they could not turn it red; they now run before it, under a time limit,
  and fail instead of hanging when the guard is gone. The README's first
  sentence says no change merges past the checks "while they are red", which
  the pull-request rewrite limit two sentences on no longer contradicts.
- The public text says what the two pre-1.0 reviews found it overstated.
  A pull request can rewrite its own CI file so that the required checks run
  nothing and pass. That needs only write access, is visible in the diff,
  and nothing in 1.0 blocks it (#301 would flag it). The README, the guide and
  "About what green means" now say so. The guide no longer says an agent
  without administration "cannot get past" the rules, or that the agent
  asks before merging (it is told to), or that every dependency is pinned
  (mattpocock-skills is range-checked). The generator's rollback is best
  effort in the guide and in the `new-project` skill, which still said
  "creates nothing". The arsenal no longer says every third-party entry is
  pinned. The README describes the door's CodeQL recovery push as it is:
  one empty commit, pushed by the door. The fork recipe names the download
  URLs inside the two reusable workflows. The tutorial says the recommended
  login is administration on every repository the person owns.
- `pr-review.yml` declared `policy-file` and `policy-heading` but ignored
  them: the guard always checked `## Code Review Rules` in `AGENTS.md`, the
  file the reviewer actually reads. A caller that named `REVIEW.md` believed
  that file was guarded, and it was not. Now a value other
  than the default stops the check with an error saying the input is not
  supported. The input names stay, so a caller passing the defaults, or
  nothing, is unchanged. A caller that passed another value now gets a red
  check until it removes the value; before, that value was silently ignored.
  `poll-seconds`, also declared and ignored (a fixed 20), is now used, and a
  value that is not a whole number of 10 or more stops the check. Below that,
  a long wait spends the repository's API quota, and a fetch that hits the
  limit reads as no review. Found by the pre-1.0
  external review.
- `floor-check` compares which app each required check must come from, not
  only its name. The ruleset the generator raises pins every required check
  to GitHub Actions. A live rule that lost that pin can be satisfied by a
  commit status of the same name, which anyone with write access can post.
  `floor-check` reported such a rule as healthy ("all 9 expected checks are
  required"). Now it fails, naming the check, as it does for a check pinned to
  another app. Without `--ruleset` there is no expected app, so the comparison
  is reported as not made. It also reads every active required-checks rule,
  not only the last one: GitHub enforces each, so a check is required when
  any ruleset requires it and pinned when any pins it, and the branch must
  be current when any of them is strict. Before, a second
  ruleset gave a false "dropped", and would have given a false "any source".
  Found by the pre-1.0 external review.
- `docs/how-to/run-a-project.md` no longer says a plain-words request for a
  typed skill "gets the work done by hand". The agent may do it without the
  skill's safeguards, or not at all. The page now names each skill's own
  safeguards: rollback for `new-project`, confirmations and a separate
  worktree for `template-update`. And agreed words go
  into `CONTEXT.md`, while a decision that is hard to reverse, surprising
  without context and a real trade-off goes under `docs/adr/`,
  not one file for both. Both are from the reviewer's last round on #306.
- The generated `AGENTS.md` has told the agent, since the template was
  rebuilt, to report "in the five-item shape plinth's guidance defines
  (`/plinth:arsenal`)". The arsenal never defined it. It does now, from #68's
  design: at four moments, five items.
- The tutorial said nobody can push past the checks; it now says nothing
  merges past them, including your own merge.
- `NOTICE` now carries each third-party plugin's copyright line and the MIT
  permission text. MIT asks that both travel with every copy. `ponytail-skills`
  is mounted from the upstream `skills/` folder, which has no LICENSE file,
  so an installed copy carried neither; `NOTICE` had named only the licence
  and the commit. Each licence was read on 2026-09-27, at the pinned commit
  or, for the two plinth does not pin, at a commit `NOTICE` names:
  MIT for taste-skill, last30days, ponytail and mattpocock-skills, and
  Apache-2.0 for Impeccable, which plinth lists and does not install. plinth
  copies none of their code.

### Changed

- `/plinth:new-project` renders plinth-template v1.5.8. A repository it creates
  now calls plinth's reusable workflows at `2673947`, which carries this
  release's checker fixes, instead of a commit from 2026-09-11. With the old
  default a new repository's `ci / floor-check` would have run the old
  checker, which misses a removed source pin, until Dependabot raised the
  pin. From the second pre-1.0 review. `/plinth:floor-check` now reports a
  repository on v1.5.7 as one tag behind.
- `/plinth:new-project` renders plinth-template v1.5.7. Its only change: the
  generated `.claude/settings.json` denies `gh repo delete`, and `AGENTS.md`
  names it among what the settings deny. The recommended login can delete any
  repository the person owns, and no required check can undo that. From the
  pre-1.0 review. `/plinth:floor-check` now reports a repository on v1.5.6 as
  one tag behind.
- `/plinth:new-project` renders plinth-template v1.5.6. Its only change: the
  generated `AGENTS.md` says that Claude Code's automatic memory stays on the
  machine it ran on, so a decision, an unverified item or a next step the
  next person needs goes into the issue or pull request, not only into memory.
  It is the one improvement from the 2026-09-27 trends review taken before
  v1.0.0; the rest are #299–#304. `/plinth:floor-check` now reports a
  repository on v1.5.5 as one tag behind.

- The README and the glossary say what plinth can and cannot claim, as three
  reviewers read them before v1.0.0 (#65). The first paragraph names the user
  (someone who directs an AI agent and does not read the diff) and the limit:
  a green check means its asserted properties hold, not that the code is
  right. "Nobody can push past" now reads "nothing merges past", with who can
  still change the rules: anyone whose token has administration, an agent
  included after the browser login. The dependency list no longer says every
  dependency is pinned to a commit: `mattpocock-skills` arrives at whatever
  version the official marketplace serves, and CI checks it against the
  tested range. The generator no longer "creates nothing" on failure. When a
  step that setup cannot go on without fails, it deletes what it created if
  its token can, and names the repository if it cannot. A step it can go on
  without, such as a label, is named and left. When the create's own answer
  is lost, it does neither. The Status paragraph was about the 0.5.1 baseline
  of 2026-09-09. It now describes the release gate and the release-candidate
  runs, and says no one but the author has used plinth yet. `CONTEXT.md` no
  longer says the default install has no hooks: `last30days` adds one.

## [0.5.31] - 2026-09-26

The last changes before v1.0.0 that the owner chose to land first. The
Claude Code floor rises to 2.1.274, the stable channel's release, and CI now
installs plinth on it; the e2e gate runs the same release. The e2e driver
stops at the token's user lookup when GitHub refuses the token, instead of
naming a repository that never existed. A repository `/plinth:new-project`
creates tells its agent to answer in the language the person writes in, and
that a closing word before an issue number in a sentence closes that issue
(plinth-template v1.5.5).

tested with plinth-template v1.5.5

### Changed

- `/plinth:new-project` renders plinth-template v1.5.5. The generated
  `AGENTS.md` and the `non-engineer` output style say to answer the person in
  the language they write in, summaries included, while code, commits, pull
  requests and documents follow the repository's convention
  (coolbress/plinth-template#30, from #65's first release-candidate run). Its
  `CONTRIBUTING.md` step 5, `AGENTS.md` and pull request template say that a
  close, fix or resolve word before an issue number anywhere in the
  description closes that issue. `/plinth:floor-check` now reports a
  repository on v1.5.4 as one tag behind.

- The Claude Code floor rises from 2.1.234 to 2.1.274, and it is now checked.
  2.1.234 had been set by a feature, not by a run: the settings the template
  ships were measured on 2.1.267 and 2.1.278, and the user tasks ran on
  2.1.282 and 2.1.283. 2.1.274 is the stable channel's release on 2026-09-26,
  so a person on that channel is not stopped. `ci / install` now installs
  plinth the README's way a second time on the floor itself. The floor has one
  source, `scripts/new-project.sh`: the install test fails when the README or
  the tutorial states another, or when `e2e.yml` pins a release below it. The
  e2e pin moves from 2.1.236 to 2.1.274, with its SHA256 from the release
  manifest (#65).

### Fixed

- `scripts/e2e.sh` stops at the token's user lookup, saying the token is
  refused, when GitHub rejects the token. Before, `gh` printed its error body
  where the user was read. The lookup's failure was lost, and the run went on
  with an empty owner. It ended in a loud line saying to delete a repository
  that never existed. An answer without a numeric id or a login now counts as
  a failed lookup too (#288).

## [0.5.30] - 2026-09-26

The findings from the second v1.0.0 release-candidate pass (RC2). A
repository `/plinth:new-project` creates tells its agent that `Assisted-by`
is the only line that marks AI, and to remove a tool's default
`Co-Authored-By` and generated-with line (plinth-template v1.5.4); whether an
agent follows it is not yet observed. When the generator stops for a token set
in the environment, it names `~/.zshenv` as a place the token may come from,
alongside `~/.zshrc` and `~/.bashrc`.

tested with plinth-template v1.5.4

### Changed

- `/plinth:new-project` renders plinth-template v1.5.4. Its only change: the
  generated `CONTRIBUTING.md`, `AGENTS.md` and pull request template say
  `Assisted-by` is the only line that marks AI, so a tool's default
  `Co-Authored-By` and generated-with line are removed while a person's
  trailers stay (coolbress/plinth-template#34, from #65's second
  release-candidate pass). `/plinth:floor-check` now reports a repository on
  v1.5.3 as one tag behind.

### Fixed

- When `GH_TOKEN` or `GITHUB_TOKEN` is set, `/plinth:new-project`'s stop and
  the tutorial name `~/.zshenv` next to `~/.zshrc` and `~/.bashrc` as where the
  variable may come from. Every zsh reads it, Claude Code's own shell included,
  so a token left there stays after it is removed from `~/.zshrc` (from #65's
  second release-candidate pass).

## [0.5.29] - 2026-09-26

The fixes from the v1.0.0 release-candidate run. The README's install block
now works on its own in a fresh Claude Code configuration, where before it
left plinth failing to load. A repository `/plinth:new-project` creates tells
its agent to merge only when the person says so for that pull request, with
the command that keeps the description as the commit, and to check a
worktree before removing it (plinth-template v1.5.3). When `gh` holds a
fine-grained token, the generator's stop links a pre-filled token form and
says how the browser login stays inside Claude Code.

tested with plinth-template v1.5.3

### Changed

- When `gh` holds a fine-grained token, `/plinth:new-project`'s stop now
  prints a link to GitHub's fine-grained token form, pre-filled for the owner
  with the permissions the door needs (`members` too, for an organization) and
  a 7-day expiry. The one choice left on the form is "All repositories", and
  the stop names it. Before, the stop listed the permissions to pick by hand.
  When `GH_TOKEN` or `GITHUB_TOKEN` is set, the stop also says the variable
  usually comes from a shell startup file. Once it is removed there and Claude
  Code is restarted, the browser login and the generator stay inside Claude
  Code, with no terminal switch. The tutorial and README say the same. From
  the v1.0.0 release-candidate run (#285).

- `/plinth:new-project` renders plinth-template v1.5.3. Its only change: the
  generated `AGENTS.md` says the agent merges only when the person says so
  for that pull request, with `CONTRIBUTING.md` step 7's command, and checks
  a worktree for ignored files before removing it; step 7 says who decides
  (coolbress/plinth-template#31, from the v1.0.0 release-candidate run).
  `/plinth:floor-check` now reports a repository on v1.5.2 as one tag behind.

### Fixed

- The README's install block now works on its own in a fresh Claude Code
  configuration. It was two lines, and run as written before Claude Code's
  first interactive run it left plinth failing to load: `mattpocock-skills`
  lives in Anthropic's official marketplace, which such a configuration does
  not have yet. The block now adds that marketplace first. Where it is already
  added, the line only says so and exits 0. `tests/install-smoke.sh` runs the
  block exactly as written; it used to add the official marketplace itself
  first, which hid this. Found in the v1.0.0 release-candidate run (#282).

## [0.5.28] - 2026-09-25

A repository `/plinth:new-project` creates now sends a reader who wants to
know what a check does, or why it is red, to plinth's Required checks page:
plinth-template v1.5.2 puts that link at the top of the generated `ci.yml`,
where it used to point at the reusable workflow's source.

tested with plinth-template v1.5.2

### Changed

- `/plinth:new-project` renders plinth-template v1.5.2. Its only change: the
  generated `ci.yml` points a reader who wants to know what a check does, or
  why it is red, at plinth's [Required checks](docs/reference/required-checks.md)
  page instead of `python-ci.yml` (coolbress/plinth-template#27).
  `/plinth:floor-check` now reports a repository on v1.5.1 as one tag behind.

## [0.5.27] - 2026-09-25

plinth now has the pages a reader needs besides the tutorial: every check
the wall requires with what a red means and the fix, why plinth is shaped
the way it is, and how a maintainer cuts a release or raises the template
pin. Also in this release, `/plinth:template-update` no longer stops on a
`.rej` file or a quoted conflict marker the repository already had, and
takes over only its own pull request.

tested with plinth-template v1.5.1

### Added

- Four documentation pages: [Required checks](docs/reference/required-checks.md),
  each check the wall requires with what it asserts, what a red means and the
  fix, held to `ruleset.json` by `tests/required-checks-doc.sh`;
  [Concepts](docs/explanation/concepts.md), why plinth is shaped the way it
  is; and two maintainer how-tos,
  [cut a release](docs/how-to/cut-a-release.md) (moved from `CONTRIBUTING.md`)
  and [upgrade the template pin](docs/how-to/upgrade-the-template-pin.md).
  README, `CONTEXT.md` and `AGENTS.md` link to them instead of repeating the
  check list. The concepts page names the one dependency not pinned by SHA,
  `mattpocock-skills`, which comes from Anthropic's official marketplace
  within the 1.2.3 to below 2.0.0 range the install test checks. The release
  how-to says what to do when `gh workflow run e2e.yml` answers HTTP 403: run
  it through `scripts/with-admin-token.sh` in a separate terminal.

### Fixed

- `/plinth:new-project --private` pointed to a page that did not exist; it
  now links to the private-repository section of the concepts page.
- `/plinth:template-update` takes an open pull request already on its
  branch as its own only when that pull request's head is this repository
  at the commit it just pushed. Before, a fork's pull request from a branch
  of the same name could be recorded in its place, leaving the update with
  no pull request. Otherwise it opens its own.
- `/plinth:template-update` counts a `.rej` file or a conflict-marker line
  as a conflict only in files the update changed. A `.rej` fixture or a
  document quoting a marker that the repository already had no longer stops
  every run. Unmerged paths still stop it wherever they are, and so does
  an untracked `.rej` in the new worktree, even one `.gitignore` ignores.

## [0.5.26] - 2026-09-25

A repository `/plinth:new-project` made from an older template can now be
brought up to the template plinth is tested with, as a draft pull request:
`/plinth:template-update` runs the `copier update` line
`/plinth:floor-check` prints, in a worktree beside the repository, after
you have read its plan and said yes, and leaves any conflict for you to
resolve before anything is pushed. `/plinth:floor-check`'s printed line
gains `--defaults` so that it runs without a terminal. Also in this release,
the door's hint after a failed first push follows git's error, so a GitHub
server error no longer blames the token.

Known limits of the new skill, filed as #274: an open pull request from a
fork with the same branch name could be taken for the update's own, and a
`.rej` file or a marker-like line already committed reads as a conflict.

tested with plinth-template v1.5.1

### Added

- `/plinth:template-update` applies the template update `/plinth:floor-check`
  reports. It prints a plan first and writes nothing until you say yes. Then it
  runs the checker's own `copier update` line in a new worktree beside the
  repository, branched from the default branch after checking that branch
  against GitHub, and opens a draft pull request. The description lists what
  merged cleanly and what a person resolved. A conflict stops it before
  anything is pushed, left in the worktree for you to resolve; it never picks
  a side. It never pushes to the default branch and does not wait for the
  pull request's checks.

### Changed

- The `copier update` line in `/plinth:floor-check`'s template drift item
  now carries `--defaults`. Without it, copier stops when there is no
  terminal to ask its questions in. With it, each question takes the answer
  the repository recorded, or the template's default for one it never
  recorded.

### Fixed

- When `/plinth:new-project` cannot push the new repository's first commit,
  its hint now follows git's error. A GitHub server error (`Internal Server
  Error`, an HTTP 5xx) says GitHub failed, not the token, and to run the door
  again; an authentication or permission refusal keeps the token hint; any
  other error prints both as possibilities. The rollback that deletes the new
  repository is unchanged.

## [0.5.25] - 2026-09-24

A repository `/plinth:new-project` creates now tells its contributors how to
merge so that a pull request's description lands on `main` as written:
plinth-template v1.5.1 carries the squash merge command into the generated
`CONTRIBUTING.md`, where GitHub's default would hard-wrap the description at
72 columns. Also in this release, plinth checks the tools it runs on itself
more closely: its own Python is linted and type-checked, and zizmor, ruff
and mypy install only from files whose hashes this repository lists.

tested with plinth-template v1.5.1

### Changed

- `/plinth:new-project` renders plinth-template v1.5.1. Its only change: the
  generated `CONTRIBUTING.md` gives the squash merge command that keeps a pull
  request's description as its commit, instead of GitHub's default, which
  hard-wraps it at 72 columns (coolbress/plinth-template#24, the template's
  copy of #250). `/plinth:floor-check` now reports a repository on v1.5.0 as
  one tag behind.
- zizmor, ruff and mypy, the Python tools `ci / tools` runs, install from a
  hash-locked `tests/lint-tools.txt` (with their dependencies) into a venv,
  with `pip install --require-hashes --only-binary=:all:`. They ran through
  `pipx run` or `uvx` before, pinned by version only, so a changed artifact
  would have run unnoticed. A file whose hash is not listed now stops the
  step. The pins move to `tests/lint-tools.in`; `CONTRIBUTING.md` says how to
  raise one (#264).
- plinth's own CI lints and type-checks the Python it ships into consumers'
  CI: `scripts/floor-check.py` and the pr-review judgement scripts.
  `tests/python-lint.sh` runs ruff 0.16.8 and mypy 2.3.1 with their defaults
  in `ci / tools`, mypy checking against Python 3.10. The 31 ruff findings
  and 4 mypy errors it found are fixed without changing behaviour: regex flag
  names spelled out (`re.IGNORECASE` for `re.I`), imports sorted,
  `check=False` written where it was already the default, one `startswith`
  given a tuple instead of two calls, redundant parentheses and an unused
  `noqa` removed, a variable in `attest.py` renamed so it holds one type, and
  two `cast`s for values mypy could not narrow (#261).

## [0.5.24] - 2026-09-24

This release changes how `third-party / review` gets the scripts that
decide its result. A repository that pins `pr-review.yml` to this
release's commit now downloads four scripts from
`raw.githubusercontent.com` at that same commit. Before, the scripts were
written inline in the workflow. What the check decides is unchanged. A
runner that cannot reach that host fails the check at the new step,
rather than passing. The other two changes restructure
`/plinth:new-project`'s script. It reaches the same decisions, but when the
owner has a public `.github` repository it now reads all three
pull-request template paths and every file in its issue-template folder
before deciding, where it used to stop at the first match and skip
non-template files. That is one more API call per extra file, per run.

tested with plinth-template v1.5.0

### Changed

- `third-party / review` (`pr-review.yml`) now fetches its four judgement
  scripts from `raw.githubusercontent.com/coolbress/plinth` at the commit the
  caller's `uses:` line resolved to (`job.workflow_sha`), in a new step
  before the check, instead of carrying them inline. What they decide is
  unchanged. A runner that cannot reach that host now fails the check at
  that step (#234).

## [0.5.23] - 2026-09-24

Installing plinth now tells you what it costs a session. The default set
runs one hook, `last30days`'s `SessionStart` check, and its skills fill
part of Claude Code's skill listing, which is capped at 1% of the model's
context window. On a 1M-context model all of the default set's
descriptions fit. On the two 200k models measured on a fresh install,
most of them are cut to the skill's name. Adding a dependency that ships a hook
is now something to ask about first. Also in this release: the
contributing guide gives the squash merge command that keeps a pull
request's description as its commit.

tested with plinth-template v1.5.0

### Changed

- The README and `/plinth:arsenal` no longer say the default set's skill
  listing is over a fixed ~2,000-token budget. Claude Code's cap is 1% of the
  model's context window, built-in skills included. Measured with `/context`
  on a fresh install (#255): with a 1M-context model all 33 listed skills
  keep their descriptions; with the two 200k-context models measured
  (Haiku 4.5, Sonnet 4.5) the listing is cut to about 2,000 tokens and 25
  of the 33 keep only their name. The per-plugin figures in
  `/plinth:arsenal` are now these live readings. The earlier estimate
  counted every `SKILL.md` on disk, including skills Claude Code never
  lists: mattpocock-skills' files outside its manifest's `skills` list, and
  its 14 marked `disable-model-invocation`.
- `CONTRIBUTING.md` step 5 gives the merge command that makes the squash
  commit the pull request description: `gh pr merge --squash` with the
  description passed as `--body`. Without it GitHub's default squash
  message is the description hard-wrapped at 72 columns, so a description
  written at about 80 columns landed on `main` with stray one-word lines.
  `AGENTS.md`'s "becomes the squash commit" points at that step.
- The README's install section, `/plinth:arsenal` and the marketplace
  descriptions say what the default set costs a session: `last30days` runs
  a `SessionStart` hook, and its skills take up part of Claude Code's
  skill listing (measured in the first entry above). `AGENTS.md`'s
  Ask-first rule on hooks now covers adding a dependency, or raising its
  pin, when that version ships a hook.

## [0.5.22] - 2026-09-24

`/plinth:floor-check` stopped giving advice it could not stand behind. It
told everyone to run `/sandbox`, reading a setting `/sandbox` does not write,
and on macOS the sandbox stops `gh` and the generator's copier step. The
sandbox item now says what was measured and where, and no longer calls the
sandbox off. Also in this release: the floor-check skill writes a finding's
fix from the lines the checker indents under it.

tested with plinth-template v1.5.0

### Changed

- `/plinth:floor-check` writes the fix line for a FAIL or WARN from the `INFO`
  lines indented under it. The checker puts a finding's repair there — among
  others the `--project` guidance when several directories below the root hold
  a `pyproject.toml`, `git rm --cached`, the action-pin lookups,
  `copier update`, the JSON-log hint, `gh label create`, the ruleset and
  default-branch fixes and the CodeQL language patch — but the skill told
  the agent to leave every `INFO` alone, so its fix line could miss the one
  actionable text. An `INFO` at the normal indent is still a fact to leave
  where it is.
- `floor-check --sandbox` no longer reports the sandbox off and tells you to
  run `/sandbox`. It read `sandbox.enabled`, which `/sandbox` on Claude Code
  2.1.278 does not write, so an unset key is now `SKIP  sandbox not verified`,
  and `sandbox.enabled: true` is an `INFO`, no longer a PASS. The lines under
  either say what was measured on macOS (#222): off, a `bash -c` or a script
  can still read `.env`; on, `gh` stops working because the sandbox enforces
  the floor's `Read(~/.config/gh/**)` deny against it, which no repository
  setting can fix (anthropics/claude-code#95135, #67105), and
  `/plinth:new-project` stops at its `uvx` copier step. Linux, WSL2 and
  native Windows are marked not measured. The floor-check skill, the README
  and the getting-started tutorial say the same, and `/plinth:new-project`
  drops its `sandbox is off; run /sandbox` warning, which read the same key
  and, on macOS, pointed at a setting that stops the script's own copier
  step.

## [0.5.21] - 2026-09-23

The generator's own setup step led every new reader to a stop: the
tutorial's `gh auth login` gives default scopes, which lack `workflow`. The
login step now carries the scopes and says it runs inside a Claude Code
session, and the fine-grained stop names the browser login beside the
admin-token path. Also in this release: `/plinth:floor-check` checks the wall
again under zsh.

tested with plinth-template v1.5.0

### Changed

- `AGENTS.md` says that closing an issue writes its ending into the body —
  `## Outcome`, naming which of completed, cancelled, superseded or moved to a
  follow-up it is. The rule was already in `docs/agents/issue-tracker.md` and
  in all three issue forms, but both are read when an issue is *opened*, and
  `Closes #N` closes one through GitHub without asking anyone, so nothing
  raised it at the moment it applies. Measured across every closed issue in
  this tracker on 2026-09-23: 63 of 86 had an ending, 23 did not. Research
  records are not in that count — their ending is `## Decision`, and 17 of 18
  have one. Nothing about the product changes.

  `docs/agents/issue-tracker.md`'s wayfinder **Resolve** step asked for
  `## Findings`, `## Decision` *and* `## Outcome`, which contradicts the shape
  the same file's table gives a record two sections earlier. It now matches the
  table. No record has ever carried both: all 17 closed research and grilling
  records use `## Question` / `## Findings` / `## Decision`, none has an
  `## Outcome`, and the only two issues of that family that do are a map and a
  spec. Resolve serves four child kinds, so it now branches: a `research`,
  `prototype` or `grilling` child ends in `## Decision`, a `task` child in
  `## Outcome` like any other task.

### Fixed

- The getting-started tutorial's login step no longer leads to a stop. It
  said `gh auth login`, whose default scopes lack `workflow`, so a reader who
  followed it met the scope stop on the first run. It now reads
  `gh auth login -s repo,workflow,delete_repo`, says what `delete_repo` buys,
  and says the command runs inside a Claude Code session: it prints a
  one-time code and a URL, and a browser finishes it. The scope stop's
  `gh auth refresh` fix says the same (#228).
- The generator's fine-grained-token stop names two fixes instead of one:
  the browser login above, after which the generator runs wherever it is
  started, or the admin-token path in a separate terminal. The browser login
  is shorter, but its token is scoped `repo` across the account rather than
  to selected repositories; the admin-token path keeps the fine-grained
  token's narrow reach. `README.md` and the tutorial say the same (#228).
- With `GH_TOKEN` or `GITHUB_TOKEN` set, both stops first say to unset it,
  because `gh` uses it before any login it stores; and the scope stop adds
  that with no login of `gh`'s own left, `gh auth login` replaces the
  refresh (#228, #246).

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

[Unreleased]: https://github.com/coolbress/plinth/compare/v1.7.5...HEAD
[1.7.5]: https://github.com/coolbress/plinth/releases/tag/v1.7.5
[1.7.4]: https://github.com/coolbress/plinth/releases/tag/v1.7.4
[1.7.3]: https://github.com/coolbress/plinth/releases/tag/v1.7.3
[1.7.2]: https://github.com/coolbress/plinth/releases/tag/v1.7.2
[1.7.1]: https://github.com/coolbress/plinth/releases/tag/v1.7.1
[1.7.0]: https://github.com/coolbress/plinth/releases/tag/v1.7.0
[1.6.0]: https://github.com/coolbress/plinth/releases/tag/v1.6.0
[1.5.0]: https://github.com/coolbress/plinth/releases/tag/v1.5.0
[1.4.0]: https://github.com/coolbress/plinth/releases/tag/v1.4.0
[1.3.0]: https://github.com/coolbress/plinth/releases/tag/v1.3.0
[1.2.1]: https://github.com/coolbress/plinth/releases/tag/v1.2.1
[1.2.0]: https://github.com/coolbress/plinth/releases/tag/v1.2.0
[1.1.1]: https://github.com/coolbress/plinth/releases/tag/v1.1.1
[1.1.0]: https://github.com/coolbress/plinth/releases/tag/v1.1.0
[1.0.0]: https://github.com/coolbress/plinth/releases/tag/v1.0.0
[0.5.31]: https://github.com/coolbress/plinth/releases/tag/v0.5.31
[0.5.30]: https://github.com/coolbress/plinth/releases/tag/v0.5.30
[0.5.29]: https://github.com/coolbress/plinth/releases/tag/v0.5.29
[0.5.28]: https://github.com/coolbress/plinth/releases/tag/v0.5.28
[0.5.27]: https://github.com/coolbress/plinth/releases/tag/v0.5.27
[0.5.26]: https://github.com/coolbress/plinth/releases/tag/v0.5.26
[0.5.25]: https://github.com/coolbress/plinth/releases/tag/v0.5.25
[0.5.24]: https://github.com/coolbress/plinth/releases/tag/v0.5.24
[0.5.23]: https://github.com/coolbress/plinth/releases/tag/v0.5.23
[0.5.22]: https://github.com/coolbress/plinth/releases/tag/v0.5.22
[0.5.21]: https://github.com/coolbress/plinth/releases/tag/v0.5.21
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
