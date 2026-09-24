---
name: template-update
description: Apply the plinth-template update /plinth:floor-check reports as a draft pull request, from a worktree branched off the verified default branch. User-invoked only; it pushes a branch and opens a pull request, and it leaves every conflict for a person.
disable-model-invocation: true
---

# Template update

Runs the `copier update` line `/plinth:floor-check` prints under its template
drift WARN, and turns the result into a draft pull request. One script does
it in three steps, each started only on the user's word in this session; this
skill runs it and relays what it says. The command is the checker's own line,
read from it, never written out here or by you.

## 1. The plan

From the repository's own checkout:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/template-update.sh
```

It fetches the default branch, checks it against GitHub's copy, and prints the
two tags, the worktree and branch it would make, and the command. It writes
nothing. Show that output whole. Exit 1 means nothing to do or a stop (the
recorded tag is the target, no pin to carry, a base it could not verify):
show the message and stop there.

## 2. The user's yes

Ask the user whether to apply exactly that plan. Invoking this skill is not
the yes: the yes is to the plan they have just read. Without it, stop.

On a yes, run the `--apply` line the plan printed, as printed, adding your own
agent and model:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/template-update.sh --apply <sha from the plan> --assisted-by <agent>:<model>
```

For example `--assisted-by Claude:claude-fable-5-1`. The line ends the pull
request description. The script refuses if the default branch moved since
the plan; then show the plan again and ask again.

## 3. What it says

- **Exit 0**: it made one commit in the worktree, pushed that branch, and
  opened a draft pull request. Show the URL. Its checks start now and nothing
  waited for them. Do not wait for them, mark it ready or merge it.
- **Exit 3, a conflict**: copier left files a person has to resolve. The
  script names them and the worktree, and nothing is pushed yet. Show the list
  and the path. Do not resolve a conflict yourself and do not pick a side, not
  even one that looks obvious: the user resolves it, in the worktree (remove
  every marker, delete each `.rej` once applied, `git add`). If they ask for
  help, show both sides and let them decide. When they say it is done, run
  the `--finish` line the script printed, adding the same `--assisted-by`.
  If anything is still unresolved it stops again with exit 3 and opens
  nothing.
- **Exit 1**: it stopped. Show the message; it names what to do. When the
  push or the pull request failed, that is the same `--finish` line again,
  which pushes the commit already made and does not make a second one. Do not
  work around it: do not run copier, `git push` or `gh pr create` yourself.

The pull request's description lists what copier merged cleanly, what a
person resolved, and anything else a person changed after the update. It
uses the two headings of the pull-request template plinth-template renders;
it does not read a template this repository or its owner changed. If theirs
differs, tell the user, and leave the rewording to them. The
worktree stays beside the repository (`<repository>-template-<tag>`) after the
pull request opens. Nothing here pushes to the default branch, and nothing
runs again on its own.
