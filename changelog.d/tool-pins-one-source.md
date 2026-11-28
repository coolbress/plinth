### Security

- A new project renders with copier 9.19.1, up from 9.18.2. copier 9.19.0's
  release note lists one security fix: "**vcs**: prevent argument injection
  via `git` subprocess calls" (#1220). copier's dependencies now come from a
  lock, every one at the version locked, where before they were bounded by
  a date.
- `ci / lint` in every consumer runs zizmor 1.33.1, up from 1.29.0 (#1220).
  It reports medium and above, as before. A new project's workflows, every
  archetype, show no finding under 1.33.1. A repository whose own workflows
  have more may see a new finding fail the step; the step's next line names
  the command to run here.

### Changed

- Each tool version plinth pins has one source that Dependabot raises as a
  pull request (#1220): `tools/lint` (zizmor, ruff, mypy, for `ci / tools`)
  and `tools/copier` (the renderer the door and `/plinth:template-update`
  run), each a `pyproject.toml` with exact pins and a `uv.lock` with every
  dependency hashed. `tests/tool-pins.sh` fails when another copy names
  another version.
- [`/plinth:floor-check`](https://github.com/coolbress/plinth/blob/main/skills/floor-check/SKILL.md)'s
  `copier update` line no longer carries `--exclude-newer <date>`.
  [`/plinth:template-update`](https://github.com/coolbress/plinth/blob/main/skills/template-update/SKILL.md)
  runs it with copier's lock as uv's constraints, so the line names no path
  on this machine. The pull request it opens quotes the shorter line. The
  line is for that skill to run: pasted into a terminal by hand, it resolves
  copier's dependencies at their newest.
