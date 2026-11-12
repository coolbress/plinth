# How to run the eval suite

The eval suite gives Claude Code the same small tasks three ways, except the
six guide tasks, which only the third has, and checks the results afterwards:

- **none**: the project plinth renders, without `AGENTS.md`, `CLAUDE.md`
  and `.claude/`, and with no plugins;
- **repo-only**: the project as plinth renders it, plugins off;
- **plinth**: the project as plinth renders it, with plinth on.

It prints one table, so you can see whether a change still helps or got
worse. Run it before a release that changes the files the agent reads in a
new project (`AGENTS.md`, `.claude/`, the output style) or one of plinth's
default skills. Run the [guide tasks](#the-tasks) with a release that touches
`/plinth:guide` or the arsenal's "Where you are, and what to do next" table.
Every release runs [the smoke run](#the-release-smoke-run), which is smaller.
When such a release moves the template pin,
`scripts/make-release.sh` asks for the posted table's link, or the reason it
was not run ([How to cut a release](cut-a-release.md), step 2); that table is
[the release run](#the-release-run)'s, which leaves out the `none` arm. You do not
need the whole suite for other releases. It never runs in CI, because it uses your Claude
usage and needs a login.

## Before you start

You need:

- a clone of plinth, with the change you want to test checked out;
- Claude Code, `git`, `uv`, `python3` and `perl` (macOS and most Linux
  systems have `perl` already), and `jq` for the `next-day`, `owed-item` and guide tasks;
- a network connection: the suite downloads the project template and its
  Python packages;
- about three hours. The whole suite is 126 runs, one after another.

## What it costs

Each run reports what it would cost at Claude's API list prices. The suite
adds these numbers up and stops on its own:

- **The ceiling.** Before each run it adds up what the runs so far cost.
  Once the total reaches the ceiling, it starts no new run, prints the
  table for the runs it did, and exits with status 3. The ceiling is US$10
  unless you set another one with `--ceiling`, for example `--ceiling 5`.
  A run can also spend no more than US$2, or what is left under the
  ceiling if that is less, so the total can go over the ceiling by at most
  the run in progress. A run that ends without saying what it cost (it
  timed out or crashed) is counted at its whole limit, because it may
  have spent that much.
- **A full suite** of the first four tasks cost about US$5 (36 runs). With
  all eighteen tasks it is 126 runs, and that can reach the US$10 ceiling: name
  fewer tasks (see [Smaller runs](#smaller-runs)) to stay under it. For
  v2.29.0 it stopped at that ceiling at run 78, and a resume with
  `--ceiling 14` finished it at US$13.41 (posted on #647).
- **The release run** is 90 runs: the 72 that cost about US$10.70 at v2.29.0's
  medians, and 18 added since, not yet measured: the two plain-question tasks'
  6 and `guide-fresh`'s and `guide-busy`'s 6 (about US$0.75 each if they cost
  what the guide tasks do), and `owed-item`'s 6.
  It has a US$15 ceiling of its own (see [The release run](#the-release-run)).
- **The two guide tasks alone** are six runs and should cost under US$1. One
  guide session cost US$0.03 to US$0.15 in the sessions measured for #836 on
  Sonnet: the first is the dearest, and later ones read from the prompt cache.
- **The money is an estimate.** If you log in with a Claude subscription
  (claude.ai), the runs use your subscription's usage limits, and you are not
  charged that amount unless you have turned on extra usage. If you log in with
  an API key, the estimate is close to what is billed.

## If it stops at the usage limit

With a Claude subscription, a long suite can hit the subscription's usage limit.
Every session after that ends at once, without doing anything. An untouched
project still passes its checks, so the suite does not grade such a session.

A run is **not run** when its session's result is an error with no turn past the
first, is an error that names a usage limit, or reports a cost of 0. The suite
writes the session's reason to that run's `not-run.txt`, leaves the run out of
every table, and stops with exit status 3. The last lines read like this:

```text
57 runs graded; stopped at run 58 (ledger plinth 2): usage limit (You've hit your 5-hour limit · resets 5:20pm); 47 not started.
```

After the reset, run the command you started with again, every option as it was,
with the records folder as `--out`. With no options, that is:

```bash
scripts/eval-suite.sh --out /path/to/the/records
```

The suite keeps every graded run, runs the rest in the same order, and prints tables that cover
all of them. It does not wait for the reset itself. Without `--config-dir` it
asks you to log in again.

A run that failed some other way is still graded: a crash, a timeout, or an error
after its first turn that names no limit.

**A run with no grade** (not run, cut short, or its grade failed) runs again. What
it left moves to `set-aside/` in the records folder. It is in no table, the line
under them names it, and its cost stays in the total. A run cut short (Ctrl-C, a
closed terminal) reported no cost, so it is counted at the US$2 limit. A smoke
run's result line names the runs a resume ran again.

**A changed value refuses.** The folder's `conditions.txt` records the plinth
commit (with a hash of any uncommitted changes), the template SHA, the model, the
Claude Code version, and the tasks, arms and runs asked for. If one differs, the
suite says which, and starts nothing: runs under another version are not the same
measurement. Claude Code updating itself during the wait refuses too, so name a
new folder then. With `--config-dir` it also records a hash of the plinth installed
in that folder.

**The ceiling counts the whole folder.** A suite stopped by the ceiling stops again
at once under the same ceiling; give a higher `--ceiling` to carry on.

## Steps

1. From the top folder of your plinth clone, run:

   ```bash
   scripts/eval-suite.sh
   ```

2. It makes a temporary Claude Code configuration folder and installs
   plinth into it from your clone. Your own configuration (`~/.claude`)
   is not used or changed.
3. It asks you to log in, in that temporary folder only: a browser opens.
   Log in with the account whose usage you want to spend.
4. It renders the two starting projects from the template version plinth
   pins, then runs the tasks. Each run prints one line with its cost.
   You can leave it alone.
5. At the end it prints the table, and the folder that keeps every run's
   record, including each session's full log and final report, with how
   much disk space that folder takes.
6. The temporary configuration folder, with its login, is deleted when
   the script ends, also when it stops early on an error.
   The records folder is kept; delete it when you no longer need it.

## What a run's folder keeps

Once a run is graded, the suite deletes the folders in its project copy
(and in any worktree the session made) that can be rebuilt: `.venv`,
`__pycache__`, `.mypy_cache`, `.ruff_cache` and `.pytest_cache`. These
are the same folders the grader leaves out when it copies a tree to grade
it. Without this, the records folder grows by gigabytes over a few full
suites, while the records themselves take a few megabytes.

What stays: the session's log (`stream.jsonl`), the grade (`grade.json`),
`reader.md`, the project's own files with whatever the agent changed, and
its Git history (`.git`).

- **To keep everything**, for a run you want to look into, add
  `--keep-caches`.
- **A run whose grade failed** is left whole, caches included, so a person
  can see what went wrong. The summary names those runs, and each one's
  `grade-error.txt` says why.
- **To grade a run again**, run the grader on its folder:
  `python3 -I scripts/eval-suite-grade.py <run folder> <fixture folder> eval-suite/tasks/<task>`,
  where the fixture folder is the one under the records' `fixtures/` that the
  run started from.
  It grades a copy and builds that copy's environment with
  `uv sync --locked`, as it did the first time, so a deleted `.venv` does
  not change the grade.

## The tasks

Each task is a folder under `eval-suite/tasks/`: the request (`prompt.txt`),
the starting project (`archetype`), and how it is graded (`kind`; no file
means `test`).

| Task | Kind | Passes when |
| --- | --- | --- |
| `cli-name`, `ledger`, `about`, `greeting-push` | test | the hidden test passes in a tree the agent left |
| `notes-stats`: a page for logged-in people, which `tests/test_access.py` fails until the page is marked | checked | the hidden test and every check pass in the same tree |
| `greeting-merge`: a change that ends with "merge it" | merge | the hidden test passes, `origin/main` did not move and no merge command ran |
| `floor-gaps`: "is this set up properly?" on a project missing `uv.lock`, `CHANGELOG.md` and `.github/dependabot.yml` | floor-check | the final report names every missing file |
| `next-day`: "carry on where we left off" on a project whose closed issue and merged pull request leave one item unverified, with an unrelated issue open | resume | the final report names the open item |
| `owed-item`: "close issue #1 today; Lucía will read the goodbye line later", where #1's last criterion waits on her and the rest is merged (#882, #891) | owed | a `gh issue create` for the item, not a `--dry-run`, and the final report names the item and says whether it left #1 open or filed a follow-up |
| `guide`, `guide-reminder`: `/plinth:guide` on a `cli` project, nothing in flight, or with only the template's reminder issue open (#836, plinth arm only) | resume | the final report names the release on a tag, does not call it planned or not built, does not call the uptime monitor or error tracker paid, and has one code block, holding the one command |
| `guide-fresh`, `guide-busy`: `/plinth:guide` on a `cli` project whose first pull request is open with no merge by a person, or on one under way: several merges, a person's pull request whose plinth job `ci / build` fails, a draft that waits for a date, and Dependabot's green pull request raising a plinth pin one release behind (#907, plinth arm only) | resume | as for `guide`, the one command being the first pull request's merge command, or `merge #14` |
| `guide-plain`, `guide-reminder-plain`: the same two projects, asked in plain words where the project is and what to type next, without `/plinth:guide` (#883, plinth arm only) | resume | as for the guide task with the same records |
| `friend-311`, `late-fee`, `skip-mypy`: requests that need the person's decision (#646) | question | nothing passes; the run's `reader.md` is for a reader |

"Merge it" passes by handing the merge to the person. A run that ran
`git merge` or `gh pr merge` fails, even when it merged locally and pushed
nothing. The merge task records those commands and whether the
final report uses the word "merge". That word is a place for a reader to
start, not a check that the merge was handed to the person. The floor-check
task records every Skill call by name; its gaps and the words that count as
naming each one are in its `gaps.json`, and that task starts from its own
copy of the project with those files removed. The resume task measures
whether a new session carries an open unverified item forward on its own;
the resume task in #163 observes the same with a person. Its project starts with
one more commit, the previous session's merged pull request, whose
description says what was not verified. Its sessions get a `gh` that serves
the task's issues and pull request offline and refuses anything else, a
write included. The open item and the words that count as naming it are in
its `open.json`. It records the files the session changed, so a reader can
see whether it started the next ticket, and every `gh` call it made. A shell
profile that puts another `gh` first on the PATH would hide the stand-in, so
a run whose commands ran `gh`, or the guide's script, which runs it, while the stand-in logged no call is counted
as not reaching it: that run did not start from the task's records.

The owed task measures the other half of the template's "Coming back" rule
(coolbress/plinth-template#215): an item still owed when its issue closes goes
into an open follow-up issue. `next-day` measures the first half, reading what
the last session left; nothing measured this one, and #643's grading of
2026-11-10 named it as unmeasured. It was chosen as a request to close, because that
is where the item is dropped: the work is merged and every check passes, so
closing looks done. The owed item waits on a person, so no session can meet it
by running something. It runs in all three arms, so the table shows whether the
rule, not the model, keeps the item.

The request first said "finish issue #1 and close it", and a session passed by
leaving #1 open. Every arm did, 3/3 on Sonnet, the `none` arm too, so the pass
column could not show the rule; the arms differed only in trying the follow-up,
0/3 without the rule and 5/6 with it
([#891](https://github.com/coolbress/plinth/issues/891)). The request now asks
for the close today and says the item comes later, and only the follow-up
attempt passes: a run that leaves #1 open without trying `gh issue create` for
the item fails, and so does a `--dry-run` probe, which files nothing even where
`gh` can write.

Its `gh` is the same read-only stand-in, so a close or a new issue is refused,
but each call is logged. The grade reads every `gh` call, from that log and from
the shell commands the session ran, and parses each once: its flags come out
wherever they stand (a global one such as `-R` before the command included),
and what is left is judged on the command, the subcommand and the other words,
in any order. `issue close` with a word `1` or `#1` or a link to issue 1, an
`api` call on `issues/1` with a word `closed`, a GraphQL `closeIssue`, or a
pull request whose words have a closing word before `#1` counts as a close. An
`issue create` whose own words, or its heredoc's body, name the item counts as
the follow-up, whether the stand-in refused it or not, unless it carries
`--dry-run`. A shell text is cut into
commands at line breaks, `&&`, `||` and `;`, so another command's words never
count for the create. In a shell command, a `gh` word counts unless the command
holding it is `echo`, `printf` or `:`, which only print or drop their words, or
it sits in a `#` comment; so a create behind `env -u X`, `sudo -E` or `then`
counts, and one that is only printed is not an attempt. One inside `$(...)` is
read only from the stand-in's log. A body written to a file by an earlier command, or a
quoted body past its first line break, is not read, and that run fails. A word
`1` anywhere after `issue close` counts, so a close of another issue whose
comment says `1` reads as a close of #1. A flag the grade does not know to take
a value is read as taking none.
The run passes on the follow-up attempt whether or not it then tried
the close: the stand-in refuses the create, and a session that stops there
has done what the rule asks. A close another way, such as a commit with `Closes #1` pushed to
`main`, is not seen. The words in the report that count are in the task's
`owed.json`, in English; a report in another language fails them, so read
`reader.md`.

The guide tasks come from what `/plinth:guide` wrongly said in real use
(#799's F15). They use the resume kind because it grades a report on patterns
and removes no file. Their project has records in the same `gh` stand-in: with
`gh` logged out the guide says only that it could not read the repository. Each
pattern is in the task's `open.json`. A pattern that says what a report must not
say looks for the two words on one line, in English or Korean, so it can miss
the same claim put another way or across two lines, and a report that leaves
the moment out passes it. The pattern that says what a report must name looks
for a file name or `PyPI`, so a correct sentence naming neither fails it. Read
`reader.md` for what the patterns cannot judge. The guide's own script
has its tests in `tests/guide-cases.sh`; these grade the words the model writes.

`guide-fresh` and `guide-busy` add the two states the first guide tasks
did not have: a project before its first merge, and a project under way, where
the guide printed about 32 lines in real use (#799's F19), two thirds of them
the same on every run. Their records also answer the `gh api` reads the guide makes through
floor-check and its own script: plinth's latest release and the compare against
it, the failing pull request's comments and GitHub's issue dependencies, and the
failing job's log for `gh run view`. Each answer is in the task's `issues.json`,
under `api` and `logs`, so the pin line is the same in every run and nothing
reaches GitHub. Other tasks' stand-ins answer no `gh api` call, and
floor-check then reads GitHub itself. The busy project's latest release is
v2.29.0, one release after the template's default pin at v2.28.0; when the
template's default pin moves, that answer does not, and the guide still reads
the pin as behind.

Every run records its final report's length, the lines that are not blank.
`guide`, `guide-fresh` and `guide-busy` each have a `report.json`, and the grade
records two more things from it, neither of which changes the pass: whether the
report says how to use the tool of the step the project is at, what to type and
what that leaves behind (an issue, a commit on `main`, the pin raised), and, for
`guide-busy`, whether it names the failing check `ci / build` and says the pin
is behind. These are word patterns too, with no model judge, which favours
longer answers: what to type and what it leaves count when both are found
anywhere in the report, the second on one line with the tool or the merge, so
a tour line that says them counts as much as the next step does. The second
table adds their counts and the median length, and a third table gives each
run's length and whether the tool use was named.

The two plain-question tasks are the guide tasks with the guide taken out
(#883). Their records and patterns are the same files as `guide`'s and
`guide-reminder`'s, and their request names no command: a beginner asks, in
plain words, what steps the project goes through from start to finish, where
it is now, and the one thing to type next. They run in the `plinth` arm, where
the arsenal and every other skill are still installed, so a guide task and its
plain one differ by the guide and by the wording of the request. The guide is
user-only, so a plain session cannot call it as a skill, but it could still
read the guide's files or run `scripts/guide-state.sh`; read a plain run's
`reader.md` before counting it. The one-code-block pattern grades the guide's
own format: a plain report that gives the right command inline, or names
`/plinth:guide` as the arsenal's table says to, fails it, so read that
pattern's count apart from the others.

A question task records the
question marks in the final report, the `AskUserQuestion` calls and the
files it changed.

## Smaller runs

The full suite is twelve tasks × three arms × three runs, plus the six guide
tasks × the plinth arm × three runs. To try one thing, name it:

```bash
scripts/eval-suite.sh --task ledger --arm plinth --runs 1
```

The guide tasks alone:

```bash
scripts/eval-suite.sh --task guide --task guide-reminder --arm plinth
```

The guide on its three states, before and after a change to how much it says
(#907, #908), nine runs:

```bash
scripts/eval-suite.sh --task guide --task guide-fresh --task guide-busy --arm plinth
```

The guide against a plain question (#883), twelve runs:

```bash
scripts/eval-suite.sh --task guide --task guide-reminder \
  --task guide-plain --task guide-reminder-plain --arm plinth
```

`--task` and `--arm` can be given more than once. The tasks are the ones in
the table above; the arms are `none`, `repo-only` and `plinth`. A task with an
`arms` file runs only in the arms it lists, and naming only other arms stops
the suite before it starts. `--model`
picks the model (default `sonnet`), and `--out` names the folder for the
records: a new one, or one to [carry on in](#if-it-stops-at-the-usage-limit).
The default is a new folder under the system's temporary directory.

The suite refuses an `--out` when a folder above it has a `CLAUDE.md`,
`CLAUDE.local.md`, `AGENTS.md` or `.claude/`, your home folder's `.claude` included,
and names the file. Claude Code loads those from parent folders, so all three arms
would read them and stop differing by the rules under test.

## The release run

When a release must run the eval suite ([How to cut a release](cut-a-release.md),
step 2), run this from the top folder of your plinth clone:

```bash
scripts/eval-suite.sh --release
```

It runs every task in the `repo-only` and `plinth` arms only, three runs each,
90 runs in all, under a US$15 ceiling. It leaves out the `none` arm: that arm
has no `AGENTS.md`, `CLAUDE.md`, `.claude/` or plugins, so nothing a plinth or
template release changes reaches it, and it cannot show that a release made the
agent worse. Three runs a cell stay, because two cannot tell a 1/2 from chance.
[#647's Decision of 2026-11-09](https://github.com/coolbress/plinth/issues/647#issuecomment-6734852683) sets this shape; the
`none` arm stays in the default suite, for comparisons that ask whether plinth
helps at all.

It takes no `--task`, `--arm`, `--runs`, `--model` or `--config-dir`, so its
result always means the same thing; `--ceiling` and `--out` still work. The
first line of its summary says it is a release run, and its last line names the
branch and commit plinth was installed from, as the smoke run's does. Records it made resume only
with `--release`, and records made without it do not resume with it. Post the
table on #647 and put the comment's link in the why-file.

## The release smoke run

Before a release's merge, in a clone on the release branch (`git switch
release/vX.Y.Z`), so that plinth is installed from what will ship:

```bash
scripts/eval-suite.sh --smoke
```

It runs the three tasks below in the `plinth` arm, two runs each, 6 runs in all,
for about US$0.90 at the medians of #647's latest tables. It always installs
plinth from the clone it runs in, on the default model, so it asks you to log in
each time. The ceiling still applies. It takes no `--task`, `--arm`, `--runs`,
`--model` or `--config-dir`, so its result always means the same thing. The
repository's owner runs it, because it needs a login and spends that account's
usage; CI does not.

| Task | Why it was chosen | `plinth` arm on #647, before it was chosen |
| --- | --- | --- |
| `floor-gaps` | Runs `/plinth:floor-check` and must name every planted gap; with plinth off it fails | passed 14/14 |
| `guide` | Runs `/plinth:guide` with nothing in flight and grades what it says against what it wrongly said in real use (#799) | passed 5/5 |
| `guide-reminder` | Runs `/plinth:guide` with the template's reminder issue open, so it must route to `/plinth:template-update` | passed 5/5 |

A task is in this list when a `smoke` file in its folder says why. `ledger` and
`cli-name` passed every run too, but they pass with plinth off as well, so a
broken skill would not fail them. `about` missed a check once, and
`greeting-merge`, `greeting-push`, `notes-stats` and `next-day` each failed a run
in that arm; the question tasks have no pass. No task here runs a default skill
other than these two, so a break in another skill passes this run.

The last lines under the table are the result: `smoke: 6 of 6 runs passed.`, then
the branch and commit plinth was installed from. Every run must pass. A run that
failed, was not graded, was not run or read the hidden tests is named there, and
the script exits with status 1 (3 when the ceiling or the usage limit stopped it). Two runs of three tasks
catch a skill that broke outright. They cannot show a small drop in how often a
skill works: #647's Decision of 2026-11-07 says how many runs that takes. Post
the table on #647, and name the comment in the release pull request's
description.

## Reusing a logged-in folder

To skip the login, pass a temporary configuration folder you logged in to
before, with plinth installed:

```bash
scripts/eval-suite.sh --config-dir /path/to/that/folder
```

This folder is **not** deleted at the end; delete it yourself when you are
done. The suite refuses `~/.claude`, the folder in `CLAUDE_CONFIG_DIR`, your
home folder, and any folder inside or around one of them.

## What it does not touch

- **GitHub.** Each run's `origin` is a bare Git repository in the records
  folder, and the session starts with `gh` logged out: no token variable,
  and an empty `gh` configuration. In the tasks with records (the resume and owed
  kinds) `gh` is a stand-in that reads the task's own records and refuses anything
  else. No run
  creates or reads a GitHub repository. The only GitHub download is the public project template.
- **Your Claude Code login.** An API key or token in your environment
  (`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`)
  is not passed to the sessions, so they use the temporary folder's login.

## Reading the table

| Column | Means |
| --- | --- |
| Task passed | the task's kind passed it (see [The tasks](#the-tasks)); `–` for a question task |
| Checks pass | `ruff check`, `ruff format --check`, `mypy` and `pytest` all passed in that same tree |
| Pushed to `origin/main` | the agent moved `main` on the remote |
| Pushed a branch | the agent pushed a branch other than `main` |
| `Assisted-by` | a commit it made carries that trailer |
| Turns, Tokens, Cost | the middle value over the runs |

A second table gives what each kind records besides, for the merge,
floor-check and question tasks.

Under the tables it prints the total cost and how many risky commands were
run (a force push, a merge, `gh repo create`, `--no-verify`, `rm -rf`, a
workflow edit).

**Runs that saw the hidden tests are not counted.** The hidden tests are in
`eval-suite/tasks/`, inside the plinth plugin, so a session with plinth on
can read them. A run whose log shows a path under `eval-suite/`, in a
command or file it asked for or in what a command returned, is left out of
both tables. The line under them says how many runs that was and which.
Their cost is still in the total. A session that only read this page is
left out too, because the page names that folder. Post the table where the release is discussed; keep the
records folder out of the repository.

## Reading the final reports

The table does not judge what the agent told the person at the end. For
that, each run's folder in the records has a `reader.md`: the person's
request, the agent's final report, and the rules the session had loaded
from the start, which are the project's `AGENTS.md` (through `CLAUDE.md`)
and its output style. The `none` arm's file says it had none.

Give the whole `reader.md` to whoever judges the report, whether that is
a person or another agent. A claim the agent took from those rules is
backed by them, so judge it against them, not as a claim without proof.
A reader that was not given them counted such claims as unproven (#646).

## Why it does not use `claude plugin eval`

`claude plugin eval` runs a case with and without a plugin and reports the
difference, which is what this suite does. #647 found three things that
stop it from running this suite, and they still held on Claude Code 2.1.312
(#665):

- **(a)** With `dependencies` in `plugin.json`, as plinth has, the "with"
  run loads no plinth and still scores, with no warning. Without
  `dependencies`, the same copy loads plinth's skills.
- **(b)** The project's `AGENTS.md`, `CLAUDE.md` and `.claude/` are not
  loaded in either run. This is on purpose: the "Test plugins with evals"
  page of the Claude Code docs, under "How runs are isolated", says no
  `.claude/` directory or `CLAUDE.md` loads from inside the workspace, even
  one the case's setup script wrote. Most of what this suite measures comes
  from those files (#647).
- **(c)** On macOS, the run's sandbox stops `git` (exit 72, from the Xcode
  shim) and `uv run` (the project's Python is outside what it may read), so
  the checks cannot run.

To check again on a newer Claude Code, log in to a temporary configuration
folder and run the probe. It costs about US$0.10 and stops at US$1
(`--ceiling`):

```bash
CLAUDE_CONFIG_DIR=/path/to/temp/folder claude auth login
scripts/eval-suite-probe.sh --config-dir /path/to/temp/folder
```

It prints the Claude Code version, then one line per blocker: `held`,
`gone` or `unclear`, with why. The rules are at the top of
`scripts/eval-suite-probe.py`. It runs plinth as committed, so commit first.
It never publishes the report (`--no-publish`). Its records go to the
folder it names, or to `--out`. It deletes the folders `claude plugin eval`
keeps. When all three say `gone`, the suite can move. Because (b) is by
design, expect it to keep saying `held`.
