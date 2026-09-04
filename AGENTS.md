# Working in this repository

plinth is a Claude Code plugin plus its marketplace. Installers add the
marketplace and install `plinth@plinth`; that must keep working on a clean
machine. `CLAUDE.md` is a symlink to this file.

## Checks

```bash
claude plugin validate --strict .                           # marketplace
claude plugin validate --strict .claude-plugin/plugin.json  # plugin manifest
claude plugin validate --strict skills                      # skill frontmatter
./tests/marketplace-manifest.sh          # pins, dependencies, skill frontmatter
./tests/de-jargon.sh                     # no internal vocabulary in public text
./tests/readme-install-block.sh          # README install block == tutorial block
./tests/all-tests-are-wired.sh           # every tests/*.sh runs in CI
./tests/install-smoke.sh                 # real install into a temp config dir (network)
```

## Always

- Bump `version` in `.claude-plugin/plugin.json` when the plugin changes.
  Installed copies are cached by version; a stale number ships nothing.
- Pin every third-party marketplace entry to a full commit SHA. Raising a pin
  is a pull request.
- Keep the caller job named `ci` in `.github/workflows/ci.yml`. Check names are
  `ci / <job>` and rulesets require them by name.
- Never skip a job with `if:`. Report a pass instead; a skipped job has no
  check name.
- Product text is English. `.ko.md` translations are optional and never
  canonical.
- A commit made with AI carries `Assisted-by: <agent>:<model>` (the Linux kernel's
  form, e.g. `Assisted-by: Claude:claude-fable-5-1`). AI is never a `Co-Authored-By`
  and adds no session trailer or link; the person who merges answers for every line.

## Ask first

- Adding a dependency to `plugin.json`: it installs on every user's machine.
- Adding a hook anywhere in the default plugin. Hooks live in the opt-in profile.

## Never

- Push to `main` directly or merge with `--admin`.
- Point a skill at anything outside `${CLAUDE_PLUGIN_ROOT}`; the plugin root is
  this repository.

## Next move

- New repository: `/plinth:new-project <owner>/<name>`. Existing one:
  `/plinth:floor-check`.
- Choosing a tool: `/plinth:arsenal`. The planning-to-review flow: `/ask-matt`.
- Next ticket: `gh issue list --label ready-for-agent`, then `/implement #N`.

## Agent skills

- Issue tracker: GitHub Issues on `coolbress/plinth`, via `gh`. See
  [docs/agents/issue-tracker.md](docs/agents/issue-tracker.md).
- Triage labels: see [docs/agents/triage-labels.md](docs/agents/triage-labels.md).
- Domain docs: root `CONTEXT.md` and `docs/adr/`. See
  [docs/agents/domain.md](docs/agents/domain.md).
