### Changed

- An incident in plinth yields a check or nothing: rule text goes into
  `AGENTS.md` or a skill only when no check can hold it, and the pull request
  says why ([CONTRIBUTING.md](https://github.com/coolbress/plinth/blob/main/CONTRIBUTING.md#after-something-goes-wrong)).
  `tests/skill-size.sh` now also holds `AGENTS.md` to 110 lines and 7,500
  bytes, with every cap in `tests/size_caps.py`, which `ci / diff-size` lists
  as a change to the checks when a cap moves (#1138).
