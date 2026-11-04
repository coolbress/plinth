# Terms a first project meets

GitHub's screens are in English. An agent that explains in another language
says what a term means in that language and keeps the English term in brackets
after any translation, the same word every time, so the explanation matches
the button or the page: "합치기(merge)", never a new rendering per session.
The first time a session uses one of these terms with a person, it adds the
plain explanation once; after that the term alone is enough.

The entries are English. The agent renders each explanation in the person's
language and leaves the term itself as it is.

| Term | Plain explanation |
| --- | --- |
| **repository** | The project's folder on GitHub: every file, and the full history of every change to them. |
| **issue** | A numbered note on the repository that says one thing to do or fix, and later what came of it. |
| **pull request** | A proposed change, shown as a page: what changes, why, and whether the checks pass, before it joins `main`. On GitLab it is called a merge request. |
| **branch** | A separate line of work beside `main`, so a change can be made and tried without touching what already works. |
| **commit** | One saved step in the history: a set of file changes with a short message saying what and why. |
| **check** | One automated test GitHub runs on a pull request; it shows green when it passes and red when it fails. |
| **CI** | Continuous integration: the service that runs the checks on every change, on GitHub's machines, not on yours. |
| **merge** | Joining a pull request's change into `main`, so it becomes part of the project. |
| **ruleset** | The repository's rules on GitHub that refuse a merge into `main` until the required checks are green. |
| **draft** | A pull request marked as not finished yet: it can be read and checked, but it is not offered for merge. |
| **review** | Someone, a person or an automated reviewer, reading a pull request's change and saying what is wrong or unclear before it is merged. |
| **template update** | Bringing the files the project started with up to a newer version of the template, through a pull request like any other change. |

Words with a plinth-specific meaning (wall, floor, door) are in
[GLOSSARY.md](../../GLOSSARY.md).
