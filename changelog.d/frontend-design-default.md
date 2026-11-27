### Changed

- plinth's page-design skill is Anthropic's `frontend-design`, from the
  official plugin directory (`anthropics/claude-plugins-official`,
  `plugins/frontend-design`, pinned to `30202c7`), installed by default in
  place of `taste-skill` (#1082). It is one 9,390-byte `SKILL.md` with no
  scripts or hooks; taste-skill's pinned one was 87,253 bytes, and its
  upstream added Node scripts, so its pin could not be raised. Type
  `/frontend-design`, or name it in the ticket, for a page a person will look
  at; dashboards and dense product UI still go to `/design` first.
- To update from v2.45.0 or earlier: `claude plugin marketplace update plinth`,
  `claude plugin update plinth@plinth`, then once, in this order,
  `claude plugin install plinth@plinth` and
  `claude plugin uninstall taste-skill@plinth`, then `/reload-plugins`.
  `update` alone neither installs `frontend-design` nor removes `taste-skill`.
  If you had already installed `frontend-design` from the official
  marketplace, keep one copy:
  `claude plugin uninstall frontend-design@claude-plugins-official`.
