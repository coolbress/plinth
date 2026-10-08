# Required checks

## Ruleset rules

| Rule | Enforces on the default branch |
| --- | --- |
| `deletion` | The branch cannot be deleted |
| `non_fast_forward` | No force push |
| `pull_request` | Changes land through a pull request; squash is the only merge method; no approval is required; a new push dismisses an earlier approval |
| `required_status_checks` | Every check below reports a pass on the pull request's head, and the branch is up to date with the base (`strict`) |
| `code_scanning` | CodeQL has analysed the head and found no alert at `error` or at security severity `high` or above |
| Bypass list | Empty: the rules apply to owners too, `gh pr merge --admin` included |

## Required by `ruleset.json`

| Check | Asserts | A red means | The fix |
| --- | --- | --- | --- |
| `ci / pr-title` | The pull request title is Conventional Commits, `type: summary` or `type(scope): summary`, `!` before the colon for a breaking change; the type is one of the eleven standard types; the title does not end in `(#N)`, which the squash merge would repeat after adding its own number | The title does not match, or ends in `(#N)`; the job summary names the types and a table of common substitutes, or where the issue number goes instead | Edit the title. Where `ci.yml` lists the `edited` event, as plinth's own does, the check runs again on the edit; otherwise push a commit |
| `ci / lint` | `uv sync --locked` succeeds, `ruff check` and `ruff format --check` pass, and zizmor finds nothing at medium or above in `.github/workflows/` | The lockfile is missing or disagrees with `pyproject.toml`, ruff found a problem or an unformatted file, or zizmor found a workflow weakness | `uv lock`, `uv run ruff check --fix .`, `uv run ruff format .`; for zizmor, the rule it names in the log |
| `ci / typecheck` | `uv run mypy .` passes | A type error; the log names file and line | Fix the type at that line |
| `ci / test` | `uv run pytest` passes on `.python-version`, and on each version in the `extra-python-versions` input | A failing test, or one that fails only on an extra version (the log's `python <version>` line says which) | `uv run pytest`; for an extra version, `uv run --isolated --python <version> --with pytest pytest -q` |
| `ci / build` | `uv build` makes a wheel and an sdist, each installs into a clean venv, and every package under `src/` imports | Packaging is broken: a wrong project name, missing package data or metadata, or an import that fails outside the checkout | Run `uv build` and install the file from `dist/` into a new venv |
| `ci / secrets` | gitleaks finds no secret in the repository's history, deleted files included | A commit on the branch carries a key, token or private key; it is already on GitHub | Revoke the secret where it was issued, then remove it from the branch's history |
| `ci / deps` | The pull request adds no dependency version with a known vulnerability at `deps-fail-on-severity` (default `high`) or above; not a pull request: a pass. On a private repository without GitHub Code Security, GitHub refuses the review (a bare 403); where the dependency graph still accepts an SBOM report request, the job then passes with a warning that nothing was checked, and where it does not (a disabled graph answers the same 403) the review runs and fails, and Dependabot alerts report a vulnerable dependency after the merge (#395) | A dependency the pull request adds or raises has such an advisory; the log names it | Move to a patched version, or drop the dependency |
| `ci / diff-size` | Added plus removed lines, docs and lockfiles excluded, are at most `max-diff-lines` (default 400); not a pull request: a pass | The change is too large to review in one pull request; the job summary gives the count | Split it into a stack of pull requests, each against the one below. A deleted test, a kept Python test file that lost lines, an added skip or suppression marker (`skip`, `skipif`, `xfail`, `pytest.skip(`, `# noqa`, `# type: ignore`, `# pragma: no cover`) in a Python file, an edited workflow or check configuration the description does not name is a WARN in the log and the job summary, never a red: name the path in the description, then push. It does not see an assertion weakened with no line removed, and does not judge whether a listed change lowers the standard |
| `ci / floor-check` | The repository still has the floor `/plinth:floor-check` reads: the document set, agent settings, the project files its archetype needs, a ruleset and CodeQL setup that still require these checks (on a private repository the CodeQL rule is expected only where GitHub Code Security is enabled, and this job, which does not read that, says in an INFO that `/plinth:floor-check`, run with a login that administers the repository, judges a missing rule), and a `ci` job on the default branch that calls plinth's `python-ci.yml` at a full commit SHA (for plinth itself, its own `./.github/workflows/plinth-ci.yml`). Here that item reads the pull request's own `ci.yml`: a pull request that keeps the call but weakens it fails, one that repairs it can merge, and one that removes the call removes this check too, which only a run from outside the pull request sees, after the merge | At least one FAIL line in the job summary | Run `/plinth:floor-check`: each FAIL comes with one fix |

## What a job's summary says

| Form | Means |
| --- | --- |
| `pass: <standard>` | It applies here, ran, and held |
| `pass: <standard>, does not apply (<why>)` | It does not apply to this run |
| `fail: <standard>` | It applies here, ran, and did not hold |
| `not yet confirmed: <standard>, <why>; <what confirms it and when>` | It applies here but did not run or could not be read, including a step stopped by an earlier failed step in the job. Evidence about this commit that is missing: the same text is also a `::warning::` annotation, listed on the run's page and counted beside the workflow in the pull request's Checks tab, not shown in its merge box or Files changed. A step annotates at most nine lines, then one more saying how many are in the job summary: GitHub drops a step's annotations past ten with no notice. A line ending `; left to /plinth:floor-check` is a repository setting the Actions token never reads, the same in every run: it is in the summary and counted on the checker's summary line, not annotated |
| No line | The job was cancelled or timed out, or stopped before its checking step (checkout, a tool install, `ci / floor-check`'s fetch of the checker): the red or cancelled conclusion is the verdict |

| Check | Opens its summary with | Not yet confirmed on a run that otherwise passes | Passes with `does not apply` |
| --- | --- | --- | --- |
| `ci / pr-title` | The title's line | Never | Not a pull request |
| `ci / lint` | `uv sync --locked`, `ruff check`, `ruff format --check`, zizmor | zizmor's online audits, always today: the job gives zizmor no GitHub token, so it runs offline. A run with a token by hand confirms them | Never |
| `ci / typecheck` | `uv sync --locked`, mypy | Never | Never |
| `ci / test` | `uv sync --locked`, pytest on `.python-version`, pytest on the extra versions | Never | The extra versions, when `extra-python-versions` is empty |
| `ci / build` | `uv sync --locked`, `uv build`, the install smoke | Never | Never |
| `ci / secrets` | gitleaks | Never | Never |
| `ci / deps` | The dependency review's line, after the review action's own summary on a pull request: a job's summary is its steps' summaries in step order | A private repository without GitHub Code Security, where GitHub refuses the review (#395); Dependabot alerts report a vulnerable dependency after the merge. A head Dependabot pushed: CodeQL does not analyse it, and `main` is analysed after the merge (#179) | Not a pull request |
| `ci / diff-size` | The count against `max-diff-lines` | Never | Not a pull request. `max-diff-lines: 0` passes as measured and not enforced, with the count |
| `ci / floor-check` | A pass line, or one fail line per FAIL, then the checker's report | Each SKIP line, annotated. Each read the Actions token cannot make and `/plinth:floor-check` with a login that administers the repository does, ending `; left to /plinth:floor-check` and not annotated: push protection, the ruleset's bypass actors, the CodeQL default setup languages, the squash commit settings, and a private repository's missing CodeQL rule | Never |

## Required for a service archetype

| Check | Asserts | A red means | The fix |
| --- | --- | --- | --- |
| `image` | The container image builds, runs, and its first log line carries `"message": "started"`; required for `backend` and `data-ml` | The image does not build, does not start, or does not log that it started | `docker build -t app . && docker run --rm app` locally |

## Code scanning rule

| Check | Asserts | A red means | The fix |
| --- | --- | --- | --- |
| `CodeQL` | CodeQL analysed the head with no alert at the thresholds above. On a private repository the rule is there only where GitHub Code Security is enabled ([about private repositories](../explanation/concepts.md#about-private-repositories)) | An alert, or no analysis: default setup is off, or the first push of a new repository was not analysed | Fix the alert the check links to; with no analysis, turn default setup on or push the recovery commit `/plinth:new-project` prints |
| `CodeQL` | On a head Dependabot pushed, nothing: default setup starts no analysis, the check lands `neutral` and the rule passes | Not applicable | `ci / deps` and the tests still run on that head, and `main` is analysed after the merge |

## Secrets at the push

| Setting | Does | Needs | Where plinth stands |
| --- | --- | --- | --- |
| Push protection | GitHub refuses a push that carries a secret in a format it knows. The person pushing can still let it through, and a secret in a format it does not block by default passes; `ci / secrets` reports those after the push | Free on a public repository; on a private one, GitHub Secret Protection | `/plinth:new-project` turns it on. `/plinth:floor-check` reports it on, off (a WARN with the call that turns it on, never a red), or not verified when the token does not read the repository's security settings or GitHub reports no status. On a private repository where secret scanning is disabled it is an INFO naming the gap, not a WARN. `ci / floor-check` runs on the Actions token, which does not read them, and says so in an INFO: the skill, with a person's login, is the run that reads it. It is a setting, not a required check |
| Ruleset rule "require secret scanning alerts are resolved" | Blocks the merge of a pull request while an alert is open for a secret its commits introduced | GitHub Secret Protection or GitHub Advanced Security, both paid; in [public preview since 2026-09-09](https://github.blog/changelog/2026-09-09-block-pull-requests-with-exposed-secrets-from-merging/) | plinth does not set it and does not read it. With the licence, add it to the ruleset in the repository's settings |

## Optional

| Check | Asserts | A red means | The fix |
| --- | --- | --- | --- |
| `third-party / review` | An accepted reviewer reviewed the pull request's current commit; required only once added to the ruleset, as plinth's own `main` has it | No review arrived on the current commit within the wait | [Configure the third-party reviewer](../how-to/configure-the-third-party-reviewer.md) |
