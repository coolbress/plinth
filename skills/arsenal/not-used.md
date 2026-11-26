# Not used with plinth

An agent can reach each tool below without installing anything, and using it
breaks a plinth rule. Do not run one or suggest it. If the person types one,
it runs on their word.

- `/ship` (built in). Breaks: it commits without asking, finds secrets by file name only, and opens a pull request outside the project's template that it reviews in the same session, where plinth's default review is a fresh-context one.
- `/steward` (built in). Breaks: it pushes fixes for review comments and failing checks with no review first, outside the review rounds of the pull-request rules.

Neither merges. A tool that needs installing is not on this list: plinth
names its own choice for each job and says nothing about the rest. A skill
plinth installs joins the list only when it is found to break a rule.
