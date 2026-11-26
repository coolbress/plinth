### Changed

- `ci / pr-title` on a pull request a bot wrote (GitHub's `user.type` Bot,
  Dependabot's included) says in one `pass:` line that the person-only
  fields, `Review:` and `What I checked myself`, do not apply, instead of
  two `not yet confirmed` lines that showed on every such pull request and
  never cleared (#1141). The closing-keyword comparison and the bare `#N`
  check still run on a bot's description.
- On a push, `ci / pr-title` prints one line, that there is no title or
  description to read, and no longer fetches plinth's description check,
  which nothing on a push reads: a 503 from raw.githubusercontent.com had
  turned the job red on a push to `main`, and left a curl error in the log
  when a retry got through. No check name, job, step id, input or secret
  changes.
