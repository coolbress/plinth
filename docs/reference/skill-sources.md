# Where shipped skills' rules came from

A shipped skill carries no issue numbers: on a user's machine they mean
nothing, and `tests/skill-size.sh` fails on one. The record behind a rule
goes here instead, for maintainers. Open the record before changing the rule.

## template-update

| Rule in the skill | Record |
| --- | --- |
| Never move the `ci` job's pin for the person; it is their own pull request, before the update runs again. | #793 |
| At the target tag, when the owner's `.github` no longer shares the forms the repository recorded, the plan gives a line that re-renders the same tag. | #770 |
| The command carries whether the owner's `.github` publishes a pull-request template and issue forms; an unread answer stops the plan. | #726 |
| A workflow whose plinth pin is neither the recorded one nor the one the line carries is left in conflict (measured with copier 9.18.2). | #1015 |
| A plinth `uses:` line with a trailing version comment conflicts though both sides name the same pin. | #1045 |
| An approval does not lift the diff-size limit: `--over-limit` stays red until split. | #795 |
| A move writes each admin command to a file and prints a `bash <that file>` line. | #1045 |
| `release.yml` is rewritten whole by a move between a PyPI archetype and an image one, 560 to 576 lines (measured on plinth-template v1.50.1 and v1.50.2). | #1044 |
