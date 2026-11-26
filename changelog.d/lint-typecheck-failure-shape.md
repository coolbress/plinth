### Changed

- A failing `ci / lint` or `ci / typecheck` now says what failed, the next
  step and a link, as `ci / test` does (#1099): the log ends with `failed:`,
  `next:` and `more:` lines, and one annotation titled with the check's name
  says the same. Each ruff finding and each mypy error is an annotation at
  its file and line, with its code, nine at most in the job, then a line
  saying how many there are; `ruff format --check` names the files and
  `uv run ruff format`. `next:` is the local command that shows the same
  errors (`uv run ruff check .`, `uv run mypy .`). ruff or mypy stopping on
  its own error (exit 2) with no file and line named fails as "could not
  run", not as findings; mypy's syntax error, also exit 2, is an error at
  its line. The
  ruff and mypy steps are named (`ruff check`, `ruff format --check`,
  `mypy`); no job, step id, check name, input or secret is renamed, and no
  package or action is added.
