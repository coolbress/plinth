# Off by default

What a project made by `/plinth:new-project` starts with turned off, when each
is worth turning on, and where the steps are. `/plinth:new-project` prints
these as its last lines and `/plinth:guide` says them, both from the table
below through `scripts/off-by-default.sh`; an item added here reaches both.

## The list

| Feature | Archetypes | Turn it on when | Steps | On when the project has | Listed only when the project has |
| --- | --- | --- | --- | --- | --- |
| The third-party reviewer (`third-party / review`) | all | a code reviewer such as Codex's is connected to your GitHub account | `docs/how-to/configure-the-third-party-reviewer.md` | `.github/workflows/third-party.yml` | - |
| The reviewer on this repository (Codex code review) | all | your Codex settings turn code review on one repository at a time: until a review arrives, `third-party / review` waits 20 minutes on each pull request, then fails without blocking the merge | `docs/how-to/configure-the-third-party-reviewer.md#1-enable-the-reviewer-on-the-repository` | - | `.github/workflows/third-party.yml` |
| The summons token (`SUMMONS_TOKEN`) | all | the reviewer does not start on its own once a pull request is ready | `docs/how-to/configure-the-third-party-reviewer.md#summoning-the-reviewer` | - | `.github/workflows/third-party.yml` |
| Requiring the third-party reviewer (`third-party / review` in the ruleset, through `scripts/upgrade-ruleset.sh`) | all | it has reported on a pull request and you want no merge without it; the command needs repository administration | `docs/how-to/configure-the-third-party-reviewer.md#3-make-it-part-of-the-wall-optional` | - | `.github/workflows/third-party.yml` |
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
- **Listed only when the project has**: a path that must be in the project
  for the row to be told at all, `-` for none. The rows that need the
  reviewer's caller are what a project made with the reviewer turned on still
  has to do: it reports from the first pull request and is not required
  (#765). Without a project directory these rows are left out.

A GitLab project gets no list: the reviewer is a GitHub workflow, and `web`
is made on GitHub only.
