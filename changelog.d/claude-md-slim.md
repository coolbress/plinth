### Changed

- plinth's own `AGENTS.md` (`CLAUDE.md`) keeps the rules an agent needs before
  acting, in 97 lines rather than 159, and links each procedure to its one
  home: the review rounds to the reviewer how-to, closing an issue to
  [the issue tracker page](https://github.com/coolbress/plinth/blob/main/docs/agents/issue-tracker.md#closing-an-issue), the
  release pull request to the release how-to, and the dependency-entry
  exceptions to a new page, [dependency entries](https://github.com/coolbress/plinth/blob/main/docs/reference/dependency-entries.md).
  The incidents that justified its rules are lines in the decisions page.
  The only rule that changed is its own size: at most 110 lines and 7,500
  bytes, which reverses the 60-line cap #25 set for it.
