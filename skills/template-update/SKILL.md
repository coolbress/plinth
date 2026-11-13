---
name: template-update
description: Apply the plinth-template update /plinth:floor-check reports as a draft pull request, from a worktree branched off the verified default branch. User-invoked only; it pushes a branch and opens a pull request, and it resolves a conflict only on the person's word for that file.
disable-model-invocation: true
---

# Template update

Runs the `copier update` line `/plinth:floor-check` prints under its template
drift WARN, and turns the result into a draft pull request. One script does
it in three steps, each started only on the user's word in this session; this
skill runs it and relays what it says, then runs the project's review on the
pull request it opened. The command is the checker's own line,
read from it, never written out here or by you.

## 1. The plan

From the repository's own checkout:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/template-update.sh
```

It fetches the default branch, checks it against GitHub's copy, then compares
the template tag this installed plinth targets with the latest plinth
release's and the tag the project's CI pin was tested with. When the installed
one is older it prints the commands and exits 1, having written nothing else.
Show them and stop. The person types them, in this order:

1. `claude plugin marketplace update plinth`
2. `claude plugin update plinth@plinth`
3. `/reload-plugins`, or a new session: a running session does not load a new
   version
4. `/plinth:template-update` again

Never run them yourself. When it says the tag is in no release yet, pass that
on too: the commands may find nothing until a release carries it, and the plan
stops until then. When the release cannot be read it warns, naming the
tag it goes on with: pass that warning on, and carry on with the plan.

Otherwise it prints the two tags, the worktree and branch it would make, and the command. It writes
nothing. Show that output whole. Exit 1 means nothing to do or a stop (the
recorded tag is the target, no pin to carry, a base it could not verify):
show the message and stop there. When the workflows call plinth at two
commits (`ci.yml` raised by hand, `label.yml` not) and each other file's is
an ancestor of the `ci` job's, the plan carries the `ci` job's commit and a
`Moves:` line names each file it moves forward; after copier, the apply
stops if any plinth `uses:` does not name that pin. Otherwise (another file
newer, two commits neither behind the other, a compare not read) it stops:
the message names each file with its commit, which is the newer when GitHub
says, and the line that makes them one. Never move the `ci` job's pin for
the person: that is their change, in its own pull request, before the update
runs again (#793). One exception at the target tag: when the
repository recorded that its owner's `.github` shares a pull-request
template or issue forms, the owner no longer does, and the repository has
none of its own, the plan names each answer that turns false and gives a
line that re-renders the same tag, which writes the template's copies (#770).

The command keeps the plinth commit the repository's workflows call today,
so an update never undoes a pin Dependabot moved. On GitHub it also carries
whether the owner's `.github` repository publishes a pull-request template
and issue forms, so an update never writes a form that hides the owner's
shared ones; when that cannot be read, the plan says so and stops (#726). When the target tag was
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

- **Exit 0**: it made one commit in the worktree, pushed that branch (or found it pushed by the person after exit 5), and
  opened a draft pull request. Show the URL. Its checks start now and nothing
  waited for them. Do not wait for them, mark it ready or merge it.
  Its description says `Review: none (...)`, because no review has run yet.
  In the worktree, run the project's default review, the one its `AGENTS.md`
  names (on a project made with plinth, a fresh-context review given only the
  diff), then replace the `Review:` line with what ran, for example
  `Review: fresh-context`, with what it reported on the lines under it. If
  none could run, the line stays `none`, with the reason why. That is the one
  edit this skill makes to the description (`gh pr edit --body-file`, on the
  body as `gh pr view` reads it). Show the user the findings, and change
  nothing in the update for them without the user's word.
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
- **Exit 4, over the diff limit**: counted as `ci / diff-size` counts, with
  this repository's own `max-diff-lines` and `diff-size-exclude`, the update
  is over the limit. It is a commit in the worktree and nothing is pushed.
  Show the count and the proposed split: the paths of a first pull request
  that fits (issue forms first), and this update with the rest, which keeps
  `.copier-answers.yml`. Recommend the split, and run its lines only on the
  user's word. They make the first part from the update's own changes, and
  a person opens and merges its pull request. Then merge the default branch
  into this worktree and run `--finish` again; it counts from the new merge
  base. The other choice is `--finish <worktree> --over-limit`: the pull
  request opens as it is, and `ci / diff-size` stays red on it until it is
  split, since an approval does not lift the size limit (#795).
- **Exit 5, the push is the person's**: GitHub refused the branch because
  it changes `.github/workflows/` and the credential the agent pushes with
  may not (a token without the workflow permission, as
  `${CLAUDE_PLUGIN_ROOT}/docs/how-to/give-the-agent-a-token.md` recommends).
  This is not a retry: `--finish` from here is refused the same way. The
  commit is ready. Show the user the `git push` line the script printed and
  ask them to run it from a separate terminal with a credential that has the
  permission; do not run it yourself or look for another credential. When
  they say it is pushed, run the printed `--finish` line once; it finds the
  branch on origin at the commit and opens the draft without pushing again.
- **Exit 1**: it stopped. Show the message; it names what to do. When the
  push or the pull request failed, that is the same `--finish` line again,
  which pushes the commit already made and does not make a second one. Do not
  work around it: do not run copier, `git push` or `gh pr create` yourself.

The pull request's description says which plinth pin was chosen and names
both SHAs, and lists what copier merged cleanly, each conflicted file with
how it was resolved (from `--resolved`), and anything else a person changed
after the update. When the updated template names `GLOSSARY.md` and the
repository's glossary is still `CONTEXT.md` (and `CONTEXT-MAP.md`), the
script moves it to the new name with its content unchanged, after copier and
before the commit, and the description lists the move; a `GLOSSARY.md` that
already exists is kept and named as the reason. Tell the user in one line. It
follows the fields of the pull-request template plinth-template renders:
`## What and why`, `## What I checked myself`, `## How it was verified` and a
`Review:` line, in that order. `What I checked myself` holds what the script
checked and says it is not a person's check; the rest stays as the script
wrote it, apart from the `Review:` line above. It does not read a template this
repository or its owner changed. If theirs differs, tell the user, and leave
the rewording to them. The
worktree stays beside the repository (`<repository>-template-<tag>`) after the
pull request opens. Nothing here pushes to the default branch, and nothing
runs again on its own.
