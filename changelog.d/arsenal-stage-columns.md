### Changed

- `/plinth:arsenal`'s "Where you are" table has the six columns of one row
  per stage (#1086, second part): Trigger, Tool, Class, plinth piece, Also and
  Then. Tool gives one tool for each job of the stage, Class says for each
  whether it is installed, built in, platform or listed, and Also is at most
  one alternative with its condition: `/design` on the idea row (Claude Code
  v2.1.265 or later, an account where the Design template is available),
  `/wayfinder` on the plan row, `/simplify` on the build and check rows,
  `/improve-codebase-architecture`, `/insights` and `/handoff` where they
  were. `domain-modeling`, `/grill-with-docs`, `/ponytail-audit` and
  `/debug` leave the rows and stay where they are installed or listed. The
  build row names the project's `verify` skill as its check before a commit,
  in place of Claude Code's bundled `/verify`. `SKILL.md` is 93 lines and
  10,401 bytes, from 94 and 15,906.
- `/plinth:guide` says the same as before: what it says of each step (Next
  action, How to use it, It leaves) moved to `skills/guide/steps.md`, and
  `scripts/guide-state.sh` joins it to the arsenal's row by the step's name
  (`scripts/lib/stage-table.sh`). Its tool cell now carries the row's plinth
  piece, Also and Class.

### Added

- `tests/skill-size.sh` holds the arsenal's `SKILL.md` to 250 lines and
  12,000 bytes, tighter than other skills' 500 and 20,000.
- `tests/guidance-skills.sh` fails when a job in a Tool cell, or an Also
  cell, names a second tool anywhere in its text (a sequence "X, then Y"
  counts each step once), when a job's class is not the one its tool has
  (installed or listed by plinth's manifests, built in, or platform when it
  names no tool), when an Also cell is not one tool with its class and
  condition, and when a tool on the "Not used with plinth" line is in an Also
  cell.
- `tests/guide-cases.sh` fails when a stage has no row in the guide's steps,
  or one without four cells or two rows, when a row there names no stage,
  when the tool cell loses its plinth piece, `also:` or `class:`, and when one
  names a command the arsenal's table does not.
