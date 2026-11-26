---
name: template-update
description: Apply the plinth-template update /plinth:floor-check reports as a draft pull request, from a worktree branched off the verified default branch, or move the project to another archetype the same way when the person asks. User-invoked only; it pushes a branch and opens a pull request, and it resolves a conflict only on the person's word for that file.
disable-model-invocation: true
---

# Template update

Runs the `copier update` line `/plinth:floor-check` prints under its template
drift WARN, and turns the result into a draft pull request. One script does
it in three steps, each started only on the user's word in this session; this
skill runs it and relays what it says, then runs the project's review on the
pull request it opened. The command is the checker's own line,
read from it, never written out here or by you.

On GitLab it runs the same steps through `glab`: copier runs the same way,
and what reads and writes the host is `glab api`, asked of the host and
project origin's URL names, which ends in a draft merge request (a `Draft:`
title) where GitHub's ends in a draft pull request, with its pipeline in
place of the checks. Read "pull request" below as the merge request there.
The script stops before any work on a GitLab checkout whose origin URL names
no project; relay that and stop.

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
runs again. One exception at the target tag: when the
repository recorded that its owner's `.github` shares a pull-request
template or issue forms, the owner no longer does, and the repository has
none of its own, the plan names each answer that turns false and gives a
line that re-renders the same tag, which writes the template's copies.

The command keeps the plinth commit the repository's workflows call today,
so an update never undoes a pin Dependabot moved, and it never moves that
pin. On GitHub it also carries
whether the owner's `.github` repository publishes a pull-request template
and issue forms, so an update never writes a form that hides the owner's
shared ones; when that cannot be read, the plan says so and stops. A
`Plinth pin:` line compares that pin with the one the target tag was tested
with when they differ; a newer live pin is kept.

The pin comes first, the update second. When the workflows call a plinth
older than the one the target tag was tested with, the plan exits 1 having
written nothing, and says so: the two commits, the compare link, and either
`merge first: #<n> ...`, an open pull request that changes the plinth `uses:`
lines (Dependabot's, or one a person opened), or, when none is open,
`raise it first in one pull request of its own: ...`, the change to make,
every workflow that calls plinth moved to the one SHA. Show that whole and
stop. The person merges that pull request (or opens and merges one with the
change), then runs `/plinth:template-update` again. Do not make the change
or merge it for them in this skill. When the comparison could not be read
(offline, or the tag's `copier.yml` unreadable), the plan stops too and
names what it could not read: pass that on and stop; it never updates as if
the pin were current.

When `.copier-answers.yml` records a `plinth_sha` other than a pin the
workflows call (raised in the workflows only, by Dependabot or by hand), the
plan prints a `Pin conflict:` line, with one line under it. copier's old
render names the recorded pin; the command carries the pin the workflows
call, so their plinth `uses:` lines are not in conflict for that (measured
with copier 9.18.2). Two cases still are. A workflow whose pin is neither
the recorded one nor the one the command carries (the `Moves:` case above)
has its line left in conflict; the side to keep is the one naming the pin
the command carries (copier's `after updating` side). A plinth `uses:` line that
carries a trailing comment (`# v2.41.0`, as Dependabot writes it) is
changed too, since the template renders none: the plan names those files
as in conflict though both sides name the same pin, and either side runs
the same plinth. Tell the user this before asking for the yes, so
an exit 3 on those files is the conflict they were told of.

## 2. The user's yes

Ask the user whether to apply exactly that plan. Invoking this skill is not
the yes: the yes is to the plan they have just read. Without it, stop.

On a yes, run the `--apply` line the plan printed, as printed, adding your
own agent and model:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/template-update.sh --apply <sha from the plan> --assisted-by <agent>:<model>
```

For example `--assisted-by Claude:claude-fable-5-1`. The line ends the pull
request description. The script refuses if the default branch moved since
the plan; then show the plan again and ask again. It stops as the plan does,
having created nothing, when the plinth pin is behind.

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
  body as `gh pr view` reads it; on GitLab `glab mr update <iid> --description`,
  on the body as `glab mr view <iid> -F json` reads it). Show the user the findings, and change
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
     (which lines from each). Give its reason in one sentence. A plinth
     `uses:` line the plan's `Pin conflict:` line named is that conflict:
     recommend the side naming the pin the command carried.
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
  split, since an approval does not lift the size limit.
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
- **Exit 2**: the arguments were wrong and nothing was committed. A usage
  line means a flag was missing its value or given in the wrong step; run
  the step as written above. A `--resolved` path copier did not leave in
  conflict is followed by the files that are; run `--finish` again naming
  those.

The pull request's description gives the plan's plinth pin line, and lists what copier merged cleanly, each conflicted file with
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

## Moving to another archetype

Use `--archetype <a>` when the person says the project was made under an
archetype it does not fit: a `data-ml` project that trains nothing, for
example, which would otherwise delete the model example by hand and still get
it offered again by every update. Moving is the person's call: never propose
it as the fix for a warning, and run each step only on their word. It moves
between any two archetypes but `web`, which it does not move to or from, on
GitHub and on GitLab. Which names are archetypes
is the template's to say: copier refuses one it does not offer, and the plan
stops on that before anything is written. The project must already be
at the template tag this plinth targets: when it is behind, the plan stops
and says to update first.

The steps, from the plan to the conflicts a move leaves and what its pull
request says, are in `${CLAUDE_PLUGIN_ROOT}/skills/template-update/reference.md`:
read it before planning a move, and follow it as written.
