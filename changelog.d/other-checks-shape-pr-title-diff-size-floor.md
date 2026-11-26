### Changed

- A failing `ci / pr-title`, `ci / diff-size` or `ci / floor-check` now ends
  its log with `failed:`, `next:` and `more:`, and says it in one annotation
  titled with the check's name, as the other checks do (#1100); `more:`
  opens the check's section of `docs/reference/required-checks.md` at the
  plinth commit the project calls. One cause gives one annotation:
  `closing-references.sh` and `conflict-markers.py` no longer print their
  own beside it in these steps (`MESSAGE_FILE`; `ci / docs` keeps them), and
  when `ci / diff-size` cannot compute the diff, the steps after the
  measure step say so in the summary only, so a head that was not fetched
  gives one annotation where it gave three. Over the limit, the next step
  says to split the change and not to shorten docs, docstrings or tests to
  fit, and the comment above the job states what its sources measured
  (#1144). These checks' `not yet confirmed:` lines, the PR description's
  fields included (on GitLab too), say one fact per sentence; the floor
  checker's own lines keep their form. No job, step id, check name, input
  or secret is renamed.
