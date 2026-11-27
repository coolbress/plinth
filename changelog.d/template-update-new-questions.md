### Changed

- `/plinth:template-update` asks each question the template added that the
  project never answered, by name, before the yes (#1185). Until now
  `copier update --defaults` gave such a question its default unasked: a
  project rendered before plinth-template v1.51.0 recorded
  `records_language: English` whatever language its person works in. On
  GitHub the plan's run on a copy shows which questions copier recorded an
  answer for that `.copier-answers.yml` had none for (so a question whose
  `when:` is false for the project is not listed), and prints each with its
  default and its help from the target tag's `copier.yml`. A question with no
  default stops the plan, naming it, since copier's `--defaults` would
  record null. The skill asks the listed questions one at a time, with the
  default recommended unless the person's context says otherwise.
  `--apply` takes `--answer <name> <value>` for each, passed to copier as
  `--data`, quoted for display by the script's one quoting function so
  Hangul shows as typed; a name the plan does not list exits 2 having
  created nothing. The draft pull request's description records each answer,
  or "default kept". GitHub's plain update only. MINOR: no check, job,
  workflow input or secret changes.
