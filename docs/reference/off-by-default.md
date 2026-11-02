# Off by default

What a project made by `/plinth:new-project` starts with turned off, when each
is worth turning on, and where the steps are. `/plinth:new-project` prints
these as its last lines and `/plinth:guide` says them, both from the table
below through `scripts/off-by-default.sh`; an item added here reaches both.

## The list

| Feature | Archetypes | Turn it on when | Steps | On when the project has |
| --- | --- | --- | --- | --- |
| The third-party reviewer (`third-party / review`) | all | a code reviewer such as Codex's is connected to your GitHub account | `docs/how-to/configure-the-third-party-reviewer.md` | `.github/workflows/third-party.yml` |
| HSTS preload and include-subdomains | web | every subdomain answers over HTTPS (include-subdomains), and you accept that preload takes months to undo | `README.md` "HSTS preload and include-subdomains are off" | - |

The columns, as the script reads them:

- **Archetypes**: `all`, or the archetypes it applies to, comma-separated
  (`web`, `backend,web`). Another archetype is not told about it.
- **Steps**: a page in this repository (`docs/…`), printed as its link; or a
  file in the project followed by a phrase that file contains, quoted, which
  `tests/off-by-default-cases.sh` reads in the template at the pinned tag.
- **On when the project has**: a path in the project whose presence means the
  feature is on, so the guide stops listing it; `-` when nothing in the
  project says so, and the guide says it started off.

A GitLab project gets no list: the reviewer is a GitHub workflow, and `web`
is made on GitHub only.
