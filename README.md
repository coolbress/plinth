# plinth

The base a vibe-coded project stands on: required checks on GitHub that nobody
can push past, a curated set of agent skills, and a generator that starts a new
repository with both already in place.

> **Supported:** GitHub.com public repositories · personal or org owner with
> admin · Python (uv) · new repositories via `/plinth:new-project`; existing
> ones get a read-only `floor-check` · **Claude Code 2.1.234 or newer** as the
> host (skills follow the Agent Skills format and may load elsewhere, but only
> Claude Code is tested) · macOS / Linux (Windows via WSL) · tools: `claude`,
> `gh`, `git` (2.37 or newer: on an older one, the macOS system git included, the
> install fails with `index.lock: File exists`; `brew install git`), `uv`.
>
> **Outside:** when a wall cannot be raised (no admin, private repository, no
> `gh` auth) the tool stops before creating anything and says why. Private
> repositories need a GitHub Code Security license for CodeQL, so it points to
> public first, GitLab Free as the documented alternative, and a lower private
> wall as a later option. Other mismatches warn and continue.

## Install

<!-- install-block:start -->
```bash
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin marketplace add coolbress/plinth
claude plugin install plinth@plinth
```
<!-- install-block:end -->

The first line adds Anthropic's official marketplace, where one dependency
lives. A fresh configuration does not have it until Claude Code's first
interactive run, and without it plinth fails to load. Where it is already
added, the line only says so.

The default set runs one hook: `last30days` adds a `SessionStart` hook
(about 0.4 s) that checks its own configuration. Its skills cost context too.
Claude Code lists 33 of them for the model and caps the whole skill listing,
its own built-in skills included, at 1% of the model's context window. As
`/context` estimates it on a fresh install, with a 1M-context model all 33
keep their descriptions, about 3,750 tokens. With the two 200k-context models
measured (Haiku 4.5, Sonnet 4.5) the listing is cut to about 2,000 tokens and
25 of the 33 keep only their name: they still run when called by name, but
Claude is less likely to pick them on its own. The
`skillListingBudgetFraction` setting raises the cap (#255).

Third-party marketplaces do not auto-update. To move to a new version, run
`claude plugin update plinth`, then `/reload-plugins`.

Tutorial: [Getting started](docs/tutorials/getting-started.md).

## What you get

Four skills, prefixed `/plinth:`:

| Skill | Does | Who can call it |
| --- | --- | --- |
| `new-project <owner>/<name>` | Creates a repository with the required checks enforced; if a wall step fails it deletes the repository when the token allows and prints the URL when it cannot | You only: type `/` and pick it. The agent cannot see or run it; an agent saying it is not installed usually means the line was typed as text (`/plinth:arsenal` shows what is installed) |
| `floor-check [owner/name]` | Reads an existing repository against the same floor the CI job checks, the live ruleset, whether it is behind the template plinth is tested with today, and what this machine's Claude Code settings say about the sandbox; lists each miss with one fix; changes nothing | You or the agent |
| `template-update` | Applies the template update `floor-check` reports: runs its `copier update` line in a worktree beside the repository, branched from the verified default branch, and opens a draft pull request; a conflict is left for you to resolve before anything is pushed | You only, and it asks before it writes |
| `arsenal` | Catalog of the tools below: what, when, cost | You or the agent |

Installed with plinth as dependencies, each pinned to a commit:
[mattpocock-skills](https://github.com/mattpocock/skills) (planning to review),
[taste-skill](https://github.com/Leonxlnx/taste-skill) (frontend design that
does not look templated),
[last30days](https://github.com/mvanhorn/last30days-skill) and
[ponytail-skills](https://github.com/DietrichGebert/ponytail) (the ponytail
skills without its hooks). Listed but not installed: `ponytail`, the full
plugin with hooks, and [Impeccable](https://github.com/pbakaus/impeccable),
whose installer writes hooks, agents and skills into the repository. Run
`/plinth:arsenal` for the catalog; licenses are in [NOTICE](NOTICE).

Nothing in the plugin enforces anything. Enforcement is the ruleset on GitHub,
which `/plinth:new-project` raises and which owners cannot bypass; anyone
holding administration can still edit it
([About who can change the wall](docs/explanation/concepts.md#about-who-can-change-the-wall)).
When `gh` holds a fine-grained token, the generator stops and names two
fixes. The browser login is shorter, but its token is scoped `repo` across the
account rather than to selected repositories; the admin-token path keeps the
fine-grained token's narrow reach. The first is
`gh auth login -s repo,workflow,delete_repo`, which runs inside Claude Code
(a one-time code and a URL, finished in a browser), after which the generator
runs wherever it is started. Unset `GH_TOKEN` and `GITHUB_TOKEN` first if
either is set: `gh` uses them before any login it stores. The second is to rerun it through
`scripts/with-admin-token.sh` in a separate terminal, which prompts for an
admin token there and keeps it off every command line.

## Status

The install works end to end and CI proves it on a clean runner. `new-project`
creates a repository with the wall up, or creates nothing (its failure paths
run in CI against a mocked `gh`). It renders
[plinth-template v1.5.2](https://github.com/coolbress/plinth-template/releases/tag/v1.5.2),
whose CI reports every check the wall requires. In both live journeys so far
(the v0.5.1 baseline by hand and one green `e2e` run on a runner, #62,
2026-09-09) the first pull request merged, but only after the recovery commit
the door prints: CodeQL did not analyse the pull request on its first push
(#117). What each required check asserts, what a red means and its fix,
CodeQL on a head Dependabot pushed included (#179), is in
[Required checks](docs/reference/required-checks.md). `floor-check` runs the checker `ci / floor-check` runs, read-only;
exit 0 means no FAIL in what it could read, and its summary counts what it
could not. A third-party review check (`third-party / review`, Codex) is
available as an optional check; see
[docs/how-to/configure-the-third-party-reviewer.md](docs/how-to/configure-the-third-party-reviewer.md).
The [CHANGELOG](CHANGELOG.md) lists what each version adds.

## Further reading

- [Concepts](docs/explanation/concepts.md): why plinth is shaped the way it is.
- How-to, for maintainers: [cut a release](docs/how-to/cut-a-release.md),
  [upgrade the template pin](docs/how-to/upgrade-the-template-pin.md).
- [CONTEXT.md](CONTEXT.md): the vocabulary (wall, door, box, floor, arsenal, lab, profile).
- [plinth-lab](https://github.com/coolbress/plinth-lab): the evidence behind the rules. Optional.

Rebuilt in September 2026 from an earlier internal repository; its issues and
decisions moved here (the map is #15, the spec #31).
