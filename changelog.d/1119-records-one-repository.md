### Changed

- [`/plinth:records-check`](https://github.com/coolbress/plinth/blob/main/skills/records-check/SKILL.md)
  reads one repository per run, as `/plinth:floor-check` does: every `gh`
  call goes through one function, which allows the audited repository and
  its owner's `.github` and stops the run on any other. A reference to
  another repository's issue (`owner/repo#N`) is no longer requested: each
  such repository is one `SKIP` line with its count, so a reference written
  into a record cannot aim a read elsewhere (#1119).
