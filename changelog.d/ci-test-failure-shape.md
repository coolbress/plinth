### Changed

- A failing `ci / test` now says what failed, the next step and a link, in
  the three places a person and their agent look (#1098). Its log ends with
  `failed:`, `next:` and `more:` lines, the last thing plinth prints in the
  job, and one annotation titled `ci / test` says the same in at most 300
  characters: on a failing test it names the first one and the command that
  runs it (`uv run pytest <test>`), and each failed test is an annotation at
  its file and line, nine at most, then a line saying how many there are.
  Fewer warnings: a step that did not run because an earlier step failed is
  no longer a warning once the job has a `fail:` line (it repeated the
  failure and read like the cause), and every job's Verdict prints its
  summary lines into the log too. The links `python-ci.yml`,
  `pr-review.yml` and the scripts they fetch print now name the plinth
  commit the project's `ci.yml` calls (`job.workflow_sha`, its first 12
  characters), not `main`; `more:` opens the check's section of the new
  "When a check fails" part of `docs/reference/required-checks.md`. The
  pytest step is named `pytest on .python-version` (it showed as
  "Run limited() {"); no job, step id, check name, input or secret is
  renamed. The other required checks get the same shape in #1099 and #1100.
