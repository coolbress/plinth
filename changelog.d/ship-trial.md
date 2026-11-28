### Changed

- `skills/arsenal/not-used.md`: the `/ship` and `/steward` entries now say
  what a trial on a rendered `web` project measured (#1085). `/ship` opened
  its pull request with the commit's text instead of the project's template,
  and reviewed it in the same session. On a public
  repository it committed nothing and asked for a commit on a branch first.
  Its watch, which is `/steward`'s, met a failing test by changing what the
  test expects, and pushed that with no review and an AI `Co-Authored-By`
  line instead of `Assisted-by`. Both stay on the list.
