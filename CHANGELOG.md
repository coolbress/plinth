# Changelog

All notable changes to plinth. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

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
  render the template at the tested tag (`coolbress/project-template@v2.18.0`),
  push `main`, labels, CodeQL, the ruleset, secret scanning, Dependabot,
  Actions allowlist (`coolbress/plinth/*`, SHA pins required), squash only, and
  the first pull request, whose workflow must start; CodeQL is waited for too
  (default setup must register its workflow before the push, and if CodeQL
  still misses the pull request the summary names the re-push). Any failure after creation
  deletes the repository (best effort: a failed deletion prints the URL loudly).
  `scripts/with-admin-token.sh` for machines whose `gh` token is fine-grained.
  Tests: `tests/new-project-failpath.sh` (mocked `gh`, 57 cases) and
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
