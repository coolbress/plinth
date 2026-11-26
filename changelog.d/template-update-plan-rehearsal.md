### Changed

- `/plinth:template-update`'s plan shows what the update will do before the
  yes (#1184). On GitHub it runs the `copier update` line on a copy of the
  default branch outside the repository, removed when done, and lists the
  files that merge cleanly, the files that merge into the repository's own
  changes (compared with copier's render of the recorded answers at the
  recorded tag), and each file left in conflict with the lines the
  repository added there. The lists come from what copier left, not its exit
  code, which is 0 with conflicts left. It also prints the template
  CHANGELOG's section headings between the two tags, quoting a section's
  `### Files and questions` block where it has one (the compare link when
  the CHANGELOG is not read), and how to undo the update: before it merges,
  close the pull request and delete its branch and worktree; after, revert
  it in a pull request of its own. The draft pull request's description
  carries the same undo commands. copier failing on the copy stops the plan,
  with nothing written. The plan takes longer by the time of two copier
  runs (the update and the old render). The archetype move's plan and the
  GitLab path are unchanged: they take bug fixes only until a real project
  uses them. MINOR: no check, job, workflow input or secret changes.
