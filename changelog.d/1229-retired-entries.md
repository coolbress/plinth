### Added

- A removed marketplace entry is uninstalled by Claude Code itself (#1229).
  `marketplace.json` maps `taste-skill` to `null` under `renames` and sets
  `forceRemoveDeletedPlugins`, so at the next session start an installed
  `taste-skill@plinth` is uninstalled. This was measured on Claude Code
  2.1.326 and on the floor 2.1.274, and only plugins from plinth's marketplace
  are touched. Before that session, `update` leaves it disabled with no
  error. `claude plugin uninstall taste-skill@plinth` still works, and an
  exit 1 with `not found in installed plugins` means it is already gone.
- Retiring an entry is one procedure:
  - a Retired entries table in `docs/reference/dependency-entries.md`, which
    `tests/marketplace-manifest.sh` holds to `renames` and the dependencies;
  - `scripts/make-release.sh` run 1 stops a release that removes an entry,
    drops a dependency or adds one without saying what installed users run;
  - `tests/install-smoke.sh`'s upgrade path reads the table instead of naming
    `taste-skill` by hand.
- `/plinth:floor-check --plugins` names a plugin installed from the plinth
  marketplace that the marketplace no longer lists (`FC-G12`, a WARN, where
  `FC-G02` said it was not checked). When the table has it, the line names
  the release it left in and its replacement, and the fix is
  `claude plugin uninstall <name>@plinth --scope <scope>`.
