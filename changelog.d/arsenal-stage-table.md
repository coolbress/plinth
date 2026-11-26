### Changed

- `/plinth:arsenal` is lighter to read (#1086, first part). Its `SKILL.md`
  keeps the "Where you are" table and the list of skills only the person can
  start: 94 lines and 15,906 bytes, from 366 lines and 41,486, with no issue
  numbers. What lies outside the table moved to files beside it, each read
  only when the question needs it: `installed.md` (the default set and its
  cost, the built-ins the table names), `listed.md` (the listed tools and
  their install lines) and `not-used.md`. The coverage by step and concern,
  the selection criteria and the measurements, with their issue numbers, are
  in `docs/reference/arsenal-evidence.md`, for maintainers.
- The "Unsure which skill now" row names `/plinth:guide` only, says the agent
  cannot call it (it is user-only) and asks the person to type it, and says
  that on GitLab the table is the answer. `/ask-matt` stays in
  `mattpocock-skills-extra`.
- `wizard` leaves the arsenal's rows: no recorded run called it. It stays in
  `mattpocock-skills-extra`.
- The release row names GitHub's generated release notes, grouped by the
  project's `.github/release.yml`; the end row names the issue form "End or
  hand over this project".
- The skill's description is written for the agent's choice: choosing a tool
  for a stage or a job, or asked what plinth installs or what a tool costs.

### Added

- `skills/arsenal/not-used.md`: tools an agent can reach without installing
  anything whose use breaks a plinth rule, with their class and the rule.
  Today `/ship` and `/steward`, both built in. `tests/guidance-skills.sh`
  fails when an entry has no class or rule, a class other than built in or
  installed by plinth, or a tool the "Where you are" table names.
