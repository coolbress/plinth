### Changed

- The eval suite fails a run that weakened the fixture's tests (#1151).
  - A `test`, `checked` or `merge` task fails a tree that lost one of the
    fixture's test functions, or whose original test files, put back unchanged,
    fail against the agent's code. The second case catches a test loosened
    under its own name.
  - A task's `asked_tests` file names the tests its request asks to change.
    The greeting tasks name their three "Hello" tests.
  - The summary has a `Tests weakened` column. It also counts a `test`-kind
    pass whose checks failed apart from the others.
- Each eval task carries a `tier`, `regression` or `capability`, and the runner
  refuses a task without one (#1151). A task table names each task's tier and
  pass^k per arm.
- `scripts/eval-suite.sh --previous <dir>` reads the previous release run
  (#1151). The task table then marks a task saturated at three of three in
  every arm in both runs, and prints its cost per passed run beside the
  previous run's.
- `docs/how-to/run-the-eval-suite.md` says the `none` arm runs again on a
  release that changes the template's `AGENTS.md` or `.claude/`.
