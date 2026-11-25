### Changed

- `/plinth:template-update` serves GitLab, where it used to stop and point at
  the manual steps (#924). The plan, `--apply` and `--finish` run copier as on
  GitHub; what differs is what reads and writes the host: `glab api`, asked
  of the host and project origin's URL names, verifies the base, and the
  update ends in a draft merge request (a `Draft:` title), not a draft pull
  request. An archetype move (`--archetype <a>`) works there too: in place of
  required checks, its plan names the jobs of `.gitlab-ci.yml` that start
  and stop, whether "Pipelines must succeed" is on (skipped pipelines not
  counted) and whether the default branch is protected, as
  `/plinth:floor-check` reads them, and for one that is not, the `glab api`
  command a Maintainer runs. Nothing changes the project's settings. On
  GitLab the size of the update is not counted before it is pushed, so no
  split is proposed; the pipeline's `diff-size` job counts it. The script
  still stops on a GitLab checkout whose origin URL names no project, and a
  move to or from `web` is still refused on both hosts. `/plinth:floor-check`'s
  plugin-update steps on GitLab now end at `/plinth:template-update`, as on
  GitHub (#1012).
