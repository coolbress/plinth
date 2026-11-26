### Changed

- A failing `ci / build`, `ci / secrets`, `ci / deps`, `ci / migrations` or
  `ci / deploy-check` now says what failed, the next step and a link, as
  `ci / test` does (#1100): the log ends with `failed:`, `next:` and
  `more:`, and one annotation titled with the check's name says the same.
  `ci / secrets` annotates each secret gitleaks finds at its file and line,
  nine at most, naming the rule and the commit and never the secret, and
  gitleaks' own error fails as "could not run". `ci / deps` splits its one
  `fail:` line into its causes: an added dependency version with an
  advisory (named with its version and advisory, next: raise it) or a
  review that could not run (next: re-run). `ci / build` names the module
  and artifact the install smoke stopped on, and its own "no wheel or sdist"
  annotation becomes a log line, so one cause gives one annotation.
  `ci / deploy-check` names the first deployment issue it reports. Their own
  `not yet confirmed:` lines say one fact per sentence. No job, step id,
  check name, input or secret is renamed.
