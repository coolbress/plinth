### Added

- [Add a second person](https://github.com/coolbress/plinth/blob/main/docs/how-to/add-a-second-person.md):
  where the repository lives (the merge ruleset lets only the admin merge, and
  a collaborator on a personal account cannot be one), CODEOWNERS naming only the
  people, the two-person rules, a token for each person, and the way back while
  one of you is away (#1150).
- `scripts/add-ruleset-rule.sh` has a `two-people` preset: one approval, code
  owners' review and conversation resolution on, and every other field of the
  ruleset as it was. `one-person` puts the three back. `--dry-run` prints them
  before and after (#1150).
- `/plinth:guide` says once, in one line, that a second person is here: someone
  besides the owner and the login it runs under who can be assigned issues or
  opened a pull request. The line names the page and stops once a CODEOWNERS
  file is there. Its end row opens the issue form "End or hand over this
  project", and a handover goes through the second-person page first (#1150).
- `/plinth:floor-check` warns (FC-E31, never a FAIL) when two or more people can
  merge and no approval is required, or when one approval is required and only
  one person can merge (#1150).
