# Listed, not installed

Tools plinth names for a job but does not install, what each costs, and the
line that installs it. A table cell marked "(listed)" is one of these.

| Plugin | What | When | Cost | Source |
| --- | --- | --- | --- | --- |
| `mattpocock-skills-extra` | The six other Matt Pocock skills plinth carries: `/ask-matt`, `/grill-with-docs`, `/wait-what`, and `prototype`, `research`, `wizard` | When you want one of them; `/ask-matt` routes to the rest of the set, so it is listed with them. It can also suggest `/implement-spec` or `/pr`, which plinth does not install | ~0.28k tokens always on (3 skills listed), no hooks; same pin as `mattpocock-skills` | [mattpocock/skills](https://github.com/mattpocock/skills) (MIT) |
| `ponytail-skills` | One skill, `/ponytail-audit`, pre-v5 (pin `2ed6c52`): a ranked list of over-engineering to delete, simplify or replace with the standard library or the platform, repository-wide, biggest cut first; bugs, security and performance are out of its scope; applies nothing. Held on purpose: ponytail v5 rewrote it into a full quality audit (bugs, security, scale, missing tests, lean), which repeats the review step | Every week or two, or after a burst of work, if you install it | ~0.15k tokens always on (1 skill), no hooks | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) (MIT) |
| `last30days` | What people said about a topic in the last 30 days | Finding candidates and recent reactions, when you want that research. Not for deciding; verify with `/research` | ~90 tokens always on, ~90k per call, a `SessionStart` hook (~0.4 s) | [mvanhorn/last30days-skill](https://github.com/mvanhorn/last30days-skill) (MIT) |
| `ponytail` | The full ponytail plugin with its hooks: the least-code mode every turn, its review, and the audit too | Only if you want the mode enforced every turn | 3 hooks, ~1k tokens | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) (MIT) |
| `impeccable` | A design with a point of view; writes a product record (`PRODUCT.md`) and a design record (`DESIGN.md`) | A page that should be remembered, when you will answer its questions: five of them and 43 minutes on the page where `taste-skill` asked none and took five (one measurement, 2026-09-12) | Hooks, agents and skills written into the repository (`.claude/`, `.github/`); no plinth pin | [pbakaus/impeccable](https://github.com/pbakaus/impeccable) (Apache-2.0) |
| `claude-security` | Anthropic's security scan of the whole repository, or of the changes, at an effort you choose; other agents try to disprove each finding before it is reported, and it can draft patch files it never applies. Each scan writes a `CLAUDE-SECURITY-<timestamp>/` folder into the repository (the report as Markdown, JSONL and SARIF, a stamp of the commit scanned, and `patches/` when asked), with its own `.gitignore`, so the folder stays out of commits until you delete that file | A scan of the whole repository, which `/security-review` (one diff) and the required CodeQL check do not give: before a first release, or after a large change | Hooks: `UserPromptExpansion` (its banner), `PostToolUse` on `git push` and `gh pr create` (suggests a scan; `CLAUDE_SECURITY_SCAN_TIP=off` stops it) and on its own scripts with `PostToolUseFailure` (usage counts, sent through Claude Code's telemetry), `PermissionRequest` (closes its question after 60 s unanswered); tokens not measured; no plinth pin | [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/claude-security) (Anthropic, all rights reserved) |
| `sentry` | Sentry's own plugin: eight skills (set Sentry up in the app, read an issue's stack trace, alerts, releases) and Sentry's MCP server (`mcp.sentry.dev`, over HTTP), declared in its `plugin.json` | After the first deploy, when the project uses Sentry as the error tracker `${CLAUDE_PLUGIN_ROOT}/docs/how-to/set-four-things-by-hand.md` suggests: read the errors it caught from the session | A Sentry account; no hooks in its tree at `73e5354`, the commit the official marketplace pins; 8 skills in the listing, tokens not measured; no plinth pin | [getsentry/plugin-claude](https://github.com/getsentry/plugin-claude) (MIT) |

`mattpocock-skills-extra` installs with
`claude plugin install mattpocock-skills-extra@plinth` and adds its six
beside the default set's fifteen, none twice; start a new session after it.
`ponytail-skills` installs with `claude plugin install ponytail-skills@plinth`;
an install from before it left the default set keeps it until
`claude plugin prune`. `last30days` installs with
`claude plugin install last30days@plinth` and `ponytail` with
`claude plugin install ponytail@plinth`; nothing in the default set runs a
hook, and these two do. Impeccable is not in plinth's marketplace: run
`npx impeccable install` from the project root, which writes the hooks,
agents and skills above into the repository. Its own marketplace plugin
loaded hooks and agents but did not register its skill on Claude Code
2.1.269. `claude-security` and `sentry` are not in plinth's marketplace
either: install them from Anthropic's official one with
`claude plugin install claude-security@claude-plugins-official` or
`claude plugin install sentry@claude-plugins-official` (in a session,
`/plugin install` with the same name, then `/reload-plugins`); if Claude Code
says that marketplace is not found, run
`claude plugin marketplace add anthropics/claude-plugins-official` first.
Both were read on their repositories on 2026-11-24; adding either to plinth's
marketplace would pin it to a full commit SHA.

`mattpocock-skills` installs 15 of the 27 skills upstream ships, and
`mattpocock-skills-extra` lists 6 more at the same commit. The six in neither
are `setup-matt-pocock-skills`, `grill-me`, `teach`, `to-questionnaire`,
`implement-spec` and `pr`. `/ask-matt` can suggest `/implement-spec` (build a
whole plan at once with several agents) or `/pr` (a pull-request description
in its own shape); plinth installs neither, so type `/implement #N` per
ticket and follow the repository's own pull-request shape instead.
