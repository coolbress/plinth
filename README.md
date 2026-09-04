# plinth

The base a vibe-coded project stands on: required checks on GitHub that nobody
can push past, a curated set of agent skills, and a generator that starts a new
repository with both already in place.

> **Supported:** GitHub.com public repositories · personal or org owner with
> admin · Python (uv) · new repositories via `/plinth:new-project`; existing
> ones get a read-only `floor-check` · **Claude Code 2.1.234 or newer** as the
> host (skills follow the Agent Skills format and may load elsewhere, but only
> Claude Code is tested) · macOS / Linux (Windows via WSL) · tools: `claude`,
> `gh`, `git`, `uv`.
>
> **Outside:** when a wall cannot be raised (no admin, private repository, no
> `gh` auth) the tool stops before creating anything and says why. Private
> repositories need a GitHub Code Security license for CodeQL, so it points to
> public first, GitLab Free as the documented alternative, and a lower private
> wall as a later option. Other mismatches warn and continue.

## Install

<!-- install-block:start -->
```bash
claude plugin marketplace add coolbress/plinth
claude plugin install plinth@plinth
```
<!-- install-block:end -->

On a clean or CI machine, run `claude plugin marketplace add anthropics/claude-plugins-official`
first. One dependency lives there, and Claude Code registers that marketplace on
its own only during an interactive first run.

Third-party marketplaces do not auto-update. To move to a new version, run
`claude plugin update plinth`, then `/reload-plugins`.

Tutorial: [Getting started](docs/tutorials/getting-started.md).

## What you get

Three skills, prefixed `/plinth:`:

| Skill | Does | Who can call it |
| --- | --- | --- |
| `new-project <owner>/<name>` | Creates a repository with the required checks enforced; deletes it if a check cannot be raised | You only |
| `floor-check [owner/name]` | Reads an existing repository against the same floor and reports; changes nothing | You or the agent |
| `arsenal` | Catalog of the tools below: what, when, cost | You or the agent |

Installed with plinth as dependencies, each pinned to a commit:
[mattpocock-skills](https://github.com/mattpocock/skills) (planning to review),
[frontend-design](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/frontend-design),
[last30days](https://github.com/mvanhorn/last30days-skill) and
[ponytail-skills](https://github.com/DietrichGebert/ponytail) (the ponytail
skills without its hooks). Listed but not installed: `ponytail`, the full
plugin with hooks. Run
`/plinth:arsenal` for the catalog; licenses are in [NOTICE](NOTICE).

Nothing in the plugin enforces anything. Enforcement is the ruleset on GitHub,
which `/plinth:new-project` raises and which owners cannot bypass.

## Status

This first version is the skeleton: the install works end to end and CI proves it on
a clean runner, but `new-project` and `floor-check` are placeholders that say
so and stop. The [CHANGELOG](CHANGELOG.md) lists what each version adds.

## Further reading

- [CONTEXT.md](CONTEXT.md): the vocabulary (wall, door, box, floor, arsenal, lab, profile).
- [plinth-lab](https://github.com/coolbress/plinth-lab): the evidence behind the rules. Optional.

Rebuilt from `coolbress/workflows@0313cd9`, to be archived.
