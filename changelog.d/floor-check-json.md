### Added

- `scripts/floor-check.py --format json` prints the run as one JSON document
  (#1105, first part): each result's id, state, message, area, hand-off and
  view, the reason an item could not be read, who reads an item left to a
  login that administers the repository, the checks the run did not
  evaluate, and the counts. Its shape is `scripts/floor-check.schema.json`.
  The text output and `ci / floor-check` are unchanged.

### Changed

- `/plinth:floor-check` is lighter to read: its `SKILL.md` is 201 lines and
  11,906 bytes, from 577 lines and 41,710, with no issue numbers, and opens
  with the read-only rule. What each item reads and does not read moved to
  `skills/floor-check/reference.md`, which the skill opens only when the
  person asks about one item.
