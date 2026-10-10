# plinth

For someone who runs a software project through an AI agent and leads it
rather than reads it: you direct the work, read the checks and the record,
and need to know what was confirmed without reading the code.

Gated where a check can. Guided where it can't.

**What makes a project professional when you don't read the code?**
Not the code you won't read: the setup around it, the checks the code has
to pass and a record another person can read.

**How do I get better code out of an agent?**
Small steps the checks can answer, each with something you can see that
proves it done.

**Why not just tell the agent the rules?**
A rule the agent is told holds only while the agent follows it. plinth
configures the host (today GitHub) to require checks before a merge, most of
them established tools and a few plinth's own, and the host refuses the merge
while one is red.

You decide. The checks answer. The record remembers.

<!-- install-block:start -->
```bash
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin marketplace add coolbress/plinth
claude plugin install plinth@plinth
```
<!-- install-block:end -->

Then, in Claude Code, type `/plinth:new-project <owner>/<name>`: it creates
a repository with the checks already required, or says why it could
not. From there,
[run a project](docs/how-to/run-a-project.md) is the loop, stage by stage.

**The limits.** A green check means the properties it asserts hold, not that
the code is right, and a pull request can rewrite its own CI file so that
its checks do nothing ([what green means](docs/explanation/concepts.md#about-what-green-means)).
Anyone whose token has administration on the repository can change the
rules, an agent included when it works with such a token
([who can change the wall](docs/explanation/concepts.md#about-who-can-change-the-wall)).
The host blocks the merge; plinth set it up that way; neither blocks an
agent's actions. A production database, a credential, a spend ceiling and a
deployed app are outside every check
([what plinth does not do](docs/explanation/concepts.md#about-what-plinth-does-not-do));
[four things to set by hand](docs/how-to/run-a-project.md#set-four-things-by-hand-that-no-check-covers)
cover them as guidance, not checks.
No one but the author has used plinth yet. It covers GitHub.com, Python
projects managed with uv, and Claude Code as the harness. An existing
repository is only read, except that one made from plinth's template is
offered template updates as a draft pull request. A private repository needs a paid
GitHub plan, and some protections need more ([about private repositories](docs/explanation/concepts.md#about-private-repositories)).

## What plinth is

The base a vibe-coded project stands on: required checks on GitHub that no
change merges past while they are red, a curated set of agent skills, and a
generator that starts a new repository with both already in place. Most of
the checks run established tools (ruff, pytest, gitleaks, CodeQL and others),
a few are plinth's own, and plinth configures the host (today GitHub) to
require them before a merge, so the host, not plinth, refuses a merge while
they are red.

> **Supported:** GitHub.com public repositories · personal or org owner with
> admin · Python (uv) · new repositories via `/plinth:new-project`; existing
> ones get a read-only `floor-check` · **Claude Code 2.1.274 or newer** as the
> harness (CI installs plinth on that version and on the stable channel; the
> user tasks ran on 2.1.282 and 2.1.283; skills follow the Agent Skills
> format and may load elsewhere, but only Claude Code is tested) · macOS / Linux (Windows via WSL) · tools: `claude`,
> `gh`, `git` (2.37 or newer: on an older one, the macOS system git included, the
> install fails with `index.lock: File exists`; `brew install git`), `uv`.
>
> **Outside:** when a wall cannot be raised (no admin, no `gh` auth, a private
> repository on GitHub Free, personal or organization, where the token reads the
> plan) the tool stops before creating anything and says why; a token that cannot
> read the plan lets the ruleset call decide, and a refused one ends the run. A private repository on GitHub Pro, Team or Enterprise
> gets the same required checks, with CodeQL, dependency review and push
> protection only where GitHub Code Security and Secret Protection are
> enabled; the door names each part it left out and what stands in its place
> ([about private repositories](docs/explanation/concepts.md#about-private-repositories)).
> Other mismatches warn and continue.

## Install, in detail

The first line adds Anthropic's official marketplace. plinth no longer needs
it: its one dependency there now comes from plinth's own marketplace (#477),
and the next change removes the line (#481).

The default set runs no hook. Its skills cost context: Claude Code lists 14
of them for the model and caps the whole skill listing, its own built-in
skills included, at 1% of the model's context window. As `/context` estimates
it, with a 1M-context model all 14 keep their descriptions, about 1,300
tokens. With Haiku 4.5, a 200k-context model, the listing is cut to about
2,000 tokens and 9 of the 14 keep about their name: they still run when
called by name, but Claude is less likely to pick them on its own. The
`skillListingBudgetFraction` setting raises the cap (#255; measured again
for #354 and, on Claude Code 2.1.296, for #469 and #477).

Third-party marketplaces do not auto-update. To move to a new version, run
`claude plugin update plinth`, then `/reload-plugins`. Moving from v1.10.0 or
earlier also takes `claude plugin update taste-skill@plinth` once, before
`/reload-plugins`: the dependency's source changed, and until then it fails to
load (#469). Moving from v1.11.0 or earlier also takes, once and in this order,
`claude plugin install plinth@plinth` and then `claude plugin prune`, before
`/reload-plugins`: `mattpocock-skills` moved to plinth's marketplace under the
same name, and `update` does not install the moved copy. Without the two
commands nothing is lost: the official copy keeps all 25 of its skills, and
plinth reports the missing dependency with the command to run. `prune` removes
the official copy only where it arrived as plinth's dependency; one you
installed yourself stays beside plinth's (#477).

Tutorial: [Getting started](docs/tutorials/getting-started.md).

## What you get

Four skills, prefixed `/plinth:`:

| Skill | Does | Who can call it |
| --- | --- | --- |
| `new-project <owner>/<name>` | Creates a repository with the required checks enforced; if a wall step fails it deletes the repository when the token allows and prints the URL when it cannot | You only: type `/` and pick it. The agent cannot see or run it; an agent saying it is not installed usually means the line was typed as text (`/plinth:arsenal` shows what is installed) |
| `floor-check [owner/name]` | Reads an existing repository against the same floor the CI job checks, the live ruleset, whether it is behind the template plinth is tested with today, and what this machine's Claude Code settings say about the sandbox; lists each miss with one fix; changes nothing | You or the agent |
| `template-update` | Applies the template update `floor-check` reports: runs its `copier update` line in a worktree beside the repository, branched from the verified default branch, and opens a draft pull request; a conflict is left for you to resolve before anything is pushed | You only, and it asks before it writes |
| `arsenal` | Catalog of the tools below: what, when, cost | You or the agent |

Installed with plinth as dependencies, each pinned to a commit except
`mattpocock-skills`, which arrives at whatever version Anthropic's official
marketplace serves; CI checks that version against the tested range
([About pins](docs/explanation/concepts.md#about-pins)):
[mattpocock-skills](https://github.com/mattpocock/skills) (planning to review),
[taste-skill](https://github.com/Leonxlnx/taste-skill) (one skill,
`design-taste-frontend`: frontend design that does not look templated) and
[ponytail-skills](https://github.com/DietrichGebert/ponytail) (one skill,
`/ponytail-audit`: what to delete or replace with the standard library,
repository-wide). Listed but not installed:
[last30days](https://github.com/mvanhorn/last30days-skill) (what people said
about a topic in the last 30 days; about 90k tokens per call, and a
`SessionStart` hook), `ponytail`, the full plugin with hooks, and
[Impeccable](https://github.com/pbakaus/impeccable), whose installer writes
hooks, agents and skills into the repository. The first two install from
plinth's marketplace: `claude plugin install last30days@plinth`,
`claude plugin install ponytail@plinth`. Run `/plinth:arsenal` for the
catalog; licenses are in [NOTICE](NOTICE).

Nothing in the plugin enforces anything. Enforcement is the ruleset on GitHub,
which `/plinth:new-project` raises and which owners cannot bypass; anyone
holding administration can still edit it
([About who can change the wall](docs/explanation/concepts.md#about-who-can-change-the-wall)).
When `gh` holds a fine-grained token, the generator stops and names two
fixes. The browser login is shorter, but its token is scoped `repo` across the
account rather than to selected repositories; the admin-token path keeps the
fine-grained token's narrow reach. The first is
`gh auth login -s repo,workflow,delete_repo`, which runs inside Claude Code
(a one-time code and a URL, finished in a browser), after which the generator
runs wherever it is started. Unset `GH_TOKEN` and `GITHUB_TOKEN` first if
either is set: `gh` uses them before any login it stores. Remove them from the
shell startup file they come from, and the login and the generator stay inside
Claude Code. The second is to rerun it through `scripts/with-admin-token.sh` in
a separate terminal, which prompts for an admin token there and keeps it off
every command line; the stop prints a link to a fine-grained token form with
the permissions filled in.

## Status

The install works end to end and CI proves it on a clean runner. `new-project`
creates a repository with the wall up. When a step that setup cannot go on
without fails after the create, it deletes the repository if its token can,
and otherwise prints the repository to delete; a step it can go on without,
such as a label, is named and left. If the create's own answer is lost, it
does neither, so check whether the repository exists (its failure paths run in CI against a mocked
`gh`). It renders
[plinth-template v1.10.0](https://github.com/coolbress/plinth-template/releases/tag/v1.10.0),
whose CI reports every check the wall requires. Since the release gate (#62),
each release is tagged only after `e2e`, run on its release commit, has
created a repository on real GitHub, merged its first pull request and deleted
it. When CodeQL has not analysed the first push after a while, the door
pushes one empty commit to start it (#117). The owner ran three tasks on a generated
repository with 0.5.28: a first feature, a recovery from a failure, and a
resume in a new session. The install, the login and a merge were run again
with 0.5.29. Both runs are in #65. No one but the author has used plinth yet
(#163). What each required check asserts, what a red means and its fix,
CodeQL on a head Dependabot pushed included (#179), is in
[Required checks](docs/reference/required-checks.md). `floor-check` runs the checker `ci / floor-check` runs, read-only;
exit 0 means no FAIL in what it could read, and its summary counts what it
could not. A third-party review check (`third-party / review`, Codex) is
available as an optional check; see
[docs/how-to/configure-the-third-party-reviewer.md](docs/how-to/configure-the-third-party-reviewer.md).
The [CHANGELOG](CHANGELOG.md) lists what each version adds.

## Further reading

- [Concepts](docs/explanation/concepts.md): why plinth is shaped the way it is.
- How-to, for users: [run a project](docs/how-to/run-a-project.md), what to
  type at each stage and what to check before you merge.
- How-to, for maintainers: [cut a release](docs/how-to/cut-a-release.md),
  [upgrade the template pin](docs/how-to/upgrade-the-template-pin.md).
- [CONTEXT.md](CONTEXT.md): the vocabulary (wall, door, box, floor, arsenal, lab, profile).
- [plinth-lab](https://github.com/coolbress/plinth-lab): the evidence behind the rules. Optional.

Rebuilt in September 2026 from an earlier internal repository; its issues and
decisions moved here (the map is #15, the spec #31).
