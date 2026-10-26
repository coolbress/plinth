# How to turn a correction you keep making into a rule

You told the agent the same thing again: "an empty name should not print
`Hello, !`", "use the date format we agreed", "don't leave a `print` in the
code". A correction in the chat ends with the chat. This page is three ways to
make it last, from the weakest and cheapest to the one that actually stops the
mistake. Move to the next step only when the one before did not hold.

| Step | When | Where it goes | Holds | Costs |
| --- | --- | --- | --- | --- |
| 1 | The second time | One line in `AGENTS.md` | Guidance only: the agent reads it every turn and can still miss it | A few minutes; the line is read on every turn |
| 2 | The third time | One rule in the reviewer's instructions | A signal: a reviewer comments when it sees the mistake; nothing is blocked | A reviewer you have turned on; a comment to read on each pull request |
| 3 | When it matters | A test or a lint rule | A boundary: a pull request that brings the mistake back cannot merge | A few lines of code; it runs on every pull request |

Each step is a pull request. Review it like any other: read the line, the rule
or the test, and check that it says what you meant. A wrong rule is worse than
none, because the agent follows it as written.

## 1. The second time: a line in `AGENTS.md`

- **Next:** ask the agent: *"Add one line to the Always list in `AGENTS.md`:
  when a function takes a name, an empty or blank name greets the world, never
  `Hello, !`. Open a pull request with only that change."* Say the rule, not
  the story of how it went wrong.
- **What it holds:** the agent reads `AGENTS.md` at the start of every session
  (`CLAUDE.md` is a link to it), so the rule is in front of it every turn.
- **What it does not hold:** nothing checks that the agent followed it. It may
  still miss the line.
- **Costs:** a few minutes. Everything in the file is read on every turn, which
  is why the file itself says to keep it short and to drop a line that never
  fires.

Two things you may run into:

- **The pull request asks for your approval.** A pull request that changes
  `AGENTS.md` changes the agent's own rules, so `ci / diff-size` puts it to a
  person (once the repository's `ci.yml` calls plinth v2.10.0 or later). If the
  agent pushed it from [its own account](give-the-agent-its-own-account.md),
  the check stays red until you approve the pull request on GitHub: Files
  changed, Review changes, Approve. If it pushed from your account, nothing
  asks; the merge is your decision, as always. On GitLab the job only writes a
  warning in its log when the description does not name the file, and still
  passes.
- **There is no line limit in your repository.** plinth-template has a test
  that keeps the `AGENTS.md` it renders at 60 lines or fewer, but that test
  lives in the template's own repository, outside the folder copied into a new
  project. Your repository does not have it, so an extra line fails nothing.
  A new `cli` project's `AGENTS.md` is already 60 lines (plinth-template
  v1.25.0), so keep each line short and remove one that no longer earns its
  place. When `/plinth:template-update` later brings a template change to the
  same lines, it shows the conflict and asks which side to keep.

## 2. The third time: a rule for the reviewer

This step needs a third-party reviewer that is turned on
([configure the third-party reviewer](configure-the-third-party-reviewer.md)).
Without one, go to step 3.

- **Where:** the file your reviewer reads its rules from. For Codex it is the
  `## Code Review Rules` section at the end of `AGENTS.md`. For another
  reviewer, look in its documentation for "custom instructions" or "review
  guidelines"; if it reads no file from the repository, this step does not
  exist for it.
- **Next:** ask the agent: *"Add one rule to `## Code Review Rules` and change
  nothing else in the pull request."* Write the rule in plain words, as
  something to report, for example:

  ```markdown
  - Report a greeting that can come out as `Hello, !` when the name is empty or only spaces.
  ```

  Do not put the reviewer's name with an `@` in front of it in the rule, or
  in the pull request: the reviewer reads that as a task and answers it. If no
  review has started a while after the pull request is ready, the
  `third-party / review` check asks for one itself, about seven minutes in at
  its default wait.
- **Why on its own:** `third-party / review` fails a pull request that changes
  that section together with any other file, so a change to the reviewer's
  rules always arrives alone and is easy to see. Like step 1, it is a change
  to `AGENTS.md`, so the same approval applies.
- **What it holds:** a reviewer you do not control looks for the mistake on
  every pull request and leaves a comment when it sees it.
- **What it does not hold:** it is a signal, not a block. `third-party / review`
  passes when the reviewer has reviewed, whatever it said; the reviewer can
  miss the mistake; and whether it reads the rules from `main` or from the
  pull request it is reviewing is not known
  ([plinth's issue #652](https://github.com/coolbress/plinth/issues/652)), so
  assume a pull request could weaken the rule for its own review.
- **Costs:** the reviewer's subscription and its review quota, and on every
  pull request a comment to read and to end fixed, answered, or moved to an
  issue.

## 3. When it matters: a test or a lint rule

- **Next:** ask the agent: *"Write a test that fails on this mistake. Show me
  it failing on the code as it is now, then fix the code and show it
  passing."*
- **Look at:** the failing run, before the fix. A test you never saw fail has
  not shown that it can catch anything.

This is a real run, on a `cli` project rendered from plinth-template v1.25.0,
named `tally`, whose `greet()` returned `Hello, !` for an empty name. The test
added to `tests/test_tally.py`:

```python
def test_greet_without_a_name_greets_the_world() -> None:
    # Corrected three times: an empty or blank name printed "Hello, !".
    assert greet("") == "Hello, world!"
    assert greet("   ") == "Hello, world!"
```

On the code as it was, `uv run pytest` failed:

```text
E         - Hello, world!
E         ?        -----
E         + Hello, !
FAILED tests/test_tally.py::test_greet_without_a_name_greets_the_world - Asse...
1 failed, 1 passed
```

The fix was one line in `src/tally/__init__.py`:

```python
    return f"Hello, {name.strip() or 'world'}!"
```

and after it all seven tests passed, with `ruff` and `mypy` clean.

A mistake that is a pattern in the code rather than a wrong answer is a lint
rule instead. For a `print` left in the code, add `"T20"` to the `select` list
under `[tool.ruff.lint]` in `pyproject.toml`: in the same project, `uv run
ruff check .` then failed with `T201` on a `print` and passed once it was
removed.

- **What it holds:** `ci / test` runs the tests and `ci / lint` runs ruff, and
  the ruleset requires both, so a pull request that brings the mistake back
  cannot merge. On GitLab the pipeline as a whole has to pass, so a merge
  request that removes the job itself still merges.
- **What it does not hold:** only the case the test checks. The same mistake in
  another form, or in another function, passes. A later pull request can
  change the test; one that deletes a test file or removes lines from one is
  listed by `ci / diff-size`, and one the agent's own account pushed waits for
  your approval.
- **Costs:** a few lines to read in the pull request, a few seconds on every
  run, and an update to the test when you change the behaviour on purpose.
  Adding a test file, or lines to one, asks for no approval. A lint rule is a
  change to a `[tool.*]` table in `pyproject.toml`, which `ci / diff-size`
  lists, so it takes the same approval as step 1.
