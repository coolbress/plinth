### Changed

- A change's changelog line is its own file, `changelog.d/<branch-slug>.md`,
  starting with its Keep a Changelog section, in place of a line under
  `## [Unreleased]` (#1136): pull requests open from the same `main` no
  longer conflict in `CHANGELOG.md`. `scripts/make-release.sh` writes the
  fragments into the new version's section, grouped by section, deletes them
  in the release commit, and stops on a fragment that names no known section
  or is empty. `ci / docs` fails a pull request that writes under
  `[Unreleased]`, and the release pull request still passes without a
  review with its fragments removed. `scripts/raise-template-pin.sh` writes
  its line to `changelog.d/template-pin.md`.
