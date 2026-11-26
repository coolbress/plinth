### Changed

- When a merged change broke `main`, plinth says to undo it first (#1079).
  `/plinth:guide` reads the head of `main`'s latest failing CI run: when it is
  a squash merge, the next step is to undo that pull request with the
  project's own `docs/how-to/undo-a-merged-change.md` (a revert pull request
  through the same checks), ahead of any open pull request's failing check.
  A `then also:` line names what follows: restore lost or changed data, then
  reproduce and fix, then a short blameless incident note in the issue's
  Outcome. Step 7 of `docs/how-to/run-a-project.md` and the arsenal's
  "Something broke" row give that order, a leaked secret revoked or rotated
  before any history rewrite, a revoke list for something bad that ran on
  this computer, and Claude Code's built-in `/rewind` for the agent's own
  edits in a session, which never undoes a merge.
