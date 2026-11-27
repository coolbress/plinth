### Changed

- The eval suite's floor-check grade holds the short report's shape (#1105,
  third part). Besides naming every planted gap, a run fails when its final
  report does not open with the verdict (a preamble is not one), has more than five action rows
  (numbered, or bullets) or one about what could not be read, names a check id, asks anything
  outside the rows but one last question offering the pull request, changes a file, or runs a
  `gh api` call that writes (a method other than GET, or a field or an input
  with none). Each rule is recorded in the grade and counted in the summary
  row; the words are read in English and Korean.
- `/plinth:floor-check`'s description names what it checks (the protection
  rules, the base files and the agent's safety), the one pull request it
  offers (made after the check), and that it changes nothing in the
  repository and keeps one note on this machine.
