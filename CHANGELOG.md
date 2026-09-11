# Changelog

All notable changes to plinth. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). A version is a
`vX.Y.Z` tag on `main` plus a GitHub Release whose notes say why it exists and
which template tag it was tested with; `scripts/make-release.sh` cuts one, and
the version number moves only there. Numbers before the first tag were bumped
inside pull requests and have no tag.

## [Unreleased]

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
