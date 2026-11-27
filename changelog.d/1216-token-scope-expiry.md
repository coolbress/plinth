### Fixed

- [Decisions in force](https://github.com/coolbress/plinth/blob/main/docs/reference/decisions-in-force.md) no longer
  says the agent never sees the GitHub token: the deny rules close the common
  ways of reading it, and the everyday token's scope (one repository, no
  Workflows, no Administration) bounds what a token the agent does reach can
  do. [Give the agent a token](https://github.com/coolbress/plinth/blob/main/docs/how-to/give-the-agent-a-token.md)
  step 1 now names an expiration date and what an expired token looks like
  (`Bad credentials (HTTP 401)` from `gh`, `Authentication failed` from
  `git push`) (#1216).
