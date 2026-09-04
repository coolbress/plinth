# Glossary

One meaning per term, in code, docs and issues. The Korean metaphors these came
from stay in the lab.

- **wall**: the required status checks and branch rules a repository's ruleset
  enforces on `main`. Raised on GitHub, not in the plugin, so an agent cannot
  turn it off. Check names: `ci / pr-title`, `lint`, `typecheck`, `test`,
  `build`, `secrets`, `deps`, `diff-size`, `floor-check`, plus `CodeQL`.
- **door**: `/plinth:new-project`. Creates a repository, renders the box, raises
  the wall, opens the first pull request, and deletes the repository if any
  step after creation fails.
- **box**: the project template (`plinth-template`, rendered with copier). The
  files a new repository starts with.
- **floor**: the minimum a repository must have to be considered set up: the
  wall, secret scanning, dependency updates, the document set. `/plinth:floor-check`
  reads an existing repository against it and changes nothing.
- **arsenal**: the plugins plinth installs by default plus the ones it lists for
  manual install. `/plinth:arsenal` is the catalog. Nothing in it is enforced.
- **lab**: `plinth-lab`, the evidence behind the rules. Optional reading; the
  product is written to be understood without it.
- **profile**: an opt-in plugin that adds hooks on top of the default install
  (`plinth-hooks`, not part of this version). The default install has no hooks.
