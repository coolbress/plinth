### Changed

- plinth's own `ci / install` runs its 43 tests in five jobs at once,
  `ci / install-1` to `ci / install-5`, each on its own runner, instead of
  one after another in one job (#1135). `ci / install` keeps its name and
  is now their verdict: it passes only when all five did, and for a failed
  one names the step and the test it runs. Nothing changes for a project
  plinth made; `python-ci.yml` is untouched.
