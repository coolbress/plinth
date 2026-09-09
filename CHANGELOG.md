# Changelog

All notable changes to plinth. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). A version is a
`vX.Y.Z` tag on `main` plus a GitHub Release whose notes say why it exists and
which template tag it was tested with; `scripts/make-release.sh` cuts one, and
the version number moves only there. Numbers before the first tag were bumped
inside pull requests and have no tag.

## [Unreleased]

### Added

- Tier 2, the real repository journey: `scripts/e2e.sh` runs the door against
  GitHub (create, render, `main`, labels, CodeQL, ruleset, the first pull
  request), reads the wall back with the floor checker, waits for every check
  to be green, squash-merges, reads `main` back, and deletes the repository.
  Its first act is to create and delete a sibling name, `<name>-probe`, so
  a token that can create but not delete stops before anything is left behind;
  a repository it could not delete is named on stderr and in the job summary,
  and the exit is 1. When CodeQL has not picked the first pull request up
  after a fifth of the wait, it pushes the door's recovery commit once (the
  door's own advice; measured necessary on 2026-09-09, #117).
  `.github/workflows/e2e.yml` runs it nightly and on demand from the secret
  `PLINTH_E2E_TOKEN`; an absent secret is red, not a pass.
  `tests/e2e-driver.sh` holds its failure paths against a mocked `gh`.

### Fixed

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
