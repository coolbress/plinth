### Changed

- On plinth's own pull requests, an edit to the title or the description
  re-runs only the checks that read them: `ci / docs`, `ci / release-gate`
  and the canaries' `pr-title` and `diff-size`, in a new `ci-text.yml`
  (#1133). It no longer restarts `ci / install`, `ci / tools` or the
  canaries' code jobs, and it no longer cancels the run a push started.
  Every check name stays; `python-ci.yml` and consumers are unchanged.
  Pull requests open when this merges keep their older `ci / docs` and
  `ci / release-gate` from `ci.yml` until their next push: GitHub requires
  each workflow's latest run of a name, so a red one there still holds the
  merge after an edit fixes the text. A push, or "Update branch", clears it.
