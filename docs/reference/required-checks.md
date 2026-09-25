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
| `ci / pr-title` | The pull request title is Conventional Commits, `type(scope): summary` or `type(scope)!: summary`, with one of the eleven standard types | The title does not match; the job summary names the types and a table of common substitutes | Edit the title, then push a commit: the check runs on a push, not on an edit |
| `ci / lint` | `uv sync --locked` succeeds, `ruff check` and `ruff format --check` pass, and zizmor finds nothing at medium or above in `.github/workflows/` | The lockfile is missing or disagrees with `pyproject.toml`, ruff found a problem or an unformatted file, or zizmor found a workflow weakness | `uv lock`, `uv run ruff check --fix .`, `uv run ruff format .`; for zizmor, the rule it names in the log |
| `ci / typecheck` | `uv run mypy .` passes | A type error; the log names file and line | Fix the type at that line |
| `ci / test` | `uv run pytest` passes on `.python-version`, and on each version in the `extra-python-versions` input | A failing test, or one that fails only on an extra version (the log's `python <version>` line says which) | `uv run pytest`; for an extra version, `uv run --isolated --python <version> --with pytest pytest -q` |
| `ci / build` | `uv build` makes a wheel and an sdist, each installs into a clean venv, and every package under `src/` imports | Packaging is broken: a wrong project name, missing package data or metadata, or an import that fails outside the checkout | Run `uv build` and install the file from `dist/` into a new venv |
| `ci / secrets` | gitleaks finds no secret in the repository's history, deleted files included | A commit on the branch carries a key, token or private key; it is already on GitHub | Revoke the secret where it was issued, then remove it from the branch's history |
| `ci / deps` | The pull request adds no dependency version with a known vulnerability at `deps-fail-on-severity` (default `high`) or above; not a pull request: a pass | A dependency the pull request adds or raises has such an advisory; the log names it | Move to a patched version, or drop the dependency |
| `ci / diff-size` | Added plus removed lines, docs and lockfiles excluded, are at most `max-diff-lines` (default 400); not a pull request: a pass | The change is too large to review in one pull request; the job summary gives the count | Split it into a stack of pull requests, each against the one below |
| `ci / floor-check` | The repository still has the floor `/plinth:floor-check` reads: the document set, agent settings, the project files its archetype needs, and a ruleset and CodeQL setup that still require these checks | At least one FAIL line in the job summary | Run `/plinth:floor-check`: each FAIL comes with one fix |

## Required for a service archetype

| Check | Asserts | A red means | The fix |
| --- | --- | --- | --- |
| `image` | The container image builds, runs, and its first log line carries `"message": "started"`; required for `backend` and `data-ml` | The image does not build, does not start, or does not log that it started | `docker build -t app . && docker run --rm app` locally |

## Code scanning rule

| Check | Asserts | A red means | The fix |
| --- | --- | --- | --- |
| `CodeQL` | CodeQL analysed the head with no alert at the thresholds above | An alert, or no analysis: default setup is off, or the first push of a new repository was not analysed | Fix the alert the check links to; with no analysis, turn default setup on or push the recovery commit `/plinth:new-project` prints |
| `CodeQL` | On a head Dependabot pushed, nothing: default setup starts no analysis, the check lands `neutral` and the rule passes | Not applicable | `ci / deps` and the tests still run on that head, and `main` is analysed after the merge |

## Optional

| Check | Asserts | A red means | The fix |
| --- | --- | --- | --- |
| `third-party / review` | An accepted reviewer reviewed the pull request's current commit; required only once added to the ruleset | No review arrived on the current commit within the wait | [Configure the third-party reviewer](../how-to/configure-the-third-party-reviewer.md) |
