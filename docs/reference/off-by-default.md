# Off by default

What a project made by `/plinth:new-project` starts with turned off, when each
is worth turning on, and where the steps are. `/plinth:new-project` prints
these as its last lines and `/plinth:guide` says them, both from the table
below through `scripts/off-by-default.sh`; an item added here reaches both.
The guide says every item until the project's first pull request by a person
is merged, or when asked with `/plinth:guide map`; after that, how many
there are, and by name only a step its line says to do now.
The guide gives "How an item is sorted" as its reason, in these words.

## How an item is sorted

Every item `/plinth:new-project` could set up falls in one of four places,
and a new item is placed by this rule before it is built. A safety or
quality floor (the ruleset, the checks, a security policy) is installed
without asking, and where the owner already publishes their own version, in
their `.github` repository, theirs wins and plinth renders none: secure by
default, as [CISA's Secure by Design](https://www.cisa.gov/securebydesign)
asks, in the order GitHub itself reads
[community health files](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file).
Otherwise, a choice a person can judge on day one (the kind of project, its
license, whether a code reviewer is connected) is asked in plain words, with a
default that is right for most and one "use the recommended defaults?"
question in front of the rest, as [clig.dev](https://clig.dev/#interactivity)
and [create-next-app](https://nextjs.org/docs/app/api-reference/cli/create-next-app)
do; a flag that gives the answer is never asked. A choice they cannot judge
yet starts off and is told, in the list below, with when it is worth turning
on and how ([progressive disclosure](https://www.nngroup.com/articles/progressive-disclosure/)).
What plinth cannot do for them, because it needs an account outside the
repository, is named with its link, as the Codex settings row below is.

## The list

| Feature | Archetypes | Turn it on when | Steps | On when the project has | Listed only when the project has |
| --- | --- | --- | --- | --- | --- |
| The third-party reviewer (`third-party / review`) | all | a code reviewer such as Codex's is connected to your GitHub account | `docs/how-to/configure-the-third-party-reviewer.md` | `.github/workflows/third-party.yml` | - |
| Turn on Codex code review for this repository in your Codex settings, `https://chatgpt.com/codex/settings/code-review` | all | now: until it is on, `third-party / review` waits 20 minutes on each pull request and then fails; it does not block the merge | `docs/how-to/configure-the-third-party-reviewer.md#1-enable-the-reviewer-on-the-repository` | - | `.github/workflows/third-party.yml` |
| The summons token (`SUMMONS_TOKEN`) | all | the reviewer does not start on its own once a pull request is ready | `docs/how-to/configure-the-third-party-reviewer.md#summoning-the-reviewer` | - | `.github/workflows/third-party.yml` |
| Requiring the third-party reviewer (`third-party / review` in the ruleset, through `scripts/upgrade-ruleset.sh`) | all | it has reported on a pull request and you want no merge without it; the command needs repository administration | `docs/how-to/configure-the-third-party-reviewer.md#3-make-it-part-of-the-wall-optional` | - | `.github/workflows/third-party.yml` |
| Immutable releases (a published release's files and tag can never change) | cli,library,backend,data-ml | the project publishes GitHub Releases others download, and you accept that a tag name, once released, can never be used again | `docs/how-to/turn-on-what-starts-off.md#immutable-releases` | - | - |
| A support file (`SUPPORT.md`) | all | people ask for help in issues and you want to say where help is | `docs/how-to/turn-on-what-starts-off.md#a-support-file` | `SUPPORT.md` | - |
| Sponsorship (`.github/FUNDING.yml`) | all | you accept money for the project | `docs/how-to/turn-on-what-starts-off.md#sponsorship` | `.github/FUNDING.yml` | - |
| A citation file (`CITATION.cff`) | library,data-ml | people may cite the project in a paper or a report | `docs/how-to/turn-on-what-starts-off.md#a-citation-file` | `CITATION.cff` | - |
| Code owners (`.github/CODEOWNERS`) | all | a second person shares the repository and some paths should be reviewed by a particular person | `docs/how-to/turn-on-what-starts-off.md#code-owners` | `.github/CODEOWNERS` | - |
| Topics, for GitHub's search | all | you want people to find the project in GitHub's search | `docs/how-to/turn-on-what-starts-off.md#topics` | - | - |
| Turning off the wiki GitHub gives every new repository | all | the project's documents live in the repository, and you want one place for them | `docs/how-to/turn-on-what-starts-off.md#turning-the-wiki-off` | - | - |
| HSTS preload and include-subdomains | web | every subdomain answers over HTTPS (include-subdomains), and you accept that preload takes months to undo | `README.md` "HSTS preload and include-subdomains are off" | - | - |

The columns, as the script reads them:

- **Archetypes**: `all`, or the archetypes it applies to, comma-separated
  (`web`, `backend,web`). Another archetype is not told about it, and a
  project whose answers record no archetype is told only the `all` rows.
- **Steps**: a page in this repository (`docs/…`, with a `#heading` anchor
  or without), printed as its link; or a
  file in the project followed by a phrase that file contains, quoted, which
  `tests/off-by-default-cases.sh` reads in the template at the pinned tag.
- **On when the project has**: a path in the project whose presence means the
  feature is on, so neither the creation's last lines nor the guide list it;
  `-` when nothing in the project says so, and the guide says it started off.
- **Turn it on when**: when it begins `now:`, the row is a step to take
  right away rather than when it is needed: the feature cell says the step,
  the rest says what happens until it is done. `/plinth:new-project` prints
  such rows first, under "to do now".
- **Listed only when the project has**: a path that must be in the project
  for the row to be told at all, `-` for none. The rows that need the
  reviewer's caller are what a project made with the reviewer turned on still
  has to do: it reports from the first pull request and is not required
  (#765). Without a project directory these rows are left out.

A GitLab project gets no list: the reviewer and the release workflow are
GitHub workflows, immutable releases a GitHub setting, and `web` is made on
GitHub only.
