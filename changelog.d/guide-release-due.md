### Added

- `/plinth:guide` says when a release is due (#1077). A `release due:` line
  gives the last tag and its date, or `no tag yet`, how many changes merged
  since, and how many of them are a `feat:` or `fix:` by a person. When one
  is, nothing else is open (no pull request, no ticket, no spec to cut, no
  triage) and `main`'s latest CI run does not fail, the next step is to push a version tag, as the project's
  `docs/how-to/publish-a-release.md` says, with what goes out for its
  archetype; otherwise the answer says it in one sentence after the next
  step. A `web` project has no such line: it goes out by itself once `main`
  is green. The tag comes from the history read `/plinth:guide` already
  makes, so no call is added.
