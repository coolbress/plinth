### Changed

- `/plinth:floor-check` gives a short report (#1105, second part). The skill
  reads the checker's JSON through `scripts/floor-report.py`, which prints:
  - one verdict line;
  - at most five action rows, those that cannot be undone or reach others
    first, each one of three kinds: do it yourself, one pull request for
    every file item, or later;
  - one line naming every other finding;
  - what could not be read and what was not checked, each said not to be a
    problem;
  - the passes as one line;
  - one question, last.
  No check id appears in it. "Show everything" and `floor-check <area>`
  print every line, the PASS lines included. The facts that are not findings
  (the SSH-key and clean-credential lines, the wall expectation, the plugins
  at their pin, the sandbox's lines) are left to the JSON and to those views.
- A second run says what changed since the last one: fixed, still missing
  and new, by check. The last run is kept in one note on this machine,
  `~/.cache/plinth/<host>-<owner>-<repo>/floor.json`, written only from a run
  on the default branch with a clean working tree; nothing is written in the
  repository.

### Fixed

- `floor-check.py --format json --verdicts <path>` with a path that cannot be
  written prints one document, the crashed one, instead of two.
