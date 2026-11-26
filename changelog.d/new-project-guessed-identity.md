### Fixed

- `/plinth:new-project` no longer accepts a git identity that git made up from your login and the computer's name: with no `user.name` and `user.email` set (or the `GIT_AUTHOR_*` and `GIT_COMMITTER_*` pairs), the readiness checklist lists it with the two `git config --global` lines before anything is created, on GitHub and GitLab.com, so the first commit of a public repository cannot carry the computer's name (#1153).
