### Added

- The arsenal's first-merge row names Claude Code's built-in
  `/run-skill-generator`, once, after the token: it writes the project a skill
  of its own that teaches `/run` to build, launch and drive the app.
  `docs/how-to/run-a-project.md` step 1 says the same in one line (#1084). In
  a trial on a `web` and a `cli` project it left the template's `verify` skill
  unchanged and `/verify` still ran it; `/run` then used the new skill. The
  `web` project's generated driver printed its throwaway password, which the
  required CodeQL check blocked, so its skill goes in through a pull request
  like any change.
