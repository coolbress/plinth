### Added

- `/plinth:new-project` reads the folder it starts in before any question (`scripts/new-project.sh --where`, local files only). In a folder that already holds code, a repository or a plinth project, it asks one question first, whose recommended choice changes nothing there: start a new separate project, check the repository with `/plinth:floor-check`, take the next step with `/plinth:guide`, or put the code on GitHub or GitLab first. Each hand-off is a command printed for you to type (#1121).
