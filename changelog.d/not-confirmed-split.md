### Changed

- A `not yet confirmed:` line in `ci / test`, `ci / lint` and
  `ci / typecheck` says one fact per sentence (#1156): `not yet confirmed:
  <what>. Why: <reason>. What confirms it: <run>.`, in the job summary and
  in its warning. So does every job's line for a step that did not run
  because an earlier step failed, and on GitLab the `test` job's lines,
  which share the changed-lines code. The verdict's name stays
  `not yet confirmed`; the other checks' own lines follow with #1100 and
  #1101. `docs/reference/terms.md` adds `workflow run`, `job summary` and
  `annotation`, the three places a failing check sends a person.
