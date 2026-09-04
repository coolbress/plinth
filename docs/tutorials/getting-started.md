# Getting started

This tutorial will walk from an empty machine to a merged first pull request.
The steps after installing arrive with the `new-project` skill; until then this
page holds the install block that CI replays.

## Install plinth

<!-- install-block:start -->
```bash
claude plugin marketplace add coolbress/plinth
claude plugin install plinth@plinth
```
<!-- install-block:end -->

On a clean or CI machine, add the official marketplace first:
`claude plugin marketplace add anthropics/claude-plugins-official`.

Then start Claude Code and type `/plinth:arsenal` to see what was installed.
