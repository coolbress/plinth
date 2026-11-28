### Added

- The eval suite grades floor-check where it should stay quiet too (#1117):
  `floor-gaps` fails a report that calls `LICENSE`, `SECURITY.md` or
  `.gitignore`, which the project has, missing; `floor-clean` runs on a
  project with nothing to fix and fails an invented finding; `floor-unreadable`
  runs with `gh` logged out and GitHub refused and fails a report that makes
  what it could not read a failure or a row to do; and the trigger pair
  (`floor-trigger-setup`, `floor-trigger-code`) passes when "is my setup
  right?" calls `/plinth:floor-check` and "is my code right?" does not. Each is
  a regression task: pass^3 in the plinth arm on every release that touches
  floor-check.
