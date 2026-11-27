### Changed

- `/plinth:template-update` no longer recommends one side whole for a
  conflict that would lose a line the project added (#1186). On GitHub,
  when copier leaves conflicts, `--apply` compares each file with copier's
  render of the recorded answers at the recorded tag and lists the lines the
  project added there that the template's side drops. For a file with any,
  it writes a combination beside the update's record, never into the
  worktree: the template's side with each line kept where it belongs now,
  and where both sides set the same key (YAML or TOML), the project's value.
  A line whose neighbours are gone is kept at the end of its block and
  flagged; in `AGENTS.md` the skill proposes moving it under
  `## This project`, its last section, and moves it only on the person's
  word for that line. A file with no such line may still take the
  template's side. The skill offers six choices per file (the combination
  in full, the template's side, the project's side, the full diff, the
  person edits it, or stop), recommendation first. The draft pull request's
  description lists each such line and the file and section it is in now,
  or that it is not there. Measured on a copy of coolbress/nexusbt, the
  combinations of `ci.yml` and `pyproject.toml` keep its
  `test-timeout-minutes: 20`, its widened `diff-size-exclude`, its
  `extra-python-versions: ""`, its nine pytest markers and its `addopts`,
  and parse. GitHub's plain update only. MINOR: no check, job, workflow
  input or secret changes.
