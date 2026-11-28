### Added

- [`/plinth:floor-check`](https://github.com/coolbress/plinth/blob/main/skills/floor-check/reference.md#the-adoption-record)
  reads `.plinth-adoption.yml`, a repository's adoption record, on every
  machine and in `ci / floor-check`. A finding the record keeps prints as
  "kept by choice" and is not counted. Some findings cannot be kept: the
  wall's rules, push protection, a tracked dotenv file and the like. A record
  that keeps one of them gets a FAIL saying why. Until `wall_due` (at most 30
  days after `started`), a default branch with no rules at all prints as
  "the wall: later" instead of a FAIL. A record that cannot be read or is
  not valid is a FAIL naming it. With no record nothing changes, and the
  golden test holds that byte for byte. The short report says the kept items
  in one line. Nothing writes the file yet: the adopt pull request will
  (#1112).
