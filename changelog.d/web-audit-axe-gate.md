### Changed

- `ci / web-audit` on a `web` project now fails on a `critical` or `serious`
  axe-core violation of the WCAG 2.2 A and AA rules on `/` or the log-in page
  (#1149). It ran axe-core's default rules and never failed. axe-core now runs
  the rules tagged `wcag2a`, `wcag2aa`, `wcag21a`, `wcag21aa` and `wcag22aa`,
  which adds `target-size` (its default run leaves it out) and drops the
  best-practice rules, which are no WCAG criterion. `moderate` and `minor`
  violations are listed and fail nothing, and no Lighthouse score fails the
  job. The job's summary ends with a checklist of what to check by hand, each
  item with its WCAG success criteria. The job keeps its name and stays
  required by no ruleset; a project whose own pages have a critical or serious
  violation sees it red until they are fixed, and the failure names each rule
  and its first element.
