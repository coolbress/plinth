# New project: the questions

`/plinth:new-project` asks these, in this order, for each choice its arguments leave out. Use the questions, labels and descriptions as written, translated into the person's language; [How to ask](SKILL.md#ask-first-what-the-arguments-leave-out) in the skill says how.

## Contents

0. [The folder](#0-the-folder)
1. [The host](#1-the-host)
2. [What to make](#2-what-to-make)
3. [Follow-ups](#3-follow-ups)
4. [The archetype recommendation](#4-the-archetype-recommendation)
5. [Where a web app or a dashboard runs](#5-where-a-web-app-or-a-dashboard-runs)
6. [The name](#6-the-name)
7. [Who may see the project](#7-who-may-see-the-project)
8. [Every answer in one table, before anything is created](#8-every-answer-in-one-table-before-anything-is-created)

## 0. The folder

Read from `new-project.sh --where` before any other question. For `empty` or
`home`, or when a name argument or `--dir=` is given, or the person said they
want a new separate project, there is no folder question: go on to the host.
The table's `Folder` row then says where the project goes, and, when the
session started in a folder that holds something, that this folder is left
untouched.

For every other value, ask exactly one question, header `Folder`, before the
host. Its recommended choice never writes in this folder and never creates a
repository from it. Inside a repository, name the top folder from `toplevel:`
when it is not the folder the session started in: the question is about the
enclosing project, naming the top folder, and a new project never goes
inside it.

| `folder:` | Question | Choices, recommended first |
| --- | --- | --- |
| `files` | "This folder has files but is not a repository. A new project is made separately, and this code is not moved." | New separate project (Recommended) · Put this code on GitHub or GitLab first, then add plinth · Cancel |
| `git-no-remote` | "This folder is a git repository with no GitHub or GitLab remote." | New separate project (Recommended) · Publish this repository, then add plinth · Cancel |
| `git-remote <host> <path>` | "This folder is `<path>` on `<host>`, a repository plinth did not make." | Check it and add plinth's files by pull request (Recommended) · New separate project · Cancel |
| `git-remote-other <host>` | "This folder is a git repository on `<host>`, which plinth does not serve." | New separate project (Recommended) · Cancel |
| `plinth-made <path> <commit>` | "This project was made by plinth (template `<commit>`)." | Next step in this project (Recommended) · New separate project · Cancel |

What each choice does:

- **New separate project**: the questions go on from the host, as below; the
  project goes in `~/<name>`, outside this folder, and the table's `Folder`
  row says this folder is left untouched.
- **Put this code on GitHub or GitLab first, then add plinth** (`files`):
  print the command for the person to type, in their own terminal or with
  `!`, and never run it yourself. On GitHub: `git init`, `git add -A`,
  `git commit -m "First commit"`, then
  `gh repo create <name> --private --source=. --push`. On GitLab.com, the
  same first three, then `glab repo create <name> --private` and
  `git push -u origin HEAD`. Then `/plinth:floor-check` in this folder.
- **Publish this repository, then add plinth** (`git-no-remote`): print
  `gh repo create <name> --private --source=<top folder> --push` (or the
  two GitLab.com lines above), then `/plinth:floor-check`.
- **Check it and add plinth's files by pull request** (`git-remote`): print
  `/plinth:floor-check` for the person to type in this folder.
- **Next step in this project** (`plinth-made`): print `/plinth:guide` for
  the person to type in this folder.
- **Cancel**: nothing is made; say so in one line.

Inside a repository, every hand-off is run from its top folder, the
`toplevel:` path: `/plinth:floor-check` and `/plinth:guide` read the folder
they are typed in as the repository's root, and from a subfolder they report
files missing that the top folder has. When the session started below it,
print `cd <top folder>` first, written out, and say that the command is
typed in a session started there.

Every choice but **New separate project** ends the turn with the printed
command, and runs no preflight and asks nothing more. A hand-off is a
command the person types: never call the Skill tool for `/plinth:floor-check`
or `/plinth:guide`, and never run `git init` or `gh repo create` for them.
In text with no answer (a `claude -p` run with no reply), the folder
question ends as Cancel, unless the person asked for a new separate project.

## 1. The host

Asked when there is no `--host`. Header `Host`: "Where should the
repository live?" Each choice carries its readiness line from
[Check first](SKILL.md#check-first-before-any-question).

| Label | Description |
| --- | --- |
| GitHub (Recommended) | ✓ or ✗ and its readiness. A GitHub repository with the wall; every kind of project, the web app included (`--host=github`). |
| GitLab.com | ✓ or ✗ and its readiness. A GitLab.com project with its wall; needs `glab` installed and logged in. The web app is made on GitHub only. On GitLab.com the next-step guide is partly manual: `/plinth:guide` reads GitHub only, and the project's `AGENTS.md` names where the next work is instead (`--host=gitlab`); `/plinth:template-update` serves it, ending in a draft merge request. |

Then run the preflight for that host, as
[Check first](SKILL.md#check-first-before-any-question) says, before the next
question.

## 2. What to make

Asked when there is no `--archetype=`, in text (it has no
choices): "What do you want to make? A sentence or two in your own words
is enough; \"I don't know\" is an answer too." Keep the answer: the
archetype's reason quotes it, the names translate it, the visibility
reads it, and the table of step 8 shortens it into the description and
names its language as the records language. With `--archetype=` given, steps 2, 3 and 4 are not asked.

## 3. Follow-ups

Asked only when the answer to step 2 leaves the archetype open
(it fits two kinds, says too little, or is "I don't know"); one that names
what is made asks none. A description about charts, graphs, a dashboard or
seeing data ("see my sales as charts", "see my data") names it: `dashboard`.
Ask only what decides between the kinds still open:

- Header `Use`: "How will it be used?" **Someone runs it, in a terminal or
  on a schedule** (cli). **Other code imports it** (library). **It keeps
  running and answers requests** (backend). **People open it in a
  browser** (web or dashboard; then `Login`).
- Header `Login`: "Do people log in and keep their own data in it, or only
  look at tables and charts?" **They log in** (web; on GitLab.com, say it
  is made on GitHub only). **Only look at tables and charts** (dashboard).
- Header `Model`: "Does it train a machine-learning model here?" **Yes**
  (data-ml). **No**: collecting, cleaning or processing data with no model
  trained is cli.
- A schedule word ("daily", "every hour", "every morning") names `cli`
  and decides where it runs, not the kind. On GitHub, a description that
  says the computer is off ("even when my laptop is off", "while I sleep")
  recommends `cli` with `--scheduled-run`: GitHub runs it on a schedule and
  keeps each run's results as a download on the run's page. One that says
  "run it on my machine" or "on my computer" recommends `cli` with
  `--no-scheduled-run`: it runs only while the computer is on, started by a
  scheduler there (cron, launchd) that plinth does not set up. One that says
  neither asks header `Schedule`: "Should it keep running on GitHub while
  your computer is off?" **On GitHub on a schedule** (`--scheduled-run`).
  **Only on my computer** (`--no-scheduled-run`). On GitLab.com it is not
  asked: say it runs on the computer only, since a GitLab pipeline schedule
  was not tried. With `--archetype=cli` given and neither flag, nothing is
  asked and it runs on the computer only, the default.

## 4. The archetype recommendation

Asked with header `Kind`: "I recommend `ARCHETYPE`:
`REASON`. It makes `MAKES`; it does not make `NOT`." `REASON` is one line
quoting the person's words from step 2; take `MAKES` and `NOT` from the
table below, as written there. Never choose for them in silence: the
person always picks.

| Label | Description |
| --- | --- |
| Use `ARCHETYPE` (Recommended) | Make it as this kind (`--archetype=ARCHETYPE`). |
| Another kind | See the other kinds and pick one. |
| Not sure | Start with the narrowest, a terminal command (`--archetype=cli`); a kind can be changed later, with some work. |

For `cli` with a scheduled run, the recommendation names it: "I recommend
`cli`, run on GitHub on a schedule (`--scheduled-run`): `REASON`", with
`MAKES` and `NOT` from the table's `cli, on a schedule` row.

Until plinth has them, add one sentence for the gap the description falls
into: `cli` runs only on the person's computer unless it runs on GitHub on
a schedule; a bot needs a place to run, and that costs money. For `dashboard`, say also that it runs on their
computer, has no login, and that where it runs is asked next.

| Kind | Makes | Does not make |
| --- | --- | --- |
| cli | A command people install and run in a terminal; on GitHub a release only when a tag is pushed. | A server, a web page, or anything that runs by itself away from the person's computer. |
| cli, on a schedule | The same command, also run on GitHub every day and by hand, even while your computer is off; each run's results are a download on the run's page, kept 90 days, never a commit. GitHub only. | A run at an exact time: a run can start late, or be dropped, when GitHub is busy. |
| library | A package other code imports. | A command, a server or a web page. |
| backend | A service in a container that keeps running and answers requests. | Web pages with logins, or a place to run it. |
| data-ml | A model trained here, with a model card; on GitHub a `v*` tag publishes the model, its metrics and the card. | A server that answers with the model, or data collected on a schedule. |
| web | A web app with logins and a Postgres database, on GitHub only. | A light page with no logins; it costs money to run. |
| dashboard | A page of tables and charts, made with Streamlit, that runs on your computer; it can go online on Render, GitHub only. | Logins or a database: online, anyone with its address can read it. |

**Another kind** asks header `Kind` again with the kinds below other than
the one recommended, at most four: on GitLab.com leave out `web`; on GitHub,
when that leaves five, leave out `library` (or `cli`, when `library` is the
one recommended) and say in one line that it can be typed under Other. When
the `Use` follow-up was asked, it is not asked again: this list is the
next step after it, not a repeat. Every kind gets the same checks besides
(title, lint, types, tests, build, secrets, dependencies, change size, the
project's own setup) and CodeQL; say so only if asked.

| Label | Description |
| --- | --- |
| A terminal command (cli) | A command people install and run in a terminal; also the choice for a tool that runs on a schedule on the owner's machine (a data collector, a pipeline), or on GitHub while that machine is off (`--scheduled-run`). On GitHub its release workflow runs only when a tag is pushed (`v*`, or a member's `<prefix>-v*`), so a project that never tags publishes nothing. If you are not sure, choose this one. |
| Code other code imports (library) | A package other code imports. |
| A service or API (backend) | A service that keeps running and answers requests, in a container. It also checks that its container builds and starts. |
| A model you train (data-ml) | A model trained here, with a model card. On GitHub a `v*` tag publishes the model, its metrics and the card as release files. It also checks the container, and comes with a test of the training. Data processing, collection or a pipeline with no model trained is `cli`. |
| A website people log in to (web) | A web app with logins and a database, on GitHub only. It costs money to run: about US $13 a month on Render. It also checks the container, the database changes and the production settings. |
| A page of tables and charts (dashboard) | A page that shows your data as tables and charts, made with Streamlit. It runs on your computer, free, with no login and no database. It can go online on Render, about US $7 a month, GitHub only; there anyone with its address can read it. Its test opens the page with no browser. |

Right after the archetype is set, say its prerequisites in one line, with
the month's total, each figure with its link and the date it was read:

- Every kind: the agent's plan, Claude Pro, US$20 a month (US$17 a month
  billed yearly; [Claude pricing](https://claude.com/pricing), read 2026-11-26).
- `web`: also a Render account and about US $13 a month, a US$7 web service
  and a US$6 Postgres ([Render pricing](https://render.com/pricing), read
  2026-11-26), so about US$33 a month in all; where it runs is asked next.
- `cli`, `library` and `data-ml`: no host cost; US$20 a month in all.
- `cli` on a schedule: also no host cost, US$20 a month in all. In a
  public repository GitHub's runners are free; in a private one the runs
  use the plan's included Actions amount, on GitHub Free US$12 a month and
  500 MB of artifact storage
  ([GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions),
  read 2026-11-27). The results are a download under Artifacts on each
  run's page, kept 90 days; in a public repository GitHub turns the
  schedule off after 60 days with no activity, and README.md says how to
  turn it back on.
- `dashboard`: no host cost on the person's computer, US$20 a month in all;
  on Render about US$7 a month more, a web service
  ([Render pricing](https://render.com/pricing), read 2026-11-27), so about
  US$27 in all; where it runs is asked next.
- `backend`: no host cost until its image runs somewhere, which then costs
  what that place charges; US$20 a month until then.

Nothing else is needed beyond what the preflight checked. On a private
GitHub repository, CI minutes can add to it (step 7).

## 5. Where a web app or a dashboard runs

Only for `--archetype=web` on GitHub, and only when the arguments carry no
`--hosting=`: before running the script, ask the person this, in these words,
and wait for the answer. For any other archetype, or with `--host gitlab`,
do not ask it and do not pass `--hosting`.

> **Where will your app run?** Before you choose, you can read what each
> place costs and what it leaves to you:
> <https://github.com/coolbress/plinth/blob/main/docs/how-to/choose-where-a-web-app-runs.md>
>
> 1. **Render — recommended.** About $13 a month. It puts your app online at
>    a secure `https://` address (the padlock in the browser), puts out a new
>    version only after the project's automatic tests pass, and can bring your
>    data back as it was at any moment from 3 days ago up to 10 minutes ago.
>    plinth has tried every step of this.
> 2. **Another hosting service** (Railway, DigitalOcean, Fly.io). From about
>    $10 to $42 a month. Similar, but plinth has not tried them: some put out
>    a new version even when its tests fail, and on some, backups stay off
>    until you switch them on.
> 3. **A server you rent.** From about €6 a month for more power, but keeping
>    it updated, secure and backed up is your job every month.
> 4. **A computer at home.** Free to try on your own network. Putting it on
>    the internet is the riskiest choice: anyone can reach it, a flaw can lead
>    into your home network, and your data is only as safe as the backups you
>    make yourself.
>
> plinth sets up and checks only Render. Choices 2, 3 and 4 are places plinth
> does not deploy to for you and has not checked: the project's README will
> have the steps, and doing them is up to you.

If they pick 2, ask which one:

> 1. **Railway.** About $10 a month, an estimate. Backups are off until you
>    switch them on.
> 2. **DigitalOcean App Platform.** About $20 a month. Daily copies of your
>    data are kept for 7 days.
> 3. **Fly.io.** About $42 a month, most of it for the database.

Then add one argument: `--hosting=render` (1), `--hosting=railway`,
`--hosting=digitalocean` or `--hosting=fly` (2), `--hosting=vps` (3) or
`--hosting=home` (4). If the person does not answer, says they do not know, or
asks you to choose, use `--hosting=render`. Never pick another place for them.

For 3 or 4, before running the script, say this once more:

> One rule matters most on your own server or home computer. A port is a
> numbered door through which the internet reaches one program on the
> computer; a proxy is a program that takes every visitor's connection first,
> handles HTTPS, and passes the visit on to the app. Never open the app's own
> port (8000) to the internet without a proxy in front of it, and never open
> the database's port (5432) at all. The README's steps show how.

A template that does not ask this question yet makes the script stop for 2,
3 or 4 before anything is created; show that message as it is.

For `--archetype=dashboard` on GitHub with no `--hosting=`, ask this instead,
in these words, and wait for the answer. On GitLab.com do not ask it: the
page runs on the person's computer there, and Render was not tried.

> **Where will the page run?**
>
> 1. **On your computer — recommended.** Free. Only you see it, at a local
>    address, while it runs.
> 2. **Render.** About $7 a month. It puts the page online at an `https://`
>    address. **The page has no login: anyone with its address can read it,
>    and the data it shows.**

Then add `--hosting=local` (1) or `--hosting=render` (2). If the person does
not answer, says they do not know, or asks you to choose, use
`--hosting=local`.

## 6. The name

Asked when the arguments carry none. Header `Name`: "What should
the repository be called?" Offer two or three names in ASCII that
translate what step 2 means, short, lowercase, with `-` between words: a
translation, not a romanization of the person's words, since `gh` and
github.com turn every letter outside ASCII into `-`. When step 2's answer
gives nothing to translate ("I don't know"), suggest plain names for the kind
instead, such as `my-tool` for cli, checked the same way. The picker's own Other
takes a typed name; add no choice for it. Say in one line that
`owner/name` puts it under an organization. The name is at most 46
characters, the owner not counted: the new project's Python package takes
the same name, and from 47 characters lines of its code pass the 100 its
own lint check allows. When step 2 was not asked (`--archetype=` given),
ask the name in text, with no suggestions.

Before showing a suggestion, check it, and check a typed name as soon as it
is given:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/new-project.sh <name> --check --host=<host> --archetype=<archetype> $ARGUMENTS
```

with the arguments as typed after the name, so a `--dir=` or `--license=`
given there is checked as the run will use it.

It runs every check the run makes before it renders, reads only, and
creates nothing: the name rules, the 46 characters, the names the chosen
archetype's template refuses (read from the pinned template's
`copier.yml`, such as `train` for data-ml), a name already taken, a folder
already there, and the owner (an organization the login is not a member
of). Exit 0 ends with `check: ok`. Show only suggestions that passed; when
fewer than two pass because of the name (taken, refused, too long, a
folder in the way), find others and check them. A stop that is not about
the name (the tools or login, the template's tag, an owner that cannot be
read, the network) is the same for every name: show it and explain it as
[What the script printed](SKILL.md#what-the-script-printed) says, and suggest no
more names until it passes. A typed name that stops is shown and
explained the same way, and the name is asked again.

## 7. Who may see the project

Asked when neither `--public` nor `--private` is
given: ask it alone, before the table, since it decides the license
recommended, what the wall can hold on the account's plan and who can read
the code. Header `Visibility`: "Who may see this project's code?" On
GitHub, list **Anyone on the internet (public) (Recommended)** first: GitHub
Free cannot keep the ruleset on a private repository. When step 2 signals
data that should stay private (a company's or a customer's, a household
budget, health, anything personal), list **Only people you add (private)
(Recommended)** first instead and say why, quoting those words. On
GitLab.com, private is recommended.

| Label | Description |
| --- | --- |
| Anyone on the internet (public) | Anyone on the internet can read and copy the code. On GitHub, the whole history, the issues and the Actions logs are public too, and a fork made while it is public stays public if the repository is made private later ([GitHub Docs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility), read 2026-11-26); the license recommended is MIT. On GitHub the whole wall stands on every plan. On GitLab.com, anyone can read it. |
| Only people you add (private) | Only you and the people you add can read it; the license recommended is Proprietary. On GitHub Free a private repository cannot keep the ruleset, so plinth stops before creating it; on a paid plan it has no CodeQL or push protection unless the account has GitHub Code Security and Secret Protection; on a personal account, plinth reads the plan first, which needs the `read:user` permission on your GitHub login (it says the command that adds it). On GitHub, CI then runs on the plan's Actions minutes: each run is 13 jobs (14 for `backend`, `data-ml` and `web`), each billed as at least one minute, so about 13 to 15 billed minutes for a small `cli` or `library` project and more for the other kinds, whose container, database and web checks take longer; an edited title or description runs it again. GitHub Pro includes US$18 a month, about 3,000 Linux minutes at US$0.006 ([runner pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing), [Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions), read 2026-11-26): at 3 to 5 runs a pull request, roughly 40 to 75 pull requests a month for a `cli` or `library` project, fewer for the others; an estimate, not measured on a private repository. On GitLab.com this is plinth's default, since the free plan protects a private project's main branch. |

The answer becomes `--public` or `--private`, on either host. On GitLab.com,
leave out the GitHub sentences; on GitHub, the GitLab.com ones. In text,
the same question with the two choices numbered.

For private on GitHub, read the plan now, not at the end: run the check of
step 6 again with `--private`. When it stops because the plan cannot keep
the wall (GitHub Free), ask header `Plan`: "Your plan cannot keep the wall
on a private repository. What now?" **Public instead** (`--public`, the
whole wall). **Upgrade the plan and start again**: GitHub Pro for a
personal account, Team for an organization; then type
`/plinth:new-project` again. **Stop**: nothing is created. When it stops
because the token cannot read the plan, show its fix in the `!` form and
run the check again once the person says it is done. When it passes with a
`plan: not verified` line, the plan could not be read and GitHub decides
at the ruleset: show the line, say that if GitHub refuses the ruleset the
repository is deleted again, and ask the same `Plan` question with
**Private anyway** in place of the upgrade.

## 8. Every answer in one table, before anything is created

In a chat
there is no Back button: the table is the way back, so it holds every
answer, the two that cannot be taken back (the name and the visibility)
among them. The answers the questions above left open take their
defaults. On GitHub, when neither `--code-of-conduct=` nor
`--no-code-of-conduct` is given, read first whether the owner already
publishes a code of conduct:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/owner-files.sh [<owner>]
```

with the owner from the name, or nothing for a bare name. A
`code_of_conduct: yes` line means the owner's applies: row 6 says so, it
adds no flag, and **Reviewer and code of conduct** asks the reviewer only,
since the script ignores `--code-of-conduct` then. Any other line (`no`,
or `unknown: …`) leaves row 6 to its default; the script stops on its own
if the lookup fails again.

Before showing the table, check it once with every flag it holds, as
step 6 checked the name:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/new-project.sh <name> --check <flags of the table>
```

with the name once and the table's flags only: each row is a flag, those
the arguments gave included, and a name in `$ARGUMENTS` given again stops
the check (`one name only`).

A stop about the description means the line is still too long: shorten
it and check again. A stop about the records language means it was not
named in English: write it as `Korean`, not `ko` or `한국어`, and check
again. Any other stop is shown and explained as
[What the script printed](SKILL.md#what-the-script-printed) says.

Then show the table, its labels in the person's language and each flag
as written:

| # | Row | Default when not asked | Flag |
| --- | --- | --- | --- |
| 1 | Repository and host | `owner/name` on GitHub, or on GitLab.com; a bare name is shown under the login | `--host=github` or `--host=gitlab`, and the name |
| 2 | Kind | The archetype of step 4, for `web` or `dashboard` where it runs, and for `cli` on GitHub whether it runs on GitHub on a schedule | `--archetype=`, `--hosting=` for `web` or `dashboard`, and `--scheduled-run` or `--no-scheduled-run` for `cli` on GitHub |
| 3 | Visibility | The answer of step 7 | `--public` or `--private` |
| 4 | License | MIT for a public project, Proprietary for a private one | `--license=mit`, `--license=apache-2.0` or `--license=proprietary` |
| 5 | Third-party reviewer | None | `--no-third-party-review` or `--third-party-review` |
| 6 | Code of conduct | None; "the owner's applies (`<owner>/.github`)" when `owner-files.sh` says yes | `--no-code-of-conduct` or `--code-of-conduct=<contact>`; none when the owner's applies |
| 7 | Description | The sentence of step 2, shortened to one line of at most 350 characters in its own language; none when step 2 was not asked or its answer was "I don't know" | `--description=<line>` or `--no-description` |
| 8 | Records language | The language the sentence of step 2 is written in, or the one the person writes in when there is none, named in English (`Korean`, not `ko`) | `--records-language=<language>` |
| 9 | Local folder | `~/<name>`, written out as an absolute path | `--dir=<path>` |

The description is the repository's one line on its page and under the
title in `README.md`. The records language is the language the new
project's `AGENTS.md` asks its issues, pull requests, commit messages and
documents to be written in; headings tools read, commit types and code
stay in English.

On GitLab.com leave out rows 5 and 6, and keep the other rows' numbers:
the reviewer and the code of conduct are GitHub only.

When the visibility is public and the records language is not English,
one line under the table says so: "The issues and pull requests will be
in `LANGUAGE`, on a public page." Say nothing of it otherwise.

Ask, header `Create`: "Create it with these answers?"

| Label | Description |
| --- | --- |
| Create `VISIBILITY` repository `owner/name` (Recommended) | Creates it with every row above. |
| Change some | Pick the rows to change; the table comes back after. |

`VISIBILITY` is `public` or `private`, and on GitLab.com the label reads
"Create `VISIBILITY` project `owner/name` on GitLab.com". No second "are
you sure": the label says what happens, and choosing it runs the script.

**Change some** asks one question, header `Change`, a multi-select:
"Which do you want to change? To change the visibility, the kind or the
host, type it into Other." Its choices are groups of rows:

| Label | Rows |
| --- | --- |
| Name and folder | rows 1 and 9 |
| Records language and description | rows 7 and 8 |
| License | row 4 |
| Reviewer and code of conduct | rows 5 and 6 |

On GitLab.com leave out **Reviewer and code of conduct**, as its rows
are. Only the groups picked are asked, in one
call:

- **Name and folder**: the name of step 6, then the folder (below). A
  new name is checked with the table's check above, the new name in place
  of the old: step 6's command would pass the old one again in
  `$ARGUMENTS` and stop (`one name only`).
- **Records language and description**: header `Description`: "A
  one-line description for the repository's page and its README?" **Keep
  it**: the row's line. **None**: `--no-description`; it can be added
  later on the repository's page. A line typed into Other replaces it,
  shortened the same way. Then header `Records`: "Which language should
  the project's issues, pull requests and documents be written in?"
  **Keep `LANGUAGE`**: the row's. **English**:
  `--records-language=English`. Another language typed into Other is
  named in English and becomes `--records-language=<language>`.
- **License**: header `License` (below).
- **Reviewer and code of conduct**: headers `Reviewer` and `Conduct`
  (below), `Conduct` left out when the owner's applies.

A code of conduct turned on asks its report contact before the table
returns, in text, since it has no choices: "Where should reports under
the code of conduct go? An email address or a web page; anyone who can
read the repository can read it." The answer becomes
`--code-of-conduct=<answer>`. An empty answer is asked again.

The visibility, the kind and the host are changed by what is typed into
Other ("make it private"), which goes back to that question: step 7, step
4 (and step 5 for `web` or `dashboard`), or step 1 with its preflight and the name's
check again. A visibility changed this way asks the license again, with
the new recommendation first. A host changed this way drops or adds the
rows only GitHub carries. "Stop" ends it, with nothing created. A typed
answer that is none of these is asked again.

Then show the table again, each changed row marked "(changed)" after its
value, and ask header `Create` again.

A row changed at the table replaces its flag among the arguments: the
check, the run and the command said before it carry the new flag only,
never both (`--public` and `--private` together stop the script). The
name is replaced the same way: one name, the new one.

When the arguments give every row, show the table and ask nothing: the
command said before an earlier run asks no question when typed again.

In text (a `claude -p` run, or a call with no answer), show the same
numbered table, then: "Create `VISIBILITY` repository `owner/name`? Type 0
to create it as shown, or the numbers of the rows to change,
comma-separated." Do not number `Create` and `Change some` as choices in text:
the numbers are the rows', and only 0 creates. "Stop" ends it, with nothing created. Each number asks its
row's question in text, rows 1 to 3 going back to their question as
above; then the table again, the changed rows marked.

The questions the groups ask:

- Header `License`: "Which license?" Three choices, each saying what
  it grants; for a private repository list **Proprietary
  (Recommended)** first, for a public one **MIT (Recommended)**.
  **MIT**: anyone may use, copy, change and sell the code, keeping your
  copyright line; short, the usual choice for a public project
  (`--license=mit`). **Apache-2.0**: the same, plus a patent grant; when
  a company or the project you build on asks for it
  (`--license=apache-2.0`). **Proprietary**: grants nothing; nobody
  else may use, copy or share the code without your written permission
  (`--license=proprietary`).
- Header `Reviewer`, on GitHub only, asked as a fact the person knows,
  not a preference: "Is a code reviewer, such as Codex's, already
  connected to your GitHub account?" **No, or not sure (Recommended)**:
  `--no-third-party-review`; the last lines say when to turn it on.
  **Yes**: `--third-party-review`; each pull request gets a
  `third-party / review` result, which reports and is not required, so a
  pull request still merges without it. The last lines then say what to
  do right away: turn the reviewer on for the new repository.
- Header `Conduct`: "Add a code of conduct?" **No (Recommended)**:
  `--no-code-of-conduct`; most small projects start without one, and
  `/plinth:floor-check` does not ask for it. **Yes, the Contributor
  Covenant**: the most used one, version 3.0, written as
  `CODE_OF_CONDUCT.md`; it names where reports of bad behaviour go, so
  its contact is asked next.
- Header `Folder`: "Where should the local copy go?" with
  **`~/<name>` (Recommended)**, a new folder in your home directory
  (`--dir=<home>/<name>`, written out), and, when `--where` said `empty`,
  **This folder** (`--dir=<this folder>`, written out); never the home
  folder itself. Another path is typed into Other and becomes
  `--dir=<path>`. It must not exist yet, or hold nothing at all: the
  table's check stops on a folder with anything in it, `.DS_Store`
  included, and then only `~/<name>` is offered.

A typed answer to `License`, `Reviewer` or `Conduct` that is none of its
choices is asked again.

Every row becomes a flag, a default included, so that the command said
before the run (below) asks nothing when typed again: the host
(`--host=github` or `--host=gitlab`), `--archetype=`, `--public` or
`--private`, `--license=`, `--dir=` with the home directory written out
as an absolute path, the description's, `--records-language=`, and on
GitHub the reviewer's, the code of conduct's (none when the owner's
applies) and, for `cli`, `--scheduled-run` or `--no-scheduled-run`. For `web`, add `--custom-user-model` without asking, unless
the arguments give `--no-custom-user-model`: the new
project starts with its own user model (`accounts.User`), which Django
sets before the first `migrate` and which is changed later only by hand;
the table shows no row for it, and a person who wants Django's
`auth.User` types `--no-custom-user-model` as an argument.
