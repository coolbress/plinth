---
name: template-update
description: Apply the plinth-template update /plinth:floor-check reports as a draft pull request, from a worktree branched off the verified default branch. User-invoked only; it pushes a branch and opens a pull request, and it resolves a conflict only on the person's word for that file.
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

The command keeps the plinth commit the repository's workflows call today,
so an update never undoes a pin Dependabot moved. When the target tag was
tested with a newer plinth commit, the plan also prints a `Plinth pin:` line
comparing the two, a second command `With the tested pin:`, a `Recommended:`
line saying in one sentence what moving to the tested pin gains, and two
`--apply` lines, `--plinth-pin tested` (recommended) first, then
`--plinth-pin live`. A live pin newer than the tested one is kept, never
moved backwards: the plan then prints one `--apply` line and no
recommendation.

## 2. The user's yes

Ask the user whether to apply exactly that plan. Invoking this skill is not
the yes: the yes is to the plan they have just read. Without it, stop.

When the plan printed two `--apply` lines, recommend the tested pin: give
the `Recommended:` line's reason in plain words, and ask whether to apply the
plan with the tested pin, as recommended, or to keep the pin the workflows
call today. A yes to that question is a yes to the tested pin; the user may
pick the live one instead. Never recommend a pin older than the live one:
the plan does not offer it.

On a yes, run the `--apply` line the plan printed, as printed (the one the
user picked, when there were two), adding your own agent and model:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/template-update.sh --apply <sha from the plan> [--plinth-pin live|tested] --assisted-by <agent>:<model>
```

For example `--assisted-by Claude:claude-fable-5-1`. The line ends the pull
request description. The script refuses if the default branch moved since
the plan; then show the plan again and ask again.

## 3. What it says

- **Exit 0**: it made one commit in the worktree, pushed that branch, and
  opened a draft pull request. Show the URL. Its checks start now and nothing
  waited for them. Do not wait for them, mark it ready or merge it.
  An update often changes the agent's own rules (`AGENTS.md`, `CLAUDE.md`,
  `.claude/settings.json`, a file under `.claude/skills/` or
  `.claude/output-styles/`), which `ci / diff-size` lists. Tell the user:
  when the account that pushed is not an admin of the repository,
  `ci / diff-size` stays red until an admin approves the pull request on
  GitHub (Files changed, Review changes, Approve); when it is an admin, it
  stays green and the merge is the person's decision.
- **Exit 3, a conflict**: copier left files that need a resolution. The
  script names them and the worktree, and nothing is pushed yet. Show the list
  and the path, then recommend, and resolve only on the user's word:
  1. For each file the script named, read it in the worktree (the markers,
     or the `.rej` beside its file) and say in plain words what the template
     changed and what this repository changed. Recommend one resolution:
     the template's side, the repository's side, or a combination you name
     (which lines from each). Give its reason in one sentence.
  2. Wait for the user's word on each file. Their word names the file, or
     answers a question about that one file: "yes to CONTRIBUTING.md",
     "the template's side for both". Silence, or a general "go ahead" or
     "fix it" that does not name the files, is not a word on any of them:
     ask again, file by file. They may choose another side than the one you
     recommended, or resolve a file themselves; either is their word.
  3. Apply exactly the resolution they chose, for that file only, in the
     worktree: remove every marker, apply each `.rej` by hand and delete it,
     `git add` the file. Nothing else in the worktree changes.
  4. When every file has its word and is resolved, run the `--finish` line
     the script printed, adding the same `--assisted-by` and one
     `--resolved <path> "<how>"` per file, its path exactly as the script
     named it (for a `.rej`, the `.rej` path).
     `<how>` says which side and on whose word, for example
     `--resolved CONTRIBUTING.md "the template's side, applied by the agent on the user's word"`,
     or `"resolved by the user"` for a file they resolved themselves.

  If anything is still unresolved, `--finish` stops again with exit 3 and
  opens nothing and keeps none of the `--resolved` it was given; show what
  it names, go back to step 1 for those files, and give every `--resolved`
  again on the run that finishes.
  `--resolved` is a record for the description, not a check, so it never
  lets an unresolved file through.
- **Exit 1**: it stopped. Show the message; it names what to do. When the
  push or the pull request failed, that is the same `--finish` line again,
  which pushes the commit already made and does not make a second one. Do not
  work around it: do not run copier, `git push` or `gh pr create` yourself.

The pull request's description says which plinth pin was chosen and names
both SHAs, and lists what copier merged cleanly, each conflicted file with
how it was resolved (from `--resolved`), and anything else a person changed
after the update. It
uses the two headings of the pull-request template plinth-template renders;
it does not read a template this repository or its owner changed. If theirs
differs, tell the user, and leave the rewording to them. The
worktree stays beside the repository (`<repository>-template-<tag>`) after the
pull request opens. Nothing here pushes to the default branch, and nothing
runs again on its own.
