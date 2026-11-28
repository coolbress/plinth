### Changed

- `/plinth:new-project` renders plinth-template v1.53.0 instead of v1.52.0.
  A `cli` can run on GitHub on a schedule, its results kept as the run's
  artifact: `--scheduled-run`, which until now stopped with "does not ask
  scheduled_run" (coolbress/plinth-template#363; the door's half is #1070).
  The template also asks `calls_claude`, off by default: a `cli`,
  `dashboard` or `backend` that calls Claude through one module, with a
  fake-client test and the README on the key
  (coolbress/plinth-template#371, coolbress/plinth-template#373); the door
  renders it off until it asks the question itself (#1071). A `backend`'s
  publish page says where its image can run and what that costs
  (coolbress/plinth-template#370). A new project calls plinth v2.46.0's
  workflows: the template's `plinth_sha` default moved from v2.45.0, and its
  GitLab checksum with it. An existing repository needs its plinth pin raised
  to v2.46.0 before this update: `/plinth:template-update`'s plan stops and
  names that pull request first. `/plinth:floor-check` now reports a
  repository on v1.52.0 as behind. On that update an existing project gets
  `calls_claude: false` and `scheduled_run: false` in `.copier-answers.yml`,
  and a `backend` the publish page's new section
  (<https://github.com/coolbress/plinth-template/releases/tag/v1.53.0>).
