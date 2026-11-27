### Changed

- `/plinth:guide` says when a look back is due (#1145). A new `look back:`
  line gives the last issue titled `Look back …` (or none yet), the `feat:`
  merges by a person since, a tag since, and 30 days. A look back is due at
  whichever comes first since the last one, or since the first merge: a
  version tag pushed, 10 `feat:` merges, or 30 days with a merge; never with
  nothing merged. 10 and 30 are starting values. When nothing else is open,
  the next step is `/plinth:floor-check`, with a note that gives the
  `Look back YYYY-MM-DD` issue's seven questions (the restore tried and the
  bills, with `/usage` and the month's Actions usage, among them), `/insights`
  and at most three tickets; otherwise it is one sentence after what is open.
  The search rides on the guide's history read, so one run makes no more
  GitHub calls than before. Step 9 of `docs/how-to/run-a-project.md` and the
  arsenal no longer say "every week or two".
