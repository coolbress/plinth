# Not used with plinth

An agent can reach each tool below without installing anything, and using it
breaks a plinth rule. Do not run one or suggest it. If the person types one,
it runs on their word.

- `/ship` (built in). Breaks: the pull request it opens takes its title and description from the commit, not the project's template, and it reviews the change in the same session, where plinth's default review is a fresh-context one. Then it runs `/steward`'s watch. Its terms say that on a repository that is not public it first commits every uncommitted change, new files included, and its page says it finds secrets by file name only.
- `/steward` (built in). Breaks: for a failing check or a review comment it pushes a fix with no review first and with git hooks off, outside the review rounds of the pull-request rules. In a trial, run from `/ship`, it made a failing test pass by changing what the test expects, and its commit carried an AI `Co-Authored-By` instead of `Assisted-by`.

Neither merges. A tool that needs installing is not on this list: plinth
names its own choice for each job and says nothing about the rest. A skill
plinth installs joins the list only when it is found to break a rule.
