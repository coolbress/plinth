### Added

- `tests/guidance-agree.sh` (#1146) fails when the agent and the person are
  told different next steps for the same situation: which tool now, a merge
  that broke `main`, a failing check, implementing a ticket, coming back and a
  look back. It reads the template's `AGENTS.md` at the pin, the arsenal's
  row, `docs/how-to/run-a-project.md` and what `scripts/guide-state.sh` prints
  on a fixture of each state, and compares the command or page named, not the
  words. Three disagreements known today are listed with the tickets that
  remove them (coolbress/plinth-template#372, #1259); once
  `/plinth:records-check` is retired, no shipped page may name it.
