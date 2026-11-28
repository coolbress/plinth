### Changed

- [`/plinth:floor-check`](https://github.com/coolbress/plinth/blob/main/skills/floor-check/SKILL.md)
  reads text other people write, so the checker now makes its API calls for
  the audited repository only (besides its owner's `.github`, plinth and the
  template) and stops on any other. Every git call in the checker, its
  reporter and `/plinth:guide`'s state script passes `core.fsmonitor=false` and
  `core.hooksPath=/dev/null` with `GIT_CONFIG_NOSYSTEM=1`, so those calls run
  no fsmonitor program or hook of the repository they read. The checker and
  the reporter also empty every filter driver (`clean`, `smudge`, `process`)
  that the checkout's own config names, and the reporter's `git status` does
  not enter submodules, so no filter program the repository configures runs
  either (#1278); the person's global filters, such as Git LFS, stay. The
  skill and
  [Run a project](https://github.com/coolbress/plinth/blob/main/docs/how-to/run-a-project.md#1-start)
  say how to run the check headless in a repository someone else wrote
  (#1119).
