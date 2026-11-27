### Fixed

- `/plinth:template-update`'s conflict combination (#1186) no longer puts a
  line the project added in the wrong place in four YAML and TOML shapes
  (#1233). A line counts as the project's only in the table or YAML parents
  where it changed it, so the template's change to the same text in another
  table arrives. A neighbour is found in its own scope and occurrence, not as
  the first identical line. Each `[[table]]` entry is its own scope. A
  comment added above a key whose value the project left alone goes above
  the template's line, with one assignment. A TOML combination that still
  does not parse is said, so the person takes a side or edits it instead.
  PATCH: no check, job, workflow input or secret changes.
