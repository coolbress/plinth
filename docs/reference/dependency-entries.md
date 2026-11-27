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
