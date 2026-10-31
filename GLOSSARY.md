# Glossary

One meaning per term, in code, docs and issues.

- **wall**: what the host enforces on `main` before a merge. On GitHub, the
  required status checks and branch rules a repository's ruleset enforces; on
  GitLab.com Free, a lower one: the protected `main`, "Pipelines must succeed"
  over the pipeline as a whole with no checks by name, and squash with
  fast-forward ([about GitLab](docs/explanation/concepts.md#about-gitlab)). An
  automated check, not a review: green means the asserted properties hold.
  Raised on the host, not in the plugin, so an agent cannot turn it off from
  inside Claude Code; an agent whose login can administer the repository (a
  Maintainer or Owner on GitLab) can still edit it, as anyone with that
  access can. The checks, and what each asserts:
  [docs/reference/required-checks.md](docs/reference/required-checks.md).
- **host**: the service that holds the repository and enforces the wall
  outside the agent, by refusing a merge while a required check is red:
  GitHub.com, or GitLab.com (#353), where Free refuses a merge while the
  pipeline as a whole is red, with no required checks by name. plinth
  configures the host; the host refuses the merge.
- **door**: `/plinth:new-project`. Creates a repository, renders the box, raises
  the wall, opens the first pull request. If a step it cannot go on without
  fails after the create, it deletes the repository when its token can and
  names it when it cannot; a step it can go on without, such as a label, is
  named and left.
- **box**: the project template (`plinth-template`, rendered with copier). The
  files a new repository starts with. The door renders it at the tag pinned in
  `scripts/new-project.sh`.
- **floor**: the minimum a repository must have to be considered set up: the
  wall, secret scanning, dependency updates, the document set. `/plinth:floor-check`
  reads an existing repository against it and changes nothing.
- **arsenal**: the tools plinth installs by default plus the ones it lists for
  manual install. A listed tool can be outside the plugin system (a test
  library, a scanner); listing one installs nothing. `/plinth:arsenal` is the
  catalog. Nothing in it is enforced.
- **verdict**: what plinth says about one property: pass, fail, or not yet
  confirmed. The floor checker's SKIP is a not yet confirmed; its WARN is a
  pass that names something to look at.
- **reach**: what an agent session may touch, and the most it can destroy or
  spend. One of the five things a project settles once. The wall gates a
  merge, not an agent's actions: `ci / floor-check` reads only its edge, the
  deny list in the agent settings, and no check reads what a session can
  touch in production, what it may spend, or whether a restore was tried.
- **evidence condition**: one of four conditions under which a green check is
  evidence of the property it asserts: the CI definition is unchanged; the
  check configuration, the workflow inputs and the tests are the agreed
  standard; the checks ran on this commit; the check looks at the property.
- **enforcement condition**: the one condition under which a red check can
  stop a merge: the ruleset is unchanged. "Unchanged", for both kinds, means
  a change is visible and was reviewed. All five:
  [docs/explanation/concepts.md](docs/explanation/concepts.md#about-what-green-means).
- **harness**: two meanings, kept apart. The **agent harness** is the
  program that turns a model into an agent, as the
  [AI Coding Dictionary](https://github.com/mattpocock/dictionary-of-ai-coding)
  uses the word: Claude Code is one, and plinth is not. A **harness
  template** is a ready-made set of guides (rules files, `AGENTS.md`,
  skills) that steer the agent before it acts and sensors (tests, linters,
  type checks, review) that check its work after, for one kind of project
  ([Böckeler, "Harness engineering for coding agent users", martinfowler.com, 2026-04-02](https://martinfowler.com/articles/harness-engineering.html)).
  plinth is a harness template for a repository, and its sensors are
  required by the host, not by the agent. "The harness" alone means the agent
  harness.
- **profile**: an opt-in plugin that adds hooks on top of the default install
  (`plinth-hooks`, not part of this version). plinth itself has no hooks, and
  neither does any plugin in the default set.

Terms not defined here (agent, session, context window, automated check,
automated review, human review, skill) follow the
[AI Coding Dictionary](https://github.com/mattpocock/dictionary-of-ai-coding).
