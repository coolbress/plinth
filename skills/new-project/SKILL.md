---
name: new-project
description: Create a new GitHub repository with required checks already enforced. User-invoked only; creates a remote repository and deletes it if any check cannot be raised.
argument-hint: "[<owner>/]<name> [--license=<spdx>] [--archetype=cli|library|backend|data-ml] [--dir=<path>]"
disable-model-invocation: true
---

# New project

Creates `<owner>/<name>` on GitHub with the wall already up, or creates
nothing. One script does all of it; this skill runs it and relays what it says.

Run, with the user's arguments exactly as typed:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/new-project.sh $ARGUMENTS
```

The script checks tools, token, owner and visibility first and creates nothing
until all four pass. It then creates the repository, renders the template into
`~/<name>` (or `--dir`), pushes `main`, raises the ruleset and CodeQL, and
opens the first pull request. If anything fails after creation it deletes the
repository and says so.

What to do with the output:

- **It stopped before creating anything** (exit 2): show the user the message
  verbatim. It names the one fix. Do not work around it; do not run
  `gh repo create`, `gh auth`, or the script with different arguments.
- **It asks for the admin path**: the message contains one command line
  starting with `with-admin-token.sh`. Show it verbatim and tell the user to
  type it themselves, prefixed with `!` so it runs in this session. It prompts
  for a token at the terminal; never put a token on a command line or in a
  file, and never ask the user to paste one into the chat.
- **It rolled back** (exit 1): show the message. If it says `ROLLBACK FAILED`,
  repeat the URL and that the repository exists without a wall.
- **It finished** (exit 0): show the final lines. The next step for the user is
  to open the pull request URL, wait for the checks, and merge with squash.

Do not edit the generated repository in this session.
