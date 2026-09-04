# Issue tracker: GitHub

Issues, specs and tickets for plinth live in GitHub Issues on
`coolbress/plinth`. Read and write them with the `gh` CLI. (This file is what
`setup-matt-pocock-skills` would create; it is pre-filled, so do not run that
skill unless you change trackers. Original: mattpocock/skills, MIT.)

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Multi-line bodies via heredoc.
- **Read an issue**: `gh issue view <number> --comments`
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` (filter with `--label`, `--state`)
- **Comment**: `gh issue comment <number> --body "..."`
- **Labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

`gh` reads the repository from `git remote -v`, so run it inside the clone.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Change to `yes` to treat external PRs as feature requests; `/triage` reads this line.)_

## When a skill says "publish to the issue tracker"

Create a GitHub issue. Acceptance criteria map to checks (see `AGENTS.md`).

## When a skill says "fetch the relevant ticket"

`gh issue view <number> --comments`

## Wayfinding operations

Used by `/wayfinder`. A **map** is one issue; tickets are its **child** issues.

- **Map**: one issue labelled `wayfinder:map`. `gh issue create --label wayfinder:map`
- **Child ticket**: a sub-issue of the map (`gh api` sub-issues endpoint). If sub-issues are unavailable, add it to the map's task list and start the child body with `Part of #<map>`. Label: `wayfinder:<type>` (`research` / `prototype` / `grilling` / `task`). Assign yourself when you claim it.
- **Blocking**: GitHub native issue dependencies. `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the numeric **database id** (`gh api repos/<owner>/<repo>/issues/<n> --jq .id`), not `#number` or `node_id`. Fallback: start the child body with `Blocked by: #<n>, #<n>`. Unblocked once every blocker is closed.
- **Frontier query**: open children of the map with no open blocker and no assignee, first in map order.
- **Claim**: `gh issue edit <n> --add-assignee @me`, the session's first write.
- **Resolve**: `gh issue comment <n> --body "<answer>"`, then `gh issue close <n>`, then one line (gist + link) under the map's Decisions-so-far.
