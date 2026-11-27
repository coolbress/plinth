### Added

- [GitLab pipeline](https://github.com/coolbress/plinth/blob/main/docs/reference/gitlab-ci.md): a failed job's log
  ends with `failed:`, `next:` and `more:`, as the GitHub checks' do, with the
  link at the plinth commit the project's include line pins (`main`, saying
  so, when it cannot be read). A failed tool download says to re-run the
  pipeline, and a working-directory that is not there names the input.
  `test` uploads a JUnit report, so GitLab Free shows failing tests in the
  merge request's Test summary (#1101).
