### Fixed

- `/plinth:guide` never routes a breaking-change revert to be undone: a merge
  titled `revert!:` or `revert(<scope>)!:` is a revert, as `revert:` and
  GitHub's `Revert "…"` are, the forms `ci / pr-title` accepts, read in one
  place and held to the title check's by a test. An open revert of the merge
  that broke `main` is now the route itself, ahead of any other pull
  request's failing check: merged on green, diagnosed if its own check fails
  (#1203).
