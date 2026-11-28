### Added

- `/plinth:new-project` takes `--scheduled-run` for a `cli` on GitHub (#1070):
  the command also runs on GitHub every day and by hand, even while the
  person's computer is off, and each run's results are a download under
  Artifacts on the run's page, never a commit. A description with a schedule
  word and the computer off recommends it; "run it on my machine" recommends
  `cli` without it; one that says neither asks. Its prerequisites line says
  where the results are, the private-repository allowance and the 60-day
  rule. `--no-scheduled-run`, the default, runs it on the computer only. The
  GitLab door refuses `--scheduled-run` before anything is read: a GitLab
  pipeline schedule was not tried. The door passes the answer once plinth's
  template pin reaches the plinth-template release that asks it; until then
  `--scheduled-run` stops before anything is created, saying the template
  does not ask it. `/plinth:floor-check` reports a `cli` with the option the
  same as one without.
