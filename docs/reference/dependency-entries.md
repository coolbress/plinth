# Dependency entries

What an update does when a marketplace entry that plinth depends on changes,
and so how such an entry may change. `AGENTS.md` asks first for any change to
what a dependency carries; this page holds the rule and its exceptions in full.

## The rule

Narrow or widen an entry's `skills` under the name it has; never rename or
move the entry. `claude plugin update` does not install a dependency under a
new name: the old one stays installed and failing, or, with a `renames` map,
is dropped without an error (measured for #468, on Claude Code 2.1.296, before
2.1.319).

## The exceptions

- **An upstream root with its own `plugin.json`** (measured for #469). Such an
  entry cannot narrow its `skills` with a `url` source: `strict: false` then
  fails as conflicting manifests. Its source moves to `git-subdir` under the
  same name, and installed copies need `claude plugin update <name>@plinth`
  once besides the update of plinth.
- **A move from another marketplace into plinth's under the same name**
  (measured for #477). The move survives only with two commands,
  `claude plugin install plinth@plinth` then `claude plugin prune`, which the
  release note names.
- **An entry removed and replaced by one under another name** (measured for
  #1082: taste-skill for `frontend-design`). From Claude Code 2.1.319,
  `update` installs the new dependency; before it, it does not. On every
  version the old one stays installed, failing as "not found in marketplace",
  and `prune` does not take it (#468). The release note names, once and in this
  order, `claude plugin install plinth@plinth` then
  `claude plugin uninstall <old name>@plinth`.

## Retired entries

An entry plinth no longer installs, and what an installed user runs once.
There are two kinds:

- **Entry removed.** The name is gone from `marketplace.json`'s `plugins`,
  and `renames` maps it to `null`. With `forceRemoveDeletedPlugins: true`,
  Claude Code uninstalls it at the next session start, on 2.1.326 and on the
  floor 2.1.274. Only plugins installed from plinth's marketplace are
  affected. `update` alone leaves it installed and disabled (measured for
  #1229). The release note still names `claude plugin uninstall <name>@plinth`
  for a session not yet restarted. When that command exits 1 with
  `not found in installed plugins`, Claude Code has already removed the
  plugin.
- **Dependency dropped, entry kept.** The name stays in `plugins`, and so it
  is still installable by hand, but it is no longer in `plugin.json`'s
  `dependencies`. `claude plugin prune` removes the auto-installed copy.

`tests/marketplace-manifest.sh` holds the table to the manifests in both
directions:

- each removed name is a `renames` key mapped to `null`, and every such key
  is a removed name;
- no removed name is in `plugins`;
- no dropped name is a dependency.

`scripts/make-release.sh` run 1 stops a release that removes an entry or
drops a dependency without a row here and the command in its section.
`tests/install-smoke.sh` runs the commands on the upgrade from the latest
release. A retired name that comes back later loses its row and its `renames`
key.

| Name | Kind | Left in | Replaced by | Issue | An installed user runs |
| --- | --- | --- | --- | --- | --- |
| `taste-skill` | entry removed | v2.46.0 | `frontend-design` | #1082 | `claude plugin uninstall taste-skill@plinth` |
| `ponytail-skills` | dependency dropped | v2.2.0 | – | #598 | `claude plugin prune` |
